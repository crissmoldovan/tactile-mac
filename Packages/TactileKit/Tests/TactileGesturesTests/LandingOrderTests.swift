import XCTest
@testable import TactileGestures

final class LandingOrderTests: XCTestCase {

    /// Review of the October plan: movement was judged before new fingers were registered.
    func testASecondFingerLandingAsTheFirstCrossesTheThresholdJoinsTheGesture() {
        let s = TouchScript(intent: .drag)
        s.frame([(0, 100, 100)])
        s.frame([(0, 100, 105), (1, 140, 105)])   // finger 0 has moved 5 mm; finger 1 lands in the same report
        s.move([(0, (100, 105), (100, 145)), (1, (140, 105), (140, 145))], steps: 40, every: 0.02)
        s.lift()
        XCTAssertFalse(s.names.contains { $0.hasPrefix("press") })
        XCTAssertTrue(s.intentRequests.isEmpty)
        XCTAssertTrue(s.names.contains("scroll began"))
        XCTAssertEqual(s.totalScroll.dy, 40 / 300, accuracy: 0.01)   // about 40 mm down, on a 300 mm surface
    }
}
