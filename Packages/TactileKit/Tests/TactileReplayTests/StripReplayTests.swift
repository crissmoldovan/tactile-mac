import XCTest
import TactileGestures

/// The wch.cn strip's takes in survey A, replayed end to end on "12.3FHD": its mouse interface's
/// reports through `PointerFingerReader`, then the mapping, the contact filter and the engine. A
/// panel in mouse mode reports one point, so every gesture beyond one finger is off, as the app
/// sets it for such a panel; the filter then lets one finger through. Each test asserts what its
/// take's name says, or the known limit the name can't reach.
final class StripReplayTests: XCTestCase {

    /// Every gesture beyond one finger off; long-press on, as by default.
    private static let oneFingerOnly = GestureOptions.oneFingerOnly(keeping: GestureOptions())

    /// Take `number`, read with a reader whose guard is `guardInterval`, replayed one-finger-only.
    private func replay(
        take number: Int, intent: OneFingerIntent = .drag, guardInterval: TimeInterval = 0.05
    ) throws -> [GestureAction] {
        var replay = Replay(
            display: Strip.display, diagonalInches: Strip.diagonalInches, options: Self.oneFingerOnly, intent: intent)
        return replay.run(try Strip.frames(take: number, guardInterval: guardInterval))
    }

    /// The finger stayed down 1.78 s without moving: a right-click with long-press on, as it is by
    /// default, and a click with it off.
    func testTap() throws {
        let actions = try replay(take: 9)
        let rightClicks = actions.filter { if case .rightClick = $0 { return true } else { return false } }
        XCTAssertEqual(rightClicks.count, 1, "\(names(actions))")
        XCTAssertEqual(clickCounts(actions), [], "\(names(actions))")

        var longPressOff = Self.oneFingerOnly
        longPressOff.longPress = false
        var plain = Replay(display: Strip.display, diagonalInches: Strip.diagonalInches, options: longPressOff,
                           intent: .drag)
        let clicked = plain.run(try Strip.frames(take: 9))
        XCTAssertEqual(clickCounts(clicked), [1], "\(names(clicked))")
    }

    func testDoubleTap() throws {
        let seen = names(try replay(take: 10))
        XCTAssertTrue(appear(["click 1", "click 2"], inOrderIn: seen), "\(seen)")
    }

    func testDrag() throws {
        let seen = names(try replay(take: 11, intent: .drag))
        XCTAssertTrue(appear(["press 1", "drag", "release"], inOrderIn: seen), "\(seen)")
    }

    /// Asked to scroll, a finger that rested first still drags.
    func testRestThenDrag() throws {
        let seen = names(try replay(take: 12, intent: .scroll))
        XCTAssertTrue(appear(["press 1", "drag", "release"], inOrderIn: seen), "\(seen)")
    }

    /// The known limit of a panel in mouse mode: two fingers tapping together arrive as two presses
    /// of one point, 0.13 s apart, which nothing can tell from a quick double tap. A double-click,
    /// not the right-click the take asks for.
    func testTwoFingerTapIsADoubleClick() throws {
        let seen = names(try replay(take: 16))
        XCTAssertTrue(appear(["click 1", "click 2"], inOrderIn: seen), "\(seen)")
    }

    /// As the four fingers left the glass, the strip pressed again 16 ms after the release, 73 mm
    /// away, for 10 ms. The reader's 50 ms guard refuses that press, so it removes exactly the click
    /// that press would have made.
    func testFourFingerSwipeLeavesNoPhantomClick() throws {
        let guarded = clickCounts(try replay(take: 19))
        let unguarded = clickCounts(try replay(take: 19, guardInterval: 0))
        XCTAssertEqual(guarded.count, unguarded.count - 1, "guarded \(guarded), unguarded \(unguarded)")
    }

    /// Whatever the take, under either intent, the session ends, no button is left held, and every
    /// long-press ring is taken down by the action after it. (The ILITEK's every-take test checks the
    /// ring the same way.)
    func testEveryTakeEndsItsSession() throws {
        for take in 1...20 {
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
