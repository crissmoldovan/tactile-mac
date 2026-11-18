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
/// - **Taking** a touchscreen or a digitiser does exactly what `HIDTouchscreenSource` does when it
///   takes a touchscreen, in the same order: its touch interface, then its mouse sibling, each opened
///   exclusively or else shared; the touch interface's feature reports that declare Contact Count
///   Maximum or the certification blob read once each, in descriptor order, ending at a read that
///   times out; whether it has Input Mode asked; 2 written where it has it; then both listened to.
///   Each IOReturn, and the bytes each read returned, are recorded. Nothing else is read or written,
///   and nothing on any other interface, a vendor interface included.
/// - **A mouse-only device** has its pointers opened (exclusively, or shared) and listened to.
///   Nothing is read from it and nothing written.
/// - **Releasing** does what the source does: reports stop; 0 is written if this take wrote a 2;
///   every interface is closed.
/// - **Unplugging** any interface of the taken device ends the take: everything still open is
///   closed, nothing is written to a device that has gone, and `onGone` is called.
///
/// The touchscreen source must have let the device go first (the model releases a touchscreen while
/// it is checked): a device Tactile holds exclusively can't be opened again.
@MainActor
public final class SupportProbe {
    /// Called after each change to `devices` once `start()` has returned.
    public var onDevicesChanged: (@MainActor () -> Void)?

    private let system: HIDSystem
    private let log = Logger(subsystem: "com.crissmoldovan.tactile", category: "support")
    private var isStarted = false
    /// While `start()` lists what is connected now: nobody is told until it returns.
    private var isStarting = false
    private var interfaces: [HIDInterfaceID: KnownInterface] = [:]
    private var arrivals = 0
    private var taken: Taken?

    /// The device taken now.
    private final class Taken {
        let device: SupportDevice
        let onReport: @MainActor (SupportRawReport) -> Void
        let onGone: @MainActor () -> Void
        /// The interfaces open now, in the order they were opened, and whether each is held exclusively.
        var open: [(id: HIDInterfaceID, exclusive: Bool)] = []
        /// 2 was written to the touch interface, so releasing writes 0.
        var wroteInputMode = false

        init(device: SupportDevice, onReport: @escaping @MainActor (SupportRawReport) -> Void,
             onGone: @escaping @MainActor () -> Void) {
            self.device = device
            self.onReport = onReport
            self.onGone = onGone
        }
    }

    /// The live probe: IOKit's HID manager, watching digitisers, pointers and mice.
    public convenience init() {
        self.init(system: IOKitHIDSystem(matching: .supportCheck))
    }

    init(system: HIDSystem) {
        self.system = system
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

    /// Lets go of the device taken, if any, stops listing, and forgets every device.
    public func stop() {
        guard isStarted else { return }
        release()
        isStarted = false
        interfaces = [:]
        system.stopMatching()
    }

    // MARK: - Taking

    /// Takes `device` as the touchscreen source takes a touchscreen (see the type's description),
    /// and hands each raw report to `onReport` until it is released. Returns what each call gave;
    /// nil when the device is no longer connected. A device taken before is let go first.
    public func take(_ device: SupportDevice, onReport: @escaping @MainActor (SupportRawReport) -> Void,
                     onGone: @escaping @MainActor () -> Void) -> SupportSwitches? {
        guard isStarted else { return nil }
        release()
        let connected = device.interfaces.filter { interfaces[$0.id] != nil }
        guard !connected.isEmpty, connected.count == device.interfaces.count else {
            log.notice("Support check of \(device.usbID, privacy: .public): it is no longer connected")
            return nil
        }
        let taken = Taken(device: device, onReport: onReport, onGone: onGone)
        self.taken = taken
        var switches = SupportSwitches()
        log.info("Support check of \(device.usbID, privacy: .public) (\(device.kind.rawValue, privacy: .public)): taking it as Tactile takes a touchscreen")

        if device.touchInterface == nil {
            // A mouse-only device's pointers, or a digitiser's interfaces when none is known to take
            // touches: opened, never read or written.
            for interface in device.listenedOnly {
                switches.opens.append(open(interface, of: taken))
            }
        } else if let touch = device.touchInterface {
            let touchOpen = open(touch, of: taken)
            switches.opens.append(touchOpen)
            if let mouse = device.interfaces.first(where: { $0.role == .mouse }) {
                switches.opens.append(open(mouse, of: taken))
            }
            if touchOpen.held != .notOpened {
                // GET, then SET, as the source does (as Linux does).
                for report in interfaces[touch.id]?.decoder?.featureReportsToRead ?? [] {
                    let read = system.readFeatureReport(touch.id, reportID: report.reportID, length: report.length)
                    let recorded = SupportSwitches.FeatureRead(
                        reportID: report.reportID, contents: report.contents.map(\.description), lengthAsked: report.length,
                        lengthReturned: read.length, result: read.result, seconds: read.seconds, bytes: read.bytes,
                        timedOut: HIDTouchscreenSource.featureReadTimedOut(read))
                    switches.reads.append(recorded)
                    log.info("""
                        Support check of \(device.usbID, privacy: .public): read feature report \
                        \(String(format: "0x%02X", report.reportID), privacy: .public): \(report.length, privacy: .public) bytes asked, \
                        \(read.length, privacy: .public) returned (IOReturn \(IOResult.text(read.result), privacy: .public))
                        """)
                    if recorded.timedOut {
                        switches.readsStoppedAfterTimeout = true
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
                }
            }
        }
        // Listened to as the source listens: the touch interface, then its mouse; or the pointers.
        let listened = device.touchInterface == nil
            ? device.listenedOnly
            : [device.touchInterface, device.interfaces.first { $0.role == .mouse }].compactMap { $0 }
        for interface in listened where taken.open.contains(where: { $0.id == interface.id }) {
            listen(to: interface, of: taken)
        }
        return switches
    }

    /// Lets the device taken go, as the source releases a touchscreen. Returns the write of 0, when
    /// this take wrote a 2 and the touch interface is still open; nil otherwise.
    @discardableResult
    public func release() -> SupportSwitches.ModeWrite? {
        guard let taken else { return nil }
        self.taken = nil
        for open in taken.open { system.stopReports(open.id) }
        var writeBack: SupportSwitches.ModeWrite?
        if taken.wroteInputMode, let touch = taken.device.touchInterface, taken.open.contains(where: { $0.id == touch.id }) {
            let result = system.writeInputMode(touch.id, 0)
            writeBack = SupportSwitches.ModeWrite(value: 0, result: result)
            log.info("Support check of \(taken.device.usbID, privacy: .public): Input Mode 0 (mouse emulation) written back, IOReturn \(IOResult.text(result), privacy: .public)")
        }
        for open in taken.open { system.close(open.id, exclusive: open.exclusive) }
        log.info("Support check of \(taken.device.usbID, privacy: .public): let go")
        return writeBack
    }

    /// Opens one interface as a take does: exclusively, or shared if that fails.
    private func open(_ interface: SupportInterface, of taken: Taken) -> SupportSwitches.Open {
        let exclusive = system.open(interface.id, exclusive: true)
        if exclusive == kIOReturnSuccess {
            taken.open.append((interface.id, true))
            return SupportSwitches.Open(interface: interface.id, role: interface.role, exclusiveResult: exclusive, sharedResult: nil)
        }
        let shared = system.open(interface.id, exclusive: false)
        if shared == kIOReturnSuccess { taken.open.append((interface.id, false)) }
        log.notice("""
            Support check of \(taken.device.usbID, privacy: .public): its \(interface.role.rawValue, privacy: .public) interface \
            can't be held exclusively (IOReturn \(IOResult.text(exclusive), privacy: .public)); shared: IOReturn \
            \(IOResult.text(shared), privacy: .public)
            """)
        return SupportSwitches.Open(interface: interface.id, role: interface.role, exclusiveResult: exclusive, sharedResult: shared)
    }

    private func listen(to interface: SupportInterface, of taken: Taken) {
        let id = interface.id
        let role = interface.role
        let size = interfaces[id]?.reportBufferSize ?? InterfaceChoice.reportBufferSize(decoder: nil, maxInputReportSize: nil)
        system.startReports(id, bufferSize: size) { [weak self, weak taken] bytes, time in
            guard let self, let taken, self.taken === taken, taken.open.contains(where: { $0.id == id }) else { return }
            taken.onReport(SupportRawReport(interface: id, role: role, bytes: bytes, time: time))
        }
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
            // Unplugged. Nothing is written to a device that has gone.
            self.taken = nil
            for open in taken.open {
                system.stopReports(open.id)
                system.close(open.id, exclusive: open.exclusive)
            }
            log.info("Support check of \(taken.device.usbID, privacy: .public): it was unplugged")
            taken.onGone()
        }
        onDevicesChanged?()
    }
}
