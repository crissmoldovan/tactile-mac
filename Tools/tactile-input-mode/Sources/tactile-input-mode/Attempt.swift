// `describe`, `listen` and `try <method>`: the attempt to make the wch.cn strip send touches.
//
// Without a finger on the glass, a method can only be shown to be accepted, not to work: a run
// prints what was written and what came back, then counts what each interface sends.

import Foundation
import IOKit
import IOKit.hid
import InputModeCore

enum Method: String, CaseIterable {
    case report
    case beforeOpen = "before-open"
    case onPlug = "on-plug"
    case switches
    case single

    var summary: String {
        switch self {
        case .report:
            return "As Linux does at probe: read Contact Count Maximum, then write the whole Device Configuration report (Input Mode 2, Device Index 0) while the interfaces are open to listen."
        case .beforeOpen:
            return "Write the whole Device Configuration report (Input Mode 2, Device Index 0) with nothing listening, close, and only then open the interfaces to listen."
        case .onPlug:
            return "Wait for the strip to be unplugged and plugged back in, and write the whole Device Configuration report the moment its touchscreen interface appears, before anything listens."
        case .switches:
            return "Write Surface Switch and Button Switch on, as Windows and Linux do, if the descriptor declares them."
        case .single:
            return "A diagnostic, not a fix: write Input Mode 1 (single input), to see whether the panel acts on Input Mode at all."
        }
    }
}

struct Options {
    var seconds = 5.0
    var wait = 30.0
    var filter: DeviceFilter?
}

let fingerPrompt = "NOW: two fingers on the strip's glass, moved apart, until it says stop."

// MARK: - Choosing the strip

func refuseIfTactileRuns() -> Bool {
    let running = conflictingProcesses()
    guard !running.isEmpty else { return false }
    say("Tactile or Touch Up is running. Quit it first, then run this again:")
    for line in running { say("  \(line)") }
    return true
}

func chooseStrip(_ options: Options) -> Strip? {
    let strips = findStrips(options.filter)
    if strips.count == 1 { return strips[0] }
    if strips.isEmpty {
        say("No touchscreen with an Input Mode setting is connected\(options.filter == nil ? "" : " that matches \(options.filter!.text)").")
    } else {
        say("More than one touchscreen has an Input Mode setting:")
        for strip in strips { say("  \(strip.label)") }
        say("Name one with --touchscreen <vendor:product>, or <vendor:product:serial> when two share a USB ID.")
        say("If two share the serial too, this tool can't tell them apart: unplug all but one.")
    }
    return nil
}

func printHeader(_ strip: Strip) {
    say("Touchscreen: \(strip.label)")
    for iface in strip.all {
        var line = String(format: "  %@, registry 0x%llx", iface.name, iface.registryID)
        if iface.role == .vendor { line += ": only ever listened to, never written" }
        if iface.role == .mouse { line += ": only ever listened to" }
        say(line)
    }
    say("Input Monitoring for this process: \(inputMonitoringStatus()) (checked without asking)")
}

// MARK: - describe

/// Everything the descriptors say, and which methods apply. Opens nothing, writes nothing.
func runDescribe(_ options: Options) -> Int32 {
    guard let strip = chooseStrip(options) else { return 2 }
    printHeader(strip)
    for iface in strip.all {
        say()
        say("\(iface.name):")
        guard let d = iface.descriptor else {
            say("  descriptor unreadable: \(iface.descriptorProblem ?? "unknown")")
            continue
        }
        say("  collections: \(d.applications.map(\.description).joined(separator: ", "))")
        for kind in HIDReportKind.allCases {
            for id in d.reportIDs(kind) {
                say(String(format: "  %@ report 0x%02X, %d bytes: %@", kind.rawValue, id, d.reportLength(kind, id), contents(d, kind, id)))
            }
        }
    }
    say()
    say("Methods (tactile-input-mode try <method>):")
    let touch = strip.touch.descriptor
    let inputMode = strip.touch.inputModeReport.map { String(format: "0x%02X", $0) } ?? "none"
    for method in Method.allCases {
        let applies: String
        switch method {
        case .switches:
            let ids = touch.map(FeatureWritePlanner.switchReports(in:)) ?? []
            applies = ids.isEmpty ? "does not apply: no Surface Switch or Button Switch is declared"
                                  : "applies: reports \(ids.map { String(format: "0x%02X", $0) }.joined(separator: ", "))"
        case .onPlug:
            applies = "applies (Input Mode is in feature report \(inputMode)); needs the strip unplugged and plugged back in"
        default:
            applies = "applies: Input Mode is in feature report \(inputMode)"
        }
        say("  \(method.rawValue): \(applies)")
        say("      \(method.summary)")
    }
    let blob = touch.map { $0.reports(.feature, containing: Usages.certificationBlob) } ?? []
    say()
    say(blob.isEmpty ? "The certification blob (0xFF00/0xC5) is not declared on the touchscreen interface, so it is not read."
                     : "The certification blob (0xFF00/0xC5) is declared in feature report(s) \(blob).")
    return 0
}

private func contents(_ d: HIDDescriptor, _ kind: HIDReportKind, _ id: UInt8) -> String {
    var order: [HIDUsage] = []
    var counts: [HIDUsage: Int] = [:]
    var padding = 0
    for field in d.fields(kind, id) {
        if field.isConstant { padding += field.bitSize * field.count; continue }
        for element in 0..<field.count {
            let usage = field.usage(at: element) ?? HIDUsage(0, 0)
            if counts[usage] == nil { order.append(usage) }
            counts[usage, default: 0] += 1
        }
    }
    var parts = order.map { counts[$0]! > 1 ? "\($0) ×\(counts[$0]!)" : "\($0)" }
    if padding > 0 { parts.append("\(padding) bits of padding") }
    return parts.joined(separator: ", ")
}

// MARK: - listen and try

/// Listens without writing anything but the closing Input Mode 0. The baseline.
func runListen(_ options: Options) -> Int32 {
    if refuseIfTactileRuns() { return 3 }
    guard let strip = chooseStrip(options) else { return 2 }
    printHeader(strip)
    let session = begin(strip)
    say()
    say("Listening only: nothing is written before the listen.")
    session.openForInput()
    let summary = session.listen(seconds: options.seconds, prompt: fingerPrompt)
    return finish(session, summary, writesAccepted: true)
}

func runTry(_ method: Method, _ options: Options) -> Int32 {
    if refuseIfTactileRuns() { return 3 }
    if method == .onPlug { return runOnPlug(options) }
    guard let strip = chooseStrip(options) else { return 2 }
    printHeader(strip)
    guard let reportID = strip.touch.inputModeReport else { return 2 }
    say()
    say("Method \(method.rawValue): \(method.summary)")

    if method == .switches {
        let ids = strip.touch.descriptor.map(FeatureWritePlanner.switchReports(in:)) ?? []
        if ids.isEmpty {
            say("The touchscreen interface declares no Surface Switch and no Button Switch, so there is nothing to write.")
            say("Nothing was opened and nothing was written.")
            return 0
        }
    }

    let session = begin(strip)
    var accepted = true
    switch method {
    case .report, .single:
        session.openForInput()
        session.showContactCountMaximum()
        accepted = session.write([.inputMode: method == .single ? 1 : 2], reportID: reportID)
        session.showFeature(reportID)
    case .beforeOpen:
        session.open(strip.touch, exclusive: false, listen: false)
        accepted = session.write([.inputMode: 2], reportID: reportID)
        session.showFeature(reportID)
        session.close(strip.touch)
        session.openForInput()
    case .switches:
        session.openForInput()
        for id in FeatureWritePlanner.switchReports(in: strip.touch.descriptor!) {
            let mode: [DigitizerSetting: Int] = id == reportID ? [.inputMode: 2] : [:]
            accepted = session.write(mode, reportID: id) && accepted
        }
        if !FeatureWritePlanner.switchReports(in: strip.touch.descriptor!).contains(reportID) {
            accepted = session.write([.inputMode: 2], reportID: reportID) && accepted
        }
    case .onPlug:
        break
    }
    let summary = session.listen(seconds: options.seconds, prompt: fingerPrompt)
    return finish(session, summary, writesAccepted: accepted)
}

func begin(_ strip: Strip) -> Session {
    let session = Session(strip: strip)
    Session.current = session
    Safety.install()
    return session
}

/// Restores, then prints the result. A strip that could not be put back is said last, and the
/// exit code is then not 0.
func finish(_ session: Session, _ summary: ListenSummary, writesAccepted: Bool) -> Int32 {
    let putBack = session.restore()
    session.confirmUnchanged()
    say()
    say("Result:")
    for line in summary.lines() { say("  \(line)") }
    if !session.disconnected.isEmpty { say("  During the run: \(session.disconnected.joined(separator: "; ")).") }
    let ending = RunEnding(restored: putBack, writesAccepted: writesAccepted)
    if !ending.lines.isEmpty { say() }
    for line in ending.lines { say(line) }
    return ending.exitCode
}

// MARK: - on-plug

/// Waits for the strip to go and come back, and writes the moment its touchscreen interface appears.
final class PlugWatcher {
    enum Phase { case waitingForRemoval(UInt64), waitingForArrival, arrived, timedOut }

    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let filter: DeviceFilter?
    var phase: Phase
    var known: Set<UInt64>
    var arrivedStrip: Strip?
    var seenAtStart = false
    var writeAccepted = false
    private var removedAt: TimeInterval?

    init(present: Strip?, filter: DeviceFilter?) {
        self.filter = filter
        phase = present.map { .waitingForRemoval($0.touch.registryID) } ?? .waitingForArrival
        known = Set(findStrips(filter).map(\.touch.registryID))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: 0x0D, kIOHIDDeviceUsageKey: 0x04] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<PlugWatcher>.fromOpaque(context).takeUnretainedValue().matched(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<PlugWatcher>.fromOpaque(context).takeUnretainedValue().removed(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    func stop() {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    private func registryID(_ device: IOHIDDevice) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
        return id
    }

    func removed(_ device: IOHIDDevice) {
        guard case .waitingForRemoval(let id) = phase, registryID(device) == id else { return }
        removedAt = ProcessInfo.processInfo.systemUptime
        phase = .waitingForArrival
        say("  unplugged. Now plug it back in.")
    }

    /// A new touchscreen interface that matches the filter is the strip coming back, in either
    /// phase: if its removal was never announced, its return still counts.
    func matched(_ device: IOHIDDevice) {
        let id = registryID(device)
        if known.contains(id) {
            seenAtStart = true   // the watcher's first look at a strip that was already connected
            return
        }
        known.insert(id)
        let wasWaitingForRemoval: Bool
        switch phase {
        case .waitingForRemoval: wasWaitingForRemoval = true
        case .waitingForArrival: wasWaitingForRemoval = false
        case .arrived, .timedOut: return
        }
        let appeared = ProcessInfo.processInfo.systemUptime
        // The descriptor is parsed here, before anything is written.
        let iface = HIDInterface(device)
        guard let reportID = iface.inputModeReport, filter?.matches(iface.identity) ?? true else { return }
        phase = .arrived
        if wasWaitingForRemoval { say("  it came back without its removal being announced; taking it as plugged back in") }
        let strip = Strip(touch: iface, siblings: [])
        let session = begin(strip)
        arrivedStrip = strip
        if let removedAt { say(String(format: "  it came back %.1f s after it was unplugged", appeared - removedAt)) }
        // The interface can take a moment to accept an open after it is announced.
        var opened = kIOReturnError
        for _ in 0..<50 {
            opened = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            if opened == kIOReturnSuccess { break }
            usleep(10_000)
        }
        guard opened == kIOReturnSuccess else {
            say("  could not open the touchscreen interface after it appeared: \(hex(opened)); nothing written")
            return
        }
        iface.openState = .shared
        say(String(format: "  opened %@ shared, to write, not listening: %@, %.0f ms after it appeared",
                   iface.name, hex(opened), (ProcessInfo.processInfo.systemUptime - appeared) * 1000))
        writeAccepted = session.write([.inputMode: 2], reportID: reportID)
        say(String(format: "  the write returned %.0f ms after the touchscreen interface appeared",
                   (ProcessInfo.processInfo.systemUptime - appeared) * 1000))
        session.showFeature(reportID)
        session.close(iface)
    }

    /// Turns the run loop until the phase leaves `waiting` or the time is up.
    func run(for seconds: Double, until done: () -> Bool) -> Bool {
        let start = ProcessInfo.processInfo.systemUptime
        while ProcessInfo.processInfo.systemUptime - start < seconds {
            if done() { return true }
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.02, false)
        }
        return done()
    }
}

func runOnPlug(_ options: Options) -> Int32 {
    let present = findStrips(options.filter)
    if present.count > 1 {
        _ = chooseStrip(options)
        return 2
    }
    // Only this strip's return counts: the same USB ID and serial, unless --touchscreen says otherwise.
    guard let filter = options.filter ?? present.first.map({ DeviceFilter(identity: $0.touch.identity) }) else {
        say("No touchscreen with an Input Mode setting is connected. Name the one to wait for with")
        say("--touchscreen <vendor:product>, so that no other touchscreen plugged in is taken for it.")
        return 2
    }
    say("Method on-plug: \(Method.onPlug.summary)")
    if let strip = present.first { printHeader(strip) }
    say("  waiting for: \(filter.text)")
    let watcher = PlugWatcher(present: present.first, filter: filter)
    defer { watcher.stop() }
    _ = watcher.run(for: 0.3) { watcher.seenAtStart || present.isEmpty }
    if let strip = present.first {
        say(watcher.seenAtStart ? "  watching: the watcher sees the strip, and will notice it go"
                                : "  watching: the watcher has not seen the strip yet")
        say()
        say(String(format: "UNPLUG the strip's touch USB cable now (you have %.0f s).", options.wait))
        if !watcher.run(for: options.wait, until: { if case .waitingForRemoval = watcher.phase { return false }; return true }) {
            say("  It was not unplugged within \(Int(options.wait)) s. Nothing was written.")
            // The rule holds for every run: end by writing mouse emulation and closing.
            let session = begin(strip)
            let putBack = session.restore()
            session.confirmUnchanged()
            let ending = RunEnding(restored: putBack, writesAccepted: false)
            for line in ending.lines { say(line) }
            return ending.exitCode
        }
    } else {
        say(String(format: "The strip is not connected. PLUG it in now (you have %.0f s).", options.wait))
    }
    let back = watcher.run(for: options.wait) {
        if case .arrived = watcher.phase { return true }
        return false
    }
    guard back, let strip = watcher.arrivedStrip, let session = Session.current else {
        say("  It did not come back within \(Int(options.wait)) s. Nothing was written. Plugged in again, it starts in mouse emulation.")
        return 1
    }
    // Let its other interfaces appear, then listen to all of them.
    _ = watcher.run(for: 1.5) { false }
    strip.findSiblings()
    session.rememberInterfaces()
    for iface in strip.siblings { say("  found \(iface.name)") }
    session.openForInput()
    let summary = session.listen(seconds: options.seconds, prompt: fingerPrompt)
    return finish(session, summary, writesAccepted: watcher.writeAccepted)
}
