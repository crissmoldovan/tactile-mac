import XCTest
@testable import TactileGestures

/// Two fingers whose line turns more than 12° while their distance holds: a rotate, in degrees,
/// positive anticlockwise as the person sees it.
final class RotateTests: XCTestCase {

    /// Turns two fingers about `centre` (mm) by `degrees` over `steps` frames, 10 ms apart, after
    /// they land together. They start on a line at `startAngle` degrees (anticlockwise from the
    /// right, as seen), `radius` mm either side of the centre. Finger 1 is the one at `startAngle`.
    private func turn(_ s: TouchScript, by degrees: Double, radius: Double = 20, centre: (Double, Double) = (200, 150),
                      startAngle: Double = 0, steps: Int = 30, spreadingBy spread: Double = 0) {
        func fingers(at angle: Double, radius r: Double) -> [(Int, Double, Double)] {
            let rad = angle * .pi / 180
            // Seen on the display, y grows downwards: anticlockwise turns move finger 1 up.
            let dx = r * cos(rad), dy = -r * sin(rad)
            return [(0, centre.0 - dx, centre.1 - dy), (1, centre.0 + dx, centre.1 + dy)]
        }
        s.frame(fingers(at: startAngle, radius: radius))
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            s.frame(fingers(at: startAngle + degrees * t, radius: radius * (1 + spread * t)))
        }
    }

    // MARK: - Recognising a rotate

    func testATurnAnticlockwiseRotatesByItsDegrees() {
        let s = TouchScript()
        turn(s, by: 30)
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move", "rotate began", "rotate changed", "rotate ended"])
        XCTAssertEqual(s.totalRotation, 30, accuracy: 1)
        XCTAssertTrue(s.rotations.allSatisfy { $0 >= 0 })
    }

    func testATurnClockwiseIsNegative() {
        let s = TouchScript()
        turn(s, by: -30)
        s.lift()
        XCTAssertEqual(s.totalRotation, -30, accuracy: 1)
    }

    /// Pinned by hand, without the helper: finger 1, right of finger 0, moves up the display (y
    /// falling) on an arc around finger 0. Seen on the display, that is anticlockwise: positive, as
    /// `NSEvent.rotation` has it.
    func testTheSignIsAnticlockwisePositiveAsSeenWithYGrowingDownwards() {
        let s = TouchScript()
        s.frame([(0, 200, 150), (1, 240, 150)])
        for step in 1...20 {
            let angle = Double(step) * 1.5 * .pi / 180     // 30° in all
            s.frame([(0, 200, 150), (1, 200 + 40 * cos(angle), 150 - 40 * sin(angle))])
        }
        s.lift()
        XCTAssertGreaterThan(s.totalRotation, 0)
        XCTAssertEqual(s.totalRotation, 30, accuracy: 1)
    }

    /// The first event carries the whole turn so far, the 12° included: the events add up to the
    /// line's turn since the second finger landed.
    func testTheFirstEventCarriesTheTurnSoFar() {
        let s = TouchScript()
        turn(s, by: 30, steps: 30)     // 1° a frame
        s.lift()
        guard let first = s.rotations.first else { return XCTFail("no rotate: \(s.names)") }
        XCTAssertGreaterThan(first, 12)
        XCTAssertLessThanOrEqual(first, 13 + 1e-9)
        XCTAssertEqual(s.rotations.last, 0)     // the end carries no turn
    }

    func testMeasuredInMillimetresOnASurfaceThatIsNotSquare() {
        let surface = CGSize(width: 1600, height: 600)
        let s = TouchScript()
        var time = s.time
        func frame(_ fingers: [(Int, Double, Double)]) {
            time += 0.01
            s.send(TouchFrame(time: time, fingers: fingers.map {
                Finger(id: $0.0, location: CGPoint(x: $0.1 / surface.width, y: $0.2 / surface.height))
            }, surfaceSize: surface))
        }
        for step in 0...30 {
            let angle = Double(step) * .pi / 180
            let dx = 40 * cos(angle), dy = -40 * sin(angle)
            frame([(0, 800 - dx, 300 - dy), (1, 800 + dx, 300 + dy)])
        }
        frame([])
        XCTAssertEqual(s.totalRotation, 30, accuracy: 1)
    }

    func testTurningAroundOneStillFingerRotates() {
        let s = TouchScript()
        s.frame([(0, 200, 150), (1, 240, 150)])
        for step in 1...30 {
            let angle = -Double(step) * .pi / 180            // 30° clockwise, around finger 0
            s.frame([(0, 200, 150), (1, 200 + 40 * cos(angle), 150 - 40 * sin(angle))])
        }
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move", "rotate began", "rotate changed", "rotate ended"])
        XCTAssertEqual(s.totalRotation, -30, accuracy: 1)
    }

    func testTheTurnCountsFromTheLineWhenTheSecondFingerLanded() {
        let s = TouchScript()
        s.frame([(0, 200, 150)])
        s.frame([(0, 200, 152.5)])                           // drifts 2.5 mm, within the slop
        // The second finger lands level with where the first is now, not where it landed.
        s.frame([(0, 200, 152.5), (1, 240, 152.5)])
        for step in 1...30 {
            let angle = Double(step) * .pi / 180
            let dx = 20 * cos(angle), dy = -20 * sin(angle)
            s.frame([(0, 220 - dx, 152.5 - dy), (1, 220 + dx, 152.5 + dy)])
        }
        s.lift()
        XCTAssertEqual(s.totalRotation, 30, accuracy: 0.01)
    }

    func testTheMovePointerGoesBetweenTheFingersWhenItBegins() {
        let s = TouchScript()
        turn(s, by: 30, centre: (200, 150))
        let began = s.actions.firstIndex { if case .rotate(_, .began) = $0 { return true } else { return false } }
        guard let began, began > 0, case .movePointer(let point) = s.actions[began - 1] else {
            return XCTFail("no pointer move before the rotate began: \(s.names)")
        }
        XCTAssertEqual(point.x, TouchScript.at(200, 150).x, accuracy: 1e-9)
        XCTAssertEqual(point.y, TouchScript.at(200, 150).y, accuracy: 1e-9)
    }

    /// The line's direction is followed past half a turn, so a long turn adds up whole.
    func testATurnPastHalfACircleAddsUp() {
        let s = TouchScript()
        turn(s, by: 200, steps: 40)
        s.lift()
        XCTAssertEqual(s.totalRotation, 200, accuracy: 1)
    }

    // MARK: - Twisting about a resting finger

    /// Turns finger 1 about finger 0, which rests, `degrees` over 1° steps, 40 mm out.
    private func twistAboutFingerZero(_ s: TouchScript, by degrees: Int) {
        s.frame([(0, 200, 150), (1, 240, 150)])
        for step in 1...degrees {
            let angle = Double(step) * .pi / 180
            s.frame([(0, 200, 150), (1, 200 + 40 * cos(angle), 150 - 40 * sin(angle))])
        }
    }

    func testATwistOfTwentyDegreesAboutARestingFingerIsNoRotate() {
        let s = TouchScript()
        twistAboutFingerZero(s, by: 20)
        s.lift()
        s.wait(1)
        XCTAssertEqual(s.names, ["session began", "move", "session ended"])
    }

    func testATwistOfThirtyDegreesAboutARestingFingerRotatesFromTwentyFive() {
        let s = TouchScript()
        twistAboutFingerZero(s, by: 30)
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move", "rotate began", "rotate changed", "rotate ended"])
        XCTAssertEqual(s.totalRotation, 30, accuracy: 1)
        guard let first = s.rotations.first else { return XCTFail("no rotate: \(s.names)") }
        XCTAssertGreaterThan(first, 25)
        XCTAssertLessThanOrEqual(first, 26 + 1e-9)
    }

    func testATwistAboutTheMidpointStillRotatesAtTwelveDegrees() {
        let s = TouchScript()
        turn(s, by: 30, radius: 20, steps: 30)     // 1° a frame; each finger has moved 4.2 mm at 12°
        s.lift()
        guard let first = s.rotations.first else { return XCTFail("no rotate: \(s.names)") }
        XCTAssertGreaterThan(first, 12)
        XCTAssertLessThanOrEqual(first, 13 + 1e-9)
        XCTAssertEqual(s.totalRotation, 30, accuracy: 1)
    }

    /// Decision of the review: closer than 30 mm, scrolling fingers side by side, a twist about a
    /// resting finger doesn't rotate however far it turns. Going round each other still does.
    func testCloserThanThirtyMillimetresATwistAboutARestingFingerIsNoRotate() {
        let s = TouchScript()
        s.frame([(0, 200, 150), (1, 225, 150)])
        for step in 1...60 {
            let angle = Double(step) * .pi / 180
            s.frame([(0, 200, 150), (1, 200 + 25 * cos(angle), 150 - 25 * sin(angle))])
        }
        s.lift()
        s.wait(1)
        XCTAssertEqual(s.names, ["session began", "move", "session ended"])
    }

    /// The minimum span exactly: fingers landing 29.9 mm apart never rotate about the resting one;
    /// 30.0 mm apart, they rotate from 25°.
    func testATwistAboutARestingFingerNeedsTheFingersToLandThirtyMillimetresApart() {
        func twist(apart span: Double) -> TouchScript {
            let s = TouchScript()
            s.frame([(0, 200, 150), (1, 200 + span, 150)])
            for step in 1...40 {
                let angle = Double(step) * .pi / 180
                s.frame([(0, 200, 150), (1, 200 + span * cos(angle), 150 - span * sin(angle))])
            }
            s.lift()
            return s
        }
        XCTAssertEqual(twist(apart: 29.9).names, ["session began", "move"])
        let wide = twist(apart: 30)
        XCTAssertEqual(wide.names, ["session began", "move", "rotate began", "rotate changed", "rotate ended"])
        guard let first = wide.rotations.first else { return XCTFail("no rotate") }
        XCTAssertGreaterThan(first, 25)
        XCTAssertLessThanOrEqual(first, 26 + 1e-9)
        XCTAssertEqual(wide.totalRotation, 40, accuracy: 1)
    }

    func testCloserThanThirtyMillimetresFingersGoingRoundEachOtherStillRotate() {
        let s = TouchScript()
        turn(s, by: 30, radius: 10, steps: 30)     // 20 mm apart; each finger has moved 3 mm at 17.3°
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move", "rotate began", "rotate changed", "rotate ended"])
        XCTAssertEqual(s.totalRotation, 30, accuracy: 1)
    }

    // MARK: - A scroll that starts with one finger

    /// Review finding 1: fingers 18 mm apart, their line tilted 15° from square to the scroll. The
    /// left finger leads 8 mm down at 20 ms a millimetre: the gap stays within 2% while the line
    /// turns 25.9°, as a twist about the resting finger would. Then both go on 30 mm together.
    func testATiltedScrollStartedByOneFingerIsAScroll() {
        let s = TouchScript()
        let tilt = 15 * Double.pi / 180
        let a = (200.0, 150.0), b = (200 + 18 * cos(tilt), 150 + 18 * sin(tilt))
        s.frame([(0, a.0, a.1), (1, b.0, b.1)])
        s.move([(0, a, (a.0, a.1 + 8)), (1, b, b)], steps: 8, every: 0.02)
        s.move([(0, (a.0, a.1 + 8), (a.0, a.1 + 38)), (1, b, (b.0, b.1 + 30))], steps: 30, every: 0.02)
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move", "scroll began", "scroll changed", "scroll ended"])
    }

    /// Leads of 7–14 mm, the line tilted ±15° and ±30° from square to the scroll, fingers 15–25 mm
    /// apart, either finger leading: never a rotate. Where the lead keeps the gap within 8% of
    /// where it started it is exactly a scroll; where it doesn't, it is exactly a pinch, by the
    /// pinch rule, which this work doesn't change.
    func testTiltedScrollsStartedByOneFingerAreNeverARotate() {
        let scroll = ["session began", "move", "scroll began", "scroll changed", "scroll ended"]
        let pinch = ["session began", "move", "pinch began", "pinch changed", "pinch ended"]
        var scrolls = 0
        for spacing in [15.0, 18, 20, 25] {
            for lead in [7.0, 8, 10, 12, 14] {
                for tiltDegrees in [-30.0, -15, 15, 30] {
                    for leader in [0, 1] {
                        let tilt = tiltDegrees * .pi / 180
                        let a = (200.0, 150.0), b = (200 + spacing * cos(tilt), 150 + spacing * sin(tilt))
                        let s = TouchScript()
                        s.frame([(0, a.0, a.1), (1, b.0, b.1)])
                        var gapHolds = true
                        let steps = Int(lead)
                        for step in 1...steps {
                            let down = lead * Double(step) / Double(steps)
                            let pa = leader == 0 ? (a.0, a.1 + down) : a, pb = leader == 1 ? (b.0, b.1 + down) : b
                            s.frame(after: 0.02, [(0, pa.0, pa.1), (1, pb.0, pb.1)])
                            let gap = ((pb.0 - pa.0) * (pb.0 - pa.0) + (pb.1 - pa.1) * (pb.1 - pa.1)).squareRoot()
                            if down >= 3, abs(gap / spacing - 1) > 0.08 { gapHolds = false }
                        }
                        let pa = leader == 0 ? (a.0, a.1 + lead) : a, pb = leader == 1 ? (b.0, b.1 + lead) : b
                        for step in 1...30 {
                            let more = Double(step)
                            s.frame(after: 0.02, [(0, pa.0, pa.1 + more), (1, pb.0, pb.1 + more)])
                        }
                        s.lift()
                        let label = "\(spacing) mm apart, lead \(lead) mm, tilt \(tiltDegrees)°, finger \(leader) leading"
                        XCTAssertEqual(s.names, gapHolds ? scroll : pinch, label)
                        if gapHolds { scrolls += 1 }
                    }
                }
            }
        }
        // 34 of the 160 keep the gap and scroll. At 43c197e, before the minimum span, this grid gave
        // 12 scrolls, 28 rotates and 120 pinches: 22 of the rotates are scrolls now, and the other
        // 6 lead on far enough to change the gap more than 8%, so are among today's 126 pinches.
        XCTAssertEqual(scrolls, 34)
    }

    /// The risk the rule was changed for: fingers 20 mm apart side by side, one moves 6 mm down
    /// before the other starts (the line has turned 16.7°), then both go on down together 20 mm.
    func testAScrollStartedByOneFingerSideBySideIsAScroll() {
        let s = TouchScript()
        s.frame([(0, 100, 100), (1, 120, 100)])
        s.move([(0, (100, 100), (100, 106)), (1, (120, 100), (120, 100))], steps: 6, every: 0.02)
        s.move([(0, (100, 106), (100, 126)), (1, (120, 100), (120, 120))], steps: 20, every: 0.02)
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move", "scroll began", "scroll changed", "scroll ended"])
    }

    /// The same, turned through 90°: one finger above the other, the scroll sideways. (Stacked
    /// fingers scrolling down lag along their line, which changes their distance, not its turn: a
    /// pinch once the lag passes 8%, before and after this rule.)
    func testAScrollStartedByOneFingerOneAboveTheOtherIsAScroll() {
        let s = TouchScript()
        s.frame([(0, 100, 100), (1, 100, 120)])
        s.move([(0, (100, 100), (106, 100)), (1, (100, 120), (100, 120))], steps: 6, every: 0.02)
        s.move([(0, (106, 100), (126, 100)), (1, (100, 120), (120, 120))], steps: 20, every: 0.02)
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move", "scroll began", "scroll changed", "scroll ended"])
    }

    /// Both fingers have moved 3 mm and the line has turned 15°, but their directions are 79° apart:
    /// they are not going round each other, and neither rests, so the turn decides nothing.
    func testFingersNotGoingRoundEachOtherDoNotRotateAtTwelveDegrees() {
        let s = TouchScript()
        s.frame([(0, 100, 150), (1, 140, 150)])
        s.move([(0, (100, 150), (104, 150)), (1, (140, 150), (142, 140))], steps: 10)
        s.lift()
        XCTAssertFalse(s.names.contains { $0.hasPrefix("rotate") }, "\(s.names)")
    }

    // MARK: - Not a rotate

    func testATurnOfEightDegreesIsNoRotate() {
        let s = TouchScript()
        turn(s, by: 8, radius: 50, steps: 8)      // each finger moves 7 mm: past the slop, not 12°
        s.lift()
        s.wait(1)
        XCTAssertEqual(s.names, ["session began", "move", "session ended"])
    }

    func testPinchWinsWhenTheDistanceCrossesEightPercentFirst() {
        let s = TouchScript()
        turn(s, by: 20, steps: 30, spreadingBy: 0.3)     // 8% apart after about 5°
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move", "pinch began", "pinch changed", "pinch ended"])
    }

    /// Decision: when the distance and the line cross their thresholds in the same frame, it is a
    /// pinch, as when the distance crosses first.
    func testPinchWinsWhenBothCrossInTheSameFrame() {
        let s = TouchScript()
        turn(s, by: 20, steps: 1, spreadingBy: 0.2)
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move", "pinch began", "pinch ended"])   // one frame of movement
    }

    /// Review focus 2: two fingers scrolling down together while their line turns 5°.
    func testAScrollWhoseLineTurnsFiveDegreesIsAScroll() {
        let s = TouchScript()
        s.frame([(0, 100, 100), (1, 140, 100)])
        s.move([(0, (100, 100), (100, 140)), (1, (140, 100), (140, 140 + 40 * tan(5 * Double.pi / 180)))],
               steps: 40, every: 0.02)
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move", "scroll began", "scroll changed", "scroll ended"])
    }

    /// Review focus 2, further: fingers sweeping along an arc together, their line turning 40° in
    /// all. They move the same way from the start, so it is a scroll, and stays one.
    func testFingersSweepingAnArcTogetherScroll() {
        let s = TouchScript()
        // Both fingers on a line through a centre 150 mm away, turning about it.
        func fingers(_ degrees: Double) -> [(Int, Double, Double)] {
            let a = degrees * .pi / 180
            return [(0, 100 + 150 * sin(a), 250 - 150 * cos(a)), (1, 100 + 190 * sin(a), 250 - 190 * cos(a))]
        }
        for step in 0...40 { s.frame(after: 0.02, fingers(Double(step))) }
        s.lift()
        // About 150 mm/s at lift (148, the fingers' midpoint over the last 0.08 s): a flick, so it
        // coasts.
        XCTAssertEqual(s.names, ["session began", "move", "scroll began", "scroll changed", "scroll ended",
                                 "momentum began"])
    }

    // MARK: - Locked

    func testARotateStaysARotateWhenTheFingersSpread() {
        let s = TouchScript()
        turn(s, by: 20, steps: 20)
        s.move([(0, (181.206, 156.840), (160, 170)), (1, (218.794, 143.160), (240, 130))], steps: 10)
        s.lift()
        XCTAssertFalse(s.names.contains { $0.hasPrefix("pinch") })
        XCTAssertEqual(s.names, ["session began", "move", "rotate began", "rotate changed", "rotate ended"])
    }

    func testARotateStaysARotateWhenTheFingersMoveTogether() {
        let s = TouchScript()
        turn(s, by: 20, steps: 20)
        s.move([(0, (181.206, 156.840), (181.206, 196.840)), (1, (218.794, 143.160), (218.794, 183.160))], steps: 20)
        s.lift()
        XCTAssertFalse(s.names.contains { $0.hasPrefix("scroll") })
        XCTAssertEqual(s.totalRotation, 20, accuracy: 0.01)
    }

    func testTheRotateEndsWhenAFingerLifts() {
        let s = TouchScript()
        turn(s, by: 30)
        s.frame([(1, 220, 140)])                         // finger 0 lifts; finger 1 carries on
        s.move([(1, (220, 140), (200, 120))], steps: 10)
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move", "rotate began", "rotate changed", "rotate ended"])
    }

    // MARK: - Options and cancel

    func testWithRotateOffTheSameTurnIsNoRotate() {
        var options = GestureOptions()
        options.rotate = false
        let s = TouchScript(options: options)
        turn(s, by: 30)
        s.lift()
        XCTAssertFalse(s.names.contains { $0.hasPrefix("rotate") })
        XCTAssertEqual(s.names, ["session began", "move"])   // not a pinch or a scroll either
    }

    /// A turn, then a spread: a rotate with rotate on (locked before the spread), a pinch with it
    /// off, judged as if rotate didn't exist.
    func testWithRotateOffATurnThenASpreadIsAPinch() {
        func run(rotate: Bool) -> [String] {
            var options = GestureOptions()
            options.rotate = rotate
            let s = TouchScript(options: options)
            turn(s, by: 20, steps: 20)
            s.move([(0, (181.206, 156.840), (160, 170)), (1, (218.794, 143.160), (240, 130))], steps: 10)
            s.lift()
            return s.names
        }
        XCTAssertEqual(run(rotate: true), ["session began", "move", "rotate began", "rotate changed", "rotate ended"])
        XCTAssertEqual(run(rotate: false), ["session began", "move", "pinch began", "pinch changed", "pinch ended"])
    }

    /// Restated for the rule as ruled, which asks for the distance to have changed less than 8%
    /// whether pinch is on or off: with pinch off, a turn whose fingers spread 50% is nothing (it
    /// was a rotate under the first rule); one whose fingers spread 5% is a rotate.
    func testWithPinchOffTheDistanceMustStillHold() {
        func names(spreadingBy spread: Double) -> [String] {
            var options = GestureOptions()
            options.pinch = false
            let s = TouchScript(options: options)
            turn(s, by: 30, steps: 30, spreadingBy: spread)
            s.lift()
            return s.names
        }
        XCTAssertEqual(names(spreadingBy: 0.5), ["session began", "move"])
        XCTAssertEqual(names(spreadingBy: 0.05), ["session began", "move", "rotate began", "rotate changed",
                                                  "rotate ended"])
    }

    func testCancelMidRotateEndsIt() {
        let s = TouchScript()
        turn(s, by: 30)
        s.cancel()
        XCTAssertEqual(s.names.suffix(2), ["rotate ended", "session cancelled"])
        XCTAssertFalse(s.engine.needsTicks)
    }

    func testATwoFingerTapIsStillARightClick() {
        let s = TouchScript()
        s.frame([(0, 100, 100), (1, 140, 100)])
        s.lift(after: 0.1)
        XCTAssertEqual(s.names, ["session began", "move", "right-click"])
    }
}
