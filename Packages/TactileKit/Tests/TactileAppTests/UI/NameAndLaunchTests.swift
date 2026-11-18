import Foundation
import TactileScreens
import XCTest

@testable import TactileApp

/// What a rename sends, and the launch check that opens Settings once.
@MainActor
final class NameAndLaunchTests: XCTestCase {
    private let id = UIFixtures.ilitek

    // MARK: - Renaming a touchscreen

    func testANewName() {
        XCTAssertEqual(NameEntry.touchscreen("  Top screen ", current: "ILITEK-TP", deviceName: "ILITEK-TP", id: id),
                       .rename(id, to: "Top screen"))
    }

    func testAnUnchangedNameSendsNothing() {
        XCTAssertNil(NameEntry.touchscreen("ILITEK-TP", current: "ILITEK-TP", deviceName: "ILITEK-TP", id: id))
        XCTAssertNil(NameEntry.touchscreen(" Top ", current: "Top", deviceName: "ILITEK-TP", id: id))
    }

    func testABlankNameGoesBackToTheDevicesOwn() {
        XCTAssertEqual(NameEntry.touchscreen("   ", current: "Top", deviceName: "ILITEK-TP", id: id), .rename(id, to: nil))
        XCTAssertNil(NameEntry.touchscreen("", current: "ILITEK-TP", deviceName: "ILITEK-TP", id: id),
                     "it already has the device's own name")
    }

    func testTheDevicesOwnNameClearsTheCustomOne() {
        XCTAssertEqual(NameEntry.touchscreen("ILITEK-TP", current: "Top", deviceName: "ILITEK-TP", id: id),
                       .rename(id, to: nil))
    }

    // MARK: - Renaming a display

    func testRenamingADisplay() {
        XCTAssertEqual(NameEntry.display(" Top ", current: "HDMI", uuid: "U"), .renameDisplay(uuid: "U", to: "Top"))
        XCTAssertEqual(NameEntry.display("  ", current: "Top", uuid: "U"), .renameDisplay(uuid: "U", to: nil))
        XCTAssertNil(NameEntry.display("HDMI", current: "HDMI", uuid: "U"), "unchanged")
        XCTAssertNil(NameEntry.display("Top", current: "HDMI", uuid: ""), "a display without a UUID can't be named")
    }

    // MARK: - The launch check

    func testTheLaunchCheckOpensSettingsWhenNeeded() async {
        let check = LaunchCheck()
        var opened = 0
        let decision = await check.run(
            wait: {}, snapshot: { UIFixtures.snapshot(.accessibilityMissing) }, open: { opened += 1 })
        XCTAssertEqual(decision, true)
        XCTAssertEqual(opened, 1)
    }

    /// A touchscreen that isn't set up gets the first-run window, not Settings.
    func testTheLaunchCheckLeavesATouchscreenNotSetUpToTheFirstRunWindow() async {
        let check = LaunchCheck()
        var opened = 0
        let decision = await check.run(
            wait: {}, snapshot: { UIFixtures.snapshot(.nothingPaired) }, open: { opened += 1 })
        XCTAssertEqual(decision, false)
        XCTAssertEqual(opened, 0)
    }

    func testTheLaunchCheckLeavesTheDeskAlone() async {
        let check = LaunchCheck()
        var opened = 0
        let decision = await check.run(wait: {}, snapshot: { UIFixtures.desk }, open: { opened += 1 })
        XCTAssertEqual(decision, false)
        XCTAssertEqual(opened, 0)
    }

    func testTheLaunchCheckRunsOnce() async {
        let check = LaunchCheck()
        var opened = 0
        _ = await check.run(wait: {}, snapshot: { UIFixtures.snapshot(.accessibilityMissing) }, open: { opened += 1 })
        let again = await check.run(wait: {}, snapshot: { UIFixtures.snapshot(.accessibilityMissing) }, open: { opened += 1 })
        XCTAssertNil(again)
        XCTAssertEqual(opened, 1)
    }

    /// A cancelled wait is not a check: it neither decides early nor spends the one check.
    func testACancelledWaitIsNotACheck() async {
        let check = LaunchCheck()
        var opened = 0
        var looked = false
        let cancelled = await check.run(
            wait: { throw CancellationError() },
            snapshot: { looked = true; return UIFixtures.snapshot(.accessibilityMissing) },
            open: { opened += 1 })
        XCTAssertNil(cancelled)
        XCTAssertFalse(looked, "decided nothing before the wait was over")
        XCTAssertEqual(opened, 0)
        let later = await check.run(wait: {}, snapshot: { UIFixtures.snapshot(.accessibilityMissing) }, open: { opened += 1 })
        XCTAssertEqual(later, true)
        XCTAssertEqual(opened, 1)
    }

    // MARK: - A Settings window nobody asked for

    func testAWindowThatOpensByItselfAtLaunchIsClosed() {
        XCTAssertTrue(SettingsWindowGuard.shouldClose(wasRequested: false, secondsSinceLaunch: 0.4))
        XCTAssertFalse(SettingsWindowGuard.shouldClose(wasRequested: true, secondsSinceLaunch: 0.4))
        XCTAssertFalse(SettingsWindowGuard.shouldClose(wasRequested: false, secondsSinceLaunch: 30),
                       "later, a window can only come from the person")
        XCTAssertFalse(SettingsWindowGuard.shouldClose(wasRequested: false, secondsSinceLaunch: nil),
                       "launch time unknown: never close a window on a guess")
    }
}
