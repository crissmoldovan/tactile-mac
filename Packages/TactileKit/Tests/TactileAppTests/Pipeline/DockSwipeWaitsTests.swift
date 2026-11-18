// The live Dock-swipe sender's waits: each piece of work runs once, after its delay or at "run them
// now", whichever comes first. Only the main queue's real delay is used, a few tens of
// milliseconds; nothing is posted.

import Foundation
@testable import TactileApp
import XCTest

@MainActor
final class DockSwipeWaitsTests: XCTestCase {

    /// Lets the main queue run for `seconds`.
    private func spin(_ seconds: TimeInterval) {
        let done = expectation(description: "time passes")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 2)
    }

    func testAWaitRunsOnceAfterItsDelay() {
        let waits = DockSwipeWaits()
        var ran: [Int] = []
        waits.schedule(after: 0.02) { ran.append(1) }
        XCTAssertEqual(ran, [], "not before its delay")
        spin(0.15)
        XCTAssertEqual(ran, [1])
        waits.runNow()
        XCTAssertEqual(ran, [1], "run now finds nothing: it has run")
    }

    func testRunNowRunsEachPendingWaitOnceInTheOrderAsked() {
        let waits = DockSwipeWaits()
        var ran: [Int] = []
        waits.schedule(after: 0.05) { ran.append(1) }
        waits.schedule(after: 0.02) { ran.append(2) }
        waits.runNow()
        XCTAssertEqual(ran, [1, 2], "in the order they were asked for, not by delay")
        waits.runNow()
        XCTAssertEqual(ran, [1, 2], "run now twice: nothing more")
        spin(0.15)
        XCTAssertEqual(ran, [1, 2], "their delayed firings find nothing")
    }

    func testAWaitAskedForAfterRunNowRunsAfterItsDelay() {
        let waits = DockSwipeWaits()
        var ran: [Int] = []
        waits.schedule(after: 0.02) { ran.append(1) }
        waits.runNow()
        waits.schedule(after: 0.02) { ran.append(2) }
        XCTAssertEqual(ran, [1], "not before its delay")
        spin(0.15)
        XCTAssertEqual(ran, [1, 2], "after its delay, once")
        waits.runNow()
        XCTAssertEqual(ran, [1, 2])
    }
}
