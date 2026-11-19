// Everything known → what each touchscreen does, and what the interface is shown. Pure.

import CoreGraphics
import Foundation
import TactileDevices
import TactileGestures
import TactileScreens

/// Everything the model knows: the settings, the touchscreens and displays connected now, and the
/// state of the system.
public struct AppInputs: Equatable, Sendable {
    public var appVersion: String
    public var settings: TactileSettings
    /// Every connected touchscreen, in the order they connected.
    public var connected: [ConnectedTouchscreen]
    /// Which record each connected touchscreen uses, by its handle. A touchscreen absent from it has
    /// no record: it can't be told apart from another connected touchscreen (no usable USB
    /// location, and another with the same vendor, product and serial). It is held, shown under a
    /// provisional ID that is never stored, and commands for it change nothing.
    public var records: [DeviceHandle: TouchscreenID]
    /// Every connected display.
    public var displays: [DisplayFacts]
    /// The status each connected touchscreen last reported while taken, once the origin of its
    /// touches was known, by handle. Kept while it is released, which resets its status: what
    /// describes the device itself (`oneFingerOnly` and `multiFingerAvailable`, `macOSIgnoresIt`)
    /// still knows it then.
    public var lastTakenStatus: [DeviceHandle: DeviceStatus]
    public var hasAccessibilityAccess: Bool
    /// False while the screen is locked or the user is switched out.
    public var isSessionActive: Bool
    /// From the system's "will sleep" until its "did wake".
    public var isAsleep: Bool
    public var isTouchUpRunning: Bool
    public var areMissionControlShortcutsOn: Bool
    /// The settings file couldn't be used when Tactile started, and Tactile is on the defaults.
    public var settingsWereSetAside: Bool
    public var isQuitting: Bool
    /// The set-up running now, as its flow shows it; nil when none is. Its touchscreen is setting up.
    public var setUp: SetUpSnapshot?
    /// Set-up mode, as its session shows it; nil when it is off. While it is on, every connected
    /// touchscreen that can run a set-up is setting up, and none drives.
    public var setUpMode: SetUpModeSnapshot?
    /// While the displays reconfigure (the source publishes none for a moment), the displays seen
    /// last: the snapshot shows them, so the interface doesn't flash "not connected", while nothing
    /// is mapped onto them and every touchscreen is held. Nil otherwise.
    public var lastKnownDisplays: [DisplayFacts]?
    /// Whether swipes left and right can follow the fingers on this Mac: the Dock-swipe sender's
    /// `isAvailable(.horizontal)`, which reads the macOS version and the person's gesture setting.
    public var canFollowSwipes: Bool
    /// Whether Tactile opens at login, as the system says.
    public var launchAtLogin: LaunchAtLogin
    /// The touchscreen checks' claims, each on one touchscreen: Tactile lets go of a touchscreen
    /// while any claim on it is held (see `AppCommand.beginSupportCheck`).
    public var supportChecks: [UUID: TouchscreenID]
    /// The connections a touchscreen check found had stopped answering (see
    /// `AppCommand.endSupportCheck`): each is left released until it goes, Tactile is turned off and
    /// on, or the Mac sleeps and wakes.
    public var stoppedAnswering: Set<DeviceHandle>

    public init(
        appVersion: String, settings: TactileSettings, connected: [ConnectedTouchscreen],
        records: [DeviceHandle: TouchscreenID], displays: [DisplayFacts], lastTakenStatus: [DeviceHandle: DeviceStatus] = [:],
        hasAccessibilityAccess: Bool, isSessionActive: Bool, isAsleep: Bool, isTouchUpRunning: Bool,
        areMissionControlShortcutsOn: Bool, settingsWereSetAside: Bool, isQuitting: Bool, setUp: SetUpSnapshot? = nil,
        lastKnownDisplays: [DisplayFacts]? = nil, canFollowSwipes: Bool = false, launchAtLogin: LaunchAtLogin = .unavailable,
        setUpMode: SetUpModeSnapshot? = nil, supportChecks: [UUID: TouchscreenID] = [:],
        stoppedAnswering: Set<DeviceHandle> = []
    ) {
        self.appVersion = appVersion
        self.settings = settings
        self.connected = connected
        self.records = records
        self.displays = displays
        self.lastTakenStatus = lastTakenStatus
        self.hasAccessibilityAccess = hasAccessibilityAccess
        self.isSessionActive = isSessionActive
        self.isAsleep = isAsleep
        self.isTouchUpRunning = isTouchUpRunning
        self.areMissionControlShortcutsOn = areMissionControlShortcutsOn
        self.settingsWereSetAside = settingsWereSetAside
        self.isQuitting = isQuitting
        self.setUp = setUp
        self.setUpMode = setUpMode
        self.lastKnownDisplays = lastKnownDisplays
        self.canFollowSwipes = canFollowSwipes
        self.launchAtLogin = launchAtLogin
        self.supportChecks = supportChecks
        self.stoppedAnswering = stoppedAnswering
    }
}

/// How a driving touchscreen's touches are carried out: everything its pipeline needs.
public struct Driving: Equatable, Sendable {
    /// Glass points to display points, and display points to the desktop.
    public var mapping: TouchMapping
    /// The glass's size, for the gesture engine's thresholds. Never zero.
    public var surfaceSizeMM: CGSize
    /// Where the picture is on the desktop, for the pointer keeper and for scroll distances: the
    /// frame of the display it mirrors, when it mirrors one, else its own.
    public var displayFrame: CGRect
    /// The display its circles are drawn on: where the picture is, as for `displayFrame`.
    public var displayID: UInt32
    /// The gestures as stored, long-press and rotate included; when its touches come from its mouse
    /// interface, `GestureOptions.oneFingerOnly(keeping:)` of them: every multi-finger gesture off,
    /// long-press as set.
    public var options: GestureOptions
    public var oneFinger: OneFingerMode
    public var pointerReturn: PointerReturn
    public var showsCircles: Bool
    /// Which contacts its filter refuses: palms, and touches that start near an edge.
    public var rejection: RejectionRules
    /// Whether three- and four-finger swipes left and right follow the fingers, the general
    /// setting: read at the start of each session (see `TouchPipeline`).
    public var swipesFollowFingers: Bool

    public init(
        mapping: TouchMapping, surfaceSizeMM: CGSize, displayFrame: CGRect, displayID: UInt32, options: GestureOptions,
        oneFinger: OneFingerMode, pointerReturn: PointerReturn, showsCircles: Bool, rejection: RejectionRules = RejectionRules(),
        swipesFollowFingers: Bool = false
    ) {
        self.mapping = mapping
        self.surfaceSizeMM = surfaceSizeMM
        self.displayFrame = displayFrame
        self.displayID = displayID
        self.options = options
        self.oneFinger = oneFinger
        self.pointerReturn = pointerReturn
        self.showsCircles = showsCircles
        self.rejection = rejection
        self.swipesFollowFingers = swipesFollowFingers
    }
}

/// Which row of the mode table decided a touchscreen's mode, for the log.
public enum ModeRule: String, Sendable {
    case quitting, tactileOff, noAccessibility, sessionNotActive, asleep, supportCheck, stoppedAnswering, noRecord, settingUp,
        offLeftToMacOS, offIgnoringTouches, notPaired, displayNotConnected, touchesUnreadable, mouseModeShared, paired
}

/// What one connected touchscreen should be doing.
public struct ResolvedTouchscreen: Equatable, Sendable {
    public var handle: DeviceHandle
    public var id: TouchscreenID
    public var mode: TouchscreenMode
    public var deviceState: DeviceState
    /// Exactly when `mode` is `.driving`.
    public var driving: Driving?
    /// The row of the mode table that applied.
    public var rule: ModeRule

    public init(
        handle: DeviceHandle, id: TouchscreenID, mode: TouchscreenMode, deviceState: DeviceState, driving: Driving?,
        rule: ModeRule
    ) {
        self.handle = handle
        self.id = id
        self.mode = mode
        self.deviceState = deviceState
        self.driving = driving
        self.rule = rule
    }
}

public struct Resolution: Equatable, Sendable {
    /// One for each connected touchscreen, in the order they connected.
    public var touchscreens: [ResolvedTouchscreen]
    public var snapshot: AppSnapshot

    public init(touchscreens: [ResolvedTouchscreen], snapshot: AppSnapshot) {
        self.touchscreens = touchscreens
        self.snapshot = snapshot
    }
}

/// Turns everything known into what each touchscreen does and what the interface shows, and works
/// out what a command does to the settings. Pure: the model applies and saves what it answers.
///
/// **The mode of each connected touchscreen**, by the first row that applies:
///
/// | # | When | Mode | Device | Status |
/// |---|---|---|---|---|
/// | 1 | Quitting | released | released | as it would otherwise be |
/// | 2 | Tactile is off | released | released | `tactileOff` |
/// | 3 | No Accessibility access | released | released | `accessibilityMissing` |
/// | 4 | The session is not active | released | released | as it would otherwise be |
/// | 4a | The Mac is going to sleep or asleep | released | released | as it would otherwise be |
/// | 4b | A touchscreen check holds a claim on it (`supportChecks`) | released | released | as it would otherwise be |
/// | 4b′ | A touchscreen check found this connection had stopped answering (`stoppedAnswering`) | released | released | `stoppedAnswering` |
/// | 4c | No record: it can't be told apart from another connected touchscreen | held | taken | `notSetUp` |
/// | 4d | A set-up is running for it, or set-up mode is on, and it can run one (see `canRunSetUp`) | settingUp | taken | as it would otherwise be |
/// | 4e | Set-up mode is on, and it can't run a set-up | held | taken | as it would otherwise be |
/// | 5 | Off, "leave it to macOS" | released | released | `off` |
/// | 6 | Off, "ignore touches" | held | taken | `off` |
/// | 7 | Not paired | held | taken | `notSetUp` |
/// | 8 | Paired; no display for certain, or no mapping to it | held | taken | `displayNotConnected` |
/// | 8a | Paired and mapped, but its touches can't be read | held | taken | `pairedWith` |
/// | 8b | One finger from its mouse interface, and not held exclusively: macOS acts on it already | held | taken | `pairedWith` |
/// | 9 | Otherwise | driving | taken | `pairedWith` |
///
/// A diagonal override outside `SurfaceSize.plausibleDiagonals` is ignored everywhere: for the glass's size, in
/// display labels, and in the snapshot.
///
/// So set-up works on a touchscreen that is off or unpaired, and anything that releases every
/// touchscreen (rows 1–4a) ends it: the model ends the flow, storing nothing, when its touchscreen
/// can no longer run it, and ends set-up mode. While set-up mode is on no touchscreen drives: every
/// touch is set-up input (rows 4d and 4e). The touchscreen check's touchscreen is let go (row 4b),
/// so the check can take it exactly as Tactile does, and can't run a set-up until the check ends.
/// One the check found had stopped answering stays let go (row 4b′), whatever else changes, and runs
/// no set-up: nothing takes it on the main thread until it is plugged in again, Tactile is turned off
/// and on, or the Mac sleeps and wakes.
///
/// Never a guess: a pairing's display is found by `DisplayMatcher` alone, given every stored
/// pairing, of connected and remembered touchscreens alike, which never gives two touchscreens one
/// display. Only the connected touchscreens' answers are used.
public enum Resolver {

    public static func resolve(_ inputs: AppInputs) -> Resolution {
        let world = World(inputs)
        // While the displays reconfigure, what is shown is the displays seen last; what is done, none.
        var shownInputs = inputs
        if inputs.displays.isEmpty, let lastKnown = inputs.lastKnownDisplays { shownInputs.displays = lastKnown }
        let shown = shownInputs.displays == inputs.displays ? world : World(shownInputs)
        var resolved: [ResolvedTouchscreen] = []
        var snapshots: [TouchscreenSnapshot] = []
        let refusal = setUpModeRefusal(inputs, scene: setUpScene(inputs, world: world, shown: shown).scene)?.refusal
        let modeCouldBegin = refusal == nil
        for screen in world.connectedScreens {
            let outcome = world.outcome(of: screen)
            resolved.append(ResolvedTouchscreen(
                handle: screen.device.handle, id: screen.id, mode: outcome.mode, deviceState: outcome.deviceState,
                driving: outcome.driving, rule: outcome.rule))
            snapshots.append(shown.snapshot(of: screen, mode: outcome.mode, setUpModeCouldBegin: modeCouldBegin))
        }
        for screen in world.rememberedScreens {
            snapshots.append(shown.snapshot(of: screen, mode: nil, setUpModeCouldBegin: modeCouldBegin))
        }
        let snapshot = AppSnapshot(
            appVersion: inputs.appVersion,
            isOn: inputs.settings.isOn,
            warnings: warnings(inputs),
            touchscreens: snapshots,
            displays: shown.sortedDisplays.map(shown.snapshot(of:)),
            debugLogging: inputs.settings.debugLogging,
            setUp: inputs.setUp,
            setUpMode: inputs.setUpMode,
            offerSetUpTo: offerSetUpTo(inputs, shown: shown, snapshots: snapshots),
            setUpModeRefusal: refusal,
            gestureTester: nil,
            recordsFrames: inputs.settings.recordsFrames,
            swipesFollowFingers: inputs.settings.swipesFollowFingers,
            canFollowSwipes: inputs.canFollowSwipes,
            launchAtLogin: inputs.launchAtLogin)
        return Resolution(touchscreens: resolved, snapshot: snapshot)
    }

    // MARK: - Set-up

    /// Whether the connected touchscreen `id` can run a set-up now, whatever its purpose: it has a
    /// record; Tactile could take it (not quitting, on, with Accessibility access, the session
    /// active, not asleep); its touches can be read; and macOS doesn't act on them too (a mouse-mode
    /// panel that couldn't be held exclusively would move the pointer and click under the flow).
    /// The model ends a running flow, storing nothing, as soon as this is false for its touchscreen.
    public static func canRunSetUp(_ id: TouchscreenID, _ inputs: AppInputs) -> Bool {
        let world = World(inputs)
        guard let screen = world.connectedScreens.first(where: { $0.id == id }) else { return false }
        return world.canRunSetUp(screen)
    }

    /// What a flow for touchscreen `id` with `purpose` starts from; nil when it can't run one:
    /// - `.full`: never. A full set-up runs only in set-up mode, on the display chosen there
    ///   (`SetUpSession`, which starts it from `setUpScene`).
    /// - `.calibrate` and `.test`: its own display alone, which must be connected and found for
    ///   certain; and its pairing as it is.
    /// Every connected display goes in `allDisplays`, those that mirror another included.
    public static func setUpStart(for id: TouchscreenID, purpose: SetUpPurpose, in inputs: AppInputs) -> SetUpFlow.Start? {
        guard !isProvisional(id) else { return nil }
        let world = World(inputs)
        guard let screen = world.connectedScreens.first(where: { $0.id == id }) else { return nil }
        return world.setUpStart(for: screen, purpose: purpose)
    }

    /// The settings after a set-up of touchscreen `id` with `purpose` finished with `outcome`, in one
    /// change, so that one Done writes the settings file once:
    /// - an outcome: the pairing with its display (every other claim on that display cleared, as
    ///   `pair` clears them), named as the display is now when it has a name of its own, else as
    ///   remembered for the same display; its orientation and alignment; its diagonal, except for a
    ///   calibration, which keeps the stored one; and, for `.full`, `wasOfferedSetUp`;
    /// - nil: nothing, except that a `.full` set-up the person ended (`endedByThePerson`: Cancel,
    ///   or the flow's own time limit) marks it offered. An ending the person didn't choose (a lock,
    ///   sleep, quitting, unplugging, Tactile off, Accessibility gone, the display gone) leaves the
    ///   offer to be made again.
    /// Unchanged for a touchscreen with no record.
    public static func applySetUp(_ outcome: SetUpFlow.Outcome?, purpose: SetUpPurpose, to id: TouchscreenID,
                                  in inputs: AppInputs, endedByThePerson: Bool) -> TactileSettings {
        var settings = inputs.settings
        guard !isProvisional(id) else { return settings }
        let world = World(inputs)
        guard var screen = world.settings(of: id) else { return settings }
        guard let outcome else {
            if purpose == .full, endedByThePerson, !screen.wasOfferedSetUp {
                screen.wasOfferedSetUp = true
                settings.touchscreens[id] = screen
            }
            return settings
        }
        let display = inputs.displays.first { DisplayIdentity($0) == outcome.display }
            ?? world.connectedScreens.first { $0.id == id }.flatMap(world.matchedDisplay(of:))
        if let display {
            for other in world.claimants(of: display) where other != id { settings.touchscreens[other]?.unpair() }
        }
        if isUUID(outcome.display.uuid) {
            for (other, record) in settings.touchscreens where other != id && record.pairing?.display.uuid == outcome.display.uuid {
                settings.touchscreens[other]?.unpair()
            }
        }
        let remembered = screen.pairing?.display == outcome.display ? screen.pairing?.displayName ?? "" : ""
        let name = display.flatMap { World.nameToRemember(for: $0, remembered: remembered) } ?? remembered
        screen.pairing = Pairing(display: outcome.display, orientation: outcome.orientation, alignment: outcome.alignment,
                                 displayName: name)
        if purpose != .calibrate { screen.diagonalInches = usableDiagonal(outcome.diagonalInches) }
        if purpose == .full { screen.wasOfferedSetUp = true }
        settings.touchscreens[id] = screen
        return settings
    }

    /// The settings after `command`. A command that can't apply (an unknown touchscreen, a display
    /// that isn't connected) gives the settings unchanged.
    public static func apply(_ command: AppCommand, to inputs: AppInputs) -> TactileSettings {
        var settings = inputs.settings
        // A provisional ID is never a record, whatever the settings file holds under it.
        if let id = touchscreen(named: command), isProvisional(id) { return settings }
        // While a set-up runs, its Done stores a pairing, a fit and a size: nothing else changes
        // those meanwhile, for any touchscreen, so Done never undoes a change or is undone by one.
        // The same all the while set-up mode is on, between its flows too.
        if inputs.setUp != nil || inputs.setUpMode != nil, changesAFit(command) { return settings }
        let world = World(inputs)

        /// Changes the settings of touchscreen `id`, a connected one or one with a record; a
        /// connected one without a record gets one only if the change changes something.
        func change(_ id: TouchscreenID, _ make: (inout TouchscreenSettings) -> Void) {
            guard let before = world.settings(of: id) else { return }
            var after = before
            make(&after)
            if after != before { settings.touchscreens[id] = after }
        }

        switch command {
        case .setOn(let isOn):
            settings.isOn = isOn
        case .setTouchscreenOn(let id, let isOn):
            change(id) { $0.isOn = isOn }
        case .setWhenOff(let id, let whenOff):
            change(id) { $0.whenOff = whenOff }
        case .rename(let id, let name):
            change(id) { $0.customName = nonBlank(name) }
        case .pair(let id, let displayID):
            guard world.settings(of: id) != nil, let display = world.pairableDisplay(displayID) else { break }
            for other in world.claimants(of: display) where other != id {
                settings.touchscreens[other]?.unpair()
            }
            let identity = DisplayIdentity(display)
            let alreadyThere = world.isConnected(id) && world.matched[id] == displayID
            change(id) { screen in
                if alreadyThere, screen.pairing != nil {
                    // The same display, perhaps found by its fingerprint after macOS changed its
                    // UUID: keep the fit, and remember the identity as it is now.
                    screen.pairing?.display = identity
                } else {
                    screen.pair(with: identity)
                }
            }
        case .unpair(let id):
            change(id) { $0.unpair() }
        case .setOrientation(let id, let orientation):
            change(id) { $0.pairing?.orientation = orientation }
        case .setDiagonal(let id, let inches):
            change(id) { $0.diagonalInches = usableDiagonal(inches) }
        case .forget(let id):
            guard !world.isConnected(id) else { break }
            settings.touchscreens[id] = nil
        case .renameDisplay(let uuid, let name):
            guard isUUID(uuid) else { break }
            settings.displayNames[uuid] = nonBlank(name)
        case .setDebugLogging(let isOn):
            settings.debugLogging = isOn
        case .setOneFinger(let id, let mode):
            // nil: back to the default for that touchscreen (see `World.oneFingerInForce`).
            change(id) { $0.oneFinger = mode }
        case .setPointerReturn(let id, let pointerReturn):
            change(id) { $0.pointerReturn = pointerReturn }
        case .setShowsCircles(let id, let isOn):
            change(id) { $0.showsCircles = isOn }
        case .setGestures(let id, let gestures):
            // As given, even on a one-finger-only touchscreen: what is stored is what the person
            // set; what is in force is worked out when it drives.
            change(id) { $0.gestures = gestures }
        case .setRejection(let id, let rules):
            change(id) { $0.rejection = rules }
        case .copyBehaviour(let from, let to):
            // `to` was checked above; `from` must be a record too, and another touchscreen.
            guard from != to, !isProvisional(from), let source = world.settings(of: from) else { break }
            change(to) { $0.copyBehaviour(from: source) }
        case .resetBehaviour(let id):
            change(id) { $0.resetBehaviour() }
        case .clearCalibration(let id):
            change(id) { $0.pairing?.alignment = .wholeGlass }
        case .declineSetUp(let id):
            change(id) { $0.wasOfferedSetUp = true }
        case .setRecordsFrames(let isOn):
            settings.recordsFrames = isOn
        case .setSwipesFollowFingers(let isOn):
            settings.swipesFollowFingers = isOn
        case .askForAccessibility, .beginSetUp, .setUpConfirmSize, .setUpRedo, .setUpDone, .cancelSetUp,
             .copyDiagnostics, .setLaunchAtLogin, .openLoginItemsSettings, .beginSetUpMode, .setUpChoose, .setUpBack,
             .openGestureTester, .closeGestureTester, .setGestureTesterPerformsSwipes, .clearGestureTester,
             .beginSupportCheck, .endSupportCheck:
            // Not changes to the settings: the model carries these out itself (the system keeps
            // whether Tactile opens at login).
            break
        }
        return settings
    }

    /// The settings with each pairing's remembered display name (`Pairing.displayName`) brought up
    /// to date: a touchscreen whose paired display is connected, as far as is certain, remembers the
    /// name macOS gives it now, so that the display can still be named after it has gone and Tactile
    /// has been relaunched. A display that mirrors another has no name of its own, and its fallback
    /// ("Display") is never remembered. Unchanged when every name is already up to date.
    public static func rememberingDisplayNames(_ inputs: AppInputs) -> TactileSettings {
        var settings = inputs.settings
        for (id, name) in World(inputs).displayNamesSeen() where settings.touchscreens[id]?.pairing?.displayName != name {
            settings.touchscreens[id]?.pairing?.displayName = name
        }
        return settings
    }

    /// The settings with each connected touchscreen's `lastGaveOneFinger` brought up to date, as it
    /// last said while taken (`World.givesOneFinger`): `true` for touches from its mouse interface,
    /// `false` for touches from its touch interface. One that hasn't said, or whose touches can't be
    /// read, keeps what is remembered; one with no record has nothing to keep it in. Unchanged when
    /// everything is already up to date, so the model writes it only when it changes.
    public static func rememberingWhatTouchscreensGive(_ inputs: AppInputs) -> TactileSettings {
        var settings = inputs.settings
        let world = World(inputs)
        for screen in world.connectedScreens where screen.hasRecord && !isProvisional(screen.id) {
            guard let gives = world.givesOneFinger(screen.device),
                  settings.touchscreens[screen.id] != nil,
                  settings.touchscreens[screen.id]?.lastGaveOneFinger != gives
            else { continue }
            settings.touchscreens[screen.id]?.lastGaveOneFinger = gives
        }
        return settings
    }

    /// Whether `id` is a provisional ID (see `World.provisionalID`), never a record. A key of this form
    /// in the settings file, which only a hand could have put there, is left alone: never shown,
    /// never matched, never changed.
    static func isProvisional(_ id: TouchscreenID) -> Bool {
        id.rawValue.hasPrefix("#")
    }

    /// Whether `command` changes a pairing, an orientation, an alignment or a diagonal: refused
    /// while a set-up runs.
    static func changesAFit(_ command: AppCommand) -> Bool {
        switch command {
        case .pair, .unpair, .forget, .setOrientation, .clearCalibration, .setDiagonal:
            return true
        case .setOn, .setTouchscreenOn, .setWhenOff, .rename, .renameDisplay, .setDebugLogging, .askForAccessibility,
             .setOneFinger, .setPointerReturn, .setShowsCircles, .setGestures, .setRejection, .copyBehaviour,
             .resetBehaviour, .beginSetUp, .setUpConfirmSize, .setUpRedo, .setUpDone, .cancelSetUp, .declineSetUp,
             .setRecordsFrames, .copyDiagnostics, .setSwipesFollowFingers, .setLaunchAtLogin, .openLoginItemsSettings,
             .beginSetUpMode, .setUpChoose, .setUpBack, .openGestureTester, .closeGestureTester,
             .setGestureTesterPerformsSwipes, .clearGestureTester, .beginSupportCheck, .endSupportCheck:
            return false
        }
    }

    /// The touchscreen a command changes, if it changes one. For `copyBehaviour` that is `to`;
    /// `apply` checks `from` itself.
    static func touchscreen(named command: AppCommand) -> TouchscreenID? {
        switch command {
        case .setTouchscreenOn(let id, _), .setWhenOff(let id, _), .rename(let id, _), .pair(let id, _), .unpair(let id),
             .setOrientation(let id, _), .setDiagonal(let id, _), .forget(let id):
            return id
        case .setOneFinger(let id, _), .setPointerReturn(let id, _), .setShowsCircles(let id, _), .setGestures(let id, _),
             .setRejection(let id, _), .copyBehaviour(_, let id), .resetBehaviour(let id), .clearCalibration(let id),
             .beginSetUp(let id, _), .declineSetUp(let id), .openGestureTester(let id), .beginSupportCheck(let id, _):
            return id
        case .setOn, .renameDisplay, .setDebugLogging, .askForAccessibility, .setUpConfirmSize, .setUpRedo, .setUpDone,
             .cancelSetUp, .setRecordsFrames, .copyDiagnostics, .setSwipesFollowFingers, .setLaunchAtLogin,
             .openLoginItemsSettings, .beginSetUpMode, .setUpChoose, .setUpBack, .closeGestureTester,
             .setGestureTesterPerformsSwipes, .clearGestureTester, .endSupportCheck:
            return nil
        }
    }

    /// `inches`, if it is a diagonal override the engine uses: within `SurfaceSize.plausibleDiagonals`,
    /// the diagonals a person can set. Anything else clears the override, and one outside the range
    /// in a settings file is ignored: for the glass's size, in labels and in the snapshot.
    fileprivate static func usableDiagonal(_ inches: Double?) -> Double? {
        inches.flatMap { SurfaceSize.plausibleDiagonals.contains($0) ? $0 : nil }
    }

    // MARK: - Private

    private static func warnings(_ inputs: AppInputs) -> [AppWarning] {
        AppWarning.allCases.filter { warning in
            switch warning {
            case .accessibilityMissing: return !inputs.hasAccessibilityAccess
            case .touchUpRunning: return inputs.isTouchUpRunning
            case .missionControlShortcutsOff: return !inputs.areMissionControlShortcutsOn
            case .settingsSetAside: return inputs.settingsWereSetAside
            }
        }
    }

    /// `text` without spaces around it; nil when that leaves nothing.
    fileprivate static func nonBlank(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Whether `uuid` can identify a display, as `DisplayMatcher` judges it.
    fileprivate static func isUUID(_ uuid: String) -> Bool {
        !uuid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - The world as the resolver sees it

/// A touchscreen in the snapshot: connected, or remembered by its record.
private struct Screen {
    let id: TouchscreenID
    let settings: TouchscreenSettings
    /// Nil for a remembered touchscreen that isn't connected.
    let connected: ConnectedTouchscreen?
    /// The name the snapshot shows.
    let name: String
    /// False for a connected touchscreen with no record: its ID is provisional and its settings the
    /// defaults, and nothing can change them.
    var hasRecord = true

    var device: ConnectedTouchscreen { connected! }
}

/// Where a connected touchscreen ends up.
private struct Outcome {
    let mode: TouchscreenMode
    let deviceState: DeviceState
    let driving: Driving?
    let rule: ModeRule
}

/// Everything worked out once from the inputs, for `resolve` and `apply`.
private struct World {
    let inputs: AppInputs
    let connectedScreens: [Screen]
    let rememberedScreens: [Screen]
    /// The display each stored pairing means now, as the matcher answers given all of them. Only a
    /// connected touchscreen's answer is ever used.
    let matched: [TouchscreenID: UInt32]
    /// Main first, then by origin: x, then y; then by display ID.
    let sortedDisplays: [DisplayFacts]
    /// Each display's label, by display ID.
    private var labels: [UInt32: (name: String, detail: String)] = [:]
    /// The touchscreen each display is paired with, by display ID: the first claimant.
    private var owners: [UInt32: Screen] = [:]

    init(_ inputs: AppInputs) {
        self.inputs = inputs
        let settings = inputs.settings

        // Connected touchscreens, each with its record. One with no record, or with a record an
        // earlier one already has (which the model never gives), is shown under a provisional ID
        // that no record can have, with the default settings: it can't be told apart.
        var connected: [Screen] = []
        var used = Set<TouchscreenID>()
        for device in inputs.connected {
            let facts = device.facts
            let fresh: TouchscreenSettings = {
                var fresh = TouchscreenSettings()
                fresh.lastSeenName = facts.name
                return fresh
            }()
            var screen: (id: TouchscreenID, settings: TouchscreenSettings, hasRecord: Bool)
            if let record = inputs.records[device.handle], !used.contains(record), !Resolver.isProvisional(record) {
                screen = (record, settings.touchscreens[record] ?? fresh, true)
                used.insert(record)
            } else {
                screen = (Self.provisionalID(device), fresh, false)
            }
            let name = Resolver.nonBlank(screen.hasRecord ? screen.settings.customName : nil)
                ?? Resolver.nonBlank(facts.name)
                ?? Self.unnamed(usbID: Self.usbID(vendor: facts.vendorID, product: facts.productID))
            connected.append(Screen(id: screen.id, settings: screen.settings, connected: device, name: name,
                                    hasRecord: screen.hasRecord))
        }
        connectedScreens = connected

        let connectedIDs = Set(connected.map(\.id))
        rememberedScreens = settings.touchscreens
            .filter { !connectedIDs.contains($0.key) && !Resolver.isProvisional($0.key) }
            .map { id, screenSettings in
                let name = Resolver.nonBlank(screenSettings.displayName)
                    ?? Self.unnamed(usbID: IDParts(id).usbID)
                return Screen(id: id, settings: screenSettings, connected: nil, name: name)
            }
            .sorted { $0.name != $1.name ? $0.name < $1.name : $0.id.rawValue < $1.id.rawValue }

        // Every stored pairing goes to the matcher, a remembered touchscreen's too: it still claims
        // its display, so that with two identical displays a connected touchscreen whose own display
        // is off is never given the other one by its fingerprint. Only the connected touchscreens'
        // answers are used (see `matchedDisplay`). A record that two connected touchscreens share
        // (which `assign` never gives) is no one's.
        let idCounts = connected.reduce(into: [TouchscreenID: Int]()) { $0[$1.id, default: 0] += 1 }
        var pairings: [TouchscreenID: DisplayIdentity] = [:]
        for screen in connected where idCounts[screen.id] == 1 {
            if let pairing = screen.settings.pairing { pairings[screen.id] = pairing.display }
        }
        for screen in rememberedScreens {
            if let pairing = screen.settings.pairing { pairings[screen.id] = pairing.display }
        }
        matched = DisplayMatcher.resolve(pairings: pairings, connected: inputs.displays)

        sortedDisplays = inputs.displays.sorted { a, b in
            if a.isMain != b.isMain { return a.isMain }
            if a.frame.origin.x != b.frame.origin.x { return a.frame.origin.x < b.frame.origin.x }
            if a.frame.origin.y != b.frame.origin.y { return a.frame.origin.y < b.frame.origin.y }
            return a.displayID < b.displayID
        }

        for display in inputs.displays {
            if owners[display.displayID] == nil, let owner = claimantScreens(of: display).first {
                owners[display.displayID] = owner
            }
        }
        for display in inputs.displays where labels[display.displayID] == nil {
            // A display whose name may be only the fallback ("Display": it mirrors another, or was
            // read before AppKit had its screen) is better named as its pairing remembers it.
            let stored = owners[display.displayID]?.settings.pairing?.displayName ?? ""
            let remembered = Self.nameToRemember(for: display, remembered: stored) == nil ? Resolver.nonBlank(stored) : nil
            labels[display.displayID] = DisplayLabel.label(
                for: display, among: inputs.displays, customName: customName(of: display.uuid) ?? remembered,
                diagonalInches: Resolver.usableDiagonal(owners[display.displayID]?.settings.diagonalInches))
        }
    }

    /// Whether `display`'s name is only the fallback: one that mirrors another has no screen of its
    /// own, and `DisplayReading` calls it "Display". That name is never remembered for a pairing,
    /// and never shown over one remembered. (The desk has a display really called "Display": the
    /// string alone can't tell.)
    static func hasNoNameOfItsOwn(_ display: DisplayFacts) -> Bool {
        display.mirrors.map { $0 != display.displayID } ?? false
    }

    /// The name a pairing with `display` should remember, given the one it has (`remembered`):
    /// the display's own name, unless it has none of its own, or its name is exactly the fallback
    /// ("Display", as a display read before AppKit has its screen is called for a moment) and a
    /// name is already remembered. Nil when the display's name isn't to be taken.
    static func nameToRemember(for display: DisplayFacts, remembered: String) -> String? {
        guard !hasNoNameOfItsOwn(display), let name = Resolver.nonBlank(display.name) else { return nil }
        if name == DisplayReading.fallbackName, Resolver.nonBlank(remembered) != nil { return nil }
        return name
    }

    // MARK: Remembering display names

    /// The display each touchscreen with a record is paired with now, by the name macOS gives it,
    /// where that is known for certain: a connected touchscreen's display as the matcher found it,
    /// and a remembered one's display by its UUID. A display with no name of its own is left out.
    func displayNamesSeen() -> [TouchscreenID: String] {
        var names: [TouchscreenID: String] = [:]
        for screen in connectedScreens where screen.hasRecord {
            guard let pairing = screen.settings.pairing, let display = matchedDisplay(of: screen) else { continue }
            if let name = Self.nameToRemember(for: display, remembered: pairing.displayName) { names[screen.id] = name }
        }
        for screen in rememberedScreens {
            guard let pairing = screen.settings.pairing, Resolver.isUUID(pairing.display.uuid) else { continue }
            let displays = inputs.displays.filter { $0.uuid == pairing.display.uuid }
            if displays.count == 1, let display = displays.first,
               let name = Self.nameToRemember(for: display, remembered: pairing.displayName) {
                names[screen.id] = name
            }
        }
        return names
    }

    // MARK: Questions `apply` asks

    /// The settings of `id`, a touchscreen with a record or a connected one; nil for one unknown,
    /// and for a connected one with no record, which nothing can change.
    func settings(of id: TouchscreenID) -> TouchscreenSettings? {
        inputs.settings.touchscreens[id] ?? connectedScreens.first { $0.id == id && $0.hasRecord }?.settings
    }

    func isConnected(_ id: TouchscreenID) -> Bool {
        connectedScreens.contains { $0.id == id }
    }

    /// The connected display with `displayID`, if a touchscreen can be paired with it: connected,
    /// not built-in, and the only display with that ID.
    func pairableDisplay(_ displayID: UInt32) -> DisplayFacts? {
        let displays = inputs.displays.filter { $0.displayID == displayID }
        guard displays.count == 1, let display = displays.first, !display.isBuiltIn else { return nil }
        return display
    }

    /// Every touchscreen whose pairing names `display`: one whose pairing resolves to it now, and
    /// any record, connected or not, whose pairing has its UUID. A pairing that only shares its
    /// fingerprint is not one: it may be another unit of the same model.
    func claimants(of display: DisplayFacts) -> [TouchscreenID] {
        claimantScreens(of: display).map(\.id)
    }

    private func claimantScreens(of display: DisplayFacts) -> [Screen] {
        (connectedScreens + rememberedScreens).filter { screen in
            if screen.connected != nil, matched[screen.id] == display.displayID { return true }
            guard let uuid = screen.settings.pairing?.display.uuid, Resolver.isUUID(uuid) else { return false }
            return uuid == display.uuid
        }
    }

    // MARK: The mode table

    func outcome(of screen: Screen) -> Outcome {
        let settings = screen.settings
        func released(_ rule: ModeRule) -> Outcome {
            Outcome(mode: .released, deviceState: .released, driving: nil, rule: rule)
        }
        func held(_ rule: ModeRule) -> Outcome {
            Outcome(mode: .held, deviceState: .taken, driving: nil, rule: rule)
        }
        if inputs.isQuitting { return released(.quitting) }
        if !inputs.settings.isOn { return released(.tactileOff) }
        if !inputs.hasAccessibilityAccess { return released(.noAccessibility) }
        if !inputs.isSessionActive { return released(.sessionNotActive) }
        if inputs.isAsleep { return released(.asleep) }
        if inputs.supportChecks.values.contains(screen.id) { return released(.supportCheck) }
        if let device = screen.connected, inputs.stoppedAnswering.contains(device.handle) { return released(.stoppedAnswering) }
        if !screen.hasRecord { return held(.noRecord) }
        if inputs.setUp?.touchscreen == screen.id || inputs.setUpMode != nil, canRunSetUp(screen) {
            // Taken, its touches for the flow or the mode: never a pipeline, never the pointer.
            return Outcome(mode: .settingUp, deviceState: .taken, driving: nil, rule: .settingUp)
        }
        // In set-up mode every touch is set-up input: one that can't be set up is held, not driving.
        if inputs.setUpMode != nil { return held(.settingUp) }
        if !settings.isOn {
            return settings.whenOff == .leaveToMacOS ? released(.offLeftToMacOS) : held(.offIgnoringTouches)
        }
        guard let pairing = settings.pairing else { return held(.notPaired) }
        guard let display = matchedDisplay(of: screen), let mapping = mapping(pairing, on: display) else {
            return held(.displayNotConnected)
        }
        let status = screen.device.status
        if status.touchOrigin == .unreadable { return held(.touchesUnreadable) }
        // macOS moves the pointer and clicks for a mouse-mode panel it still sees: driving it too
        // would handle every touch twice.
        if macOSAlsoHandles(screen) { return held(.mouseModeShared) }
        let content = mapping.content ?? display
        let driving = Driving(
            mapping: mapping,
            surfaceSizeMM: SurfaceSize.millimetres(display: display, diagonalInches: Resolver.usableDiagonal(settings.diagonalInches)),
            displayFrame: content.frame,
            displayID: content.displayID,
            options: status.touchOrigin == .mouseInterface ? .oneFingerOnly(keeping: settings.gestures) : settings.gestures,
            oneFinger: oneFingerInForce(screen),
            pointerReturn: settings.pointerReturn,
            showsCircles: settings.showsCircles,
            rejection: settings.rejection,
            swipesFollowFingers: inputs.settings.swipesFollowFingers)
        return Outcome(mode: .driving, deviceState: .taken, driving: driving, rule: .paired)
    }

    /// Whether a connected touchscreen can run a set-up now (see `Resolver.canRunSetUp`).
    func canRunSetUp(_ screen: Screen) -> Bool {
        guard let device = screen.connected, screen.hasRecord else { return false }
        if inputs.isQuitting || !inputs.settings.isOn || !inputs.hasAccessibilityAccess || !inputs.isSessionActive
            || inputs.isAsleep {
            return false
        }
        if device.status.touchOrigin == .unreadable { return false }
        if macOSAlsoHandles(screen) { return false }
        if inputs.supportChecks.values.contains(screen.id) { return false }
        if inputs.stoppedAnswering.contains(device.handle) { return false }
        return true
    }

    /// Whether macOS also acts on a connected touchscreen's touches: it gives one finger (its touches
    /// from its mouse interface, as it says, else as remembered: `givesOneFinger`,
    /// `TouchscreenSettings.lastGaveOneFinger`) and Tactile couldn't take it for itself. Then it is
    /// held, not driven (driving it too would handle every touch twice), and no set-up of it runs,
    /// from before its first touch after a launch: as its pane says (the `oneFingerOnly` and
    /// `macOSMayAlsoRespond` notes, which go by the same).
    func macOSAlsoHandles(_ screen: Screen) -> Bool {
        guard let device = screen.connected else { return false }
        return (givesOneFinger(device) ?? screen.settings.lastGaveOneFinger) == true && device.status.exclusive == .failed
    }

    /// What a flow for `screen` with `purpose` starts from (see `Resolver.setUpStart`).
    func setUpStart(for screen: Screen, purpose: SetUpPurpose) -> SetUpFlow.Start? {
        guard purpose != .full, !Resolver.isProvisional(screen.id), canRunSetUp(screen),
              screen.settings.pairing != nil, let display = matchedDisplay(of: screen)
        else { return nil }
        return SetUpFlow.Start(
            touchscreen: screen.id, touchscreenName: screen.name, purpose: purpose, candidates: [display],
            allDisplays: inputs.displays, reportedSizeMM: screen.device.reportedSizeMM, current: screen.settings.pairing,
            currentDiagonal: Resolver.usableDiagonal(screen.settings.diagonalInches))
    }

    /// The connected display a connected touchscreen's pairing means now, if the matcher is certain.
    func matchedDisplay(of screen: Screen) -> DisplayFacts? {
        guard screen.connected != nil, let displayID = matched[screen.id] else { return nil }
        return inputs.displays.first { $0.displayID == displayID }
    }

    /// The mapping onto `display`, through the display it mirrors when it mirrors one. Nil when
    /// that display isn't connected, or the mapping can't be built: nowhere certain to land.
    private func mapping(_ pairing: Pairing, on display: DisplayFacts) -> TouchMapping? {
        var content: DisplayFacts?
        if let master = display.mirrors, master != display.displayID {
            let masters = inputs.displays.filter { $0.displayID == master }
            guard masters.count == 1 else { return nil }
            content = masters[0]
        }
        return TouchMapping(orientation: pairing.orientation, alignment: pairing.alignment, display: display, content: content)
    }

    // MARK: Snapshots

    /// - Parameter setUpModeCouldBegin: whether set-up mode could begin now (no
    ///   `Resolver.setUpModeRefusal`): `canBeSetUp` is that, for a touchscreen that could be set up in it.
    func snapshot(of screen: Screen, mode: TouchscreenMode?, setUpModeCouldBegin: Bool) -> TouchscreenSnapshot {
        let settings = screen.settings
        var notes: [TouchscreenNote] = []
        var status: TouchscreenStatus = .notConnected
        var pairedDisplayID: UInt32?
        var pairedDisplayName = settings.pairing.map(lastKnownName(of:))
        var reportedDiagonal: Double?
        var usbID = IDParts(screen.id).usbID
        var serial = IDParts(screen.id).serial
        var location: String?
        var deviceLine: String?

        if let device = screen.connected {
            let facts = device.facts
            usbID = Self.usbID(vendor: facts.vendorID, product: facts.productID)
            serial = facts.serial
            location = Self.hex(facts.locationID, digits: 8)
            deviceLine = Self.describe(device.status)
            // What the device itself is (one finger from its mouse interface; ignored by macOS) is
            // what it last said while taken: a released touchscreen's status says nothing.
            let known = knownStatus(of: device)
            // One finger, as it says, else as remembered (the default goes by the same).
            if (givesOneFinger(device) ?? settings.lastGaveOneFinger) == true { notes.append(.oneFingerOnly) }
            if device.status.exclusive == .failed { notes.append(.macOSMayAlsoRespond) }
            if device.status.touchOrigin == .unreadable { notes.append(.touchesCannotBeRead) }
            // Touches from its touch interface, and no Input Mode setting to switch it back to a
            // mouse: macOS ignores it by itself, so "Leave it to macOS" would do nothing.
            if let known, known.touchOrigin == .touchInterface, known.inputMode == .noInputModeSetting {
                notes.append(.macOSIgnoresIt)
            }

            if inputs.stoppedAnswering.contains(device.handle) {
                status = .stoppedAnswering
            } else if !inputs.settings.isOn {
                status = .tactileOff
            } else if !inputs.hasAccessibilityAccess {
                status = .accessibilityMissing
            } else if !settings.isOn {
                status = .off
            } else if let pairing = settings.pairing {
                if let display = matchedDisplay(of: screen), mapping(pairing, on: display) != nil {
                    let label = labels[display.displayID] ?? (display.name, "")
                    status = .pairedWith(name: label.name, detail: label.detail)
                } else if let display = matchedDisplay(of: screen) {
                    let name = labels[display.displayID]?.name ?? display.name
                    status = .displayNotConnected(name: name)
                    pairedDisplayName = name
                } else {
                    status = .displayNotConnected(name: lastKnownName(of: pairing))
                }
            } else {
                status = .notSetUp
            }

            // Whatever the status line says (off, Tactile off, no Accessibility), a pairing whose
            // display is connected, with somewhere for a touch to land, names it.
            if let pairing = settings.pairing, let display = matchedDisplay(of: screen),
               mapping(pairing, on: display) != nil {
                pairedDisplayID = display.displayID
                pairedDisplayName = labels[display.displayID]?.name ?? display.name
                reportedDiagonal = Self.reportedDiagonal(of: display)
            }
        }
        // Not connected: one finger as remembered, as the default goes by.
        if screen.connected == nil, settings.lastGaveOneFinger == true { notes.append(.oneFingerOnly) }
        if TouchscreenIdentity.isByPort(screen.id) { notes.append(.rememberedByPort) }
        // No USB location, and another connected touchscreen is identical: no record, so nothing
        // it shows can be changed.
        if !screen.hasRecord { notes.append(.cannotBeToldApart) }

        let choices = sortedDisplays.filter { !$0.isBuiltIn }.map { display -> DisplayChoice in
            let label = labels[display.displayID] ?? (display.name, "")
            let owner = owners[display.displayID]
            return DisplayChoice(
                id: display.displayID, name: label.name, detail: label.detail,
                inUseBy: owner.flatMap { $0.id == screen.id ? nil : $0.name })
        }

        // The one place a touchscreen's snapshot is made.
        return TouchscreenSnapshot(
            id: screen.id, name: screen.name, deviceName: screen.connected?.facts.name ?? settings.lastSeenName,
            isConnected: screen.connected != nil, isOn: settings.isOn, whenOff: settings.whenOff, mode: mode,
            status: status, notes: notes, pairedDisplayID: pairedDisplayID, pairedDisplayName: pairedDisplayName,
            displayChoices: choices, orientation: settings.pairing?.orientation,
            diagonalInches: Resolver.usableDiagonal(settings.diagonalInches),
            reportedDiagonalInches: reportedDiagonal, usbID: usbID, serial: serial, location: location,
            device: deviceLine,
            behaviour: BehaviourSnapshot(
                oneFinger: oneFingerInForce(screen), oneFingerChoice: settings.oneFinger,
                pointerReturn: settings.pointerReturn, showsCircles: settings.showsCircles,
                gestures: settings.gestures, rejection: settings.rejection,
                reportsPalms: screen.connected?.reportsPalms ?? false,
                multiFingerAvailable: !notes.contains(.oneFingerOnly)),
            isCalibrated: settings.pairing.map { $0.alignment != .wholeGlass } ?? false,
            canBeSetUp: setUpModeCouldBegin && canRunSetUp(screen))
    }

    func snapshot(of display: DisplayFacts) -> DisplaySnapshot {
        let label = labels[display.displayID] ?? (display.name, "")
        // The one place a display's snapshot is made.
        return DisplaySnapshot(
            id: display.displayID, uuid: display.uuid, name: label.name, detail: label.detail, frame: display.frame,
            isBuiltIn: display.isBuiltIn, isMain: display.isMain, pairedTouchscreen: owners[display.displayID]?.name)
    }

    /// The custom name of the display with `uuid`, if it has a UUID and a name.
    private func customName(of uuid: String) -> String? {
        guard Resolver.isUUID(uuid) else { return nil }
        return Resolver.nonBlank(inputs.settings.displayNames[uuid])
    }

    /// The name of a paired display, wherever it is: its custom name, else the name macOS gives the
    /// connected display with its UUID (unless that is only the fallback of a display mirroring
    /// another), else the name the pairing remembers, else its native size ("2560 × 1440 display").
    private func lastKnownName(of pairing: Pairing) -> String {
        let identity = pairing.display
        if let custom = customName(of: identity.uuid) { return custom }
        if Resolver.isUUID(identity.uuid), let connected = inputs.displays.first(where: { $0.uuid == identity.uuid }),
           let name = Self.nameToRemember(for: connected, remembered: pairing.displayName) {
            return name
        }
        if let remembered = Resolver.nonBlank(pairing.displayName) { return remembered }
        if identity.nativeWidth > 0, identity.nativeHeight > 0 {
            return "\(identity.nativeWidth) \u{00D7} \(identity.nativeHeight) display"
        }
        return "Unknown display"
    }

    private static func reportedDiagonal(of display: DisplayFacts) -> Double? {
        let size = display.sizeMM
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else { return nil }
        return SurfaceSize.diagonalInches(of: size)
    }

    /// "taken · input mode switchedToMultiTouch · touches from mouseInterface · exclusive held".
    private static func describe(_ status: DeviceStatus) -> String {
        [status.state.rawValue, "input mode \(status.inputMode.rawValue)",
         "touches from \(status.touchOrigin.rawValue)", "exclusive \(status.exclusive.rawValue)"]
            .joined(separator: " \u{00B7} ")
    }

    /// The ID a connected touchscreen with no record is shown under: `#`, its handle, a colon, then
    /// its base ID. No record can have it: a base ID starts with a hex digit, a port ID with `@`,
    /// and a key in the settings file that starts with `#` is never taken for a record.
    static func provisionalID(_ device: ConnectedTouchscreen) -> TouchscreenID {
        let facts = device.facts
        let base = TouchscreenIdentity.baseID(vendorID: facts.vendorID, productID: facts.productID, serial: facts.serial)
        return TouchscreenID(rawValue: "#\(device.handle.rawValue):\(base.rawValue)")
    }

    /// "222a:0001".
    static func usbID(vendor: Int, product: Int) -> String {
        "\(hex(vendor, digits: 4)):\(hex(product, digits: 4))"
    }

    /// What a touchscreen with no name is called: "Touchscreen 222a:0001".
    static func unnamed(usbID: String) -> String {
        usbID.isEmpty ? "Touchscreen" : "Touchscreen \(usbID)"
    }

    static func hex<Value: BinaryInteger>(_ value: Value, digits: Int) -> String {
        let text = String(UInt64(truncatingIfNeeded: value), radix: 16)
        return String(repeating: "0", count: max(0, digits - text.count)) + text
    }
}

// MARK: - Set-up mode

/// What set-up mode's session is given, and which touchscreen each connected handle is.
public struct SetUpScene: Equatable, Sendable {
    public var scene: SetUpSession.Scene
    /// Each connected touchscreen's ID, by its handle: its record, or its provisional ID.
    public var touchscreens: [DeviceHandle: TouchscreenID]

    public init(scene: SetUpSession.Scene, touchscreens: [DeviceHandle: TouchscreenID]) {
        self.scene = scene
        self.touchscreens = touchscreens
    }
}

extension Resolver {

    /// What set-up mode's session is given (`SetUpSession.Scene`), and which touchscreen each
    /// connected handle is:
    /// - the cards: every connected display a `.full` flow could start on alone, and alone with its
    ///   picture (`SetUpFlow.setUpModeCandidates`: never the built-in display, never a member of a
    ///   mirror set), in screen order (main first, then by origin), each with its label and the
    ///   touchscreen paired with it now, if any, as the display's own snapshot names it. While the
    ///   displays reconfigure, the displays seen last.
    /// - each connected touchscreen's line: can't be set up, with the pane's words for why, when
    ///   `canRunSetUp` says so; set up, on its display as its pane names it, when it is paired;
    ///   otherwise not set up. With what a flow for it starts from.
    public static func setUpScene(_ inputs: AppInputs) -> SetUpScene {
        let world = World(inputs)
        return setUpScene(inputs, world: world, shown: shownWorld(inputs, world))
    }

    /// Why set-up mode can't begin now, with the words for the log; nil when it can. It begins only
    /// when Tactile is on, with Accessibility access, the session active, not asleep or quitting, the
    /// displays settled, no set-up running, at least one connected touchscreen can be set up, and
    /// at least one candidate display exists (`SetUpSession.couldBegin`). The snapshot carries the
    /// reason (`AppSnapshot.setUpModeRefusal`), for the menu and the panes to say.
    public static func setUpModeRefusal(_ inputs: AppInputs) -> (refusal: SetUpModeRefusal, words: String)? {
        let world = World(inputs)
        return setUpModeRefusal(inputs, scene: setUpScene(inputs, world: world, shown: shownWorld(inputs, world)).scene)
    }

    /// What ends set-up mode at once, as an interruption, in words for the log; nil when nothing
    /// does: quitting, Tactile off, Accessibility lost, the session inactive (locked, or switched
    /// out), sleep. Each releases every touchscreen (rows 1–4a of the mode table).
    public static func setUpModeInterruption(_ inputs: AppInputs) -> String? {
        interruption(inputs)?.words
    }

    /// An interruption (see `setUpModeInterruption`), as a refusal of the mode and in words.
    private static func interruption(_ inputs: AppInputs) -> (refusal: SetUpModeRefusal, words: String)? {
        if inputs.isQuitting { return (.notNow, "Tactile is quitting") }
        if !inputs.settings.isOn { return (.tactileOff, "Tactile is off") }
        if !inputs.hasAccessibilityAccess { return (.accessibilityMissing, "no Accessibility access") }
        if !inputs.isSessionActive { return (.notNow, "the session isn't active") }
        if inputs.isAsleep { return (.notNow, "the Mac is asleep") }
        return nil
    }

    fileprivate static func setUpModeRefusal(
        _ inputs: AppInputs, scene: SetUpSession.Scene
    ) -> (refusal: SetUpModeRefusal, words: String)? {
        if let interruption = interruption(inputs) { return interruption }
        if inputs.displays.isEmpty {
            return inputs.lastKnownDisplays != nil
                ? (.notNow, "the displays are reconfiguring") : (.noDisplay, "no display is connected")
        }
        if inputs.setUpMode != nil { return (.running, "set-up mode is already on") }
        if let running = inputs.setUp { return (.running, "a set-up of \(running.touchscreen.rawValue) is running") }
        if !scene.touchscreens.contains(where: \.canBeSetUp) {
            return (.noTouchscreenCanBeSetUp, "no connected touchscreen can be set up")
        }
        if scene.cards.isEmpty { return (.noDisplayToChoose, "there is no display to set one up on") }
        return SetUpSession.couldBegin(scene) ? nil : (.notNow, "the set-up can't begin")
    }

    fileprivate static func shownWorld(_ inputs: AppInputs, _ world: World) -> World {
        guard inputs.displays.isEmpty, let lastKnown = inputs.lastKnownDisplays else { return world }
        var shownInputs = inputs
        shownInputs.displays = lastKnown
        return World(shownInputs)
    }

    fileprivate static func setUpScene(_ inputs: AppInputs, world: World, shown: World) -> SetUpScene {
        var ids: [DeviceHandle: TouchscreenID] = [:]
        let touchscreens = shown.connectedScreens.map { screen -> SetUpSession.Touchscreen in
            ids[screen.device.handle] = screen.id
            return shown.setUpModeEntry(screen, ownDisplay: world.ownDisplayID(of: screen))
        }
        let scene = SetUpSession.Scene(
            displays: inputs.displays, cards: shown.setUpModeCards(), touchscreens: touchscreens,
            isReconfiguring: inputs.displays.isEmpty && inputs.lastKnownDisplays != nil)
        return SetUpScene(scene: scene, touchscreens: ids)
    }

    /// The touchscreens the first-run window names: every connected touchscreen that can be set up
    /// (`canRunSetUp`: Tactile on, Accessibility granted), isn't (its status `notSetUp`), and has
    /// never been offered set-up, while no set-up runs and a candidate display exists. Decided on
    /// the displays shown, so that during a reconfiguration the offer stays, while `canBeSetUp` is
    /// false.
    fileprivate static func offerSetUpTo(
        _ inputs: AppInputs, shown: World, snapshots: [TouchscreenSnapshot]
    ) -> [TouchscreenID] {
        guard inputs.setUp == nil, inputs.setUpMode == nil, !shown.setUpModeCards().isEmpty else { return [] }
        return shown.connectedScreens.filter { screen in
            guard screen.hasRecord, shown.canRunSetUp(screen),
                  let snapshot = snapshots.first(where: { $0.id == screen.id })
            else { return false }
            return snapshot.status == .notSetUp && inputs.settings.touchscreens[screen.id]?.wasOfferedSetUp == false
        }.map(\.id)
    }
}

extension World {

    /// The cards of set-up mode's overview (see `Resolver.setUpScene`).
    func setUpModeCards() -> [SetUpDisplayCard] {
        let candidates = Set(SetUpFlow.setUpModeCandidates(among: inputs.displays).map(\.displayID))
        return sortedDisplays.filter { candidates.contains($0.displayID) }.map { display in
            let label = labels[display.displayID] ?? (display.name, "")
            let owner = owners[display.displayID]
            return SetUpDisplayCard(
                id: display.displayID, name: label.name, detail: label.detail, touchscreen: owner?.id,
                touchscreenName: owner?.name)
        }
    }

    /// A connected touchscreen as set-up mode's session needs it (see `Resolver.setUpScene`).
    /// `ownDisplay`: the connected display its pairing means now, found among the displays
    /// published now.
    func setUpModeEntry(_ screen: Screen, ownDisplay: UInt32?) -> SetUpSession.Touchscreen {
        let state: SetUpTouchscreenLine.State
        var reason: String?
        if !canRunSetUp(screen) {
            state = .cannotBeSetUp
            reason = cannotBeSetUpReason(screen).map(Wording.setUpUnavailable)
        } else if let pairing = screen.settings.pairing {
            if let display = matchedDisplay(of: screen), mapping(pairing, on: display) != nil {
                state = .setUp(displayName: labels[display.displayID]?.name ?? display.name)
            } else {
                state = .setUp(displayName: lastKnownName(of: pairing))
            }
        } else {
            state = .notSetUp
        }
        return SetUpSession.Touchscreen(
            line: SetUpTouchscreenLine(id: screen.id, name: screen.name, state: state, reason: reason),
            reportedSizeMM: screen.connected?.reportedSizeMM, pairing: screen.settings.pairing,
            diagonalInches: Resolver.usableDiagonal(screen.settings.diagonalInches), ownDisplay: ownDisplay)
    }

    /// The connected display `screen`'s pairing means now, when it is found for certain and a touch
    /// on it has somewhere to land.
    func ownDisplayID(of screen: Screen) -> UInt32? {
        guard let pairing = screen.settings.pairing, let display = matchedDisplay(of: screen),
              mapping(pairing, on: display) != nil
        else { return nil }
        return display.displayID
    }

    /// Why a connected touchscreen can't run a set-up, as the pane gives the reason; nil when it can,
    /// or when the reason is one the pane has no words for (the session inactive, sleep, quitting:
    /// set-up mode is never on then).
    private func cannotBeSetUpReason(_ screen: Screen) -> SetUpAvailability.Reason? {
        guard let device = screen.connected else { return .notConnected }
        if !inputs.settings.isOn { return .tactileOff }
        if !inputs.hasAccessibilityAccess { return .accessibilityMissing }
        if inputs.stoppedAnswering.contains(device.handle) { return .stoppedAnswering }
        if !screen.hasRecord { return .cannotBeToldApart }
        if device.status.touchOrigin == .unreadable { return .touchesCannotBeRead }
        if macOSAlsoHandles(screen) { return .macOSAlsoHandlesIt }
        return nil
    }

    /// What a connected touchscreen says about the device itself: its status while taken, once the
    /// origin of its touches is known; else what it said last while taken (`AppInputs.lastTakenStatus`).
    func knownStatus(of device: ConnectedTouchscreen) -> DeviceStatus? {
        let taken = device.status.state == .taken && device.status.touchOrigin != .undetermined
        return taken ? device.status : inputs.lastTakenStatus[device.handle]
    }

    /// The one-finger mode in force: the person's choice, else the default for this touchscreen,
    /// which is Always scroll for one that gives one finger and Automatic for every other. Whether it
    /// gives one finger is what it says (`givesOneFinger`), else what it last said, as remembered in
    /// its settings (`TouchscreenSettings.lastGaveOneFinger`): so after a launch the strip scrolls
    /// from its first touch. Scrolling by default is safe there: a finger that rests before it moves
    /// (`GestureConstants.holdTime`, and the long-press ring after it) drags, whatever the mode.
    func oneFingerInForce(_ screen: Screen) -> OneFingerMode {
        if let choice = screen.settings.oneFinger { return choice }
        let gives = screen.connected.flatMap(givesOneFinger) ?? screen.settings.lastGaveOneFinger
        return gives == true ? .alwaysScroll : .automatic
    }

    /// Whether a connected touchscreen gives one finger, as far as it has said: its touches from its
    /// mouse interface, or from its touch interface, as it said while taken (`knownStatus`); nil
    /// while it hasn't said, or its touches can't be read. Where it is nil, the default and the
    /// `oneFingerOnly` note (with `multiFingerAvailable`) go by what is remembered,
    /// `TouchscreenSettings.lastGaveOneFinger`.
    func givesOneFinger(_ device: ConnectedTouchscreen) -> Bool? {
        switch knownStatus(of: device)?.touchOrigin {
        case .mouseInterface?: return true
        case .touchInterface?: return false
        case .undetermined?, .unreadable?, nil: return nil
        }
    }
}

/// The USB ID and serial in a touchscreen's ID: `vendor:product:serial`, with `@location:` in front
/// for a port ID.
private struct IDParts {
    let usbID: String
    let serial: String

    init(_ id: TouchscreenID) {
        var text = Substring(id.rawValue)
        if TouchscreenIdentity.isByPort(id) { text = text.dropFirst(10) }
        let parts = text.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        if parts.count == 3 {
            usbID = "\(parts[0]):\(parts[1])"
            serial = String(parts[2])
        } else {
            usbID = ""
            serial = ""
        }
    }
}
