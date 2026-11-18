// The real desk, as of the panel survey on 2026-11-14, for previews and for the interface's tests:
// five displays, two touchscreens and one remembered. A small stand-in for the model's resolver,
// with only the rules the interface needs to look alive: commands change it the obvious way, the
// snapshot is worked out again from it, and a set-up can be walked through one touch at a time, in
// set-up mode or outside it (`PreviewDesk+SetUpMode.swift`).

import CoreGraphics
import Foundation
import TactileGestures
import TactileScreens

struct PreviewDesk: Equatable, Sendable {

    struct Screen: Equatable, Sendable {
        var id: UInt32
        var uuid: String
        var macOSName: String
        var frame: CGRect
        var reportedDiagonalInches: Double
        var isBuiltIn = false
        var isMain = false
        var isConnected = true
    }

    /// The behaviour settings, as `TouchscreenSettings.copyBehaviour` copies them, `whenOff` apart.
    struct Behaviour: Equatable, Sendable {
        /// The one-finger choice; nil: the default for its kind (`defaultOneFinger`).
        var oneFinger: OneFingerMode? = nil
        var pointerReturn = PointerReturn.backWhereItWas
        var showsCircles = true
        var gestures = GestureOptions.all
        var rejection = RejectionRules()
    }

    struct Panel: Equatable, Sendable {
        var id: TouchscreenID
        var deviceName: String
        var customName: String? = nil
        var isConnected = true
        var isOn = true
        var whenOff = WhenOff.ignoreTouches
        /// The UUID of its display, when paired.
        var pairedUUID: String? = nil
        var orientation = Orientation.asFitted
        var isCalibrated = false
        var diagonalInches: Double? = nil
        var behaviour = Behaviour()
        var wasOfferedSetUp = true
        var reportsPalms = false
        /// The size of its glass as it reports it, in millimetres.
        var glassMM: CGSize? = nil
        var usbID: String
        var serial: String
        var location: String?
        var device: String?
        var notes: [TouchscreenNote] = []

        var name: String { customName ?? deviceName }
        /// It has no record: none of its settings can change.
        var hasRecord: Bool { !notes.contains(.cannotBeToldApart) }
    }

    /// A set-up in progress.
    struct SetUpRun: Equatable, Sendable {
        var touchscreen: TouchscreenID
        var purpose: SetUpPurpose
        var step: SetUpStep
        /// Its display.
        var display: UInt32?
        /// The diagonal confirmed in the size step: nil for as reported.
        var diagonal: Double?
        /// When the last touch or button came, for the two minutes without one that end it.
        var lastInput: TimeInterval = 0
    }

    /// How long without a touch or a button ends a set-up, or set-up mode, in seconds.
    static let endsWithoutInput: TimeInterval = 120

    var appVersion = "0.5.0"
    var isOn = true
    var hasAccessibility = true
    var otherWarnings: [AppWarning] = []
    var debugLogging = false
    var recordsFrames = false
    /// Followed swipes, as stored: off unless switched on.
    var swipesFollowFingers = false
    /// Whether this Mac can follow swipes: as a Mac on macOS 26 with the gesture on can.
    var canFollowSwipes = true
    /// Launch at login, as macOS would say: off until switched on.
    var launchAtLogin = LaunchAtLogin.off
    var screens: [Screen]
    var panels: [Panel]
    var displayNames: [String: String] = [:]
    var setUpRun: SetUpRun?
    /// Set-up mode, while it is on.
    var modeRun: SetUpModeRun?
    var tester: Tester?

    // MARK: - The desk and its variants

    init(_ variant: PreviewModel.Variant) {
        screens = Self.deskScreens
        panels = Self.deskPanels
        switch variant {
        case .desk:
            break
        case .nothingPaired:
            panels.removeAll { !$0.isConnected }
            for index in panels.indices {
                panels[index].pairedUUID = nil
                panels[index].diagonalInches = nil
                panels[index].isCalibrated = false
                panels[index].wasOfferedSetUp = false
            }
        case .accessibilityMissing:
            hasAccessibility = false
        case .tactileOff:
            isOn = false
        case .displayUnplugged, .tactileOffDisplayUnplugged:
            if let hdmi = screens.firstIndex(where: { $0.macOSName == "HDMI" }) {
                screens[hdmi].isConnected = false
            }
            isOn = variant == .displayUnplugged
        case .allWarnings:
            hasAccessibility = false
            otherWarnings = [.touchUpRunning, .missionControlShortcutsOff, .settingsSetAside]
        case .identicalTwins:
            // A second ILITEK-TP, on a hub that reports no USB location: it can't be told apart.
            panels.insert(
                Panel(id: TouchscreenID(rawValue: "#7:222a:0001:V06.00.00.00"), deviceName: "ILITEK-TP",
                      wasOfferedSetUp: false, glassMM: CGSize(width: 476, height: 268), usbID: "222a:0001",
                      serial: "V06.00.00.00", location: nil,
                      device: "input mode: no setting · touches from: touch interface · exclusive: held",
                      notes: [.macOSIgnoresIt, .cannotBeToldApart]),
                at: 2)
        }
    }

    private static let deskScreens: [Screen] = [
        Screen(id: 1, uuid: "B1A6C2E4-0F3D-4C1B-9E55-2A7D41C0F001", macOSName: "Built-in Retina Display",
               frame: CGRect(x: 0, y: 0, width: 2056, height: 1329), reportedDiagonalInches: 14.2,
               isBuiltIn: true, isMain: true),
        Screen(id: 2, uuid: "5D0B7F3A-61C2-4E8D-A4F0-9C3E2B71A002", macOSName: "HDMI",
               frame: CGRect(x: -252, y: -1440, width: 2560, height: 1440), reportedDiagonalInches: 27),
        Screen(id: 3, uuid: "C4E21A9B-7D35-4F60-B812-6E0F9A54D003", macOSName: "LG HDR 4K",
               frame: CGRect(x: 2056, y: 0, width: 3008, height: 1692), reportedDiagonalInches: 27),
        Screen(id: 4, uuid: "8F7A3C11-2B94-4D6E-95A0-D1E4C7B2E004", macOSName: "Display",
               frame: CGRect(x: -2048, y: 24, width: 2048, height: 1280), reportedDiagonalInches: 18),
        Screen(id: 5, uuid: "2E9D5B07-C8A1-4F3B-8D26-7B0A3E91F005", macOSName: "12.3FHD",
               frame: CGRect(x: 228, y: 1329, width: 1600, height: 600), reportedDiagonalInches: 10.1),
    ]

    private static let deskPanels: [Panel] = [
        Panel(id: TouchscreenID(rawValue: "222a:0001:V06.00.00.00"), deviceName: "ILITEK-TP",
              pairedUUID: "5D0B7F3A-61C2-4E8D-A4F0-9C3E2B71A002", isCalibrated: true, diagonalInches: 23.8,
              glassMM: CGSize(width: 476, height: 268), usbID: "222a:0001", serial: "V06.00.00.00",
              location: "01141000",
              device: "input mode: no setting · touches from: touch interface · exclusive: held",
              notes: [.macOSIgnoresIt]),
        Panel(id: TouchscreenID(rawValue: "27c0:0859:TEST-SERIAL-0001"), deviceName: "TouchScreen",
              pairedUUID: "2E9D5B07-C8A1-4F3B-8D26-7B0A3E91F005", diagonalInches: 12.3,
              glassMM: CGSize(width: 217, height: 91), usbID: "27c0:0859", serial: "TEST-SERIAL-0001",
              location: "01130000",
              device: "input mode: switched to multi-touch · touches from: mouse interface · exclusive: held",
              notes: [.oneFingerOnly]),
        Panel(id: TouchscreenID(rawValue: "0eef:0001:"), deviceName: "ACDC Touch Input Device",
              customName: "Old panel", isConnected: false, pairedUUID: "8F7A3C11-2B94-4D6E-95A0-D1E4C7B2E004",
              usbID: "0eef:0001", serial: "", location: nil, device: nil),
    ]

    // MARK: - Commands

    /// Applies `command` the obvious way. `now` is the host's clock, for the ring of a set-up begun.
    mutating func apply(_ command: AppCommand, at now: TimeInterval = 0) {
        defer { closeTesterIfItMustClose() }
        // As the model does: while set-up mode is on or a set-up runs, nothing changes a pairing, an
        // orientation, an alignment or a diagonal, of any touchscreen. A set-up's Done stores those.
        if setUpRun != nil || modeRun != nil, Self.changesAFit(command) { return }
        switch command {
        case .setOn(let on):
            isOn = on
            if !on { interruptSetUp() }
        case .setTouchscreenOn(let id, let on):
            update(id) { $0.isOn = on }
        case .setWhenOff(let id, let whenOff):
            update(id) { $0.whenOff = whenOff }
        case .rename(let id, let name):
            update(id) { $0.customName = Self.trimmed(name) }
        case .pair(let id, let displayID):
            pair(id, with: displayID)
        case .unpair(let id):
            update(id) {
                $0.pairedUUID = nil
                $0.orientation = .asFitted
                $0.isCalibrated = false
            }
        case .setOrientation(let id, let orientation):
            update(id) {
                if $0.pairedUUID != nil {
                    $0.orientation = orientation
                }
            }
        case .setDiagonal(let id, let inches):
            update(id) { $0.diagonalInches = inches.flatMap { DiagonalEntry.range.contains($0) ? $0 : nil } }
        case .forget(let id):
            panels.removeAll { $0.id == id && !$0.isConnected }
        case .renameDisplay(let uuid, let name):
            guard !uuid.isEmpty else { return }
            displayNames[uuid] = Self.trimmed(name)
        case .setDebugLogging(let on):
            debugLogging = on
        case .askForAccessibility:
            hasAccessibility = true
        case .setOneFinger(let id, let mode):
            update(id) { $0.behaviour.oneFinger = mode }
        case .setPointerReturn(let id, let choice):
            update(id) { $0.behaviour.pointerReturn = choice }
        case .setShowsCircles(let id, let on):
            update(id) { $0.behaviour.showsCircles = on }
        case .setGestures(let id, let gestures):
            update(id) { $0.behaviour.gestures = gestures }
        case .setRejection(let id, let rules):
            update(id) { $0.behaviour.rejection = rules }
        case .copyBehaviour(let from, let to):
            guard from != to, let source = panels.first(where: { $0.id == from && $0.hasRecord }) else { return }
            update(to) {
                $0.behaviour = source.behaviour
                $0.whenOff = source.whenOff
            }
        case .resetBehaviour(let id):
            update(id) {
                $0.behaviour = Behaviour()
                $0.whenOff = .ignoreTouches
            }
        case .clearCalibration(let id):
            update(id) { $0.isCalibrated = false }
        case .beginSetUp(let id, let purpose):
            if purpose == .full {
                beginSetUpMode(at: now)
            } else {
                beginSetUp(id, purpose, at: now)
            }
        case .setUpConfirmSize(let inches):
            guard var run = setUpRun, case .size(let display, _, _, _) = run.step else { return }
            if let inches, !DiagonalEntry.range.contains(inches) { return }
            run.diagonal = inches
            run.step = .check(display: display)
            run.lastInput = now
            setUpRun = run
        case .setUpRedo:
            guard var run = setUpRun, case .check(let display) = run.step, run.purpose != .test else { return }
            run.step = .corners(display: display, target: Calibration.targets[0], index: 0, problem: nil)
            run.lastInput = now
            setUpRun = run
        case .setUpDone:
            guard let run = setUpRun, case .check = run.step else { return }
            finish(run)
        case .cancelSetUp:
            cancelSetUp()
        case .declineSetUp(let id):
            update(id) { $0.wasOfferedSetUp = true }
        case .setRecordsFrames(let on):
            recordsFrames = on
        case .copyDiagnostics:
            break
        case .setSwipesFollowFingers(let on):
            swipesFollowFingers = on
        case .setLaunchAtLogin(let on):
            // Never from outside the Applications folder; otherwise registered at once, as when the
            // person has approved Tactile before.
            guard launchAtLogin != .notInstalled else { return }
            launchAtLogin = on ? .on : .off
        case .openLoginItemsSettings:
            break
        case .beginSetUpMode, .setUpChoose, .setUpBack:
            applySetUpMode(command, at: now)
        case .openGestureTester, .closeGestureTester, .setGestureTesterPerformsSwipes, .clearGestureTester:
            applyTester(command, at: now)
        case .beginSupportCheck, .endSupportCheck:
            // The preview has no devices to check.
            break
        }
    }

    /// Whether `command` changes a pairing, an orientation, an alignment or a diagonal: refused while
    /// a set-up runs, as the model refuses it.
    private static func changesAFit(_ command: AppCommand) -> Bool {
        switch command {
        case .pair, .unpair, .forget, .setOrientation, .clearCalibration, .setDiagonal:
            return true
        default:
            return false
        }
    }

    /// Changes a panel that has a record. A panel that can't be told apart changes no setting.
    mutating func update(_ id: TouchscreenID, _ change: (inout Panel) -> Void) {
        guard let index = panels.firstIndex(where: { $0.id == id }), panels[index].hasRecord else { return }
        change(&panels[index])
    }

    private mutating func pair(_ id: TouchscreenID, with displayID: UInt32) {
        guard let screen = screens.first(where: { $0.id == displayID && $0.isConnected && !$0.isBuiltIn }),
            panels.contains(where: { $0.id == id && $0.isConnected && $0.hasRecord })
        else { return }
        for index in panels.indices where panels[index].id != id && panels[index].pairedUUID == screen.uuid {
            panels[index].pairedUUID = nil
            panels[index].isCalibrated = false
        }
        update(id) {
            if $0.pairedUUID != screen.uuid {
                $0.orientation = .asFitted
                $0.isCalibrated = false
            }
            $0.pairedUUID = screen.uuid
        }
    }

    private static func trimmed(_ name: String?) -> String? {
        let text = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    // MARK: - Set-up, walked through by hand

    /// Calibrate Corners… and Test: on its own display, connected. In set-up mode, only while every
    /// display offers itself; it runs inside the mode and returns to its overview. (A full set-up
    /// is set-up mode's: `beginSetUpMode`.)
    private mutating func beginSetUp(_ id: TouchscreenID, _ purpose: SetUpPurpose, at now: TimeInterval) {
        guard setUpRun == nil, modeRun.map({ $0.stage == .choosing }) ?? true, isOn, hasAccessibility,
            purpose != .full, let panel = panels.first(where: { $0.id == id }), canBeSetUpByTouch(panel),
            let own = connectedScreen(of: panel)
        else { return }
        let step: SetUpStep = purpose == .test
            ? .check(display: own.id)
            : .corners(display: own.id, target: Calibration.targets[0], index: 0, problem: nil)
        setUpRun = SetUpRun(
            touchscreen: id, purpose: purpose, step: step, display: own.id, diagonal: panel.diagonalInches, lastInput: now)
        flowBegan()
    }

    /// Ends a set-up, or set-up mode, after two minutes without a touch or a button.
    mutating func tickSetUp(at now: TimeInterval) {
        if modeRun != nil {
            tickSetUpMode(at: now)
        } else if let run = setUpRun, now - run.lastInput >= Self.endsWithoutInput {
            endSetUp()
        }
    }

    /// The person touches the touchscreen being set up: in the corners step, the next target, or
    /// `problem` refuses the round.
    mutating func touchSetUp(at now: TimeInterval, problem: SetUpProblem? = nil) {
        tickSetUp(at: now)
        guard var run = setUpRun else { return }
        run.lastInput = now
        if case .corners(let display, _, let index, _) = run.step {
            switch problem {
            case .tooManyFingers?, .moved?:
                run.step = .corners(display: display, target: Calibration.targets[index], index: index, problem: problem)
            case .tapsDidNotFit?, .ambiguous?:
                run.step = .corners(display: display, target: Calibration.targets[0], index: 0, problem: problem)
            case nil:
                if index + 1 < Calibration.targets.count {
                    run.step = .corners(
                        display: display, target: Calibration.targets[index + 1], index: index + 1, problem: nil)
                } else if run.purpose == .full {
                    run.step = sizeStep(on: display, for: run.touchscreen)
                } else {
                    run.step = .check(display: display)
                }
            }
        }
        setUpRun = run
    }

    /// The display being set up was turned in macOS: the corners start again from the first
    /// target, with no problem to show.
    mutating func restartCorners() {
        guard var run = setUpRun, case .corners(let display, _, _, _) = run.step else { return }
        run.step = .corners(display: display, target: Calibration.targets[0], index: 0, problem: nil)
        setUpRun = run
    }

    private func sizeStep(on display: UInt32, for id: TouchscreenID) -> SetUpStep {
        let screen = screens.first { $0.id == display }
        let panel = panels.first { $0.id == id }
        let glass = panel?.glassMM.map { Double(hypot($0.width, $0.height)) / 25.4 }
        return .size(
            display: display, displayReports: screen.map(\.reportedDiagonalInches).flatMap(Self.plausible),
            touchscreenReports: glass.flatMap(Self.plausible), current: panel?.diagonalInches)
    }

    private static func plausible(_ inches: Double) -> Double? {
        DiagonalEntry.range.contains(inches) ? inches : nil
    }

    /// Done: what the set-up found is applied in one change (for a full set-up, the display's
    /// previous touchscreen is unpaired in the same change). A test changes nothing. In set-up mode,
    /// back to its overview.
    private mutating func finish(_ run: SetUpRun) {
        setUpRun = nil
        switch run.purpose {
        case .full:
            if let display = run.display {
                pair(run.touchscreen, with: display)
                update(run.touchscreen) {
                    $0.isCalibrated = true
                    $0.diagonalInches = run.diagonal
                    $0.wasOfferedSetUp = true
                }
            }
        case .calibrate:
            update(run.touchscreen) { $0.isCalibrated = true }
        case .test:
            break
        }
        flowEnded(run, stored: true)
    }

    mutating func endSetUp() {
        setUpRun = nil
    }

    /// Whether set-up mode could set it up and could begin now (`canBeSetUp` in the snapshot).
    private func canBeSetUp(_ panel: Panel) -> Bool {
        canBeSetUpByTouch(panel) && setUpModeCouldBegin
    }

    func connectedScreen(of panel: Panel) -> Screen? {
        guard panel.isConnected, let uuid = panel.pairedUUID else { return nil }
        return screens.first { $0.uuid == uuid && $0.isConnected }
    }

    // MARK: - The snapshot

    func snapshot() -> AppSnapshot {
        let connected = screens.filter(\.isConnected)
        let facts = connected.map(Self.facts)
        let connectedPanels = panels.filter(\.isConnected)
        let remembered = panels.filter { !$0.isConnected }.sorted { ($0.name, $0.id.rawValue) < ($1.name, $1.id.rawValue) }

        func pairedPanel(_ screen: Screen) -> Panel? {
            connectedPanels.first { $0.pairedUUID == screen.uuid }
        }
        func label(_ screen: Screen) -> (name: String, detail: String) {
            DisplayLabel.label(
                for: Self.facts(screen), among: facts, customName: displayNames[screen.uuid],
                diagonalInches: pairedPanel(screen)?.diagonalInches.flatMap { DiagonalEntry.range.contains($0) ? $0 : nil })
        }

        let displays = connected
            .sorted { ($0.isMain ? 0 : 1, $0.frame.minX, $0.frame.minY) < ($1.isMain ? 0 : 1, $1.frame.minX, $1.frame.minY) }
            .map { screen in
                let (name, detail) = label(screen)
                return DisplaySnapshot(
                    id: screen.id, uuid: screen.uuid, name: name, detail: detail, frame: screen.frame,
                    isBuiltIn: screen.isBuiltIn, isMain: screen.isMain, pairedTouchscreen: pairedPanel(screen)?.name)
            }

        let touchscreens = (connectedPanels + remembered).map { panel -> TouchscreenSnapshot in
            let screen = connectedScreen(of: panel)
            let status: TouchscreenStatus
            var mode: TouchscreenMode?
            if !panel.isConnected {
                (status, mode) = (.notConnected, nil)
            } else if !isOn {
                (status, mode) = (.tactileOff, .released)
            } else if !hasAccessibility {
                (status, mode) = (.accessibilityMissing, .released)
            } else if !panel.isOn {
                (status, mode) = (.off, panel.whenOff == .ignoreTouches ? .held : .released)
            } else if let uuid = panel.pairedUUID {
                if let screen {
                    let (name, detail) = label(screen)
                    (status, mode) = (.pairedWith(name: name, detail: detail), .driving)
                } else {
                    (status, mode) = (.displayNotConnected(name: displayName(uuid: uuid)), .held)
                }
            } else {
                (status, mode) = (.notSetUp, .held)
            }
            // While set-up mode is on, every connected touchscreen is held for it.
            if setUpRun?.touchscreen == panel.id || (modeRun != nil && panel.isConnected) {
                mode = .settingUp
            }
            let choices: [DisplayChoice] = panel.isConnected
                ? displays.filter { !$0.isBuiltIn }.map { display in
                    let other = connectedPanels.first {
                        $0.id != panel.id && $0.pairedUUID == display.uuid
                    }
                    return DisplayChoice(id: display.id, name: display.name, detail: display.detail, inUseBy: other?.name)
                }
                : []
            let behaviour = panel.behaviour
            return TouchscreenSnapshot(
                id: panel.id, name: panel.name, deviceName: panel.deviceName, isConnected: panel.isConnected,
                isOn: panel.isOn, whenOff: panel.whenOff, mode: mode, status: status,
                notes: panel.isConnected ? panel.notes : [], pairedDisplayID: screen?.id,
                pairedDisplayName: panel.pairedUUID.map(displayName(uuid:)), displayChoices: choices,
                orientation: panel.pairedUUID == nil ? nil : panel.orientation, diagonalInches: panel.diagonalInches,
                reportedDiagonalInches: screen?.reportedDiagonalInches, usbID: panel.usbID, serial: panel.serial,
                location: panel.isConnected ? panel.location : nil, device: panel.isConnected ? panel.device : nil,
                behaviour: BehaviourSnapshot(
                    oneFinger: behaviour.oneFinger ?? defaultOneFinger(panel), oneFingerChoice: behaviour.oneFinger,
                    pointerReturn: behaviour.pointerReturn,
                    showsCircles: behaviour.showsCircles, gestures: behaviour.gestures, rejection: behaviour.rejection,
                    reportsPalms: panel.isConnected && panel.reportsPalms,
                    multiFingerAvailable: !(panel.isConnected && panel.notes.contains(.oneFingerOnly))),
                isCalibrated: panel.pairedUUID != nil && panel.isCalibrated, canBeSetUp: canBeSetUp(panel))
        }

        let warnings = AppWarning.allCases.filter {
            ($0 == .accessibilityMissing && !hasAccessibility) || otherWarnings.contains($0)
        }
        let setUp = setUpRun.map { run in
            SetUpSnapshot(
                touchscreen: run.touchscreen, touchscreenName: panels.first { $0.id == run.touchscreen }?.name ?? "",
                purpose: run.purpose, step: run.step)
        }
        return AppSnapshot(
            appVersion: appVersion, isOn: isOn, warnings: warnings, touchscreens: touchscreens, displays: displays,
            debugLogging: debugLogging, setUp: setUp, setUpMode: setUpModeSnapshot(displays: displays),
            offerSetUpTo: offers(), setUpModeRefusal: setUpModeRefusal,
            gestureTester: testerSnapshot(), recordsFrames: recordsFrames, swipesFollowFingers: swipesFollowFingers,
            canFollowSwipes: canFollowSwipes, launchAtLogin: launchAtLogin)
    }

    /// A display's name, connected or not: its custom name, else its last known macOS name.
    func displayName(uuid: String) -> String {
        displayNames[uuid] ?? screens.first { $0.uuid == uuid }?.macOSName ?? "Display"
    }

    /// The facts `DisplayLabel` needs. The reported size is made from the reported diagonal and the
    /// frame's proportions, so the label shows the diagonal the display reports.
    private static func facts(_ screen: Screen) -> DisplayFacts {
        let aspect = screen.frame.width / screen.frame.height
        let diagonalMM = screen.reportedDiagonalInches * 25.4
        let heightMM = diagonalMM / (aspect * aspect + 1).squareRoot()
        return DisplayFacts(
            displayID: screen.id, uuid: screen.uuid, vendor: 0, model: Int(screen.id), serial: 0,
            nativePixels: CGSize(width: screen.frame.width * 2, height: screen.frame.height * 2),
            sizeMM: CGSize(width: heightMM * aspect, height: heightMM), name: screen.macOSName, frame: screen.frame,
            rotation: 0, isBuiltIn: screen.isBuiltIn, isMain: screen.isMain, mirrors: nil)
    }
}
