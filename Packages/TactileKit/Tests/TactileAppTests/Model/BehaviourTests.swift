// Delivery 3, M3: each touchscreen's behaviour settings, from the command to the pipeline; the notes
// about the device; the paired display's remembered name.

import CoreGraphics
import Foundation
@testable import TactileApp
import TactileDevices
import TactileGestures
import TactileReading
import TactileScreens
import XCTest

private typealias Desk = DeskFixture

/// The desk, both touchscreens plugged in and started, from `settings`; removed when the test ends.
@MainActor
func deskHarness(_ test: XCTestCase, settings: TactileSettings = DeskFixture.settings,
                 writesStateFile: Bool = false) throws -> ModelHarness {
    let harness = try ModelHarness(settings: settings, writesStateFile: writesStateFile)
    test.addTeardownBlock { @MainActor in harness.cleanUp() }
    harness.source.statusWhenTaken[DeskFixture.stripHandle] = DeskFixture.taken(origin: .mouseInterface,
                                                                                inputMode: .switchedToMultiTouch)
    harness.source.plugIn(DeskFixture.ilitek())
    harness.source.plugIn(DeskFixture.stripScreen())
    harness.model.start()
    return harness
}

@MainActor
final class BehaviourTests: XCTestCase {
    private let ilitek = Desk.ilitekID
    private let strip = Desk.stripID
    private let ilitekDriving = Desk.driving(on: Desk.hdmi, diagonal: 23.8)

    /// A behaviour unlike the defaults in every field.
    private var unusual: TouchscreenSettings {
        var settings = TouchscreenSettings()
        settings.oneFinger = .alwaysScroll
        settings.pointerReturn = .staysWhereTouched
        settings.showsCircles = false
        settings.gestures.pinch = false
        settings.gestures.rotate = false
        settings.gestures.longPress = false
        settings.rejection = RejectionRules(palm: false, edgeMarginMM: 4)
        settings.whenOff = .leaveToMacOS
        return settings
    }

    // MARK: - The commands

    func testEachBehaviourCommandChangesExactlyItsField() {
        var inputs = Desk.inputs
        inputs.settings.touchscreens[strip]?.copyBehaviour(from: unusual)
        let before = inputs.settings
        let id = ilitek
        func expect(_ command: AppCommand, file: StaticString = #filePath, line: UInt = #line,
                    _ change: (inout TactileSettings) -> Void) {
            XCTAssertEqual(Resolver.apply(command, to: inputs), with(before, change), "\(command)", file: file, line: line)
        }
        var gestures = GestureOptions()
        gestures.pinch = false
        gestures.rotate = false
        let rules = RejectionRules(palm: false, edgeMarginMM: 4)

        expect(.setOneFinger(id, .alwaysScroll)) { $0.touchscreens[id]?.oneFinger = .alwaysScroll }
        // Back to the default: no choice stored.
        expect(.setOneFinger(strip, nil)) { $0.touchscreens[self.strip]?.oneFinger = nil }
        expect(.setPointerReturn(id, .staysWhereTouched)) { $0.touchscreens[id]?.pointerReturn = .staysWhereTouched }
        expect(.setShowsCircles(id, false)) { $0.touchscreens[id]?.showsCircles = false }
        expect(.setGestures(id, gestures)) { $0.touchscreens[id]?.gestures = gestures }
        expect(.setRejection(id, rules)) { $0.touchscreens[id]?.rejection = rules }
        expect(.copyBehaviour(from: strip, to: id)) { $0.touchscreens[id]?.copyBehaviour(from: self.unusual) }
        expect(.declineSetUp(id)) { $0.touchscreens[id]?.wasOfferedSetUp = true }
        expect(.setRecordsFrames(true)) { $0.recordsFrames = true }

        // Reset: the behaviour goes back to the defaults; the name, pairing, diagonal, switch and
        // offer stay.
        var changed = inputs
        changed.settings.touchscreens[id]?.copyBehaviour(from: unusual)
        changed.settings.touchscreens[id]?.customName = "Top"
        changed.settings.touchscreens[id]?.isOn = false
        changed.settings.touchscreens[id]?.wasOfferedSetUp = true
        let reset = Resolver.apply(.resetBehaviour(id), to: changed)
        XCTAssertEqual(reset, with(changed.settings) { $0.touchscreens[id]?.resetBehaviour() })
        XCTAssertEqual(reset.touchscreens[id]?.customName, "Top")
        XCTAssertEqual(reset.touchscreens[id]?.isOn, false)
        XCTAssertEqual(reset.touchscreens[id]?.wasOfferedSetUp, true)
        XCTAssertEqual(reset.touchscreens[id]?.diagonalInches, 23.8)
        XCTAssertEqual(reset.touchscreens[id]?.pairing, changed.settings.touchscreens[id]?.pairing)
        XCTAssertEqual(reset.touchscreens[id]?.gestures, .all)

        // Clearing the calibration: the whole glass again, the orientation kept.
        var calibrated = inputs
        let turned = Orientation(quarterTurns: 1, isFlipped: true)
        calibrated.settings.touchscreens[id]?.pairing?.orientation = turned
        calibrated.settings.touchscreens[id]?.pairing?.alignment = GlassAlignment(
            pictureRect: CGRect(x: 0.02, y: 0.03, width: 0.95, height: 0.9))
        XCTAssertTrue(Resolver.resolve(calibrated).snapshot.touchscreens.first { $0.id == id }?.isCalibrated ?? false)
        let cleared = Resolver.apply(.clearCalibration(id), to: calibrated)
        XCTAssertEqual(cleared, with(calibrated.settings) { $0.touchscreens[id]?.pairing?.alignment = .wholeGlass })
        XCTAssertEqual(cleared.touchscreens[id]?.pairing?.orientation, turned)

        // A remembered touchscreen's behaviour can be changed too, and copied from.
        let remembered = TouchscreenID(rawValue: "1234:5678:R")
        var withRemembered = inputs
        withRemembered.settings.touchscreens[remembered] = unusual
        XCTAssertEqual(Resolver.apply(.setOneFinger(remembered, .alwaysDrag), to: withRemembered).touchscreens[remembered]?.oneFinger,
                       .alwaysDrag)
        XCTAssertEqual(Resolver.apply(.copyBehaviour(from: remembered, to: id), to: withRemembered).touchscreens[id]?.gestures,
                       unusual.gestures)
    }

    func testBehaviourCommandsThatMustChangeNothing() {
        var inputs = Desk.inputs
        inputs.settings.touchscreens[strip]?.copyBehaviour(from: unusual)
        // A key that looks provisional, which only a hand could have put in the file.
        let handMade = TouchscreenID(rawValue: "#1:222a:0001:V06.00.00.00")
        inputs.settings.touchscreens[handMade] = unusual
        let unknown = TouchscreenID(rawValue: "ffff:ffff:nobody")
        let commands: [(String, AppCommand)] = [
            ("one finger, unknown", .setOneFinger(unknown, .alwaysDrag)),
            ("pointer return, unknown", .setPointerReturn(unknown, .staysWhereTouched)),
            ("circles, unknown", .setShowsCircles(unknown, false)),
            ("gestures, unknown", .setGestures(unknown, GestureOptions())),
            ("rejection, unknown", .setRejection(unknown, RejectionRules())),
            ("copy onto an unknown touchscreen", .copyBehaviour(from: strip, to: unknown)),
            ("copy from an unknown touchscreen", .copyBehaviour(from: unknown, to: ilitek)),
            ("copy onto itself", .copyBehaviour(from: strip, to: strip)),
            ("copy from a key that looks provisional", .copyBehaviour(from: handMade, to: ilitek)),
            ("copy onto a key that looks provisional", .copyBehaviour(from: strip, to: handMade)),
            ("reset, unknown", .resetBehaviour(unknown)),
            ("reset what is already the default", .resetBehaviour(ilitek)),
            ("clear the calibration of the whole glass", .clearCalibration(ilitek)),
            ("clear the calibration, unknown", .clearCalibration(unknown)),
            ("decline, unknown", .declineSetUp(unknown)),
            ("records frames, as it is", .setRecordsFrames(false)),
            ("begin set-up", .beginSetUp(ilitek, .full)),
            ("confirm a size", .setUpConfirmSize(inches: 23.8)),
            ("redo", .setUpRedo),
            ("done", .setUpDone),
            ("cancel", .cancelSetUp),
            ("copy diagnostics", .copyDiagnostics),
        ]
        for (name, command) in commands {
            XCTAssertEqual(Resolver.apply(command, to: inputs), inputs.settings, name)
        }

        // An unpaired touchscreen has no calibration to clear.
        var unpaired = inputs
        unpaired.settings.touchscreens[ilitek]?.unpair()
        XCTAssertEqual(Resolver.apply(.clearCalibration(ilitek), to: unpaired), unpaired.settings)
    }

    func testATouchscreenThatCannotBeToldApartChangesNothing() throws {
        var inputs = Desk.inputs
        inputs.records[Desk.ilitekHandle] = nil
        let resolved = Resolver.resolve(inputs)
        let provisional = try XCTUnwrap(resolved.touchscreens.first { $0.handle == Desk.ilitekHandle }?.id)
        XCTAssertTrue(Resolver.isProvisional(provisional))
        let snapshot = try XCTUnwrap(resolved.snapshot.touchscreens.first { $0.id == provisional })
        XCTAssertTrue(snapshot.notes.contains(.cannotBeToldApart))
        XCTAssertFalse(try XCTUnwrap(resolved.snapshot.touchscreens.first { $0.id == strip }).notes.contains(.cannotBeToldApart))

        inputs.settings.touchscreens[strip]?.copyBehaviour(from: unusual)
        for command: AppCommand in [
            .setOneFinger(provisional, .alwaysDrag), .setGestures(provisional, GestureOptions()),
            .setRejection(provisional, RejectionRules(palm: false)), .resetBehaviour(provisional),
            .copyBehaviour(from: strip, to: provisional), .copyBehaviour(from: provisional, to: strip),
            .declineSetUp(provisional), .clearCalibration(provisional),
        ] {
            XCTAssertEqual(Resolver.apply(command, to: inputs), inputs.settings, "\(command)")
        }
    }

    /// Review Focus 5.
    func testCopyOntoAOneFingerOnlyTouchscreen() throws {
        var inputs = Desk.inputs
        var gestures = GestureOptions()
        gestures.pinch = false
        inputs.settings.touchscreens[ilitek]?.gestures = gestures
        inputs.settings.touchscreens[ilitek]?.oneFinger = .alwaysDrag
        inputs.settings.touchscreens[ilitek]?.rejection = RejectionRules(palm: true, edgeMarginMM: 3)
        inputs.settings.touchscreens[ilitek]?.customName = "Top"
        inputs.settings.touchscreens[ilitek]?.pairing?.orientation = Orientation(quarterTurns: 2, isFlipped: false)
        inputs.settings.touchscreens[strip]?.customName = "Strip"
        let stripBefore = try XCTUnwrap(inputs.settings.touchscreens[strip])

        inputs.settings = Resolver.apply(.copyBehaviour(from: ilitek, to: strip), to: inputs)
        let stripAfter = try XCTUnwrap(inputs.settings.touchscreens[strip])

        XCTAssertEqual(stripAfter.gestures, gestures, "the stored gestures are copied")
        XCTAssertEqual(stripAfter.oneFinger, .alwaysDrag)
        XCTAssertEqual(stripAfter.rejection, RejectionRules(palm: true, edgeMarginMM: 3))
        XCTAssertEqual(stripAfter.customName, "Strip", "not the name")
        XCTAssertEqual(stripAfter.lastSeenName, stripBefore.lastSeenName)
        XCTAssertEqual(stripAfter.pairing, stripBefore.pairing, "not the pairing, orientation or alignment")
        XCTAssertEqual(stripAfter.diagonalInches, 12.3, "not the size")
        XCTAssertEqual(stripAfter.isOn, stripBefore.isOn)

        // It still behaves as one finger.
        let resolved = Resolver.resolve(inputs)
        let driving = try XCTUnwrap(resolved.touchscreens.first { $0.id == strip }?.driving)
        XCTAssertEqual(driving.options, .oneFingerOnly(keeping: gestures))
        XCTAssertEqual(driving.options.fingerLimit, 1)
        let snapshot = try XCTUnwrap(resolved.snapshot.touchscreens.first { $0.id == strip })
        XCTAssertEqual(snapshot.behaviour.gestures, gestures, "the snapshot shows what is stored")
        XCTAssertFalse(snapshot.behaviour.multiFingerAvailable)

        let outputs = RecordingOutputs()
        let pipeline = TouchPipeline(id: strip, driving: driving, outputs: outputs, cancelOther: { _, _ in })
        pipeline.handle(glassFrame(1.00, (0, 0.4, 0.5)))
        pipeline.handle(glassFrame(1.02, (0, 0.4, 0.5), (1, 0.6, 0.5)))
        pipeline.handle(glassFrame(1.10, (0, 0.4, 0.5), (1, 0.6, 0.5)))
        pipeline.handle(glassFrame(1.15))
        pipeline.tick(at: 2)
        XCTAssertEqual(outputs.count(.rightDown), 0, "a second finger is refused")
        XCTAssertEqual(outputs.count(.down), 1)
    }

    // MARK: - A 0.2.0 file

    /// Review Focus 6: a settings file as 0.2.0 wrote it.
    func testA020FileLoads() throws {
        let file = """
            {
              "debugLogging" : false,
              "displayNames" : { },
              "isOn" : true,
              "recordsFrames" : false,
              "touchscreens" : {
                "222a:0001:V06.00.00.00" : {
                  "diagonalInches" : 23.8,
                  "gestures" : { "pinch" : true, "swipes" : true, "twoFingerScroll" : true, "twoFingerTap" : true },
                  "isOn" : true,
                  "lastSeenName" : "ILITEK-TP",
                  "oneFinger" : "automatic",
                  "pairing" : {
                    "alignment" : { "pictureRect" : [ [ 0, 0 ], [ 1, 1 ] ] },
                    "display" : {
                      "model" : 3600, "nativeHeight" : 1440, "nativeWidth" : 2560, "serial" : 1,
                      "uuid" : "4C2D0E10-0000-0000-0A20-0104B53C2278", "vendor" : 19501
                    },
                    "orientation" : { "isFlipped" : false, "quarterTurns" : 2 }
                  },
                  "pointerReturn" : "backWhereItWas",
                  "showsCircles" : true,
                  "whenOff" : "ignoreTouches"
                },
                "27c0:0859:TEST-SERIAL-0001" : {
                  "diagonalInches" : 12.3,
                  "gestures" : { "pinch" : true, "swipes" : true, "twoFingerScroll" : true, "twoFingerTap" : true },
                  "isOn" : true,
                  "lastSeenName" : "TouchScreen",
                  "oneFinger" : "automatic",
                  "pairing" : {
                    "alignment" : { "pictureRect" : [ [ 0.01, 0.03 ], [ 0.98, 0.96 ] ] },
                    "display" : {
                      "model" : 291, "nativeHeight" : 720, "nativeWidth" : 1920, "serial" : 0,
                      "uuid" : "2D1E0123-0000-0000-1A21-0103802D1A78", "vendor" : 11550
                    },
                    "orientation" : { "isFlipped" : true, "quarterTurns" : 0 }
                  },
                  "pointerReturn" : "backWhereItWas",
                  "showsCircles" : true,
                  "whenOff" : "ignoreTouches"
                }
              },
              "version" : 1
            }
            """
        let harness = try ModelHarness(fileBytes: Data(file.utf8))
        addTeardownBlock { @MainActor in harness.cleanUp() }
        harness.source.statusWhenTaken[Desk.stripHandle] = Desk.taken(origin: .mouseInterface, inputMode: .switchedToMultiTouch)
        harness.source.plugIn(Desk.ilitek())
        harness.source.plugIn(Desk.stripScreen())
        harness.model.start()

        XCTAssertEqual(harness.model.snapshot.warnings, [], "nothing set aside")
        let defaults = TouchscreenSettings()
        let oneFinger: [TouchscreenID: OneFingerMode] = [ilitek: .automatic, strip: .alwaysScroll]
        for (id, display, orientation) in [(ilitek, Desk.hdmi, Orientation(quarterTurns: 2, isFlipped: false)),
                                           (strip, Desk.strip, Orientation(quarterTurns: 0, isFlipped: true))] {
            let snapshot = try XCTUnwrap(harness.touchscreen(id), "\(id)")
            XCTAssertEqual(snapshot.mode, .driving, "\(id)")
            XCTAssertEqual(snapshot.pairedDisplayID, display.displayID, "\(id): its pairing is kept")
            XCTAssertEqual(snapshot.orientation, orientation, "\(id): its orientation is kept")
            XCTAssertNil(snapshot.behaviour.oneFingerChoice, "\(id): \"automatic\" in a 0.2.0 file is the default")
            XCTAssertEqual(snapshot.behaviour.oneFinger, oneFinger[id], "\(id): the default for its kind")
            XCTAssertEqual(snapshot.behaviour.pointerReturn, defaults.pointerReturn, "\(id)")
            XCTAssertEqual(snapshot.behaviour.showsCircles, defaults.showsCircles, "\(id)")
            XCTAssertEqual(snapshot.behaviour.gestures, .all, "\(id): long-press and rotate at their defaults")
            XCTAssertEqual(snapshot.behaviour.rejection, RejectionRules(), "\(id)")
        }
        XCTAssertTrue(try XCTUnwrap(harness.touchscreen(strip)).isCalibrated, "the strip keeps its alignment")
        XCTAssertFalse(try XCTUnwrap(harness.touchscreen(ilitek)).isCalibrated)
        let saved = try XCTUnwrap(harness.savedSettings())
        XCTAssertEqual(saved.touchscreens[strip]?.pairing?.alignment,
                       GlassAlignment(pictureRect: CGRect(x: 0.01, y: 0.03, width: 0.98, height: 0.96)))
        XCTAssertEqual(saved.touchscreens[ilitek]?.wasOfferedSetUp, false)
    }

    // MARK: - Through a pipeline

    /// A one-finger stroke to the right, landing at `start`.
    private func stroke(_ pipeline: TouchPipeline, at start: TimeInterval) {
        for step in 0...4 {
            pipeline.handle(glassFrame(start + Double(step) * 0.03, (0, 0.30 + CGFloat(step) * 0.02, 0.5)))
        }
        pipeline.handle(glassFrame(start + 0.2))
    }

    func testAlwaysScrollScrollsWhereAutomaticWouldDrag() {
        let outputs = RecordingOutputs()
        outputs.intentAnswer = .drag
        let pipeline = TouchPipeline(id: ilitek, driving: ilitekDriving, outputs: outputs, cancelOther: { _, _ in })

        stroke(pipeline, at: 1)
        pipeline.tick(at: 2)
        XCTAssertEqual(outputs.count(.down), 1, "automatic: what is under the finger says drag")
        XCTAssertGreaterThan(outputs.count(.drag), 0)
        XCTAssertEqual(outputs.count(.scroll), 0)
        XCTAssertEqual(outputs.record.intentQuestions.count, 1)

        pipeline.update(with(ilitekDriving) { $0.oneFinger = .alwaysScroll })
        stroke(pipeline, at: 3)
        pipeline.tick(at: 4)
        XCTAssertEqual(outputs.count(.down), 1, "always scroll: no press")
        XCTAssertGreaterThan(outputs.count(.scroll), 0)
        XCTAssertEqual(outputs.record.intentQuestions.count, 1, "nothing asked")
    }

    func testStaysWhereTouched() {
        for (pointerReturn, warps) in [(PointerReturn.staysWhereTouched, [CGPoint]()),
                                       (.backWhereItWas, [Desk.pointerHome])] {
            let outputs = RecordingOutputs()
            let pipeline = TouchPipeline(id: ilitek, driving: with(ilitekDriving) { $0.pointerReturn = pointerReturn },
                                         outputs: outputs, cancelOther: { _, _ in })
            pipeline.handle(glassFrame(1.0, (0, 0.5, 0.5)))
            pipeline.handle(glassFrame(1.1))
            pipeline.tick(at: 2)
            XCTAssertEqual(outputs.count(.down), 1, "\(pointerReturn)")
            XCTAssertEqual(outputs.record.warps, warps, "\(pointerReturn)")
            if warps.isEmpty {
                XCTAssertTrue(Desk.hdmi.frame.contains(outputs.record.pointer), "left where the finger lifted")
            }
        }
    }

    /// A change of gestures applies to fingers that land afterwards: the touch in progress is
    /// judged as it began.
    func testAChangeOfGesturesWaitsForTheGlassToClear() {
        let outputs = RecordingOutputs()
        let pipeline = TouchPipeline(id: ilitek, driving: ilitekDriving, outputs: outputs, cancelOther: { _, _ in })
        pipeline.handle(glassFrame(1.00, (0, 0.4, 0.4)))
        pipeline.handle(glassFrame(1.02, (0, 0.4, 0.4), (1, 0.6, 0.4)))
        // Every multi-finger gesture off, with two fingers down.
        pipeline.update(with(ilitekDriving) { $0.options = Desk.noGestures })
        pipeline.handle(glassFrame(1.10, (0, 0.4, 0.4), (1, 0.6, 0.4)))
        pipeline.handle(glassFrame(1.15))
        XCTAssertEqual(outputs.count(.rightDown), 1, "the touch that began with the two-finger tap on is one")
        pipeline.tick(at: 1.8)

        // The next touch: one finger only, the second refused and drawn hollow.
        pipeline.handle(glassFrame(2.00, (0, 0.4, 0.4)))
        pipeline.handle(glassFrame(2.02, (0, 0.4, 0.4), (1, 0.6, 0.4)))
        XCTAssertEqual(outputs.record.circles.last,
                       .show(display: Desk.hdmi.displayID, fingers: [0: CGPoint(x: 0.4, y: 0.4), 1: CGPoint(x: 0.6, y: 0.4)],
                             hollow: [1]))
        pipeline.handle(glassFrame(2.10))
        pipeline.tick(at: 3)
        XCTAssertEqual(outputs.count(.rightDown), 1)
        XCTAssertEqual(outputs.count(.down), 1, "the first finger's tap clicks")
    }

    // MARK: - Through the model

    func testEveryBehaviourSettingReachesThePipelineWithoutEndingATouch() throws {
        let harness = try deskHarness(self)
        let frames = try SurveyTakes.ilitek(take: 11)
        let half = frames.count / 2
        harness.send(frames.prefix(half), from: Desk.ilitekHandle)
        XCTAssertEqual(harness.outputs.count(.down), 1, "the drag has started")
        let drags = harness.outputs.count(.drag)

        var gestures = GestureOptions()
        gestures.pinch = false
        for command: AppCommand in [
            .setOneFinger(ilitek, .alwaysScroll), .setPointerReturn(ilitek, .staysWhereTouched),
            .setRejection(ilitek, RejectionRules(palm: true, edgeMarginMM: 6)), .setGestures(ilitek, gestures),
            .setShowsCircles(ilitek, false),
        ] {
            harness.model.perform(command)
            XCTAssertEqual(harness.outputs.count(.up), 0, "\(command): the touch goes on")
        }
        XCTAssertNil(harness.log.first("event up"))
        XCTAssertEqual(harness.outputs.record.arrowHidden, [true], "never cancelled")

        harness.send(frames.dropFirst(half), from: Desk.ilitekHandle)
        harness.tick(after: 1)
        XCTAssertGreaterThan(harness.outputs.count(.drag), drags, "the drag went on")
        XCTAssertEqual(harness.outputs.count(.down), 1)
        XCTAssertEqual(harness.outputs.count(.up), 1)
        XCTAssertEqual(harness.outputs.count(.scroll), 0, "one-finger mode is decided when the finger starts moving")

        let snapshot = try XCTUnwrap(harness.touchscreen(ilitek))
        XCTAssertEqual(snapshot.behaviour.oneFinger, .alwaysScroll)
        XCTAssertEqual(snapshot.behaviour.pointerReturn, .staysWhereTouched)
        XCTAssertEqual(snapshot.behaviour.rejection, RejectionRules(palm: true, edgeMarginMM: 6))
        XCTAssertEqual(snapshot.behaviour.gestures, gestures)
        XCTAssertFalse(snapshot.behaviour.showsCircles)
        XCTAssertEqual(harness.savedSettings()?.touchscreens[ilitek]?.oneFinger, .alwaysScroll)

        // The next touch has them all: always scroll, no circles, the pointer left where it lifts.
        let circles = harness.outputs.record.circles.count
        let t = harness.clock + 1
        harness.send((0...4).map { glassFrame(t + Double($0) * 0.03, (0, 0.30 + CGFloat($0) * 0.02, 0.5)) }
                     + [glassFrame(t + 0.2)], from: Desk.ilitekHandle)
        harness.tick(after: 2)
        XCTAssertGreaterThan(harness.outputs.count(.scroll), 0)
        XCTAssertEqual(harness.outputs.count(.down), 1)
        XCTAssertEqual(harness.outputs.record.circles.count, circles)
        XCTAssertEqual(harness.outputs.record.warps, [Desk.pointerHome],
                       "the drag went home, as set when it began; this touch stays where it lifted")
    }

    func testCirclesOffMidTouchHidesThem() throws {
        let harness = try deskHarness(self)
        harness.send([glassFrame(100.00, (0, 0.5, 0.5))], from: Desk.ilitekHandle)
        XCTAssertEqual(harness.outputs.record.circles.last,
                       .show(display: Desk.hdmi.displayID, fingers: [0: CGPoint(x: 0.5, y: 0.5)], hollow: []))

        harness.model.perform(.setShowsCircles(ilitek, false))
        XCTAssertEqual(harness.outputs.record.circles.last, .hide(display: Desk.hdmi.displayID))
        let circles = harness.outputs.record.circles.count

        harness.send([glassFrame(100.05, (0, 0.5, 0.5)), glassFrame(100.10)], from: Desk.ilitekHandle)
        XCTAssertEqual(harness.outputs.record.circles.count, circles, "nothing more is drawn")
        XCTAssertEqual(harness.outputs.count(.down), 1, "the tap still clicks")
        XCTAssertEqual(harness.outputs.count(.up), 1)
    }

    // MARK: - The notes

    func testMacOSIgnoresATouchscreenWithNoInputModeThatSendsTouches() throws {
        let harness = try deskHarness(self)
        XCTAssertTrue(try XCTUnwrap(harness.touchscreen(ilitek)).notes.contains(.macOSIgnoresIt),
                      "touches from its touch interface, no Input Mode setting")
        XCTAssertFalse(try XCTUnwrap(harness.touchscreen(strip)).notes.contains(.macOSIgnoresIt), "a mouse to macOS")

        // Left to macOS, it is released and its status says nothing; what it said while taken holds.
        harness.model.perform(.setTouchscreenOn(ilitek, false))
        harness.model.perform(.setWhenOff(ilitek, .leaveToMacOS))
        XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .released)
        XCTAssertTrue(try XCTUnwrap(harness.touchscreen(ilitek)).notes.contains(.macOSIgnoresIt))

        // A new connection that has never been taken: not known.
        harness.model.perform(.setOn(false))
        harness.source.unplug(Desk.ilitekHandle)
        harness.source.plugIn(Desk.ilitek(handle: DeviceHandle(rawValue: 9)))
        XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .released)
        XCTAssertFalse(try XCTUnwrap(harness.touchscreen(ilitek)).notes.contains(.macOSIgnoresIt))

        // A panel that was switched to multi-touch can be switched back: macOS would use it.
        var switched = Desk.inputs
        switched.connected[0].status.inputMode = .switchedToMultiTouch
        let snapshot = try XCTUnwrap(Resolver.resolve(switched).snapshot.touchscreens.first { $0.id == ilitek })
        XCTAssertFalse(snapshot.notes.contains(.macOSIgnoresIt))
    }

    /// Review item 5: a touchscreen whose touches came from its mouse interface stays one finger
    /// only in the snapshot while it is released.
    func testOneFingerOnlyHoldsWhileReleased() throws {
        let harness = try deskHarness(self)
        XCTAssertEqual(harness.touchscreen(strip)?.behaviour.multiFingerAvailable, false)
        harness.model.perform(.setOn(false))
        XCTAssertEqual(harness.touchscreen(strip)?.mode, .released)
        XCTAssertEqual(harness.touchscreen(strip)?.behaviour.multiFingerAvailable, false, "Tactile off")
        XCTAssertTrue(try XCTUnwrap(harness.touchscreen(strip)).notes.contains(.oneFingerOnly))
        harness.model.perform(.setOn(true))
        harness.conditions.setSessionActive(false)
        XCTAssertEqual(harness.touchscreen(strip)?.behaviour.multiFingerAvailable, false, "locked")
        XCTAssertEqual(harness.touchscreen(ilitek)?.behaviour.multiFingerAvailable, true)
    }

    // MARK: - The paired display's name

    func testThePairedDisplaysNameIsRemembered() throws {
        let harness = try deskHarness(self)
        let saved = try XCTUnwrap(harness.savedSettings())
        XCTAssertEqual(saved.touchscreens[ilitek]?.pairing?.displayName, "HDMI")
        XCTAssertEqual(saved.touchscreens[strip]?.pairing?.displayName, "12.3FHD")

        // HDMI is unplugged, and Tactile relaunched: the name is still known.
        harness.displays.set(Desk.displays.filter { $0.displayID != Desk.hdmi.displayID })
        XCTAssertEqual(harness.touchscreen(ilitek)?.status, .displayNotConnected(name: "HDMI"))
        harness.model.shutDown()
        let relaunched = try ModelHarness(settings: harness.savedSettings())
        addTeardownBlock { @MainActor in relaunched.cleanUp() }
        relaunched.displays.set(Desk.displays.filter { $0.displayID != Desk.hdmi.displayID })
        relaunched.source.plugIn(Desk.ilitek())
        relaunched.model.start()
        XCTAssertEqual(relaunched.touchscreen(ilitek)?.status, .displayNotConnected(name: "HDMI"))
        XCTAssertEqual(relaunched.touchscreen(ilitek)?.pairedDisplayName, "HDMI")
        XCTAssertNil(relaunched.touchscreen(ilitek)?.pairedDisplayID)

        // A new name from macOS is remembered.
        relaunched.displays.set(Desk.displays.map { $0.displayID == Desk.hdmi.displayID ? with($0) { $0.name = "Dell" } : $0 })
        XCTAssertEqual(relaunched.savedSettings()?.touchscreens[ilitek]?.pairing?.displayName, "Dell")
    }

    func testAMirroringDisplayNeverOverwritesTheRememberedName() throws {
        let harness = try deskHarness(self)
        let before = try Data(contentsOf: harness.settingsURL)

        // HDMI now mirrors the LG: it has no screen of its own, and macOS gives it no name.
        let mirroring = with(Desk.hdmi) {
            $0.mirrors = Desk.lg.displayID
            $0.name = "Display"
        }
        harness.displays.set(Desk.displays.map { $0.displayID == Desk.hdmi.displayID ? mirroring : $0 })
        XCTAssertEqual(try Data(contentsOf: harness.settingsURL), before, "nothing saved")
        XCTAssertEqual(harness.savedSettings()?.touchscreens[ilitek]?.pairing?.displayName, "HDMI")
        let snapshot = try XCTUnwrap(harness.touchscreen(ilitek))
        XCTAssertEqual(snapshot.mode, .driving)
        XCTAssertEqual(snapshot.pairedDisplayName, "HDMI", "named as it was, not \"Display\"")
        if case .pairedWith(let name, _) = snapshot.status {
            XCTAssertEqual(name, "HDMI")
        } else {
            XCTFail("\(snapshot.status)")
        }
        XCTAssertEqual(harness.model.snapshot.displays.first { $0.id == Desk.hdmi.displayID }?.name, "HDMI")

        harness.displays.set(Desk.displays.filter { $0.displayID != Desk.hdmi.displayID })
        XCTAssertEqual(harness.touchscreen(ilitek)?.status, .displayNotConnected(name: "HDMI"))
    }

    /// Review item 6: a display read before AppKit has its screen is called "Display" for a
    /// moment; that never replaces a name remembered.
    func testTheFallbackNameNeverReplacesARememberedOne() throws {
        let harness = try deskHarness(self)
        XCTAssertEqual(harness.savedSettings()?.touchscreens[ilitek]?.pairing?.displayName, "HDMI")
        let before = try Data(contentsOf: harness.settingsURL)

        harness.displays.set(Desk.displays.map { $0.displayID == Desk.hdmi.displayID ? with($0) { $0.name = "Display" } : $0 })
        XCTAssertEqual(try Data(contentsOf: harness.settingsURL), before, "nothing saved")
        XCTAssertEqual(harness.touchscreen(ilitek)?.pairedDisplayName, "HDMI")
        if case .pairedWith(let name, _)? = harness.touchscreen(ilitek)?.status {
            XCTAssertEqual(name, "HDMI")
        } else {
            XCTFail("paired")
        }
        harness.displays.set(Desk.displays.filter { $0.displayID != Desk.hdmi.displayID })
        XCTAssertEqual(harness.touchscreen(ilitek)?.status, .displayNotConnected(name: "HDMI"))

        // A display with no name remembered yet takes "Display": it may really be called that.
        var inputs = Desk.inputs
        inputs.settings.touchscreens[ilitek]?.pair(with: DisplayIdentity(Desk.display))
        XCTAssertEqual(Resolver.rememberingDisplayNames(inputs).touchscreens[ilitek]?.pairing?.displayName, "Display")
    }

    func testADisplayReallyCalledDisplayIsRemembered() throws {
        var inputs = Desk.inputs
        inputs.settings.touchscreens[ilitek]?.pair(with: DisplayIdentity(Desk.display))
        let settings = Resolver.rememberingDisplayNames(inputs)
        XCTAssertEqual(settings.touchscreens[ilitek]?.pairing?.displayName, "Display", "its own name, though the same word")
        XCTAssertEqual(settings.touchscreens[strip]?.pairing?.displayName, "12.3FHD")

        // A remembered touchscreen whose display is connected learns its name by the display's UUID.
        inputs.connected.removeFirst()
        inputs.records[Desk.ilitekHandle] = nil
        XCTAssertEqual(Resolver.rememberingDisplayNames(inputs).touchscreens[ilitek]?.pairing?.displayName, "Display")

        // Up to date: unchanged.
        inputs.settings = Resolver.rememberingDisplayNames(inputs)
        XCTAssertEqual(Resolver.rememberingDisplayNames(inputs), inputs.settings)
    }
}
