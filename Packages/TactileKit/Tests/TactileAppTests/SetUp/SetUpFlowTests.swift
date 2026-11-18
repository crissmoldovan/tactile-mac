// The set-up flow, step by step: the plan's table of tests. The rules the table doesn't list are
// in `SetUpFlowRuleTests`, and hostile input in `SetUpFlowHostileInputTests`.

import CoreGraphics
import Foundation
import TactileApp
import TactileReading
import TactileScreens
import XCTest

private typealias Desk = SetUpDesk
private typealias Driver = FlowDriver

private let targets = Calibration.targets

/// The corners step as it starts: the first target, no problem.
func firstTarget(on display: DisplayFacts, problem: SetUpProblem? = nil) -> SetUpStep {
    .corners(display: display.displayID, target: Calibration.targets[0], index: 0, problem: problem)
}

/// Asserts that `event` finished with an outcome of `display`, `orientation`, an alignment within
/// `accuracy` of `rect`, and `diagonal`.
func assertOutcome(
    _ event: SetUpFlow.Event, display: DisplayIdentity, orientation: Orientation, rect: CGRect, diagonal: Double?,
    accuracy: CGFloat = 1e-9, file: StaticString = #filePath, line: UInt = #line
) {
    guard case .finished(let outcome?) = event else {
        return XCTFail("not finished with an outcome: \(event)", file: file, line: line)
    }
    XCTAssertEqual(outcome.display, display, file: file, line: line)
    XCTAssertEqual(outcome.orientation, orientation, file: file, line: line)
    XCTAssertEqual(outcome.diagonalInches, diagonal, file: file, line: line)
    assertRect(outcome.alignment.pictureRect, rect, accuracy: accuracy, file: file, line: line)
}

func assertRect(
    _ actual: CGRect, _ expected: CGRect, accuracy: CGFloat, file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: accuracy, "\(actual)", file: file, line: line)
    XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: accuracy, "\(actual)", file: file, line: line)
    XCTAssertEqual(actual.size.width, expected.size.width, accuracy: accuracy, "\(actual)", file: file, line: line)
    XCTAssertEqual(actual.size.height, expected.size.height, accuracy: accuracy, "\(actual)", file: file, line: line)
}

/// Asserts that `mapping` takes each corner tap back to the target it was made on, as the person
/// saw it: the fit, checked through the production path of a point.
func assertTapsLandOnTheirTargets(
    _ mapping: TouchMapping?, _ taps: [CGPoint], file: StaticString = #filePath, line: UInt = #line
) {
    guard let mapping else { return XCTFail("no check mapping", file: file, line: line) }
    for (tap, target) in zip(taps, Calibration.targets) {
        let landed = mapping.displayPoint(forGlass: tap)
        XCTAssertEqual(landed.x, target.x, accuracy: 1e-9, "\(target)", file: file, line: line)
        XCTAssertEqual(landed.y, target.y, accuracy: 1e-9, "\(target)", file: file, line: line)
    }
}

final class SetUpFlowTests: XCTestCase {

    // MARK: - A full set-up

    func testAFullSetUpStartsAtTheCornersOfItsOneDisplay() throws {
        let driver = try Driver(Desk.start())
        XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi), "no pair step: set-up mode chose the display")
        XCTAssertEqual(driver.flow.snapshot.touchscreen, Desk.ilitekID)
        XCTAssertEqual(driver.flow.snapshot.touchscreenName, "ILITEK-TP")
        XCTAssertEqual(driver.flow.snapshot.purpose, .full)

        // The one candidate must be the only one, and can't be the built-in display.
        XCTAssertNil(SetUpFlow(Desk.start(candidates: [Desk.hdmi, Desk.strip]), at: Driver.t0), "two candidates")
        XCTAssertNil(SetUpFlow(Desk.start(candidates: [Desk.hdmi, Desk.hdmi]), at: Driver.t0), "one listed twice")
        XCTAssertNil(SetUpFlow(Desk.start(candidates: [Desk.builtIn]), at: Driver.t0), "the built-in display")
        XCTAssertNil(SetUpFlow(Desk.start(candidates: []), at: Driver.t0), "none")
        XCTAssertNotNil(SetUpFlow(Desk.start(candidates: [Desk.strip]), at: Driver.t0))
    }

    func testAFullSetUpLeftAloneEndsAfterTwoMinutes() throws {
        var driver = try Driver(Desk.start())
        XCTAssertEqual(driver.wait(until: 119.9), .stillRunning)
        XCTAssertEqual(driver.wait(until: 120), .finished(nil), "two minutes without a touch")
        XCTAssertEqual(driver.wait(until: 125), .finished(nil))
    }

    // MARK: - Corners

    func testFourGoodTapsFit() throws {
        let orientation = Orientation(quarterTurns: 1, isFlipped: false)
        let taps = Desk.cornerTaps(on: Desk.hdmi, orientation: orientation, rect: Desk.offCentre)
        var driver = try Driver(Desk.start())
        XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi))

        for (index, tap) in taps.enumerated() {
            XCTAssertEqual(
                driver.step, .corners(display: 3, target: targets[index], index: index, problem: nil), "tap \(index)")
            XCTAssertEqual(driver.tap(tap, at: 2 + Double(index)), .stillRunning)
        }
        guard case .size(display: 3, _, _, _) = driver.step else { return XCTFail("\(driver.step)") }
        XCTAssertNil(driver.flow.checkMapping)

        driver.call { $0.confirmSize(inches: 23.8) }
        XCTAssertEqual(driver.step, .check(display: 3))
        let mapping = try XCTUnwrap(driver.flow.checkMapping)
        XCTAssertEqual(mapping.orientation, orientation)
        assertRect(mapping.alignment.pictureRect, Desk.offCentre, accuracy: 1e-9)
        XCTAssertEqual(mapping.display, Desk.hdmi)
        XCTAssertNil(mapping.content)
        assertTapsLandOnTheirTargets(mapping, taps)
    }

    func testEachOrientationIsRecovered() throws {
        for orientation in Orientation.allCases {
            let taps = Desk.cornerTaps(on: Desk.hdmi, orientation: orientation, rect: Desk.offCentre)
            var driver = try Driver(Desk.calibrating())
            driver.taps(taps, from: 1)
            XCTAssertEqual(driver.step, .check(display: 3), "\(orientation)")
            assertTapsLandOnTheirTargets(driver.flow.checkMapping, taps)
            assertOutcome(
                driver.press { $0.done() }, display: DisplayIdentity(Desk.hdmi), orientation: orientation,
                rect: Desk.offCentre, diagonal: nil)
        }
    }

    func testTheTargetsAllowForARotatedDisplay() throws {
        let orientation = Orientation(quarterTurns: 2, isFlipped: true)
        var outcomes: [SetUpFlow.Event] = []
        for display in [Desk.hdmi, Desk.hdmiTurned] {
            // The glass is fixed on the panel, so the taps are where the targets fall on the
            // panel, which macOS has turned under them.
            let taps = Desk.cornerTaps(on: display, orientation: orientation, rect: Desk.offCentre)
            var driver = try Driver(Desk.start(.calibrate, candidates: [display], current: Desk.pairing(Desk.hdmi)))
            driver.taps(taps, from: 1)
            XCTAssertEqual(driver.step, .check(display: 3), "\(display.rotation)°")
            assertTapsLandOnTheirTargets(driver.flow.checkMapping, taps)
            outcomes.append(driver.press { $0.done() })
        }
        XCTAssertNotEqual(
            Desk.cornerTaps(on: Desk.hdmi, orientation: orientation, rect: Desk.offCentre),
            Desk.cornerTaps(on: Desk.hdmiTurned, orientation: orientation, rect: Desk.offCentre),
            "the turned display's taps are elsewhere on the glass")
        for outcome in outcomes {
            assertOutcome(
                outcome, display: DisplayIdentity(Desk.hdmi), orientation: orientation, rect: Desk.offCentre,
                diagonal: nil)
        }
    }

    func testASlideOrTwoFingersRefusesTheTap() throws {
        let taps = Desk.cornerTaps(on: Desk.hdmi)
        var driver = try Driver(Desk.calibrating())
        XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi))

        // A slide: 5% of the glass.
        driver.finger(1.0, at: taps[0])
        driver.finger(1.05, at: CGPoint(x: taps[0].x + 0.03, y: taps[0].y + 0.04))
        driver.finger(1.1, at: taps[0])
        driver.lift(1.15)
        XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi, problem: .moved))

        // Two fingers at once.
        driver.frame(2.0, [Contact(id: 1, position: taps[0]), Contact(id: 2, position: taps[1])])
        driver.frame(2.1, [Contact(id: 1, position: taps[0]), Contact(id: 2, position: taps[1])])
        driver.lift(2.2)
        XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi, problem: .tooManyFingers))

        // A good tap clears it.
        driver.tap(taps[0], at: 3)
        XCTAssertEqual(driver.step, .corners(display: 3, target: targets[1], index: 1, problem: nil))
    }

    func testTapsThatDoNotFitStartAgain() throws {
        let taps = Desk.cornerTaps(on: Desk.hdmi)
        var driver = try Driver(Desk.calibrating())
        // The first target's place, tapped again for the second.
        XCTAssertEqual(driver.taps([taps[0], taps[0], taps[2], taps[3]], from: 1), .stillRunning)
        XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi, problem: .tapsDidNotFit))
        XCTAssertNil(driver.flow.checkMapping)

        // A good round then fits.
        driver.taps(taps, from: 6)
        XCTAssertEqual(driver.step, .check(display: 3))
    }

    // MARK: - Size

    func testSizeOffersOnlyPlausibleReports() throws {
        var driver = try Driver(Desk.start(diagonal: 23.8))
        driver.taps(Desk.cornerTaps(on: Desk.hdmi), from: 2)
        guard case .size(display: 3, let display?, let glass?, current: 23.8) = driver.step else {
            return XCTFail("\(driver.step)")
        }
        XCTAssertEqual(display, 27.0, accuracy: 0.05, "HDMI reports 27″")
        XCTAssertEqual(glass, 21.5, accuracy: 0.05, "the ILITEK reports 21.5″")

        // A display that reports no size, and a touchscreen that reports none.
        let silent = changed(Desk.hdmi) { $0.sizeMM = .zero }
        driver = try Driver(Desk.start(candidates: [silent], glass: nil))
        driver.taps(Desk.cornerTaps(on: silent), from: 2)
        XCTAssertEqual(driver.step, .size(display: 3, displayReports: nil, touchscreenReports: nil, current: nil))

        // Sizes that put the picture's density outside 50…400 dots per inch.
        let tiny = changed(Desk.hdmi) { $0.sizeMM = CGSize(width: 60, height: 33) }
        driver = try Driver(Desk.start(candidates: [tiny], glass: CGSize(width: 4000, height: 2250)))
        driver.taps(Desk.cornerTaps(on: tiny), from: 2)
        XCTAssertEqual(driver.step, .size(display: 3, displayReports: nil, touchscreenReports: nil, current: nil))
    }

    func testSizeRefusesNonsense() throws {
        var driver = try Driver(Desk.start())
        driver.taps(Desk.cornerTaps(on: Desk.hdmi), from: 2)
        let size = driver.step
        guard case .size = size else { return XCTFail("\(size)") }
        let before = driver.flow

        for nonsense in [0, -5, 1000, .nan, .infinity, -.infinity, 2.99, 200.01, .greatestFiniteMagnitude] {
            XCTAssertEqual(driver.call { $0.confirmSize(inches: nonsense) }, .stillRunning, "\(nonsense)")
            XCTAssertEqual(driver.flow, before, "\(nonsense)")
        }
        driver.call { $0.confirmSize(inches: 3) }
        XCTAssertEqual(driver.step, .check(display: 3), "3″ is the smallest plausible")
    }

    // MARK: - Check

    func testCheckThenDoneGivesTheOutcome() throws {
        let orientation = Orientation(quarterTurns: 2, isFlipped: true)
        var driver = try Driver(Desk.start())
        driver.taps(Desk.cornerTaps(on: Desk.hdmi, orientation: orientation, rect: Desk.offCentre), from: 2)
        driver.call { $0.confirmSize(inches: 23.8) }
        XCTAssertEqual(driver.step, .check(display: 3))
        // Touches in the check step are only shown, by the caller.
        driver.tap(CGPoint(x: 0.3, y: 0.6), at: 7)
        XCTAssertEqual(driver.step, .check(display: 3))

        assertOutcome(
            driver.press { $0.done() }, display: DisplayIdentity(Desk.hdmi), orientation: orientation,
            rect: Desk.offCentre, diagonal: 23.8)
    }

    func testRedoGoesBackToCorners() throws {
        let first = Orientation(quarterTurns: 3, isFlipped: false)
        let second = Orientation.asFitted
        var driver = try Driver(Desk.start(diagonal: 27))
        driver.taps(Desk.cornerTaps(on: Desk.hdmi, orientation: first, rect: Desk.offCentre), from: 2)
        driver.press { $0.confirmSize(inches: 23.8) }

        XCTAssertEqual(driver.press { $0.redo() }, .stillRunning)
        XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi))
        XCTAssertNil(driver.flow.checkMapping)

        let secondTaps = Desk.cornerTaps(on: Desk.hdmi, orientation: second, rect: Desk.wholeGlass)
        driver.taps(secondTaps, from: 10)
        guard case .size(display: 3, _, _, current: 23.8) = driver.step else {
            return XCTFail("the size again, with the one just confirmed: \(driver.step)")
        }
        driver.press { $0.confirmSize(inches: nil) }
        assertTapsLandOnTheirTargets(driver.flow.checkMapping, secondTaps)
        assertOutcome(
            driver.press { $0.done() }, display: DisplayIdentity(Desk.hdmi), orientation: second,
            rect: Desk.wholeGlass, diagonal: nil)
    }

    func testCalibrateKeepsTheDisplayAndSize() throws {
        // Paired with HDMI under an older identity: the same panel, its UUID since changed.
        var current = Desk.pairing(Desk.hdmi, Orientation(quarterTurns: 1, isFlipped: true), Desk.offCentre)
        current.display.uuid = "00000000-0000-0000-0000-0000000000AA"
        current.displayName = "HDMI"
        let orientation = Orientation(quarterTurns: 0, isFlipped: true)
        var driver = try Driver(Desk.start(.calibrate, candidates: [Desk.hdmi], current: current, diagonal: 23.8))
        XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi), "no pairing step")

        driver.taps(Desk.cornerTaps(on: Desk.hdmi, orientation: orientation), from: 1)
        XCTAssertEqual(driver.step, .check(display: 3), "no size step")
        XCTAssertEqual(driver.flow.snapshot.purpose, .calibrate)
        assertOutcome(
            driver.press { $0.done() }, display: current.display, orientation: orientation, rect: Desk.wholeGlass,
            diagonal: 23.8)
    }

    func testTestStoresNothing() throws {
        let stored = Orientation(quarterTurns: 1, isFlipped: false)
        var driver = try Driver(
            Desk.start(.test, candidates: [Desk.hdmi], current: Desk.pairing(Desk.hdmi, stored, Desk.offCentre),
                       diagonal: 23.8))
        XCTAssertEqual(driver.step, .check(display: 3), "the check step alone")
        let mapping = try XCTUnwrap(driver.flow.checkMapping)
        XCTAssertEqual(mapping.orientation, stored)
        XCTAssertEqual(mapping.alignment.pictureRect, Desk.offCentre)
        XCTAssertEqual(mapping.display, Desk.hdmi)

        // Past the check's reaction time, so that only the purpose can refuse the Redo.
        driver.wait(until: 0.5)
        let before = driver.flow
        XCTAssertEqual(driver.call { $0.redo() }, .stillRunning)
        XCTAssertEqual(driver.call { $0.confirmSize(inches: 20) }, .stillRunning)
        XCTAssertEqual(driver.flow, before)
        XCTAssertEqual(driver.press { $0.done() }, .finished(nil))
    }

    // MARK: - Ending

    func testCancelAtEveryStepGivesNil() throws {
        var steps: [(String, Driver)] = []
        var driver = try Driver(Desk.start())
        steps.append(("corners", driver))
        driver.tap(Desk.cornerTaps(on: Desk.hdmi)[0], at: 2)
        steps.append(("corners, one tap in", driver))
        driver.finger(3, at: Desk.cornerTaps(on: Desk.hdmi)[1])
        steps.append(("corners, mid-tap", driver))
        driver.lift(3.1)
        driver.taps(Array(Desk.cornerTaps(on: Desk.hdmi)[2...]), from: 4)
        steps.append(("size", driver))
        driver.call { $0.confirmSize(inches: nil) }
        steps.append(("check", driver))
        steps.append(("calibrate", try Driver(Desk.calibrating())))
        steps.append(("test", try Driver(Desk.start(.test, candidates: [Desk.hdmi], current: Desk.pairing(Desk.hdmi)))))

        for (name, driver) in steps {
            var driver = driver
            XCTAssertEqual(driver.last, .stillRunning, name)
            XCTAssertEqual(driver.call { $0.cancel() }, .finished(nil), name)
        }
    }

    func testTheDisplayGoingAwayEndsIt() throws {
        let withoutHDMI = Desk.all.filter { $0.displayID != Desk.hdmi.displayID }
        var driver = try Driver(Desk.start())
        driver.taps(Array(Desk.cornerTaps(on: Desk.hdmi)[..<2]), from: 2)
        XCTAssertEqual(driver.step, .corners(display: 3, target: targets[2], index: 2, problem: nil))
        XCTAssertEqual(driver.call { $0.displaysChanged(withoutHDMI, at: Driver.time(5)) }, .finished(nil))

        // In the size and check steps too.
        driver = try Driver(Desk.start())
        driver.taps(Desk.cornerTaps(on: Desk.hdmi), from: 2)
        var check = driver
        check.call { $0.confirmSize(inches: nil) }
        XCTAssertEqual(driver.call { $0.displaysChanged(withoutHDMI, at: Driver.time(7)) }, .finished(nil), "size")
        XCTAssertEqual(check.call { $0.displaysChanged(withoutHDMI, at: Driver.time(7)) }, .finished(nil), "check")
    }
}
