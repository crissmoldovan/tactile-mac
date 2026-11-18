import XCTest
@testable import TactileGestures

final class OneFingerTests: XCTestCase {

    func testTapClicksWhereTheFingerLanded() {
        let s = TouchScript()
        s.frame([(0, 100, 100)])
        s.frame(after: 0.08, [(0, 100.5, 100.5)])
        s.lift(after: 0.02)
        XCTAssertEqual(s.names, ["session began", "move", "click 1"])
        XCTAssertEqual(s.actions.last, .click(at: TouchScript.at(100, 100), count: 1))
    }

    /// With long-press off. With it on, as by default, this is a right-click: see LongPressTests.
    func testLongStillPressStillClicks() {
        var options = GestureOptions()
        options.longPress = false
        let s = TouchScript(options: options)
        s.frame([(0, 100, 100)])
        s.wait(1)
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move", "click 1"])
    }

    func testMovementWithinTheSlopIsStillATap() {
        let s = TouchScript()
        s.frame([(0, 100, 100)])
        s.move([(0, (100, 100), (102, 101))], steps: 5)
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move", "click 1"])
    }

    func testQuickTapsInOnePlaceCountUp() {
        let s = TouchScript()
        for _ in 0..<3 {
            s.frame(after: 0.15, [(0, 100, 100)])
            s.lift(after: 0.05)
        }
        XCTAssertEqual(s.clickCounts, [1, 2, 3])
        XCTAssertEqual(s.names.filter { $0 == "session began" }.count, 1)
    }

    func testTapsFarApartAreSeparateClicks() {
        let s = TouchScript()
        s.frame([(0, 100, 100)])
        s.lift(after: 0.05)
        s.frame(after: 0.1, [(0, 120, 100)])
        s.lift(after: 0.05)
        XCTAssertEqual(s.clickCounts, [1, 1])
    }

    func testMovingFingerDragsWhenTheIntentIsDrag() {
        let s = TouchScript(intent: .drag)
        s.frame([(0, 100, 100)])
        s.move([(0, (100, 100), (140, 100))], steps: 10)
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move", "press 1", "drag", "release"])
        XCTAssertTrue(s.actions.contains(.press(at: TouchScript.at(100, 100), count: 1)))
        XCTAssertEqual(s.actions.last, .release(at: TouchScript.at(140, 100)))
    }

    func testMovingFingerScrollsWhenTheIntentIsScroll() {
        let s = TouchScript(intent: .scroll)
        s.frame([(0, 100, 100)])
        s.move([(0, (100, 100), (100, 160))], steps: 60, every: 0.02)  // 50 mm/s: too slow to coast
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move", "scroll began", "scroll changed", "scroll ended"])
        XCTAssertEqual(s.totalScroll.dy, 60 / 300, accuracy: 1e-9)  // content follows the finger
        XCTAssertEqual(s.totalScroll.dx, 0, accuracy: 1e-9)
    }

    func testRestingFirstAlwaysDrags() {
        let s = TouchScript(intent: .scroll)
        s.frame([(0, 100, 100)])
        s.wait(0.5)
        s.move([(0, (100, 100), (130, 100))], steps: 10)
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move", "press 1", "drag", "release"])
        XCTAssertTrue(s.intentRequests.isEmpty)
    }

    func testIntentIsAskedOnceWithTheLandingPoint() {
        let s = TouchScript(intent: .scroll)
        s.frame([(0, 100, 100)])
        s.move([(0, (100, 100), (100, 150))], steps: 10)
        s.lift()
        XCTAssertEqual(s.intentRequests, [TouchScript.at(100, 100)])
    }

    func testTapsNeverAskForTheIntent() {
        let s = TouchScript(intent: .scroll)
        s.frame([(0, 100, 100)])
        s.lift(after: 0.1)
        XCTAssertTrue(s.intentRequests.isEmpty)
    }

    func testTapThenDragPressesWithCountTwo() {
        let s = TouchScript(intent: .drag)
        s.frame([(0, 100, 100)])
        s.lift(after: 0.05)
        s.frame(after: 0.1, [(0, 100, 100)])
        s.move([(0, (100, 100), (130, 100))], steps: 10)
        s.lift()
        XCTAssertTrue(s.actions.contains(.press(at: TouchScript.at(100, 100), count: 2)))
    }

    func testASecondFingerCancelsAPendingTap() {
        let s = TouchScript()
        s.frame([(0, 100, 100)])
        s.frame(after: 0.05, [(0, 100, 100), (1, 300, 200)])
        s.lift(after: 0.05)
        XCTAssertFalse(s.names.contains("click 1"))
    }

    func testARepeatedContactIDInOneReportCountsAsOneFinger() {
        let plain = TouchScript()
        plain.frame([(0, 100, 100)])
        plain.lift(after: 0.05)

        let doubled = TouchScript()
        doubled.frame([(0, 100, 100), (0, 100, 100)])
        doubled.lift(after: 0.05)

        XCTAssertEqual(doubled.names, plain.names)
    }

    func testAFrameWithNoSurfaceSizeKeepsTheLastOne() {
        let s = TouchScript(intent: .drag)
        s.frame([(0, 100, 100)])
        // 10 mm on the 500 mm surface. With no size, it must still be measured against 500 × 300.
        s.send(TouchFrame(time: s.time + 0.01,
                          fingers: [Finger(id: 0, location: TouchScript.at(110, 100))],
                          surfaceSize: .zero))
        XCTAssertTrue(s.names.contains("press 1"))
    }

    func testARepeatedContactIDMidDragStillDrags() {
        let plain = TouchScript(intent: .drag)
        plain.frame([(0, 100, 100)])
        plain.frame([(0, 110, 100)])
        plain.frame([(0, 120, 100)])

        let doubled = TouchScript(intent: .drag)
        doubled.frame([(0, 100, 100)])
        doubled.frame([(0, 110, 100)])
        doubled.frame([(0, 120, 100), (0, 120, 100)])

        XCTAssertEqual(doubled.actions, plain.actions)
    }
}
