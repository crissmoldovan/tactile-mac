import XCTest
@testable import TactileGestures

final class MomentumAndSessionTests: XCTestCase {

    /// One finger scrolls 40 mm down in 0.1 s (400 mm/s) and lifts.
    private func flick(_ s: TouchScript) {
        s.frame([(0, 100, 100)])
        s.move([(0, (100, 100), (100, 140))], steps: 10)
        s.lift()
    }

    func testFlickCoastsThenStops() {
        let s = TouchScript(intent: .scroll)
        flick(s)
        s.wait(2)
        XCTAssertEqual(s.names, ["session began", "move", "scroll began", "scroll changed", "scroll ended",
                                 "momentum began", "momentum changed", "momentum ended", "session ended"])
        XCTAssertFalse(s.momentumSteps.isEmpty)
        XCTAssertTrue(s.momentumSteps.allSatisfy { $0.dy > 0 && abs($0.dx) < 1e-9 })
    }

    func testSlowScrollDoesNotCoast() {
        let s = TouchScript(intent: .scroll)
        s.frame([(0, 100, 100)])
        s.move([(0, (100, 100), (100, 140))], steps: 50, every: 0.02)  // 40 mm/s
        s.lift()
        s.wait(1)
        XCTAssertFalse(s.names.contains("momentum began"))
        XCTAssertEqual(s.names.suffix(2), ["scroll ended", "session ended"])
    }

    func testScrollThatStopsBeforeLiftingDoesNotCoast() {
        let s = TouchScript(intent: .scroll)
        s.frame([(0, 100, 100)])
        s.move([(0, (100, 100), (100, 140))], steps: 10)
        for _ in 0..<15 { s.frame(after: 0.02, [(0, 100, 140)]) }
        s.lift()
        XCTAssertFalse(s.names.contains("momentum began"))
    }

    /// A tap that stops a coasting scroll only stops it: on a web page a click would follow the link
    /// under the finger.
    func testTouchingStopsMomentumWithoutStartingANewSession() {
        let s = TouchScript(intent: .scroll)
        flick(s)
        s.wait(0.1)
        s.frame([(0, 200, 200)])
        s.lift(after: 0.05)
        XCTAssertEqual(s.names, ["session began", "move", "scroll began", "scroll changed", "scroll ended",
                                 "momentum began", "momentum changed", "momentum ended", "move"])
        s.wait(1)
        XCTAssertEqual(s.names.last, "session ended")
    }

    func testATapAfterMomentumHasFinishedStillClicks() {
        let s = TouchScript(intent: .scroll)
        flick(s)
        var ticks = 0
        while !s.names.contains("momentum ended"), ticks < 180 {   // at most 3 s
            s.wait(1.0 / 60)
            ticks += 1
        }
        XCTAssertTrue(s.names.contains("momentum ended"))
        XCTAssertFalse(s.names.contains("session ended"))   // still in the double-tap wait
        s.frame([(0, 200, 200)])
        s.lift(after: 0.05)
        XCTAssertTrue(s.names.contains("click 1"))
    }

    func testSessionEndsOnlyAfterTheDoubleTapWindow() {
        let s = TouchScript()
        s.frame([(0, 100, 100)])
        s.lift(after: 0.05)
        s.wait(0.3)
        XCTAssertFalse(s.names.contains("session ended"))
        s.wait(0.2)
        XCTAssertEqual(s.names.last, "session ended")
    }

    func testNeedsTicksFollowsTheSession() {
        let s = TouchScript()
        XCTAssertFalse(s.engine.needsTicks)
        s.frame([(0, 100, 100)])
        XCTAssertTrue(s.engine.needsTicks)
        s.lift(after: 0.05)
        XCTAssertTrue(s.engine.needsTicks)
        s.wait(0.5)
        XCTAssertFalse(s.engine.needsTicks)
    }
}
