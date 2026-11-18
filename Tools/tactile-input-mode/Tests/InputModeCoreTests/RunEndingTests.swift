import XCTest
@testable import InputModeCore

final class RunEndingTests: XCTestCase {
    func testAFailedRestoreIsTheLastLineAndTheExitCodeIsNotZero() {
        let ending = RunEnding(restored: false, writesAccepted: true)
        XCTAssertEqual(ending.lines.last, "NOT put back: unplug the strip's touch cable and plug it back in.")
        XCTAssertEqual(ending.exitCode, RunEnding.notPutBackExitCode)
        XCTAssertNotEqual(ending.exitCode, 0)
    }

    func testAFailedRestoreOutranksARefusedWrite() {
        XCTAssertEqual(RunEnding(restored: false, writesAccepted: false).exitCode, RunEnding.notPutBackExitCode)
    }

    func testARestoredRunEndsWithNothingMore() {
        XCTAssertEqual(RunEnding(restored: true, writesAccepted: true).lines, [])
        XCTAssertEqual(RunEnding(restored: true, writesAccepted: true).exitCode, 0)
    }

    func testTheStripIsPutBackWhenEitherWriteIsAccepted() {
        XCTAssertTrue(RunEnding.putBack(wholeReportAccepted: true, fallbackAccepted: nil, attachedAfter: true))
        XCTAssertTrue(RunEnding.putBack(wholeReportAccepted: false, fallbackAccepted: true, attachedAfter: true))
    }

    func testTheStripIsNotPutBackWhenBothWritesFailWhileItIsAttached() {
        XCTAssertFalse(RunEnding.putBack(wholeReportAccepted: false, fallbackAccepted: false, attachedAfter: true))
    }

    func testAStripThatHasGoneCountsAsPutBack() {
        // Plugged in again, it starts in mouse emulation.
        XCTAssertTrue(RunEnding.putBack(wholeReportAccepted: false, fallbackAccepted: false, attachedAfter: false))
    }

    func testARestoredRunWhoseWriteWasRefusedExitsOne() {
        XCTAssertEqual(RunEnding(restored: true, writesAccepted: false).exitCode, 1)
    }
}
