// Set-up mode's overview, worked out from the snapshot alone: which card each candidate display gets
// in each stage, where the session card goes, and what each button sends. The model decides every
// stage (`SetUpModeSnapshot`); this only says how each display shows it.
//
// - Choosing: every candidate display offers itself. A free one says "Set up a touchscreen on this
//   screen", with This One; one with a touchscreen says so, with Test and Set Up Again Here; the one
//   just set up in this session says where, and is marked.
// - Waiting for a touch on D: D is bright, "Now touch this screen", with Back; every other card is
//   dimmed, says it waits for D, and keeps its button, so another display can still be chosen.
// - Touched first, T: every card adds "You touched T. Click the screen you touched." above its
//   button; Test goes, and the session card offers Back.
// - The session card: on the built-in display (never a candidate), else beside the first
//   candidate's card. One line per touchscreen, the latest notice, "Esc leaves at any time", Finish.
//   Should the chosen display carry it, its "Now touch this screen" goes in a card beside it. For
//   touch that isn't working right, a way to the touchscreen check, with the mouse: Check This
//   Touchscreen… with one touchscreen, Check… on each line with several. It leaves set-up mode first
//   (`SetUpModeCheck`).

import Foundation
import TactileScreens

/// A button of set-up mode's overview, and what it sends.
enum SetUpModeButton: Hashable, Sendable {
    /// A free display's card: choose it.
    case thisOne(display: UInt32)
    /// A card whose display has a touchscreen: choose it all the same, for the touchscreen touched.
    case setUpAgainHere(display: UInt32)
    /// A card whose display has a touchscreen: the check alone, for that touchscreen, in the mode.
    case test(TouchscreenID)
    /// The chosen display's card, or the session card after a touch first: back to choosing.
    case back
    /// The session card: leave set-up mode.
    case finish

    var command: AppCommand {
        switch self {
        case .thisOne(let display), .setUpAgainHere(let display): return .setUpChoose(displayID: display)
        case .test(let id): return .beginSetUp(id, .test)
        case .back: return .setUpBack
        case .finish: return .cancelSetUp
        }
    }

    var title: String {
        switch self {
        case .thisOne: return Wording.setUpModeThisOne
        case .setUpAgainHere: return Wording.setUpModeSetUpAgain
        case .test: return Wording.test
        case .back: return Wording.setUpModeBack
        case .finish: return Wording.setUpModeFinish
        }
    }
}

/// One candidate display's card in the overview.
struct SetUpModeCard: Equatable, Sendable {
    /// What the display has.
    enum State: Equatable, Sendable {
        /// No touchscreen is paired with it.
        case free
        /// A touchscreen is paired with it; `isJustSetUp` when it is the last one Done in this
        /// session. `canBeTested`: it is connected and can be set up, so Test can run.
        case setUp(touchscreen: TouchscreenID, name: String, isJustSetUp: Bool, canBeTested: Bool)
    }

    /// Where the mode is, from this display's side.
    enum Moment: Equatable, Sendable {
        /// Every display offers itself.
        case offering
        /// This display was chosen: "Now touch this screen".
        case touchHere
        /// Another display was chosen and waits for a touch.
        case waitingElsewhere(displayName: String)
    }

    var displayID: UInt32
    var name: String
    var detail: String
    var state: State
    var moment: Moment
    /// Once a touchscreen was touched before a display was chosen: its name.
    var touchedFirst: String?

    /// What the display has, in a line: free, set up here, or just set up on it.
    var stateLine: String {
        switch state {
        case .free: return Wording.setUpModeOffer
        case .setUp(_, let touchscreenName, let isJustSetUp, _):
            return isJustSetUp
                ? Wording.setUpModeJustSetUp(name: touchscreenName, displayName: name)
                : Wording.setUpModeSetUpHere(name: touchscreenName)
        }
    }

    /// While another display waits for a touch, the card is dimmed with its display, the
    /// just-set-up card's green border too, so the chosen display stands out; else drawn in full.
    var opacity: Double {
        if case .waitingElsewhere = moment { return 0.55 }
        return 1
    }

    var isJustSetUp: Bool {
        if case .setUp(_, _, true, _) = state { return true }
        return false
    }

    /// Its buttons, left to right. The chosen display: Back. A free one: This One. One with a
    /// touchscreen: Test (while every display offers itself, and only when it can run) and Set Up
    /// Again Here.
    var buttons: [SetUpModeButton] {
        if moment == .touchHere { return [.back] }
        switch state {
        case .free:
            return [.thisOne(display: displayID)]
        case .setUp(let touchscreen, _, _, let canBeTested):
            let offersTest = moment == .offering && touchedFirst == nil && canBeTested
            return (offersTest ? [.test(touchscreen)] : []) + [.setUpAgainHere(display: displayID)]
        }
    }

    /// The button drawn prominent, as the thing to do: This One; Set Up Again Here once a
    /// touchscreen was touched first. None on a dimmed card, nor on the chosen display's.
    var prominentButton: SetUpModeButton? {
        guard moment == .offering else { return nil }
        switch state {
        case .free: return .thisOne(display: displayID)
        case .setUp: return touchedFirst == nil ? nil : .setUpAgainHere(display: displayID)
        }
    }
}

/// The session card: every connected touchscreen, the latest notice, the way to the touchscreen
/// check, and Finish.
struct SetUpModeSession: Equatable, Sendable {
    /// How the card offers the touchscreen check.
    enum CheckOffer: Equatable, Sendable {
        /// One touchscreen in the session: "Touch not working right?" and Check This Touchscreen….
        case one(TouchscreenID)
        /// Several: Check… on each touchscreen's line.
        case eachLine
    }

    var lines: [SetUpTouchscreenLine]
    var notice: SetUpModeNotice?
    /// Once a touchscreen was touched before a display was chosen: its name, with Back beside it.
    var touchedFirst: String?
    /// Whether each line's touchscreen can be checked once set-up mode has let go of it
    /// (`SupportCheckAvailability.leavingSetUp`); an earlier check still letting go is the view's
    /// to add, as it changes without the snapshot.
    var checks: [TouchscreenID: SupportCheckAvailability] = [:]

    var checkOffer: CheckOffer? {
        guard let first = lines.first else { return nil }
        return lines.count == 1 ? .one(first.id) : .eachLine
    }
}

/// What Check This Touchscreen… and Check… on the session card do, with the touchscreen's ID: leave
/// set-up mode, then open the check (`SetUpModeCheck`). Renders and previews do less.
typealias CheckTouchscreen = @MainActor (TouchscreenID) -> Void

/// Check This Touchscreen… and Check… on the session card. Set-up mode is left exactly as Finish
/// leaves it (`cancelSetUp`), keeping whatever was set up in it. Then, once the model's snapshot says
/// set-up has let go (no set-up mode, no set-up, and the touchscreen no longer being set up), the
/// check opens for that touchscreen, found again in that snapshot. If set-up still has it (the model
/// didn't leave), or it has gone, no check opens.
enum SetUpModeCheck {
    @MainActor
    static func leaveThenCheck(
        _ id: TouchscreenID, perform: PerformCommand, snapshot: () -> AppSnapshot?, open: (SupportTarget) -> Void
    ) {
        perform(.cancelSetUp)
        guard let after = snapshot(), after.setUp == nil, after.setUpMode == nil else {
            InterfaceLog.log.info("set-up: the check wasn't opened; set-up mode is still on")
            return
        }
        guard let touchscreen = after.touchscreens.first(where: { $0.id == id }), touchscreen.isConnected,
            touchscreen.mode != .settingUp
        else {
            InterfaceLog.log.info("set-up: the check wasn't opened; the touchscreen isn't there now")
            return
        }
        open(SupportTarget(touchscreen))
    }

    /// The app's: the check's window opens on the main actor's next turn, once the set-up screens,
    /// which follow the same snapshot, have come down.
    @MainActor
    static func leaveThenCheck(_ id: TouchscreenID, model: any AppModel) {
        leaveThenCheck(id, perform: { model.perform($0) }, snapshot: { model.snapshot }, open: { target in
            Task { @MainActor in SupportCheckWindow.open(target, perform: { model.perform($0) }) }
        })
    }
}

/// What one display shows in the overview: its card, if it is a candidate; the session card, if it
/// is the session card's display.
struct SetUpModeScreen: Equatable, Sendable {
    var card: SetUpModeCard?
    var session: SetUpModeSession?
    /// A display was chosen and waits for a touch: every other screen is dimmed deeply.
    var aDisplayWaits: Bool

    var hasCards: Bool { card != nil || session != nil }

    /// How much black is laid over the display: none on the chosen one, which is bright; deep while
    /// another waits for a touch, and on a display with no card; else enough to read the cards over
    /// the person's windows.
    var dimming: Double {
        if card?.moment == .touchHere { return 0 }
        return aDisplayWaits || !hasCards ? 0.82 : 0.62
    }

    /// The chosen display also carries the session card (no built-in display, and it is the first
    /// candidate, or a mirror brings the card to it): its "Now touch this screen" goes in a card of
    /// its own beside the session card, both in the middle, rather than on the backdrop above them,
    /// where a long session card would cover it on a short display.
    var saysTouchHereInACard: Bool { card?.moment == .touchHere && session != nil }

    /// Below the middle on the chosen display, under its message on the backdrop; else in the
    /// middle.
    var placement: SetUpControlsPlacement {
        card?.moment == .touchHere && !saysTouchHereInACard ? .belowCentre : .centre
    }
}

extension SetUpScreenRole {
    /// The session card, on the overview screen that has it.
    var session: SetUpModeSession? {
        if case .overview(let overview) = self { return overview.session }
        return nil
    }
}

extension SetUpScreens {
    /// Set-up mode's overview: a screen for each display in the snapshot, in its order. A candidate
    /// display gets its card; the session card goes where `sessionDisplay` says, and takes the
    /// keyboard.
    static func overview(_ mode: SetUpModeSnapshot, in snapshot: AppSnapshot) -> [SetUpScreen] {
        let shown = Set(snapshot.displays.map(\.id))
        let cards = mode.displays.filter { shown.contains($0.id) }
        // A stage the cards can't show is drawn as choosing: a display chosen that has no card, or a
        // flow running with no flow in the snapshot (the next snapshot brings it).
        var waitingOn: SetUpDisplayCard?
        var touchedFirst: String?
        switch mode.stage {
        case .waitingForTouch(let display): waitingOn = cards.first { $0.id == display }
        case .touchedFirst(_, let name): touchedFirst = name
        case .choosing, .running: break
        }
        let lines = Dictionary(mode.touchscreens.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sessionDisplay = Self.sessionDisplay(mode, in: snapshot)
        // Whether each line's touchscreen can be checked, once the card's Check has left the mode.
        var checks: [TouchscreenID: SupportCheckAvailability] = [:]
        for line in mode.touchscreens {
            let touchscreen = snapshot.touchscreens.first { $0.id == line.id }
            checks[line.id] = touchscreen.map { SupportCheckAvailability.leavingSetUp($0) } ?? .notConnected
        }
        let session = SetUpModeSession(
            lines: mode.touchscreens, notice: mode.notice, touchedFirst: touchedFirst, checks: checks)

        return snapshot.displays.map { display in
            let card = cards.first { $0.id == display.id }.map { card -> SetUpModeCard in
                let state: SetUpModeCard.State
                if let touchscreen = card.touchscreen {
                    let line = lines[touchscreen]
                    state = .setUp(
                        touchscreen: touchscreen, name: card.touchscreenName ?? line?.name ?? "",
                        isJustSetUp: touchscreen == mode.justSetUp,
                        canBeTested: line.map { $0.state != .cannotBeSetUp } ?? false)
                } else {
                    state = .free
                }
                let moment: SetUpModeCard.Moment
                if let waitingOn {
                    moment = waitingOn.id == card.id ? .touchHere : .waitingElsewhere(displayName: waitingOn.name)
                } else {
                    moment = .offering
                }
                return SetUpModeCard(
                    displayID: card.id, name: card.name, detail: card.detail, state: state, moment: moment,
                    touchedFirst: touchedFirst)
            }
            let screen = SetUpModeScreen(
                card: card, session: display.id == sessionDisplay ? session : nil, aDisplayWaits: waitingOn != nil)
            return SetUpScreen(
                displayID: display.id, touchscreenName: "", progress: nil, role: .overview(screen),
                hasControls: screen.hasCards, takesKeyboard: display.id == sessionDisplay, placement: screen.placement)
        }
    }

    /// Where the session card goes: on the built-in display, which is never a candidate; else beside
    /// the first candidate's card; else on the first display.
    static func sessionDisplay(_ mode: SetUpModeSnapshot, in snapshot: AppSnapshot) -> UInt32? {
        if let builtIn = snapshot.displays.first(where: \.isBuiltIn) { return builtIn.id }
        let shown = Set(snapshot.displays.map(\.id))
        return mode.displays.first { shown.contains($0.id) }?.id ?? snapshot.displays.first?.id
    }
}
