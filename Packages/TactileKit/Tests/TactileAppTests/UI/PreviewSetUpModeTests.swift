import Foundation
import TactileScreens
import XCTest

@testable import TactileApp

/// The preview model's set-up mode: every stage, driven by the commands the real model takes and by
/// touches and cables by hand, so the screens can be drawn and tested without the model.
@MainActor
final class PreviewSetUpModeTests: XCTestCase {
    private let ilitek = UIFixtures.ilitek
    private let strip = UIFixtures.strip
    private let oldPanel = UIFixtures.oldPanel
    private var now: TimeInterval = 2000

    private func model(_ variant: PreviewModel.Variant = .desk) -> PreviewModel {
        PreviewModel(variant, clock: { [unowned self] in self.now })
    }

    private func id(_ name: String, _ model: PreviewModel) throws -> UInt32 {
        try XCTUnwrap(UIFixtures.displayID(named: name, in: model.snapshot))
    }

    private func touchscreen(_ id: TouchscreenID, _ model: PreviewModel) throws -> TouchscreenSnapshot {
        try XCTUnwrap(UIFixtures.touchscreen(id, in: model.snapshot))
    }

    private func stage(_ model: PreviewModel) throws -> SetUpModeSnapshot.Stage {
        try XCTUnwrap(model.snapshot.setUpMode).stage
    }

    /// Corners, size and check of the flow running, then Done.
    private func finishFlow(_ model: PreviewModel, inches: Double? = nil) {
        for _ in 0..<4 { model.touchSetUp() }
        model.perform(.setUpConfirmSize(inches: inches))
        model.perform(.setUpDone)
    }

    // MARK: - Beginning

    func testTheModeBegins() throws {
        let model = model()
        model.perform(.beginSetUpMode)
        let mode = try XCTUnwrap(model.snapshot.setUpMode)
        XCTAssertEqual(mode.stage, .choosing)
        XCTAssertEqual(mode.displays.map(\.name), ["Display", "HDMI", "12.3FHD", "LG HDR 4K"],
                       "every display but the built-in one, in the snapshot's order")
        XCTAssertEqual(mode.displays.map(\.touchscreen), [nil, ilitek, strip, nil])
        XCTAssertEqual(mode.displays.map(\.touchscreenName), [nil, "ILITEK-TP", "TouchScreen", nil])
        XCTAssertEqual(mode.touchscreens.map(\.id), [ilitek, strip], "every connected touchscreen")
        XCTAssertNil(mode.justSetUp)
        XCTAssertNil(mode.notice)
        XCTAssertNil(model.snapshot.setUp)
        XCTAssertEqual(try touchscreen(ilitek, model).mode, .settingUp, "held for the mode")
        XCTAssertEqual(try touchscreen(strip, model).mode, .settingUp)
        XCTAssertNil(try touchscreen(oldPanel, model).mode)
        XCTAssertFalse(try touchscreen(ilitek, model).canBeSetUp, "the mode couldn't begin again now")
    }

    func testBeginSetUpFullIsReadAsTheMode() {
        let model = model()
        model.perform(.beginSetUp(strip, .full))
        XCTAssertEqual(model.snapshot.setUpMode?.stage, .choosing)
        XCTAssertNil(model.snapshot.setUp)
    }

    /// Only when Tactile is on, Accessibility granted, no set-up running, a touchscreen can be set up
    /// and a candidate display exists.
    func testTheModeBeginsOnlyWhenItCould() throws {
        for variant in [PreviewModel.Variant.tactileOff, .accessibilityMissing, .allWarnings] {
            let model = model(variant)
            model.perform(.beginSetUpMode)
            XCTAssertNil(model.snapshot.setUpMode, "\(variant)")
        }
        let testing = model()
        testing.perform(.beginSetUp(ilitek, .test))
        testing.perform(.beginSetUpMode)
        XCTAssertNil(testing.snapshot.setUpMode, "a test from a pane runs")

        let noDisplay = model()
        for name in ["HDMI", "LG HDR 4K", "Display", "12.3FHD"] {
            noDisplay.simulate(.displayConnected(try id(name, noDisplay), false))
        }
        noDisplay.perform(.beginSetUpMode)
        XCTAssertNil(noDisplay.snapshot.setUpMode, "no candidate display")

        let noTouchscreen = model()
        noTouchscreen.simulate(.touchscreenConnected(ilitek, false))
        noTouchscreen.simulate(.touchscreenConnected(strip, false))
        noTouchscreen.perform(.beginSetUpMode)
        XCTAssertNil(noTouchscreen.snapshot.setUpMode, "no touchscreen to set up")
    }

    // MARK: - Click, then touch

    func testChooseThenTouch() throws {
        let model = model()
        let lg = try id("LG HDR 4K", model)
        model.perform(.beginSetUpMode)
        model.perform(.setUpChoose(displayID: lg))
        XCTAssertEqual(try stage(model), .waitingForTouch(display: lg))
        model.simulate(.touch(ilitek))
        XCTAssertEqual(try stage(model), .running)
        let setUp = try XCTUnwrap(model.snapshot.setUp)
        XCTAssertEqual(setUp.touchscreen, ilitek)
        XCTAssertEqual(setUp.purpose, .full)
        XCTAssertEqual(setUp.step, .corners(display: lg, target: Calibration.targets[0], index: 0, problem: nil))

        finishFlow(model, inches: 27)
        XCTAssertNil(model.snapshot.setUp)
        let mode = try XCTUnwrap(model.snapshot.setUpMode)
        XCTAssertEqual(mode.stage, .choosing)
        XCTAssertEqual(mode.justSetUp, ilitek)
        XCTAssertEqual(mode.displays.first { $0.id == lg }?.touchscreen, ilitek)
        XCTAssertNil(mode.displays.first { $0.name == "HDMI" }?.touchscreen, "its old display is free")
        XCTAssertEqual(mode.touchscreens.first { $0.id == ilitek }?.state, .setUp(displayName: "LG HDR 4K"))
        XCTAssertEqual(try touchscreen(ilitek, model).pairedDisplayID, lg)
        XCTAssertEqual(try touchscreen(ilitek, model).diagonalInches, 27)
    }

    func testChoosingAnotherDisplayWhileWaiting() throws {
        let model = model()
        let lg = try id("LG HDR 4K", model), display = try id("Display", model)
        model.perform(.beginSetUpMode)
        model.perform(.setUpChoose(displayID: lg))
        model.perform(.setUpChoose(displayID: display))
        XCTAssertEqual(try stage(model), .waitingForTouch(display: display))
        model.perform(.setUpChoose(displayID: try id("Built-in Retina Display", model)))
        XCTAssertEqual(try stage(model), .waitingForTouch(display: display), "the built-in display is never a candidate")
    }

    // MARK: - Touch, then click

    func testTouchThenChoose() throws {
        let model = model()
        let fhd = try id("12.3FHD", model)
        model.perform(.beginSetUpMode)
        model.simulate(.touch(strip))
        XCTAssertEqual(try stage(model), .touchedFirst(touchscreen: strip, name: "TouchScreen"))
        XCTAssertNil(model.snapshot.setUp)
        model.simulate(.touch(ilitek))
        XCTAssertEqual(try stage(model), .touchedFirst(touchscreen: ilitek, name: "ILITEK-TP"), "the latest touch")
        model.simulate(.touch(strip))
        model.perform(.setUpChoose(displayID: fhd))
        XCTAssertEqual(try stage(model), .running)
        XCTAssertEqual(model.snapshot.setUp?.touchscreen, strip)
        XCTAssertEqual(model.snapshot.setUp?.step,
                       .corners(display: fhd, target: Calibration.targets[0], index: 0, problem: nil))
    }

    /// Another touchscreen's touch while a flow runs is ignored; the flow's own is its next tap.
    func testOnlyTheFlowsTouchscreenTapsWhileItRuns() throws {
        let model = model()
        model.perform(.beginSetUpMode)
        model.perform(.setUpChoose(displayID: try id("LG HDR 4K", model)))
        model.simulate(.touch(ilitek))
        let corners = model.snapshot
        model.simulate(.touch(strip))
        XCTAssertEqual(model.snapshot, corners)
        model.simulate(.touch(ilitek))
        guard case .corners(_, _, 1, _)? = model.snapshot.setUp?.step else { return XCTFail("the second target") }
    }

    // MARK: - Back

    func testBackFromEachStage() throws {
        let model = model()
        let before = model.snapshot
        model.perform(.beginSetUpMode)
        let overview = model.snapshot
        model.perform(.setUpChoose(displayID: try id("LG HDR 4K", model)))
        model.perform(.setUpBack)
        XCTAssertEqual(model.snapshot, overview, "waiting for a touch")
        model.simulate(.touch(strip))
        model.perform(.setUpBack)
        XCTAssertEqual(model.snapshot, overview, "touched first")
        model.perform(.setUpChoose(displayID: try id("LG HDR 4K", model)))
        model.simulate(.touch(strip))
        for _ in 0..<4 { model.touchSetUp() }
        model.perform(.setUpConfirmSize(inches: 20))
        model.perform(.setUpBack)
        XCTAssertEqual(model.snapshot, overview, "the check: nothing stored")
        model.perform(.cancelSetUp)
        XCTAssertEqual(model.snapshot, before)
    }

    // MARK: - Test, and Calibrate, in the mode

    func testTestFromACard() throws {
        let model = model()
        let hdmi = try id("HDMI", model)
        model.perform(.beginSetUpMode)
        model.perform(.beginSetUp(ilitek, .test))
        XCTAssertEqual(try stage(model), .running)
        XCTAssertEqual(model.snapshot.setUp?.purpose, .test)
        XCTAssertEqual(model.snapshot.setUp?.step, .check(display: hdmi))
        model.perform(.setUpDone)
        XCTAssertEqual(try stage(model), .choosing)
        XCTAssertNil(model.snapshot.setUpMode?.justSetUp, "a test sets nothing up")

        model.perform(.setUpChoose(displayID: try id("LG HDR 4K", model)))
        model.perform(.beginSetUp(ilitek, .test))
        XCTAssertNil(model.snapshot.setUp, "Test only while every display offers itself")
    }

    // MARK: - Review Focus 4: a display taken from another touchscreen

    func testADisplayTakenFromAnotherTouchscreen() throws {
        let model = model()
        let hdmi = try id("HDMI", model)
        model.perform(.beginSetUpMode)
        model.perform(.setUpChoose(displayID: hdmi))
        model.simulate(.touch(strip))
        finishFlow(model)
        XCTAssertEqual(try touchscreen(strip, model).pairedDisplayID, hdmi)
        XCTAssertNil(try touchscreen(ilitek, model).pairedDisplayName, "unpaired in the same change")
        let mode = try XCTUnwrap(model.snapshot.setUpMode)
        XCTAssertEqual(mode.displays.first { $0.id == hdmi }?.touchscreen, strip)
        XCTAssertEqual(mode.touchscreens.map(\.state), [.notSetUp, .setUp(displayName: "HDMI")])
    }

    // MARK: - Notices

    func testATouchFromOneThatCannotBeSetUp() throws {
        let model = model(.identicalTwins)
        model.perform(.beginSetUpMode)
        let twin = try XCTUnwrap(model.snapshot.touchscreens.first { $0.notes.contains(.cannotBeToldApart) })
        model.simulate(.touch(twin.id))
        XCTAssertEqual(try stage(model), .choosing)
        XCTAssertEqual(model.snapshot.setUpMode?.notice, .cannotBeSetUp(touchscreen: twin.id, name: "ILITEK-TP"))
        model.perform(.setUpChoose(displayID: try id("LG HDR 4K", model)))
        XCTAssertNil(model.snapshot.setUpMode?.notice, "until the stage changes")
        model.simulate(.touch(twin.id))
        XCTAssertEqual(try stage(model), .waitingForTouch(display: try id("LG HDR 4K", model)), "still waiting")
        XCTAssertNotNil(model.snapshot.setUpMode?.notice)
    }

    func testTheChosenDisplayGoes() throws {
        let model = model()
        let lg = try id("LG HDR 4K", model)
        model.perform(.beginSetUpMode)
        model.perform(.setUpChoose(displayID: lg))
        model.simulate(.displayConnected(lg, false))
        XCTAssertEqual(try stage(model), .choosing)
        XCTAssertEqual(model.snapshot.setUpMode?.notice, .displayGone(name: "LG HDR 4K"))
        XCTAssertFalse(model.snapshot.setUpMode?.displays.contains { $0.id == lg } ?? true)

        // While its flow runs.
        model.simulate(.displayConnected(lg, true))
        model.perform(.setUpChoose(displayID: lg))
        model.simulate(.touch(ilitek))
        model.touchSetUp()
        model.simulate(.displayConnected(lg, false))
        XCTAssertEqual(try stage(model), .choosing)
        XCTAssertNil(model.snapshot.setUp)
        XCTAssertEqual(model.snapshot.setUpMode?.notice, .displayGone(name: "LG HDR 4K"))
        XCTAssertEqual(try touchscreen(ilitek, model).pairedDisplayID, try id("HDMI", model), "nothing stored")
    }

    func testTheAnsweringTouchscreenGoes() throws {
        let model = model()
        model.perform(.beginSetUpMode)
        model.simulate(.touch(strip))
        model.simulate(.touchscreenConnected(strip, false))
        XCTAssertEqual(try stage(model), .choosing)
        XCTAssertEqual(model.snapshot.setUpMode?.notice, .touchscreenGone(name: "TouchScreen"))
        XCTAssertEqual(model.snapshot.setUpMode?.touchscreens.map(\.id), [ilitek])

        model.perform(.setUpChoose(displayID: try id("LG HDR 4K", model)))
        model.simulate(.touch(ilitek))
        model.simulate(.touchscreenConnected(ilitek, false))
        XCTAssertNil(model.snapshot.setUp)
        XCTAssertEqual(model.snapshot.setUpMode?.notice, .touchscreenGone(name: "ILITEK-TP"))
    }

    // MARK: - Leaving

    /// Finish keeps what was Done and stores nothing more; every touchscreen goes back to its table
    /// mode.
    func testFinishKeepsWhatWasDone() throws {
        let model = model(.nothingPaired)
        let hdmi = try id("HDMI", model), lg = try id("LG HDR 4K", model)
        model.perform(.beginSetUpMode)
        model.perform(.setUpChoose(displayID: hdmi))
        model.simulate(.touch(ilitek))
        finishFlow(model)
        model.perform(.setUpChoose(displayID: lg))
        model.simulate(.touch(strip))
        for _ in 0..<4 { model.touchSetUp() }
        model.perform(.cancelSetUp)
        XCTAssertNil(model.snapshot.setUpMode)
        XCTAssertNil(model.snapshot.setUp)
        XCTAssertEqual(try touchscreen(ilitek, model).pairedDisplayID, hdmi)
        XCTAssertEqual(try touchscreen(ilitek, model).mode, .driving)
        XCTAssertNil(try touchscreen(strip, model).pairedDisplayName, "its flow wasn't Done")
        XCTAssertEqual(try touchscreen(strip, model).mode, .held)
        XCTAssertEqual(model.snapshot.offerSetUpTo, [], "not set up when the mode began: offered")
    }

    /// Two minutes without a command or a touch, in any stage, leave the mode as Esc would.
    func testTwoMinutesWithoutInputLeave() throws {
        for reach in [{ (_: PreviewModel) in }, { (model: PreviewModel) in model.simulate(.touch(self.strip)) }] {
            let model = model(.nothingPaired)
            let start = now
            model.perform(.beginSetUpMode)
            reach(model)
            now = start + 119
            model.tickSetUp()
            XCTAssertNotNil(model.snapshot.setUpMode)
            now = start + 120
            model.tickSetUp()
            XCTAssertNil(model.snapshot.setUpMode)
            XCTAssertEqual(model.snapshot.offerSetUpTo, [], "as Esc: offered")
        }
        // In a flow: its taps count as input.
        let model = model()
        let start = now
        model.perform(.beginSetUpMode)
        model.perform(.setUpChoose(displayID: try id("LG HDR 4K", model)))
        model.simulate(.touch(ilitek))
        now = start + 100
        model.touchSetUp()
        now = start + 200
        model.tickSetUp()
        XCTAssertNotNil(model.snapshot.setUpMode, "a tap 100 s ago")
        now = start + 220
        model.tickSetUp()
        XCTAssertNil(model.snapshot.setUpMode)

        // A touchscreen that can't be set up gives no input, however often it lands, as in the model.
        let twins = self.model(.identicalTwins)
        let begun = now
        twins.perform(.beginSetUpMode)
        let twin = try XCTUnwrap(twins.snapshot.touchscreens.first { $0.notes.contains(.cannotBeToldApart) })
        for seconds in stride(from: 10.0, through: 110, by: 10) {
            now = begun + seconds
            twins.simulate(.touch(twin.id))
        }
        XCTAssertNotNil(twins.snapshot.setUpMode)
        now = begun + 120
        twins.tickSetUp()
        XCTAssertNil(twins.snapshot.setUpMode, "the twin's touches kept nothing on")
    }

    /// While the mode is on, no fit changes, of any touchscreen.
    func testNoFitChangesWhileTheModeIsOn() throws {
        let model = model()
        model.perform(.beginSetUpMode)
        let overview = model.snapshot
        for command: AppCommand in [.setDiagonal(ilitek, inches: 20), .unpair(strip), .forget(oldPanel),
                                    .pair(strip, displayID: try id("LG HDR 4K", model)), .clearCalibration(ilitek)] {
            model.perform(command)
            XCTAssertEqual(model.snapshot, overview, "\(command)")
        }
    }

    func testEveryStageSurvivesJSON() throws {
        let model = model(.identicalTwins)
        var snapshots: [AppSnapshot] = []
        model.perform(.beginSetUpMode)
        snapshots.append(model.snapshot)
        model.simulate(.touch(strip))
        snapshots.append(model.snapshot)
        model.perform(.setUpChoose(displayID: try id("12.3FHD", model)))
        snapshots.append(model.snapshot)
        finishFlow(model)
        snapshots.append(model.snapshot)
        let twin = try XCTUnwrap(model.snapshot.touchscreens.first { $0.notes.contains(.cannotBeToldApart) })
        model.simulate(.touch(twin.id))
        snapshots.append(model.snapshot)
        for snapshot in snapshots {
            XCTAssertEqual(try JSONDecoder().decode(AppSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        }
    }
}
