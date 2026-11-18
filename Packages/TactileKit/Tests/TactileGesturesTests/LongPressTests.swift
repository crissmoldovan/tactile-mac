import XCTest
@testable import TactileGestures

/// One finger resting 0.6 s: lifting it then right-clicks, and the engine says so the moment it
/// becomes true, so the interface can ring the finger's circle.
final class LongPressTests: XCTestCase {

    private func options(_ change: (inout GestureOptions) -> Void) -> GestureOptions {
        var options = GestureOptions()
        change(&options)
        return options
    }

    // MARK: - Ready

    func testRestingForTheDurationSaysReadyAtTheFirstTickAfterIt() {
        let s = TouchScript()
        s.frame([(0, 100, 100)])
        let landed = s.time
        XCTAssertTrue(s.engine.needsTicks)    // resting, not yet ready: time matters

        var readyAt: TimeInterval?
        while readyAt == nil, s.time < landed + 1 {
            s.wait(1.0 / 60)
            if s.names.contains("long-press ready") { readyAt = s.time }
        }
        guard let readyAt else { return XCTFail("never ready: \(s.names)") }
        XCTAssertGreaterThanOrEqual(readyAt - landed, 0.6)
        XCTAssertLessThan(readyAt - landed, 0.6 + 1.0 / 60 + 1e-9)
        XCTAssertEqual(s.names, ["session began", "move", "long-press ready"])
        XCTAssertEqual(s.longPressReadies, [TouchScript.at(100, 100)])
    }

    func testAFrameSaysReadyWhenNoTickCameFirst() {
        let s = TouchScript()
        s.frame([(0, 100, 100)])
        s.frame(after: 0.55, [(0, 100, 100)])
        XCTAssertFalse(s.names.contains("long-press ready"))
        s.frame(after: 0.1, [(0, 100, 100)])
        XCTAssertEqual(s.names, ["session began", "move", "long-press ready"])
    }

    func testReadyIsSaidExactlyOnce() {
        let s = TouchScript()
        s.frame([(0, 100, 100)])
        for _ in 0..<50 {
            s.frame(after: 0.02, [(0, 100, 100)])
            s.wait(0.02)
        }
        XCTAssertEqual(s.longPressReadies.count, 1)
    }

    // MARK: - Lifting

    func testLiftingAfterReadyRightClicksWhereTheFingerLanded() {
        let s = TouchScript()
        s.frame([(0, 100, 100)])
        s.move([(0, (100, 100), (101.5, 101))], steps: 10, every: 0.07)   // a drift within the 3 mm
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move", "long-press ready", "right-click"])
        XCTAssertEqual(s.rightClicks, [TouchScript.at(100, 100)])
        XCTAssertTrue(s.clickCounts.isEmpty)
    }

    func testALiftThatIsTheFirstNewsOfTheDurationStillRightClicks() {
        let s = TouchScript()
        s.frame([(0, 100, 100)])
        s.lift(after: 0.7)    // no tick and no frame in between
        XCTAssertEqual(s.names, ["session began", "move", "long-press ready", "right-click"])
    }

    func testLiftingBeforeTheDurationClicks() {
        let s = TouchScript()
        s.frame([(0, 100, 100)])
        s.wait(0.5)
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move", "click 1"])
    }

    func testWithLongPressOffAPauseStillClicks() {
        let s = TouchScript(options: options { $0.longPress = false })
        s.frame([(0, 100, 100)])
        s.wait(0.7)
        s.lift()
        s.wait(1)
        XCTAssertEqual(s.names, ["session began", "move", "click 1", "session ended"])
    }

    func testTheSessionEndsAfterARightClickAsAfterAClick() {
        let s = TouchScript()
        s.frame([(0, 100, 100)])
        s.wait(0.7)
        s.lift()
        s.wait(0.3)
        XCTAssertFalse(s.names.contains("session ended"))
        s.wait(0.2)
        XCTAssertEqual(s.names.last, "session ended")
        XCTAssertFalse(s.engine.needsTicks)
    }

    // MARK: - Double-clicks

    func testALongPressDoesNotStartADoubleClick() {
        let s = TouchScript()
        s.frame([(0, 100, 100)])
        s.wait(0.7)
        s.lift()
        s.frame(after: 0.1, [(0, 100, 100)])
        s.lift(after: 0.05)
        XCTAssertEqual(s.rightClicks.count, 1)
        XCTAssertEqual(s.clickCounts, [1])
    }

    func testALongPressDoesNotContinueADoubleClick() {
        let s = TouchScript()
        s.frame([(0, 100, 100)])
        s.lift(after: 0.05)                     // a tap
        s.frame(after: 0.1, [(0, 100, 100)])    // lands within the double-tap window, then rests
        s.wait(0.7)
        s.lift()
        s.frame(after: 0.1, [(0, 100, 100)])
        s.lift(after: 0.05)
        XCTAssertEqual(s.clickCounts, [1, 1])
        XCTAssertEqual(s.rightClicks.count, 1)
    }

    // MARK: - Moving

    /// Review focus 1: rest 0.7 s, then move 5 mm. A drag, whatever the intent, and no right-click.
    func testMovingAfterReadyDragsAndDoesNotRightClick() {
        let s = TouchScript(intent: .scroll)
        s.frame([(0, 100, 100)])
        s.wait(0.7)
        s.move([(0, (100, 100), (105, 100))], steps: 5)
        s.lift()
        s.wait(1)
        XCTAssertEqual(s.names, ["session began", "move", "long-press ready", "press 1", "drag", "release",
                                 "session ended"])
        XCTAssertTrue(s.rightClicks.isEmpty)
        XCTAssertTrue(s.intentRequests.isEmpty)
        XCTAssertEqual(s.actions.last(where: { if case .release = $0 { return true } else { return false } }),
                       .release(at: TouchScript.at(105, 100)))
    }

    /// The engine's next action after `longPressReady` always ends the ring: the right-click, the
    /// press of a drag, the cancel, or the withdrawal when a second finger lands.
    func testTheActionAfterReadyIsAlwaysOneThatEndsTheRing() {
        func next(after script: (TouchScript) -> Void) -> String? {
            let s = TouchScript()
            s.frame([(0, 100, 100)])
            s.wait(0.7)
            script(s)
            let names = s.actions.map(TouchScript.name(of:))
            guard let ready = names.firstIndex(of: "long-press ready"), ready + 1 < names.count else { return nil }
            return names[ready + 1]
        }
        XCTAssertEqual(next { $0.lift() }, "right-click")
        XCTAssertEqual(next { $0.move([(0, (100, 100), (110, 100))], steps: 5) }, "press 1")
        XCTAssertEqual(next { $0.cancel() }, "session cancelled")
        XCTAssertEqual(next { $0.frame([(0, 100, 100), (1, 140, 100)]) }, "long-press withdrawn")
    }

    // MARK: - Stopping a coasting scroll

    func testATouchThatStopsACoastingScrollNeverRightClicks() {
        let s = TouchScript(intent: .scroll)
        s.frame([(0, 100, 100)])
        s.move([(0, (100, 100), (100, 140))], steps: 10)   // 400 mm/s: coasts
        s.lift()
        s.wait(0.1)
        XCTAssertTrue(s.names.contains("momentum began"))
        s.frame([(0, 200, 200)])
        s.wait(1.5)
        s.lift()
        s.wait(1)
        XCTAssertFalse(s.names.contains("long-press ready"))
        XCTAssertTrue(s.rightClicks.isEmpty)
        XCTAssertTrue(s.clickCounts.isEmpty)
        XCTAssertEqual(s.names.suffix(3), ["momentum ended", "move", "session ended"])
    }

    // MARK: - A second finger

    func testASecondFingerWhileRestingGivesTheTwoFingerRulesAndNoReady() {
        let s = TouchScript()
        s.frame([(0, 100, 100)])
        s.wait(0.3)
        s.frame([(0, 100, 100), (1, 140, 100)])
        s.wait(1)
        s.lift()
        s.wait(1)
        XCTAssertEqual(s.names, ["session began", "move", "session ended"])   // a slow two-finger tap: nothing
    }

    func testASecondFingerWhileRestingCanStillScroll() {
        let s = TouchScript()
        s.frame([(0, 100, 100)])
        s.wait(0.3)
        s.frame([(0, 100, 100), (1, 140, 100)])
        s.move([(0, (100, 100), (100, 140)), (1, (140, 100), (140, 140))], steps: 40, every: 0.02)
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move", "scroll began", "scroll changed", "scroll ended"])
    }

    /// Decision: a second finger landing after `longPressReady` still makes a two-finger gesture
    /// (the ILITEK's recorded pinch has its second finger land 0.64 s after the first), so lifting
    /// no longer right-clicks, and the engine withdraws the ring at once.
    func testASecondFingerAfterReadyWithdrawsItAndCanStillPinch() {
        let s = TouchScript()
        s.frame([(0, 100, 100)])
        s.wait(0.7)
        s.frame([(0, 100, 100), (1, 140, 100)])
        s.move([(0, (100, 100), (90, 100)), (1, (140, 100), (150, 100))], steps: 10)
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move", "long-press ready", "long-press withdrawn",
                                 "move", "pinch began", "pinch changed", "pinch ended"])
        XCTAssertTrue(s.rightClicks.isEmpty)
    }

    func testAfterTheWithdrawalTwoFingersTappingStillRightClickAsATwoFingerTap() {
        let s = TouchScript()
        s.frame([(0, 100, 100)])
        s.wait(0.7)
        s.frame([(0, 100, 100), (1, 140, 100)])
        s.lift(after: 0.1)
        XCTAssertEqual(s.names, ["session began", "move", "long-press ready", "long-press withdrawn", "right-click"])
        XCTAssertEqual(s.rightClicks.count, 1)
        XCTAssertTrue(isClose(s.rightClicks[0], TouchScript.at(120, 100)))   // between the fingers
    }

    // MARK: - Cancel

    func testCancelAfterReadyDoesNotRightClick() {
        let s = TouchScript()
        s.frame([(0, 100, 100)])
        s.wait(0.7)
        s.cancel()
        XCTAssertEqual(s.names.suffix(2), ["long-press ready", "session cancelled"])
        s.lift()
        s.wait(1)
        XCTAssertTrue(s.rightClicks.isEmpty)
        XCTAssertTrue(s.clickCounts.isEmpty)
        XCTAssertEqual(s.names.last, "session cancelled")
    }

    // MARK: - Options

    func testWithLongPressOffNothingIsSaidAndNothingRightClicks() {
        let s = TouchScript(options: options { $0.longPress = false })
        s.frame([(0, 100, 100)])
        s.wait(2)
        s.lift()
        XCTAssertEqual(s.names, ["session began", "move", "click 1"])
    }

    /// Options are read when a gesture is decided: once ready has been said, lifting right-clicks
    /// even if long-press was switched off in between.
    func testReadyIsAPromiseKept() {
        let s = TouchScript()
        s.frame([(0, 100, 100)])
        s.wait(0.7)
        s.engine.options.longPress = false
        s.lift()
        XCTAssertEqual(s.rightClicks.count, 1)
    }
}
