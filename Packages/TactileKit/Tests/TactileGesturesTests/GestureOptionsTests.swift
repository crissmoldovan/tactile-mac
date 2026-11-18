import XCTest
@testable import TactileGestures

final class GestureOptionsTests: XCTestCase {

    private func script(_ change: (inout GestureOptions) -> Void) -> TouchScript {
        var options = GestureOptions()
        change(&options)
        return TouchScript(options: options)
    }

    func testPinchOffNeverPinches() {
        let s = script { $0.pinch = false }
        s.frame([(0, 100, 100), (1, 140, 100)])
        s.move([(0, (100, 100), (80, 100)), (1, (140, 100), (160, 100))], steps: 10)
        s.lift()
        XCTAssertFalse(s.names.contains { $0.hasPrefix("pinch") })
    }

    func testTwoFingerScrollOffNeverScrolls() {
        let s = script { $0.twoFingerScroll = false }
        s.frame([(0, 100, 100), (1, 140, 100)])
        s.move([(0, (100, 100), (100, 140)), (1, (140, 100), (140, 140))], steps: 40, every: 0.02)
        s.lift()
        XCTAssertFalse(s.names.contains { $0.hasPrefix("scroll") })
    }

    func testTwoFingerTapOffNeverRightClicks() {
        let s = script { $0.twoFingerTap = false }
        s.frame([(0, 100, 100), (1, 140, 100)])
        s.lift(after: 0.1)
        XCTAssertFalse(s.names.contains("right-click"))
    }

    func testSwipesOffLeavesTheFirstTwoFingersTheirGesture() {
        let s = script { $0.swipes = false }
        s.frame([(0, 100, 100), (1, 140, 100), (2, 180, 100)])
        s.move([(0, (100, 100), (100, 140)), (1, (140, 100), (140, 140)), (2, (180, 100), (180, 140))],
               steps: 40, every: 0.02)
        s.lift()
        XCTAssertFalse(s.names.contains { $0.hasPrefix("swipe") })
        XCTAssertTrue(s.names.contains("scroll began"))
    }

    func testSwipesOffIgnoresAThirdFingerThatLandsLate() {
        let s = script { $0.swipes = false }
        s.frame([(0, 100, 100), (1, 140, 100)])
        s.frame(after: 0.05, [(0, 100, 100), (1, 140, 100), (2, 180, 100)])
        s.move([(0, (100, 100), (100, 140)), (1, (140, 100), (140, 140)), (2, (180, 100), (180, 140))],
               steps: 40, every: 0.02)
        s.lift()
        XCTAssertFalse(s.names.contains { $0.hasPrefix("swipe") })
        XCTAssertTrue(s.names.contains("scroll began"))
    }

    /// Finger 5 and the lowest late finger, 2, take part and scroll down together. Finger 9 moves
    /// sideways, so a gesture that took 9 instead would not be a scroll.
    func testLateFingersJoinByLowestContactIDWhateverTheirOrder() {
        func run(_ late: [(Int, Double, Double)]) -> [GestureAction] {
            let s = script { $0.swipes = false }
            s.frame([(5, 100, 100)])
            s.frame(after: 0.03, [(5, 100, 100)] + late)
            s.move([(5, (100, 100), (100, 140)), (2, (140, 100), (140, 140)), (9, (300, 200), (340, 200))],
                   steps: 40, every: 0.02)
            s.lift()
            return s.actions
        }
        let nineFirst = run([(9, 300, 200), (2, 140, 100)])
        let twoFirst = run([(2, 140, 100), (9, 300, 200)])
        XCTAssertEqual(nineFirst, twoFirst)
        XCTAssertTrue(twoFirst.contains(.scroll(by: .zero, phase: .ended)))
    }

    private var oneFingerOnly: GestureOptions {
        .oneFingerOnly(keeping: GestureOptions())
    }

    func testWithEveryMultiFingerGestureOffASecondFingerDoesNotCancelATap() {
        let plain = TouchScript(options: oneFingerOnly)
        plain.frame([(0, 100, 100)])
        plain.lift(after: 0.05)

        let s = TouchScript(options: oneFingerOnly)
        s.frame([(0, 100, 100)])
        s.frame([(0, 100, 100), (1, 140, 100)])
        s.lift(after: 0.04)

        XCTAssertEqual(s.names, plain.names)   // one click, as if the second finger weren't there
    }

    func testWithEveryMultiFingerGestureOffASecondFingerDoesNotStopADrag() {
        let s = TouchScript(intent: .drag, options: oneFingerOnly)
        s.frame([(0, 100, 100)])
        s.frame([(0, 100, 100), (1, 140, 100)])   // a stray contact before the first finger has moved
        s.move([(0, (100, 100), (150, 100)), (1, (140, 100), (140, 100))], steps: 5)
        s.lift()
        XCTAssertTrue(s.names.contains("press 1"))
        XCTAssertTrue(s.names.contains("drag"))
        XCTAssertTrue(s.names.contains("release"))
    }

    func testInOneFingerModeARestingContactIsInvisible() {
        func run(palm: Bool) -> [GestureAction] {
            let s = TouchScript(intent: .drag, options: oneFingerOnly)
            let rest: [(Int, Double, Double)] = palm ? [(9, 300, 250)] : []
            s.frame([(0, 100, 100)])
            s.frame([(0, 100, 100)] + rest)                   // the palm comes to rest after the finger
            for x in stride(from: 110.0, through: 150.0, by: 10.0) { s.frame([(0, x, 100)] + rest) }
            s.frame(rest)                                     // the finger lifts; the palm stays
            s.wait(1)
            s.frame([(1, 200, 100)] + rest)                   // a second stroke, palm still down
            for x in stride(from: 210.0, through: 250.0, by: 10.0) { s.frame([(1, x, 100)] + rest) }
            s.frame(rest)
            s.wait(1)
            return s.actions
        }
        let alone = run(palm: false)
        XCTAssertEqual(run(palm: true), alone)
        XCTAssertEqual(alone.filter { if case .press = $0 { return true } else { return false } }.count, 2)
    }

    func testInOneFingerModeARestingContactDoesNotDelayMomentum() {
        func run(palm: Bool) -> [String] {
            let s = TouchScript(intent: .scroll, options: oneFingerOnly)
            let rest: [(Int, Double, Double)] = palm ? [(9, 300, 250)] : []
            s.frame([(0, 100, 100)])
            s.frame([(0, 100, 100)] + rest)
            for step in 1...10 { s.frame([(0, 100, 100 + Double(step) * 4)] + rest) }   // 400 mm/s
            s.frame(rest)
            s.wait(2)
            return s.names
        }
        let alone = run(palm: false)
        XCTAssertEqual(run(palm: true), alone)
        XCTAssertTrue(alone.contains("momentum began"))
        XCTAssertEqual(alone.last, "session ended")
    }

    // MARK: - Long-press

    func testOptionsSavedBeforeLongPressExistedHaveItOn() throws {
        XCTAssertTrue(GestureOptions().longPress)
        XCTAssertTrue(GestureOptions.all.longPress)
        XCTAssertTrue(try JSONDecoder().decode(GestureOptions.self, from: Data("{}".utf8)).longPress)
        XCTAssertTrue(try JSONDecoder().decode(GestureOptions.self, from: Data(#"{"pinch":false}"#.utf8)).longPress)
        XCTAssertFalse(try JSONDecoder().decode(GestureOptions.self, from: Data(#"{"longPress":false}"#.utf8)).longPress)
        var off = GestureOptions()
        off.longPress = false
        XCTAssertEqual(try JSONDecoder().decode(GestureOptions.self, from: JSONEncoder().encode(off)), off)
    }

    /// Long-press is a one-finger gesture: it leaves a one-finger-only touchscreen at one finger.
    func testLongPressDoesNotCountTowardsTheFingerLimit() {
        var options = GestureOptions.oneFingerOnly(keeping: .all)
        options.longPress = true
        XCTAssertEqual(options.fingerLimit, 1)
    }

    // MARK: - Rotate

    func testOptionsSavedBeforeRotateExistedHaveItOn() throws {
        XCTAssertTrue(GestureOptions().rotate)
        XCTAssertTrue(GestureOptions.all.rotate)
        XCTAssertTrue(try JSONDecoder().decode(GestureOptions.self, from: Data(#"{"pinch":false}"#.utf8)).rotate)
        XCTAssertFalse(try JSONDecoder().decode(GestureOptions.self, from: Data(#"{"rotate":false}"#.utf8)).rotate)
        var off = GestureOptions()
        off.rotate = false
        XCTAssertEqual(try JSONDecoder().decode(GestureOptions.self, from: JSONEncoder().encode(off)), off)
    }

    /// Review finding 2: a touchscreen set to one finger before rotate existed saved the four
    /// older switches off and no rotate. It must still be one finger, with long-press on.
    func testASettingSavedAsOneFingerBeforeRotateExistedStaysOneFinger() throws {
        let saved = #"{"twoFingerScroll":false,"pinch":false,"twoFingerTap":false,"swipes":false}"#
        let options = try JSONDecoder().decode(GestureOptions.self, from: Data(saved.utf8))
        XCTAssertFalse(options.rotate)
        XCTAssertEqual(options.fingerLimit, 1)
        XCTAssertTrue(options.longPress)
    }

    /// Only that whole setting turns rotate off: a stored rotate wins, and any older switch on or
    /// missing leaves rotate at its default.
    func testOnlyTheWholeOldOneFingerSettingTurnsRotateOff() throws {
        func rotate(_ json: String) throws -> Bool {
            try JSONDecoder().decode(GestureOptions.self, from: Data(json.utf8)).rotate
        }
        XCTAssertTrue(try rotate(#"{"pinch":false}"#))
        XCTAssertTrue(try rotate(#"{"twoFingerScroll":false,"pinch":false,"twoFingerTap":false}"#))
        XCTAssertTrue(try rotate(#"{"twoFingerScroll":false,"pinch":false,"twoFingerTap":false,"swipes":true}"#))
        XCTAssertTrue(try rotate(#"{"twoFingerScroll":false,"pinch":false,"twoFingerTap":false,"swipes":false,"rotate":true}"#))
        XCTAssertFalse(try rotate(#"{"rotate":false}"#))
        XCTAssertEqual(try JSONDecoder().decode(GestureOptions.self, from: JSONEncoder().encode(GestureOptions.oneFingerOnly(keeping: .all))),
                       .oneFingerOnly(keeping: .all))
    }

    func testRotateAloneKeepsEveryFinger() {
        var options = GestureOptions.oneFingerOnly(keeping: .all)
        options.rotate = true
        XCTAssertNil(options.fingerLimit)
    }

    func testOneFingerOnlyTurnsEveryMultiFingerGestureOffAndKeepsLongPressAsItWas() {
        let kept = GestureOptions.oneFingerOnly(keeping: .all)
        XCTAssertEqual(kept.fingerLimit, 1)
        XCTAssertFalse(kept.twoFingerScroll || kept.pinch || kept.twoFingerTap || kept.swipes || kept.rotate)
        XCTAssertTrue(kept.longPress)

        var noLongPress = GestureOptions()
        noLongPress.longPress = false
        XCTAssertFalse(GestureOptions.oneFingerOnly(keeping: noLongPress).longPress)
        XCTAssertEqual(GestureOptions.oneFingerOnly(keeping: noLongPress).fingerLimit, 1)
    }

    /// The whole one-finger-only behaviour, through the call the app makes for a touchscreen that
    /// reports one point: a second contact is invisible, and a long-press still right-clicks.
    func testOneFingerOnlyIgnoresASecondContactAndStillLongPresses() {
        let s = TouchScript(options: .oneFingerOnly(keeping: .all))
        s.frame([(0, 100, 100)])
        s.frame([(0, 100, 100), (9, 300, 250)])     // a palm comes to rest
        s.wait(0.7)
        s.frame([(9, 300, 250)])                    // the finger lifts; the palm stays
        XCTAssertEqual(s.names, ["session began", "move", "long-press ready", "right-click"])
    }

    func testWhichFingersTakePartDoesNotDependOnReportOrder() {
        func run(_ landing: [(Int, Double, Double)]) -> [GestureAction] {
            let s = script { $0.swipes = false }
            s.frame(landing)
            s.move([(0, (100, 100), (100, 140)), (1, (140, 100), (140, 140)), (2, (180, 100), (180, 140))],
                   steps: 40, every: 0.02)
            s.lift()
            return s.actions
        }
        XCTAssertEqual(run([(0, 100, 100), (1, 140, 100), (2, 180, 100)]),
                       run([(2, 180, 100), (1, 140, 100), (0, 100, 100)]))
    }
}
