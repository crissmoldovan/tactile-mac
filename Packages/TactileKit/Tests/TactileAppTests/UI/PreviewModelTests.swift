import Foundation
import TactileScreens
import XCTest

@testable import TactileApp

/// The preview model: the real desk, its variants, and each command applied the obvious way.
@MainActor
final class PreviewModelTests: XCTestCase {
    private let ilitek = UIFixtures.ilitek
    private let strip = UIFixtures.strip
    private let oldPanel = UIFixtures.oldPanel

    private func touchscreen(_ id: TouchscreenID, _ model: PreviewModel) throws -> TouchscreenSnapshot {
        try XCTUnwrap(UIFixtures.touchscreen(id, in: model.snapshot))
    }

    private func displayID(_ name: String, _ model: PreviewModel) throws -> UInt32 {
        try XCTUnwrap(UIFixtures.displayID(named: name, in: model.snapshot))
    }

    // MARK: - The desk

    func testTheDesk() throws {
        let model = PreviewModel(.desk)
        let snapshot = model.snapshot
        XCTAssertEqual(snapshot.appVersion, "0.5.0")
        XCTAssertTrue(snapshot.isOn)
        XCTAssertEqual(snapshot.warnings, [])
        XCTAssertEqual(snapshot.touchscreens.map(\.name), ["ILITEK-TP", "TouchScreen", "Old panel"])
        XCTAssertEqual(snapshot.displays.map(\.name), [
            "Built-in Retina Display", "Display", "HDMI", "12.3FHD", "LG HDR 4K",
        ])

        let ilitek = try touchscreen(self.ilitek, model)
        XCTAssertEqual(ilitek.mode, .driving)
        XCTAssertEqual(ilitek.status, .pairedWith(name: "HDMI", detail: "23.8″ · 2560 × 1440 · above the main display"))
        XCTAssertEqual(ilitek.pairedDisplayID, try displayID("HDMI", model))
        XCTAssertEqual(ilitek.diagonalInches, 23.8)
        XCTAssertEqual(try XCTUnwrap(ilitek.reportedDiagonalInches), 27, accuracy: 0.05)
        XCTAssertEqual(ilitek.usbID, "222a:0001")
        XCTAssertEqual(ilitek.serial, "V06.00.00.00")
        XCTAssertEqual(ilitek.location, "01141000")
        XCTAssertEqual(ilitek.notes, [.macOSIgnoresIt])
        XCTAssertEqual(ilitek.orientation, .asFitted)

        let strip = try touchscreen(self.strip, model)
        XCTAssertEqual(strip.mode, .driving)
        XCTAssertEqual(strip.status, .pairedWith(name: "12.3FHD", detail: "12.3″ · 1600 × 600 · below the main display"))
        XCTAssertEqual(strip.notes, [.oneFingerOnly])
        XCTAssertEqual(try XCTUnwrap(strip.reportedDiagonalInches), 10.1, accuracy: 0.05)
        XCTAssertEqual(strip.location, "01130000")

        let old = try touchscreen(oldPanel, model)
        XCTAssertFalse(old.isConnected)
        XCTAssertNil(old.mode)
        XCTAssertEqual(old.status, .notConnected)
        XCTAssertEqual(old.deviceName, "ACDC Touch Input Device")
        XCTAssertNil(old.pairedDisplayID)
        XCTAssertNil(old.location)
        XCTAssertEqual(old.displayChoices, [])
    }

    func testTheBuiltInDisplayIsNeverAChoice() {
        for variant in PreviewModel.Variant.allCases {
            let snapshot = UIFixtures.snapshot(variant)
            let builtIn = snapshot.displays.filter(\.isBuiltIn).map(\.id)
            for touchscreen in snapshot.touchscreens {
                XCTAssertTrue(Set(touchscreen.displayChoices.map(\.id)).isDisjoint(with: builtIn), "\(variant)")
            }
        }
    }

    func testEachChoiceSaysWhoElseUsesIt() throws {
        let model = PreviewModel(.desk)
        let choices = try touchscreen(ilitek, model).displayChoices
        XCTAssertEqual(choices.first { $0.name == "12.3FHD" }?.inUseBy, "TouchScreen")
        XCTAssertNil(choices.first { $0.name == "HDMI" }?.inUseBy)
        XCTAssertNil(choices.first { $0.name == "LG HDR 4K" }?.inUseBy)
    }

    func testEverySnapshotSurvivesJSON() throws {
        for variant in PreviewModel.Variant.allCases {
            let snapshot = UIFixtures.snapshot(variant)
            let data = try JSONEncoder().encode(snapshot)
            XCTAssertEqual(try JSONDecoder().decode(AppSnapshot.self, from: data), snapshot, "\(variant)")
        }
    }

    // MARK: - The variants

    func testNothingPaired() throws {
        let model = PreviewModel(.nothingPaired)
        XCTAssertEqual(model.snapshot.touchscreens.map(\.name), ["ILITEK-TP", "TouchScreen"])
        for touchscreen in model.snapshot.touchscreens {
            XCTAssertEqual(touchscreen.status, .notSetUp)
            XCTAssertEqual(touchscreen.mode, .held)
            XCTAssertNil(touchscreen.pairedDisplayID)
            XCTAssertNil(touchscreen.orientation)
            XCTAssertTrue(touchscreen.displayChoices.allSatisfy { $0.inUseBy == nil })
        }
    }

    func testAccessibilityMissing() throws {
        let model = PreviewModel(.accessibilityMissing)
        XCTAssertEqual(model.snapshot.warnings, [.accessibilityMissing])
        XCTAssertEqual(try touchscreen(ilitek, model).status, .accessibilityMissing)
        XCTAssertEqual(try touchscreen(ilitek, model).mode, .released)
        XCTAssertEqual(try touchscreen(strip, model).status, .accessibilityMissing)
        XCTAssertEqual(try touchscreen(oldPanel, model).status, .notConnected)
    }

    func testTactileOff() throws {
        let model = PreviewModel(.tactileOff)
        XCTAssertFalse(model.snapshot.isOn)
        XCTAssertEqual(try touchscreen(ilitek, model).status, .tactileOff)
        XCTAssertEqual(try touchscreen(ilitek, model).mode, .released)
    }

    func testADisplayUnplugged() throws {
        let model = PreviewModel(.displayUnplugged)
        XCTAssertFalse(model.snapshot.displays.contains { $0.name == "HDMI" })
        let ilitek = try touchscreen(self.ilitek, model)
        XCTAssertEqual(ilitek.status, .displayNotConnected(name: "HDMI"))
        XCTAssertEqual(ilitek.mode, .held)
        XCTAssertNil(ilitek.pairedDisplayID)
        XCTAssertNil(ilitek.reportedDiagonalInches)
        XCTAssertEqual(ilitek.orientation, .asFitted)
        XCTAssertFalse(ilitek.displayChoices.contains { $0.name == "HDMI" })
    }

    func testTactileOffWithTheDisplayUnplugged() throws {
        let model = PreviewModel(.tactileOffDisplayUnplugged)
        let ilitek = try touchscreen(self.ilitek, model)
        XCTAssertEqual(ilitek.status, .tactileOff)
        XCTAssertNil(ilitek.pairedDisplayID)
        XCTAssertEqual(ilitek.pairedDisplayName, "HDMI")
        XCTAssertEqual(ilitek.orientation, .asFitted)
    }

    func testThePairedDisplaysNameIsThereWheneverItIsPaired() throws {
        XCTAssertEqual(try touchscreen(ilitek, PreviewModel(.desk)).pairedDisplayName, "HDMI")
        XCTAssertEqual(try touchscreen(strip, PreviewModel(.desk)).pairedDisplayName, "12.3FHD")
        XCTAssertEqual(try touchscreen(oldPanel, PreviewModel(.desk)).pairedDisplayName, "Display",
                       "a remembered touchscreen's display, not connected")
        XCTAssertEqual(try touchscreen(ilitek, PreviewModel(.displayUnplugged)).pairedDisplayName, "HDMI")
        XCTAssertEqual(try touchscreen(ilitek, PreviewModel(.accessibilityMissing)).pairedDisplayName, "HDMI")
        XCTAssertNil(try touchscreen(ilitek, PreviewModel(.nothingPaired)).pairedDisplayName)

        let model = PreviewModel(.desk)
        model.perform(.unpair(ilitek))
        XCTAssertNil(try touchscreen(ilitek, model).pairedDisplayName)
        let hdmi = try XCTUnwrap(model.snapshot.displays.first { $0.name == "HDMI" })
        model.perform(.pair(ilitek, displayID: hdmi.id))
        model.perform(.renameDisplay(uuid: hdmi.uuid, to: "Top"))
        XCTAssertEqual(try touchscreen(ilitek, model).pairedDisplayName, "Top")
    }

    func testAllWarnings() {
        XCTAssertEqual(PreviewModel(.allWarnings).snapshot.warnings, AppWarning.allCases)
    }

    // MARK: - Commands

    func testTurningTactileOffAndOn() throws {
        let model = PreviewModel(.desk)
        model.perform(.setOn(false))
        XCTAssertFalse(model.snapshot.isOn)
        XCTAssertEqual(try touchscreen(ilitek, model).status, .tactileOff)
        XCTAssertEqual(try touchscreen(strip, model).mode, .released)
        model.perform(.setOn(true))
        XCTAssertEqual(model.snapshot, PreviewModel(.desk).snapshot)
    }

    func testTurningATouchscreenOffEitherWay() throws {
        let model = PreviewModel(.desk)
        model.perform(.setTouchscreenOn(ilitek, false))
        var ilitek = try touchscreen(self.ilitek, model)
        XCTAssertFalse(ilitek.isOn)
        XCTAssertEqual(ilitek.status, .off)
        XCTAssertEqual(ilitek.mode, .held)

        model.perform(.setWhenOff(self.ilitek, .leaveToMacOS))
        ilitek = try touchscreen(self.ilitek, model)
        XCTAssertEqual(ilitek.whenOff, .leaveToMacOS)
        XCTAssertEqual(ilitek.mode, .released)
        XCTAssertEqual(try touchscreen(strip, model).mode, .driving)
    }

    func testRenamingATouchscreen() throws {
        let model = PreviewModel(.desk)
        model.perform(.rename(ilitek, to: "  Top screen "))
        XCTAssertEqual(try touchscreen(ilitek, model).name, "Top screen")
        XCTAssertEqual(try touchscreen(ilitek, model).deviceName, "ILITEK-TP")
        XCTAssertEqual(
            try touchscreen(strip, model).displayChoices.first { $0.name == "HDMI" }?.inUseBy, "Top screen")
        model.perform(.rename(ilitek, to: "   "))
        XCTAssertEqual(try touchscreen(ilitek, model).name, "ILITEK-TP")
        model.perform(.rename(ilitek, to: "Top screen"))
        model.perform(.rename(ilitek, to: nil))
        XCTAssertEqual(try touchscreen(ilitek, model).name, "ILITEK-TP")
    }

    func testPairingAFreeDisplay() throws {
        let model = PreviewModel(.desk)
        model.perform(.setOrientation(ilitek, Orientation(quarterTurns: 2, isFlipped: false)))
        let lg = try displayID("LG HDR 4K", model)
        model.perform(.pair(ilitek, displayID: lg))
        let ilitek = try touchscreen(self.ilitek, model)
        XCTAssertEqual(ilitek.pairedDisplayID, lg)
        XCTAssertEqual(ilitek.orientation, .asFitted, "a different display starts as fitted")
        XCTAssertEqual(
            ilitek.status, .pairedWith(name: "LG HDR 4K", detail: "23.8″ · 3008 × 1692 · right of the main display"))
        XCTAssertEqual(model.snapshot.displays.first { $0.id == lg }?.pairedTouchscreen, "ILITEK-TP")
    }

    func testPairingTheSameDisplayKeepsTheOrientation() throws {
        let model = PreviewModel(.desk)
        let turned = Orientation(quarterTurns: 1, isFlipped: true)
        model.perform(.setOrientation(ilitek, turned))
        model.perform(.pair(ilitek, displayID: try displayID("HDMI", model)))
        XCTAssertEqual(try touchscreen(ilitek, model).orientation, turned)
    }

    func testPairingADisplayInUseMovesIt() throws {
        let model = PreviewModel(.desk)
        let hdmi = try displayID("HDMI", model)
        let fhd = try displayID("12.3FHD", model)
        model.perform(.pair(ilitek, displayID: fhd))
        XCTAssertEqual(try touchscreen(ilitek, model).pairedDisplayID, fhd)
        XCTAssertEqual(try touchscreen(strip, model).status, .notSetUp)
        XCTAssertEqual(try touchscreen(strip, model).mode, .held)
        model.perform(.pair(strip, displayID: hdmi))
        XCTAssertEqual(try touchscreen(strip, model).pairedDisplayID, hdmi)
        XCTAssertEqual(try touchscreen(ilitek, model).pairedDisplayID, fhd, "two picks swap two displays")
    }

    func testUnpairing() throws {
        let model = PreviewModel(.desk)
        model.perform(.unpair(ilitek))
        let ilitek = try touchscreen(self.ilitek, model)
        XCTAssertEqual(ilitek.status, .notSetUp)
        XCTAssertEqual(ilitek.mode, .held)
        XCTAssertNil(ilitek.pairedDisplayID)
        XCTAssertNil(ilitek.orientation)
        XCTAssertNil(ilitek.reportedDiagonalInches)
        XCTAssertNil(try touchscreen(strip, model).displayChoices.first { $0.name == "HDMI" }?.inUseBy)
    }

    func testSettingTheOrientation() throws {
        let model = PreviewModel(.desk)
        let turned = Orientation(quarterTurns: 3, isFlipped: true)
        model.perform(.setOrientation(ilitek, turned))
        XCTAssertEqual(try touchscreen(ilitek, model).orientation, turned)
    }

    func testSettingTheDiagonal() throws {
        let model = PreviewModel(.desk)
        model.perform(.setDiagonal(ilitek, inches: 21.5))
        XCTAssertEqual(try touchscreen(ilitek, model).diagonalInches, 21.5)
        XCTAssertEqual(
            try touchscreen(ilitek, model).status,
            .pairedWith(name: "HDMI", detail: "21.5″ · 2560 × 1440 · above the main display"))
        model.perform(.setDiagonal(ilitek, inches: nil))
        XCTAssertNil(try touchscreen(ilitek, model).diagonalInches)
        XCTAssertEqual(
            try touchscreen(ilitek, model).status,
            .pairedWith(name: "HDMI", detail: "27″ · 2560 × 1440 · above the main display"))
        model.perform(.setDiagonal(ilitek, inches: 23.8))
        model.perform(.setDiagonal(ilitek, inches: 250))
        XCTAssertNil(try touchscreen(ilitek, model).diagonalInches, "outside 3…200 clears the override")
    }

    func testForgettingARememberedTouchscreen() throws {
        let model = PreviewModel(.desk)
        model.perform(.forget(oldPanel))
        XCTAssertEqual(model.snapshot.touchscreens.map(\.name), ["ILITEK-TP", "TouchScreen"])
    }

    func testRenamingADisplay() throws {
        let model = PreviewModel(.desk)
        let hdmi = try XCTUnwrap(model.snapshot.displays.first { $0.name == "HDMI" })
        model.perform(.renameDisplay(uuid: hdmi.uuid, to: "Top"))
        XCTAssertEqual(model.snapshot.displays.first { $0.id == hdmi.id }?.name, "Top")
        XCTAssertEqual(
            try touchscreen(ilitek, model).status,
            .pairedWith(name: "Top", detail: "23.8″ · 2560 × 1440 · above the main display"))
        XCTAssertEqual(try touchscreen(strip, model).displayChoices.first { $0.id == hdmi.id }?.name, "Top")
        model.perform(.renameDisplay(uuid: hdmi.uuid, to: " "))
        XCTAssertEqual(model.snapshot.displays.first { $0.id == hdmi.id }?.name, "HDMI")
    }

    func testADisplayWithoutAUUIDKeepsItsName() {
        let model = PreviewModel(.desk)
        let before = model.snapshot
        model.perform(.renameDisplay(uuid: "", to: "Nameless"))
        XCTAssertEqual(model.snapshot, before)
    }

    func testTheNameOfAnUnpluggedDisplayIsItsLastKnownOne() throws {
        let model = PreviewModel(.desk)
        let hdmi = try XCTUnwrap(model.snapshot.displays.first { $0.name == "HDMI" })
        model.perform(.renameDisplay(uuid: hdmi.uuid, to: "Top"))
        var desk = PreviewDesk(.displayUnplugged)
        desk.apply(.renameDisplay(uuid: hdmi.uuid, to: "Top"))
        XCTAssertEqual(
            desk.snapshot().touchscreens.first { $0.id == ilitek }?.status, .displayNotConnected(name: "Top"))
    }

    func testDebugLogging() {
        let model = PreviewModel(.desk)
        model.perform(.setDebugLogging(true))
        XCTAssertTrue(model.snapshot.debugLogging)
        model.perform(.setDebugLogging(false))
        XCTAssertFalse(model.snapshot.debugLogging)
    }

    func testAskingForAccessibilityGrantsItInThePreview() throws {
        let model = PreviewModel(.accessibilityMissing)
        model.perform(.askForAccessibility)
        XCTAssertEqual(model.snapshot.warnings, [])
        XCTAssertEqual(try touchscreen(ilitek, model).mode, .driving)
    }

    func testCommandsThatChangeNothing() throws {
        let model = PreviewModel(.desk)
        let before = model.snapshot
        let builtIn = try XCTUnwrap(model.snapshot.displays.first(where: \.isBuiltIn)).id
        let unknown = TouchscreenID(rawValue: "ffff:ffff:nobody")
        let commands: [AppCommand] = [
            .pair(ilitek, displayID: builtIn),
            .pair(ilitek, displayID: 999),
            .pair(oldPanel, displayID: try displayID("LG HDR 4K", model)),
            .forget(ilitek),
            .setTouchscreenOn(unknown, false),
            .rename(unknown, to: "x"),
            .setDiagonal(unknown, inches: 20),
        ]
        for command in commands {
            model.perform(command)
            XCTAssertEqual(model.snapshot, before, "\(command)")
        }
        model.perform(.unpair(ilitek))
        let unpaired = model.snapshot
        model.perform(.setOrientation(ilitek, Orientation(quarterTurns: 1, isFlipped: false)))
        XCTAssertEqual(model.snapshot, unpaired, "an unpaired touchscreen has no orientation to set")
    }

    func testThePreviewIsObservable() {
        let model = PreviewModel(.desk)
        let changed = expectation(description: "snapshot changed")
        withObservationTracking {
            _ = model.snapshot
        } onChange: {
            changed.fulfill()
        }
        model.perform(.setOn(false))
        wait(for: [changed], timeout: 1)
    }

    /// `steadySnapshot` follows `snapshot` by construction, whoever writes it: a write that changes
    /// only the tester's feed, whole or in place, leaves it alone and is never told; a write that
    /// changes anything else sets it.
    func testTheSteadySnapshotFollowsEveryWriteOfTheSnapshot() throws {
        let model = PreviewModel(.desk)
        model.perform(.openGestureTester(ilitek))
        let steady = model.steadySnapshot
        XCTAssertEqual(steady, model.snapshot.withoutTesterFeed)
        XCTAssertNotEqual(model.snapshot.gestureTester?.recent, [], "the preview's tester has a feed")
        let told = Told()
        withObservationTracking { _ = model.steadySnapshot } onChange: { told.value = true }

        var feedOnly = model.snapshot
        feedOnly.gestureTester?.recent = []
        feedOnly.gestureTester?.seen = []
        model.snapshot = feedOnly
        model.snapshot.gestureTester?.fingersDown = 4
        XCTAssertEqual(model.snapshot.gestureTester?.fingersDown, 4)
        XCTAssertFalse(told.value, "a write of the feed alone never sets it")
        XCTAssertEqual(model.steadySnapshot, steady)

        var changed = model.snapshot
        changed.isOn.toggle()
        model.snapshot = changed
        XCTAssertTrue(told.value, "a write of anything else sets it")
        XCTAssertEqual(model.steadySnapshot, changed.withoutTesterFeed)
    }
}
