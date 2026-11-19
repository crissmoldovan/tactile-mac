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

    /// In CI, a measurement over the strict bound but within CI's headroom passes, and leaves a
    /// GitHub Actions warning naming the test and the numbers, so what only a run of one's own would
    /// catch still shows on the PR. Never on a run of one's own, never within the strict bound, and
    /// never over CI's bound, where the test fails anyway.
    func testAMeasurementWithinOnlyCIsHeadroomLeavesAWarning() {
        let strict = 0.2263125, ci = 0.58
        XCTAssertNil(TestTiming.headroomWarning("T", measured: 0.253, strict: strict, ci: ci, unit: "ms", local))
        XCTAssertNil(TestTiming.headroomWarning("T", measured: 0.2, strict: strict, ci: ci, unit: "ms", github))
        XCTAssertNil(TestTiming.headroomWarning("T", measured: 0.6, strict: strict, ci: ci, unit: "ms", github))
        XCTAssertEqual(
            TestTiming.headroomWarning("LongGestureTests (pinch, tester open)", measured: 0.253, strict: strict, ci: ci,
                                       unit: "ms", github),
            "::warning title=Timing headroom::LongGestureTests (pinch, tester open): 0.253 ms, over the strict bound of "
                + "0.226 ms, within CI's 0.580 ms. A run of one's own would fail it.")
        XCTAssertEqual(
            TestTiming.headroomWarning("a wait", measured: 1.5, strict: 1, ci: TestTiming.limit(1, github), unit: "s", github),
            "::warning title=Timing headroom::a wait: 1.500 s, over the strict bound of 1.000 s, within CI's 5.000 s. "
                + "A run of one's own would fail it.")
        XCTAssertEqual(
            TestTiming.headroomWarning("100%\nsure", measured: 1.5, strict: 1, ci: 5, unit: "s", github)?.components(separatedBy: "::").last?
                .hasPrefix("100%25%0Asure:"), true, "a workflow command's message is escaped")
    }

    /// The cost's warning uses the cost's two bounds; a wait's, the limit's.
    func testTheBoundsAWarningComparesWith() {
        let early = 0.13
        XCTAssertEqual(
            TestTiming.costWarning("T", cost: 0.3, early: early, ratio: 1.5, margin: 0.03, github),
            TestTiming.headroomWarning("T", measured: 0.3, strict: TestTiming.costBound(early: early, ratio: 1.5, margin: 0.03, local),
                                       ci: TestTiming.costBound(early: early, ratio: 1.5, margin: 0.03, github), unit: "ms", github))
        XCTAssertNotNil(TestTiming.costWarning("T", cost: 0.3, early: early, ratio: 1.5, margin: 0.03, github))
        XCTAssertNil(TestTiming.costWarning("T", cost: 0.3, early: early, ratio: 1.5, margin: 0.03, local))
        XCTAssertEqual(TestTiming.waitWarning("T", seconds: 2, limit: 1, github),
                       TestTiming.headroomWarning("T", measured: 2, strict: 1, ci: 5, unit: "s", github))
        XCTAssertNil(TestTiming.waitWarning("T", seconds: 0.5, limit: 1, github))
    }
}
