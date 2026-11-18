// The model's clock. Its activity is given as closures here, so no test holds off App Nap; its
// timer is never run, as no test spins the run loop, and is invalidated by `stop`.

import Foundation
@testable import TactileApp
import XCTest

@MainActor
final class LiveTickerTests: XCTestCase {
    func testTheActivityLastsAsLongAsTheTimer() {
        var begun = 0
        var ended: [String] = []
        let ticker = LiveTicker(
            beginActivity: {
                begun += 1
                return NSString(string: "activity \(begun)")
            },
            endActivity: { ended.append(($0 as? NSString).map(String.init) ?? "?") })
        XCTAssertFalse(ticker.isRunning)

        ticker.start {}
        XCTAssertTrue(ticker.isRunning)
        XCTAssertEqual(begun, 1)
        ticker.start {}
        XCTAssertEqual(begun, 1, "already running: no second activity")

        ticker.stop()
        XCTAssertFalse(ticker.isRunning)
        XCTAssertEqual(ended, ["activity 1"])
        ticker.stop()
        XCTAssertEqual(ended, ["activity 1"], "already stopped")

        ticker.start {}
        ticker.stop()
        XCTAssertEqual(begun, 2)
        XCTAssertEqual(ended, ["activity 1", "activity 2"])
    }
}
