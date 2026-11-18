// What each corners round measured, kept for tuning the corners' limits from real taps, and the
// line the model logs it as.

import CoreGraphics
import Foundation
import TactileApp
import TactileReading
import TactileScreens
import XCTest

private typealias Desk = SetUpDesk
private typealias Driver = FlowDriver
private typealias Report = SetUpFlow.CornersReport

/// The ILITEK's glass, which it reports: 476 × 268 mm, plausible on "HDMI".
private let glass = Desk.ilitekGlass

final class SetUpFlowCornersReportTests: XCTestCase {

    /// A tap on `p` that rolls `roll` millimetres across and back while down: its mean is `p`, its
    /// travel `roll`.
    private func rollingTap(_ driver: inout Driver, _ p: CGPoint, at t: Double, roll: Double = 1) {
        driver.wait(until: t)
        driver.finger(t, at: p)
        driver.finger(t + 0.03, at: CGPoint(x: p.x + roll / glass.width, y: p.y))
        driver.finger(t + 0.06, at: CGPoint(x: p.x - roll / glass.width, y: p.y))
        driver.lift(t + 0.1)
    }

    /// The corner taps of a glass fitted straight, its picture `offCentre`, with tap 2 moved `wild`
    /// millimetres across.
    private func taps(wild: Double) -> [CGPoint] {
        var taps = Desk.cornerTaps(on: Desk.hdmi, rect: Desk.offCentre)
        taps[2].x += wild / glass.width
        return taps
    }

    private func assertNumbers(
        _ actual: [Double]?, _ expected: [Double], file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let actual, actual.count == expected.count else {
            return XCTFail("\(String(describing: actual)) ≠ \(expected)", file: file, line: line)
        }
        for (a, e) in zip(actual, expected) {
            XCTAssertEqual(a, e, accuracy: 1e-6, "\(actual)", file: file, line: line)
        }
    }

    func testNoReportBeforeTheFirstRound() throws {
        var driver = try Driver(Desk.calibrating())
        XCTAssertNil(driver.flow.lastCornersReport)
        rollingTap(&driver, taps(wild: 0)[0], at: 1)
        XCTAssertNil(driver.flow.lastCornersReport, "a round is four taps")
    }

    func testAnAcceptedRoundIsReported() throws {
        var driver = try Driver(Desk.calibrating())
        // A slide first, refused as moved at 7 mm: the round goes on.
        let p = taps(wild: 0)[0]
        driver.finger(1, at: p)
        driver.finger(1.05, at: CGPoint(x: p.x + 7 / glass.width, y: p.y))
        driver.lift(1.1)
        for (i, tap) in taps(wild: 5).enumerated() {
            rollingTap(&driver, tap, at: 2 + Double(i))
        }
        XCTAssertEqual(driver.step, .check(display: 3))
        let report = try XCTUnwrap(driver.flow.lastCornersReport)
        XCTAssertEqual(report.touchscreen, Desk.ilitekID)
        XCTAssertEqual(report.touchscreenName, "ILITEK-TP")
        XCTAssertEqual(report.round, 1)
        XCTAssertEqual(report.verdict, .accepted)
        XCTAssertEqual(report.orientation, .asFitted)
        XCTAssertEqual(report.glassMM, glass)
        XCTAssertEqual(report.glassSource, .reported)
        // Tap 2, 5 mm across, and tap 1, which shares its target's x, each lie 2.5 mm from the fit.
        assertNumbers(report.fromFit, [0, 2.5, 2.5, 0])
        XCTAssertEqual(report.spread ?? 0, (2 * 2.5 * 2.5 / 4).squareRoot(), accuracy: 1e-6)
        assertNumbers(report.travel, [1, 1, 1, 1])
        XCTAssertEqual(report.travelSource, .reported)
        assertNumbers(report.moved, [7])
    }

    func testARefusedRoundIsReported() throws {
        // One tap 20 mm off: Calibration fits it, the limits refuse it.
        var driver = try Driver(Desk.calibrating())
        for (i, tap) in taps(wild: 20).enumerated() {
            rollingTap(&driver, tap, at: 1 + Double(i), roll: 0.5)
        }
        XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi, problem: .tapsDidNotFit))
        var report = try XCTUnwrap(driver.flow.lastCornersReport)
        XCTAssertEqual(report.round, 1)
        XCTAssertEqual(report.verdict, .refused(.tapsDidNotFit))
        XCTAssertEqual(report.orientation, .asFitted)
        XCTAssertEqual(report.glassSource, .reported)
        assertNumbers(report.fromFit, [0, 10, 10, 0])
        XCTAssertEqual(report.spread ?? 0, (2 * 100.0 / 4).squareRoot(), accuracy: 1e-6)
        assertNumbers(report.travel, [0.5, 0.5, 0.5, 0.5])
        assertNumbers(report.moved, [])

        // The next round: the first target's place tapped again for the second, which Calibration
        // itself refuses. There is no fit, so nothing from one.
        let straight = taps(wild: 0)
        for (i, tap) in [straight[0], straight[0], straight[2], straight[3]].enumerated() {
            rollingTap(&driver, tap, at: 6 + Double(i))
        }
        report = try XCTUnwrap(driver.flow.lastCornersReport)
        XCTAssertEqual(report.round, 2)
        XCTAssertEqual(report.verdict, .refused(.tapsDidNotFit))
        XCTAssertNil(report.orientation)
        XCTAssertNil(report.glassMM)
        XCTAssertNil(report.glassSource)
        XCTAssertNil(report.fromFit)
        XCTAssertNil(report.spread)
        assertNumbers(report.travel, [1, 1, 1, 1])

        // And a third, good, of glass fitted turned half round and flipped: accepted, round 3.
        let turned = Orientation(quarterTurns: 2, isFlipped: true)
        for (i, tap) in Desk.cornerTaps(on: Desk.hdmi, orientation: turned, rect: Desk.offCentre).enumerated() {
            rollingTap(&driver, tap, at: 11 + Double(i))
        }
        XCTAssertEqual(driver.flow.lastCornersReport?.round, 3)
        XCTAssertEqual(driver.flow.lastCornersReport?.verdict, .accepted)
        XCTAssertEqual(driver.flow.lastCornersReport?.orientation, turned)
    }

    func testARoundStartedAgainForgetsTheTapsItHad() throws {
        // Two taps, then the display turned in macOS: the corners start again, and the round's
        // report has the four taps of the new round only.
        var driver = try Driver(Desk.calibrating())
        let p = taps(wild: 0)[0]
        driver.finger(1, at: p)
        driver.finger(1.05, at: CGPoint(x: p.x + 7 / glass.width, y: p.y))  // refused as moved
        driver.lift(1.1)
        rollingTap(&driver, taps(wild: 0)[0], at: 2, roll: 2)
        rollingTap(&driver, taps(wild: 0)[1], at: 3, roll: 2)
        driver.call { $0.displaysChanged(Desk.all(with: Desk.hdmiTurned), at: Driver.time(3.5)) }
        XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi))
        for (i, tap) in Desk.cornerTaps(on: Desk.hdmiTurned, rect: Desk.offCentre).enumerated() {
            rollingTap(&driver, tap, at: 5 + Double(i), roll: 0.5)
        }
        let report = try XCTUnwrap(driver.flow.lastCornersReport)
        XCTAssertEqual(report.round, 1)
        XCTAssertEqual(report.verdict, .accepted)
        assertNumbers(report.travel, [0.5, 0.5, 0.5, 0.5])
        assertNumbers(report.moved, [])
    }

    func testWhereTheSizesCameFrom() throws {
        // No report: "HDMI"'s own 602 × 329 mm, laid along the glass by the fit, over the picture's
        // extent; before the fit, its shorter reading.
        var driver = try Driver(
            Desk.start(.calibrate, candidates: [Desk.hdmi], glass: nil, current: Desk.pairing(Desk.hdmi)))
        for (i, tap) in taps(wild: 0).enumerated() {
            driver.tap(tap, at: 1 + Double(i))
        }
        var report = try XCTUnwrap(driver.flow.lastCornersReport)
        XCTAssertEqual(report.glassSource, .display)
        XCTAssertEqual(report.glassMM?.width ?? 0, 602 / Desk.offCentre.width, accuracy: 1e-6)
        XCTAssertEqual(report.glassMM?.height ?? 0, 329 / Desk.offCentre.height, accuracy: 1e-6)
        XCTAssertEqual(report.travelSource, .display)

        // No size at all: shares of the glass.
        let silent = changed(Desk.hdmi) { $0.sizeMM = .zero }
        driver = try Driver(
            Desk.start(.calibrate, candidates: [silent], all: Desk.all(with: silent), glass: nil,
                       current: Desk.pairing(silent)))
        var shares = taps(wild: 0)
        shares[2].x += 0.01
        for (i, tap) in shares.enumerated() {
            driver.tap(tap, at: 1 + Double(i))
        }
        report = try XCTUnwrap(driver.flow.lastCornersReport)
        XCTAssertEqual(report.verdict, .accepted)
        XCTAssertNil(report.glassMM)
        XCTAssertEqual(report.glassSource, .shares)
        assertNumbers(report.fromFit, [0, 0.005, 0.005, 0])
        XCTAssertEqual(report.travelSource, .shares)
        assertNumbers(report.travel, [0, 0, 0, 0])
    }

    // MARK: - The log line

    func testTheLogLine() {
        let accepted = Report(
            touchscreen: Desk.ilitekID, touchscreenName: "ILITEK-TP", round: 2, verdict: .accepted,
            orientation: Orientation(quarterTurns: 2, isFlipped: true), glassMM: CGSize(width: 476, height: 268),
            glassSource: .reported, fromFit: [2.14, 3.36, 1.0, 2.8], spread: 2.5, travel: [0.44, 0.9, 0.3, 1.06],
            travelSource: .reported, moved: [])
        XCTAssertEqual(
            accepted.logLine,
            "Set-up corners: ILITEK-TP [222a:0001:V06.00.00.00] round 2: accepted; orientation 180° flipped; "
                + "glass 476.0 × 268.0 mm (reported); taps 2.1, 3.4, 1.0, 2.8 mm from fit; spread 2.5 mm; "
                + "travel 0.4, 0.9, 0.3, 1.1 mm (reported); moved none")

        let noFit = Report(
            touchscreen: Desk.stripID, touchscreenName: "TouchScreen", round: 1, verdict: .refused(.tapsDidNotFit),
            orientation: nil, glassMM: nil, glassSource: nil, fromFit: nil, spread: nil,
            travel: [0.2, 0.3, 0.26, 0.4], travelSource: .display, moved: [7.04, 5.36])
        XCTAssertEqual(
            noFit.logLine,
            "Set-up corners: TouchScreen [27c0:0859:TEST-SERIAL-0001] round 1: refused (tapsDidNotFit); "
                + "orientation none; glass none; taps none from fit; spread none; "
                + "travel 0.2, 0.3, 0.3, 0.4 mm (display); moved 7.0, 5.4 mm")

        let inShares = Report(
            touchscreen: Desk.ilitekID, touchscreenName: "ILITEK-TP", round: 3, verdict: .refused(.ambiguous),
            orientation: Orientation(quarterTurns: 1, isFlipped: false), glassMM: nil, glassSource: .shares,
            fromFit: [0, 0.005, 0.005, 0], spread: 0.0035355, travel: [0.001, 0, 0.0004, 0.002],
            travelSource: .shares, moved: [0.0312])
        XCTAssertEqual(
            inShares.logLine,
            "Set-up corners: ILITEK-TP [222a:0001:V06.00.00.00] round 3: refused (ambiguous); orientation 90°; "
                + "glass unknown (shares of the glass); taps 0.0000, 0.0050, 0.0050, 0.0000 of the glass from fit; "
                + "spread 0.0035 of the glass; travel 0.0010, 0.0000, 0.0004, 0.0020 of the glass (shares); "
                + "moved 0.0312 of the glass")
    }
}
