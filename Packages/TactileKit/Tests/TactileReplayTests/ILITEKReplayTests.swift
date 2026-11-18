import CoreGraphics
import XCTest
import TactileGestures

/// The ILITEK's takes in survey B, replayed end to end on "HDMI" with every gesture on: its touch
/// interface's reports through `TouchFrameBuilder`, then the mapping, the contact filter and the
/// engine. Each test asserts what its take's name says: the verdict the survey expected.
final class ILITEKReplayTests: XCTestCase {

    /// Take `number`, replayed with every gesture on.
    private func replay(take number: Int, intent: OneFingerIntent = .drag) throws -> [GestureAction] {
        var replay = Replay(display: ILITEK.display, diagonalInches: ILITEK.diagonalInches, intent: intent)
        return replay.run(try ILITEK.frames(take: number))
    }

    func testTap() throws {
        XCTAssertEqual(names(try replay(take: 9)), ["session began", "move", "click 1", "session ended"])
    }

    func testDoubleTap() throws {
        let seen = names(try replay(take: 10))
        XCTAssertTrue(appear(["click 1", "click 2"], inOrderIn: seen), "\(seen)")
        XCTAssertFalse(seen.contains { $0.hasPrefix("press") }, "\(seen)")
    }

    /// The finger took 0.585 s to move 3 mm, longer than the 0.4 s hold, so it drags whatever the
    /// intent: the resolver never gets to choose.
    func testDrag() throws {
        for intent in [OneFingerIntent.drag, .scroll] {
            let seen = names(try replay(take: 11, intent: intent))
            XCTAssertTrue(appear(["press 1", "drag", "release"], inOrderIn: seen), "\(intent): \(seen)")
            XCTAssertFalse(seen.contains { $0.hasPrefix("click") }, "\(intent): \(seen)")
        }
    }

    /// Asked to scroll, a finger that rested first still drags.
    func testRestThenDrag() throws {
        let seen = names(try replay(take: 12, intent: .scroll))
        XCTAssertTrue(appear(["press 1", "drag", "release"], inOrderIn: seen), "\(seen)")
    }

    /// Still for at least 0.6 s, then lifted: a right-click with long-press on, as it is by default,
    /// and a click with it off.
    func testPressAndHold() throws {
        let actions = try replay(take: 13)
        let rightClicks = actions.filter { if case .rightClick = $0 { return true } else { return false } }
        XCTAssertEqual(rightClicks.count, 1, "\(names(actions))")
        XCTAssertEqual(clickCounts(actions), [], "\(names(actions))")
        XCTAssertFalse(names(actions).contains { $0.hasPrefix("press") || $0 == "drag" || $0.hasPrefix("scroll") },
                       "\(names(actions))")

        var longPressOff = GestureOptions.all
        longPressOff.longPress = false
        var plain = Replay(display: ILITEK.display, diagonalInches: ILITEK.diagonalInches, options: longPressOff,
                           intent: .drag)
        let clicked = plain.run(try ILITEK.frames(take: 13))
        XCTAssertEqual(clickCounts(clicked), [1], "\(names(clicked))")
        XCTAssertFalse(names(clicked).contains("right-click"), "\(names(clicked))")
        XCTAssertFalse(names(clicked).contains { $0.hasPrefix("press") || $0 == "drag" || $0.hasPrefix("scroll") },
                       "\(names(clicked))")
    }

    /// The take's prompt: slide two fingers up the glass "as if scrolling a page down". A scroll
    /// moves the content with the fingers, so a page scrolled down is a total scroll pointing up the
    /// screen: dy below zero, y growing downwards. No momentum is asserted either way: the fingers
    /// stopped 0.39 s before they lifted.
    func testTwoFingerScroll() throws {
        let actions = try replay(take: 14)
        let seen = names(actions)
        XCTAssertTrue(appear(["scroll began", "scroll changed", "scroll ended"], inOrderIn: seen), "\(seen)")
        XCTAssertFalse(seen.contains { $0.hasPrefix("press") || $0.hasPrefix("pinch") }, "\(seen)")
        let total = totalScroll(actions)
        XCTAssertLessThan(total.dy, 0, "total scroll \(total)")
        XCTAssertGreaterThan(abs(total.dy), abs(total.dx), "total scroll \(total)")
    }

    /// The second finger landed 0.64 s after the first, when the first had moved 2.8 mm of the 3 mm
    /// that would have committed it alone: the narrowest call in the survey.
    func testPinch() throws {
        let seen = names(try replay(take: 15))
        XCTAssertTrue(appear(["pinch began", "pinch ended"], inOrderIn: seen), "\(seen)")
        XCTAssertFalse(seen.contains { $0.hasPrefix("press") || $0.hasPrefix("scroll") }, "\(seen)")
    }

    /// Ten fingers, as many as the panel tracks, landing within 0.1 s and resting.
    func testTenFingersDoNothingHarmful() throws {
        let seen = names(try replay(take: 3))
        XCTAssertFalse(seen.contains { $0.hasPrefix("click") || $0.hasPrefix("press") || $0 == "right-click" },
                       "\(seen)")
    }

    /// Whatever the take, under either intent, the session ends, no button is left held, and every
    /// long-press ring is taken down by the action after it.
    func testEveryTakeEndsItsSession() throws {
        for take in 1...15 {
            for intent in [OneFingerIntent.drag, .scroll] {
                let actions = try replay(take: take, intent: intent)
                let seen = names(actions)
                XCTAssertEqual(seen.last, "session ended", "take \(take), \(intent): \(seen)")
                XCTAssertTrue(everyPressIsReleased(actions), "take \(take), \(intent): \(seen)")
                XCTAssertTrue(everyRingIsTakenDown(actions), "take \(take), \(intent): \(seen)")
            }
        }
    }
}
