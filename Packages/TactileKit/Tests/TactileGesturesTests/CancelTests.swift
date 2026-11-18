import XCTest
@testable import TactileGestures

final class CancelTests: XCTestCase {

    func testCancelWhenIdleDoesNothing() {
        let s = TouchScript()
        s.cancel()
        XCTAssertTrue(s.actions.isEmpty)
    }

    func testCancelBeforeAnythingIsDecidedJustEndsTheSession() {
        let s = TouchScript()
        s.frame([(0, 100, 100)])
        s.cancel()
        XCTAssertEqual(s.names.last, "session cancelled")
        XCTAssertFalse(s.names.contains { $0.hasPrefix("click") })
    }

    func testCancelDuringADragReleasesAndEndsTheSession() {
        let s = TouchScript(intent: .drag)
        s.frame([(0, 100, 100)])
        s.move([(0, (100, 100), (150, 100))], steps: 5)
        s.cancel()
        XCTAssertEqual(s.names.suffix(2), ["release", "session cancelled"])
        XCTAssertFalse(s.engine.needsTicks)
    }

    func testCancelDuringAScrollEndsIt() {
        let s = TouchScript(intent: .scroll)
        s.frame([(0, 100, 100)])
        s.move([(0, (100, 100), (100, 150))], steps: 25, every: 0.02)
        s.cancel()
        XCTAssertEqual(s.names.suffix(2), ["scroll ended", "session cancelled"])
    }

    func testCancelDuringAPinchEndsIt() {
        let s = TouchScript()
        s.frame([(0, 100, 100), (1, 140, 100)])
        s.move([(0, (100, 100), (80, 100)), (1, (140, 100), (160, 100))], steps: 10)
        s.cancel()
        XCTAssertEqual(s.names.suffix(2), ["pinch ended", "session cancelled"])
    }

    func testCancelDuringATwoFingerScrollEndsIt() {
        let s = TouchScript()
        s.frame([(0, 100, 100), (1, 140, 100)])
        s.move([(0, (100, 100), (100, 140)), (1, (140, 100), (140, 140))], steps: 20, every: 0.02)
        s.cancel()
        XCTAssertEqual(s.names.suffix(2), ["scroll ended", "session cancelled"])
    }

    func testCancelDuringTheDoubleTapWaitCancelsTheSession() {
        let s = TouchScript()
        s.frame([(0, 100, 100)])
        s.lift(after: 0.05)
        s.wait(0.1)
        s.cancel()
        XCTAssertEqual(s.names.last, "session cancelled")
        XCTAssertFalse(s.engine.needsTicks)

        let settled = s.actions.count
        s.wait(1)
        XCTAssertEqual(s.actions.count, settled)
    }

    func testCancelDuringMomentumEndsIt() {
        let s = TouchScript()
        s.frame([(0, 100, 100), (1, 140, 100)])
        s.move([(0, (100, 100), (100, 140)), (1, (140, 100), (140, 140))], steps: 10)   // 400 mm/s
        s.lift()
        s.wait(0.1)
        s.cancel()
        XCTAssertEqual(s.names.suffix(2), ["momentum ended", "session cancelled"])
        XCTAssertFalse(s.engine.needsTicks)
    }

    func testFingersStillDownAfterACancelAreIgnoredUntilTheyLift() {
        let s = TouchScript(intent: .drag)
        s.frame([(0, 100, 100)])
        s.move([(0, (100, 100), (150, 100))], steps: 5)
        s.cancel()
        let settled = s.actions.count

        s.move([(0, (150, 100), (200, 100))], steps: 5)
        s.lift()
        s.wait(1)
        XCTAssertEqual(s.actions.count, settled)

        s.frame([(0, 100, 100)])
        XCTAssertEqual(s.actions.count, settled + 2)   // session began, pointer move
    }
}
