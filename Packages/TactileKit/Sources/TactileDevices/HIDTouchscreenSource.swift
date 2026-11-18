// The live USB side: finds touchscreens as they come and go, takes them over and lets them go, and
// turns their raw reports into frames. The IOKit calls are behind `HIDSystem`; every rule here is
// tested against a fake.

import CoreGraphics
import Foundation
import IOKit
import os
import TactileReading
import TactileScreens

/// The touchscreens plugged into this Mac, through IOKit's HID manager.
///
/// - **Finding.** Every HID interface with a Touch Screen collection is a touchscreen interface;
///   its siblings are the interfaces at the same USB location ID with the same vendor and product
///   ID. A touchscreen's mouse interface is the first sibling whose descriptor is a mouse's and
///   which is not also a pen's or a keyboard's. A mouse that is no touchscreen's sibling is never
///   opened. Interfaces arriving together are grouped before the touchscreen is announced; a mouse
///   sibling arriving later is added and announced as a change.
/// - **Connected means released:** nothing is opened beyond reading properties and descriptors.
/// - **Taking:** each interface is opened exclusively (any open of it closed first), or shared if
///   that fails; then the touchscreen interface's feature reports that declare Contact Count
///   Maximum or the certification blob are read, once each, and what they say is dropped (the
///   ILITEK stays a mouse until a host has read its blob; after a read that times out, they
///   aren't read again on this connection); then, if the touchscreen interface has
///   Input Mode, 2 is written; then reports are listened to, and the reader starts afresh. The
///   mode is never read to decide anything.
/// - **Releasing:** reports stop; 0 is written if this taking sent a 2 (whatever the panel
///   answered, since a panel can apply the write and still answer with an error); the interfaces
///   are closed.
/// - **Unplugging:** announced once, when the touchscreen interface goes. Nothing is written to a
///   device that has gone, and no frame is made up: the app cancels the touch.
///
/// For whoever drives it:
/// - Set `delegate` before `start()`: `start()` announces every touchscreen already connected
///   before it returns.
/// - Call `stop()` before dropping the source. A started source dropped without it, on the main
///   thread, releases everything quietly in `deinit` (with the Input Mode write, without telling
///   the delegate); off the main thread it only has the system stop matching, on the main thread.
///   Both are safety nets, not the way to end.
/// - `touchscreenChanged` can arrive inside the caller's own `setState`: every status change is
///   announced before `setState` returns. The delegate may call back into the source from any of
///   its methods, `stop()` included; the frames of a report whose touchscreen was released, or
///   whose source was stopped, meanwhile are dropped.
/// - An origin change is announced before the frames of the report that caused it. On a change
///   from `mouseInterface` to `touchInterface`, if the mouse finger was down, the next frame is
///   empty: it ends that finger.
/// - **The mouse interface going on its own.** When a taken touchscreen whose origin is
///   `mouseInterface` loses its mouse interface while its touchscreen interface stays, exactly one
///   `touchscreenChanged` comes, with `hasMouseInterface == false` and the origin unchanged, and no
///   frame. A finger that was down is not ended by the source: the app cancels the touch on that
///   change.
/// - `facts.locationID == 0` means the touchscreen has no USB location: it has no mouse sibling,
///   and no port to remember it by.
@MainActor
public final class HIDTouchscreenSource: TouchscreenSource {
    public weak var delegate: TouchscreenSourceDelegate?

    private let system: HIDSystem
    private let log = Logger(subsystem: "com.crissmoldovan.tactile", category: "devices")
    /// Where the touchscreen check's report reads what was done with each touchscreen: the same
    /// lines as the log's, keyed by the touchscreen's touch interface, with no serial and no name.
    private let logBook: DeviceLogBook
    private var isStarted = false
    /// Every touchscreen and mouse interface connected now.
    private var interfaces: [HIDInterfaceID: KnownInterface] = [:]
    private var arrivals = 0
    /// In the order they connected.
    private var touchscreens: [Touchscreen] = []
    private var nextHandle: UInt64 = 1
    private var settleIsDue = false
    /// Touchscreen interfaces left alone because their device's touchscreen is read from another.
    private var setAside: Set<HIDInterfaceID> = []

    public convenience init() {
        self.init(system: IOKitHIDSystem(), logBook: .shared)
    }

    /// `logBook` nil: one of its own, as the tests have.
    init(system: HIDSystem, logBook: DeviceLogBook? = nil) {
        self.system = system
        self.logBook = logBook ?? DeviceLogBook()
    }

    /// Writes a line about `touchscreen` in the log book.
    private func note(_ touchscreen: Touchscreen, _ text: String) {
        logBook.note(touchscreen.touch.id, category: "devices", text)
    }

    /// A started source dropped without `stop()` still lets every touchscreen go: what IOKit holds
    /// must not outlive it, and a panel it switched is put back. Off the main thread its own state
    /// can't be touched, so the system is handed to the main thread to stop matching: that closes
    /// what is open and unschedules everything before anything is freed, but writes no Input Mode.
    deinit {
        guard Thread.isMainThread else {
            log.fault("A touchscreen source was dropped off the main thread without stop(); stopping on the main thread")
            let system = self.system
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                MainActor.assumeIsolated { system.stopMatching() }
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
            return
        }
        MainActor.assumeIsolated {
            guard isStarted else { return }
            log.notice("A touchscreen source was dropped without stop(); releasing everything")
            releaseEverything()
        }
    }

    // MARK: - TouchscreenSource

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        log.info("Watching for touchscreens")
        system.startMatching(
            matched: { [weak self] in self?.matched($0) },
            removed: { [weak self] in self?.removed($0) })
        settle()
    }

    public func stop() {
        guard isStarted else { return }
        let all = releaseEverything()
        log.info("Stopped watching for touchscreens")
        for touchscreen in all { delegate?.touchscreenDisconnected(touchscreen.handle) }
    }

    /// Releases every taken touchscreen, stops matching and forgets everything, telling nobody.
    /// Returns the touchscreens that were connected.
    @discardableResult
    private func releaseEverything() -> [Touchscreen] {
        isStarted = false
        let all = touchscreens
        for touchscreen in all where touchscreen.state == .taken { release(touchscreen) }
        touchscreens = []
        interfaces = [:]
        setAside = []
        system.stopMatching()
        return all
    }

    public func setState(_ state: DeviceState, for handle: DeviceHandle) {
        guard isStarted, let touchscreen = touchscreen(handle) else {
            log.notice("\(handle, privacy: .public) is not connected; it can't be \(state.rawValue, privacy: .public)")
            return
        }
        guard touchscreen.state != state else { return }
        switch state {
        case .taken: take(touchscreen)
        case .released: release(touchscreen)
        }
        announceChange(of: touchscreen)
    }

    /// Does what a take does to the panel, in the same order: the feature reads, then the Input
    /// Mode write where there is the setting. The app doesn't call it: it takes every touchscreen
    /// again on wake, and that take reads.
    public func refresh() {
        guard isStarted else { return }
        for touchscreen in touchscreens where touchscreen.state == .taken {
            guard isStarted, self.touchscreen(touchscreen.handle) === touchscreen, touchscreen.state == .taken,
                  touchscreen.open.contains(where: { $0.id == touchscreen.touch.id }) else { continue }
            readFeatureReports(of: touchscreen, during: .refresh)
            guard touchscreen.hasInputMode else { continue }
            let before = touchscreen.connected.status
            touchscreen.connected.status.inputMode = switchToMultiTouch(touchscreen)
            if touchscreen.connected.status != before { announceChange(of: touchscreen) }
        }
    }

    // MARK: - Interfaces coming and going

    private func matched(_ description: HIDInterfaceDescription) {
        guard isStarted, interfaces[description.id] == nil else { return }
        interfaces[description.id] = KnownInterface(description, arrival: arrivals)
        arrivals += 1
        settleSoon()
    }

    /// Groups interfaces once those arriving together have all arrived.
    private func settleSoon() {
        guard !settleIsDue else { return }
        settleIsDue = true
        system.later { [weak self] in
            self?.settleIsDue = false
            self?.settle()
        }
    }

    /// Gives touchscreens without a mouse sibling the one that has arrived, and announces the
    /// touchscreens whose interfaces have arrived.
    private func settle() {
        guard isStarted else { return }
        let free = interfaces.values.filter { owner(of: $0.id) == nil }.sorted { $0.arrival < $1.arrival }
        var claimed: Set<HIDInterfaceID> = []

        for touchscreen in touchscreens where touchscreen.mouse == nil {
            let candidates = free.filter { !claimed.contains($0.id) }
            guard let mouse = InterfaceChoice.mouseSibling(of: touchscreen.touch, among: candidates) else { continue }
            claimed.insert(mouse.id)
            attach(mouse, to: touchscreen)
            guard isStarted else { return }
        }

        for group in InterfaceChoice.groups(free.filter { !claimed.contains($0.id) }) {
            guard let touch = interfaces[group.touch], owner(of: touch.id) == nil else { continue }
            if touch.locationID != 0, touchscreens.contains(where: { $0.touch.locationID == touch.locationID }) { continue }
            connect(touch, mouse: group.mouse.flatMap { interfaces[$0] })
            guard isStarted else { return }
        }

        for interface in interfaces.values where interface.isTouchscreen && owner(of: interface.id) == nil {
            guard setAside.insert(interface.id).inserted else { continue }
            log.notice("""
                Touchscreen interface \(interface.id, privacy: .public) at \(Self.location(interface.locationID), privacy: .public) \
                is left alone: its device is read from another touchscreen interface
                """)
        }
    }

    private func connect(_ touch: KnownInterface, mouse: KnownInterface?) {
        let handle = DeviceHandle(rawValue: nextHandle)
        nextHandle += 1
        let d = touch.description
        let facts = TouchscreenFacts(vendorID: d.vendorID, productID: d.productID, serial: d.serial,
                                     locationID: d.locationID, name: d.product)
        let connected = ConnectedTouchscreen(handle: handle, facts: facts, maxContacts: max(touch.contactSlots, 1),
                                             reportedSizeMM: touch.decoder?.surfaceSizeMM, hasMouseInterface: mouse != nil,
                                             reportsPalms: touch.decoder.map { $0.reportsContactSize || $0.reportsConfidence } ?? false)
        let touchscreen = Touchscreen(connected: connected, touch: touch, mouse: mouse)
        touchscreens.append(touchscreen)
        let size = connected.reportedSizeMM.map { String(format: "%.1f × %.1f mm", $0.width, $0.height) } ?? "no size"
        log.info("""
            Connected \(handle, privacy: .public): \(Self.usbID(facts), privacy: .public) "\(facts.name, privacy: .public)" \
            serial "\(facts.serial, privacy: .public)" at \(Self.location(facts.locationID), privacy: .public); \
            \(connected.maxContacts, privacy: .public) contacts, \(size, privacy: .public), \
            \(mouse == nil ? "no mouse interface" : "a mouse interface", privacy: .public)\
            \(touch.decoder == nil ? "; its report descriptor can't be read" : "", privacy: .public)
            """)
        note(touchscreen, "Connected \(handle): \(Self.usbID(facts)) at \(Self.location(facts.locationID)); \(connected.maxContacts) contacts, "
             + "\(size), \(mouse == nil ? "no mouse interface" : "a mouse interface")"
             + (touch.decoder == nil ? "; its report descriptor can't be read" : ""))
        delegate?.touchscreenConnected(touchscreen.connected)
    }

    private func attach(_ mouse: KnownInterface, to touchscreen: Touchscreen) {
        touchscreen.mouse = mouse
        touchscreen.connected.hasMouseInterface = true
        log.info("\(touchscreen.handle, privacy: .public): its mouse interface arrived")
        note(touchscreen, "\(touchscreen.handle): its mouse interface arrived")
        if touchscreen.state == .taken {
            if openForTaking(mouse, of: touchscreen) {
                listen(to: mouse, of: touchscreen)
                touchscreen.reader.setMouse(mouse.decoder)
            }
            touchscreen.updateTakenStatus()
        }
        announceChange(of: touchscreen)
    }

    private func removed(_ id: HIDInterfaceID) {
        guard isStarted, interfaces.removeValue(forKey: id) != nil else { return }
        setAside.remove(id)
        if let touchscreen = touchscreens.first(where: { $0.touch.id == id }) {
            // Unplugged. Nothing is written to a device that has gone.
            touchscreen.taking += 1
            for open in touchscreen.open {
                system.stopReports(open.id)
                system.close(open.id, exclusive: open.exclusive)
            }
            touchscreen.open = []
            touchscreens.removeAll { $0 === touchscreen }
            log.info("Disconnected \(touchscreen.handle, privacy: .public)")
            note(touchscreen, "Disconnected \(touchscreen.handle)")
            delegate?.touchscreenDisconnected(touchscreen.handle)
            settleSoon()
        } else if let touchscreen = touchscreens.first(where: { $0.mouse?.id == id }) {
            if let index = touchscreen.open.firstIndex(where: { $0.id == id }) {
                system.stopReports(id)
                system.close(id, exclusive: touchscreen.open[index].exclusive)
                touchscreen.open.remove(at: index)
            }
            touchscreen.mouse = nil
            touchscreen.reader.setMouse(nil)
            touchscreen.connected.hasMouseInterface = false
            if touchscreen.state == .taken { touchscreen.updateTakenStatus() }
            log.info("\(touchscreen.handle, privacy: .public): its mouse interface went")
            note(touchscreen, "\(touchscreen.handle): its mouse interface went")
            announceChange(of: touchscreen)
            settleSoon()
        }
    }

    // MARK: - Taking and releasing

    private func take(_ touchscreen: Touchscreen) {
        touchscreen.taking += 1
        let touchOpen = openForTaking(touchscreen.touch, of: touchscreen)
        let mouseOpen = touchscreen.mouse.map { openForTaking($0, of: touchscreen) } ?? false
        // GET, then SET, as Linux does.
        if touchOpen { readFeatureReports(of: touchscreen, during: .take) }

        var inputMode = InputModeStatus.notSwitched
        touchscreen.wroteInputMode = false
        touchscreen.hasInputMode = touchOpen && system.hasInputMode(touchscreen.touch.id)
        if touchscreen.hasInputMode {
            inputMode = switchToMultiTouch(touchscreen)
        } else if touchOpen {
            inputMode = .noInputModeSetting
            log.info("\(touchscreen.handle, privacy: .public) has no Input Mode setting; left as it is")
            note(touchscreen, "\(touchscreen.handle) has no Input Mode setting; left as it is")
        }

        listen(to: touchscreen.touch, of: touchscreen)
        if let mouse = touchscreen.mouse { listen(to: mouse, of: touchscreen) }
        touchscreen.reader = TouchscreenReader(touch: touchOpen ? touchscreen.touch.decoder : nil,
                                               mouse: mouseOpen ? touchscreen.mouse?.decoder : nil)
        touchscreen.connected.status = DeviceStatus(state: .taken, inputMode: inputMode)
        touchscreen.updateTakenStatus()
        let status = touchscreen.connected.status
        log.info("""
            Took \(touchscreen.handle, privacy: .public): exclusive access \(status.exclusive.rawValue, privacy: .public), \
            input mode \(status.inputMode.rawValue, privacy: .public), touches \(status.touchOrigin.rawValue, privacy: .public)
            """)
        note(touchscreen, "Took \(touchscreen.handle): exclusive access \(status.exclusive.rawValue), "
             + "input mode \(status.inputMode.rawValue), touches \(status.touchOrigin.rawValue)")
    }

    /// Opens one interface for taking: exclusively, or shared if that fails. Returns whether it is open.
    private func openForTaking(_ interface: KnownInterface, of touchscreen: Touchscreen) -> Bool {
        // An interface holds one open at a time: never an exclusive open on top of a shared one.
        if let index = touchscreen.open.firstIndex(where: { $0.id == interface.id }) {
            system.close(interface.id, exclusive: touchscreen.open[index].exclusive)
            touchscreen.open.remove(at: index)
        }
        let role = interface.id == touchscreen.touch.id ? "touchscreen" : "mouse"
        let seized = system.open(interface.id, exclusive: true)
        if seized == kIOReturnSuccess {
            touchscreen.open.append((interface.id, true))
            log.info("\(touchscreen.handle, privacy: .public): holding its \(role, privacy: .public) interface exclusively")
            note(touchscreen, "\(touchscreen.handle): holding its \(role) interface exclusively")
            return true
        }
        let shared = system.open(interface.id, exclusive: false)
        if shared == kIOReturnSuccess {
            touchscreen.open.append((interface.id, false))
            log.error("""
                \(touchscreen.handle, privacy: .public): its \(role, privacy: .public) interface can't be held exclusively \
                (IOReturn \(IOResult.text(seized), privacy: .public)); reading it shared, so macOS may also respond
                """)
            note(touchscreen, "\(touchscreen.handle): its \(role) interface can't be held exclusively (IOReturn \(IOResult.text(seized))); "
                 + "reading it shared")
            return true
        }
        log.error("""
            \(touchscreen.handle, privacy: .public): its \(role, privacy: .public) interface can't be opened \
            (exclusive: IOReturn \(IOResult.text(seized), privacy: .public); shared: IOReturn \(IOResult.text(shared), privacy: .public))
            """)
        note(touchscreen, "\(touchscreen.handle): its \(role) interface can't be opened (exclusive: IOReturn \(IOResult.text(seized)); "
             + "shared: IOReturn \(IOResult.text(shared)))")
        return false
    }

    /// Reads, once each and in descriptor order, the touchscreen interface's feature reports that
    /// declare Contact Count Maximum or the certification blob, asking for each one's declared length.
    ///
    /// Windows and Linux read these whenever a touchscreen enumerates, and the ILITEK stays in its
    /// power-on mouse emulation until a host has read its 0x06: it was multi-touch before the
    /// 16 November 2026 reboot only because the survey's probe had read it. So every take reads
    /// them, with the touchscreen interface open, before the Input Mode write and before anything
    /// is listened to; `refresh()` does too, before its write. A failed read is logged as an error,
    /// and the take or refresh goes on.
    ///
    /// A read that times out (see `featureReadTimedOut`) ends this connection's reads: the
    /// touchscreen isn't asked again until it is plugged in again or the source starts again, so a
    /// panel that never answers holds Tactile once, not on every take. Never while released, never
    /// the mouse or a vendor interface, and nothing is written.
    private func readFeatureReports(of touchscreen: Touchscreen, during occasion: FeatureReadOccasion) {
        guard !touchscreen.featureReadsTimedOut else { return }
        for report in touchscreen.touch.decoder?.featureReportsToRead ?? [] {
            let read = system.readFeatureReport(touchscreen.touch.id, reportID: report.reportID, length: report.length)
            let entry = Self.featureReadLog(read, of: report, by: touchscreen.handle, during: occasion)
            if entry.isError {
                log.error("\(entry.text, privacy: .public)")
            } else {
                log.info("\(entry.text, privacy: .public)")
            }
            note(touchscreen, entry.text)
            if Self.featureReadTimedOut(read) {
                touchscreen.featureReadsTimedOut = true
                return
            }
        }
    }

    /// Writes Input Mode = 2 to a touchscreen whose touchscreen interface is open and has it. The
    /// write counts as made once it is sent: a panel can apply it and still answer with an error.
    private func switchToMultiTouch(_ touchscreen: Touchscreen) -> InputModeStatus {
        touchscreen.wroteInputMode = true
        let result = system.writeInputMode(touchscreen.touch.id, 2)
        let accepted = result == kIOReturnSuccess
        log.info("""
            \(touchscreen.handle, privacy: .public): Input Mode 2 (multi-touch) \(accepted ? "accepted" : "refused", privacy: .public) \
            (IOReturn \(IOResult.text(result), privacy: .public))
            """)
        note(touchscreen, "\(touchscreen.handle): Input Mode 2 (multi-touch) \(accepted ? "accepted" : "refused") (IOReturn \(IOResult.text(result)))")
        return accepted ? .switchedToMultiTouch : .switchRefused
    }

    private func listen(to interface: KnownInterface, of touchscreen: Touchscreen) {
        guard touchscreen.open.contains(where: { $0.id == interface.id }) else { return }
        let id = interface.id
        let handle = touchscreen.handle
        let role: TouchscreenReader.Interface = id == touchscreen.touch.id ? .touch : .mouse
        system.startReports(id, bufferSize: interface.reportBufferSize) { [weak self] bytes, time in
            self?.report(bytes, from: role, interface: id, of: handle, at: time)
        }
    }

    private func release(_ touchscreen: Touchscreen) {
        touchscreen.taking += 1
        for open in touchscreen.open { system.stopReports(open.id) }
        if touchscreen.wroteInputMode, touchscreen.open.contains(where: { $0.id == touchscreen.touch.id }) {
            let result = system.writeInputMode(touchscreen.touch.id, 0)
            log.info("""
                \(touchscreen.handle, privacy: .public): Input Mode 0 (mouse emulation) written back \
                (IOReturn \(IOResult.text(result), privacy: .public))
                """)
            note(touchscreen, "\(touchscreen.handle): Input Mode 0 (mouse emulation) written back (IOReturn \(IOResult.text(result)))")
        }
        for open in touchscreen.open { system.close(open.id, exclusive: open.exclusive) }
        touchscreen.open = []
        touchscreen.wroteInputMode = false
        touchscreen.hasInputMode = false
        touchscreen.reader.reset()
        touchscreen.connected.status = DeviceStatus()
        log.info("Released \(touchscreen.handle, privacy: .public)")
        note(touchscreen, "Released \(touchscreen.handle)")
    }

    // MARK: - Reports

    private func report(_ bytes: [UInt8], from role: TouchscreenReader.Interface, interface id: HIDInterfaceID,
                        of handle: DeviceHandle, at time: TimeInterval) {
        guard let touchscreen = touchscreen(handle), touchscreen.state == .taken,
              touchscreen.open.contains(where: { $0.id == id }) else { return }
        let taking = touchscreen.taking
        let origin = touchscreen.reader.origin
        let frames = touchscreen.reader.add(bytes, from: role, at: time)
        if touchscreen.reader.origin != origin {
            touchscreen.connected.status.touchOrigin = touchscreen.reader.origin
            log.info("\(handle, privacy: .public): touches come from \(touchscreen.reader.origin.rawValue, privacy: .public)")
            note(touchscreen, "\(handle): touches come from \(touchscreen.reader.origin.rawValue)")
            announceChange(of: touchscreen)
        }
        for frame in frames {
            // The delegate may have released the touchscreen, or stopped the source, meanwhile.
            guard isStarted, self.touchscreen(handle) === touchscreen, touchscreen.taking == taking else { return }
            delegate?.touchscreen(handle, produced: frame)
        }
    }

    // MARK: - Helpers

    private func announceChange(of touchscreen: Touchscreen) {
        delegate?.touchscreenChanged(touchscreen.connected)
    }

    private func touchscreen(_ handle: DeviceHandle) -> Touchscreen? {
        touchscreens.first { $0.handle == handle }
    }

    private func owner(of id: HIDInterfaceID) -> Touchscreen? {
        touchscreens.first { $0.touch.id == id || $0.mouse?.id == id }
    }

    private static func usbID(_ facts: TouchscreenFacts) -> String {
        String(format: "%04x:%04x", facts.vendorID, facts.productID)
    }

    private static func location(_ locationID: UInt32) -> String {
        String(format: "0x%08x", locationID)
    }
}

/// When a touchscreen's feature reports are read.
enum FeatureReadOccasion: String { case take, refresh }

extension HIDTouchscreenSource {
    /// A read that takes this long or longer counts as timed out, whatever it returned. The HID
    /// request timeout is 5 s on this desk's panels.
    static let featureReadTimeLimit: TimeInterval = 4

    /// IOKit's timeout code, or a read that took `featureReadTimeLimit` or longer.
    static func featureReadTimedOut(_ read: FeatureReportRead) -> Bool {
        read.result == IOResult.timeout || read.seconds >= featureReadTimeLimit
    }

    /// The log line for one feature report read: the length asked for, the length that came
    /// back, how long it took and the IOReturn. A read that failed or timed out is an error, which
    /// the unified log keeps after a reboot; one that worked is info.
    static func featureReadLog(_ read: FeatureReportRead, of report: FeatureReportToRead, by handle: DeviceHandle,
                               during occasion: FeatureReadOccasion) -> (text: String, isError: Bool) {
        let id = String(format: "0x%02X", report.reportID)
        let returned = read.length > 0 ? "\(read.length) returned" : "none returned"
        let seconds = String(format: "%.3f", read.seconds)
        let line = "\(handle): read feature report \(id) (\(report.describedContents)): \(report.length) bytes asked, "
            + "\(returned) in \(seconds) s (IOReturn \(IOResult.text(read.result)))"
        let goesOn = "the \(occasion.rawValue) goes on"
        if featureReadTimedOut(read) {
            let why = read.result == kIOReturnSuccess ? "it took \(Int(featureReadTimeLimit)) s or more" : "it timed out"
            return (line + "; \(why), so this touchscreen's feature reports won't be read again until it is plugged in "
                    + "again or Tactile restarts, and \(goesOn)", true)
        }
        if read.result != kIOReturnSuccess { return (line + "; the read failed, and \(goesOn)", true) }
        return (line, false)
    }
}

/// One connected touchscreen, as the source keeps it.
@MainActor
private final class Touchscreen {
    var connected: ConnectedTouchscreen
    let touch: KnownInterface
    var mouse: KnownInterface?
    var reader: TouchscreenReader
    /// The interfaces open now, the touchscreen interface first, and whether each is held exclusively.
    var open: [(id: HIDInterfaceID, exclusive: Bool)] = []
    /// The touchscreen interface has Input Mode; known while taken.
    var hasInputMode = false
    /// A write of Input Mode 2 was sent during this taking, so releasing writes 0.
    var wroteInputMode = false
    /// A feature report read timed out on this connection, so none is read again: a touchscreen
    /// plugged in again, or the source started again, is a new connection and is read again.
    var featureReadsTimedOut = false
    /// Counts takes, releases and unplugging, so a report's frames stop when any of them happens.
    var taking = 0

    init(connected: ConnectedTouchscreen, touch: KnownInterface, mouse: KnownInterface?) {
        self.connected = connected
        self.touch = touch
        self.mouse = mouse
        reader = TouchscreenReader(touch: touch.decoder, mouse: mouse?.decoder)
    }

    var handle: DeviceHandle { connected.handle }
    var state: DeviceState { connected.status.state }

    /// Exclusive access and touch origin, for a taken touchscreen, from what is open now.
    func updateTakenStatus() {
        let wanted = [touch.id] + (mouse.map { [$0.id] } ?? [])
        let held = wanted.allSatisfy { id in open.contains { $0.id == id && $0.exclusive } }
        connected.status.exclusive = held ? .held : .failed
        connected.status.touchOrigin = reader.origin
    }
}
