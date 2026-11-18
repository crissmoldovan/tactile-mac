// The corners step's limits, in millimetres on the glass: how far a tap may be from its fitted
// place, how far the taps may spread, how far a tap's finger may move; where the glass's size
// comes from; and noisy taps across every orientation and rotation.

import CoreGraphics
import Foundation
import TactileApp
import TactileReading
import TactileScreens
import XCTest

private typealias Desk = SetUpDesk
private typealias Driver = FlowDriver

/// "HDMI" as it really is: 23.8″ at 16:9.
private let largeGlass = CGSize(width: 527, height: 296)
/// "12.3FHD" as it reports itself.
private let stripGlass = CGSize(width: 240, height: 90)

/// `x` and `y` millimetres as shares of `glass`, on each of its own axes.
private func mm(_ x: Double, _ y: Double, on glass: CGSize) -> CGVector {
    CGVector(dx: x / glass.width, dy: y / glass.height)
}

final class SetUpFlowMillimetreTests: XCTestCase {

    /// The four corner taps on `display`'s glass fitted `orientation`, whole, with tap `wild` moved
    /// by `offset` (a share of the glass on each of its own axes); and whether `Calibration.fit`
    /// alone would take them, on a display that isn't turned or mirroring, whose targets are on
    /// its own picture where they are shown.
    private func taps(
        on display: DisplayFacts, orientation: Orientation, wild: Int, offset: CGVector
    ) -> (taps: [CGPoint], fitAlone: Bool) {
        var taps = Desk.cornerTaps(on: display, orientation: orientation)
        taps[wild].x += offset.dx
        taps[wild].y += offset.dy
        let fitTaps = zip(Calibration.targets, taps).map { CalibrationTap(target: $0, glass: $1) }
        if case .success = Calibration.fit(fitTaps) { return (taps, true) }
        return (taps, false)
    }

    /// The step a calibration of `display` ends in, with those taps, by a touchscreen that reports
    /// `glass`.
    private func step(
        on display: DisplayFacts = Desk.hdmi, glass: CGSize?, orientation: Orientation = .asFitted,
        diagonal: Double? = nil, wild: Int = 2, offset: CGVector, file: StaticString = #filePath, line: UInt = #line
    ) throws -> SetUpStep {
        var driver = try Driver(
            Desk.start(.calibrate, candidates: [display], all: Desk.all(with: display), glass: glass,
                       current: Desk.pairing(display), diagonal: diagonal),
            file: file, line: line)
        driver.taps(taps(on: display, orientation: orientation, wild: wild, offset: offset).taps, from: 1)
        return driver.step
    }

    // MARK: - One wild tap

    func testOneWildTapIsRefusedOnTheLargeGlass() throws {
        let refused = firstTarget(on: Desk.hdmi, problem: .tapsDidNotFit)
        for offset in [mm(20, 0, on: largeGlass), mm(0, 20, on: largeGlass), mm(-14.2, 14.2, on: largeGlass)] {
            XCTAssertTrue(taps(on: Desk.hdmi, orientation: .asFitted, wild: 2, offset: offset).fitAlone, "\(offset)")
            XCTAssertEqual(try step(glass: largeGlass, offset: offset), refused, "20 mm off: \(offset)")
        }
        for offset in [mm(5, 0, on: largeGlass), mm(0, -5, on: largeGlass), mm(3.5, 3.5, on: largeGlass)] {
            XCTAssertEqual(try step(glass: largeGlass, offset: offset), .check(display: 3), "5 mm off: \(offset)")
        }
    }

    func testOneWildTapIsRefusedOnTheStripsGlass() throws {
        let refused = firstTarget(on: Desk.strip, problem: .tapsDidNotFit)
        let across = mm(20, 0, on: stripGlass)
        XCTAssertTrue(taps(on: Desk.strip, orientation: .asFitted, wild: 2, offset: across).fitAlone)
        XCTAssertEqual(try step(on: Desk.strip, glass: stripGlass, offset: across), refused, "20 mm across")
        XCTAssertEqual(
            try step(on: Desk.strip, glass: stripGlass, offset: mm(0, 20, on: stripGlass)), refused, "20 mm down")
        for offset in [mm(5, 0, on: stripGlass), mm(0, 5, on: stripGlass)] {
            XCTAssertEqual(try step(on: Desk.strip, glass: stripGlass, offset: offset), .check(display: 4), "\(offset)")
        }
    }

    func testTapsSpreadTooFarAreRefusedThoughEachIsNearItsPlace() throws {
        // Each tap d across, the two on each side of the picture in opposite directions: the fit
        // stays where it was, and every tap lies d from its fitted place.
        func spread(_ d: Double) throws -> SetUpStep {
            let signs: [Double] = [1, 1, -1, -1]
            let taps = zip(Desk.cornerTaps(on: Desk.hdmi), signs).map { tap, sign in
                CGPoint(x: tap.x + sign * d / largeGlass.width, y: tap.y)
            }
            var driver = try Driver(
                Desk.start(.calibrate, candidates: [Desk.hdmi], glass: largeGlass, current: Desk.pairing(Desk.hdmi)))
            driver.taps(taps, from: 1)
            return driver.step
        }
        XCTAssertEqual(try spread(6.5), firstTarget(on: Desk.hdmi, problem: .tapsDidNotFit), "each 6.5 mm out")
        XCTAssertEqual(try spread(5.5), .check(display: 3), "each 5.5 mm out")
    }

    func testNoSingleTapMoreThan16MillimetresOffIsTaken() throws {
        // A tap off by d, the other three true, lies d / 2 from its fitted place: 8 mm is 16 mm off.
        for (display, glass) in [(Desk.hdmi, largeGlass), (Desk.strip, stripGlass)] {
            for wild in 0..<4 {
                for k in 0..<24 {
                    let angle = Double(k) * .pi / 12
                    let offset = mm(16.2 * cos(angle), 16.2 * sin(angle), on: glass)
                    XCTAssertEqual(
                        try step(on: display, glass: glass, wild: wild, offset: offset),
                        firstTarget(on: display, problem: .tapsDidNotFit), "\(glass), tap \(wild), \(k * 15)°")
                }
                XCTAssertEqual(
                    try step(on: display, glass: glass, wild: wild, offset: mm(15.8, 0, on: glass)),
                    .check(display: display.displayID), "\(glass), tap \(wild), 15.8 mm across")
            }
        }
    }

    // MARK: - Where the glass's size comes from

    func testWithNoReportedSizeTheDisplaysSizeIsUsed() throws {
        // "HDMI" reports 602 × 329 mm.
        let refused = firstTarget(on: Desk.hdmi, problem: .tapsDidNotFit)
        XCTAssertEqual(try step(glass: nil, offset: CGVector(dx: 20.0 / 602, dy: 0)), refused, "20 mm across")
        XCTAssertEqual(try step(glass: nil, offset: CGVector(dx: 5.0 / 602, dy: 0)), .check(display: 3), "5 mm across")

        // Fitted a quarter turn round: the glass's own x axis runs down the picture, 329 mm.
        let turnedFit = Orientation(quarterTurns: 1, isFlipped: false)
        XCTAssertEqual(
            try step(glass: nil, orientation: turnedFit, offset: CGVector(dx: 12.0 / 329, dy: 0)), .check(display: 3),
            "12 mm along the glass's x: 6 mm from its place")
        XCTAssertEqual(
            try step(glass: nil, orientation: turnedFit, offset: CGVector(dx: 18.0 / 329, dy: 0)), refused,
            "18 mm along the glass's x: 9 mm from its place")

        // Turned in macOS: its frame and reported size turn, the glass on it doesn't.
        XCTAssertEqual(
            try step(on: Desk.hdmiTurned, glass: nil, offset: CGVector(dx: 0, dy: 12.0 / 329)), .check(display: 3),
            "12 mm along the glass's y")
        XCTAssertEqual(
            try step(on: Desk.hdmiTurned, glass: nil, offset: CGVector(dx: 0, dy: 18.0 / 329)), refused,
            "18 mm along the glass's y")

        // Reporting no size, with a diagonal confirmed for it: a 23.8″ picture of its shape.
        let silent = changed(Desk.hdmi) { $0.sizeMM = .zero }
        XCTAssertEqual(try step(on: silent, glass: nil, diagonal: 23.8, offset: mm(20, 0, on: largeGlass)), refused)
        XCTAssertEqual(
            try step(on: silent, glass: nil, diagonal: 23.8, offset: mm(5, 0, on: largeGlass)), .check(display: 3))
    }

    func testAPictureCoveringPartOfTheGlassMakesTheGlassLarger() throws {
        // No report: "HDMI"'s 602 mm picture covers 0.6 of the glass's width, so the glass is
        // 1003 mm wide, and a tap's shares of it are that many millimetres.
        let rect = CGRect(x: 0.2, y: 0, width: 0.6, height: 1)
        func step(offBy mm: Double) throws -> SetUpStep {
            var taps = Desk.cornerTaps(on: Desk.hdmi, rect: rect)
            taps[2].x -= mm / (602 / 0.6)
            var driver = try Driver(
                Desk.start(.calibrate, candidates: [Desk.hdmi], glass: nil, current: Desk.pairing(Desk.hdmi)))
            driver.taps(taps, from: 1)
            return driver.step
        }
        XCTAssertEqual(try step(offBy: 14), .check(display: 3), "14 mm off: 7 mm from its place")
        XCTAssertEqual(try step(offBy: 18), firstTarget(on: Desk.hdmi, problem: .tapsDidNotFit), "18 mm off: 9 mm")
    }

    func testAnImplausibleReportFallsBackToTheDisplaysSize() throws {
        // A touchscreen that reports ten times its glass (one wrong unit exponent in its descriptor),
        // or the largest size a number can hold, 1.8e308 mm. Honest taps, each landing up to 2 mm
        // out and rolling 1 mm while down, all complete on the display's size, as they did before
        // the limits were millimetres.
        var generator = Seeded(state: 1937)
        let real = largeGlass  // "HDMI"'s glass; the display reports 602 × 329 mm
        let largest = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        for report in [CGSize(width: 5270, height: 2960), largest] {
            for orientation in Orientation.allCases {
                for _ in 0..<5 {
                    // In the glass's own axes, which a quarter turn of the fit lays across the picture.
                    let turned = orientation.quarterTurns % 2 == 1
                    let glass = turned ? CGSize(width: real.height, height: real.width) : real
                    let reported = turned ? CGSize(width: report.height, height: report.width) : report
                    var driver = try Driver(
                        Desk.start(
                            .calibrate, candidates: [Desk.hdmi], glass: reported, current: Desk.pairing(Desk.hdmi)))
                    for (i, target) in Desk.cornerTaps(on: Desk.hdmi, orientation: orientation).enumerated() {
                        let landing = CGPoint(
                            x: target.x + .random(in: -2...2, using: &generator) / glass.width,
                            y: target.y + .random(in: -2...2, using: &generator) / glass.height)
                        let angle = Double.random(in: 0..<(2 * .pi), using: &generator)
                        let rolled = CGPoint(
                            x: landing.x + cos(angle) / glass.width, y: landing.y + sin(angle) / glass.height)
                        let t = 1 + Double(i)
                        driver.wait(until: t)
                        driver.finger(t, at: landing)
                        driver.finger(t + 0.05, at: rolled)
                        driver.lift(t + 0.1)
                    }
                    XCTAssertEqual(driver.step, .check(display: 3), "report \(report), \(orientation)")
                    XCTAssertEqual(driver.flow.checkMapping?.orientation, orientation, "report \(report)")
                }
            }
        }
    }

    func testAnImplausibleReportLeavesTheDisplaysSizeToJudgeTheFit() throws {
        // Ten times "HDMI"'s glass: the 602 × 329 mm it reports judges the round instead.
        let tenTimes = CGSize(width: 5270, height: 2960)
        let refused = firstTarget(on: Desk.hdmi, problem: .tapsDidNotFit)
        XCTAssertEqual(try step(glass: tenTimes, offset: CGVector(dx: 20.0 / 602, dy: 0)), refused, "20 mm across")
        XCTAssertEqual(try step(glass: tenTimes, offset: CGVector(dx: 5.0 / 602, dy: 0)), .check(display: 3))
    }

    func testWithNoReportATapsTravelIsJudgedOnTheDisplaysSizeEitherWayRound() throws {
        // Before the fit, which side of "HDMI"'s 602 × 329 mm lies along the glass's x isn't known:
        // a tap may move 5 mm on the shorter reading. 0.014 of the glass is 4.6 mm of 329; 0.016 is 5.3.
        var driver = try Driver(
            Desk.start(.calibrate, candidates: [Desk.hdmi], glass: nil, current: Desk.pairing(Desk.hdmi)))
        let moves: [(CGVector, SetUpProblem?)] = [
            (CGVector(dx: 0.014, dy: 0), nil), (CGVector(dx: 0, dy: 0.014), nil),
            (CGVector(dx: 0.016, dy: 0), .moved), (CGVector(dx: 0, dy: -0.016), .moved),
        ]
        var index = 0
        for (i, (move, problem)) in moves.enumerated() {
            let q = Desk.cornerTaps(on: Desk.hdmi)[index]
            let t = 1 + Double(i)
            driver.finger(t, at: q)
            driver.finger(t + 0.05, at: CGPoint(x: q.x + move.dx, y: q.y + move.dy))
            driver.lift(t + 0.1)
            if problem == nil { index += 1 }
            XCTAssertEqual(
                driver.step,
                .corners(display: 3, target: Calibration.targets[index], index: index, problem: problem), "\(move)")
        }
    }

    func testWithNoSizeAtAllTheLimitsAreSharesOfTheGlass() throws {
        // Neither the touchscreen nor the display reports a size, and none is confirmed: only
        // `Calibration`'s own limit, as before. 6% of the glass would be 32 mm on a 23.8″ glass.
        let silent = changed(Desk.hdmi) { $0.sizeMM = .zero }
        XCTAssertEqual(try step(on: silent, glass: nil, offset: CGVector(dx: 0.06, dy: 0)), .check(display: 3))

        // And a tap may move 3% of the glass.
        let p = Desk.cornerTaps(on: silent)[0]
        var driver = try Driver(
            Desk.start(.calibrate, candidates: [silent], all: Desk.all(with: silent), glass: nil,
                       current: Desk.pairing(silent)))
        driver.finger(1.0, at: p)
        driver.finger(1.05, at: CGPoint(x: p.x + 0.029, y: p.y))
        driver.lift(1.1)
        XCTAssertEqual(driver.step, .corners(display: 3, target: Calibration.targets[1], index: 1, problem: nil))
        let q = Desk.cornerTaps(on: silent)[1]
        driver.finger(2.0, at: q)
        driver.finger(2.05, at: CGPoint(x: q.x, y: q.y + 0.031))
        driver.lift(2.1)
        XCTAssertEqual(driver.step, .corners(display: 3, target: Calibration.targets[1], index: 1, problem: .moved))
    }

    // MARK: - How far a tap may move

    func testATapMayMoveFiveMillimetres() throws {
        for (display, glass) in [(Desk.hdmi, Desk.ilitekGlass), (Desk.strip, Desk.stripGlass)] {
            let taps = Desk.cornerTaps(on: display)
            var driver = try Driver(
                Desk.start(.calibrate, candidates: [display], glass: glass, current: Desk.pairing(display)))
            let moves: [(CGVector, SetUpProblem?)] = [
                (mm(4.9, 0, on: glass), nil), (mm(0, 4.9, on: glass), nil), (mm(3.4, 3.4, on: glass), nil),
                (mm(-5.1, 0, on: glass), .moved), (mm(0, -5.1, on: glass), .moved), (mm(3.7, 3.7, on: glass), .moved),
            ]
            var index = 0
            for (i, (move, problem)) in moves.enumerated() {
                let p = taps[index]
                let t = 1 + Double(i)
                driver.finger(t, at: p)
                driver.finger(t + 0.05, at: CGPoint(x: p.x + move.dx, y: p.y + move.dy))
                driver.finger(t + 0.1, at: p)
                driver.lift(t + 0.15)
                if problem == nil { index += 1 }
                XCTAssertEqual(
                    driver.step,
                    .corners(
                        display: display.displayID, target: Calibration.targets[index], index: index, problem: problem),
                    "\(glass): \(move)")
            }
        }
    }

    // MARK: - Noise

    func testNoisyTapsAcrossEveryOrientationAndRotation() throws {
        // Every tap up to 1% of the glass out on each axis, as a hand is: the right orientation every
        // time, and touches landing within 1.5% of the picture of where they should.
        var generator = Seeded(state: 2611)
        let rect = CGRect(x: 0.02, y: 0.04, width: 0.96, height: 0.92)
        for (base, glass) in [(Desk.hdmi, Desk.ilitekGlass), (Desk.strip, Desk.stripGlass)] {
            for degrees in [0, 90, 180, 270] {
                let display = Desk.turned(base, by: degrees)
                for orientation in Orientation.allCases {
                    for _ in 0..<5 {
                        let label = "\(base.name) at \(degrees)°, \(orientation)"
                        let noisy = Desk.cornerTaps(on: display, orientation: orientation, rect: rect).map {
                            CGPoint(
                                x: $0.x + .random(in: -0.01...0.01, using: &generator),
                                y: $0.y + .random(in: -0.01...0.01, using: &generator))
                        }
                        var driver = try Driver(
                            Desk.start(.calibrate, candidates: [display], all: Desk.all(with: display), glass: glass,
                                       current: Desk.pairing(display)))
                        driver.taps(noisy, from: 1)
                        let mapping = try XCTUnwrap(driver.flow.checkMapping, "refused: \(label)")
                        XCTAssertEqual(mapping.orientation, orientation, label)
                        for x in stride(from: 0.0, through: 1.0, by: 0.125) {
                            for y in stride(from: 0.0, through: 1.0, by: 0.125) {
                                let p = CGPoint(x: x, y: y)
                                let truth = Desk.glassPoint(
                                    touching: p, on: display, orientation: orientation, rect: rect)
                                let landed = mapping.displayPoint(forGlass: truth)
                                let error = max(abs(landed.x - p.x), abs(landed.y - p.y))
                                XCTAssertLessThanOrEqual(error, 0.015, "\(label) \(p)")
                            }
                        }
                    }
                }
            }
        }
    }
}
