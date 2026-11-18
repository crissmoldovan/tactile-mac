import CoreGraphics
import Foundation
import XCTest
@testable import TactileScreens
import TactileTestSupport

/// The picture rectangle the brief's tests fit: a little in from the glass's edges, not centred.
private let pictureRect = CGRect(x: 0.02, y: 0.03, width: 0.95, height: 0.93)

private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: x, y: y)
}

/// Perfect taps: each target sent backwards through the alignment, then through the orientation.
private func perfectTaps(
    _ orientation: Orientation, _ rect: CGRect = pictureRect, targets: [CGPoint] = Calibration.targets
) -> [CalibrationTap] {
    targets.map { target in
        let oriented = point(rect.origin.x + target.x * rect.size.width, rect.origin.y + target.y * rect.size.height)
        return CalibrationTap(target: target, glass: orientation.inverse(oriented))
    }
}

/// `taps` with each glass point moved by the matching offset.
private func moved(_ taps: [CalibrationTap], by offsets: [CGVector]) -> [CalibrationTap] {
    zip(taps, offsets).map { tap, offset in
        CalibrationTap(target: tap.target, glass: point(tap.glass.x + offset.dx, tap.glass.y + offset.dy))
    }
}

/// `taps` with the targets of taps `i` and `j` exchanged: the glass points stay where they were.
private func swappingTargets(_ taps: [CalibrationTap], _ i: Int, _ j: Int) -> [CalibrationTap] {
    var swapped = taps
    swapped[i].target = taps[j].target
    swapped[j].target = taps[i].target
    return swapped
}

/// The fit, which the test expects there to be.
private func fitted(
    _ taps: [CalibrationTap], _ message: @autoclosure () -> String = "", file: StaticString = #filePath,
    line: UInt = #line
) throws -> Calibration.Fit {
    switch Calibration.fit(taps) {
    case .success(let fit):
        return fit
    case .failure(let failure):
        let error = FitFailed(failure: failure, message: message())
        XCTFail(error.description, file: file, line: line)
        throw error
    }
}

private struct FitFailed: Error, CustomStringConvertible {
    let failure: Calibration.Failure
    let message: String
    var description: String { "no fit: \(failure) \(message)" }
}

private func assertRect(
    _ actual: CGRect, _ expected: CGRect, accuracy: CGFloat, _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath, line: UInt = #line
) {
    let pairs = [
        ("x", actual.origin.x, expected.origin.x), ("y", actual.origin.y, expected.origin.y),
        ("width", actual.size.width, expected.size.width), ("height", actual.size.height, expected.size.height),
    ]
    for (name, a, e) in pairs {
        XCTAssertEqual(a, e, accuracy: accuracy, "\(name): \(actual) ≠ \(expected) \(message())", file: file, line: line)
    }
}

/// Whether every number in `fit` is finite.
private func hasOnlyFiniteNumbers(_ fit: Calibration.Fit) -> Bool {
    let r = fit.alignment.pictureRect
    return [r.origin.x, r.origin.y, r.size.width, r.size.height].allSatisfy(\.isFinite) && fit.error.isFinite
}

/// The orientation that does what `orientation` does and then `then` to the oriented point.
private func composed(_ orientation: Orientation, then: (CGPoint) -> CGPoint) -> Orientation? {
    // Three points not on one line pin down which of the 8 it is.
    let probes = [point(0.1, 0.2), point(0.7, 0.3), point(0.4, 0.9)]
    return Orientation.allCases.first { candidate in
        probes.allSatisfy { p in
            let a = candidate.apply(p), b = then(orientation.apply(p))
            return abs(a.x - b.x) < 1e-12 && abs(a.y - b.y) < 1e-12
        }
    }
}

final class CalibrationTests: XCTestCase {
    /// Fixed offsets of glass points, up to 0.005 on each axis, in three patterns: irregular; the
    /// full 0.005 on both axes, in a different direction for each tap; and the same for every tap.
    private let noisePatterns: [[CGVector]] = [
        [CGVector(dx: 0.005, dy: -0.004), CGVector(dx: -0.003, dy: 0.005), CGVector(dx: 0.004, dy: -0.005),
         CGVector(dx: -0.005, dy: 0.002)],
        [CGVector(dx: -0.005, dy: -0.005), CGVector(dx: 0.005, dy: -0.005), CGVector(dx: 0.005, dy: 0.005),
         CGVector(dx: -0.005, dy: 0.005)],
        Array(repeating: CGVector(dx: 0.005, dy: 0.005), count: 4),
    ]

    func testTheTargetsAreTheFourCornersInFromTheEdges() {
        XCTAssertEqual(Calibration.targets, [point(0.12, 0.12), point(0.88, 0.12), point(0.88, 0.88), point(0.12, 0.88)])
    }

    func testRecoversEveryOrientationFromPerfectTaps() throws {
        for orientation in Orientation.allCases {
            let fit = try fitted(perfectTaps(orientation), "\(orientation)")
            XCTAssertEqual(fit.orientation, orientation)
            assertRect(fit.alignment.pictureRect, pictureRect, accuracy: 1e-9, "\(orientation)")
            XCTAssertEqual(fit.error, 0, accuracy: 1e-9, "\(orientation)")
        }
    }

    func testRecoversEveryOrientationFromNoisyTaps() throws {
        for orientation in Orientation.allCases {
            for (index, offsets) in noisePatterns.enumerated() {
                let place = "\(orientation), pattern \(index)"
                let fit = try fitted(moved(perfectTaps(orientation), by: offsets), place)
                XCTAssertEqual(fit.orientation, orientation, place)
                assertRect(fit.alignment.pictureRect, pictureRect, accuracy: 0.02, place)
                // No tap is more than 0.005 × √2 from where it should be.
                XCTAssertLessThanOrEqual(fit.error, 0.005 * 2.0.squareRoot() + 1e-12, place)
            }
        }
    }

    func testRefusesTapsThatDoNotFit() {
        let taps = Calibration.targets.map { CalibrationTap(target: $0, glass: point(0.5, 0.5)) }
        XCTAssertEqual(Calibration.fit(taps), .failure(.tapsDoNotFit))
    }

    func testRefusesFewerThanFourTaps() {
        let good = perfectTaps(.asFitted)
        XCTAssertEqual(Calibration.fit(Array(good.prefix(3))), .failure(.tooFewTaps))
        XCTAssertEqual(Calibration.fit([]), .failure(.tooFewTaps))
    }

    /// Tapping the next target where the previous one was, or the other way round. No orientation
    /// can explain it: on one axis the targets no longer follow the taps at all.
    func testRefusesTapsWithTwoNeighbouringTargetsSwapped() {
        for orientation in Orientation.allCases {
            for (i, j) in [(0, 1), (1, 2), (2, 3), (3, 0)] {
                let taps = swappingTargets(perfectTaps(orientation), i, j)
                XCTAssertEqual(Calibration.fit(taps), .failure(.tapsDoNotFit), "\(orientation), targets \(i) and \(j)")
            }
        }
    }

    /// The known limit, pinned. The four targets sit on a square's corners. Exchanging the targets
    /// of two opposite corners while the other two stay is the square's reflection across the
    /// diagonal through those other two, and that reflection is one of the 8 orientations. So the
    /// taps are, exactly, a perfect calibration of a glass fitted that way: nothing in four points
    /// can tell the two apart. In the app it takes tapping where no target is shown, twice.
    func testOppositeCornersSwappedLookLikeAnotherFitting() throws {
        let whole = GlassAlignment.wholeGlass.pictureRect
        let good = perfectTaps(.asFitted, whole)

        // Top-left and bottom-right exchanged: the reflection across the top-right to bottom-left
        // diagonal, (x, y) → (1 − y, 1 − x).
        let acrossRising = try fitted(swappingTargets(good, 0, 2))
        XCTAssertEqual(acrossRising.orientation, Orientation(quarterTurns: 1, isFlipped: true))
        XCTAssertEqual(acrossRising.orientation.apply(point(0.1, 0.3)).x, 0.7, accuracy: 1e-12)
        XCTAssertEqual(acrossRising.orientation.apply(point(0.1, 0.3)).y, 0.9, accuracy: 1e-12)
        assertRect(acrossRising.alignment.pictureRect, whole, accuracy: 1e-9)
        XCTAssertEqual(acrossRising.error, 0, accuracy: 1e-9)

        // Top-right and bottom-left exchanged: the reflection across the top-left to bottom-right
        // diagonal, (x, y) → (y, x).
        let acrossFalling = try fitted(swappingTargets(good, 1, 3))
        XCTAssertEqual(acrossFalling.orientation, Orientation(quarterTurns: 3, isFlipped: true))
        XCTAssertEqual(acrossFalling.orientation.apply(point(0.1, 0.3)).x, 0.3, accuracy: 1e-12)
        XCTAssertEqual(acrossFalling.orientation.apply(point(0.1, 0.3)).y, 0.1, accuracy: 1e-12)
        assertRect(acrossFalling.alignment.pictureRect, whole, accuracy: 1e-9)
        XCTAssertEqual(acrossFalling.error, 0, accuracy: 1e-9)
    }

    func testAMirrorNeverWins() {
        for orientation in Orientation.allCases {
            let competing = Calibration.everyFit(perfectTaps(orientation)).filter(Calibration.competes)
            XCTAssertEqual(competing.map(\.orientation), [orientation], "\(orientation)")
        }
    }

    /// The error can't tell an orientation from itself followed by a mirror: the least-squares line
    /// of the mirrored axis is the same line turned round, and every tap is as far from it as
    /// before. Only the rule that the rectangle's width and height be 0.5…1.5 rejects the mirror,
    /// whose extent on that axis is negative.
    func testOnlyTheExtentRuleRejectsAMirror() throws {
        let mirrors: [(name: String, apply: (CGPoint) -> CGPoint, width: CGFloat, height: CGFloat)] = [
            ("left to right", { point(1 - $0.x, $0.y) }, -1, 1),
            ("top to bottom", { point($0.x, 1 - $0.y) }, 1, -1),
            ("half turn", { point(1 - $0.x, 1 - $0.y) }, -1, -1),
        ]
        for orientation in Orientation.allCases {
            for (index, taps) in [perfectTaps(orientation), moved(perfectTaps(orientation), by: noisePatterns[0])].enumerated() {
                let fits = Calibration.everyFit(taps)
                let truth = try XCTUnwrap(fits.first { $0.orientation == orientation }, "\(orientation)")
                XCTAssertTrue(Calibration.competes(truth), "\(orientation)")
                for mirror in mirrors {
                    let place = "\(orientation) then \(mirror.name), taps \(index)"
                    let mirrored = try XCTUnwrap(composed(orientation, then: mirror.apply), place)
                    let fit = try XCTUnwrap(fits.first { $0.orientation == mirrored }, place)
                    XCTAssertEqual(fit.error, truth.error, accuracy: 1e-12, place)
                    XCTAssertEqual(
                        fit.alignment.pictureRect.size.width, mirror.width * pictureRect.size.width, accuracy: 0.02, place)
                    XCTAssertEqual(
                        fit.alignment.pictureRect.size.height, mirror.height * pictureRect.size.height, accuracy: 0.02,
                        place)
                    XCTAssertFalse(Calibration.competes(fit), place)
                }
            }
        }
    }

    /// Targets all on one diagonal can't tell a glass fitted straight from one reflected across that
    /// diagonal: both fit perfectly, with a picture that fills the glass.
    func testRefusesTapsThatCannotTellTheAxesApart() {
        let diagonal = [point(0.12, 0.12), point(0.37, 0.37), point(0.63, 0.63), point(0.88, 0.88)]
        let taps = perfectTaps(.asFitted, GlassAlignment.wholeGlass.pictureRect, targets: diagonal)
        XCTAssertEqual(Calibration.everyFit(taps).filter(Calibration.competes).count, 2)
        XCTAssertEqual(Calibration.fit(taps), .failure(.ambiguous))
    }

    /// Targets near one diagonal, moving off it in steps of 0.005. The straight fit stays perfect.
    /// The fit reflected across that diagonal keeps competing, with a picture near the whole glass,
    /// while its error grows from 0 by about 0.0048 a step. So the taps are refused as ambiguous
    /// while that error is within 0.02: up to 0.020 off (an error of 0.0191), and not from 0.025 off
    /// (0.0239).
    func testAmbiguityIsASecondFitWithinTheMargin() throws {
        XCTAssertEqual(Calibration.ambiguityMargin, 0.02)
        let reflected = Orientation(quarterTurns: 3, isFlipped: true)
        for step in 0...20 {
            let off = CGFloat(step) * 0.005
            let place = "off \(off)"
            let targets = [point(0.12, 0.12), point(0.37, 0.37 + off), point(0.63, 0.63 - off), point(0.88, 0.88)]
            let taps = perfectTaps(.asFitted, GlassAlignment.wholeGlass.pictureRect, targets: targets)
            let competing = Calibration.everyFit(taps).filter(Calibration.competes)
            XCTAssertEqual(Set(competing.map(\.orientation)), [.asFitted, reflected], place)
            let straight = try XCTUnwrap(competing.first { $0.orientation == .asFitted }, place)
            let rival = try XCTUnwrap(competing.first { $0.orientation == reflected }, place)
            XCTAssertEqual(straight.error, 0, accuracy: 1e-9, place)
            XCTAssertEqual(rival.error - straight.error <= Calibration.ambiguityMargin, step <= 4, place)
            if step <= 4 {
                XCTAssertEqual(Calibration.fit(taps), .failure(.ambiguous), place)
            } else {
                XCTAssertEqual(try fitted(taps, place), straight, place)
            }
        }
    }

    /// Every tap the same distance from where the fit puts its target, in a pattern that leaves the
    /// least-squares lines where they were: the error is that distance, and 0.04 is the most allowed.
    func testRefusesAnErrorAboveTheLimit() throws {
        func taps(error: CGFloat) -> [CalibrationTap] {
            let d = error / 2.0.squareRoot()
            let offsets = [CGVector(dx: d, dy: d), CGVector(dx: -d, dy: -d), CGVector(dx: d, dy: d), CGVector(dx: -d, dy: -d)]
            return moved(perfectTaps(.asFitted, GlassAlignment.wholeGlass.pictureRect), by: offsets)
        }
        XCTAssertEqual(Calibration.largestError, 0.04)
        let within = try fitted(taps(error: 0.039))
        XCTAssertEqual(within.orientation, .asFitted)
        XCTAssertEqual(within.error, 0.039, accuracy: 1e-12)
        assertRect(within.alignment.pictureRect, GlassAlignment.wholeGlass.pictureRect, accuracy: 1e-12)
        XCTAssertEqual(Calibration.fit(taps(error: 0.041)), .failure(.tapsDoNotFit))
    }

    func testRefusesAPictureTooSmallOrTooLargeForTheGlass() throws {
        XCTAssertEqual(Calibration.extents, 0.5...1.5)
        let narrow = CGRect(x: 0.25, y: 0.1, width: 0.49, height: 0.8)
        XCTAssertEqual(Calibration.fit(perfectTaps(.asFitted, narrow)), .failure(.tapsDoNotFit))
        let justWideEnough = CGRect(x: 0.25, y: 0.1, width: 0.51, height: 0.8)
        assertRect(try fitted(perfectTaps(.asFitted, justWideEnough)).alignment.pictureRect, justWideEnough, accuracy: 1e-9)
        let tall = CGRect(x: 0.1, y: -0.25, width: 0.8, height: 1.51)
        XCTAssertEqual(Calibration.fit(perfectTaps(.asFitted, tall)), .failure(.tapsDoNotFit))
        let justShortEnough = CGRect(x: 0.1, y: -0.25, width: 0.8, height: 1.49)
        assertRect(try fitted(perfectTaps(.asFitted, justShortEnough)).alignment.pictureRect, justShortEnough, accuracy: 1e-9)
    }

    func testRefusesATapThatIsNotFinite() {
        let good = perfectTaps(.asFitted)
        for bad in [CGFloat.nan, .infinity, -.infinity, .signalingNaN] {
            for index in good.indices {
                var glassX = good, targetY = good
                glassX[index].glass.x = bad
                targetY[index].target.y = bad
                XCTAssertEqual(Calibration.fit(glassX), .failure(.tapsDoNotFit), "glass x \(bad) at \(index)")
                XCTAssertEqual(Calibration.fit(targetY), .failure(.tapsDoNotFit), "target y \(bad) at \(index)")
            }
        }
        // A fifth tap that isn't finite spoils four good ones.
        XCTAssertEqual(
            Calibration.fit(good + [CalibrationTap(target: point(0.5, 0.5), glass: point(.nan, 0.5))]),
            .failure(.tapsDoNotFit))
    }

    func testUsesEveryTapWhenThereAreMoreThanFour() throws {
        let centre = CalibrationTap(target: point(0.5, 0.5), glass: point(0.5, 0.5))
        let five = perfectTaps(.asFitted, GlassAlignment.wholeGlass.pictureRect) + [centre]
        XCTAssertEqual(try fitted(five).orientation, .asFitted)
        XCTAssertEqual(try fitted(five).error, 0, accuracy: 1e-9)

        // Four good taps and one 0.4 off on each axis.
        var spoiled = five
        spoiled[4].glass = point(0.9, 0.1)
        XCTAssertEqual(Calibration.fit(spoiled), .failure(.tapsDoNotFit))
    }

    func testRefusesTargetsThatDoNotSpanBothAxes() {
        let glass = perfectTaps(.asFitted).map(\.glass)
        let oneTarget = glass.map { CalibrationTap(target: point(0.5, 0.5), glass: $0) }
        XCTAssertEqual(Calibration.fit(oneTarget), .failure(.tapsDoNotFit))
        let oneRow = zip(glass, [0.12, 0.37, 0.63, 0.88] as [CGFloat]).map {
            CalibrationTap(target: point($1, 0.5), glass: $0)
        }
        XCTAssertEqual(Calibration.fit(oneRow), .failure(.tapsDoNotFit))
        let oneColumn = zip(glass, [0.12, 0.37, 0.63, 0.88] as [CGFloat]).map {
            CalibrationTap(target: point(0.5, $1), glass: $0)
        }
        XCTAssertEqual(Calibration.fit(oneColumn), .failure(.tapsDoNotFit))
    }

    /// Whatever it is given, `fit` returns, and a fit it returns has only finite numbers, a picture
    /// 0.5…1.5 of the glass on each axis and an error of at most 0.04.
    func testNeverTrapsOrGivesANonFiniteFit() throws {
        let big = CGFloat.greatestFiniteMagnitude
        let tiny = CGFloat.leastNonzeroMagnitude
        let good = perfectTaps(.asFitted)
        var inputs: [[CalibrationTap]] = [
            good.map { CalibrationTap(target: $0.target, glass: point($0.glass.x * big, $0.glass.y * big)) },
            good.map { CalibrationTap(target: point($0.target.x * big, $0.target.y * -big), glass: $0.glass) },
            good.map { CalibrationTap(target: point($0.target.x * tiny, $0.target.y * tiny), glass: $0.glass) },
            good.map { CalibrationTap(target: $0.target, glass: point($0.glass.x * tiny, $0.glass.y * tiny)) },
            good.map { CalibrationTap(target: $0.target, glass: point($0.glass.x * 1e6 - 3e5, $0.glass.y * -1e6)) },
            good.map { CalibrationTap(target: point($0.target.x * 1e200, $0.target.y * 1e200), glass: point(1e200, -1e200)) },
            good.map { CalibrationTap(target: point(1e-300 * $0.target.x, 0.5), glass: $0.glass) },
            good.map { _ in CalibrationTap(target: point(big, big), glass: point(-big, big)) },
            Array(repeating: CalibrationTap(target: .zero, glass: .zero), count: 4),
            (0..<100).map { CalibrationTap(target: point(CGFloat($0 % 10) / 9, CGFloat($0 / 10) / 9), glass: point(0.5, 0.5)) },
        ]
        inputs.append((0..<100).map {
            let target = point(CGFloat($0 % 10) / 9, CGFloat($0 / 10) / 9)
            return CalibrationTap(target: target, glass: point(0.05 + 0.9 * target.x, 0.04 + 0.92 * target.y))
        })
        for (index, taps) in inputs.enumerated() {
            if case .success(let fit) = Calibration.fit(taps) {
                XCTAssertTrue(hasOnlyFiniteNumbers(fit), "input \(index): \(fit)")
                XCTAssertTrue(Calibration.extents.contains(fit.alignment.pictureRect.size.width), "input \(index)")
                XCTAssertTrue(Calibration.extents.contains(fit.alignment.pictureRect.size.height), "input \(index)")
                XCTAssertLessThanOrEqual(fit.error, Calibration.largestError, "input \(index)")
            }
            for fit in Calibration.everyFit(taps) {
                XCTAssertTrue(hasOnlyFiniteNumbers(fit), "input \(index): \(fit)")
            }
        }
        // The last: a hundred taps on a grid, each exactly where a 0.9 × 0.92 picture puts it.
        XCTAssertEqual(try fitted(inputs[inputs.count - 1]).orientation, .asFitted)
    }

    func testTheSameTapsGiveTheSameAnswer() {
        for orientation in Orientation.allCases {
            let taps = moved(perfectTaps(orientation), by: noisePatterns[0])
            XCTAssertEqual(Calibration.fit(taps), Calibration.fit(taps))
            XCTAssertEqual(Calibration.everyFit(taps), Calibration.everyFit(taps))
        }
    }

    // MARK: - The surveyed panels

    private let wchVendorID = 0x27c0, wchProductID = 0x0859
    private let ilitekVendorID = 0x222a, ilitekProductID = 0x0001

    /// The survey asked for the corners themselves, in takes 5 to 8, in this order.
    private let cornerTakes = [
        (number: 5, title: "Corner: top-left", target: point(0, 0)),
        (number: 6, title: "Corner: top-right", target: point(1, 0)),
        (number: 7, title: "Corner: bottom-right", target: point(1, 1)),
        (number: 8, title: "Corner: bottom-left", target: point(0, 1)),
    ]

    /// Each corner take as one tap: the median, on each axis, of every position the survey tool
    /// decoded from its reports (fingers for the ILITEK, the pointer for the wch.cn strip).
    private func cornerTaps(_ touchscreen: SurveyFixtures.Touchscreen) throws -> [CalibrationTap] {
        try cornerTakes.map { corner in
            let take = try XCTUnwrap(touchscreen.takes.first { $0.number == corner.number }, "no take \(corner.number)")
            XCTAssertEqual(take.title, corner.title)
            var xs: [Double] = [], ys: [Double] = []
            for report in take.reports {
                for finger in report.fingers ?? [] {
                    if let x = finger.x, let y = finger.y { xs.append(x); ys.append(y) }
                }
                if let x = report.pointer?.x, let y = report.pointer?.y { xs.append(x); ys.append(y) }
            }
            let x = try XCTUnwrap(median(xs), "take \(corner.number) has no positions")
            let y = try XCTUnwrap(median(ys), "take \(corner.number) has no positions")
            return CalibrationTap(target: corner.target, glass: point(x, y))
        }
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    func testBothRealPanelsAreFittedStraight() throws {
        let wch = try XCTUnwrap(SurveyFixtures.surveyA.touchscreen(vendorID: wchVendorID, productID: wchProductID))
        let ilitek = try XCTUnwrap(SurveyFixtures.surveyB.touchscreen(vendorID: ilitekVendorID, productID: ilitekProductID))
        for (name, panel) in [("wch.cn", wch), ("ILITEK", ilitek)] {
            let fit = try fitted(cornerTaps(panel), name)
            XCTAssertEqual(fit.orientation, .asFitted, name)
            assertRect(fit.alignment.pictureRect, GlassAlignment.wholeGlass.pictureRect, accuracy: 0.05, name)
            XCTAssertLessThanOrEqual(fit.error, Calibration.largestError, name)
        }
    }
}
