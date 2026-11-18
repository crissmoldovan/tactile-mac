import TactileScreens
import XCTest

@testable import TactileApp

/// Every case of every enum the interface puts into words.
final class WordingTests: XCTestCase {

    // MARK: - The status line

    func testTheStatusLineForEveryStatus() {
        let cases: [(TouchscreenStatus, WhenOff, String)] = [
            (.notConnected, .ignoreTouches, "Not connected"),
            (.tactileOff, .ignoreTouches, "Left to macOS while Tactile is off."),
            (.accessibilityMissing, .ignoreTouches, "Left to macOS until Tactile has Accessibility access."),
            (.off, .ignoreTouches, "Off. Its touches are ignored."),
            (.off, .leaveToMacOS, "Off. Its touches are left to macOS."),
            (.notSetUp, .ignoreTouches, "Not set up. It does nothing until it is paired with a display."),
            (.displayNotConnected(name: "HDMI"), .ignoreTouches,
             "Display not connected: HDMI. It resumes when the display returns."),
            (.pairedWith(name: "HDMI", detail: "23.8″ · 2560 × 1440 · above the main display"), .leaveToMacOS,
             "Paired with HDMI — 23.8″ · 2560 × 1440 · above the main display"),
            (.pairedWith(name: "HDMI", detail: ""), .ignoreTouches, "Paired with HDMI"),
        ]
        for (status, whenOff, expected) in cases {
            XCTAssertEqual(Wording.statusLine(status, whenOff: whenOff), expected, "\(status)")
        }
    }

    func testTheStatusLineOfASnapshotUsesItsWhenOff() {
        var strip = UIFixtures.desk.touchscreens[1]
        strip.status = .off
        strip.whenOff = .leaveToMacOS
        XCTAssertEqual(Wording.statusLine(for: strip), "Off. Its touches are left to macOS.")
    }

    // MARK: - Notes

    func testEveryNote() {
        XCTAssertEqual(Wording.note(.oneFingerOnly), "One finger only: this touchscreen stayed in mouse mode")
        XCTAssertEqual(Wording.note(.macOSMayAlsoRespond), "macOS may also respond to touches")
        XCTAssertEqual(Wording.note(.touchesCannotBeRead), "Touches can’t be read")
        XCTAssertEqual(
            Wording.note(.rememberedByPort), "Remembered by its USB port: another touchscreen has the same ID")
    }

    // MARK: - The menu

    func testTheMenuStateForEveryStatus() {
        let cases: [(TouchscreenStatus, String)] = [
            (.notConnected, "Not connected"),
            (.tactileOff, "Left to macOS"),
            (.accessibilityMissing, "Left to macOS"),
            (.off, "Off"),
            (.notSetUp, "Not set up"),
            (.displayNotConnected(name: "HDMI"), "Display not connected: HDMI"),
            (.pairedWith(name: "12.3FHD", detail: "12.3″ · 1600 × 600 · below the main display"),
             "Paired with 12.3FHD"),
        ]
        for (status, expected) in cases {
            XCTAssertEqual(Wording.menuState(status, notes: []), expected, "\(status)")
        }
    }

    func testTheMenuStateCarriesTheNotesThatLimitATouchscreen() {
        let paired = TouchscreenStatus.pairedWith(name: "12.3FHD", detail: "")
        XCTAssertEqual(Wording.menuState(paired, notes: [.oneFingerOnly]), "Paired with 12.3FHD · one finger only")
        XCTAssertEqual(
            Wording.menuState(paired, notes: [.macOSMayAlsoRespond]), "Paired with 12.3FHD · macOS may also respond")
        XCTAssertEqual(Wording.menuState(.notSetUp, notes: [.touchesCannotBeRead]), "Not set up · touches can’t be read")
        XCTAssertEqual(Wording.menuState(paired, notes: [.rememberedByPort]), "Paired with 12.3FHD")
        XCTAssertEqual(
            Wording.menuState(paired, notes: [.oneFingerOnly, .macOSMayAlsoRespond]),
            "Paired with 12.3FHD · one finger only · macOS may also respond")
        XCTAssertEqual(
            Wording.menuState(.displayNotConnected(name: "12.3FHD"), notes: [.oneFingerOnly]),
            "Display not connected: 12.3FHD · one finger only")
    }

    func testTheMenuStateLeavesOutNotesWhileTactileIsNotHandlingTheTouchscreen() {
        for status in [TouchscreenStatus.tactileOff, .accessibilityMissing, .off, .notConnected] {
            XCTAssertFalse(Wording.menuState(status, notes: [.oneFingerOnly]).contains("one finger"), "\(status)")
        }
    }

    func testTheMenuLineForEachTouchscreenOfTheDesk() {
        XCTAssertEqual(UIFixtures.desk.touchscreens.map(Wording.menuState(for:)), [
            "Paired with HDMI", "Paired with 12.3FHD · one finger only", "Not connected",
        ])
    }

    // MARK: - Warnings

    func testEveryWarning() {
        XCTAssertEqual(Wording.warningTitle(.accessibilityMissing), "Accessibility access missing")
        XCTAssertEqual(
            Wording.warningDetail(.accessibilityMissing),
            "Tactile can’t drive touchscreens without it, so it leaves them all to macOS. If Tactile is already listed and switched on in Accessibility settings, remove it with − and add it again with +.")
        XCTAssertEqual(
            Wording.warningAction(.accessibilityMissing),
            WarningAction(title: "Open Accessibility Settings…", kind: .command(.askForAccessibility)))

        XCTAssertEqual(Wording.warningTitle(.touchUpRunning), "Touch Up is running")
        XCTAssertEqual(Wording.warningDetail(.touchUpRunning), "Quit it, or both apps will act on the same touches.")
        XCTAssertEqual(Wording.warningAction(.touchUpRunning)?.title, "Quit Touch Up")

        XCTAssertEqual(Wording.warningTitle(.missionControlShortcutsOff), "The Mission Control shortcuts are off")
        XCTAssertEqual(
            Wording.warningDetail(.missionControlShortcutsOff),
            "Swipes need them. Turn them on in System Settings › Keyboard › Keyboard Shortcuts › Mission Control.")
        XCTAssertEqual(Wording.warningAction(.missionControlShortcutsOff)?.title, "Open Keyboard Settings…")

        XCTAssertEqual(Wording.warningTitle(.settingsSetAside), "The settings file couldn’t be read")
        XCTAssertEqual(
            Wording.warningDetail(.settingsSetAside),
            "It was set aside as settings.json.broken, and Tactile started from the defaults.")
        XCTAssertNil(Wording.warningAction(.settingsSetAside))
    }

    func testEveryWarningHasWords() {
        for warning in AppWarning.allCases {
            XCTAssertFalse(Wording.warningTitle(warning).isEmpty, "\(warning)")
            XCTAssertFalse(Wording.warningDetail(warning).isEmpty, "\(warning)")
        }
    }

    // MARK: - Displays

    func testADisplayLabel() {
        XCTAssertEqual(
            Wording.displayLabel(name: "HDMI", detail: "23.8″ · 2560 × 1440 · above the main display"),
            "HDMI — 23.8″ · 2560 × 1440 · above the main display")
        XCTAssertEqual(Wording.displayLabel(name: "HDMI", detail: ""), "HDMI")
    }

    func testADisplayChoiceSaysWhoUsesIt() {
        let free = DisplayChoice(id: 4, name: "LG HDR 4K", detail: "27″ · 3008 × 1692 · right of the main display",
                                 inUseBy: nil)
        let taken = DisplayChoice(id: 5, name: "12.3FHD", detail: "12.3″ · 1600 × 600 · below the main display",
                                  inUseBy: "TouchScreen")
        XCTAssertEqual(Wording.displayChoice(free), "LG HDR 4K — 27″ · 3008 × 1692 · right of the main display")
        XCTAssertEqual(
            Wording.displayChoice(taken), "12.3FHD — 12.3″ · 1600 × 600 · below the main display (in use by TouchScreen)")
        XCTAssertEqual(Wording.unpaired, "Unpaired")
        XCTAssertEqual(Wording.missingDisplay(name: "HDMI"), "HDMI (not connected)")
    }

    func testTheDeskLabelsAreTheOnesTheDesignShows() {
        let ilitek = UIFixtures.desk.touchscreens[0]
        XCTAssertEqual(
            Wording.statusLine(for: ilitek), "Paired with HDMI — 23.8″ · 2560 × 1440 · above the main display")
        let labels = ilitek.displayChoices.map(Wording.displayChoice)
        XCTAssertEqual(labels, [
            "Display — 18″ · 2048 × 1280 · left of the main display",
            "HDMI — 23.8″ · 2560 × 1440 · above the main display",
            "12.3FHD — 12.3″ · 1600 × 600 · below the main display (in use by TouchScreen)",
            "LG HDR 4K — 27″ · 3008 × 1692 · right of the main display",
        ])
    }

    // MARK: - The controls of a pane

    func testWhenOffChoices() {
        XCTAssertEqual(WhenOff.allCases.map(Wording.whenOff), ["Ignore touches", "Leave it to macOS"])
    }

    func testOrientationChoices() {
        XCTAssertEqual((0..<4).map(Wording.quarterTurns), ["0°", "90°", "180°", "270°"])
        XCTAssertEqual(Wording.flip, "Flip")
    }

    func testInches() {
        XCTAssertEqual(Wording.inches(23.8), "23.8″")
        XCTAssertEqual(Wording.inches(27), "27″")
        XCTAssertEqual(Wording.inches(10.05), "10.1″")
        XCTAssertEqual(Wording.inches(26.97), "27″")
    }

    func testWhatTheDisplayReports() {
        XCTAssertEqual(Wording.reportedDiagonal(displayName: "HDMI", inches: 27), "HDMI reports 27″")
        XCTAssertEqual(Wording.reportedDiagonal(displayName: "12.3FHD", inches: 10.1), "12.3FHD reports 10.1″")
        XCTAssertEqual(Wording.reportedDiagonal(displayName: nil, inches: 27), "The display reports 27″")
        XCTAssertNil(Wording.reportedDiagonal(displayName: "HDMI", inches: nil))
    }

    func testARememberedTouchscreensDisplay() {
        XCTAssertEqual(Wording.rememberedPairing(displayName: "Display"), "Display")
        XCTAssertEqual(Wording.rememberedPairing(displayName: nil), "Unpaired")
    }

    func testTheNamePromptOfATouchscreenWithoutANameOfItsOwn() {
        XCTAssertEqual(Wording.namePrompt(deviceName: "ILITEK-TP"), "ILITEK-TP")
        XCTAssertEqual(Wording.namePrompt(deviceName: ""), "Name")
        XCTAssertEqual(Wording.namePrompt(deviceName: "  "), "Name")
    }

    func testTheVersion() {
        XCTAssertEqual(Wording.version("0.2.0"), "Version 0.2.0")
        XCTAssertEqual(Wording.credit, "Inspired by Touch Up by Sebastian Hueber")
    }

    func testTheMenuTitles() {
        XCTAssertEqual(Wording.menuTactileOn, "Tactile On")
        XCTAssertEqual(Wording.menuSettings, "Settings…")
        XCTAssertEqual(Wording.menuQuit, "Quit Tactile")
        XCTAssertEqual(Wording.touchscreens, "Touchscreens")
        XCTAssertEqual(Wording.forgetButton, "Forget This Touchscreen…")
    }

    func testForgettingAsks() {
        XCTAssertEqual(Wording.forgetQuestion(name: "Old panel"), "Forget “Old panel”?")
        XCTAssertEqual(Wording.renameDisplayTitle(name: "HDMI"), "Rename “HDMI”")
    }
}
