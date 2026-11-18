// The live model: keeps everything known, resolves it after every change, and applies the
// difference to the device layer and the touch pipelines.

import CoreGraphics
import Foundation
import Observation
import TactileDevices
import TactileGestures
import TactileOutput
import TactileReading
import TactileScreens
import os

/// What the interface sees and can ask for, and the device layer's delegate.
///
/// It keeps `AppInputs`, and after every change to them (a connection, a removal, a status change,
/// a display change, a condition change, a command) resolves them again and applies the difference:
/// 1. a touchscreen that stops driving, or whose touches now land elsewhere, has its pipeline
///    cancelled, before anything is asked of its device;
/// 2. the device layer is asked to take or let go of each touchscreen whose device state changed;
/// 3. a touchscreen that starts driving gets a new pipeline, and one that keeps driving with
///    different settings has its pipeline updated;
/// 4. `snapshot` is replaced, and the state file written, only when it differs.
///
/// A frame goes to its touchscreen's pipeline when it is driving, to set-up mode while it is on, to
/// the set-up flow when one is running for its touchscreen, and is dropped otherwise.
///
/// **Set-up mode** (`TactileModel+SetUpMode.swift`) holds every touchscreen in a single pass: the
/// model holds one `SetUpSession` while it is on, gives it every touchscreen's frames, and applies
/// what it answers. Its flows are stored by their Done exactly as a flow outside the mode is.
///
/// **Set-up outside the mode** (Calibrate Corners… and Test from a pane). The model holds at most
/// one `SetUpFlow` of its own. While it runs, its touchscreen is taken and
/// setting up (see `Resolver`'s mode table): its frames go to the flow and never to a pipeline or the
/// arbiter, so they never move the pointer or click, and no other touchscreen is disturbed. Its
/// pipeline is cancelled first, as for any touchscreen that stops driving. The flow is ticked 10
/// times a second in every step (60 while a touch elsewhere needs it), on the clock its frames are
/// timed on: the flow's own time limits end a forgotten set-up.
/// In its check step the touches are shown as circles, mapped with its `checkMapping`. What is
/// published is the flow's `snapshot`, which changes only when what it shows changes, never the
/// flow, whose clock moves on every tick. Anything that ends driving ends the flow with nothing
/// stored: Tactile off, Accessibility gone, the session inactive, sleep, quitting, the touchscreen
/// unplugged or no longer readable, and the display in use gone once the displays have settled. Done applies the outcome in one change to the settings
/// (`Resolver.applySetUp`), and the touchscreen drives again through the next resolve. After each
/// round of its corners, accepted or refused, what the round measured is logged as one line, the
/// flow's `CornersReport.logLine`, for tuning the corners' limits from real taps.
///
/// A change that arrives while a round is being applied (the device layer reports a new status
/// before `setState` returns) never starts a second round inside the first: it is noted, and the
/// round goes again once the current one has finished.
///
/// **The gesture tester** (`TactileModel+GestureTester.swift`) observes one driving touchscreen's
/// pipeline, which drives as always but holds its swipes unless they are let through; at the end of
/// each round it closes when it can no longer be open (a display reconfiguration waits for the
/// displays to settle), and its feed goes into the snapshot, and between rounds at most ten times a
/// second; the state file then follows at most once a second, and at the end of each gesture.
/// `steadySnapshot`, the snapshot without that feed, which every window but the tester's reads, is
/// set with `snapshot` only when it differs, so the feed's updates draw no other window again.
///
/// The settings are loaded once, by `start`, from the one store the model keeps for its life:
/// nothing is saved before they are loaded, so a file the store can't use is never written over.
///
/// Main thread only.
@MainActor
@Observable
public final class TactileModel: AppModel, TouchscreenSourceDelegate {

    /// Written by the round and by the gesture tester's news; whoever writes it, `steadySnapshot`
    /// follows (`snapshotChanged`).
    public internal(set) var snapshot: AppSnapshot {
        didSet { snapshotChanged() }
    }
    /// `snapshot` without the gesture tester's feed, set with it when that differs (`AppModel`).
    public private(set) var steadySnapshot: AppSnapshot

    private let source: TouchscreenSource
    private let displays: DisplaySource
    private let conditions: SystemConditions
    private let store: SettingsStore
    private let stateFile: StateFile?
    private let outputs: PipelineOutputs
    /// The host's clock, the one frames are timed on. Internal only for the model's own extensions
    /// (`TactileModel+…`).
    let now: () -> TimeInterval
    /// Where recorded frames go: `~/Library/Logs/Tactile` in the app.
    private let framesFolder: URL
    /// macOS's version, for Copy Diagnostics.
    private let systemVersion: String
    /// Puts Copy Diagnostics' text on the pasteboard.
    private let copyToPasteboard: @MainActor (String) -> Void

    /// Everything the model knows. Internal only for the model's own extensions (`TactileModel+…`),
    /// which change it as the model does, then resolve; interface code never reads or sets it: it
    /// reads `snapshot` and sends commands through `perform`.
    @ObservationIgnored var inputs: AppInputs
    /// What each connected touchscreen was resolved to last time, by handle.
    @ObservationIgnored private var resolved: [DeviceHandle: ResolvedTouchscreen] = [:]
    /// The device state last asked of each connected touchscreen.
    @ObservationIgnored private var requestedStates: [DeviceHandle: DeviceState] = [:]
    /// One pipeline for each driving touchscreen, by handle.
    @ObservationIgnored private var pipelines: [DeviceHandle: TouchPipeline] = [:]
    /// The touchscreens whose last frame had fingers on the glass, driving or not, and when each
    /// touchscreen's last frame came.
    @ObservationIgnored private var fingersDown: Set<DeviceHandle> = []
    @ObservationIgnored private var lastFrameTimes: [DeviceHandle: TimeInterval] = [:]
    /// Touchscreens whose touches have just moved from the mouse interface to the touch interface,
    /// mid-touch, and the time of that change: an empty frame no later than it is the reader ending
    /// the mouse finger, not the finger lifting.
    @ObservationIgnored private var syntheticLiftBy: [DeviceHandle: TimeInterval] = [:]
    /// The touchscreens whose pipelines have been given a recorder (or failed to get one) since
    /// frame recording was switched on, by handle. A pipeline made afresh gets a new file.
    @ObservationIgnored private var recordingHandles: Set<DeviceHandle> = []
    /// The gesture tester while it is open (see `TactileModel+GestureTester.swift`).
    @ObservationIgnored var gestureTester: GestureTesterSession?
    /// The set-up running now outside set-up mode, and the connection of the touchscreen it is for.
    /// Internal, as the two below, only for the model's own extensions (`TactileModel+…`).
    @ObservationIgnored var setUp: (flow: SetUpFlow, handle: DeviceHandle)?
    /// Set-up mode, while it is on (`TactileModel+SetUpMode.swift`).
    @ObservationIgnored var setUpMode: SetUpSession?
    /// What set-up mode's session was last told is connected, and each connected handle's ID.
    @ObservationIgnored var setUpModeScene: SetUpScene?
    /// The displays the set-up flow was last told of.
    @ObservationIgnored private var setUpDisplays: [DisplayFacts] = []
    /// The display the check step's circles are on, while they may be showing.
    @ObservationIgnored private var setUpCirclesOn: UInt32?
    /// Each touchscreen's latest frame while fingers are on its glass, for a set-up that begins then.
    /// Internal only for the model's own extensions (`TactileModel+…`).
    @ObservationIgnored var lastFrames: [DeviceHandle: ContactFrame] = [:]
    /// The clock: 60 Hz for a touch, 10 Hz for a set-up. A test may replace it before `start`.
    @ObservationIgnored var ticker: ModelTicker
    @ObservationIgnored private(set) var hasStarted = false
    @ObservationIgnored private var hasLoadedSettings = false
    @ObservationIgnored private var hasShutDown = false
    @ObservationIgnored private var isApplying = false
    @ObservationIgnored private var mustApplyAgain = false
    /// Why the last save failed; nil when it succeeded.
    @ObservationIgnored private var lastSaveFailure: String?
    /// How many failed saves have been logged: one for each run of failures with the same reason.
    @ObservationIgnored private(set) var loggedSaveFailures = 0
    /// How many times the settings file has been written, for tests.
    @ObservationIgnored private(set) var saves = 0

    /// - Parameters:
    ///   - framesFolder: where recorded frames are written; `~/Library/Logs/Tactile` when nil.
    ///   - systemVersion: macOS's version, for Copy Diagnostics.
    ///   - copyToPasteboard: puts Copy Diagnostics' text on the pasteboard.
    ///   - logs: whether the model and its pipelines write to the log (`ModelLog`): the app's model
    ///     does; a test's doesn't. No default, so neither can be forgotten.
    public init(appVersion: String, source: TouchscreenSource, displays: DisplaySource, conditions: SystemConditions,
                store: SettingsStore, stateFileURL: URL?, outputs: PipelineOutputs, now: @escaping () -> TimeInterval,
                framesFolder: URL? = nil,
                systemVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
                copyToPasteboard: @escaping @MainActor (String) -> Void = LivePasteboard.copy,
                logs: Bool) {
        ModelLog.set(on: logs)
        self.source = source
        self.displays = displays
        self.conditions = conditions
        self.store = store
        stateFile = stateFileURL.map(StateFile.init(url:))
        self.outputs = outputs
        self.now = now
        self.framesFolder = framesFolder ?? Self.defaultFramesFolder
        self.systemVersion = systemVersion
        self.copyToPasteboard = copyToPasteboard
        let inputs = AppInputs(
            appVersion: appVersion, settings: TactileSettings(), connected: [], records: [:],
            displays: displays.displays,
            hasAccessibilityAccess: conditions.hasAccessibilityAccess, isSessionActive: conditions.isSessionActive,
            isAsleep: false, isTouchUpRunning: conditions.isTouchUpRunning,
            areMissionControlShortcutsOn: conditions.areMissionControlShortcutsOn, settingsWereSetAside: false,
            isQuitting: false)
        self.inputs = inputs
        ticker = LiveTicker()
        let resolved = Resolver.resolve(inputs).snapshot
        snapshot = resolved
        steadySnapshot = resolved.withoutTesterFeed
    }

    /// Loads the settings, starts listening, and starts the device layer, which announces every
    /// touchscreen already connected. Call once.
    public func start() {
        guard !hasStarted, !hasShutDown else { return }
        hasStarted = true

        let (settings, outcome) = store.load()
        hasLoadedSettings = true
        inputs.settings = settings
        switch outcome {
        case .loaded:
            ModelLog.model.info("Settings loaded from \(self.store.fileURL.path, privacy: .public)")
        case .noFile:
            ModelLog.model.info("No settings file yet; starting from the defaults")
        case .setAside(let url):
            inputs.settingsWereSetAside = true
            ModelLog.model.error("The settings file couldn't be used; set aside as \(url.path, privacy: .public). Starting from the defaults")
        case .couldNotSetAside:
            inputs.settingsWereSetAside = true
            ModelLog.model.error("The settings file couldn't be used or set aside; starting from the defaults. It won't be written over")
        }

        source.delegate = self
        displays.onChange = { [weak self] in self?.displaysChanged() }
        conditions.onChange = { [weak self] in self?.conditionsChanged() }
        conditions.onWillSleep = { [weak self] in self?.willSleep() }
        conditions.onDidWake = { [weak self] in self?.didWake() }
        readDisplays()
        readConditions()
        // Records decided before the settings were loaded are decided again from them.
        inputs.records = [:]
        assignRecords()
        resolveAndApply()
        writeStateFile()
        source.start()
    }

    public func perform(_ command: AppCommand) {
        guard !hasShutDown else { return }
        if command == .askForAccessibility {
            ModelLog.model.info("Asking for Accessibility access")
            conditions.askForAccessibility()
            return
        }
        switch command {
        case .setLaunchAtLogin(let isOn):
            ModelLog.model.info("Launch at login: asking the system to switch it \(isOn ? "on" : "off", privacy: .public)")
            conditions.setLaunchAtLogin(isOn)
        case .openLoginItemsSettings:
            ModelLog.model.info("Opening Login Items in System Settings")
            conditions.openLoginItemsSettings()
        default:
            break
        }
        // What the system says about launching at login is read again after every command.
        inputs.launchAtLogin = conditions.launchAtLogin
        // Set-up mode's commands, and the set-up commands while it is on.
        if performInSetUpMode(command) { return }
        switch command {
        case .copyDiagnostics:
            ModelLog.model.info("Copying the diagnostics")
            // What is known now, not the last round's snapshot: launch at login, just read, and
            // what a round reads again (whether this Mac can follow swipes).
            resolveAndApply()
            copyToPasteboard(Diagnostics.text(snapshot: snapshot, settings: inputs.settings, systemVersion: systemVersion))
            return
        case .beginSetUp(let id, let purpose):
            beginSetUp(id, purpose)
            return
        case .setUpConfirmSize(let inches):
            stepSetUp("confirm size \(inches.map { "\($0)″" } ?? "as reported")") { $0.confirmSize(inches: inches) }
            return
        case .setUpRedo:
            stepSetUp("redo", tooSoonAs: "Redo") { $0.redo() }
            return
        case .setUpDone:
            stepSetUp("done", tooSoonAs: "Done") { $0.done() }
            return
        case .cancelSetUp:
            stepSetUp("cancel") { $0.cancel() }
            return
        case .openGestureTester, .closeGestureTester, .setGestureTesterPerformsSwipes, .clearGestureTester:
            performGestureTester(command)
        case .beginSupportCheck(let id):
            guard inputs.setUp == nil, setUp == nil, setUpMode == nil else {
                ModelLog.model.info("The touchscreen check of \(Self.usbAndLocation(id, self.inputs), privacy: .public) can't begin while a set-up runs")
                return
            }
            ModelLog.model.info("The touchscreen check has \(Self.usbAndLocation(id, self.inputs), privacy: .public): letting it go until the check ends")
            inputs.supportCheck = id
        case .endSupportCheck:
            guard let id = inputs.supportCheck else { return }
            ModelLog.model.info("The touchscreen check let \(Self.usbAndLocation(id, self.inputs), privacy: .public) go: taking it back")
            inputs.supportCheck = nil
        default:
            break
        }
        noteSetUpInInputs()
        let settings = Resolver.apply(command, to: inputs)
        if settings != inputs.settings {
            ModelLog.model.info("Command \(String(describing: command), privacy: .public)")
            inputs.settings = settings
            save()
        }
        resolveAndApply()
    }

    /// Cancels every touch, releases every touchscreen, brings the arrow back, saves, and removes the
    /// state file. Done by the time it returns; the model does nothing afterwards.
    ///
    /// Reached from inside a round of applying (a delegate callback during `setState`), it can't
    /// resolve again: it cancels every touch itself, before the device layer lets go of anything,
    /// and that round stops where it is.
    public func shutDown() {
        guard !hasShutDown else { return }
        ModelLog.model.info("Shutting down")
        // A followed swipe left open would leave the screen between two Desktops: closed first,
        // and its end repeated at once, as the repeat's wait would die with the process.
        outputs.dockSwipes.closeIfOpen()
        outputs.sendDockSwipeWaitsNow()
        inputs.isQuitting = true
        resolveAndApply()
        cancelEveryPipeline()
        hasShutDown = true
        // After a session that ended normally the arrow stays hidden until the mouse moves.
        outputs.keeper.sessionCancelled()
        source.stop()
        source.delegate = nil
        displays.onChange = nil
        conditions.onChange = nil
        conditions.onWillSleep = nil
        conditions.onDidWake = nil
        ticker.stop()
        save()
        if let stateFile {
            do {
                try stateFile.remove()
            } catch {
                ModelLog.model.error("Couldn't remove the state file: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: - TouchscreenSourceDelegate

    public func touchscreenConnected(_ touchscreen: ConnectedTouchscreen) {
        guard !hasShutDown else { return }
        ModelLog.model.info("Connected: \(Self.describe(touchscreen), privacy: .public)")
        inputs.connected.removeAll { $0.handle == touchscreen.handle }
        inputs.connected.append(touchscreen)
        requestedStates[touchscreen.handle] = touchscreen.status.state
        noteTakenStatus(of: touchscreen)
        assignRecords()
        resolveAndApply()
    }

    /// A change for a touchscreen that isn't connected is dropped: it can't bring one back.
    ///
    /// When a touchscreen's fingers stop coming from where they came from, its touch is cancelled at
    /// once: when it loses its mouse interface while its touches came from it (no lift will come),
    /// and when the origin of its touches changes while fingers are down (a panel with no mouse
    /// interface, whose touchscreen interface sends pointer reports, only ever does the second).
    /// After a change from the mouse interface to the touch interface, the reader first ends the
    /// mouse finger with an empty frame; that frame is not a lift, and the finger, now on the touch
    /// interface, is ignored until it lifts. A finger counts as down for `TouchPipeline.silenceLimit`
    /// after its last frame, through a lost mouse interface too.
    public func touchscreenChanged(_ touchscreen: ConnectedTouchscreen) {
        guard !hasShutDown else { return }
        let handle = touchscreen.handle
        guard let index = inputs.connected.firstIndex(where: { $0.handle == handle }) else { return }
        let before = inputs.connected[index]
        guard before != touchscreen else { return }
        inputs.connected[index] = touchscreen
        noteTakenStatus(of: touchscreen)
        if before.status != touchscreen.status {
            ModelLog.model.info("\(handle.description, privacy: .public) status: \(Self.describe(touchscreen.status), privacy: .public)")
        }

        let time = now()
        let wasMouse = before.status.touchOrigin == .mouseInterface
        if before.hasMouseInterface, !touchscreen.hasMouseInterface,
           wasMouse || touchscreen.status.touchOrigin == .mouseInterface {
            // No lift will come from it. The finger may still be down: if the touch interface
            // reports it next, the origin changes, and that is the same touch.
            cancelTouch(of: handle, at: time, because: "its mouse interface has gone")
        } else if before.status.touchOrigin != touchscreen.status.touchOrigin, hasFingersDown(handle, at: time) {
            cancelTouch(of: handle, at: time, because: "its touches now come from \(touchscreen.status.touchOrigin.rawValue)")
            if wasMouse, touchscreen.status.touchOrigin == .touchInterface { syntheticLiftBy[handle] = time }
        }

        if before.facts != touchscreen.facts { assignRecords() }
        resolveAndApply()
    }

    public func touchscreenDisconnected(_ handle: DeviceHandle) {
        guard !hasShutDown, let index = inputs.connected.firstIndex(where: { $0.handle == handle }) else { return }
        ModelLog.model.info("Disconnected: \(handle.description, privacy: .public)")
        // Resolving again cancels its touch. Nothing is asked of a device that has gone: it is no
        // longer among the touchscreens resolved.
        inputs.connected.remove(at: index)
        requestedStates[handle] = nil
        resolved[handle] = nil
        inputs.lastTakenStatus[handle] = nil
        lastFrames[handle] = nil
        fingersDown.remove(handle)
        lastFrameTimes[handle] = nil
        syntheticLiftBy[handle] = nil
        assignRecords()
        resolveAndApply()
    }

    public func touchscreen(_ handle: DeviceHandle, produced frame: ContactFrame) {
        guard !hasShutDown, inputs.connected.contains(where: { $0.handle == handle }) else { return }
        if let by = syntheticLiftBy.removeValue(forKey: handle), frame.contacts.isEmpty, frame.time <= by {
            return  // the reader ending the mouse finger: the finger is still down, on the touch interface
        }
        if frame.contacts.isEmpty {
            fingersDown.remove(handle)
            lastFrames[handle] = nil
        } else {
            fingersDown.insert(handle)
            lastFrames[handle] = frame
        }
        lastFrameTimes[handle] = frame.time
        if setUpMode != nil {
            feedSetUpMode(frame, from: handle)
            return
        }
        if let setUp, setUp.handle == handle {
            feedSetUp(frame)
            return
        }
        guard let pipeline = pipelines[handle] else { return }
        if inputs.settings.debugLogging {
            let contacts = frame.contacts.map { "\($0.id)@(\(Self.short($0.position.x)), \(Self.short($0.position.y)))" }
            ModelLog.model.debug("\(handle.description, privacy: .public) frame \(frame.time, privacy: .public): \(contacts.joined(separator: " "), privacy: .public)")
        }
        pipeline.handle(frame)
        publishGestureTesterIfDue(at: frame.time)
        updateTicking()
    }

    // MARK: - For tests

    /// Whether the 60 Hz clock is running.
    var isTicking: Bool { ticker.isRunning }

    /// Ticks every pipeline, and the set-up flow, at the current time, as the timer does.
    func tickPipelines() {
        guard !hasShutDown else { return }
        let time = now()
        for pipeline in Array(pipelines.values) { pipeline.tick(at: time) }
        publishGestureTesterIfDue(at: time)
        tickSetUp(at: time)
        tickSetUpMode(at: time)
        updateTicking()
    }

    /// The set-up flow running now, in set-up mode or outside it, for tests.
    var setUpFlow: SetUpFlow? { setUp?.flow ?? setUpMode?.flow }

    // MARK: - Surroundings

    /// A followed swipe open is closed first: the Spaces it moves may have changed with the displays.
    /// Its touch goes on, and its end is then handled with nothing.
    private func displaysChanged() {
        guard !hasShutDown else { return }
        outputs.dockSwipes.closeIfOpen()
        readDisplays()
        resolveAndApply()
    }

    private func conditionsChanged() {
        guard !hasShutDown else { return }
        readConditions()
        resolveAndApply()
    }

    /// Every touchscreen is released until the Mac wakes, so nothing can start a touch between now
    /// and the sleep itself.
    private func willSleep() {
        guard !hasShutDown else { return }
        ModelLog.model.info("Going to sleep: every touchscreen released")
        outputs.dockSwipes.closeIfOpen()
        inputs.isAsleep = true
        resolveAndApply()
    }

    /// Every touchscreen that should be is taken afresh: its mode written again, its reader reset.
    private func didWake() {
        guard !hasShutDown else { return }
        ModelLog.model.info("Woke: taking the touchscreens again")
        inputs.isAsleep = false
        resolveAndApply()
    }

    /// While the displays reconfigure, the source publishes none for a moment: the displays seen
    /// last are kept for the snapshot (see `AppInputs.lastKnownDisplays`), and nothing maps onto them.
    private func readDisplays() {
        let current = displays.displays
        if current.isEmpty {
            if !inputs.displays.isEmpty { inputs.lastKnownDisplays = inputs.displays }
        } else {
            inputs.lastKnownDisplays = nil
        }
        inputs.displays = current
    }

    /// Keeps what a taken touchscreen says about where its touches come from, for while it is
    /// released (see `AppInputs.lastTakenStatus`).
    private func noteTakenStatus(of touchscreen: ConnectedTouchscreen) {
        let status = touchscreen.status
        guard status.state == .taken, status.touchOrigin != .undetermined else { return }
        inputs.lastTakenStatus[touchscreen.handle] = status
    }

    private func readConditions() {
        inputs.hasAccessibilityAccess = conditions.hasAccessibilityAccess
        inputs.isSessionActive = conditions.isSessionActive
        inputs.isTouchUpRunning = conditions.isTouchUpRunning
        inputs.areMissionControlShortcutsOn = conditions.areMissionControlShortcutsOn
        inputs.launchAtLogin = conditions.launchAtLogin
    }

    /// The sender's logging, with its per-event lines on only while the app has turned its swipe
    /// lines on and the person has asked for a detailed log. A sender made in a test, with its
    /// swipe lines off, stays quiet whatever the setting.
    static func dockSwipeLogging(_ logging: DockSwipeLogging, debugLogging: Bool) -> DockSwipeLogging {
        DockSwipeLogging(swipes: logging.swipes, events: logging.swipes && debugLogging)
    }

    // MARK: - Records and settings

    /// Which record each connected touchscreen uses. A touchscreen with a new record gets the
    /// default settings, and its name; a record's name follows its device's. Saved at once.
    ///
    /// A USB location tells touchscreens apart only when it is not 0 (the device layer gives 0 when
    /// there is none) and exactly one connected touchscreen is at it. Touchscreens at such locations
    /// get their records from `TouchscreenIdentity.assign`. One without a usable location gets the
    /// record under its base ID if no other connected touchscreen has that base ID; otherwise it can't
    /// be told apart, and has no record.
    private func assignRecords() {
        let atLocation = inputs.connected.reduce(into: [UInt32: Int]()) { $0[$1.facts.locationID, default: 0] += 1 }
        func isLocated(_ device: ConnectedTouchscreen) -> Bool {
            device.facts.locationID != 0 && atLocation[device.facts.locationID] == 1
        }
        let located = inputs.connected.filter(isLocated)
        var current: [UInt32: TouchscreenID] = [:]
        for device in located {
            if let record = inputs.records[device.handle] { current[device.facts.locationID] = record }
        }
        let assigned = TouchscreenIdentity.assign(
            connected: located.map(\.facts), current: current, stored: Set(inputs.settings.touchscreens.keys))
        var records: [DeviceHandle: TouchscreenID] = [:]
        for device in located { records[device.handle] = assigned[device.facts.locationID] }

        func base(_ device: ConnectedTouchscreen) -> TouchscreenID {
            TouchscreenIdentity.baseID(
                vendorID: device.facts.vendorID, productID: device.facts.productID, serial: device.facts.serial)
        }
        let withBase = inputs.connected.reduce(into: [TouchscreenID: Int]()) { $0[base($1), default: 0] += 1 }
        var used = Set(records.values)
        for device in inputs.connected where !isLocated(device) {
            let id = base(device)
            guard withBase[id] == 1, !used.contains(id) else { continue }
            records[device.handle] = id
            used.insert(id)
        }
        inputs.records = records

        var changed = false
        for device in inputs.connected {
            guard let id = inputs.records[device.handle] else { continue }
            if var settings = inputs.settings.touchscreens[id] {
                guard settings.lastSeenName != device.facts.name else { continue }
                settings.lastSeenName = device.facts.name
                inputs.settings.touchscreens[id] = settings
            } else {
                var settings = TouchscreenSettings()
                settings.lastSeenName = device.facts.name
                inputs.settings.touchscreens[id] = settings
                ModelLog.model.info("New record \(id.rawValue, privacy: .public) for \(device.handle.description, privacy: .public)")
            }
            changed = true
        }
        if changed { save() }
    }

    /// Saves the settings through the store. Never before they are loaded. A failure is logged once
    /// for as long as it fails for the same reason; the change still applies in memory.
    ///
    /// Internal only for the model's own extensions (`TactileModel+…`); interface code never calls
    /// it: it sends commands through `perform`, which saves what they change.
    func save() {
        guard hasLoadedSettings else {
            ModelLog.model.info("Not saved: the settings haven't been loaded yet")
            return
        }
        do {
            try store.save(inputs.settings)
            saves += 1
            if lastSaveFailure != nil { ModelLog.model.info("Settings saved again") }
            lastSaveFailure = nil
        } catch {
            let reason = String(describing: error)
            if reason != lastSaveFailure {
                loggedSaveFailures += 1
                ModelLog.model.error("Couldn't save the settings: \(reason, privacy: .public)")
            }
            lastSaveFailure = reason
        }
    }

    // MARK: - Resolving and applying

    /// Resolves and applies, again if something changed while applying (taking a touchscreen
    /// reports back its new status at once).
    ///
    /// Internal only for the model's own extensions (`TactileModel+…`); interface code never calls
    /// it: every command sent through `perform` ends with it.
    func resolveAndApply() {
        guard hasStarted, !hasShutDown else { return }
        guard !isApplying else {
            mustApplyAgain = true
            return
        }
        isApplying = true
        defer { isApplying = false }
        var rounds = 0
        repeat {
            mustApplyAgain = false
            applyOnce()
            rounds += 1
        } while mustApplyAgain && rounds < 8 && !hasShutDown
        if mustApplyAgain, !hasShutDown {
            ModelLog.model.error("Still changing after \(rounds) rounds; the next change resolves again")
        }
    }

    private func applyOnce() {
        // A set-up that can't go on ends first, storing nothing; one whose displays changed hears so.
        settleSetUp()
        // A paired display seen now has its name remembered, so it can be named once it has gone.
        let named = Resolver.rememberingDisplayNames(inputs)
        if named != inputs.settings {
            inputs.settings = named
            save()
        }
        rememberWhatTouchscreensGive()
        // Set-up mode: what ends it at once, then what changed in what is connected.
        settleSetUpMode()
        noteSetUpInInputs()
        // Whether a followed swipe could be followed here: the macOS version and the person's
        // gesture setting, which may have changed in System Settings. Cheap: no window server.
        // Read at every round; the conditions watch the gesture setting and say when it changed,
        // so a change in it brings a round of its own.
        inputs.canFollowSwipes = outputs.dockSwipes.isAvailable(.horizontal)
        outputs.dockSwipes.logging = Self.dockSwipeLogging(outputs.dockSwipes.logging,
                                                          debugLogging: inputs.settings.debugLogging)
        let resolution = Resolver.resolve(inputs)
        let time = now()
        let byHandle = Dictionary(resolution.touchscreens.map { ($0.handle, $0) }, uniquingKeysWith: { first, _ in first })

        // 1. Pipelines that stop, before anything is asked of their devices. One whose touches now
        //    land elsewhere is cancelled too, and started afresh below.
        for (handle, pipeline) in pipelines {
            if let next = byHandle[handle], next.id == pipeline.id, let driving = next.driving,
               driving.mapping == pipeline.driving.mapping {
                continue
            }
            pipeline.cancel(at: time, reason: .stoppedDriving)
            pipelines[handle] = nil
        }

        // 2. Device states. Asking may report back at once, and may even shut the model down.
        for touchscreen in resolution.touchscreens where requestedStates[touchscreen.handle] != touchscreen.deviceState {
            guard !hasShutDown else { return }
            requestedStates[touchscreen.handle] = touchscreen.deviceState
            if touchscreen.deviceState == .released {
                fingersDown.remove(touchscreen.handle)
                lastFrames[touchscreen.handle] = nil
                syntheticLiftBy[touchscreen.handle] = nil
            }
            ModelLog.model.info("\(touchscreen.handle.description, privacy: .public): \(touchscreen.deviceState.rawValue, privacy: .public)")
            source.setState(touchscreen.deviceState, for: touchscreen.handle)
        }
        guard !hasShutDown else { return }

        // 3. Pipelines that start, and those that carry on.
        for touchscreen in resolution.touchscreens {
            guard let driving = touchscreen.driving,
                  inputs.connected.contains(where: { $0.handle == touchscreen.handle }) else { continue }
            if let pipeline = pipelines[touchscreen.handle] {
                if pipeline.driving != driving { pipeline.update(driving) }
            } else {
                pipelines[touchscreen.handle] = TouchPipeline(
                    id: touchscreen.id, driving: driving, outputs: outputs,
                    cancelOther: { [weak self] other, time in self?.takeOver(from: other, at: time) },
                    fingersAlreadyDown: hasFingersDown(touchscreen.handle, at: time))
                recordingHandles.remove(touchscreen.handle)
            }
        }
        updateRecorders(resolution)

        logChanges(resolution)
        resolved = byHandle

        // 4. What the interface shows.
        let shown = withGestureTester(resolution, pipelines: pipelines, at: time,
                                      displaysSettling: inputs.lastKnownDisplays != nil)
        if shown != snapshot {
            snapshot = shown
            writeStateFile()
        }
        updateTicking()
    }

    /// After every write of `snapshot`: `steadySnapshot` follows it, when what it holds differs. While
    /// a gesture goes on in the gesture tester only its feed changes, and this doesn't.
    private func snapshotChanged() {
        let steady = snapshot.withoutTesterFeed
        if steady != steadySnapshot {
            steadySnapshot = steady
        }
    }

    // MARK: - Recording frames

    /// `~/Library/Logs/Tactile`, defined once in `TactileFolders`.
    private static var defaultFramesFolder: URL { TactileFolders.frames }

    /// While frames are recorded, each driving touchscreen's pipeline records to a file of its own,
    /// named for the touchscreen: a new file each time recording is switched on or the touchscreen
    /// starts driving. Switched off, every recorder is dropped, which closes its file.
    private func updateRecorders(_ resolution: Resolution) {
        guard inputs.settings.recordsFrames else {
            guard !recordingHandles.isEmpty else { return }
            for pipeline in pipelines.values { pipeline.recorder = nil }
            recordingHandles = []
            ModelLog.model.info("Frame recording stopped")
            return
        }
        for (handle, pipeline) in pipelines where !recordingHandles.contains(handle) {
            recordingHandles.insert(handle)
            let name = resolution.snapshot.touchscreens.first { $0.id == pipeline.id }?.name ?? pipeline.id.rawValue
            if let recorder = FrameRecorder(directory: framesFolder, label: name) {
                pipeline.recorder = recorder
                ModelLog.model.info("\(name, privacy: .public): recording frames to \(recorder.url.path, privacy: .public)")
            } else {
                pipeline.recorder = nil
                ModelLog.model.error("\(name, privacy: .public): couldn't make a file in \(self.framesFolder.path, privacy: .public) to record frames")
            }
        }
    }

    /// Whether `handle`'s last frame had fingers down and came recently enough to believe: after
    /// `TouchPipeline.silenceLimit` with nothing, its lift was lost, as its pipeline judges too.
    /// Internal only for the model's own extensions (`TactileModel+…`).
    func hasFingersDown(_ handle: DeviceHandle, at time: TimeInterval) -> Bool {
        guard fingersDown.contains(handle), let last = lastFrameTimes[handle] else { return false }
        return time - last <= TouchPipeline.silenceLimit
    }

    /// Cancels `handle`'s touch now, as when it stops driving; it gets a fresh pipeline when the model
    /// next resolves.
    private func cancelTouch(of handle: DeviceHandle, at time: TimeInterval, because reason: String) {
        guard let pipeline = pipelines.removeValue(forKey: handle) else { return }
        ModelLog.model.info("\(handle.description, privacy: .public): touch cancelled, \(reason, privacy: .public)")
        pipeline.cancel(at: time, reason: .stoppedDriving)
    }

    /// Another touchscreen took the pointer from `id`'s.
    private func takeOver(from id: TouchscreenID, at time: TimeInterval) {
        for pipeline in pipelines.values where pipeline.id == id {
            pipeline.cancel(at: time, reason: .takenOver)
        }
    }

    private func cancelEveryPipeline() {
        let time = now()
        for pipeline in pipelines.values { pipeline.cancel(at: time, reason: .stoppedDriving) }
        pipelines = [:]
    }

    private func logChanges(_ resolution: Resolution) {
        for touchscreen in resolution.touchscreens {
            let before = resolved[touchscreen.handle]
            let shown = resolution.snapshot.touchscreens.first { $0.id == touchscreen.id }
            let beforeShown = snapshot.touchscreens.first { $0.id == touchscreen.id }
            guard before?.mode != touchscreen.mode || before?.rule != touchscreen.rule
                    || beforeShown?.status != shown?.status else { continue }
            let name = shown?.name ?? touchscreen.id.rawValue
            let status = shown.map { String(describing: $0.status) } ?? "?"
            ModelLog.model.info("\(name, privacy: .public) [\(touchscreen.id.rawValue, privacy: .public)]: \(before?.mode.rawValue ?? "new", privacy: .public) → \(touchscreen.mode.rawValue, privacy: .public) (\(touchscreen.rule.rawValue, privacy: .public)); \(status, privacy: .public)")
        }
    }

    func writeStateFile() {
        guard let stateFile, !hasShutDown else { return }
        do {
            try stateFile.write(snapshot)
        } catch {
            ModelLog.model.error("Couldn't write the state file: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Ticks

    /// 60 Hz while a pipeline needs ticks; else 10 Hz while a set-up or set-up mode runs, in any step
    /// or stage; else none.
    private func updateTicking() {
        let touch = !hasShutDown && (pipelines.values.contains { $0.needsTicks } || gestureTesterNeedsTicks)
        let settingUp = !hasShutDown && (setUp != nil || setUpMode != nil)
        if touch || settingUp {
            ticker.start(every: touch ? TickRate.touchInterval : TickRate.setUpInterval) { [weak self] in
                self?.tickPipelines()
            }
        } else if ticker.isRunning {
            ticker.stop()
        }
    }

    // MARK: - Set-up

    /// Starts a set-up of touchscreen `id`, if none is running and it can run one now.
    private func beginSetUp(_ id: TouchscreenID, _ purpose: SetUpPurpose) {
        guard hasStarted else { return }
        if let running = setUp {
            ModelLog.model.info("Set-up of \(id.rawValue, privacy: .public) not begun: one is running for \(running.flow.snapshot.touchscreen.rawValue, privacy: .public)")
            return
        }
        let time = now()
        guard let handle = inputs.connected.first(where: { inputs.records[$0.handle] == id })?.handle,
              let start = Resolver.setUpStart(for: id, purpose: purpose, in: inputs),
              var flow = SetUpFlow(start, at: time)
        else {
            ModelLog.model.info("Set-up of \(id.rawValue, privacy: .public) (\(purpose.rawValue, privacy: .public)) can't begin now")
            return
        }
        ModelLog.model.info("\(Self.setUpBeganLine(start), privacy: .public)")
        // A finger already resting when it begins is not a touch: the flow sees it first, timed
        // before its start, and ignores it until it lifts.
        if hasFingersDown(handle, at: time), let frame = lastFrames[handle] { _ = flow.handle(frame) }
        setUp = (flow, handle)
        setUpDisplays = inputs.displays
        resolveAndApply()
    }

    /// One of the person's steps in the running set-up, if one is running.
    /// `tooSoonAs`: for Done and Redo, the name a line gives the command when the flow ignores it as
    /// too soon after the check appeared (see `tooSoonLine`).
    private func stepSetUp(_ name: String, tooSoonAs: String? = nil, _ step: (inout SetUpFlow) -> SetUpFlow.Event) {
        guard var current = setUp else { return }
        ModelLog.model.info("Set-up: \(name, privacy: .public)")
        // The flow times a change a command makes at its next moment: it is given that moment at
        // once, so the change is timed when the person made it, not at the next tick.
        let time = now()
        var event = current.flow.tick(at: time)
        if event == .stillRunning, let tooSoonAs, let line = Self.tooSoonLine(tooSoonAs, after: current.flow) {
            ModelLog.model.info("\(line, privacy: .public)")
        }
        if event == .stillRunning { event = step(&current.flow) }
        if event == .stillRunning { event = current.flow.tick(at: time) }
        setUp = current
        // Done, Cancel, or the flow's own time limit: the person's ending.
        settled(event, endedByThePerson: true)
        resolveAndApply()
    }

    /// The line for a Done or Redo (`command`) that `flow`, ticked at the command's moment, will
    /// ignore because the check has only just appeared; nil when it will take it, or isn't showing
    /// the check. So a Done pressed too soon doesn't read like a hang in the log.
    static func tooSoonLine(_ command: String, after flow: SetUpFlow) -> String? {
        flow.isCheckTooRecent ? "Set-up: \(command) ignored, the check has only just appeared" : nil
    }

    /// A frame of the touchscreen being set up: for the flow, and in the check step for its circles.
    private func feedSetUp(_ frame: ContactFrame) {
        guard var current = setUp else { return }
        let before = current.flow.snapshot
        let roundBefore = current.flow.lastCornersReport?.round
        let event = current.flow.handle(frame)
        setUp = current
        // A round of the corners ends only on a frame: its taps' distances, for tuning the limits.
        if let report = current.flow.lastCornersReport, report.round != roundBefore {
            ModelLog.model.info("\(report.logLine, privacy: .public)")
        }
        // A frame ends a flow only by its time limit, which the person let pass.
        settled(event, endedByThePerson: true)
        if let current = setUp { drawSetUpCircles(frame, with: current.flow.checkMapping) }
        if setUp?.flow.snapshot != before { resolveAndApply() }
    }

    private func tickSetUp(at time: TimeInterval) {
        guard var current = setUp else { return }
        let before = current.flow.snapshot
        let event = current.flow.tick(at: time)
        setUp = current
        settled(event, endedByThePerson: true)  // only its time limit
        if setUp?.flow.snapshot != before { resolveAndApply() }
    }

    /// At the start of every round: a set-up whose touchscreen can no longer run it (gone, released,
    /// unreadable) ends, storing nothing; one whose displays changed is told, which may end it. The
    /// moment of a reconfiguration with no displays at all is not a change for it: it hears the
    /// displays once they have settled.
    private func settleSetUp() {
        guard var current = setUp else { return }
        let id = current.flow.snapshot.touchscreen
        // Its own time limit first, which is the person's ending; then what isn't.
        var event = current.flow.tick(at: now())
        if event != .stillRunning {
            setUp = current
            settled(event, endedByThePerson: true)
            return
        }
        if !inputs.connected.contains(where: { $0.handle == current.handle }) || inputs.records[current.handle] != id {
            ModelLog.model.info("Set-up of \(id.rawValue, privacy: .public) ends: the touchscreen has gone")
            event = current.flow.cancel()
        } else if !Resolver.canRunSetUp(id, inputs) {
            ModelLog.model.info("Set-up of \(id.rawValue, privacy: .public) ends: the touchscreen can't be taken or read now")
            event = current.flow.cancel()
        } else if !inputs.displays.isEmpty, inputs.displays != setUpDisplays {
            setUpDisplays = inputs.displays
            event = current.flow.displaysChanged(inputs.displays, at: now())
        }
        setUp = current
        settled(event, endedByThePerson: false)
    }

    /// What the flow answered: when it has finished, the set-up ends, and its outcome, if any, is
    /// stored in one change. `endedByThePerson`: Done, Cancel, or the flow's own time limit, which
    /// count as the offer made (see `Resolver.applySetUp`); not a lock, sleep, quitting, unplugging,
    /// Tactile off, Accessibility gone or the display gone.
    private func settled(_ event: SetUpFlow.Event, endedByThePerson: Bool) {
        guard case .finished(let outcome) = event, let current = setUp else {
            if setUp?.flow.checkMapping == nil { hideSetUpCircles() }
            return
        }
        let shown = current.flow.snapshot
        setUp = nil
        hideSetUpCircles()
        let settings = Resolver.applySetUp(outcome, purpose: shown.purpose, to: shown.touchscreen, in: inputs,
                                           endedByThePerson: endedByThePerson)
        ModelLog.model.info("\(Self.setUpEndedLine(shown.touchscreenName, shown.touchscreen, shown.purpose, outcome), privacy: .public)")
        if settings != inputs.settings {
            inputs.settings = settings
            save()
        }
    }

    /// In the check step, the touches shown where they land, mapped with the flow's check mapping
    /// (`mapping`; nil outside the check step), on the display whose picture it is. They never reach
    /// a pipeline or the arbiter. Internal only for the model's own extensions (`TactileModel+…`).
    func drawSetUpCircles(_ frame: ContactFrame, with mapping: TouchMapping?) {
        guard let mapping else {
            hideSetUpCircles()
            return
        }
        if frame.contacts.isEmpty {
            if let shown = setUpCirclesOn { outputs.showCircles([:], hollow: [], ringed: [], onDisplay: shown) }
            setUpCirclesOn = nil
            return
        }
        let displayID = (mapping.content ?? mapping.display).displayID
        if let shown = setUpCirclesOn, shown != displayID { outputs.hideCircles(onDisplay: shown) }
        var points: [Int: CGPoint] = [:]
        for contact in frame.contacts where points[contact.id] == nil {
            points[contact.id] = mapping.displayPoint(forGlass: contact.position)
        }
        outputs.showCircles(points, hollow: [], ringed: [], onDisplay: displayID)
        setUpCirclesOn = displayID
    }

    /// Hides the check step's circles, if they are showing. Internal only for the model's own
    /// extensions (`TactileModel+…`).
    func hideSetUpCircles() {
        guard let shown = setUpCirclesOn else { return }
        outputs.hideCircles(onDisplay: shown)
        setUpCirclesOn = nil
    }

    // MARK: - Describing

    private static func describe(_ touchscreen: ConnectedTouchscreen) -> String {
        let facts = touchscreen.facts
        return "\(touchscreen.handle) \"\(facts.name)\" \(String(format: "%04x:%04x", facts.vendorID, facts.productID)) serial \"\(facts.serial)\" at \(String(format: "%08x", facts.locationID)), \(touchscreen.maxContacts) contacts, mouse interface \(touchscreen.hasMouseInterface ? "yes" : "no")"
    }

    /// A touchscreen by its USB ID and location, never its record's ID, which holds its serial:
    /// "222a:0001 at 01141000".
    static func usbAndLocation(_ id: TouchscreenID, _ inputs: AppInputs) -> String {
        guard let handle = inputs.records.first(where: { $0.value == id })?.key,
              let facts = inputs.connected.first(where: { $0.handle == handle })?.facts else { return "a touchscreen" }
        return String(format: "%04x:%04x at %08x", facts.vendorID, facts.productID, facts.locationID)
    }

    private static func describe(_ status: DeviceStatus) -> String {
        "\(status.state.rawValue), input mode \(status.inputMode.rawValue), touches from \(status.touchOrigin.rawValue), exclusive \(status.exclusive.rawValue)"
    }

    private static func short(_ value: CGFloat) -> String {
        String(format: "%.4f", Double(value))
    }
}
