import TactileTestSupport
import XCTest

/// The tests' wall-clock limits: as written on a run of one's own, with headroom on a CI runner,
/// a shared machine whose speed varies from one minute to the next.
final class TestTimingTests: XCTestCase {

    private let local: [String: String] = [:]
    private let github = ["GITHUB_ACTIONS": "true", "CI": "true"]

    func testACIRunIsToldByItsEnvironment() {
        XCTAssertFalse(TestTiming.isCI(local))
        XCTAssertTrue(TestTiming.isCI(github))
        XCTAssertTrue(TestTiming.isCI(["CI": "1"]))
        XCTAssertFalse(TestTiming.isCI(["CI": "false"]))
        XCTAssertFalse(TestTiming.isCI(["CI": ""]))
    }

    func testALimitHasHeadroomOnlyInCI() {
        XCTAssertEqual(TestTiming.limit(1, local), 1)
        XCTAssertEqual(TestTiming.limit(1, github), 5)
        XCTAssertEqual(TestTiming.limit(10, github), 50)
    }

    /// The bound for a cost that mustn't grow: strict on a run of one's own; in CI a wider ratio and
    /// a minimum margin, so a median of a fraction of a millisecond can't fail on noise, while a cost
    /// that grows with the gesture (several times as much) still fails.
    func testACostBoundIsStrictLocallyAndHasHeadroomInCI() {
        XCTAssertEqual(TestTiming.costBound(early: 0.2, ratio: 1.5, margin: 0.03, local), 0.33, accuracy: 1e-12)
        // The run that failed CUE-1297: 0.253 ms against a bound of 0.226 ms.
        let early = (0.2263125 - 0.03) / 1.5
        XCTAssertGreaterThan(TestTiming.costBound(early: early, ratio: 1.5, margin: 0.03, github), 0.253)
        XCTAssertEqual(TestTiming.costBound(early: 0.2, ratio: 1.5, margin: 0.03, github), 0.2 * 2.5 + 0.25, accuracy: 1e-12)
        XCTAssertLessThan(TestTiming.costBound(early: 0.2, ratio: 1.5, margin: 0.03, github), 0.2 * 5, "five times as much still fails")
    }
}
