import XCTest
@testable import TactileGestures

final class ContactFilterTests: XCTestCase {

    private func fingers(_ ids: Int...) -> [Finger] {
        ids.map { Finger(id: $0, location: CGPoint(x: 0.5, y: 0.5)) }
    }

    private func ids(_ fingers: [Finger]) -> [Int] {
        fingers.map(\.id)
    }

    func testWithNoLimitEveryFingerCounts() {
        var filter = ContactFilter()
        XCTAssertEqual(ids(filter.live(fingers(3, 1, 2))), [3, 1, 2])
        XCTAssertTrue(filter.refused.isEmpty)
    }

    func testAFingerLandingBeyondTheLimitIsRefused() {
        var filter = ContactFilter(fingerLimit: 1)
        XCTAssertEqual(ids(filter.live(fingers(0))), [0])
        XCTAssertEqual(ids(filter.live(fingers(0, 1))), [0])
        XCTAssertEqual(filter.refused, [1])
    }

    func testARefusedFingerStaysRefusedUntilItLifts() {
        var filter = ContactFilter(fingerLimit: 1)
        _ = filter.live(fingers(0))
        _ = filter.live(fingers(0, 9))                              // 9 is a resting palm
        XCTAssertEqual(ids(filter.live(fingers(9))), [])            // the finger lifts; the palm doesn't take its place
        XCTAssertEqual(ids(filter.live(fingers(9, 1))), [1])        // the next stroke counts, with the palm still down
        XCTAssertEqual(ids(filter.live(fingers(1))), [1])           // the palm lifts
        XCTAssertTrue(filter.refused.isEmpty)
        XCTAssertEqual(ids(filter.live(fingers(1, 9))), [1])        // contact 9 lands again and is refused afresh
        XCTAssertEqual(ids(filter.live(fingers(9))), [])
        XCTAssertEqual(ids(filter.live([])), [])
        XCTAssertEqual(ids(filter.live(fingers(9))), [9])           // the glass was clear, so 9 is an ordinary finger now
    }

    func testWhenMoreLandTogetherThanFitTheLowestIDsCount() {
        var filter = ContactFilter(fingerLimit: 1)
        XCTAssertEqual(ids(filter.live(fingers(7, 2, 5))), [2])
        XCTAssertEqual(filter.refused, [5, 7])
    }

    func testAFingerThatCountsKeepsCountingWhenTheLimitDrops() {
        var filter = ContactFilter()
        _ = filter.live(fingers(0, 1))
        filter.fingerLimit = 1
        XCTAssertEqual(ids(filter.live(fingers(0, 1))), [0, 1])
        XCTAssertEqual(ids(filter.live(fingers(0, 1, 2))), [0, 1])  // but nothing new gets in
    }

    func testARefusedFingerStaysRefusedWhenTheLimitGoes() {
        var filter = ContactFilter(fingerLimit: 1)
        _ = filter.live(fingers(0))
        _ = filter.live(fingers(0, 1))
        filter.fingerLimit = nil
        XCTAssertEqual(ids(filter.live(fingers(0, 1))), [0])
        XCTAssertEqual(ids(filter.live(fingers(0, 1, 2))), [0, 2])
    }

    func testARepeatedContactIDCountsOnce() {
        var filter = ContactFilter(fingerLimit: 1)
        XCTAssertEqual(ids(filter.live(fingers(4, 4))), [4])
        XCTAssertTrue(filter.refused.isEmpty)
    }

    func testALimitOfTwoTakesTheTwoLowestAndThenNoMore() {
        var filter = ContactFilter(fingerLimit: 2)
        XCTAssertEqual(ids(filter.live(fingers(6, 3, 8))), [6, 3])
        XCTAssertEqual(filter.refused, [8])
        XCTAssertEqual(ids(filter.live(fingers(6, 8, 1))), [6, 1])    // 3 lifted: its room goes to the newcomer
        XCTAssertEqual(filter.refused, [8])
    }

    /// With no rules, the filter that is told the time and the surface size behaves exactly as the
    /// one that isn't, frame by frame.
    func testWithNoRulesTheTimedFilterIsTheOldOne() {
        let script: [[Int]] = [[0], [0, 9], [9], [9, 1], [1, 2, 3, 4, 5, 6], [2, 3], [], [7, 7, 8], [8], []]
        for limit in [nil, 1, 2] {
            var old = ContactFilter(fingerLimit: limit)
            var timed = ContactFilter(fingerLimit: limit, rules: .none)
            for (index, frame) in script.enumerated() {
                let contacts = frame.map { Finger(id: $0, location: CGPoint(x: 0.001, y: 0.5),
                                                  size: CGSize(width: 40, height: 40), isConfident: false) }
                XCTAssertEqual(ids(timed.live(contacts, at: Double(index) * 0.01, surfaceSize: CGSize(width: 500, height: 300))),
                               ids(old.live(contacts)), "limit \(String(describing: limit)), frame \(index)")
                XCTAssertEqual(timed.refused, old.refused)
                XCTAssertFalse(timed.mustCancel || old.mustCancel)
            }
        }
    }

    func testOptionsWithEveryMultiFingerGestureOffLimitFingersToOne() {
        var options = GestureOptions()
        XCTAssertNil(options.fingerLimit)
        options.twoFingerScroll = false
        options.pinch = false
        options.twoFingerTap = false
        XCTAssertNil(options.fingerLimit)                           // swipes are still on
        options.swipes = false
        XCTAssertNil(options.fingerLimit)                           // rotate is still on
        options.rotate = false
        XCTAssertEqual(options.fingerLimit, 1)
    }
}
