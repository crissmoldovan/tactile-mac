// The set-up flow's rules beyond the plan's table: what a touch is, which displays can be
// candidates, displays changing mid-flow, and calls made in the wrong step or after the end.

import CoreGraphics
import Foundation
@testable import TactileApp
import TactileReading
import TactileScreens
import XCTest

private typealias Desk = SetUpDesk
private typealias Driver = FlowDriver

private let targets = Calibration.targets
private let middle = CGPoint(x: 0.5, y: 0.5)

final class SetUpFlowRuleTests: XCTestCase {

    // MARK: - What a touch is

    func testAFingerAlreadyDownWhenTheFlowStartsIsNotATouch() throws {
        // Its frames keep coming, from just before the start: in a full set-up's corners.
        let taps = Desk.cornerTaps(on: Desk.hdmi)
        var driver = try Driver(Desk.start())
        for i in -1...20 {
            let t = Double(i) / 10
            driver.wait(until: max(0, t))
            driver.finger(t, at: taps[0])
        }
        driver.lift(2.05)
        XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi))

        // Its first frame just after the start.
        driver = try Driver(Desk.start())
        driver.finger(0.05, at: taps[0])
        driver.wait(until: 2)
        driver.finger(2, at: taps[0])
        driver.lift(2.1)
        XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi))

        // The next landing is a tap.
        driver.tap(taps[0], at: 2.5)
        XCTAssertEqual(driver.step, .corners(display: 3, target: targets[1], index: 1, problem: nil))
    }

    func testAFingerRestingWhenTheFlowStartsIsNotATouchForASecond() throws {
        // A panel silent with the finger down for 0.45 s, longer than a reaction: still not a tap.
        let taps = Desk.cornerTaps(on: Desk.hdmi)
        var driver = try Driver(Desk.start())
        driver.wait(until: 0.45)
        driver.finger(0.45, at: taps[0])
        driver.wait(until: 0.9)
        driver.finger(0.9, at: taps[0])
        driver.lift(1.0)
        XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi))
        // The same finger, lifted and landing again, is.
        driver.tap(taps[0], at: 1.5)
        XCTAssertEqual(driver.step, .corners(display: 3, target: targets[1], index: 1, problem: nil))

        // In a calibration too.
        var calibrating = try Driver(Desk.calibrating())
        calibrating.tap(taps[0], at: 0.6)
        XCTAssertEqual(calibrating.step, firstTarget(on: Desk.hdmi))
        calibrating.tap(taps[0], at: 1.2)
        XCTAssertEqual(calibrating.step, .corners(display: 3, target: targets[1], index: 1, problem: nil))
    }

    func testAFingerAlreadyDownWhenCalibratingStartsIsNotATap() throws {
        var driver = try Driver(Desk.calibrating())
        driver.finger(0.1, at: Desk.cornerTaps(on: Desk.hdmi)[0])
        driver.finger(1.0, at: Desk.cornerTaps(on: Desk.hdmi)[0])
        driver.lift(1.1)
        XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi))
    }

    func testAFrameTimedBeforeTheStartIsNoTap() throws {
        // Handed to the flow as it starts (fingers already down), or late: timed before it.
        let taps = Desk.cornerTaps(on: Desk.hdmi)
        var driver = try Driver(Desk.start())
        driver.finger(-0.2, at: taps[0])
        driver.wait(until: 1.5)
        driver.finger(1.5, at: taps[0])
        driver.lift(1.6)
        XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi), "the same fingers, until the glass clears")
        driver.tap(taps[0], at: 2)
        XCTAssertEqual(driver.step, .corners(display: 3, target: targets[1], index: 1, problem: nil))
    }

    func testAnIgnoredTouchStillCountsAsATouchForTheWait() throws {
        var driver = try Driver(Desk.calibrating())
        driver.tap(Desk.cornerTaps(on: Desk.hdmi)[0], at: 99)  // lifts at 99.1
        driver.finger(99.2, at: middle)  // 0.1 s after the target moved: no tap
        driver.lift(99.3)
        XCTAssertEqual(driver.wait(until: 219.1), .stillRunning, "two minutes from the ignored landing, not the tap")
        XCTAssertEqual(driver.wait(until: 219.3), .finished(nil))
    }

    func testATapLandingJustAfterTheTargetMovedIsIgnored() throws {
        let taps = Desk.cornerTaps(on: Desk.hdmi)
        var driver = try Driver(Desk.calibrating())
        driver.tap(taps[0], at: 1)  // lifts at 1.1
        // A double tap: its second half lands 0.2 s after the second target appeared.
        driver.tap(taps[0], at: 1.3)
        XCTAssertEqual(driver.step, .corners(display: 3, target: targets[1], index: 1, problem: nil))
        driver.taps(Array(taps[1...]), from: 2)
        XCTAssertEqual(driver.step, .check(display: 3))
    }

    func testARefusedTapIsNotAChange() throws {
        // The target stays where it was, so the next tap may come straight away.
        let taps = Desk.cornerTaps(on: Desk.hdmi)
        var driver = try Driver(Desk.calibrating())
        driver.frame(1, [Contact(id: 1, position: taps[0]), Contact(id: 2, position: middle)])
        driver.lift(1.1)
        driver.tap(taps[0], at: 1.15)
        XCTAssertEqual(driver.step, .corners(display: 3, target: targets[1], index: 1, problem: nil))
    }

    func testATapIsTheMeanOfItsPositions() throws {
        let taps = Desk.cornerTaps(on: Desk.hdmi)
        var driver = try Driver(Desk.calibrating())
        // Lands 0.4% (1.9 mm) right of the place, ends as far left of it: the mean is the place.
        driver.finger(1.0, at: CGPoint(x: taps[0].x + 0.004, y: taps[0].y))
        driver.finger(1.05, at: taps[0])
        driver.finger(1.1, at: CGPoint(x: taps[0].x - 0.004, y: taps[0].y))
        driver.lift(1.15)
        driver.taps(Array(taps[1...]), from: 2)
        assertOutcome(
            driver.press { $0.done() }, display: DisplayIdentity(Desk.hdmi), orientation: .asFitted,
            rect: Desk.wholeGlass, diagonal: nil, accuracy: 1e-12)
    }

    func testAnotherFingerTakingOverMidTapIsTooManyFingers() throws {
        let p = Desk.cornerTaps(on: Desk.hdmi)[0]
        var driver = try Driver(Desk.calibrating())
        // The panel gave a new contact ID with no clear frame between: another finger.
        driver.finger(1.0, at: p, id: 1)
        driver.finger(1.05, at: p, id: 2)
        driver.lift(1.1)
        XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi, problem: .tooManyFingers))

        // A second finger joining, then lifting first.
        driver.finger(2.0, at: p, id: 1)
        driver.frame(2.05, [Contact(id: 1, position: p), Contact(id: 2, position: middle)])
        driver.finger(2.1, at: p, id: 1)
        driver.lift(2.15)
        XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi, problem: .tooManyFingers))
    }

    func testAPositionOffTheGlassIsTakenAtItsEdge() throws {
        // As the reader clamps; not relied on. 1.4 and 1.0 are the same point of the glass.
        var driver = try Driver(Desk.calibrating())
        driver.finger(1.0, at: CGPoint(x: 1.4, y: 0.5))
        driver.finger(1.05, at: CGPoint(x: 1.0, y: 0.5))
        driver.lift(1.1)
        XCTAssertEqual(driver.step, .corners(display: 3, target: targets[1], index: 1, problem: nil))
    }

    func testAPositionThatIsNotANumberIsNoTap() throws {
        let p = Desk.cornerTaps(on: Desk.hdmi)[0]
        for bad in [CGFloat.nan, .infinity, -.infinity] {
            var driver = try Driver(Desk.calibrating())
            driver.finger(1.0, at: CGPoint(x: bad, y: 0.5))
            driver.finger(1.05, at: p)
            driver.lift(1.1)
            XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi), "\(bad) landing")

            driver.finger(2.0, at: p)
            driver.finger(2.05, at: CGPoint(x: p.x, y: bad))
            driver.finger(2.1, at: p)
            driver.lift(2.15)
            XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi), "\(bad) mid-tap")
        }
    }

    // MARK: - The calibration checks deferred from Delivery 2a

    func testEveryTargetOfferedIsOnThePicture() throws {
        XCTAssertEqual(SetUpFlow.targets, Calibration.targets, "all four, in order")
        var offered: [CGPoint] = []
        var driver = try Driver(Desk.calibrating())
        for (i, tap) in Desk.cornerTaps(on: Desk.hdmi).enumerated() {
            guard case .corners(_, let target, _, _) = driver.step else { return XCTFail("\(driver.step)") }
            offered.append(target)
            driver.tap(tap, at: 1 + Double(i))
        }
        XCTAssertEqual(offered, Calibration.targets)
        for target in offered {
            XCTAssertTrue((0...1).contains(target.x) && (0...1).contains(target.y), "\(target)")
        }
    }

    func testATapFarFromItsFittedPlaceRefusesTheRound() {
        // As the fit would give it: perfect taps of the whole glass, as fitted, on a 527 × 296 mm glass.
        let glass = CGSize(width: 527, height: 296)
        let fit = Calibration.Fit(orientation: .asFitted, alignment: .wholeGlass, error: 0)
        let good = Calibration.targets.map { CalibrationTap(target: $0, glass: $0) }
        XCTAssertTrue(SetUpFlow.tapsLieNearTheirTargets(good, under: fit, glassMM: glass))

        var near = good
        near[2].glass.x += 7.9 / 527
        XCTAssertTrue(SetUpFlow.tapsLieNearTheirTargets(near, under: fit, glassMM: glass))

        var wild = good
        wild[2].glass.x += 8.1 / 527
        XCTAssertFalse(SetUpFlow.tapsLieNearTheirTargets(wild, under: fit, glassMM: glass), "one tap beyond 8 mm")

        // Each within 8 mm, but all of them 6.5 mm out: spread too far.
        func lowered(by mm: CGFloat) -> [CalibrationTap] {
            good.map { CalibrationTap(target: $0.target, glass: CGPoint(x: $0.glass.x, y: $0.glass.y + mm / 296)) }
        }
        let spread = lowered(by: 6.5)
        XCTAssertFalse(SetUpFlow.tapsLieNearTheirTargets(spread, under: fit, glassMM: glass), "spread beyond 6 mm")
        let tight = lowered(by: 5.9)
        XCTAssertTrue(SetUpFlow.tapsLieNearTheirTargets(tight, under: fit, glassMM: glass), "spread within 6 mm")

        var broken = good
        broken[0].glass.y = .nan
        XCTAssertFalse(SetUpFlow.tapsLieNearTheirTargets(broken, under: fit, glassMM: glass))

        // Through an orientation: the distance is on the glass in its own axes, whichever way it is
        // fitted. Its y axis is 296 mm long.
        let turned = Orientation(quarterTurns: 1, isFlipped: true)
        let turnedFit = Calibration.Fit(orientation: turned, alignment: .wholeGlass, error: 0)
        var turnedTaps = Calibration.targets.map { CalibrationTap(target: $0, glass: turned.inverse($0)) }
        XCTAssertTrue(SetUpFlow.tapsLieNearTheirTargets(turnedTaps, under: turnedFit, glassMM: glass))
        turnedTaps[1].glass.y += 7.9 / 296
        XCTAssertTrue(SetUpFlow.tapsLieNearTheirTargets(turnedTaps, under: turnedFit, glassMM: glass))
        turnedTaps[1].glass.y += 0.2 / 296
        XCTAssertFalse(SetUpFlow.tapsLieNearTheirTargets(turnedTaps, under: turnedFit, glassMM: glass))
    }

    // MARK: - Size

    func testTheTouchscreensReportIsLaidAlongTheDisplay() throws {
        // A strip-sized glass whose own x axis runs along its short side: 91 × 217 mm as it
        // reports. Fitted a quarter turn round on "12.3FHD", its 217 mm lie along the 1600 points.
        let glass = CGSize(width: 91, height: 217)
        let turnedFit = Orientation(quarterTurns: 1, isFlipped: false)
        var driver = try Driver(Desk.start(candidates: [Desk.strip], glass: glass))
        driver.taps(Desk.cornerTaps(on: Desk.strip, orientation: turnedFit), from: 2)
        guard case .size(display: 4, _, let offered?, _) = driver.step else { return XCTFail("\(driver.step)") }
        XCTAssertEqual(offered, 9.26, accuracy: 0.01)

        // Fitted straight, those 91 mm would lie along the 1600 points: 446 points per inch.
        driver = try Driver(Desk.start(candidates: [Desk.strip], glass: glass))
        driver.taps(Desk.cornerTaps(on: Desk.strip), from: 2)
        guard case .size(display: 4, _, nil, _) = driver.step else { return XCTFail("\(driver.step)") }

        // The same glass, fitted the same quarter turn, on the display turned in macOS: the frame
        // turns too, and the 217 mm lie along its 1600 points again.
        let stripTurned = changed(Desk.strip) {
            $0.frame = CGRect(x: 228, y: 1329, width: 600, height: 1600)
            $0.sizeMM = CGSize(width: 90, height: 240)
            $0.rotation = 270
        }
        driver = try Driver(Desk.start(candidates: [stripTurned], glass: glass))
        driver.taps(Desk.cornerTaps(on: stripTurned, orientation: turnedFit), from: 2)
        guard case .size(display: 4, let display?, let turned?, _) = driver.step else {
            return XCTFail("\(driver.step)")
        }
        XCTAssertEqual(turned, 9.26, accuracy: 0.01)
        XCTAssertEqual(display, 10.1, accuracy: 0.05, "the strip's display reports 10.1″")
    }

    func testTheTouchscreensReportIsOfferedOnlyOnADisplayOfItsShape() throws {
        // The ILITEK's 476 × 268 mm (16:9) on "12.3FHD" (8:3): plausible by density, not its glass.
        var driver = try Driver(Desk.start(candidates: [Desk.strip]))
        driver.taps(Desk.cornerTaps(on: Desk.strip), from: 2)
        guard case .size(display: 4, _, touchscreenReports: nil, _) = driver.step else {
            return XCTFail("\(driver.step)")
        }

        // The strip's own glass, 217 × 91 mm, is within 15% of the picture's shape.
        driver = try Driver(Desk.start(candidates: [Desk.strip], glass: Desk.stripGlass))
        driver.taps(Desk.cornerTaps(on: Desk.strip), from: 2)
        guard case .size(display: 4, _, let offered?, _) = driver.step else { return XCTFail("\(driver.step)") }
        XCTAssertEqual(offered, 9.26, accuracy: 0.01)
    }

    func testAPlausibleDensityOutsideThePlausibleDiagonalsIsNotOffered() throws {
        // 300 × 200 points reporting 60 × 40 mm: 127 points per inch, 2.8″, which the size step
        // could never take back.
        let small = changed(Desk.display) {
            $0.frame = CGRect(x: -300, y: 24, width: 300, height: 200)
            $0.sizeMM = CGSize(width: 60, height: 40)
        }
        var driver = try Driver(Desk.start(candidates: [small], glass: CGSize(width: 60, height: 40)))
        driver.taps(Desk.cornerTaps(on: small), from: 2)
        XCTAssertEqual(driver.step, .size(display: 5, displayReports: nil, touchscreenReports: nil, current: nil))
    }

    // MARK: - Which displays can be candidates

    func testNoCandidateNoFlow() {
        XCTAssertNil(SetUpFlow(Desk.start(candidates: []), at: Driver.t0))
        XCTAssertNil(SetUpFlow(Desk.start(), at: .nan), "a start that isn't a time")
        XCTAssertNil(SetUpFlow(Desk.start(), at: .infinity))
    }

    func testTheBuiltInDisplayIsNeverACandidate() throws {
        XCTAssertNil(SetUpFlow(Desk.start(candidates: [Desk.builtIn]), at: Driver.t0))
        XCTAssertNil(SetUpFlow(Desk.start(candidates: [Desk.builtIn, Desk.hdmi]), at: Driver.t0), "not the only one")
        XCTAssertNil(SetUpFlow(Desk.calibrating(Desk.builtIn), at: Driver.t0))
        XCTAssertFalse(SetUpFlow.canStartFull(on: Desk.builtIn, among: Desk.all))
        XCTAssertTrue(SetUpFlow.canStartFull(on: Desk.hdmi, among: Desk.all))
    }

    func testADisplayUnderAnIDTwiceIsNoCandidate() throws {
        // Two different displays under one ID: which one is meant can't be known.
        let impostor = changed(Desk.display) { $0.displayID = Desk.hdmi.displayID }
        XCTAssertFalse(SetUpFlow.canStartFull(on: Desk.hdmi, among: Desk.all + [impostor]))
        XCTAssertFalse(SetUpFlow.canStartFull(on: Desk.hdmi, among: [Desk.builtIn]), "not connected")
    }

    func testADisplayWithNowhereToLandIsNoCandidate() throws {
        let flat = changed(Desk.display) { $0.frame = CGRect(x: 0, y: 0, width: 0, height: 1280) }
        XCTAssertNil(SetUpFlow(Desk.start(candidates: [flat], all: Desk.all(with: flat)), at: Driver.t0))
        XCTAssertFalse(SetUpFlow.canStartFull(on: flat, among: Desk.all(with: flat)))
    }

    func testAMirroringDisplayIsSetUpThroughThePictureItShows() throws {
        // "12.3FHD" mirrors "HDMI": it shows HDMI's picture, and its taps are judged on it.
        let mirroring = changed(Desk.strip) { $0.mirrors = Desk.hdmi.displayID }
        let all = [Desk.builtIn, Desk.lg, Desk.hdmi, mirroring, Desk.display]
        XCTAssertTrue(SetUpFlow.canStartFull(on: mirroring, among: all))
        let taps = Desk.cornerTaps(on: mirroring, content: Desk.hdmi)
        var driver = try Driver(Desk.start(candidates: [mirroring], all: all, glass: Desk.stripGlass))
        XCTAssertEqual(driver.step, firstTarget(on: mirroring))
        driver.taps(taps, from: 1)
        guard case .size(display: 4, _, _, _) = driver.step else { return XCTFail("\(driver.step)") }
    }

    /// Fix round 1, item 1: set-up mode offers no display whose picture another candidate also shows.
    func testSetUpModesCandidatesAreAloneWithTheirPicture() {
        XCTAssertEqual(SetUpFlow.setUpModeCandidates(among: Desk.all).map(\.displayID), [2, 3, 4, 5])
        let stripMirroringHDMI = changed(Desk.strip) { $0.mirrors = Desk.hdmi.displayID }
        XCTAssertEqual(SetUpFlow.setUpModeCandidates(among: Desk.all(with: stripMirroringHDMI)).map(\.displayID), [2, 5],
                       "neither member of the mirror set")
        let both = [Desk.builtIn, Desk.lg, changed(Desk.hdmi) { $0.mirrors = 2 }, changed(Desk.strip) { $0.mirrors = 2 }]
        XCTAssertEqual(SetUpFlow.setUpModeCandidates(among: both).map(\.displayID), [], "three showing one picture")
        let thirdOnly = [Desk.builtIn, Desk.lg, changed(Desk.hdmi) { $0.mirrors = 1 }, changed(Desk.strip) { $0.mirrors = 1 }]
        XCTAssertEqual(SetUpFlow.setUpModeCandidates(among: thirdOnly).map(\.displayID), [2],
                       "two mirroring the built-in display show one picture")
        let stripMirroringBuiltIn = changed(Desk.strip) { $0.mirrors = Desk.builtIn.displayID }
        XCTAssertEqual(SetUpFlow.setUpModeCandidates(among: Desk.all(with: stripMirroringBuiltIn)).map(\.displayID),
                       [2, 3, 4, 5], "alone with the built-in display's picture: it stays")
    }

    func testNumbersThatAreNotNumbersAreLeftOutSoAFlowEqualsItself() throws {
        let broken = changed(Desk.display) { $0.sizeMM.width = .nan }
        XCTAssertNil(SetUpFlow(Desk.start(candidates: [broken], all: Desk.all(with: broken)), at: Driver.t0))
        XCTAssertFalse(SetUpFlow.canStartFull(on: broken, among: Desk.all(with: broken)))
        let flow = try XCTUnwrap(SetUpFlow(
            Desk.start(
                candidates: [Desk.hdmi], all: Desk.all + [broken], glass: CGSize(width: CGFloat.nan, height: 1),
                diagonal: .nan),
            at: Driver.t0))
        XCTAssertEqual(flow, flow)
        XCTAssertEqual(flow.snapshot.step, firstTarget(on: Desk.hdmi))

        var driver = try Driver(
            Desk.start(candidates: [Desk.hdmi], glass: CGSize(width: CGFloat.nan, height: 1), diagonal: .nan))
        driver.taps(Desk.cornerTaps(on: Desk.hdmi), from: 2)
        guard case .size(display: 3, _, touchscreenReports: nil, current: nil) = driver.step else {
            return XCTFail("\(driver.step)")
        }
        XCTAssertEqual(driver.flow, driver.flow)
    }

    func testAMirroringDisplayWhoseOriginalIsMissingIsNoCandidate() {
        let mirroring = changed(Desk.strip) { $0.mirrors = 99 }
        XCTAssertNil(SetUpFlow(Desk.start(candidates: [mirroring]), at: Driver.t0))
    }

    func testTheTargetsAllowForAMirroredDisplay() throws {
        // The strip shows the built-in display's picture, with bars at its sides.
        let mirroring = changed(Desk.strip) { $0.mirrors = Desk.builtIn.displayID }
        let all = [Desk.builtIn, mirroring]
        let orientation = Orientation(quarterTurns: 2, isFlipped: false)
        let taps = Desk.cornerTaps(on: mirroring, content: Desk.builtIn, orientation: orientation, rect: Desk.offCentre)
        var driver = try Driver(
            Desk.start(.calibrate, candidates: [mirroring], all: all, current: Desk.pairing(Desk.strip)))
        driver.taps(taps, from: 1)
        XCTAssertEqual(driver.step, .check(display: 4))
        XCTAssertEqual(driver.flow.checkMapping?.content, Desk.builtIn)
        assertTapsLandOnTheirTargets(driver.flow.checkMapping, taps)
        assertOutcome(
            driver.press { $0.done() }, display: DisplayIdentity(Desk.strip), orientation: orientation,
            rect: Desk.offCentre, diagonal: nil)
    }

    func testCalibrateAndTestNeedTheirOwnDisplayAlone() {
        for purpose in [SetUpPurpose.calibrate, .test] {
            XCTAssertNil(SetUpFlow(Desk.start(purpose, candidates: [Desk.hdmi]), at: Driver.t0), "unpaired \(purpose)")
            XCTAssertNil(
                SetUpFlow(
                    Desk.start(purpose, candidates: [Desk.hdmi], current: Desk.pairing(Desk.strip)), at: Driver.t0),
                "another display \(purpose)")
            XCTAssertNil(
                SetUpFlow(
                    Desk.start(purpose, candidates: [Desk.hdmi, Desk.strip], current: Desk.pairing(Desk.hdmi)),
                    at: Driver.t0),
                "two displays \(purpose)")
            XCTAssertNotNil(
                SetUpFlow(
                    Desk.start(purpose, candidates: [Desk.hdmi], current: Desk.pairing(Desk.hdmi)), at: Driver.t0),
                "\(purpose)")
        }
        // The same panel under a new UUID is still its own display: matched by its fingerprint.
        var renamed = Desk.pairing(Desk.hdmi)
        renamed.display.uuid = ""
        XCTAssertNotNil(SetUpFlow(Desk.start(.calibrate, candidates: [Desk.hdmi], current: renamed), at: Driver.t0))
    }

    func testATwinIsNotItsOwnDisplayWhileTheStoredOneIsConnected() {
        // The same model and serial as HDMI, another UUID: matched by its fingerprint alone.
        let twin = changed(Desk.hdmi) {
            $0.displayID = 9
            $0.uuid = "9C2D0E10-0000-0000-0A20-0104B53C2278"
        }
        let hdmiAway = Desk.all.filter { $0.displayID != Desk.hdmi.displayID } + [twin]
        for purpose in [SetUpPurpose.calibrate, .test] {
            XCTAssertNil(
                SetUpFlow(
                    Desk.start(purpose, candidates: [twin], all: Desk.all + [twin], current: Desk.pairing(Desk.hdmi)),
                    at: Driver.t0),
                "\(purpose): HDMI itself is connected")
            XCTAssertNotNil(
                SetUpFlow(
                    Desk.start(purpose, candidates: [twin], all: hdmiAway, current: Desk.pairing(Desk.hdmi)),
                    at: Driver.t0),
                "\(purpose): HDMI away, its twin by fingerprint")
        }
    }

    // MARK: - Displays changing

    func testADisplayJoiningMidRoundChangesNothing() throws {
        let newcomer = changed(Desk.lg) {
            $0.displayID = 9
            $0.uuid = "9E6D5B14-0000-0000-2B1F-0104B53C2278"
        }
        var driver = try Driver(Desk.start(candidates: [Desk.strip]))
        driver.tap(Desk.cornerTaps(on: Desk.strip)[0], at: 5)
        driver.finger(6, at: Desk.cornerTaps(on: Desk.strip)[1])
        let before = driver.flow.snapshot
        driver.call { $0.displaysChanged(Desk.all + [newcomer], at: Driver.time(6.05)) }
        XCTAssertEqual(driver.flow.snapshot, before, "in the corners step")
        driver.lift(6.1)
        driver.taps(Array(Desk.cornerTaps(on: Desk.strip)[2...]), from: 7)
        guard case .size(display: 4, _, _, _) = driver.step else {
            return XCTFail("the tap in progress didn't count: \(driver.step)")
        }
    }

    func testTheDisplayTurningMidRoundStartsTheCornersAgain() throws {
        var driver = try Driver(Desk.calibrating())
        driver.taps(Array(Desk.cornerTaps(on: Desk.hdmi)[..<2]), from: 1)
        driver.finger(3, at: Desk.cornerTaps(on: Desk.hdmi)[2])
        let turned = Desk.all.map { $0.displayID == Desk.hdmi.displayID ? Desk.hdmiTurned : $0 }
        XCTAssertEqual(driver.call { $0.displaysChanged(turned, at: Driver.time(3.05)) }, .stillRunning)
        XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi), "the targets moved on the panel")
        driver.lift(3.1)
        XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi), "the tap in progress was for the old picture")

        let taps = Desk.cornerTaps(on: Desk.hdmiTurned, rect: Desk.offCentre)
        driver.taps(taps, from: 4)
        assertTapsLandOnTheirTargets(driver.flow.checkMapping, taps)
        assertOutcome(
            driver.press { $0.done() }, display: DisplayIdentity(Desk.hdmi), orientation: .asFitted,
            rect: Desk.offCentre, diagonal: nil)
    }

    func testTheDisplayMovingInTheArrangementKeepsTheTaps() throws {
        var driver = try Driver(Desk.calibrating())
        driver.taps(Array(Desk.cornerTaps(on: Desk.hdmi)[..<2]), from: 1)
        let moved = changed(Desk.hdmi) { $0.frame.origin = CGPoint(x: 3000, y: -500) }
        let all = Desk.all.map { $0.displayID == Desk.hdmi.displayID ? moved : $0 }
        driver.call { $0.displaysChanged(all, at: Driver.time(3)) }
        XCTAssertEqual(driver.step, .corners(display: 3, target: targets[2], index: 2, problem: nil))
        driver.taps(Array(Desk.cornerTaps(on: Desk.hdmi)[2...]), from: 4)
        XCTAssertEqual(driver.flow.checkMapping?.display, moved, "the check maps onto where the display is now")
    }

    func testAnotherDisplayUnderTheSameIDHasGone() throws {
        var driver = try Driver(Desk.calibrating())
        driver.tap(Desk.cornerTaps(on: Desk.hdmi)[0], at: 1)
        let replaced = changed(Desk.display) { $0.displayID = Desk.hdmi.displayID }
        let all = [Desk.builtIn, Desk.lg, replaced, Desk.strip]
        XCTAssertEqual(driver.call { $0.displaysChanged(all, at: Driver.time(2)) }, .finished(nil))
    }

    func testTheCheckFollowsTheDisplay() throws {
        var driver = try Driver(Desk.start(.test, candidates: [Desk.hdmi], current: Desk.pairing(Desk.hdmi)))
        let turned = Desk.all.map { $0.displayID == Desk.hdmi.displayID ? Desk.hdmiTurned : $0 }
        XCTAssertEqual(driver.call { $0.displaysChanged(turned, at: Driver.time(1)) }, .stillRunning)
        XCTAssertEqual(driver.flow.checkMapping?.display, Desk.hdmiTurned)

        // Mirroring one that isn't there: nowhere certain to show a touch.
        let lost = Desk.all.map { $0.displayID == Desk.hdmi.displayID ? changed(Desk.hdmi) { $0.mirrors = 99 } : $0 }
        XCTAssertEqual(driver.call { $0.displaysChanged(lost, at: Driver.time(2)) }, .finished(nil))
    }

    // MARK: - Calls in the wrong step, and after the end

    func testConfirmSizeRedoOrDoneInTheWrongStepDoesNothing() throws {
        var driver = try Driver(Desk.start())
        let steps = [("corners", driver)]
        driver.taps(Desk.cornerTaps(on: Desk.hdmi), from: 2)
        let size = driver
        driver.call { $0.confirmSize(inches: 20) }
        let check = driver

        for (name, driver) in steps + [("size", size), ("check", check)] {
            let calls: [(String, (inout SetUpFlow) -> SetUpFlow.Event)] = [
                ("confirmSize", { $0.confirmSize(inches: 22) }), ("redo", { $0.redo() }), ("done", { $0.done() }),
            ]
            for (call, action) in calls {
                if (name, call) == ("size", "confirmSize") || (name, call) == ("check", "redo")
                    || (name, call) == ("check", "done")
                {
                    continue
                }
                var flow = driver.flow
                XCTAssertEqual(action(&flow), .stillRunning, "\(call) in \(name)")
                XCTAssertEqual(flow, driver.flow, "\(call) in \(name)")
            }
        }
    }

    func testEveryCallAfterTheEndKeepsTheEnd() throws {
        var driver = try Driver(Desk.start())
        driver.taps(Desk.cornerTaps(on: Desk.hdmi), from: 2)
        driver.press { $0.confirmSize(inches: 23.8) }
        let end = driver.press { $0.done() }
        guard case .finished(.some) = end else { return XCTFail("\(end)") }
        XCTAssertNil(driver.flow.checkMapping, "nothing to map with once it has ended")
        let ended = driver.flow

        let calls: [(String, (inout SetUpFlow) -> SetUpFlow.Event)] = [
            ("handle", {
                $0.handle(ContactFrame(time: Driver.time(10), contacts: [Contact(id: 1, position: middle)]))
            }),
            ("lift", { $0.handle(ContactFrame(time: Driver.time(11), contacts: [])) }),
            ("tick", { $0.tick(at: Driver.time(500)) }),
            ("confirmSize", { $0.confirmSize(inches: 30) }),
            ("redo", { $0.redo() }),
            ("done", { $0.done() }),
            ("cancel", { $0.cancel() }),
            ("displaysChanged", { $0.displaysChanged([], at: Driver.time(600)) }),
        ]
        for (name, call) in calls {
            var flow = ended
            XCTAssertEqual(call(&flow), end, name)
            XCTAssertEqual(flow, ended, name)
        }

        // Cancelled, the same.
        var cancelled = try XCTUnwrap(SetUpFlow(Desk.start(), at: Driver.t0))
        XCTAssertEqual(cancelled.cancel(), .finished(nil))
        let afterCancel = cancelled
        for (name, call) in calls {
            var flow = afterCancel
            XCTAssertEqual(call(&flow), .finished(nil), name)
            XCTAssertEqual(flow, afterCancel, name)
        }
    }

    func testTheCheckMappingIsNilBeforeTheCheck() throws {
        var driver = try Driver(Desk.start())
        XCTAssertNil(driver.flow.checkMapping, "corners")
        driver.taps(Desk.cornerTaps(on: Desk.hdmi), from: 2)
        XCTAssertNil(driver.flow.checkMapping, "size")
        driver.call { $0.confirmSize(inches: nil) }
        XCTAssertNotNil(driver.flow.checkMapping, "check")
    }

    // MARK: - Time

    func testAChangeACommandMakesIsTimedByWhatComesNext() throws {
        // Redo after half a minute of nothing: the flow's clock still says the last tap's lift.
        let taps = Desk.cornerTaps(on: Desk.hdmi)
        var driver = try Driver(Desk.calibrating())
        driver.taps(taps, from: 1)
        XCTAssertEqual(driver.step, .check(display: 3))
        driver.wait(until: 5)  // the check has been shown a while: the last the flow hears for half a minute
        driver.call { $0.redo() }  // at about 34 s
        driver.tap(taps[0], at: 34.1)
        XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi), "the frame that tells it the time is the change")
        driver.tap(taps[0], at: 34.3)
        XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi), "0.2 s after it")
        driver.tap(taps[0], at: 34.6)
        XCTAssertEqual(driver.step, .corners(display: 3, target: targets[1], index: 1, problem: nil))

        // A tick tells it the time as well.
        driver = try Driver(Desk.calibrating())
        driver.taps(taps, from: 1)
        driver.wait(until: 5)
        driver.call { $0.redo() }
        driver.call { $0.tick(at: Driver.time(34)) }
        driver.tap(taps[0], at: 34.1)
        XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi))
        driver.tap(taps[0], at: 34.5)
        XCTAssertEqual(driver.step, .corners(display: 3, target: targets[1], index: 1, problem: nil))

        // The size answered after 100 s: two minutes from the answer, not from the last tap.
        driver = try Driver(Desk.start())
        driver.taps(taps, from: 2)  // the last lifts at 5.1
        driver.call { $0.confirmSize(inches: nil) }
        XCTAssertEqual(driver.call { $0.tick(at: Driver.time(105.1)) }, .stillRunning)
        XCTAssertEqual(driver.call { $0.tick(at: Driver.time(225)) }, .stillRunning)
        XCTAssertEqual(driver.call { $0.tick(at: Driver.time(225.2)) }, .finished(nil))
    }

    func testDoneOrRedoTooSoonAfterTheCheckAppearsDoesNothing() throws {
        // Return pressed twice on the size card: the second press lands on the check, 0.05 s later.
        var driver = try Driver(Desk.start())
        driver.taps(Desk.cornerTaps(on: Desk.hdmi), from: 2)
        XCTAssertEqual(driver.press { $0.confirmSize(inches: 23.8) }, .stillRunning)
        XCTAssertEqual(driver.step, .check(display: 3))
        XCTAssertEqual(driver.press(after: 0.05) { $0.done() }, .stillRunning, "Done 0.05 s after the check appeared")
        XCTAssertEqual(driver.press(after: 0.05) { $0.redo() }, .stillRunning, "Redo 0.1 s after")
        XCTAssertEqual(driver.step, .check(display: 3), "the check stays")
        guard case .finished(.some) = driver.press(after: 0.4, { $0.done() }) else {
            return XCTFail("Done 0.5 s after the check appeared: \(driver.last)")
        }

        // While the change to the check is still pending (no frame or tick since the size was
        // answered), the check hasn't been seen at all, however long the size card was shown.
        driver = try Driver(Desk.start())
        driver.taps(Desk.cornerTaps(on: Desk.hdmi), from: 2)  // the last lifts at 5.1
        driver.wait(until: 8)
        driver.call { $0.confirmSize(inches: nil) }
        XCTAssertEqual(driver.call { $0.done() }, .stillRunning, "pending")
        XCTAssertEqual(driver.call { $0.redo() }, .stillRunning, "pending")
        driver.call { $0.tick(at: Driver.time(9)) }  // the check appears now
        XCTAssertEqual(driver.call { $0.done() }, .stillRunning, "0 s after")
        driver.call { $0.tick(at: Driver.time(9.5)) }
        guard case .finished(.some) = driver.call({ $0.done() }) else { return XCTFail("\(driver.last)") }

        // After the corners, for a calibration: the check appears as the last tap lifts.
        driver = try Driver(Desk.calibrating())
        driver.taps(Desk.cornerTaps(on: Desk.hdmi), from: 1)  // the last lifts at 4.1
        XCTAssertEqual(driver.press(after: 0.2) { $0.redo() }, .stillRunning)
        XCTAssertEqual(driver.step, .check(display: 3), "Redo 0.2 s after the check appeared")
        XCTAssertEqual(driver.press(after: 0.3) { $0.redo() }, .stillRunning)
        XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi), "Redo 0.5 s after")

        // A test's check appears as the flow starts.
        driver = try Driver(Desk.start(.test, candidates: [Desk.hdmi], current: Desk.pairing(Desk.hdmi)))
        XCTAssertEqual(driver.press(after: 0.1) { $0.done() }, .stillRunning)
        XCTAssertEqual(driver.press(after: 0.4) { $0.done() }, .finished(nil))
    }

    func testADoneOrRedoTooSoonIsToldApartFromOneTaken() throws {
        // What the model reads, at the command's moment, to log a Done or Redo it ignored as too soon.
        var driver = try Driver(Desk.start())
        driver.taps(Desk.cornerTaps(on: Desk.hdmi), from: 2)
        var tooSoon: [Bool] = []
        driver.press { tooSoon.append($0.isCheckTooRecent); return $0.confirmSize(inches: 23.8) }
        XCTAssertEqual(tooSoon, [false], "the size step: not the check")
        driver.press(after: 0.05) { tooSoon.append($0.isCheckTooRecent); return $0.done() }
        driver.press(after: 0.05) { tooSoon.append($0.isCheckTooRecent); return $0.redo() }
        XCTAssertEqual(tooSoon, [false, true, true], "Done 0.05 s and Redo 0.1 s after the check appeared")
        guard case .finished(.some) = driver.press(after: 0.4, { tooSoon.append($0.isCheckTooRecent); return $0.done() })
        else { return XCTFail("\(driver.last)") }
        XCTAssertEqual(tooSoon.last, false, "Done 0.5 s after: taken")

        // While the change to the check is pending, it hasn't been seen at all.
        driver = try Driver(Desk.start())
        driver.taps(Desk.cornerTaps(on: Desk.hdmi), from: 2)
        driver.wait(until: 8)
        driver.call { $0.confirmSize(inches: nil) }
        XCTAssertTrue(driver.flow.isCheckTooRecent, "pending")

        // A calibration's check, after the last tap.
        driver = try Driver(Desk.calibrating())
        driver.taps(Desk.cornerTaps(on: Desk.hdmi), from: 1)
        driver.press(after: 0.2) { tooSoon.append($0.isCheckTooRecent); return $0.redo() }
        XCTAssertEqual(tooSoon.last, true, "Redo 0.2 s after")
        driver.press(after: 0.3) { tooSoon.append($0.isCheckTooRecent); return $0.redo() }
        XCTAssertEqual(tooSoon.last, false, "Redo 0.5 s after: taken")
        XCTAssertFalse(driver.flow.isCheckTooRecent, "the corners again: not the check")

        // A test's check, as the flow starts.
        driver = try Driver(Desk.start(.test, candidates: [Desk.hdmi], current: Desk.pairing(Desk.hdmi)))
        driver.press(after: 0.1) { tooSoon.append($0.isCheckTooRecent); return $0.done() }
        XCTAssertEqual(tooSoon.last, true)
        driver.press(after: 0.4) { tooSoon.append($0.isCheckTooRecent); return $0.done() }
        XCTAssertEqual(tooSoon.last, false)
    }

    func testAFrameTimedBeforeACommandIsNoTap() throws {
        // Redo at 10 s; then a frame stamped 5 s, delivered late: from before the redo, not for it.
        let taps = Desk.cornerTaps(on: Desk.hdmi)
        var driver = try Driver(Desk.calibrating())
        driver.taps(taps, from: 1)
        driver.wait(until: 10)
        driver.call { $0.redo() }
        driver.finger(5.0, at: taps[0])
        driver.lift(5.1)
        XCTAssertEqual(driver.step, firstTarget(on: Desk.hdmi))
    }

    func testAContactRestingInTheCheckStepIsNoInput() throws {
        // A hand left on the glass, trembling half a millimetre: two minutes, and the flow ends.
        var driver = try Driver(Desk.start(.test, candidates: [Desk.hdmi], current: Desk.pairing(Desk.hdmi)))
        driver.finger(10, at: middle)
        for t in stride(from: 11.0, through: 129.0, by: 1) {
            driver.finger(t, at: CGPoint(x: 0.5 + 0.001 * sin(t), y: 0.5))
        }
        XCTAssertEqual(driver.finger(129.9, at: middle), .stillRunning)
        XCTAssertEqual(driver.finger(130.1, at: middle), .finished(nil), "a hand left on the glass")

        // Moving further than a tap may is input: someone is trying the touches out.
        driver = try Driver(Desk.start(.test, candidates: [Desk.hdmi], current: Desk.pairing(Desk.hdmi)))
        driver.finger(10, at: middle)
        driver.finger(100, at: CGPoint(x: 0.52, y: 0.5))  // 9.5 mm on the ILITEK's glass
        XCTAssertEqual(driver.finger(219.9, at: CGPoint(x: 0.52, y: 0.5)), .stillRunning)
        XCTAssertEqual(driver.finger(220.1, at: CGPoint(x: 0.52, y: 0.5)), .finished(nil))
    }

    func testEveryStepEndsAfterTwoMinutesWithoutInput() throws {
        // Corners: a tap is input; time after it is not.
        var driver = try Driver(Desk.calibrating())
        driver.tap(Desk.cornerTaps(on: Desk.hdmi)[0], at: 1)  // lifts at 1.1
        XCTAssertEqual(driver.call { $0.tick(at: Driver.time(121)) }, .stillRunning)
        XCTAssertEqual(driver.call { $0.tick(at: Driver.time(121.2)) }, .finished(nil), "corners")

        // Size: two minutes to answer.
        driver = try Driver(Desk.start())
        driver.taps(Desk.cornerTaps(on: Desk.hdmi), from: 2)  // the last lifts at 5.1
        guard case .size = driver.step else { return XCTFail("\(driver.step)") }
        XCTAssertEqual(driver.call { $0.tick(at: Driver.time(125)) }, .stillRunning)
        XCTAssertEqual(driver.call { $0.tick(at: Driver.time(125.2)) }, .finished(nil), "size")

        // Check: any touch is input, a finger held there included.
        driver = try Driver(Desk.start(.test, candidates: [Desk.hdmi], current: Desk.pairing(Desk.hdmi)))
        driver.finger(100, at: middle)
        driver.finger(200, at: CGPoint(x: 0.6, y: 0.5))
        XCTAssertEqual(driver.call { $0.tick(at: Driver.time(319.9)) }, .stillRunning)
        XCTAssertEqual(driver.call { $0.tick(at: Driver.time(320.1)) }, .finished(nil), "check")
    }

    func testTimeGoingBackMovesNothing() throws {
        let taps = Desk.cornerTaps(on: Desk.hdmi)
        var driver = try Driver(Desk.start())
        driver.tap(taps[0], at: 4)  // lifts at 4.1: the second target
        let second = driver.step
        XCTAssertEqual(driver.call { $0.tick(at: Driver.time(1)) }, .stillRunning)
        XCTAssertEqual(driver.call { $0.tick(at: .nan) }, .stillRunning)
        XCTAssertEqual(driver.call { $0.tick(at: -.infinity) }, .stillRunning)
        XCTAssertEqual(driver.step, second)

        // A landing timed before the change, or not timed at all, is no tap.
        driver.finger(2.5, at: taps[1])
        driver.lift(2.6)
        driver.call { $0.handle(ContactFrame(time: .nan, contacts: [Contact(id: 1, position: taps[1])])) }
        driver.call { $0.handle(ContactFrame(time: .nan, contacts: [])) }
        XCTAssertEqual(driver.step, second)

        // A tick far ahead ends a flow left alone that long.
        XCTAssertEqual(driver.call { $0.tick(at: Driver.time(60)) }, .stillRunning)
        XCTAssertEqual(driver.step, second)
        XCTAssertEqual(driver.call { $0.tick(at: .greatestFiniteMagnitude) }, .finished(nil))
    }
}
