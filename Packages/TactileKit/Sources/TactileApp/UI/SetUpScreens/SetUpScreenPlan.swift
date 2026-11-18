// What each display shows while set-up mode is on or a set-up runs, worked out from the snapshot
// alone: the interface never decides a step. `SetUpOverlay` puts a screen on every display from this
// plan, and the renders draw the same plan. A running flow (corners, size, check) is drawn as it
// always was, its Cancel reading Back in set-up mode; between flows, set-up mode's overview is drawn
// (`SetUpModePlan.swift`).

import CoreGraphics
import Foundation
import TactileScreens

/// The steps of a set-up, as the screens name them.
enum SetUpStepName: CaseIterable, Sendable {
    case corners, size, check
}

/// A flow's step as the display it is on shows it: which display, its role there, where its buttons
/// go, and the step's name.
struct SetUpStepShown: Equatable, Sendable {
    var display: UInt32
    var role: SetUpScreenRole
    var placement: SetUpControlsPlacement
    var name: SetUpStepName

    init(_ step: SetUpStep, purpose: SetUpPurpose) {
        switch step {
        case .corners(let on, let target, let index, let problem):
            self.init(display: on, role: .corners(target: target, index: index, problem: problem),
                      placement: .belowCentre, name: .corners)
        case .size(let on, let displayReports, let touchscreenReports, let current):
            self.init(display: on, role: .size(SetUpSizeChoices(
                displayReports: displayReports, touchscreenReports: touchscreenReports, current: current)),
                      placement: .centre, name: .size)
        case .check(let on):
            self.init(display: on, role: .check(canRedo: purpose != .test), placement: .bottom, name: .check)
        }
    }

    init(display: UInt32, role: SetUpScreenRole, placement: SetUpControlsPlacement, name: SetUpStepName) {
        self.display = display
        self.role = role
        self.placement = placement
        self.name = name
    }
}

/// The steps a set-up of this purpose goes through, and which one it is at: the line at the top of
/// the screen being touched. A test is the check alone and lists no steps.
struct SetUpProgress: Equatable, Sendable {
    var steps: [SetUpStepName]
    var current: SetUpStepName

    init(steps: [SetUpStepName], current: SetUpStepName) {
        self.steps = steps
        self.current = current
    }

    init(purpose: SetUpPurpose, current: SetUpStepName) {
        switch purpose {
        case .full: steps = [.corners, .size, .check]
        case .calibrate: steps = [.corners, .check]
        case .test: steps = []
        }
        self.current = current
    }
}

/// The size card's choices: the display's reported diagonal and the touchscreen's, each where it is
/// offered, then another size typed in. Which one is chosen, and the text typed, belong to the card
/// until Continue; nothing is sent before.
struct SetUpSizeChoices: Equatable, Sendable {
    enum Choice: Hashable, Sendable {
        /// As reported: no diagonal of its own, so the display's report is used.
        case displayReport
        /// The touchscreen's own report, as a diagonal of its own.
        case touchscreenReport
        /// A diagonal typed in.
        case another
    }

    var displayReports: Double?
    var touchscreenReports: Double?
    /// The diagonal in force now, if one was set.
    var current: Double?

    var choices: [Choice] {
        (displayReports == nil ? [] : [.displayReport]) + (touchscreenReports == nil ? [] : [.touchscreenReport])
            + [.another]
    }

    /// The diagonal in force, if one is set: the report it equals, else typed in. With none, as the
    /// display reports, else as the touchscreen reports.
    var initialChoice: Choice {
        if let current {
            if let displayReports, Self.same(current, displayReports) { return .displayReport }
            if let touchscreenReports, Self.same(current, touchscreenReports) { return .touchscreenReport }
            return .another
        }
        return choices[0]
    }

    var initialText: String {
        initialChoice == .another ? DiagonalEntry.text(for: current) : ""
    }

    /// What Continue sends for `choice` and the text typed; nil while it can't be pressed.
    func command(_ choice: Choice, text: String) -> AppCommand? {
        guard choices.contains(choice) else { return nil }
        switch choice {
        case .displayReport:
            return .setUpConfirmSize(inches: nil)
        case .touchscreenReport:
            return touchscreenReports.map { .setUpConfirmSize(inches: $0) }
        case .another:
            guard case .inches(let value) = DiagonalEntry.parse(text) else { return nil }
            return .setUpConfirmSize(inches: value)
        }
    }

    private static func same(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.05 }
}

/// What one display shows.
enum SetUpScreenRole: Equatable, Sendable {
    /// Set-up mode between flows: the display's card, the session card, or both (see
    /// `SetUpModeScreen`).
    case overview(SetUpModeScreen)
    /// Corners, on the display being set up: one target, at a point of its picture (0…1 from the
    /// top-left).
    case corners(target: CGPoint, index: Int, problem: SetUpProblem?)
    /// Size, on the display being set up.
    case size(SetUpSizeChoices)
    /// Check, on the display being set up: clear, the model's circles show where touches land.
    case check(canRedo: Bool)
    /// Corners, size or check are on another display: this one is dimmed and says which. The name
    /// is nil when that display is no longer in the snapshot.
    case elsewhere(displayName: String?)

    /// Whether this is the screen the touchscreen is touched on, where the buttons must say they
    /// answer the mouse.
    var isTouched: Bool {
        switch self {
        case .corners, .size, .check: return true
        case .overview(let overview): return overview.card?.moment == .touchHere
        case .elsewhere: return false
        }
    }
}

/// Where a screen's buttons go.
enum SetUpControlsPlacement: Equatable, Sendable {
    /// Just below the middle, under the message drawn above it.
    case belowCentre
    /// In the middle: the size card.
    case centre
    /// Near the bottom edge, leaving the middle clear: the check.
    case bottom
}

/// One display's set-up screen.
struct SetUpScreen: Equatable, Identifiable, Sendable {
    var displayID: UInt32
    /// The touchscreen a flow sets up; empty in set-up mode's overview.
    var touchscreenName: String
    /// Where a flow is; nil in set-up mode's overview.
    var progress: SetUpProgress?
    var role: SetUpScreenRole
    /// Whether it has buttons. During a flow outside set-up mode, a display paired with another
    /// connected touchscreen has none, so that touchscreen's taps there never land on one; its screen
    /// is click-through throughout. In set-up mode every touchscreen is held and none drives, so
    /// every display has them during a flow, the one being set up above all (it may have been taken
    /// from another touchscreen); and in the overview, every display with a card.
    var hasControls: Bool
    /// The one screen whose buttons take the keyboard, so Esc and Return reach the set-up.
    var takesKeyboard: Bool
    var placement: SetUpControlsPlacement
    /// Corners: the targets started again from the first with no problem to say why (the display
    /// was turned in macOS mid-round). Shown until the next tap is taken.
    var restartedCorners = false
    /// A flow run inside set-up mode: its Cancel reads Back and returns to the overview, and Esc
    /// leaves the whole mode.
    var inSetUpMode = false

    var id: UInt32 { displayID }

    /// How much black is laid over the display. During a flow, a display with no buttons is another
    /// touchscreen's: it stays usable, lightly dimmed; the others not being touched are dimmed, so
    /// the one being touched stands out, which has a background of its own, or is clear. In the
    /// overview, see `SetUpModeScreen.dimming`.
    var dimming: Double {
        switch role {
        case .corners, .size, .check: return 0
        case .overview(let overview): return overview.dimming
        case .elsewhere: return hasControls ? 0.6 : 0.28
        }
    }

    /// Whether its line goes at an edge instead of the middle: on another touchscreen's display,
    /// out of the way of what the person is doing there.
    var messageAtEdge: Bool { dimming > 0 && !hasControls }

    /// Whether its backdrop takes the mouse and swallows it. In set-up mode's overview, always: the
    /// click is the choice, and a click outside the cards does nothing. During a flow, where it has
    /// buttons and hides what is beneath (the corners, the size card), so a click there never
    /// reaches a window the person can't see; the check is clear, over the person's own windows, and
    /// the dimmed displays (another touchscreen's above all, which has no buttons) let clicks
    /// through.
    var backdropTakesMouse: Bool {
        if case .overview = role { return true }
        guard hasControls else { return false }
        switch role {
        case .corners, .size: return true
        case .check, .elsewhere, .overview: return false
        }
    }

    /// The moment the keyboard follows: it is given to the screen that takes it when the screens go
    /// up and whenever this changes. The overview, or the flow's step.
    var keyboardMoment: SetUpStepName? { progress?.current }

    /// Whether a key presses one of its card's buttons: outside set-up mode, Esc is Cancel's and
    /// Return the step's default button's; in the mode, only a default button (the size's
    /// Continue, the check's Done) answers a key, since Back has none (Esc leaves the whole mode).
    var keyboardPressesItsButtons: Bool {
        switch role {
        case .size, .check: return true
        case .corners, .elsewhere: return !inSetUpMode
        case .overview: return false
        }
    }

    /// The hint beside the buttons of the screen being touched: the mouse, and the keyboard where a
    /// key presses one of them.
    var mouseHint: String { keyboardPressesItsButtons ? Wording.setUpMouseHint : Wording.setUpMouseOnlyHint }
}

/// What the overlay is told: whether set-up mode is on or a set-up runs, and its screens. Told
/// apart, so that a set-up with no displays for a moment (the displays reconfiguring) keeps its
/// screens, and the text typed in them, rather than taking them down.
struct SetUpPresentation: Equatable, Sendable {
    enum Change: Equatable, Sendable {
        /// No set-up runs: the screens come down.
        case takeDown
        /// A set-up runs with no display to show it on, for now: the screens stay as they are.
        case keep
        /// The screens go up, or change, to match the plan.
        case show
    }

    var isRunning: Bool
    var plan: [SetUpScreen]

    init(isRunning: Bool, plan: [SetUpScreen]) {
        self.isRunning = isRunning
        self.plan = plan
    }

    init(_ snapshot: AppSnapshot) {
        self.init(isRunning: snapshot.setUp != nil || snapshot.setUpMode != nil, plan: SetUpScreens.plan(snapshot))
    }

    var change: Change {
        guard isRunning else { return .takeDown }
        return plan.isEmpty ? .keep : .show
    }
}

enum SetUpScreens {
    /// How many corner targets there are.
    static let targetCount = Calibration.targets.count

    /// Whether a set-up card drops a key-down: a repeat of Return (key code 36) or Enter (76), and
    /// nothing else. Return held on the size card confirms the size once; its repeats would press
    /// the next card's default button, and one arriving after the check's reaction time would be
    /// Done, skipping the check. Every first press passes, and every other key's repeats (Esc,
    /// Delete, the digits in the size field).
    static func dropsKeyDown(keyCode: UInt16, isARepeat: Bool) -> Bool {
        isARepeat && (keyCode == 36 || keyCode == 76)
    }
    /// The space between the middle of a display and the buttons below it, in points.
    static let controlsGap: CGFloat = 28
    /// The space between the bottom edge and the check's buttons, in points.
    static let bottomMargin: CGFloat = 56
    /// The least space kept between the buttons and a display's sides.
    static let sideMargin: CGFloat = 16

    /// A screen for each display in the snapshot, in its order, while set-up mode is on or a set-up
    /// runs; none otherwise. A running flow is drawn whether or not the mode is on; between flows,
    /// the mode's overview.
    static func plan(_ snapshot: AppSnapshot) -> [SetUpScreen] {
        guard let setUp = snapshot.setUp else {
            return snapshot.setUpMode.map { overview($0, in: snapshot) } ?? []
        }
        let step = SetUpStepShown(setUp.step, purpose: setUp.purpose)
        let progress = SetUpProgress(purpose: setUp.purpose, current: step.name)
        let inSetUpMode = snapshot.setUpMode != nil
        let others = snapshot.touchscreens.filter { $0.id != setUp.touchscreen && $0.isConnected }
        // In set-up mode every touchscreen is held: none can tap a button by mistake.
        func hasControls(_ display: UInt32) -> Bool {
            inSetUpMode || !others.contains { $0.pairedDisplayID == display }
        }

        var screens = snapshot.displays.map { display -> SetUpScreen in
            let isOn = display.id == step.display
            return SetUpScreen(
                displayID: display.id, touchscreenName: setUp.touchscreenName, progress: progress,
                role: isOn ? step.role : elsewhere(step.display, in: snapshot), hasControls: hasControls(display.id),
                takesKeyboard: false, placement: isOn ? step.placement : .belowCentre, inSetUpMode: inSetUpMode)
        }

        // The keyboard: on the display being set up; failing that, the first screen with buttons.
        let chosen = screens.firstIndex { $0.displayID == step.display && $0.hasControls }
            ?? screens.firstIndex(where: \.hasControls)
        if let chosen {
            screens[chosen].takesKeyboard = true
        }
        return screens
    }

    /// The plan put on the screens there are. `screen(for:)` gives, for a display, the display whose
    /// screen shows its picture: itself, or for a display that mirrors another, the one whose
    /// picture it shows; nil when no screen shows it. Where several displays share a screen, the
    /// screen shows the one being touched (or, in the overview, waiting for a touch), else one with a
    /// card, else the screen's own. During a flow it has buttons only if every display it shows may
    /// have them, since another touchscreen's taps on any of them land there. In the overview it
    /// keeps the session card if any display it shows had it, and has buttons when it has a card.
    /// A display no screen shows is listed in `unplaced`, to be logged.
    static func placed(
        _ plan: [SetUpScreen], screen: (UInt32) -> UInt32?
    ) -> (screens: [(screenID: UInt32, screen: SetUpScreen)], unplaced: [UInt32]) {
        var groups: [(screenID: UInt32, entries: [SetUpScreen])] = []
        var unplaced: [UInt32] = []
        for entry in plan {
            guard let screenID = screen(entry.displayID) else {
                unplaced.append(entry.displayID)
                continue
            }
            if let index = groups.firstIndex(where: { $0.screenID == screenID }) {
                groups[index].entries.append(entry)
            } else {
                groups.append((screenID, [entry]))
            }
        }
        func rank(_ entry: SetUpScreen, on screenID: UInt32) -> (Int, Int) {
            let role: Int
            switch entry.role {
            case .corners, .size, .check: role = 2
            case .overview(let overview):
                role = overview.card?.moment == .touchHere ? 2 : overview.card != nil ? 1 : 0
            case .elsewhere: role = 0
            }
            return (role, entry.displayID == screenID ? 1 : 0)
        }
        var placed = groups.map { group -> (screenID: UInt32, screen: SetUpScreen) in
            var winner = group.entries.max { rank($0, on: group.screenID) < rank($1, on: group.screenID) }!
            if case .overview(var overview) = winner.role {
                overview.session = overview.session ?? group.entries.lazy.compactMap(\.role.session).first
                winner.role = .overview(overview)
                winner.hasControls = overview.hasCards
                winner.placement = overview.placement
            } else {
                winner.hasControls = group.entries.allSatisfy(\.hasControls)
            }
            winner.takesKeyboard = group.entries.contains(where: \.takesKeyboard) && winner.hasControls
            return (group.screenID, winner)
        }
        if !placed.contains(where: { $0.screen.takesKeyboard }), let first = placed.firstIndex(where: { $0.screen.hasControls }) {
            placed[first].screen.takesKeyboard = true
        }
        return (placed, unplaced)
    }

    /// The plan for `snapshot`, following on from `previous`, the plan shown until now: the one thing
    /// a snapshot alone can't say is that the corners went back to the first target without a
    /// problem, which only the target shown before can tell.
    static func plan(_ snapshot: AppSnapshot, after previous: [SetUpScreen]) -> [SetUpScreen] {
        following(plan(snapshot), after: previous)
    }

    /// `plan`, with what only the plan before it can tell (see `plan(_:after:)`).
    static func following(_ plan: [SetUpScreen], after previous: [SetUpScreen]) -> [SetUpScreen] {
        plan.map { screen in
            guard case .corners(_, 0, nil) = screen.role,
                let before = previous.first(where: { $0.displayID == screen.displayID }),
                case .corners(_, let earlier, _) = before.role
            else { return screen }
            var screen = screen
            screen.restartedCorners = earlier > 0 || before.restartedCorners
            return screen
        }
    }

    private static func elsewhere(_ display: UInt32, in snapshot: AppSnapshot) -> SetUpScreenRole {
        .elsewhere(displayName: snapshot.displays.first { $0.id == display }?.name)
    }

    /// Where the buttons of `size` go on a display whose frame is `screen`, both in AppKit's
    /// coordinates (origin bottom-left, y up): centred across, placed as `placement` says, in whole
    /// points, and never past the display's edges.
    static func controlsFrame(_ placement: SetUpControlsPlacement, size: CGSize, on screen: CGRect) -> CGRect {
        let width = min(size.width, max(0, screen.width - 2 * sideMargin))
        let height = min(size.height, screen.height)
        let y: CGFloat
        switch placement {
        case .centre: y = screen.midY - height / 2
        case .belowCentre: y = screen.midY - controlsGap - height
        case .bottom: y = screen.minY + bottomMargin
        }
        let x = (screen.midX - width / 2).rounded()
        let clampedY = min(max(y.rounded(), screen.minY), screen.maxY - height)
        return CGRect(x: x, y: clampedY, width: width.rounded(), height: height.rounded())
    }
}
