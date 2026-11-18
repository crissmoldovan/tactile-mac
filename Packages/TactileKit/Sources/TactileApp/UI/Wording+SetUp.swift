// The words of set-up mode, the set-up screens and the first-run window. Sentence case, except the
// buttons and menu items.
//
// Where the accepted mockup and the plan differ, the plan's later wording is used: "Press Esc to
// cancel." (the plan's call 3: Esc or the Cancel button cancels, moving the mouse does not), where
// mockup 8 had "Press Esc or use the mouse to cancel." In set-up mode Esc leaves the whole mode, and
// a flow's Cancel reads Back, so the flow screens there say "Press Esc to leave set-up."

import Foundation

extension Wording {

    // MARK: - The first-run window

    /// "ILITEK-TP isn’t set up"; "ILITEK-TP and TouchScreen aren’t set up"; "A, B and C aren’t set
    /// up".
    public static func firstRunTitle(names: [String]) -> String {
        names.count == 1 ? "\(names[0]) isn’t set up" : "\(list(names)) aren’t set up"
    }

    /// What is wrong and what setting up takes, for one touchscreen or several.
    public static func firstRunMessage(count: Int) -> String {
        count == 1
            ? "Tactile ignores it until it knows which display it is on. Setting up takes about a minute: click its screen, touch it, then touch four targets."
            : "Tactile ignores them until it knows which display each one is on. Setting up takes about a minute for each: click its screen, touch it, then touch four targets."
    }

    public static let firstRunSetUp = "Set Up…"
    public static let firstRunNotNow = "Not Now"
    /// The window's title, for VoiceOver and the window list; the title bar doesn't show it.
    public static let firstRunWindowTitle = "Set Up Touchscreens"

    /// "A", "A and B", "A, B and C".
    static func list(_ names: [String]) -> String {
        guard let last = names.last else { return "" }
        guard names.count > 1 else { return last }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }

    // MARK: - Set-up mode: where it begins

    /// The menu item that begins set-up mode.
    public static let setUpTouchscreens = "Set Up Touchscreens…"

    /// Why Set Up Touchscreens… can't be used now: beneath it in the menu.
    static func setUpModeUnavailable(_ reason: SetUpModeAvailability.Reason) -> String {
        switch reason {
        case .running: return "A set-up is running."
        case .tactileOff: return "Turn Tactile on to set up touchscreens."
        case .accessibilityMissing: return "Tactile needs Accessibility access to set up touchscreens."
        case .noTouchscreen: return "Connect a touchscreen first."
        case .noneCanBeSetUp: return "None of the connected touchscreens can be set up. Settings says why."
        case .noExternalDisplay: return "Connect an external display first."
        case .notNow: return "Set-up can’t begin just now. Try again in a moment."
        case .noDisplayToChoose: return setUpNoDisplayToChoose
        }
    }

    /// Set-up mode can't begin: every external display is in a mirror set.
    static let setUpNoDisplayToChoose =
        "No display can be chosen: displays that mirror each other can’t be told apart. Stop mirroring first."

    // MARK: - Set-up mode: a display's card

    /// A free display's card.
    public static let setUpModeOffer = "Set up a touchscreen on this screen"
    /// A display's card, when a touchscreen is paired with it.
    public static func setUpModeSetUpHere(name: String) -> String { "✓ \(name) is set up here" }
    /// The card of the display the last touchscreen was set up on, in this session.
    public static func setUpModeJustSetUp(name: String, displayName: String) -> String {
        "✓ \(name) is set up on \(displayName)"
    }
    /// The mark beside a card just set up.
    public static let setUpModeJustDone = "Just set up"

    /// The chosen display, bright.
    public static let setUpModeTouchHere = "Now touch this screen"
    public static let setUpModeTouchHint = "Touch it anywhere with one finger, then lift it."
    /// Every other display's card while the chosen one waits for a touch.
    public static func setUpModeWaiting(displayName: String) -> String { "Waiting for a touch on \(displayName)" }
    /// Every card, once a touchscreen was touched before a display was chosen.
    public static func setUpModeTouchedFirst(name: String) -> String {
        "You touched \(name). Click the screen you touched."
    }

    public static let setUpModeThisOne = "This One"
    public static let setUpModeSetUpAgain = "Set Up Again Here"
    public static let setUpModeBack = "Back"
    public static let setUpModeFinish = "Finish"

    // MARK: - Set-up mode: the session card

    public static let setUpModeTitle = "Set Up Touchscreens"
    public static let setUpModeIntro =
        "On the screen that has a touchscreen, click This One, then touch that screen. Or touch it first, then click its screen."
    public static let setUpModeEscLeaves = "Esc leaves at any time."
    /// Beside Back on the session card, once a touchscreen was touched first.
    public static func setUpModeYouTouched(name: String) -> String { "You touched \(name)." }

    /// A touchscreen's line on the session card.
    public static func setUpModeLine(_ state: SetUpTouchscreenLine.State) -> String {
        switch state {
        case .setUp(let displayName): return "Set up on \(displayName)"
        case .notSetUp: return "Not set up"
        case .cannotBeSetUp: return "Can’t be set up"
        }
    }

    /// The latest thing set-up mode has to tell, on the session card.
    public static func setUpModeNotice(_ notice: SetUpModeNotice) -> String {
        switch notice {
        case .cannotBeSetUp(_, let name): return "\(name) can’t be set up, so its touch was ignored."
        case .displayGone(let name): return "\(name) was disconnected. Choose another screen."
        case .touchscreenGone(let name): return "\(name) was disconnected. Nothing about it was changed."
        }
    }

    /// A display set-up mode shows no card on: it is neither a candidate nor the session card's.
    public static let setUpModeElsewhere = "Setting up touchscreens"

    // MARK: - Every set-up screen

    public static let setUpPressEsc = "Press Esc to cancel."
    /// In set-up mode, where Esc leaves the whole mode.
    public static let setUpPressEscToLeave = "Press Esc to leave set-up."
    /// Beside the buttons on the screen being touched: the touchscreen's touches go to the set-up,
    /// so only the mouse (or trackpad) or the keyboard presses a button: Esc cancels, Return presses
    /// the step's default button.
    public static let setUpMouseHint = "Use the mouse or the keyboard for these buttons."
    /// In set-up mode, beside a card whose one button is Back, which answers no key (Esc leaves the
    /// whole mode).
    public static let setUpMouseOnlyHint = "Use the mouse for this button."

    static func setUpStepName(_ step: SetUpStepName) -> String {
        switch step {
        case .corners: return "Corners"
        case .size: return "Size"
        case .check: return "Check"
        }
    }

    /// The name of a set-up that is the check step alone.
    public static let setUpTest = "Test"

    /// A display that shows no step: the set-up is on another display, whose name isn't known.
    public static func setUpSettingUp(name: String) -> String { "Setting up \(name)" }

    /// Every other display, once the set-up is on one display.
    public static func setUpElsewhere(name: String, displayName: String?) -> String {
        guard let displayName else { return setUpSettingUp(name: name) }
        return "Setting up \(name) on \(displayName)"
    }

    // MARK: - Corners

    public static let setUpCornersInstruction = "Touch the centre of the target."

    /// "2 of 4", for the target at `index` (from 0).
    public static func setUpCornersProgress(index: Int) -> String {
        "\(index + 1) of \(SetUpScreens.targetCount)"
    }

    /// The corners started again from the first target with no problem (the display was turned in
    /// macOS mid-round), until the next tap is taken.
    public static let setUpCornersRestarted = "Starting again from the first corner."

    /// Why the last round was refused.
    public static func setUpProblem(_ problem: SetUpProblem) -> String {
        switch problem {
        case .tapsDidNotFit: return "The taps didn’t fit. Touch the four targets again."
        case .ambiguous: return "Those taps could fit more than one way. Tap each target again."
        case .tooManyFingers: return "More than one finger touched. Touch the target with one finger."
        case .moved: return "The finger slid. Touch the target and lift without sliding."
        }
    }

    // MARK: - Size

    /// The size card's question: what the display reports, else what the touchscreen reports.
    public static func setUpSizeQuestion(displayReports: Double?, touchscreenReports: Double?) -> String {
        if let displayReports {
            return "This screen reports \(inches(displayReports)). Is that right?"
        }
        if let touchscreenReports {
            return "The touchscreen reports \(inches(touchscreenReports)). Is that right?"
        }
        return "How big is this screen?"
    }

    /// Beside a choice's size, or the choice itself for Another size.
    static func setUpSizeChoice(_ choice: SetUpSizeChoices.Choice) -> String {
        switch choice {
        case .displayReport: return "what the display reports"
        case .touchscreenReport: return "what the touchscreen reports"
        case .another: return "Another size"
        }
    }

    public static let setUpSizeHint = "Measured from corner to corner of the picture, in inches."
    public static let setUpContinue = "Continue"

    // MARK: - Check

    public static let setUpCheckInstruction = "Touch anywhere to see where it lands."
    public static let setUpRedo = "Redo"
    public static let setUpDone = "Done"
}
