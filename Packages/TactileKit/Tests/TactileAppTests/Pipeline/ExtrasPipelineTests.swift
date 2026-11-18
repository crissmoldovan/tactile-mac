// Delivery 3, M5: the Extras gestures from Delivery 4a, wired into the pipeline: long-press with its
// ring, rotate, palm and edge rejection. Through pipelines with the recording outputs: nothing here
// posts an event, moves the pointer or opens a window.

import CoreGraphics
import Foundation
@testable import TactileApp
import TactileDevices
import TactileGestures
import TactileReading
import TactileScreens
import XCTest

private typealias Desk = DeskFixture

/// A frame whose contacts may carry a size (a share of the glass) and a confidence flag.
private func frame(_ time: TimeInterval, _ contacts: (Int, CGFloat, CGFloat, CGSize?, Bool?)...) -> ContactFrame {
    ContactFrame(time: time, contacts: contacts.map {
        Contact(id: $0.0, position: CGPoint(x: $0.1, y: $0.2), size: $0.3, isConfident: $0.4)
    })
}

@MainActor
final class ExtrasPipelineTests: XCTestCase {
    private let ilitekDriving = Desk.driving(on: Desk.hdmi, diagonal: 23.8)

    private func single(_ driving: Driving, _ outputs: RecordingOutputs, id: TouchscreenID = Desk.ilitekID) -> TouchPipeline {
        TouchPipeline(id: id, driving: driving, outputs: outputs, cancelOther: { other, _ in
            XCTFail("nothing to take over from \(other)")
        })
    }

    /// Ticks `pipeline` at 60 Hz from `start` to `end`, as the model's clock does.
    private func tick(_ pipeline: TouchPipeline, from start: TimeInterval, to end: TimeInterval) {
        var time = start
        while time < end {
            time = min(end, time + 1.0 / 60)
            pipeline.tick(at: time)
        }
    }

    private func buttons(_ outputs: RecordingOutputs) -> [PostedEvent.Kind] {
        outputs.events.map(\.kind).filter { [.down, .up, .rightDown, .rightUp].contains($0) }
    }

    // MARK: - Long-press and its ring

    func testAPressHeldThenLiftedRightClicksWithTheRingFromATick() {
        let outputs = RecordingOutputs()
        let pipeline = single(ilitekDriving, outputs)
        pipeline.handle(glassFrame(1.0, (0, 0.5, 0.5)))
        XCTAssertEqual(outputs.record.circles, [.show(display: Desk.hdmi.displayID, fingers: [0: CGPoint(x: 0.5, y: 0.5)],
                                                      hollow: [])])

        // The panel is quiet while the finger rests: the ready action comes from a tick.
        tick(pipeline, from: 1.0, to: 1.7)
        XCTAssertEqual(outputs.record.circles.count, 2, "drawn again on the tick that rang")
        XCTAssertEqual(outputs.record.circles.last, .show(display: Desk.hdmi.displayID,
                                                          fingers: [0: CGPoint(x: 0.5, y: 0.5)], hollow: [], ringed: [0]))
        XCTAssertEqual(buttons(outputs), [], "nothing yet")

        pipeline.handle(glassFrame(1.7))
        tick(pipeline, from: 1.7, to: 2.5)
        XCTAssertEqual(buttons(outputs), [.rightDown, .rightUp], "one right-click, no left click")
        let point = Desk.mapping(on: Desk.hdmi).desktopPoint(forDisplay: CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(outputs.events(.rightDown).first?.location, point)
        XCTAssertEqual(outputs.record.circles.last?.ringed, [], "the ring is gone")
        XCTAssertEqual(outputs.record.circles.filter { $0.ringed == [0] }.count, 1)
    }

    func testAPressHeldThenDraggedIsADragAndTheRingGoes() {
        let outputs = RecordingOutputs()
        let pipeline = single(with(ilitekDriving) { $0.oneFinger = .alwaysDrag }, outputs)
        // The panel repeats its report while the finger rests: the ready action comes on a frame.
        for step in 0...14 { pipeline.handle(glassFrame(1.0 + Double(step) * 0.05, (0, 0.5, 0.5))) }
        XCTAssertEqual(outputs.record.circles.last?.ringed, [0], "ready, ringed")
        let ringedAt = outputs.record.circles.count

        for step in 1...5 { pipeline.handle(glassFrame(1.7 + Double(step) * 0.03, (0, 0.5 + CGFloat(step) * 0.02, 0.5))) }
        pipeline.handle(glassFrame(1.9))
        pipeline.tick(at: 3)
        XCTAssertEqual(buttons(outputs), [.down, .up], "a drag: one press, one release")
        XCTAssertGreaterThan(outputs.count(.drag), 0)
        XCTAssertEqual(outputs.record.circles.dropFirst(ringedAt).compactMap(\.ringed).filter { !$0.isEmpty }, [],
                       "the ring went with the first movement")
    }

    func testASecondFingerAfterReadyTakesTheRingDown() {
        let outputs = RecordingOutputs()
        let pipeline = single(ilitekDriving, outputs)
        for step in 0...14 { pipeline.handle(glassFrame(1.0 + Double(step) * 0.05, (0, 0.4, 0.5))) }
        XCTAssertEqual(outputs.record.circles.last?.ringed, [0])

        pipeline.handle(glassFrame(1.75, (0, 0.4, 0.5), (1, 0.6, 0.5)))
        XCTAssertEqual(outputs.record.circles.last, .show(
            display: Desk.hdmi.displayID, fingers: [0: CGPoint(x: 0.4, y: 0.5), 1: CGPoint(x: 0.6, y: 0.5)], hollow: [],
            ringed: []))
        for step in 1...10 { pipeline.handle(glassFrame(1.75 + Double(step) * 0.05, (0, 0.4, 0.5), (1, 0.6, 0.5))) }
        pipeline.handle(glassFrame(2.3))
        pipeline.tick(at: 3)
        XCTAssertEqual(outputs.count(.rightDown), 0, "lifting no longer right-clicks")
        XCTAssertEqual(outputs.count(.down), 0)
    }

    func testLongPressOffIsAClick() {
        let outputs = RecordingOutputs()
        let pipeline = single(with(ilitekDriving) { $0.options.longPress = false }, outputs)
        pipeline.handle(glassFrame(1.0, (0, 0.5, 0.5)))
        tick(pipeline, from: 1.0, to: 1.7)
        pipeline.handle(glassFrame(1.7))
        pipeline.tick(at: 2.5)
        XCTAssertEqual(buttons(outputs), [.down, .up])
        XCTAssertEqual(outputs.record.circles.compactMap(\.ringed).filter { !$0.isEmpty }, [], "never ringed")
    }

    /// Call 9: long-press stays available on a one-finger touchscreen, where it is the only
    /// right-click. The strip's survey "tap" rests 1.78 s.
    func testLongPressRightClicksOnAOneFingerOnlyTouchscreen() throws {
        let frames = try SurveyTakes.strip(take: 9)
        let driving = Desk.driving(on: Desk.strip, diagonal: 12.3, options: .oneFingerOnly(keeping: GestureOptions()))
        XCTAssertTrue(driving.options.longPress)
        let outputs = RecordingOutputs()
        let pipeline = single(driving, outputs, id: Desk.stripID)
        for frame in frames {
            pipeline.handle(frame)
            pipeline.tick(at: frame.time)
        }
        tick(pipeline, from: frames.last?.time ?? 0, to: (frames.last?.time ?? 0) + 1)
        XCTAssertEqual(buttons(outputs), [.rightDown, .rightUp])
        XCTAssertTrue(outputs.events(.rightDown).allSatisfy { Desk.strip.frame.contains($0.location) })
        let id = try XCTUnwrap(frames.first?.contacts.first?.id)
        XCTAssertGreaterThan(outputs.record.circles.filter { $0.ringed == [id] }.count, 0, "ringed while ready")
        XCTAssertEqual(outputs.record.circles.last?.ringed, [], "and not after")
    }

    func testTheRingThroughTheModelsClock() throws {
        let harness = try deskHarness(self)
        harness.send([glassFrame(100, (0, 0.5, 0.5))], from: Desk.ilitekHandle)
        XCTAssertTrue(harness.model.isTicking, "a finger is down")
        for _ in 0..<42 { harness.tick(after: 1.0 / 60) }
        XCTAssertEqual(harness.outputs.record.circles.last?.ringed, [0], "rung by the model's tick")
        harness.send([glassFrame(harness.clock + 0.01)], from: Desk.ilitekHandle)
        harness.tick(after: 1)
        XCTAssertEqual(harness.outputs.count(.rightDown), 1)
        XCTAssertEqual(harness.outputs.count(.down), 0)
        XCTAssertEqual(harness.outputs.record.circles.last?.ringed, [])
    }

    // MARK: - Rotate

    /// Two fingers 80 mm apart, turning about their midpoint by `degrees` (positive: clockwise as the
    /// display is seen, y growing downwards) in `steps` frames.
    private func twist(_ pipeline: TouchPipeline, surface: CGSize, degrees: Double, steps: Int = 20, at start: TimeInterval = 1) {
        let centre = CGPoint(x: surface.width / 2, y: surface.height / 2)
        let radius = 40.0
        for step in 0...steps {
            let angle = (Double(step) * degrees / Double(steps)) * .pi / 180
            let a = CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
            let b = CGPoint(x: centre.x - radius * cos(angle), y: centre.y - radius * sin(angle))
            pipeline.handle(glassFrame(start + Double(step) * 0.02, (0, a.x / surface.width, a.y / surface.height),
                                       (1, b.x / surface.width, b.y / surface.height)))
        }
        pipeline.handle(glassFrame(start + Double(steps) * 0.02 + 0.05))
    }

    func testATwoFingerTwistRotatesByTheTwist() {
        let outputs = RecordingOutputs()
        let pipeline = single(ilitekDriving, outputs)
        twist(pipeline, surface: ilitekDriving.surfaceSizeMM, degrees: 40)
        pipeline.tick(at: 3)

        let rotations = outputs.events.filter(\.isRotation)
        XCTAssertGreaterThan(rotations.count, 2)
        XCTAssertEqual(rotations.first?.gesturePhase, 1, "began")
        XCTAssertEqual(rotations.last?.gesturePhase, 4, "ended")
        XCTAssertEqual(rotations.filter { $0.gesturePhase == 1 }.count, 1)
        XCTAssertEqual(rotations.filter { $0.gesturePhase == 4 }.count, 1)
        // Clockwise as the display is seen: negative, as `NSEvent.rotation` reads it.
        XCTAssertEqual(rotations.map(\.rotation).reduce(0, +), -40, accuracy: 0.01, "the degrees add up to the twist")
        XCTAssertEqual(buttons(outputs), [])
        XCTAssertEqual(outputs.count(.scroll), 0)
        XCTAssertEqual(outputs.events.filter(\.isZoom), [])

        // Anticlockwise: positive.
        let other = RecordingOutputs()
        twist(single(ilitekDriving, other), surface: ilitekDriving.surfaceSizeMM, degrees: -30)
        XCTAssertEqual(other.events.filter(\.isRotation).map(\.rotation).reduce(0, +), 30, accuracy: 0.01)
    }

    func testRotateOffIsNoRotation() {
        let outputs = RecordingOutputs()
        let pipeline = single(with(ilitekDriving) { $0.options.rotate = false }, outputs)
        twist(pipeline, surface: ilitekDriving.surfaceSizeMM, degrees: 40)
        pipeline.tick(at: 3)
        XCTAssertEqual(outputs.events.filter(\.isRotation), [])
    }

    func testAMouseModeTouchscreenWithRotateStoredOnRefusesASecondContact() throws {
        var inputs = Desk.inputs
        XCTAssertTrue(inputs.settings.touchscreens[Desk.stripID]?.gestures.rotate ?? false, "stored on")
        inputs.settings.touchscreens[Desk.stripID]?.gestures.longPress = false
        let driving = try XCTUnwrap(Resolver.resolve(inputs).touchscreens.first { $0.id == Desk.stripID }?.driving)
        XCTAssertFalse(driving.options.rotate, "not in force")
        XCTAssertEqual(driving.options.fingerLimit, 1)

        let outputs = RecordingOutputs()
        twist(single(driving, outputs, id: Desk.stripID), surface: driving.surfaceSizeMM, degrees: 40)
        XCTAssertEqual(outputs.events.filter { $0.kind == .gesture }, [], "no rotation")
        XCTAssertTrue(outputs.record.circles.contains {
            if case .show(Desk.strip.displayID, let fingers, [1], _) = $0 { return fingers.count == 2 }
            return false
        }, "the second contact is refused, drawn hollow")
    }

    // MARK: - Palms

    func testAContactThatTurnsPalmCutsTheTouchShort() {
        let outputs = RecordingOutputs()
        let pipeline = single(ilitekDriving, outputs)
        // Two fingers scroll upwards; in its third frame contact 1 is no longer confident.
        pipeline.handle(frame(1.00, (0, 0.4, 0.6, nil, true), (1, 0.6, 0.6, nil, true)))
        pipeline.handle(frame(1.02, (0, 0.4, 0.57, nil, true), (1, 0.6, 0.57, nil, true)))
        XCTAssertEqual(outputs.events(.scroll).first?.scrollPhase, 1, "scrolling")
        pipeline.handle(frame(1.04, (0, 0.4, 0.54, nil, true), (1, 0.6, 0.54, nil, false)))

        let scrolls = outputs.events(.scroll)
        XCTAssertEqual(scrolls.filter { $0.scrollPhase == 1 }.count, 1)
        XCTAssertEqual(scrolls.filter { $0.scrollPhase == 4 }.count, 1, "the scroll is closed")
        XCTAssertEqual(outputs.record.arrowHidden, [true, false], "the keeper was told cancelled: the arrow is back")
        XCTAssertNil(outputs.arbiter.owner, "the pointer is free")
        let afterCancel = outputs.events.count

        // The hand's other finger carries on: nothing, drawn hollow, and it doesn't hold the pointer.
        for step in 3...8 {
            pipeline.handle(frame(1.0 + Double(step) * 0.02, (0, 0.4, 0.6 - CGFloat(step) * 0.03, nil, true),
                                  (1, 0.6, 0.6 - CGFloat(step) * 0.03, nil, false)))
            XCTAssertNil(outputs.arbiter.owner)
        }
        if case .show(_, let fingers, let hollow, _)? = outputs.record.circles.last {
            XCTAssertEqual(hollow, Set(fingers.keys))
        } else {
            XCTFail("circles")
        }
        pipeline.handle(frame(1.2, (1, 0.6, 0.36, nil, false)))
        pipeline.handle(glassFrame(1.25))
        pipeline.tick(at: 2)
        XCTAssertEqual(outputs.events.count, afterCancel, "nothing more")
        XCTAssertEqual(outputs.record.warps, [], "cancelled, not ended: the pointer is not sent home")

        // The next touch works.
        pipeline.handle(glassFrame(2.5, (0, 0.5, 0.5)))
        pipeline.handle(glassFrame(2.6))
        XCTAssertEqual(buttons(outputs), [.down, .up])
    }

    func testAPalmDuringAPressReleasesTheButtonOnce() {
        let outputs = RecordingOutputs()
        let pipeline = single(with(ilitekDriving) { $0.oneFinger = .alwaysDrag }, outputs)
        let finger = CGSize(width: 0.02, height: 0.02)        // about 10.5 × 6 mm on the 23.8″ glass
        let palm = CGSize(width: 0.06, height: 0.06)          // about 32 × 18 mm: wider than 25 mm
        pipeline.handle(frame(1.00, (0, 0.30, 0.5, finger, nil)))
        pipeline.handle(frame(1.02, (0, 0.32, 0.5, finger, nil)))
        XCTAssertEqual(buttons(outputs), [.down], "pressed")
        pipeline.handle(frame(1.04, (0, 0.34, 0.5, palm, nil)))
        XCTAssertEqual(buttons(outputs), [.down, .up], "one release, where it was")
        XCTAssertEqual(outputs.events(.up).first?.location, outputs.events(.drag).last?.location ?? outputs.events(.down).first?.location)
        XCTAssertEqual(outputs.record.arrowHidden, [true, false])

        for step in 3...6 { pipeline.handle(frame(1.0 + Double(step) * 0.02, (0, 0.30 + CGFloat(step) * 0.02, 0.5, palm, nil))) }
        pipeline.handle(glassFrame(1.2))
        pipeline.tick(at: 2)
        XCTAssertEqual(buttons(outputs), [.down, .up], "no click, nothing more")
    }

    func testContactSizesAreSharesOfTheGlassInMillimetres() {
        let surface = CGSize(width: 500, height: 300)
        XCTAssertEqual(TouchPipeline.millimetres(CGSize(width: 0.1, height: 0.2), orientation: .asFitted, surface: surface),
                       CGSize(width: 50, height: 60))
        // The glass turned a quarter: its width lies along the display's height.
        XCTAssertEqual(TouchPipeline.millimetres(CGSize(width: 0.1, height: 0.2),
                                                 orientation: Orientation(quarterTurns: 1, isFlipped: false), surface: surface),
                       CGSize(width: 30, height: 100))
        // A panel's own whole units, as today's reader passes them, are never a share: no size.
        for raw in [CGSize(width: 50, height: 40), CGSize(width: 1, height: 1), CGSize(width: 0, height: 0),
                    CGSize(width: 0.5, height: 2), CGSize(width: CGFloat.nan, height: 0.1)] {
            XCTAssertNil(TouchPipeline.millimetres(raw, orientation: .asFitted, surface: surface), "\(raw)")
        }
        XCTAssertNil(TouchPipeline.millimetres(nil, orientation: .asFitted, surface: surface))

        // So a panel that reports sizes in its own units still taps.
        let outputs = RecordingOutputs()
        let pipeline = single(ilitekDriving, outputs)
        pipeline.handle(frame(1.0, (0, 0.5, 0.5, CGSize(width: 120, height: 120), nil)))
        pipeline.handle(glassFrame(1.1))
        XCTAssertEqual(buttons(outputs), [.down, .up])
    }

    func testTenFingersLandingTogetherPostNothing() {
        let outputs = RecordingOutputs()
        let pipeline = single(ilitekDriving, outputs)
        let fingers = (0..<10).map { (id: $0, x: 0.2 + CGFloat($0) * 0.06) }
        for step in 0...10 {
            pipeline.handle(ContactFrame(time: 1.0 + Double(step) * 0.02, contacts: fingers.map {
                Contact(id: $0.id, position: CGPoint(x: $0.x - CGFloat(step) * 0.01, y: 0.5))
            }))
        }
        pipeline.handle(glassFrame(1.3))
        tick(pipeline, from: 1.3, to: 2.5)
        XCTAssertEqual(outputs.events, [])
        XCTAssertEqual(outputs.record.arrowHidden, [], "no session began")
        XCTAssertNil(outputs.arbiter.owner)
        for call in outputs.record.circles {
            if case .show(_, let shown, let hollow, _) = call { XCTAssertEqual(hollow, Set(shown.keys), "all hollow") }
        }
    }

    /// The ILITEK's survey take 3: ten fingers landing over 0.1 s, resting, then lifting. The first
    /// four count until the fifth makes a hand; then the touch is cut short.
    func testTheILITEKsWholeHandTakeClicksNothing() throws {
        let frames = try SurveyTakes.ilitek(take: 3)
        let outputs = RecordingOutputs()
        let pipeline = single(ilitekDriving, outputs)
        for frame in frames {
            pipeline.handle(frame)
            pipeline.tick(at: frame.time)
        }
        tick(pipeline, from: frames.last?.time ?? 0, to: (frames.last?.time ?? 0) + 2)
        XCTAssertEqual(buttons(outputs), [], "no click of any kind")
        XCTAssertEqual(outputs.count(.scroll), 0)
        XCTAssertEqual(outputs.events.filter { $0.kind == .gesture || $0.kind == .keyDown }, [])
        XCTAssertNil(outputs.arbiter.owner)
        XCTAssertEqual(outputs.record.warps, [], "never ended normally")
    }

    // MARK: - Edges

    func testAnEdgeMarginIgnoresATouchThatStartsNearTheEdge() {
        let driving = with(ilitekDriving) { $0.rejection = RejectionRules(palm: true, edgeMarginMM: 5) }
        let width = driving.surfaceSizeMM.width
        let outputs = RecordingOutputs()
        let pipeline = single(driving, outputs)

        pipeline.handle(glassFrame(1.0, (0, 3 / width, 0.5)))
        pipeline.handle(glassFrame(1.1))
        pipeline.tick(at: 2)
        XCTAssertEqual(outputs.events, [], "3 mm from the left edge: ignored")
        XCTAssertEqual(outputs.record.circles.first, .show(display: Desk.hdmi.displayID,
                                                           fingers: [0: CGPoint(x: 3 / width, y: 0.5)], hollow: [0]))

        pipeline.handle(glassFrame(3.0, (0, 8 / width, 0.5)))
        pipeline.handle(glassFrame(3.1))
        XCTAssertEqual(buttons(outputs), [.down, .up], "8 mm in: a tap")

        // With no margin, the touch 3 mm in taps too.
        let none = RecordingOutputs()
        let plain = single(ilitekDriving, none)
        plain.handle(glassFrame(1.0, (0, 3 / width, 0.5)))
        plain.handle(glassFrame(1.1))
        XCTAssertEqual(buttons(none), [.down, .up])
    }

    func testAChangeOfRulesAppliesFromTheNextFrame() {
        let outputs = RecordingOutputs()
        let pipeline = single(ilitekDriving, outputs)
        pipeline.update(with(ilitekDriving) { $0.rejection = RejectionRules(palm: false, edgeMarginMM: 5) })
        pipeline.handle(glassFrame(1.0, (0, 0.003, 0.5)))
        pipeline.handle(glassFrame(1.1))
        XCTAssertEqual(outputs.events, [], "the margin was in force for that touch")
    }

    // MARK: - A 0.2.0 touchscreen

    /// Every survey take, replayed as 0.2.0 drove it (every option that came after it off: long-press,
    /// rotate, the rejection rules) and with 0.3.0's defaults. A 0.2.0 touchscreen must behave as it
    /// did, but for long-press: with only long-press switched off, every take gives exactly 0.2.0's
    /// events; palm rejection at its default changes none of them; and the takes that change at all
    /// are those where a finger rests still for 0.6 s or more (the corner taps, the holds, and the
    /// strip's 1.78 s "tap").
    func testA020TouchscreenBehavesAsItDidButForLongPress() throws {
        func events(_ frames: [ContactFrame], _ driving: Driving, _ id: TouchscreenID) -> [PostedEvent] {
            let outputs = RecordingOutputs()
            let pipeline = single(driving, outputs, id: id)
            for frame in frames {
                pipeline.handle(frame)
                pipeline.tick(at: frame.time)
            }
            tick(pipeline, from: frames.last?.time ?? 0, to: (frames.last?.time ?? 0) + 3)
            return outputs.events
        }
        func as020(_ driving: Driving) -> Driving {
            with(driving) {
                $0.options.longPress = false
                $0.options.rotate = false
                $0.rejection = .none
            }
        }
        let stripDriving = Desk.driving(on: Desk.strip, diagonal: 12.3, options: .oneFingerOnly(keeping: GestureOptions()))
        var takes: [(String, TouchscreenID, Driving, [ContactFrame])] = []
        for number in SurveyTakes.ilitekTakes {
            takes.append(("ILITEK \(number)", Desk.ilitekID, ilitekDriving, try SurveyTakes.ilitek(take: number)))
        }
        for number in SurveyTakes.stripTakes {
            takes.append(("strip \(number)", Desk.stripID, stripDriving, try SurveyTakes.strip(take: number)))
        }

        var palmChanges: [String] = []
        var changes: [String] = []
        for (name, id, driving, frames) in takes where !frames.isEmpty {
            let before = events(frames, as020(driving), id)
            if events(frames, with(as020(driving)) { $0.rejection = RejectionRules() }, id) != before { palmChanges.append(name) }
            XCTAssertEqual(events(frames, with(driving) { $0.options.longPress = false }, id), before,
                           "\(name): 0.3.0's defaults with long-press off are 0.2.0")
            if events(frames, driving, id) != before { changes.append(name) }
        }
        XCTAssertEqual(palmChanges, [], "palm rejection on changes none of the takes")
        XCTAssertEqual(changes, ["ILITEK 5", "ILITEK 6", "ILITEK 7", "ILITEK 8", "ILITEK 13", "strip 2", "strip 3", "strip 6",
                                 "strip 7", "strip 8", "strip 9", "strip 13"],
                       "the corner taps, the holds and the strip's long tap: long-press")
    }
}
