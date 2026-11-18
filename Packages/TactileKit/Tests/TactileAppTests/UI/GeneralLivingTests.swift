import AppKit
import Foundation
import TactileScreens
import XCTest

@testable import TactileApp

/// General in 0.4.0: Launch at login in each state, Swipes follow the fingers, and the preview
/// model's own state for both.
@MainActor
final class GeneralLivingTests: XCTestCase {


    // MARK: - Launch at login: words

    func testLaunchAtLoginWords() {
        XCTAssertEqual(Wording.launchAtLogin, "Launch at login")
        XCTAssertNil(Wording.launchAtLoginNote(.off))
        XCTAssertNil(Wording.launchAtLoginNote(.on))
        XCTAssertEqual(Wording.launchAtLoginNote(.needsApproval), "Allow Tactile in Login Items.")
        XCTAssertEqual(Wording.launchAtLoginNote(.notInstalled), "Install Tactile in the Applications folder first.")
        XCTAssertEqual(Wording.launchAtLoginNote(.unavailable), "macOS wouldn’t register Tactile to open at login.")
        XCTAssertEqual(Wording.openLoginItemsSettings, "Open Login Items Settings…")
    }

    // MARK: - Launch at login: the row

    func testTheLaunchAtLoginRowInEachState() {
        XCTAssertEqual(LaunchAtLoginRow(.off),
                       LaunchAtLoginRow(isOn: false, isEnabled: true, note: nil, offersLoginItemsSettings: false))
        XCTAssertEqual(LaunchAtLoginRow(.on),
                       LaunchAtLoginRow(isOn: true, isEnabled: true, note: nil, offersLoginItemsSettings: false))
        XCTAssertEqual(LaunchAtLoginRow(.needsApproval),
                       LaunchAtLoginRow(isOn: true, isEnabled: true, note: "Allow Tactile in Login Items.",
                                        offersLoginItemsSettings: true),
                       "registered and waiting: on, and the way to approve it")
        XCTAssertEqual(LaunchAtLoginRow(.notInstalled),
                       LaunchAtLoginRow(isOn: false, isEnabled: false,
                                        note: "Install Tactile in the Applications folder first.",
                                        offersLoginItemsSettings: false),
                       "never registered from a build folder")
        XCTAssertEqual(LaunchAtLoginRow(.unavailable),
                       LaunchAtLoginRow(isOn: false, isEnabled: true,
                                        note: "macOS wouldn’t register Tactile to open at login.",
                                        offersLoginItemsSettings: false),
                       "it can be tried again")
    }

    /// Carried item D: a Tactile outside the Applications folder whose login item is registered
    /// shows the switch on and usable, so it can be switched off there; afterwards it reads not
    /// installed, and the switch is disabled.
    func testALoginItemRegisteredFromOutsideApplicationsCanBeSwitchedOff() {
        let item = FakeLoginItem(status: .enabled)
        let before = LaunchAtLoginRow(LaunchAtLoginRules.state(isInstalled: false, status: item.status, refused: false))
        XCTAssertEqual(before, LaunchAtLoginRow(isOn: true, isEnabled: true, note: nil, offersLoginItemsSettings: false))
        XCTAssertEqual(before.toggleCommand, .setLaunchAtLogin(false))

        _ = LaunchAtLoginRules.request(false, isInstalled: false, registrar: item)
        let after = LaunchAtLoginRow(LaunchAtLoginRules.state(isInstalled: false, status: item.status, refused: false))
        XCTAssertEqual(after.isEnabled, false)
        XCTAssertEqual(after.isOn, false)
        XCTAssertEqual(after.note, "Install Tactile in the Applications folder first.")
        XCTAssertNil(after.toggleCommand, "and it can't be switched on again from there")
    }

    func testWhatTheLaunchAtLoginControlsSend() {
        XCTAssertEqual(LaunchAtLoginRow.command(true), .setLaunchAtLogin(true))
        XCTAssertEqual(LaunchAtLoginRow.command(false), .setLaunchAtLogin(false))
        XCTAssertEqual(LaunchAtLoginRow.openSettingsCommand, .openLoginItemsSettings)
    }

    // MARK: - Swipes follow the fingers

    func testFollowedSwipesWords() {
        XCTAssertEqual(Wording.experimental, "Experimental")
        XCTAssertEqual(Wording.swipesFollowFingers, "Swipes follow the fingers")
        XCTAssertEqual(
            Wording.swipesFollowFingersExplanation,
            "Three- and four-finger swipes left and right slide between Desktops with your fingers. If a Desktop gets stuck half way, switch this off and run `killall Dock` in Terminal.")
        XCTAssertEqual(
            Wording.swipesFollowFingersUnavailable,
            "Needs macOS 26 or earlier, and a trackpad’s “Swipe between full-screen applications” switched on in System Settings › Trackpad › More Gestures.")
    }

    func testTheFollowedSwipesRow() {
        var snapshot = UIFixtures.desk
        snapshot.canFollowSwipes = true
        snapshot.swipesFollowFingers = false
        XCTAssertEqual(FollowedSwipesRow(snapshot), FollowedSwipesRow(isOn: false, isEnabled: true, reason: nil))
        snapshot.swipesFollowFingers = true
        XCTAssertEqual(FollowedSwipesRow(snapshot), FollowedSwipesRow(isOn: true, isEnabled: true, reason: nil))
        snapshot.canFollowSwipes = false
        XCTAssertEqual(
            FollowedSwipesRow(snapshot),
            FollowedSwipesRow(isOn: false, isEnabled: false, reason: Wording.swipesFollowFingersUnavailable),
            "stored on, and can't follow here: shown off and disabled, with why; the shortcuts are used")
        XCTAssertEqual(FollowedSwipesRow.command(true), .setSwipesFollowFingers(true))
    }

    // MARK: - What each switch sends

    /// What a click on the switch sends, from the state shown: the other position; nothing while
    /// it is disabled.
    func testWhatTheLaunchAtLoginSwitchSendsInEachState() {
        XCTAssertEqual(LaunchAtLoginRow(.off).toggleCommand, .setLaunchAtLogin(true))
        XCTAssertEqual(LaunchAtLoginRow(.on).toggleCommand, .setLaunchAtLogin(false))
        XCTAssertEqual(LaunchAtLoginRow(.needsApproval).toggleCommand, .setLaunchAtLogin(false),
                       "shown on: a click unregisters it")
        XCTAssertEqual(LaunchAtLoginRow(.unavailable).toggleCommand, .setLaunchAtLogin(true), "tried again")
        XCTAssertNil(LaunchAtLoginRow(.notInstalled).toggleCommand, "never from a build folder")
    }

    func testWhatTheFollowedSwipesSwitchSends() {
        var snapshot = UIFixtures.desk
        snapshot.canFollowSwipes = true
        snapshot.swipesFollowFingers = false
        XCTAssertEqual(FollowedSwipesRow(snapshot).toggleCommand, .setSwipesFollowFingers(true))
        snapshot.swipesFollowFingers = true
        XCTAssertEqual(FollowedSwipesRow(snapshot).toggleCommand, .setSwipesFollowFingers(false))
        snapshot.canFollowSwipes = false
        XCTAssertNil(FollowedSwipesRow(snapshot).toggleCommand)
    }

    // MARK: - The preview model

    func testThePreviewKeepsItsOwnState() {
        let model = PreviewModel(.desk)
        XCTAssertFalse(model.snapshot.swipesFollowFingers, "off unless switched on")
        XCTAssertTrue(model.snapshot.canFollowSwipes)
        XCTAssertEqual(model.snapshot.launchAtLogin, .off)

        model.perform(.setSwipesFollowFingers(true))
        XCTAssertTrue(model.snapshot.swipesFollowFingers)
        model.perform(.setSwipesFollowFingers(false))
        XCTAssertFalse(model.snapshot.swipesFollowFingers)

        model.perform(.setLaunchAtLogin(true))
        XCTAssertEqual(model.snapshot.launchAtLogin, .on)
        model.perform(.setLaunchAtLogin(false))
        XCTAssertEqual(model.snapshot.launchAtLogin, .off)

        let before = model.snapshot
        model.perform(.openLoginItemsSettings)
        XCTAssertEqual(model.snapshot, before)
        XCTAssertEqual(model.loginItemsSettingsOpened, 1)
    }

    func testThePreviewNeverRegistersFromOutsideApplications() {
        var desk = PreviewDesk(.desk)
        desk.launchAtLogin = .notInstalled
        let model = PreviewModel(desk: desk)
        model.perform(.setLaunchAtLogin(true))
        XCTAssertEqual(model.snapshot.launchAtLogin, .notInstalled)
    }

    func testThePreviewMacThatCannotFollowSwipes() {
        var desk = PreviewDesk(.desk)
        desk.canFollowSwipes = false
        let model = PreviewModel(desk: desk)
        model.perform(.setSwipesFollowFingers(true))
        XCTAssertTrue(model.snapshot.swipesFollowFingers, "stored as asked")
        XCTAssertFalse(FollowedSwipesRow(model.snapshot).isOn, "shown off: it can't follow here")
    }
}
