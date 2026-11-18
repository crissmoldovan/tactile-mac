import XCTest

@testable import TactileApp

/// The words of set-up mode: the menu item and why it can't be used, a display's card at each
/// stage, the session card, its lines and its notices.
final class WordingSetUpModeTests: XCTestCase {

    func testWhySetUpTouchscreensCannotBeUsed() {
        let cases: [(SetUpModeAvailability.Reason, String)] = [
            (.running, "A set-up is running."),
            (.tactileOff, "Turn Tactile on to set up touchscreens."),
            (.accessibilityMissing, "Tactile needs Accessibility access to set up touchscreens."),
            (.noTouchscreen, "Connect a touchscreen first."),
            (.noneCanBeSetUp, "None of the connected touchscreens can be set up. Settings says why."),
            (.noExternalDisplay, "Connect an external display first."),
            (.notNow, "Set-up can’t begin just now. Try again in a moment."),
        ]
        for (reason, expected) in cases {
            XCTAssertEqual(Wording.setUpModeUnavailable(reason), expected, "\(reason)")
            XCTAssertEqual(SetUpModeAvailability.unavailable(reason).reason, reason)
        }
        XCTAssertNil(SetUpModeAvailability.available.reason)
    }

    func testADisplaysCard() {
        XCTAssertEqual(Wording.setUpModeOffer, "Set up a touchscreen on this screen")
        XCTAssertEqual(Wording.setUpModeSetUpHere(name: "ILITEK-TP"), "✓ ILITEK-TP is set up here")
        XCTAssertEqual(Wording.setUpModeJustSetUp(name: "TouchScreen", displayName: "12.3FHD"),
                       "✓ TouchScreen is set up on 12.3FHD")
        XCTAssertEqual(Wording.setUpModeJustDone, "Just set up")
        XCTAssertEqual(Wording.setUpModeTouchHere, "Now touch this screen")
        XCTAssertEqual(Wording.setUpModeTouchHint, "Touch it anywhere with one finger, then lift it.")
        XCTAssertEqual(Wording.setUpModeWaiting(displayName: "HDMI"), "Waiting for a touch on HDMI")
        XCTAssertEqual(Wording.setUpModeTouchedFirst(name: "ILITEK-TP"),
                       "You touched ILITEK-TP. Click the screen you touched.")
    }

    func testTheButtons() {
        XCTAssertEqual(Wording.setUpModeThisOne, "This One")
        XCTAssertEqual(Wording.setUpModeSetUpAgain, "Set Up Again Here")
        XCTAssertEqual(Wording.setUpModeBack, "Back")
        XCTAssertEqual(Wording.setUpModeFinish, "Finish")
        XCTAssertEqual(SetUpModeButton.thisOne(display: 2).title, "This One")
        XCTAssertEqual(SetUpModeButton.setUpAgainHere(display: 2).title, "Set Up Again Here")
        XCTAssertEqual(SetUpModeButton.test(UIFixtures.ilitek).title, "Test")
        XCTAssertEqual(SetUpModeButton.back.title, "Back")
        XCTAssertEqual(SetUpModeButton.finish.title, "Finish")
    }

    func testTheSessionCard() {
        XCTAssertEqual(Wording.setUpModeTitle, "Set Up Touchscreens")
        XCTAssertEqual(
            Wording.setUpModeIntro,
            "On the screen that has a touchscreen, click This One, then touch that screen. Or touch it first, then click its screen.")
        XCTAssertEqual(Wording.setUpModeEscLeaves, "Esc leaves at any time.")
        XCTAssertEqual(Wording.setUpModeYouTouched(name: "TouchScreen"), "You touched TouchScreen.")
        XCTAssertEqual(Wording.setUpModeLine(.setUp(displayName: "HDMI")), "Set up on HDMI")
        XCTAssertEqual(Wording.setUpModeLine(.notSetUp), "Not set up")
        XCTAssertEqual(Wording.setUpModeLine(.cannotBeSetUp), "Can’t be set up")
        XCTAssertEqual(Wording.setUpModeElsewhere, "Setting up touchscreens")
    }

    func testEveryNotice() {
        let cases: [(SetUpModeNotice, String)] = [
            (.cannotBeSetUp(touchscreen: UIFixtures.strip, name: "TouchScreen"),
             "TouchScreen can’t be set up, so its touch was ignored."),
            (.displayGone(name: "LG HDR 4K"), "LG HDR 4K was disconnected. Choose another screen."),
            (.touchscreenGone(name: "ILITEK-TP"), "ILITEK-TP was disconnected. Nothing about it was changed."),
        ]
        for (notice, expected) in cases {
            XCTAssertEqual(Wording.setUpModeNotice(notice), expected, "\(notice)")
        }
    }

    func testAListOfNames() {
        XCTAssertEqual(Wording.list([]), "")
        XCTAssertEqual(Wording.list(["A"]), "A")
        XCTAssertEqual(Wording.list(["A", "B"]), "A and B")
        XCTAssertEqual(Wording.list(["A", "B", "C"]), "A, B and C")
    }
}
