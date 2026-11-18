import TactileGestures
import TactileScreens
import XCTest

@testable import TactileApp

/// The words of 0.3.0: the behaviour controls, set-up by touch, the set-up screens, the first-run
/// window, General's additions and the warnings' buttons. Every case of every enum.
final class WordingBehaviourTests: XCTestCase {

    // MARK: - Notes and states

    func testTheNewNotes() {
        XCTAssertEqual(
            Wording.note(.macOSIgnoresIt),
            "macOS ignores this touchscreen by itself, so “Leave it to macOS” does nothing here.")
        XCTAssertEqual(
            Wording.note(.cannotBeToldApart),
            "It can’t be told apart from an identical touchscreen, so Tactile can’t keep settings for it.")
    }

    func testTheMenuCarriesCannotBeToldApartButNotMacOSIgnoresIt() {
        XCTAssertEqual(Wording.menuState(.notSetUp, notes: [.cannotBeToldApart]), "Not set up · can’t be told apart")
        XCTAssertEqual(
            Wording.menuState(.pairedWith(name: "HDMI", detail: ""), notes: [.macOSIgnoresIt]), "Paired with HDMI")
    }

    func testATouchscreenBeingSetUp() {
        var ilitek = UIFixtures.desk.touchscreens[0]
        ilitek.mode = .settingUp
        XCTAssertEqual(Wording.statusLine(for: ilitek), "Being set up. Its touches go to the set-up screens.")
        XCTAssertEqual(Wording.menuState(for: ilitek), "Being set up")
    }

    // MARK: - Set-up by touch, calibration and test

    func testTheSetUpButtons() {
        XCTAssertEqual(Wording.setUpByTouch, "Set Up by Touch…")
        XCTAssertEqual(Wording.setUpTouchscreens, "Set Up Touchscreens…")
        XCTAssertEqual(Wording.alignment, "Alignment")
        XCTAssertEqual(Wording.alignmentState(isCalibrated: true), "Calibrated")
        XCTAssertEqual(Wording.alignmentState(isCalibrated: false), "Whole glass")
        XCTAssertEqual(Wording.calibrateCorners, "Calibrate Corners…")
        XCTAssertEqual(Wording.test, "Test")
        XCTAssertEqual(Wording.useWholeGlass, "Use Whole Glass")
        XCTAssertEqual(Wording.useWholeGlassQuestion(name: "ILITEK-TP"), "Use the whole glass for “ILITEK-TP”?")
        XCTAssertFalse(Wording.useWholeGlassMessage.isEmpty)
    }

    func testWhySetUpIsUnavailable() {
        let cases: [(SetUpAvailability.Reason, String)] = [
            (.notConnected, "It isn’t connected."),
            (.beingSetUp, "It is being set up now."),
            (.anotherBeingSetUp, "Another touchscreen is being set up."),
            (.setUpModeOn, "Set-up is running on the screens."),
            (.tactileOff, "Turn Tactile on to set it up."),
            (.accessibilityMissing, "Tactile needs Accessibility access to set it up."),
            (.cannotBeToldApart, "Tactile can’t keep settings for it."),
            (.touchesCannotBeRead, "Its touches can’t be read."),
            (.macOSAlsoHandlesIt,
             "macOS is also handling this touchscreen, so it can’t be set up. Quit any other app that reads it, then unplug it and plug it back in."),
            (.noExternalDisplay, "Connect an external display first."),
            (.notNow, "Set-up can’t begin just now. Try again in a moment."),
            (.unpaired, "Pair it with a display first."),
            (.displayNotConnected, "Its display isn’t connected."),
        ]
        for (reason, expected) in cases {
            XCTAssertEqual(Wording.setUpUnavailable(reason), expected, "\(reason)")
        }
    }

    func testWhyTheFitControlsWait() {
        XCTAssertEqual(Wording.setUpRunning, "A set-up is running. Finish or cancel it to change these.")
    }

    // MARK: - Behaviour

    func testOneFinger() {
        XCTAssertEqual(Wording.oneFingerLabel, "One finger")
        XCTAssertEqual(OneFingerMode.allCases.map(Wording.oneFinger), ["Automatic", "Always drag", "Always scroll"])
        XCTAssertEqual(OneFingerMode.allCases.map { Wording.oneFingerExplanation($0, ringShows: true) }, [
            "Drags or scrolls depending on what’s under it", "Drags, as a mouse would",
            "Scrolls, as on a phone. To drag, rest a finger until the ring appears, then move it.",
        ])
        XCTAssertEqual(OneFingerMode.allCases.map { Wording.oneFingerExplanation($0, ringShows: false) }, [
            "Drags or scrolls depending on what’s under it", "Drags, as a mouse would",
            "Scrolls, as on a phone. To drag, rest a finger for a moment, then move it.",
        ], "no ring to wait for: long-press or the circles off")
        XCTAssertEqual(OneFingerMode.allCases.map(Wording.oneFingerDefault),
                       ["Default (Automatic)", "Default (Always drag)", "Default (Always scroll)"])
    }

    func testThePointer() {
        XCTAssertEqual(Wording.pointerReturnLabel, "After a touch, the pointer")
        XCTAssertEqual(PointerReturn.allCases.map(Wording.pointerReturn), ["Goes back where it was", "Stays where you touched"])
    }

    func testTheGroupsAndSwitches() {
        XCTAssertEqual(Wording.behaviour, "Behaviour")
        XCTAssertEqual(Wording.touchCircles, "Touch circles")
        XCTAssertEqual(Wording.gestures, "Gestures")
        XCTAssertEqual(GestureRow.Kind.allCases.map(Wording.gesture), [
            "Two-finger scroll", "Pinch to zoom", "Two-finger tap for right-click", "Three- and four-finger swipes",
            "Two-finger rotate", "Long-press for right-click",
        ])
        XCTAssertEqual(Wording.gestureExplanation(.swipes), "Desktops, Mission Control and App Exposé")
        XCTAssertEqual(Wording.gestureExplanation(.longPress), "Rest a finger for a moment, then lift it")
        for kind in [GestureRow.Kind.twoFingerScroll, .pinch, .twoFingerTap, .rotate] {
            XCTAssertNil(Wording.gestureExplanation(kind), "\(kind)")
        }
        XCTAssertEqual(
            Wording.oneFingerOnlyGestures,
            "One finger only: this touchscreen stayed in mouse mode. Long-press is its right-click.")
        XCTAssertEqual(
            Wording.swipesNeedShortcuts,
            "Swipes need the Mission Control shortcuts, which are off. Turn them on in System Settings › Keyboard › Keyboard Shortcuts › Mission Control.")
    }

    func testAccidentalTouches() {
        XCTAssertEqual(Wording.accidentalTouches, "Accidental touches")
        XCTAssertEqual(Wording.palmRejection, "Palm rejection")
        XCTAssertEqual(Wording.palmExplanation(reportsPalms: true), "Ignores a resting palm, and a whole hand on the glass.")
        XCTAssertEqual(
            Wording.palmExplanation(reportsPalms: false),
            "This touchscreen doesn’t report the size of a touch, so only a whole hand can be recognised.")
        XCTAssertEqual(Wording.edgeMargin, "Ignore touches starting near the edge")
        XCTAssertEqual(Wording.edgeMarginValue(0), "Off")
        XCTAssertEqual(Wording.edgeMarginValue(4), "4 mm")
        XCTAssertEqual(Wording.edgeMarginValue(10), "10 mm")
        XCTAssertEqual(Wording.edgeMarginValue(2.5), "2.5 mm")
        XCTAssertEqual(Wording.edgeMarginValue(.nan), "Off")
    }

    func testCopyAndReset() {
        XCTAssertEqual(Wording.copySettingsFrom, "Copy Settings From…")
        XCTAssertEqual(Wording.copySource(name: "TouchScreen", isConnected: true), "TouchScreen")
        XCTAssertEqual(Wording.copySource(name: "Old panel", isConnected: false), "Old panel (not connected)")
        XCTAssertEqual(Wording.reset, "Reset")
        XCTAssertEqual(Wording.resetQuestion(name: "ILITEK-TP"), "Reset the behaviour of “ILITEK-TP”?")
        XCTAssertFalse(Wording.resetMessage.isEmpty)
        XCTAssertEqual(Wording.behaviourFootnote, "Copy and Reset change the behaviour settings only, never the pairing.")
    }

    // MARK: - General

    func testGeneralsAdditions() {
        XCTAssertEqual(Wording.recordFrames, "Record frames")
        XCTAssertEqual(
            Wording.recordFramesExplanation,
            "Writes each touchscreen’s frames to a file in ~/Library/Logs/Tactile, for use as tests.")
        XCTAssertEqual(Wording.copyDiagnosticsLabel, "Copy diagnostics")
        XCTAssertEqual(Wording.copyDiagnosticsExplanation, "Touchscreens, displays, pairings, states and warnings.")
        XCTAssertEqual(Wording.copyDiagnosticsButton, "Copy")
        XCTAssertEqual(Wording.copied, "Copied")
    }

    func testEveryWarningsButton() {
        XCTAssertEqual(
            Wording.warningAction(.accessibilityMissing),
            WarningAction(title: "Open Accessibility Settings…", kind: .command(.askForAccessibility)))
        XCTAssertEqual(
            Wording.warningAction(.missionControlShortcutsOff),
            WarningAction(title: "Open Keyboard Settings…", kind: .openKeyboardSettings))
        XCTAssertEqual(Wording.warningAction(.touchUpRunning), WarningAction(title: "Quit Touch Up", kind: .quitTouchUp))
        XCTAssertNil(Wording.warningAction(.settingsSetAside))
    }

    // MARK: - The first-run window

    /// For one, two and three touchscreens.
    func testTheFirstRunWindow() {
        XCTAssertEqual(Wording.firstRunTitle(names: ["ILITEK-TP"]), "ILITEK-TP isn’t set up")
        XCTAssertEqual(Wording.firstRunTitle(names: ["ILITEK-TP", "TouchScreen"]), "ILITEK-TP and TouchScreen aren’t set up")
        XCTAssertEqual(Wording.firstRunTitle(names: ["ILITEK-TP", "TouchScreen", "Old panel"]),
                       "ILITEK-TP, TouchScreen and Old panel aren’t set up")
        XCTAssertEqual(
            Wording.firstRunMessage(count: 1),
            "Tactile ignores it until it knows which display it is on. Setting up takes about a minute: click its screen, touch it, then touch four targets.")
        for count in [2, 3] {
            XCTAssertEqual(
                Wording.firstRunMessage(count: count),
                "Tactile ignores them until it knows which display each one is on. Setting up takes about a minute for each: click its screen, touch it, then touch four targets.")
        }
        XCTAssertEqual(Wording.firstRunSetUp, "Set Up…")
        XCTAssertEqual(Wording.firstRunNotNow, "Not Now")
        XCTAssertEqual(Wording.firstRunWindowTitle, "Set Up Touchscreens")
    }

    // MARK: - The set-up screens

    func testTheOtherDisplaysDuringAFlow() {
        XCTAssertEqual(Wording.setUpSettingUp(name: "ILITEK-TP"), "Setting up ILITEK-TP")
        XCTAssertEqual(
            Wording.setUpElsewhere(name: "ILITEK-TP", displayName: "HDMI"), "Setting up ILITEK-TP on HDMI")
        XCTAssertEqual(Wording.setUpElsewhere(name: "ILITEK-TP", displayName: nil), "Setting up ILITEK-TP")
    }

    func testTheStepNames() {
        XCTAssertEqual(SetUpStepName.allCases.map(Wording.setUpStepName), ["Corners", "Size", "Check"])
        XCTAssertEqual(Wording.setUpTest, "Test")
    }

    func testTheCorners() {
        XCTAssertEqual(Wording.setUpCornersInstruction, "Touch the centre of the target.")
        XCTAssertEqual(Wording.setUpCornersProgress(index: 1), "2 of 4")
        XCTAssertEqual(Wording.setUpCornersProgress(index: 0), "1 of 4")
        XCTAssertEqual(Wording.setUpCornersRestarted, "Starting again from the first corner.")
    }

    func testEveryProblem() {
        let cases: [(SetUpProblem, String)] = [
            (.tapsDidNotFit, "The taps didn’t fit. Touch the four targets again."),
            (.ambiguous, "Those taps could fit more than one way. Tap each target again."),
            (.tooManyFingers, "More than one finger touched. Touch the target with one finger."),
            (.moved, "The finger slid. Touch the target and lift without sliding."),
        ]
        for (problem, expected) in cases {
            XCTAssertEqual(Wording.setUpProblem(problem), expected, "\(problem)")
        }
    }

    func testTheSizeQuestion() {
        XCTAssertEqual(
            Wording.setUpSizeQuestion(displayReports: 27, touchscreenReports: 21.5), "This screen reports 27″. Is that right?")
        XCTAssertEqual(
            Wording.setUpSizeQuestion(displayReports: nil, touchscreenReports: 21.5),
            "The touchscreen reports 21.5″. Is that right?")
        XCTAssertEqual(Wording.setUpSizeQuestion(displayReports: nil, touchscreenReports: nil), "How big is this screen?")
        XCTAssertEqual(Wording.setUpSizeChoice(.displayReport), "what the display reports")
        XCTAssertEqual(Wording.setUpSizeChoice(.touchscreenReport), "what the touchscreen reports")
        XCTAssertEqual(Wording.setUpSizeChoice(.another), "Another size")
        XCTAssertEqual(Wording.setUpSizeHint, "Measured from corner to corner of the picture, in inches.")
        XCTAssertEqual(Wording.setUpContinue, "Continue")
    }

    func testTheCheck() {
        XCTAssertEqual(Wording.setUpCheckInstruction, "Touch anywhere to see where it lands.")
        XCTAssertEqual(Wording.setUpRedo, "Redo")
        XCTAssertEqual(Wording.setUpDone, "Done")
    }

    func testEveryScreenSaysHowToCancelAndWhatTheButtonsAnswer() {
        XCTAssertEqual(Wording.setUpPressEsc, "Press Esc to cancel.")
        XCTAssertEqual(Wording.setUpPressEscToLeave, "Press Esc to leave set-up.", "in set-up mode")
        XCTAssertEqual(Wording.setUpMouseHint, "Use the mouse or the keyboard for these buttons.")
        XCTAssertEqual(Wording.setUpMouseOnlyHint, "Use the mouse for this button.", "Back alone, in set-up mode")
        XCTAssertEqual(Wording.cancel, "Cancel")
    }
}
