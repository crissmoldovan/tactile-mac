import CoreGraphics
import XCTest
@testable import TactileOutput

@MainActor
final class PointerKeeperTests: XCTestCase {
    private let touchscreen = CGRect(x: 2056, y: 163, width: 1920, height: 1080)

    func testPointerFromAnotherScreenGoesBack() {
        XCTAssertTrue(PointerKeeper.shouldReturn(home: CGPoint(x: 500, y: 500), touchscreenFrame: touchscreen, mode: .backWhereItWas))
    }

    func testPointerAlreadyOnTheTouchscreenStays() {
        XCTAssertFalse(PointerKeeper.shouldReturn(home: CGPoint(x: 3000, y: 600), touchscreenFrame: touchscreen, mode: .backWhereItWas))
    }

    func testStaysWhereTouchedNeverReturns() {
        XCTAssertFalse(PointerKeeper.shouldReturn(home: CGPoint(x: 500, y: 500), touchscreenFrame: touchscreen, mode: .staysWhereTouched))
    }

    func testTaggedEventsAreRecognisedAsTactiles() {
        let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: .zero, mouseButton: .left)
        event?.setIntegerValueField(.eventSourceUserData, value: EventSender.tag)
        XCTAssertTrue(PointerKeeper.isFromTactile(event, now: EventSender.lastPostTime + 10))
    }

    func testUntaggedEventsLongAfterOurOwnAreReal() {
        let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: .zero, mouseButton: .left)
        XCTAssertFalse(PointerKeeper.isFromTactile(event, now: EventSender.lastPostTime + 10))
    }

    // MARK: - Sessions
    //
    // Every keeper below is built with stand-ins for the pointer, the arrow and the warp, and
    // installs no event monitors, so nothing here moves the real pointer or hides the real arrow.

    /// Review of the October plan: a touch cut short left the old pointer position behind, and a
    /// later touch sent the pointer there.
    func testCancellingForgetsWhereThePointerWasAndNeverMovesIt() {
        var location = CGPoint(x: 3000, y: 600)   // on another display
        var hidden = false
        var warps: [CGPoint] = []
        let keeper = PointerKeeper(pointerLocation: { location },
                                   setArrowHidden: { hidden = $0 },
                                   warp: { warps.append($0) })
        let touchscreen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        keeper.sessionBegan(touchscreenFrame: touchscreen, returnMode: .backWhereItWas)
        XCTAssertTrue(hidden)

        keeper.sessionCancelled()
        XCTAssertFalse(hidden)
        keeper.sessionEnded()
        XCTAssertTrue(warps.isEmpty)

        location = CGPoint(x: 2500, y: 300)
        keeper.sessionBegan(touchscreenFrame: touchscreen, returnMode: .backWhereItWas)
        keeper.sessionEnded()
        XCTAssertEqual(warps, [CGPoint(x: 2500, y: 300)])   // the fresh position, not the stale one
    }

    func testHandingOverToAnotherTouchscreenKeepsTheOriginalHome() {
        var location = CGPoint(x: 5000, y: 500)   // on a third display
        var warps: [CGPoint] = []
        let keeper = PointerKeeper(pointerLocation: { location },
                                   setArrowHidden: { _ in },
                                   warp: { warps.append($0) })
        keeper.sessionBegan(touchscreenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), returnMode: .backWhereItWas)
        location = CGPoint(x: 400, y: 300)        // the hidden pointer is now under the finger
        keeper.sessionBegan(touchscreenFrame: CGRect(x: 1920, y: 0, width: 1600, height: 600),   // taken over, no end in between
                            returnMode: .backWhereItWas)
        keeper.sessionEnded()
        XCTAssertEqual(warps, [CGPoint(x: 5000, y: 500)])
    }

    func testCancellingWithNoSessionDoesNothing() {
        var hiddenChanges = 0
        var warps = 0
        let keeper = PointerKeeper(pointerLocation: { .zero },
                                   setArrowHidden: { _ in hiddenChanges += 1 },
                                   warp: { _ in warps += 1 })
        keeper.sessionCancelled()
        XCTAssertEqual(hiddenChanges, 0)
        XCTAssertEqual(warps, 0)
    }

    // MARK: - Hand-overs, ends and real mouse movement

    private let touchscreenA = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let touchscreenB = CGRect(x: 1920, y: 0, width: 1600, height: 600)

    func testAHandOverTakesTheNewTouchscreensFrame() {
        var warps: [CGPoint] = []
        let keeper = PointerKeeper(pointerLocation: { CGPoint(x: 2000, y: 300) },   // on B, not on A
                                   setArrowHidden: { _ in },
                                   warp: { warps.append($0) })
        keeper.sessionBegan(touchscreenFrame: touchscreenA, returnMode: .backWhereItWas)
        keeper.sessionBegan(touchscreenFrame: touchscreenB, returnMode: .backWhereItWas)
        keeper.sessionEnded()
        XCTAssertEqual(warps, [])   // home is on B, which holds the pointer at the end
    }

    func testAHandOverTakesTheNewTouchscreensReturnSetting() {
        var warps: [CGPoint] = []
        let keeper = PointerKeeper(pointerLocation: { CGPoint(x: 5000, y: 500) },   // on neither
                                   setArrowHidden: { _ in },
                                   warp: { warps.append($0) })
        keeper.sessionBegan(touchscreenFrame: touchscreenA, returnMode: .backWhereItWas)
        keeper.sessionBegan(touchscreenFrame: touchscreenB, returnMode: .staysWhereTouched)
        keeper.sessionEnded()
        XCTAssertEqual(warps, [])
    }

    func testEndingWithNoSessionDoesNothing() {
        var calls: [String] = []
        let keeper = PointerKeeper(pointerLocation: { calls.append("pointerLocation"); return .zero },
                                   setArrowHidden: { calls.append("setArrowHidden(\($0))") },
                                   warp: { calls.append("warp(\($0))") })
        keeper.sessionEnded()
        XCTAssertEqual(calls, [])
    }

    func testTheArrowStaysHiddenAfterANormalEndUntilTheMouseMoves() {
        var hidden: [Bool] = []
        let keeper = PointerKeeper(pointerLocation: { CGPoint(x: 5000, y: 500) },
                                   setArrowHidden: { hidden.append($0) },
                                   warp: { _ in })
        keeper.sessionBegan(touchscreenFrame: touchscreenA, returnMode: .backWhereItWas)
        keeper.sessionEnded()
        XCTAssertEqual(hidden.last, true)
        keeper.realMouseMoved()
        XCTAssertEqual(hidden.last, false)
    }

    /// A hand that has taken the mouse keeps the pointer: it isn't pulled back home at the end.
    func testRealMouseMovementForgetsHome() {
        var warps: [CGPoint] = []
        let keeper = PointerKeeper(pointerLocation: { CGPoint(x: 5000, y: 500) },   // off the touchscreen
                                   setArrowHidden: { _ in },
                                   warp: { warps.append($0) })
        keeper.sessionBegan(touchscreenFrame: touchscreenA, returnMode: .backWhereItWas)
        keeper.realMouseMoved()
        keeper.sessionEnded()
        XCTAssertEqual(warps, [])
    }

    func testCancellingAfterAnEndStillShowsTheArrow() {
        var hidden: [Bool] = []
        var warps: [CGPoint] = []
        let keeper = PointerKeeper(pointerLocation: { CGPoint(x: 5000, y: 500) },   // off the touchscreen
                                   setArrowHidden: { hidden.append($0) },
                                   warp: { warps.append($0) })
        keeper.sessionBegan(touchscreenFrame: touchscreenA, returnMode: .backWhereItWas)
        keeper.sessionEnded()
        XCTAssertEqual(warps, [CGPoint(x: 5000, y: 500)])   // the end's own warp
        keeper.sessionCancelled()
        XCTAssertEqual(hidden.last, false)
        XCTAssertEqual(warps, [CGPoint(x: 5000, y: 500)])   // nothing more
    }
}
