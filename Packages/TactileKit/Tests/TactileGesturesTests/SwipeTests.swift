import XCTest
@testable import TactileGestures

final class SwipeTests: XCTestCase {

    func testThreeFingersLandingInQuickSuccessionSwipeLeftOnce() {
        let s = TouchScript()
        s.frame([(0, 200, 150)])
        s.frame(after: 0.05, [(0, 200, 150), (1, 230, 150)])
        s.frame(after: 0.05, [(0, 200, 150), (1, 230, 150), (2, 260, 150)])
        s.move([(0, (200, 150), (160, 150)), (1, (230, 150), (190, 150)), (2, (260, 150), (220, 150))], steps: 20)
        s.lift()
        XCTAssertEqual(s.swipes, [.left])
    }

    func testFourFingerSwipeUp() {
        let s = TouchScript()
        let starts: [(Int, Double, Double)] = [(0, 200, 200), (1, 230, 200), (2, 260, 200), (3, 290, 200)]
        s.frame(starts)
        s.move(starts.map { ($0.0, ($0.1, $0.2), ($0.1, $0.2 - 40)) }, steps: 20)
        s.lift()
        XCTAssertEqual(s.swipes, [.up])
    }

    func testThreeFingerSwipeRightAndDown() {
        let starts: [(Int, Double, Double)] = [(0, 200, 100), (1, 230, 100), (2, 260, 100)]
        let right = TouchScript()
        right.frame(starts)
        right.move(starts.map { ($0.0, ($0.1, $0.2), ($0.1 + 40, $0.2)) }, steps: 20)
        right.lift()
        XCTAssertEqual(right.swipes, [.right])

        let down = TouchScript()
        down.frame(starts)
        down.move(starts.map { ($0.0, ($0.1, $0.2), ($0.1, $0.2 + 40)) }, steps: 20)
        down.lift()
        XCTAssertEqual(down.swipes, [.down])
    }

    func testShortSwipeDoesNothing() {
        let s = TouchScript()
        let starts: [(Int, Double, Double)] = [(0, 200, 150), (1, 230, 150), (2, 260, 150)]
        s.frame(starts)
        s.move(starts.map { ($0.0, ($0.1, $0.2), ($0.1 - 20, $0.2)) }, steps: 20)
        s.lift()
        XCTAssertEqual(s.swipes, [])
    }

    func testDiagonalSwipeDoesNothing() {
        let s = TouchScript()
        let starts: [(Int, Double, Double)] = [(0, 200, 100), (1, 230, 100), (2, 260, 100)]
        s.frame(starts)
        s.move(starts.map { ($0.0, ($0.1, $0.2), ($0.1 + 30, $0.2 + 30)) }, steps: 20)
        s.lift()
        XCTAssertEqual(s.swipes, [])
    }

    func testAThirdFingerLandingLateIsNoSwipe() {
        let s = TouchScript()
        s.frame([(0, 200, 150), (1, 230, 150)])
        s.frame(after: 0.5, [(0, 200, 150), (1, 230, 150), (2, 260, 150)])
        s.move([(0, (200, 150), (160, 150)), (1, (230, 150), (190, 150)), (2, (260, 150), (220, 150))], steps: 20)
        s.lift()
        XCTAssertEqual(s.swipes, [])
    }
}
