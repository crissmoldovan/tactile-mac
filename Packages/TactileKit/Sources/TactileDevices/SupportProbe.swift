// The touchscreen check's hands on a device: it lists the devices the check can check, takes one
// exactly as the touchscreen source takes a touchscreen, records what every call returned, hands
// over the raw reports, and lets the device go as the source does. The IOKit calls are behind
// `HIDSystem`, so every rule here is tested against a fake.

import Foundation
import IOKit
import os
import TactileReading

/// What one take of a device did, call by call, as the check reports it.
public struct SupportSwitches: Equatable, Sendable {
    /// How one interface was opened: exclusively, or shared when that failed, as a take opens it.
    public struct Open: Equatable, Sendable {
        public enum Held: String, Sendable { case exclusively, shared, notOpened = "not opened" }

        public var interface: UInt64
        public var role: SupportInterface.Role
        /// The exclusive open's IOReturn.
        public var exclusiveResult: Int32
        /// The shared open's, when the exclusive one failed and it was tried.
        public var sharedResult: Int32?

        public init(interface: UInt64, role: SupportInterface.Role, exclusiveResult: Int32, sharedResult: Int32?) {
            self.interface = interface
            self.role = role
            self.exclusiveResult = exclusiveResult
            self.sharedResult = sharedResult
        }

        public var held: Held {
            if exclusiveResult == kIOReturnSuccess { return .exclusively }
            return sharedResult == kIOReturnSuccess ? .shared : .notOpened
        }
    }

    /// One feature report read, as a take reads it: what was asked, what came back, and how long it took.
    public struct FeatureRead: Equatable, Sendable {
        public var reportID: Int
        /// What the report declares that makes it worth reading: "Contact Count Maximum",
        /// "certification blob".
        public var contents: [String]
        public var lengthAsked: Int
        public var lengthReturned: Int
        public var result: Int32
        public var seconds: TimeInterval
        /// What came back, the report ID byte first when the interface uses IDs.
        public var bytes: [UInt8]
        /// IOKit's timeout code, or a read that took the source's time limit or longer
        /// (`HIDTouchscreenSource.featureReadTimedOut`): the reads end with it.
        public var timedOut: Bool

        public init(reportID: Int, contents: [String], lengthAsked: Int, lengthReturned: Int, result: Int32,
                    seconds: TimeInterval, bytes: [UInt8], timedOut: Bool = false) {
            self.reportID = reportID
            self.contents = contents
            self.lengthAsked = lengthAsked
            self.lengthReturned = lengthReturned
            self.result = result
            self.seconds = seconds
            self.bytes = bytes
            self.timedOut = timedOut
        }
    }

    /// One write of Input Mode: 2 multi-touch, 0 mouse emulation.
    public struct ModeWrite: Equatable, Sendable {
        public var value: Int
        public var result: Int32

        public init(value: Int, result: Int32) {
            self.value = value
            self.result = result
        }
    }

    public var opens: [Open] = []
    public var reads: [FeatureRead] = []
    /// Whether the touch interface has Input Mode, as a take asks it (while it is open); nil when it
    /// wasn't asked: the interface couldn't be opened, or the device is mouse-only.
    public var hasInputMode: Bool?
    /// The write of 2, where it has the setting.
    public var inputModeWrite: ModeWrite?
    /// A read timed out, so the rest weren't read, as the source does.
    public var readsStoppedAfterTimeout = false

    public init() {}

    /// "0xe00002e2", as IOKit's headers write codes.
    public static func ioReturnText(_ code: Int32) -> String { IOResult.text(code) }
}

/// One raw input report, as it arrived on an interface of the device taken.
public struct SupportRawReport: Equatable, Sendable {
    public var interface: UInt64
    public var role: SupportInterface.Role
    /// The report, starting with the report ID byte when the interface uses IDs.
    public var bytes: [UInt8]
    /// On the host's clock, in seconds.
    public var time: TimeInterval

    public init(interface: UInt64, role: SupportInterface.Role, bytes: [UInt8], time: TimeInterval) {
        self.interface = interface
        self.role = role
        self.bytes = bytes
        self.time = time
    }
}

/// The devices the touchscreen check can check, and one of them taken at a time.
///
/// - **Listing** reads what the HID system describes and opens nothing (`SupportDevices`).
/// - **Taking** a touchscreen or a digitiser with a touch interface does exactly what
///   `HIDTouchscreenSource` does when it takes a touchscreen, in the same order: its touch
///   interface, then its mouse sibling, each opened exclusively or else shared; the touch
///   interface's feature reports that declare Contact Count Maximum or the certification blob read
///   once each, in descriptor order, ending at a read that times out; whether it has Input Mode
///   asked; 2 written where it has it; then both listened to. Each IOReturn, and the bytes each read
///   returned, are recorded. Nothing else is read or written, and nothing on any other interface, a
///   vendor interface included.
/// - **The reads run off the main thread** (`HIDSystem.readFeatureReportInBackground`), so a panel
///   slow to answer never freezes the window. After each one the take goes on only if it is still
///   the one under way: a release or a stop asked for meanwhile is carried out then (what is open
///   closed, then the matching stopped), and nothing more is done. No device is ever closed under a
///   read still in flight.
/// - **A device with no touch interface** (mouse-only, or a digitiser Tactile can't tell about) has
///   its listened interfaces opened (exclusively, or shared) and listened to. Nothing is read from
///   it and nothing written.
/// - **Releasing** does what the source does: reports stop; 0 is written if this take wrote a 2;
///   every interface is closed.
/// - **Unplugging.** When the touch interface goes (or, with none, the last listened interface),
///   the device has gone: everything still open is closed and nothing is written. When another of
///   its interfaces goes, the take ends as a release does, 0 written to the touch interface if this
///   take wrote a 2, best effort. Either way `onGone` is called with what was written.
/// - Every step is written in the log book (`DeviceLogBook`), keyed by `SupportDevice.logKey`.
///
/// The touchscreen source must have let the device go first (the model releases a touchscreen while
/// it is checked): a device Tactile holds exclusively can't be opened again.
@MainActor
public final class SupportProbe {
    /// Called after each change to `devices` once `start()` has returned.
    public var onDevicesChanged: (@MainActor () -> Void)?

    private let system: HIDSystem
    private let log = Logger(subsystem: "com.crissmoldovan.tactile", category: "support")
    /// Where the report reads what the check did.
    private let logBook: DeviceLogBook
    private var isStarted = false
    /// While `start()` lists what is connected now: nobody is told until it returns.
    private var isStarting = false
    private var interfaces: [HIDInterfaceID: KnownInterface] = [:]
    private var arrivals = 0
    private var taken: Taken?
    /// `stop()` came while a read was under way: it is finished when the read returns, so no device
    /// is closed, nor the matching stopped, under a request still in flight.
    private var stopAfterRead = false

    /// The device taken now.
    private final class Taken {
        let device: SupportDevice
        let onReport: @MainActor (SupportRawReport) -> Void
        let onGone: @MainActor (SupportSwitches.ModeWrite?) -> Void
        /// The interfaces open now, in the order they were opened, and whether each is held exclusively.
        var open: [(id: HIDInterfaceID, exclusive: Bool)] = []
        /// 2 was written to the touch interface, so releasing writes 0.
        var wroteInputMode = false
        /// A read is under way off the main thread.
        var isReading = false
        /// A release was asked for while a read was under way: the take does it when the read returns.
        var releaseAfterRead = false

        init(device: SupportDevice, onReport: @escaping @MainActor (SupportRawReport) -> Void,
             onGone: @escaping @MainActor (SupportSwitches.ModeWrite?) -> Void) {
            self.device = device
            self.onReport = onReport
            self.onGone = onGone
        }
    }

    /// The live probe: IOKit's HID manager, watching digitisers, pointers and mice, writing to the
    /// app's log book.
    public convenience init() {
        self.init(system: IOKitHIDSystem(matching: .supportCheck), logBook: .shared)
    }

    /// `logBook` nil: one of its own, as the tests have.
    init(system: HIDSystem, logBook: DeviceLogBook? = nil) {
        self.system = system
        self.logBook = logBook ?? DeviceLogBook()
    }

    /// Every device the check can check, connected now, in the order they arrived.
    public var devices: [SupportDevice] {
        SupportDevices.group(Array(interfaces.values))
    }

    /// Starts listing. Every device connected now is listed before it returns.
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        isStarting = true
        system.startMatching(
            matched: { [weak self] in self?.matched($0) },
            removed: { [weak self] in self?.removed($0) })
        isStarting = false
    }

    /// Lets go of the device taken, if any, stops listing, and forgets every device. During a read it
    /// returns at once, and all of it is done when the read returns (within the HID request timeout,
    /// about 5 s): nothing blocks meanwhile.
    public func stop() {
        guard isStarted else { return }
        if let taken, taken.isReading {
            taken.releaseAfterRead = true
            stopAfterRead = true
            return
        }
        release()
        finishStopping()
    }

    private func finishStopping() {
        stopAfterRead = false
        isStarted = false
        interfaces = [:]
        system.stopMatching()
    }

    // MARK: - Taking

    /// Takes `device` as the touchscreen source takes a touchscreen (see the type's description),
    /// and hands each raw report to `onReport` until it is released. Returns what each call gave; nil
    /// when the device is no longer connected, or when it was released, unplugged or stopped before
    /// the take was over. A device taken before is let go first.
    public func take(_ device: SupportDevice, onReport: @escaping @MainActor (SupportRawReport) -> Void,
                     onGone: @escaping @MainActor (SupportSwitches.ModeWrite?) -> Void) async -> SupportSwitches? {
        guard isStarted else { return nil }
        release()
        let connected = device.interfaces.filter { interfaces[$0.id] != nil }
        guard !connected.isEmpty, connected.count == device.interfaces.count else {
            log.notice("Support check of \(device.usbID, privacy: .public): it is no longer connected")
            note(device, "it is no longer connected")
            return nil
        }
        let taken = Taken(device: device, onReport: onReport, onGone: onGone)
        self.taken = taken
        var switches = SupportSwitches()
        log.info("Support check of \(device.usbID, privacy: .public) (\(device.kind.rawValue, privacy: .public)): taking it as Tactile takes a touchscreen")
        note(device, "taking it (\(device.kind.rawValue)) as Tactile takes a touchscreen")

        guard let touch = device.touchInterface else {
            // A mouse-only device's pointers, or a digitiser's interfaces when none is known to take
            // touches: opened, never read or written.
            for interface in device.listenedOnly { switches.opens.append(open(interface, of: taken)) }
            listen(device.listenedOnly, of: taken)
            return switches
        }

        let touchOpen = open(touch, of: taken)
        switches.opens.append(touchOpen)
        let mouse = device.interfaces.first { $0.role == .mouse }
        if let mouse { switches.opens.append(open(mouse, of: taken)) }
        if touchOpen.held != .notOpened {
            // GET, then SET, as the source does (as Linux does).
            for report in interfaces[touch.id]?.decoder?.featureReportsToRead ?? [] {
                taken.isReading = true
                let read = await system.readFeatureReportInBackground(touch.id, reportID: report.reportID, length: report.length)
                taken.isReading = false
                guard stillTaking(taken) else { return nil }
                let recorded = SupportSwitches.FeatureRead(
                    reportID: report.reportID, contents: report.contents.map(\.description), lengthAsked: report.length,
                    lengthReturned: read.length, result: read.result, seconds: read.seconds, bytes: read.bytes,
                    timedOut: HIDTouchscreenSource.featureReadTimedOut(read))
                switches.reads.append(recorded)
                let line = "read feature report \(String(format: "0x%02X", report.reportID)): \(report.length) bytes asked, "
                    + "\(read.length) returned in \(String(format: "%.3f", read.seconds)) s (IOReturn \(IOResult.text(read.result)))"
                log.info("Support check of \(device.usbID, privacy: .public): \(line, privacy: .public)")
                note(device, line)
                if recorded.timedOut {
                    switches.readsStoppedAfterTimeout = true
                    note(device, "the read timed out, so no more are read")
                    break
                }
            }
            let hasInputMode = system.hasInputMode(touch.id)
            switches.hasInputMode = hasInputMode
            if hasInputMode {
                taken.wroteInputMode = true
                let result = system.writeInputMode(touch.id, 2)
                switches.inputModeWrite = SupportSwitches.ModeWrite(value: 2, result: result)
                log.info("Support check of \(device.usbID, privacy: .public): Input Mode 2 (multi-touch), IOReturn \(IOResult.text(result), privacy: .public)")
                note(device, "Input Mode 2 (multi-touch) written (IOReturn \(IOResult.text(result)))")
            } else {
                note(device, "it has no Input Mode setting; nothing written")
            }
        }
        // Listened to as the source listens: the touch interface, then its mouse.
        listen([touch] + (mouse.map { [$0] } ?? []), of: taken)
        return switches
    }

    /// After a read: whether the take goes on. A release asked for meanwhile is done now, and one
    /// that went (unplugged, or the probe stopped) has nothing left to do.
    private func stillTaking(_ taken: Taken) -> Bool {
        if taken.releaseAfterRead {
            // Asked to let go, or one interface went, while the read was under way. Nothing has been
            // written yet: the reads come before the write.
            if self.taken === taken { self.taken = nil }
            _ = close(taken, writingBack: true)
            if stopAfterRead { finishStopping() }
            return false
        }
        return isStarted && self.taken === taken
    }

    /// Lets the device taken go, as the source releases a touchscreen. Returns the write of 0, when
    /// this take wrote a 2 and the touch interface is still open; nil otherwise. Asked during a read,
    /// it is done when the read returns, before anything else is written.
    @discardableResult
    public func release() -> SupportSwitches.ModeWrite? {
        guard let taken else { return nil }
        if taken.isReading {
            taken.releaseAfterRead = true
            return nil
        }
        self.taken = nil
        return close(taken, writingBack: true)
    }

    /// Stops reports, writes 0 to the touch interface after a 2 when `writingBack` and it is still
    /// connected and open, and closes everything.
    private func close(_ taken: Taken, writingBack: Bool) -> SupportSwitches.ModeWrite? {
        for open in taken.open { system.stopReports(open.id) }
        var writeBack: SupportSwitches.ModeWrite?
        if writingBack, taken.wroteInputMode, let touch = taken.device.touchInterface, interfaces[touch.id] != nil,
           taken.open.contains(where: { $0.id == touch.id }) {
            let result = system.writeInputMode(touch.id, 0)
            writeBack = SupportSwitches.ModeWrite(value: 0, result: result)
            log.info("Support check of \(taken.device.usbID, privacy: .public): Input Mode 0 (mouse emulation) written back, IOReturn \(IOResult.text(result), privacy: .public)")
            note(taken.device, "Input Mode 0 (mouse emulation) written back (IOReturn \(IOResult.text(result)))")
        }
        for open in taken.open { system.close(open.id, exclusive: open.exclusive) }
        taken.open = []
        log.info("Support check of \(taken.device.usbID, privacy: .public): let go")
        note(taken.device, "let go")
        return writeBack
    }

    /// Opens one interface as a take does: exclusively, or shared if that fails.
    private func open(_ interface: SupportInterface, of taken: Taken) -> SupportSwitches.Open {
        let exclusive = system.open(interface.id, exclusive: true)
        if exclusive == kIOReturnSuccess {
            taken.open.append((interface.id, true))
            note(taken.device, "holding its \(interface.role.rawValue) interface exclusively")
            return SupportSwitches.Open(interface: interface.id, role: interface.role, exclusiveResult: exclusive, sharedResult: nil)
        }
        let shared = system.open(interface.id, exclusive: false)
        if shared == kIOReturnSuccess { taken.open.append((interface.id, false)) }
        let line = "its \(interface.role.rawValue) interface can't be held exclusively (IOReturn \(IOResult.text(exclusive))); "
            + "shared: IOReturn \(IOResult.text(shared))"
        log.notice("Support check of \(taken.device.usbID, privacy: .public): \(line, privacy: .public)")
        note(taken.device, line)
        return SupportSwitches.Open(interface: interface.id, role: interface.role, exclusiveResult: exclusive, sharedResult: shared)
    }

    private func listen(_ listened: [SupportInterface], of taken: Taken) {
        for interface in listened where taken.open.contains(where: { $0.id == interface.id }) {
            let id = interface.id
            let role = interface.role
            let size = interfaces[id]?.reportBufferSize ?? InterfaceChoice.reportBufferSize(decoder: nil, maxInputReportSize: nil)
            system.startReports(id, bufferSize: size) { [weak self, weak taken] bytes, time in
                guard let self, let taken, self.taken === taken, taken.open.contains(where: { $0.id == id }) else { return }
                taken.onReport(SupportRawReport(interface: id, role: role, bytes: bytes, time: time))
            }
        }
    }

    /// Writes a line about `device` in the log book, as "Support check: …".
    private func note(_ device: SupportDevice, _ text: String) {
        guard let key = device.logKey else { return }
        logBook.note(key, category: "support", "Support check: \(text)")
    }

    // MARK: - Interfaces coming and going

    private func matched(_ description: HIDInterfaceDescription) {
        guard isStarted, interfaces[description.id] == nil else { return }
        interfaces[description.id] = KnownInterface(description, arrival: arrivals)
        arrivals += 1
        if !isStarting { onDevicesChanged?() }
    }

    private func removed(_ id: HIDInterfaceID) {
        guard isStarted, interfaces.removeValue(forKey: id) != nil else { return }
        if let taken, taken.device.interfaces.contains(where: { $0.id == id }) {
            self.taken = nil
            let device = taken.device
            let hasGone = device.touchInterface.map { $0.id == id }
                ?? !device.listenedOnly.contains { interfaces[$0.id] != nil }
            let writeBack: SupportSwitches.ModeWrite?
            if hasGone {
                // Unplugged. Nothing is written to a device that has gone.
                for open in taken.open {
                    system.stopReports(open.id)
                    system.close(open.id, exclusive: open.exclusive)
                }
                taken.open = []
                writeBack = nil
                log.info("Support check of \(device.usbID, privacy: .public): it was unplugged")
                note(device, "it was unplugged")
            } else {
                // One interface went and the rest stays: let it go as a release does, best effort.
                log.info("Support check of \(device.usbID, privacy: .public): one of its interfaces went; letting the rest go")
                note(device, "its \(device.interfaces.first { $0.id == id }?.role.rawValue ?? "other") interface went; letting the rest go")
                writeBack = taken.isReading ? nil : close(taken, writingBack: true)
                if taken.isReading { taken.releaseAfterRead = true }
            }
            taken.onGone(writeBack)
        }
        onDevicesChanged?()
    }
}
