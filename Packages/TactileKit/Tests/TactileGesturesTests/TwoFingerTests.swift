import XCTest
@testable import TactileGestures

final class TwoFingerTests: XCTestCase {

    func testTwoFingerTapRightClicksBetweenTheFingers() {
        let s = TouchScript()
        s.frame([(0, 100, 100)])
        s.frame(after: 0.03, [(0, 100, 100), (1, 140, 100)])
        s.lift(after: 0.1)
        XCTAssertEqual(s.names, ["session began", "move", "right-click"])
        XCTAssertEqual(s.rightClicks.count, 1)
        XCTAssertTrue(isClose(s.rightClicks[0], TouchScript.at(120, 100)))
    }

    func testFingersLiftingAMomentApartStillRightClick() {
        let s = TouchScript()
        s.frame([(0, 100, 100), (1, 140, 100)])
        s.frame(after: 0.1, [(1, 140, 100)])
        s.lift(after: 0.1)
        XCTAssertEqual(s.names, ["session began", "move", "right-click"])
    }

    func testSlowTwoFingerTapDoesNothing() {
        let s = TouchScript()
        s.frame([(0, 100, 100), (1, 140, 100)])
        s.wait(0.5)
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move"])
    }

    func testTwoFingersMovingTogetherScroll() {
        let s = TouchScript(intent: .drag)
        s.frame([(0, 100, 100), (1, 140, 100)])
        s.move([(0, (100, 100), (100, 140)), (1, (140, 100), (140, 140))], steps: 40, every: 0.02)  // 50 mm/s
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move", "scroll began", "scroll changed", "scroll ended"])
        XCTAssertTrue(s.pointerMoves.contains { isClose($0, TouchScript.at(120, 100)) })
        XCTAssertEqual(s.totalScroll.dy, 40 / 300, accuracy: 1e-9)
        XCTAssertTrue(s.intentRequests.isEmpty)
    }

    func testTwoFingerFlickCoasts() {
        let s = TouchScript()
        s.frame([(0, 100, 100), (1, 140, 100)])
        s.move([(0, (100, 100), (100, 140)), (1, (140, 100), (140, 140))], steps: 10)  // 400 mm/s
        s.lift()
        s.wait(2)
        XCTAssertEqual(s.names.suffix(5), ["scroll ended", "momentum began", "momentum changed", "momentum ended", "session ended"])
    }

    func testMomentumDoesNotStartWhenTheLastFingerRestsBeforeLifting() {
        let s = TouchScript()
        s.frame([(0, 100, 100), (1, 140, 100)])
        s.move([(0, (100, 100), (100, 140)), (1, (140, 100), (140, 140))], steps: 10)  // 400 mm/s
        s.frame([(1, 140, 140)])                                   // one finger lifts
        for _ in 0..<50 { s.frame(after: 0.02, [(1, 140, 140)]) }  // the other rests for 1 s
        s.lift()
        s.wait(2)
        XCTAssertTrue(s.names.contains("scroll ended"))
        XCTAssertFalse(s.names.contains { $0.hasPrefix("momentum") })
    }

    func testSpreadingFingersPinch() {
        let s = TouchScript()
        s.frame([(0, 100, 100), (1, 140, 100)])
        s.move([(0, (100, 100), (90, 100)), (1, (140, 100), (150, 100))], steps: 10)
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move", "pinch began", "pinch changed", "pinch ended"])
        XCTAssertEqual(s.totalZoom, 60.0 / 40.0, accuracy: 1e-9)
    }

    func testAScrollNeverBecomesAPinch() {
        let s = TouchScript()
        s.frame([(0, 100, 100), (1, 140, 100)])
        s.move([(0, (100, 100), (100, 120)), (1, (140, 100), (140, 120))], steps: 20, every: 0.02)
        s.move([(0, (100, 120), (80, 120)), (1, (140, 120), (160, 120))], steps: 20, every: 0.02)
        s.lift()
        XCTAssertFalse(s.names.contains { $0.hasPrefix("pinch") })
        XCTAssertEqual(s.names, ["session began", "move", "scroll began", "scroll changed", "scroll ended"])
    }

    func testFingerAddedDuringADragIsIgnored() {
        let s = TouchScript(intent: .drag)
        s.frame([(0, 100, 100)])
        s.move([(0, (100, 100), (120, 100))], steps: 10)
        s.frame([(0, 120, 100), (1, 200, 100)])
        s.move([(0, (120, 100), (140, 100)), (1, (200, 100), (220, 100))], steps: 10)
        s.frame([(1, 220, 100)])
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move", "press 1", "drag", "release"])
        XCTAssertEqual(s.actions.last, .release(at: TouchScript.at(140, 100)))
    }

    func testTheOrderFingersAreListedInDoesNotMatter() {
        func scrollDown(swapping: Bool) -> TouchScript {
            let s = TouchScript()
            for step in 0...40 {
                let y = 100 + Double(step)
                var fingers = [(0, 100.0, y), (1, 140.0, y)]
                if swapping && step % 2 == 1 { fingers.reverse() }
                s.frame(after: 0.02, fingers)
            }
            s.lift()
            return s
        }
        let plain = scrollDown(swapping: false)
        let swapped = scrollDown(swapping: true)
        XCTAssertEqual(swapped.names, plain.names)
        XCTAssertEqual(swapped.totalScroll.dy, plain.totalScroll.dy, accuracy: 1e-9)
    }
}
