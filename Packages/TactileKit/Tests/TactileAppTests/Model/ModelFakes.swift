// Fakes for everything the model is told and everything it tells, and a harness that puts them
// together with a temporary settings folder. Nothing here opens a device, posts an event, moves the
// pointer or opens a window, and the folder is removed at the end of each test.

import CoreGraphics
import Foundation
@testable import TactileApp
import TactileDevices
import TactileReading
import TactileScreens
import XCTest

/// The device layer, as the model sees it. As the real one does, `setState` reports the new status
/// through the delegate before it returns, and `stop` lets go of every touchscreen and reports each
/// as disconnected.
@MainActor
final class FakeTouchscreenSource: TouchscreenSource {
    weak var delegate: TouchscreenSourceDelegate?
    let log: CallLog
    /// Every touchscreen plugged in now; those plugged in before `start` are announced by it.
    private(set) var plugged: [ConnectedTouchscreen] = []
    /// The status a touchscreen reports once taken; `DeskFixture.taken()` when not given.
    var statusWhenTaken: [DeviceHandle: DeviceStatus] = [:]
    private(set) var refreshes = 0
    private(set) var isStarted = false
    /// The state each touchscreen was last left in, kept after it has gone.
    private var states: [DeviceHandle: DeviceState] = [:]

    init(log: CallLog) {
        self.log = log
    }

    func start() {
        log.add("source.start")
        isStarted = true
        for touchscreen in plugged { delegate?.touchscreenConnected(touchscreen) }
    }

    func stop() {
        log.add("source.stop")
        isStarted = false
        let gone = plugged
        plugged = []
        for touchscreen in gone {
            states[touchscreen.handle] = .released
            delegate?.touchscreenDisconnected(touchscreen.handle)
        }
    }

    func setState(_ state: DeviceState, for handle: DeviceHandle) {
        log.add("source.setState \(handle) \(state.rawValue)")
        guard let index = plugged.firstIndex(where: { $0.handle == handle }) else {
            log.add("source.setState for a device that has gone")
            return
        }
        guard plugged[index].status.state != state else { return }
        plugged[index].status = state == .taken ? statusWhenTaken[handle] ?? DeskFixture.taken() : DeviceStatus()
        states[handle] = state
        delegate?.touchscreenChanged(plugged[index])
    }

    func refresh() {
        log.add("source.refresh")
        refreshes += 1
    }

    // MARK: What a test does

    func plugIn(_ touchscreen: ConnectedTouchscreen) {
        plugged.append(touchscreen)
        states[touchscreen.handle] = touchscreen.status.state
        if isStarted { delegate?.touchscreenConnected(touchscreen) }
    }

    func unplug(_ handle: DeviceHandle) {
        plugged.removeAll { $0.handle == handle }
        delegate?.touchscreenDisconnected(handle)
    }

    func change(_ handle: DeviceHandle, _ make: (inout ConnectedTouchscreen) -> Void) {
        guard let index = plugged.firstIndex(where: { $0.handle == handle }) else { return }
        make(&plugged[index])
        delegate?.touchscreenChanged(plugged[index])
    }

    func send(_ frame: ContactFrame, from handle: DeviceHandle) {
        delegate?.touchscreen(handle, produced: frame)
    }

    func send(_ frames: some Sequence<ContactFrame>, from handle: DeviceHandle) {
        for frame in frames { send(frame, from: handle) }
    }

    func state(of handle: DeviceHandle) -> DeviceState? {
        states[handle]
    }

    /// How many times the model asked for `handle`'s state.
    func requests(for handle: DeviceHandle) -> Int {
        log.entries.filter { $0.hasPrefix("source.setState \(handle) ") }.count
    }
}

@MainActor
final class FakeDisplaySource: DisplaySource {
    private(set) var displays: [DisplayFacts]
    var onChange: (@MainActor () -> Void)?

    init(_ displays: [DisplayFacts]) {
        self.displays = displays
    }

    func set(_ displays: [DisplayFacts]) {
        self.displays = displays
        onChange?()
    }
}

@MainActor
final class FakeSystemConditions: SystemConditions {
    private(set) var hasAccessibilityAccess = true
    private(set) var isSessionActive = true
    private(set) var isTouchUpRunning = false
    private(set) var areMissionControlShortcutsOn = true
    var onChange: (@MainActor () -> Void)?
    var onWillSleep: (@MainActor () -> Void)?
    var onDidWake: (@MainActor () -> Void)?
    private(set) var accessibilityRequests = 0

    func askForAccessibility() {
        accessibilityRequests += 1
    }

    /// What the system says about launching at login; a test sets it, or the answer to a request does.
    var launchAtLogin = LaunchAtLogin.off
    /// What becomes of a request to switch launch at login on or off: by default, it is done.
    var answerToLaunchAtLogin: (Bool) -> LaunchAtLogin = { $0 ? .on : .off }
    /// Every request to switch launch at login, in order, and how often Login Items was opened.
    private(set) var launchAtLoginRequests: [Bool] = []
    private(set) var loginItemsOpened = 0

    func setLaunchAtLogin(_ on: Bool) {
        launchAtLoginRequests.append(on)
        launchAtLogin = answerToLaunchAtLogin(on)
    }

    func openLoginItemsSettings() {
        loginItemsOpened += 1
    }

    /// The person changed it in System Settings and came back: the conditions say they changed.
    func launchAtLoginChanged(to state: LaunchAtLogin) {
        launchAtLogin = state
        onChange?()
    }

    func setAccessibility(_ granted: Bool) {
        hasAccessibilityAccess = granted
        onChange?()
    }

    func setSessionActive(_ active: Bool) {
        isSessionActive = active
        onChange?()
    }

    func setTouchUpRunning(_ running: Bool) {
        isTouchUpRunning = running
        onChange?()
    }

    /// Something the conditions watch but don't carry changed, as the live ones say when the
    /// trackpad's "Swipe between full-screen applications" changes: they say so, and nothing they
    /// carry is different.
    func somethingWatchedChanged() {
        onChange?()
    }

    func sleep() { onWillSleep?() }
    func wake() { onDidWake?() }
}

/// The model's clock, recorded: it never ticks by itself; a test ticks the model by hand.
@MainActor
final class RecordingTicker: ModelTicker {
    private(set) var isRunning = false
    private(set) var interval: TimeInterval?
    private(set) var starts = 0
    private(set) var stops = 0
    let log: CallLog

    init(log: CallLog) {
        self.log = log
    }

    func start(every interval: TimeInterval, _ tick: @escaping @MainActor @Sendable () -> Void) {
        guard self.interval != interval else { return }
        if !isRunning { starts += 1 }
        isRunning = true
        self.interval = interval
        log.add("ticker start every \(interval)")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        interval = nil
        stops += 1
        log.add("ticker stop")
    }
}

/// A model with fakes all round, a temporary settings folder, and a clock the test moves.
@MainActor
final class ModelHarness {
    let log = CallLog()
    let source: FakeTouchscreenSource
    let displays = FakeDisplaySource(DeskFixture.displays)
    let conditions = FakeSystemConditions()
    let outputs: RecordingOutputs
    let ticker: RecordingTicker
    let folder: URL
    let store: SettingsStore
    let model: TactileModel
    var clock: TimeInterval = 10_000
    /// What Copy Diagnostics put on the pasteboard, in order.
    private(set) var pasteboard: [String] = []

    var settingsURL: URL { folder.appendingPathComponent("settings.json") }
    var stateURL: URL { folder.appendingPathComponent("state.json") }
    /// Where the model records frames: inside the temporary folder, never `~/Library`.
    var framesURL: URL { folder.appendingPathComponent("Frames", isDirectory: true) }

    /// - Parameters:
    ///   - settings: written to the settings file before the model starts; nil for no file.
    ///   - fileBytes: written to the settings file as they are, instead.
    ///   - writesStateFile: whether the model is given a state file.
    init(settings: TactileSettings? = nil, fileBytes: Data? = nil, writesStateFile: Bool = false) throws {
        source = FakeTouchscreenSource(log: log)
        outputs = RecordingOutputs(log: log)
        ticker = RecordingTicker(log: log)
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TactileModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let settingsURL = folder.appendingPathComponent("settings.json")
        if let settings { try SettingsStore(fileURL: settingsURL).save(settings) }
        if let fileBytes { try fileBytes.write(to: settingsURL) }
        store = SettingsStore(fileURL: settingsURL)
        var now: () -> TimeInterval = { 0 }
        var copy: @MainActor (String) -> Void = { _ in }
        model = TactileModel(
            appVersion: "0.2.0", source: source, displays: displays, conditions: conditions, store: store,
            stateFileURL: writesStateFile ? folder.appendingPathComponent("state.json") : nil, outputs: outputs,
            now: { now() }, framesFolder: folder.appendingPathComponent("Frames", isDirectory: true),
            systemVersion: "Version 26.1 (Build 25B78)", copyToPasteboard: { copy($0) }, logs: false)
        now = { [unowned self] in MainActor.assumeIsolated { self.clock } }
        copy = { [unowned self] text in self.pasteboard.append(text) }
        model.ticker = ticker
    }

    /// Shuts the model down, if the test hasn't, and removes the folder.
    func cleanUp() {
        model.shutDown()
        chmod(folder.path, 0o755)
        try? FileManager.default.removeItem(at: folder)
    }

    /// The settings in the file now, as a fresh store reads them; nil when there is no file.
    func savedSettings() -> TactileSettings? {
        let (settings, outcome) = SettingsStore(fileURL: settingsURL).load()
        return outcome == .loaded ? settings : nil
    }

    /// Sends `frames` from `handle`, with the clock following their times.
    func send(_ frames: some Sequence<ContactFrame>, from handle: DeviceHandle) {
        for frame in frames {
            clock = frame.time
            source.send(frame, from: handle)
        }
    }

    /// The person switched "Swipe between full-screen applications" in System Settings: the sender
    /// reads it so from now on, and the conditions, which watch it, say they changed, as the live
    /// ones do within a poll or when Tactile becomes the active app.
    func switchSpaceSwipe(_ isOn: Bool) {
        outputs.dockSurroundings.isSpaceSwipeEnabled = isOn
        conditions.somethingWatchedChanged()
    }

    /// Moves the clock on and ticks every pipeline, as the timer would.
    func tick(after seconds: TimeInterval) {
        clock += seconds
        model.tickPipelines()
    }

    func touchscreen(_ id: TouchscreenID) -> TouchscreenSnapshot? {
        model.snapshot.touchscreens.first { $0.id == id }
    }
}
