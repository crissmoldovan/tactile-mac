import CoreGraphics
import Foundation
import TactileGestures
import TactileScreens
import XCTest

@testable import TactileApp

/// The preview model's 0.3.0 half: each touchscreen's behaviour, the commands that change it, and a
/// whole set-up walked through step by step on a clock the test moves. Set-up mode's stages are
/// `PreviewSetUpModeTests`'.
@MainActor
final class PreviewSetUpTests: XCTestCase {
    private let ilitek = UIFixtures.ilitek
    private let strip = UIFixtures.strip
    private let oldPanel = UIFixtures.oldPanel

    /// The time the test says it is.
    private var now: TimeInterval = 1000

    private func model(_ variant: PreviewModel.Variant = .desk) -> PreviewModel {
        PreviewModel(variant, clock: { [unowned self] in self.now })
    }

    private func touchscreen(_ id: TouchscreenID, _ model: PreviewModel) throws -> TouchscreenSnapshot {
        try XCTUnwrap(UIFixtures.touchscreen(id, in: model.snapshot))
    }

    private func displayID(_ name: String, _ model: PreviewModel) throws -> UInt32 {
        try XCTUnwrap(UIFixtures.displayID(named: name, in: model.snapshot))
    }

    private func step(_ model: PreviewModel) throws -> SetUpStep {
        try XCTUnwrap(model.snapshot.setUp).step
    }

    // MARK: - The desk in 0.3.0

    func testTheDesksBehaviour() throws {
        let model = model()
        let defaults = TouchscreenSettings()
        let ilitek = try touchscreen(self.ilitek, model)
        XCTAssertEqual(ilitek.behaviour, BehaviourSnapshot(
            oneFinger: .automatic, oneFingerChoice: nil, pointerReturn: defaults.pointerReturn,
            showsCircles: true,
            gestures: .all, rejection: RejectionRules(), reportsPalms: false, multiFingerAvailable: true))
        XCTAssertEqual(ilitek.notes, [.macOSIgnoresIt])
        XCTAssertTrue(ilitek.isCalibrated)
        XCTAssertTrue(ilitek.canBeSetUp)

        let strip = try touchscreen(self.strip, model)
        XCTAssertFalse(strip.behaviour.multiFingerAvailable)
        XCTAssertFalse(strip.behaviour.reportsPalms)
        XCTAssertEqual(strip.behaviour.oneFinger, .alwaysScroll, "its default: one finger comes through")
        XCTAssertNil(strip.behaviour.oneFingerChoice)
        XCTAssertFalse(strip.isCalibrated)
        XCTAssertTrue(strip.canBeSetUp)

        XCTAssertFalse(try touchscreen(oldPanel, model).canBeSetUp, "not connected")
        XCTAssertNil(model.snapshot.setUp)
        XCTAssertNil(model.snapshot.setUpMode)
        XCTAssertEqual(model.snapshot.offerSetUpTo, [])
        XCTAssertFalse(model.snapshot.recordsFrames)
    }

    func testIdenticalTwins() throws {
        let model = model(.identicalTwins)
        let twin = try XCTUnwrap(model.snapshot.touchscreens.first { $0.notes.contains(.cannotBeToldApart) })
        XCTAssertTrue(twin.isConnected)
        XCTAssertEqual(twin.name, "ILITEK-TP")
        XCTAssertEqual(twin.status, .notSetUp)
        XCTAssertNil(twin.location)
        XCTAssertFalse(twin.canBeSetUp)
        XCTAssertEqual(model.snapshot.offerSetUpTo, [], "it can't be set up, so it isn't offered")

        let before = model.snapshot
        for command: AppCommand in [
            .setTouchscreenOn(twin.id, false), .setOneFinger(twin.id, .alwaysScroll), .rename(twin.id, to: "Twin"),
            .beginSetUp(twin.id, .calibrate), .copyBehaviour(from: ilitek, to: twin.id), .resetBehaviour(twin.id),
            .pair(twin.id, displayID: try displayID("LG HDR 4K", model)),
        ] {
            model.perform(command)
            XCTAssertEqual(model.snapshot, before, "\(command): it has no record")
        }
        model.perform(.copyBehaviour(from: twin.id, to: strip))
        XCTAssertEqual(model.snapshot, before, "nor is it a source")
    }

    // MARK: - Behaviour commands

    func testEachBehaviourCommandChangesItsField() throws {
        let model = model()
        model.perform(.setOneFinger(ilitek, .alwaysScroll))
        XCTAssertEqual(try touchscreen(ilitek, model).behaviour.oneFinger, .alwaysScroll)
        model.perform(.setPointerReturn(ilitek, .staysWhereTouched))
        XCTAssertEqual(try touchscreen(ilitek, model).behaviour.pointerReturn, .staysWhereTouched)
        model.perform(.setShowsCircles(ilitek, false))
        XCTAssertFalse(try touchscreen(ilitek, model).behaviour.showsCircles)
        var gestures = GestureOptions.all
        gestures.swipes = false
        model.perform(.setGestures(ilitek, gestures))
        XCTAssertEqual(try touchscreen(ilitek, model).behaviour.gestures, gestures)
        model.perform(.setRejection(ilitek, RejectionRules(palm: false, edgeMarginMM: 6)))
        XCTAssertEqual(try touchscreen(ilitek, model).behaviour.rejection, RejectionRules(palm: false, edgeMarginMM: 6))

        let strip = try touchscreen(self.strip, model)
        XCTAssertEqual(strip.behaviour.oneFinger, .alwaysScroll, "one touchscreen's settings never on another")
        XCTAssertNil(strip.behaviour.oneFingerChoice)
        XCTAssertTrue(strip.behaviour.showsCircles)
    }

    /// The one-finger default follows the touchscreen's kind; a choice wins; nil goes back to it.
    func testTheOneFingerDefault() throws {
        let model = model()
        model.perform(.setOneFinger(strip, .automatic))
        var strip = try touchscreen(self.strip, model)
        XCTAssertEqual(strip.behaviour.oneFinger, .automatic, "a choice of Automatic, on the strip")
        XCTAssertEqual(strip.behaviour.oneFingerChoice, .automatic)
        model.perform(.setOneFinger(self.strip, nil))
        strip = try touchscreen(self.strip, model)
        XCTAssertEqual(strip.behaviour.oneFinger, .alwaysScroll, "back to its default")
        XCTAssertNil(strip.behaviour.oneFingerChoice)
        model.perform(.setOneFinger(ilitek, .alwaysScroll))
        model.perform(.resetBehaviour(ilitek))
        XCTAssertNil(try touchscreen(ilitek, model).behaviour.oneFingerChoice, "Reset: the default")
    }

    func testCopyingBehaviour() throws {
        let model = model()
        model.perform(.setOneFinger(strip, .alwaysDrag))
        model.perform(.setRejection(strip, RejectionRules(palm: false, edgeMarginMM: 3)))
        model.perform(.setWhenOff(strip, .leaveToMacOS))
        let ilitekBefore = try touchscreen(ilitek, model)
        model.perform(.copyBehaviour(from: strip, to: ilitek))
        let ilitek = try touchscreen(self.ilitek, model)
        XCTAssertEqual(ilitek.behaviour.oneFinger, .alwaysDrag)
        XCTAssertEqual(ilitek.behaviour.rejection, RejectionRules(palm: false, edgeMarginMM: 3))
        XCTAssertEqual(ilitek.whenOff, .leaveToMacOS)
        XCTAssertEqual(ilitek.behaviour.gestures, .all, "the strip's stored gestures, copied whole")
        XCTAssertTrue(ilitek.behaviour.multiFingerAvailable, "a property of the device, not copied")
        XCTAssertEqual(ilitek.pairedDisplayID, ilitekBefore.pairedDisplayID)
        XCTAssertEqual(ilitek.orientation, ilitekBefore.orientation)
        XCTAssertEqual(ilitek.diagonalInches, ilitekBefore.diagonalInches)
        XCTAssertEqual(ilitek.isCalibrated, ilitekBefore.isCalibrated)
        XCTAssertEqual(ilitek.name, ilitekBefore.name)

        let before = model.snapshot
        model.perform(.copyBehaviour(from: ilitek.id, to: ilitek.id))
        XCTAssertEqual(model.snapshot, before, "onto itself changes nothing")
        model.perform(.copyBehaviour(from: TouchscreenID(rawValue: "ffff:ffff:x"), to: ilitek.id))
        XCTAssertEqual(model.snapshot, before, "from nobody changes nothing")
    }

    func testCopyingFromARememberedTouchscreen() throws {
        let model = model()
        model.perform(.setShowsCircles(oldPanel, false))
        model.perform(.copyBehaviour(from: oldPanel, to: strip))
        XCTAssertFalse(try touchscreen(strip, model).behaviour.showsCircles)
    }

    func testResettingBehaviour() throws {
        let model = model()
        model.perform(.setOneFinger(ilitek, .alwaysScroll))
        model.perform(.setShowsCircles(ilitek, false))
        model.perform(.setWhenOff(ilitek, .leaveToMacOS))
        model.perform(.resetBehaviour(ilitek))
        XCTAssertEqual(model.snapshot, self.model().snapshot)
    }

    func testUsingTheWholeGlass() throws {
        let model = model()
        model.perform(.clearCalibration(ilitek))
        XCTAssertFalse(try touchscreen(ilitek, model).isCalibrated)
    }

    func testRecordingFrames() {
        let model = model()
        model.perform(.setRecordsFrames(true))
        XCTAssertTrue(model.snapshot.recordsFrames)
        model.perform(.setRecordsFrames(false))
        XCTAssertFalse(model.snapshot.recordsFrames)
        let before = model.snapshot
        model.perform(.copyDiagnostics)
        XCTAssertEqual(model.snapshot, before)
        XCTAssertEqual(model.diagnosticsCopied, 1)
    }

    // MARK: - The offer

    /// Every touchscreen that isn't set up and wasn't offered, at once; Not Now declines one.
    func testTheOfferNamesEveryTouchscreenNotSetUp() {
        let model = model(.nothingPaired)
        XCTAssertEqual(model.snapshot.offerSetUpTo, [ilitek, strip])
        model.perform(.declineSetUp(ilitek))
        XCTAssertEqual(model.snapshot.offerSetUpTo, [strip])
        model.perform(.declineSetUp(strip))
        XCTAssertEqual(model.snapshot.offerSetUpTo, [])
    }

    /// No offer while set-up mode is on. Leaving it by Finish offers no touchscreen again that was
    /// not set up when it began; Tactile turned off (an interruption) leaves the offer as it was.
    func testNoOfferWhileSetUpModeIsOn() {
        let finished = model(.nothingPaired)
        finished.perform(.beginSetUpMode)
        XCTAssertEqual(finished.snapshot.offerSetUpTo, [])
        finished.perform(.cancelSetUp)
        XCTAssertNil(finished.snapshot.setUpMode)
        XCTAssertEqual(finished.snapshot.offerSetUpTo, [], "both were offered: the mode was begun for them")

        let interrupted = model(.nothingPaired)
        interrupted.perform(.beginSetUpMode)
        interrupted.perform(.setOn(false))
        XCTAssertNil(interrupted.snapshot.setUpMode)
        interrupted.perform(.setOn(true))
        XCTAssertEqual(interrupted.snapshot.offerSetUpTo, [ilitek, strip], "an interruption marks nothing")
    }

    // MARK: - A whole set-up

    func testAFullSetUpStepByStep() throws {
        let model = model(.nothingPaired)
        let hdmi = try displayID("HDMI", model)
        model.perform(.beginSetUp(ilitek, .full))
        XCTAssertNotNil(model.snapshot.setUpMode, "a full set-up is set-up mode")
        XCTAssertNil(model.snapshot.setUp)
        model.perform(.setUpChoose(displayID: hdmi))
        model.simulate(.touch(ilitek))
        let setUp = try XCTUnwrap(model.snapshot.setUp)
        XCTAssertEqual(setUp.touchscreen, ilitek)
        XCTAssertEqual(setUp.touchscreenName, "ILITEK-TP")
        XCTAssertEqual(setUp.purpose, .full)
        XCTAssertEqual(setUp.step, .corners(display: hdmi, target: Calibration.targets[0], index: 0, problem: nil),
                       "no pair step: the corners on the display chosen")
        XCTAssertEqual(try touchscreen(ilitek, model).mode, .settingUp)
        XCTAssertEqual(model.snapshot.offerSetUpTo, [])

        model.touchSetUp(.moved)
        XCTAssertEqual(try step(model), .corners(display: hdmi, target: Calibration.targets[0], index: 0, problem: .moved))
        model.touchSetUp()
        XCTAssertEqual(try step(model), .corners(display: hdmi, target: Calibration.targets[1], index: 1, problem: nil))
        model.touchSetUp()
        model.touchSetUp()
        XCTAssertEqual(try step(model), .corners(display: hdmi, target: Calibration.targets[3], index: 3, problem: nil))
        model.touchSetUp()
        guard case .size(let sizeDisplay, let displayReports, let touchscreenReports, let current) = try step(model) else {
            return XCTFail("size after four taps")
        }
        XCTAssertEqual(sizeDisplay, hdmi)
        XCTAssertEqual(try XCTUnwrap(displayReports), 27, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(touchscreenReports), 21.5, accuracy: 0.05)
        XCTAssertNil(current)

        model.perform(.setUpConfirmSize(inches: 1000))
        if case .size = try step(model) {} else { XCTFail("nonsense is refused") }
        model.perform(.setUpConfirmSize(inches: 23.8))
        XCTAssertEqual(try step(model), .check(display: hdmi))

        model.perform(.setUpDone)
        XCTAssertNil(model.snapshot.setUp)
        XCTAssertEqual(model.snapshot.setUpMode?.stage, .choosing, "back to the overview")
        let ilitek = try touchscreen(self.ilitek, model)
        XCTAssertEqual(ilitek.pairedDisplayID, hdmi)
        XCTAssertEqual(ilitek.diagonalInches, 23.8)
        XCTAssertTrue(ilitek.isCalibrated)
        XCTAssertEqual(ilitek.mode, .settingUp, "held for the mode until it ends")
        model.perform(.cancelSetUp)
        XCTAssertEqual(try touchscreen(self.ilitek, model).mode, .driving)
        XCTAssertEqual(model.snapshot.offerSetUpTo, [], "the strip was not set up when the mode began: offered")
    }

    /// The display was turned in macOS mid-round: the corners start again, with no problem.
    func testTheCornersCanStartAgainWithoutAProblem() throws {
        let model = model()
        model.perform(.beginSetUp(ilitek, .calibrate))
        let hdmi = try displayID("HDMI", model)
        model.touchSetUp()
        model.touchSetUp()
        model.restartSetUpCorners()
        XCTAssertEqual(try step(model), .corners(display: hdmi, target: Calibration.targets[0], index: 0, problem: nil))
    }

    /// As the flow does: two minutes without a touch or a button, and a calibration ends by itself.
    func testTwoMinutesWithoutInputEndTheSetUp() throws {
        let model = model()
        let start = now
        model.perform(.beginSetUp(ilitek, .calibrate))
        now = start + 60
        model.touchSetUp()
        now = start + 179
        model.tickSetUp()
        XCTAssertNotNil(model.snapshot.setUp, "a minute and 59 seconds since the last touch")
        now = start + 180
        model.tickSetUp()
        XCTAssertNil(model.snapshot.setUp)
        XCTAssertTrue(try touchscreen(ilitek, model).isCalibrated, "nothing changed")
    }

    func testTapsThatDoNotFitStartTheCornersAgain() throws {
        let model = model()
        model.perform(.beginSetUp(ilitek, .calibrate))
        let hdmi = try displayID("HDMI", model)
        model.touchSetUp()
        model.touchSetUp()
        model.touchSetUp(.tapsDidNotFit)
        XCTAssertEqual(try step(model), .corners(display: hdmi, target: Calibration.targets[0], index: 0, problem: .tapsDidNotFit))
    }

    func testRedoGoesBackToTheCorners() throws {
        let model = model()
        model.perform(.beginSetUp(ilitek, .calibrate))
        let hdmi = try displayID("HDMI", model)
        for _ in 0..<4 { model.touchSetUp() }
        XCTAssertEqual(try step(model), .check(display: hdmi), "calibrate has no size step")
        model.perform(.setUpRedo)
        XCTAssertEqual(try step(model), .corners(display: hdmi, target: Calibration.targets[0], index: 0, problem: nil))
    }

    func testCalibrating() throws {
        let model = model()
        model.perform(.setDiagonal(strip, inches: 12.3))
        model.perform(.beginSetUp(strip, .calibrate))
        let fhd = try displayID("12.3FHD", model)
        XCTAssertEqual(try step(model), .corners(display: fhd, target: Calibration.targets[0], index: 0, problem: nil))
        for _ in 0..<4 { model.touchSetUp() }
        model.perform(.setUpDone)
        let strip = try touchscreen(self.strip, model)
        XCTAssertTrue(strip.isCalibrated)
        XCTAssertEqual(strip.pairedDisplayID, fhd)
        XCTAssertEqual(strip.diagonalInches, 12.3, "kept")
    }

    func testTestingStoresNothing() throws {
        let model = model()
        let before = model.snapshot
        model.perform(.beginSetUp(ilitek, .test))
        XCTAssertEqual(try step(model), .check(display: try displayID("HDMI", model)))
        model.perform(.setUpRedo)
        XCTAssertEqual(try step(model), .check(display: try displayID("HDMI", model)), "a test has no corners to go back to")
        model.perform(.setUpDone)
        XCTAssertEqual(model.snapshot, before)
    }

    /// Finish (or Esc) at every stage of set-up mode, before anything is Done, changes nothing.
    func testLeavingAtEveryStageChangesNothing() throws {
        let stagesReached: [(String, (PreviewModel) throws -> Void)] = [
            ("choosing", { _ in }),
            ("waiting for a touch", { model in model.perform(.setUpChoose(displayID: try self.displayID("LG HDR 4K", model))) }),
            ("touched first", { model in model.simulate(.touch(self.strip)) }),
            ("corners", { model in
                model.perform(.setUpChoose(displayID: try self.displayID("LG HDR 4K", model)))
                model.simulate(.touch(self.strip))
            }),
            ("size", { model in
                model.perform(.setUpChoose(displayID: try self.displayID("LG HDR 4K", model)))
                model.simulate(.touch(self.strip))
                for _ in 0..<4 { model.touchSetUp() }
            }),
            ("check", { model in
                model.perform(.setUpChoose(displayID: try self.displayID("LG HDR 4K", model)))
                model.simulate(.touch(self.strip))
                for _ in 0..<4 { model.touchSetUp() }
                model.perform(.setUpConfirmSize(inches: 12.3))
            }),
        ]
        for (name, reach) in stagesReached {
            let model = model()
            let before = model.snapshot
            now += 1
            model.perform(.beginSetUpMode)
            now += 1
            try reach(model)
            XCTAssertNotNil(model.snapshot.setUpMode, name)
            model.perform(.cancelSetUp)
            XCTAssertEqual(model.snapshot, before, name)
        }
    }

    func testOneSetUpAtATime() throws {
        let model = model()
        model.perform(.beginSetUp(ilitek, .test))
        let running = model.snapshot
        for command: AppCommand in [.beginSetUp(strip, .full), .beginSetUpMode, .beginSetUp(strip, .calibrate)] {
            model.perform(command)
            XCTAssertEqual(model.snapshot, running, "\(command)")
        }
    }

    func testNoSetUpWhileTactileIsOffAndTurningItOffEndsOne() throws {
        let model = model()
        model.perform(.setOn(false))
        model.perform(.beginSetUpMode)
        model.perform(.beginSetUp(ilitek, .test))
        XCTAssertNil(model.snapshot.setUpMode)
        XCTAssertNil(model.snapshot.setUp)
        model.perform(.setOn(true))
        model.perform(.beginSetUp(ilitek, .test))
        XCTAssertNotNil(model.snapshot.setUp)
        model.perform(.setOn(false))
        XCTAssertNil(model.snapshot.setUp)
        model.perform(.setOn(true))
        model.perform(.beginSetUpMode)
        XCTAssertNotNil(model.snapshot.setUpMode)
        model.perform(.setOn(false))
        XCTAssertNil(model.snapshot.setUpMode)
    }

    func testCalibrationNeedsItsDisplay() {
        let model = model(.displayUnplugged)
        model.perform(.beginSetUp(ilitek, .calibrate))
        XCTAssertNil(model.snapshot.setUp)
        model.perform(.beginSetUp(ilitek, .test))
        XCTAssertNil(model.snapshot.setUp)
        model.perform(.beginSetUp(ilitek, .full))
        XCTAssertNotNil(model.snapshot.setUpMode, "set-up mode can pair it again")
    }

    /// As in the model: while a set-up runs, nothing changes a pairing, an orientation, an alignment
    /// or a diagonal, of any touchscreen; its Done stores those. The commands the pane's fit
    /// controls send are those the model refuses.
    func testNoFitChangesWhileASetUpRuns() throws {
        let model = model()
        model.perform(.beginSetUp(ilitek, .calibrate))
        let running = model.snapshot
        let commands: [AppCommand] = [
            .setDiagonal(ilitek, inches: 27),
            .setDiagonal(strip, inches: 10),
            .setOrientation(strip, Orientation(quarterTurns: 1, isFlipped: false)),
            .clearCalibration(ilitek),
            .pair(strip, displayID: try displayID("LG HDR 4K", model)),
            .unpair(strip),
            .forget(oldPanel),
        ]
        for command in commands {
            model.perform(command)
            XCTAssertEqual(model.snapshot, running, "\(command)")
            XCTAssertTrue(Resolver.changesAFit(command), "\(command): the model refuses it too")
        }
        model.perform(.cancelSetUp)
        model.perform(.setDiagonal(ilitek, inches: 27))
        XCTAssertEqual(try touchscreen(ilitek, model).diagonalInches, 27, "once it has ended")
    }

    func testStepCommandsOutsideTheirStepChangeNothing() throws {
        let model = model()
        let before = model.snapshot
        for command: AppCommand in [.setUpConfirmSize(inches: 20), .setUpRedo, .setUpDone, .cancelSetUp] {
            model.perform(command)
            XCTAssertEqual(model.snapshot, before, "\(command) with no set-up running")
        }
        model.perform(.beginSetUpMode)
        let overview = model.snapshot
        for command: AppCommand in [.setUpConfirmSize(inches: 20), .setUpRedo, .setUpDone, .setUpBack] {
            model.perform(command)
            XCTAssertEqual(model.snapshot, overview, "\(command) in set-up mode's overview")
        }
    }

    func testEverySetUpSnapshotSurvivesJSON() throws {
        let model = model(.nothingPaired)
        model.perform(.beginSetUpMode)
        var snapshots = [model.snapshot]
        model.perform(.setUpChoose(displayID: try displayID("HDMI", model)))
        snapshots.append(model.snapshot)
        model.simulate(.touch(ilitek))
        snapshots.append(model.snapshot)
        for _ in 0..<4 { model.touchSetUp() }
        snapshots.append(model.snapshot)
        model.perform(.setUpConfirmSize(inches: nil))
        snapshots.append(model.snapshot)
        for snapshot in snapshots {
            XCTAssertEqual(try JSONDecoder().decode(AppSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        }
    }
}
