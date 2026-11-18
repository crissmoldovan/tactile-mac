// One run against one strip: its opens, its writes, listening, and putting everything back.
//
// Every write goes through FeatureWritePlanner, against the touchscreen interface's own descriptor.
// The vendor interface is only ever opened to listen. Whatever happens (the normal end, an error, a
// signal, exit()), the run ends by writing Input Mode 0 (mouse emulation) and closing every open.

import Foundation
import IOKit
import IOKit.hid
import InputModeCore

final class Session {
    /// The session that restore() acts on from signal handlers and atexit.
    static var current: Session?

    let strip: Strip
    private var tallies: [UInt64: InterfaceTally] = [:]
    private var counting = false
    private(set) var disconnected: [String] = []
    private var restoreResult: Bool?
    private var startIDs: [UInt64]

    init(strip: Strip) {
        self.strip = strip
        startIDs = strip.all.map(\.registryID).sorted()
    }

    /// Takes the strip's interfaces as they are now as the ones to compare against at the end.
    func rememberInterfaces() {
        startIDs = strip.all.map(\.registryID).sorted()
    }

    // MARK: Opening and closing

    /// Opens every interface to listen: the touchscreen and mouse interfaces exclusively (so a finger
    /// on the glass doesn't also drive the pointer), any other interface shared.
    func openForInput() {
        for iface in strip.all {
            open(iface, exclusive: iface.role == .touchscreen || iface.role == .mouse, listen: true)
        }
    }

    /// An IOHIDDevice holds one open at a time, so an open interface is closed before it is opened
    /// again (the sequence the survey proved: close the shared open, then open exclusively).
    @discardableResult
    func open(_ iface: HIDInterface, exclusive: Bool, listen: Bool) -> IOReturn {
        if iface.openState != .closed { close(iface, quietly: true) }
        var result = IOHIDDeviceOpen(iface.device, IOOptionBits(exclusive ? kIOHIDOptionsTypeSeizeDevice : kIOHIDOptionsTypeNone))
        var how = exclusive ? "exclusively" : "shared"
        if result == kIOReturnSuccess {
            iface.openState = exclusive ? .exclusive : .shared
        } else if exclusive {
            let failed = result
            result = IOHIDDeviceOpen(iface.device, IOOptionBits(kIOHIDOptionsTypeNone))
            if result == kIOReturnSuccess { iface.openState = .shared }
            how = "shared, because the exclusive open failed (\(hex(failed)))"
        }
        if result == kIOReturnSuccess, listen {
            let context = Unmanaged.passUnretained(iface).toOpaque()
            IOHIDDeviceRegisterInputReportCallback(iface.device, iface.buffer, iface.bufferSize, reportCallback, context)
            IOHIDDeviceRegisterRemovalCallback(iface.device, removalCallback, context)
            if !iface.scheduled {
                IOHIDDeviceScheduleWithRunLoop(iface.device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
                iface.scheduled = true
            }
        }
        let purpose = listen ? "to listen" : "to write, not listening"
        say("  opened \(iface.name) \(how), \(purpose): \(hex(result))")
        return result
    }

    func close(_ iface: HIDInterface, quietly: Bool = false) {
        guard iface.openState != .closed else { return }
        if iface.scheduled {
            IOHIDDeviceUnscheduleFromRunLoop(iface.device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            iface.scheduled = false
        }
        let options = IOOptionBits(iface.openState == .exclusive ? kIOHIDOptionsTypeSeizeDevice : kIOHIDOptionsTypeNone)
        let result = IOHIDDeviceClose(iface.device, options)
        iface.openState = .closed
        if !quietly { say("  closed \(iface.name): \(hex(result))") }
    }

    func closeAll() {
        for iface in strip.all { close(iface) }
    }

    // MARK: Writing and reading feature reports (touchscreen interface only)

    /// Writes digitizer settings as one whole feature report, after the planner has checked it
    /// against the touchscreen interface's descriptor. Prints exactly what was sent and the result.
    @discardableResult
    func write(_ values: [DigitizerSetting: Int], reportID: UInt8) -> Bool {
        writeFeature(values, reportID: reportID, to: strip.touch)
    }

    /// Reads a feature report the touchscreen interface declares, and prints it as it came back.
    func showFeature(_ id: UInt8) {
        let iface = strip.touch
        guard let descriptor = iface.descriptor, descriptor.reportIDs(.feature).contains(id) else {
            say(String(format: "  feature report 0x%02X is not declared: not read", id))
            return
        }
        let size = descriptor.reportLength(.feature, id)
        var buffer = [UInt8](repeating: 0, count: size)
        var length = CFIndex(size)
        let result = IOHIDDeviceGetReport(iface.device, kIOHIDReportTypeFeature, CFIndex(id), &buffer, &length)
        let bytes = Array(buffer.prefix(max(0, min(Int(length), size))))
        var line = String(format: "  read feature report 0x%02X: %@ (%@)", id, hexBytes(bytes), hex(result))
        if result == kIOReturnSuccess, descriptor.usesReportIDs {
            line += bytes.first == id
                ? ": a real answer"
                : String(format: ": it does not start with 0x%02X, so it is not the panel's answer (macOS keeps its own copy)", id)
        }
        say(line)
    }

    /// Reads Contact Count Maximum from whichever feature report declares it, as Linux does at probe.
    func showContactCountMaximum() {
        guard let id = strip.touch.descriptor?.reports(.feature, containing: Usages.contactCountMaximum).first else {
            say("  no Contact Count Maximum is declared: not read")
            return
        }
        showFeature(id)
    }

    // MARK: Listening

    func received(_ report: [UInt8], from iface: HIDInterface) {
        guard counting else { return }
        tallies[iface.registryID]?.add(report)
    }

    func removed(_ iface: HIDInterface) {
        let line = "\(iface.name) disconnected"
        disconnected.append(line)
        iface.openState = .closed
        iface.scheduled = false
        say("  !! \(line)")
    }

    /// Counts what every open interface sends for `seconds`, with the run loop turning.
    func listen(seconds: Double, prompt: String) -> ListenSummary {
        tallies = [:]
        for iface in strip.all where iface.openState != .closed {
            tallies[iface.registryID] = InterfaceTally(role: iface.role, descriptor: iface.descriptor)
        }
        say()
        say(prompt)
        print("  listening:", terminator: "")
        let start = ProcessInfo.processInfo.systemUptime
        var shown = Int(seconds.rounded(.up)) + 1
        counting = true
        while true {
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            if elapsed >= seconds { break }
            let left = Int((seconds - elapsed).rounded(.up))
            if left < shown {
                shown = left
                print(" \(left)", terminator: "")
                fflush(stdout)
            }
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.05, false)
        }
        counting = false
        say(" STOP. Lift your fingers.")
        let ordered = strip.all.compactMap { tallies[$0.registryID] }
        return ListenSummary(tallies: ordered, seconds: seconds)
    }

    // MARK: Putting everything back

    var hasRestored: Bool { restoreResult != nil }

    /// Writes Input Mode 0 (mouse emulation) and closes every open. Runs once, from any way out;
    /// later calls return the first answer. False only when the strip is still attached and
    /// neither the whole-report write nor the element write was accepted.
    @discardableResult
    func restore() -> Bool {
        if let restoreResult { return restoreResult }
        counting = false
        say()
        say("Putting the strip back as it was found (mouse emulation, nothing held):")
        var putBack = true
        if let reportID = strip.touch.inputModeReport {
            if disconnected.contains(where: { $0.hasPrefix(strip.touch.name) }) {
                say("  the touchscreen interface is gone; a panel that is plugged in again starts in mouse emulation")
            } else {
                // Always attempted, even if the registry no longer lists the interface: only a write
                // that fails on a strip that has really gone counts as put back.
                if strip.touch.openState == .closed { open(strip.touch, exclusive: false, listen: false) }
                let whole = write([.inputMode: 0], reportID: reportID)
                var fallback: IOReturn?
                if !whole {
                    say("  the whole-report write failed; writing Input Mode 0 through its element instead:")
                    let result = writeInputModeElement(strip.touch, 0)
                    say("  wrote Input Mode 0 by IOHIDDeviceSetValue: \(hex(result)), \(result == kIOReturnSuccess ? "accepted" : "NOT accepted")")
                    fallback = result
                }
                let attached = whole || fallback == kIOReturnSuccess ? true : isAttached(strip.touch)
                putBack = RunEnding.putBack(wholeReportAccepted: whole, fallbackAccepted: fallback.map { $0 == kIOReturnSuccess },
                                            attachedAfter: attached)
                if !attached { say("  the strip has gone; plugged in again, it starts in mouse emulation") }
            }
        }
        closeAll()
        restoreResult = putBack
        return putBack
    }

    /// The interfaces of this strip's USB device that the registry has now.
    private func interfacesNow() -> [HIDInterface] {
        hidDevices(matching: [kIOHIDVendorIDKey: strip.touch.vendorID, kIOHIDProductIDKey: strip.touch.productID])
            .map(HIDInterface.init)
            .filter { $0.registryID == strip.touch.registryID || $0.identity.isSibling(of: strip.touch.identity) }
    }

    private func isAttached(_ iface: HIDInterface) -> Bool {
        interfacesNow().contains { $0.registryID == iface.registryID }
    }

    /// After restore: is the strip still there as the same interfaces?
    func confirmUnchanged() {
        let ids = interfacesNow().map(\.registryID).sorted()
        if ids == startIDs {
            say("  the strip did not re-enumerate: the same \(ids.count) interfaces, with the same registry IDs")
        } else {
            say("  the strip's interfaces CHANGED: before \(startIDs.map { String(format: "0x%llx", $0) }), now \(ids.map { String(format: "0x%llx", $0) })")
        }
    }
}

/// The one function that sends a feature report. The planner refuses anything but a declared
/// feature report of a touchscreen interface holding only standard digitizer settings.
@discardableResult
func writeFeature(_ values: [DigitizerSetting: Int], reportID: UInt8, to iface: HIDInterface) -> Bool {
    guard let descriptor = iface.descriptor else {
        say("  refused: \(iface.name) has no readable descriptor (\(iface.descriptorProblem ?? "unknown"))")
        return false
    }
    let plan: PlannedFeatureWrite
    do {
        plan = try FeatureWritePlanner.plan(role: iface.role, descriptor: descriptor, reportID: reportID, values: values)
    } catch {
        say("  \(error)")
        return false
    }
    let result = plan.bytes.withUnsafeBufferPointer { buffer in
        IOHIDDeviceSetReport(iface.device, kIOHIDReportTypeFeature, CFIndex(plan.reportID), buffer.baseAddress!, buffer.count)
    }
    let verdict = result == kIOReturnSuccess ? "accepted" : "NOT accepted"
    say("  wrote \(plan.summary) to \(iface.name) with SET_REPORT: \(hex(result)), \(verdict)")
    return result == kIOReturnSuccess
}

/// The older way, through IOKit's Input Mode element. IOKit sends the whole report, filling its
/// other fields from its own copy, so the report is first checked by the planner like any other
/// write: a report that also holds anything but the standard digitizer settings is refused.
/// Used by the `multitouch` and `mouse` commands, and as the fallback when restoring.
func writeInputModeElement(_ iface: HIDInterface, _ mode: Int) -> IOReturn {
    guard iface.role == .touchscreen, let element = inputModeElement(iface.device) else { return kIOReturnUnsupported }
    guard let descriptor = iface.descriptor else {
        say("  refused: \(iface.name) has no readable descriptor (\(iface.descriptorProblem ?? "unknown"))")
        return kIOReturnNotPermitted
    }
    let reportID = UInt8(truncatingIfNeeded: IOHIDElementGetReportID(element))
    do {
        _ = try FeatureWritePlanner.plan(role: iface.role, descriptor: descriptor, reportID: reportID, values: [.inputMode: mode])
    } catch {
        say("  \(error)")
        return kIOReturnNotPermitted
    }
    let value = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, mach_absolute_time(), mode)
    return IOHIDDeviceSetValue(iface.device, element, value)
}

func inputModeElement(_ device: IOHIDDevice) -> IOHIDElement? {
    let matching: [String: Any] = [
        kIOHIDElementUsagePageKey: 0x0D,
        kIOHIDElementUsageKey: 0x52,
        kIOHIDElementTypeKey: kIOHIDElementTypeFeature.rawValue,
    ]
    let elements = IOHIDDeviceCopyMatchingElements(device, matching as CFDictionary, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement]
    return elements?.first
}

private let reportCallback: IOHIDReportCallback = { context, _, _, _, _, report, length in
    guard let context else { return }
    let iface = Unmanaged<HIDInterface>.fromOpaque(context).takeUnretainedValue()
    Session.current?.received(Array(UnsafeBufferPointer(start: report, count: max(0, length))), from: iface)
}

private let removalCallback: IOHIDCallback = { context, _, _ in
    guard let context else { return }
    Session.current?.removed(Unmanaged<HIDInterface>.fromOpaque(context).takeUnretainedValue())
}

/// Restores on SIGINT, SIGTERM, SIGHUP and SIGQUIT (handled on the main run loop) and at exit().
/// A crash or `kill -9` skips all of this: macOS drops the exclusive opens, and a replug puts the
/// strip back in mouse emulation.
enum Safety {
    private static var sources: [DispatchSourceSignal] = []

    static func install() {
        guard sources.isEmpty else { return }
        // Output piped to a process that dies (tee, after Ctrl-C) must not kill this one before it restores.
        signal(SIGPIPE, SIG_IGN)
        // Ctrl-Z would stop the tool with the strip held and Input Mode written.
        signal(SIGTSTP, SIG_IGN)
        for sig in [SIGINT, SIGTERM, SIGHUP, SIGQUIT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                say()
                say("Stopped by signal \(sig).")
                let putBack = Session.current?.restore() ?? true
                for line in RunEnding(restored: putBack, writesAccepted: true).lines { say(line) }
                exit(putBack ? 128 + sig : RunEnding.notPutBackExitCode)
            }
            source.resume()
            sources.append(source)
        }
        atexit {
            // Only when nothing restored earlier, as on an exit() after an error.
            guard let session = Session.current, !session.hasRestored else { return }
            if !session.restore() {
                say(RunEnding.notPutBack)
                _exit(RunEnding.notPutBackExitCode)
            }
        }
    }
}
