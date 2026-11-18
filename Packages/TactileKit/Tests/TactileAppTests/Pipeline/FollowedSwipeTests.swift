// Delivery 4b, Part S2: the followed swipe through a pipeline. The Dock-swipe sender's events are
// captured by the recording outputs; nothing posts a Dock swipe.

import CoreGraphics
import Foundation
@testable import TactileApp
import TactileGestures
import TactileOutput
import TactileReading
import TactileScreens
import XCTest

private typealias Desk = DeskFixture

/// Three fingers on the HDMI's glass, 30 mm apart, and moving them.
@MainActor
struct SwipeScript {
    let pipeline: TouchPipeline
    /// The glass's width and height in millimetres.
    let surface: CGSize
    var time: TimeInterval
    /// Each finger's glass point now.
    var fingers: [(id: Int, x: CGFloat, y: CGFloat)]

    init(_ pipeline: TouchPipeline, surface: CGSize, at time: TimeInterval, fingers count: Int = 3) {
        self.pipeline = pipeline
        self.surface = surface
        self.time = time
        let spacing = 30 / surface.width
        fingers = (0..<count).map { (id: $0, x: 0.45 + CGFloat($0) * spacing, y: 0.5) }
    }

    private var frame: ContactFrame {
        ContactFrame(time: time, contacts: fingers.map { Contact(id: $0.id, position: CGPoint(x: $0.x, y: $0.y)) })
    }

    /// The fingers landing together.
    mutating func land() {
        pipeline.handle(frame)
    }

    /// Every finger moved `dx` millimetres along the glass (negative: left), over `steps` frames
    /// 10 ms apart.
    mutating func move(_ dx: Double, steps: Int = 20) {
        let step = CGFloat(dx) / CGFloat(steps) / surface.width
        for _ in 0..<steps {
            time += 0.01
            fingers = fingers.map { ($0.id, $0.x + step, $0.y) }
            pipeline.handle(frame)
        }
    }

    /// Every finger lifting at once.
    mutating func lift() {
        time += 0.01
        pipeline.handle(ContactFrame(time: time, contacts: []))
    }
}

@MainActor
final class FollowedSwipeTests: XCTestCase {
    private let following = Desk.driving(on: Desk.hdmi, diagonal: 23.8, swipesFollowFingers: true)
    private var surface: CGSize { following.surfaceSizeMM }

    private func pipeline(_ driving: Driving, _ outputs: RecordingOutputs, id: TouchscreenID = Desk.ilitekID,
                          constants: GestureConstants = .standard) -> TouchPipeline {
        TouchPipeline(id: id, driving: driving, outputs: outputs, cancelOther: { _, _ in }, constants: constants)
    }

    /// One three-finger swipe 50 mm left, landing at `time`; the session settles afterwards.
    private func swipeLeft(_ pipeline: TouchPipeline, at time: TimeInterval, surface: CGSize) {
        var script = SwipeScript(pipeline, surface: surface, at: time)
        script.land()
        script.move(-50)
        script.lift()
        pipeline.tick(at: script.time + 1)
    }

    // MARK: - Followed, or the shortcut

    func testAFollowedSwipePostsDockEventsAndNoShortcut() {
        let outputs = RecordingOutputs()
        swipeLeft(pipeline(following, outputs), at: 10, surface: surface)
        XCTAssertEqual(outputs.dockPhases.first, .began)
        XCTAssertGreaterThan(outputs.dockPhases.filter { $0 == .changed }.count, 3)
        XCTAssertEqual(outputs.dockSwipeEvents.filter(\.isEnd).map(\.phase), [.ended], "one end, completed")
        XCTAssertGreaterThan(outputs.dockSwipeEvents.last?.progress ?? 0, 0, "fingers left: the Space on the right")
        XCTAssertEqual(outputs.shortcuts, 0, "no shortcut")
        XCTAssertFalse(outputs.dockSwipes.isOpen)
        // Every Dock event goes out with its companion.
        XCTAssertEqual(outputs.record.dockEvents.filter { $0.type == 29 }.count, outputs.dockSwipeEvents.count)
    }

    func testWithTheSettingOffTheShortcutAndNoDockEvents() {
        let outputs = RecordingOutputs()
        swipeLeft(pipeline(Desk.driving(on: Desk.hdmi, diagonal: 23.8), outputs), at: 10, surface: surface)
        XCTAssertEqual(outputs.record.dockEvents, [])
        XCTAssertEqual(outputs.shortcuts, 1, "today's one-shot swipe")
    }

    func testABeganTheSenderRefusesGivesTheShortcutAtTheLift() {
        let outputs = RecordingOutputs()
        outputs.dockSurroundings.spaces[Desk.hdmi.displayID] = .some(nil)  // its Spaces can't be found out
        swipeLeft(pipeline(following, outputs), at: 10, surface: surface)
        XCTAssertEqual(outputs.record.dockEvents, [])
        XCTAssertEqual(outputs.shortcuts, 1, "the person loses the following, never the swipe")
    }

    func testACancelledFollowedSwipePostsNothingElse() {
        let outputs = RecordingOutputs()
        let p = pipeline(following, outputs)
        var script = SwipeScript(p, surface: surface, at: 10)
        script.land()
        script.move(-40)
        script.move(25, steps: 10)  // back, and lifting while moving back
        script.lift()
        p.tick(at: script.time + 1)
        XCTAssertEqual(outputs.dockSwipeEvents.filter(\.isEnd).map(\.phase), [.cancelled])
        XCTAssertEqual(outputs.shortcuts, 0, "a cancelled swipe: nothing")
    }

    func testUnavailableBetweenSessionsFallsBackOnTheNextNeverMidSwipe() {
        let outputs = RecordingOutputs()
        let p = pipeline(following, outputs)
        var script = SwipeScript(p, surface: surface, at: 10)
        script.land()
        script.move(-30)
        XCTAssertTrue(outputs.dockSwipes.isOpen)
        // The person switches the gesture off in System Settings, mid-swipe.
        outputs.dockSurroundings.isSpaceSwipeEnabled = false
        script.move(-20)
        script.lift()
        p.tick(at: script.time + 1)
        XCTAssertEqual(outputs.dockSwipeEvents.filter(\.isEnd).map(\.phase), [.ended], "the swipe begun runs to its end")
        XCTAssertEqual(outputs.shortcuts, 0)

        let before = outputs.dockSwipeEvents.count
        swipeLeft(p, at: 20, surface: surface)
        XCTAssertEqual(outputs.dockSwipeEvents.count, before, "the next session isn't followed")
        XCTAssertEqual(outputs.shortcuts, 1, "it has the shortcut")
    }

    func testTheSettingIsReadAtTheStartOfASession() {
        let outputs = RecordingOutputs()
        let p = pipeline(Desk.driving(on: Desk.hdmi, diagonal: 23.8), outputs)
        var script = SwipeScript(p, surface: surface, at: 10)
        script.land()
        p.update(following)  // switched on with the fingers down
        script.move(-50)
        script.lift()
        p.tick(at: script.time + 1)
        XCTAssertEqual(outputs.record.dockEvents, [], "not this session")
        XCTAssertEqual(outputs.shortcuts, 1)

        swipeLeft(p, at: 20, surface: surface)
        XCTAssertEqual(outputs.dockSwipeEvents.filter(\.isEnd).map(\.phase), [.ended], "the next one")
        XCTAssertEqual(outputs.shortcuts, 1)
    }

    func testFourFingersFollowAsThree() {
        let outputs = RecordingOutputs()
        let p = pipeline(following, outputs)
        var script = SwipeScript(p, surface: surface, at: 10, fingers: 4)
        script.land()
        script.move(50)
        script.lift()
        p.tick(at: script.time + 1)
        XCTAssertEqual(outputs.dockSwipeEvents.filter(\.isEnd).map(\.phase), [.ended])
        XCTAssertLessThan(outputs.dockSwipeEvents.last?.progress ?? 0, 0, "fingers right: the Space on the left")
        XCTAssertEqual(outputs.shortcuts, 0)
    }

    func testAVerticalSwipeIsStillTheShortcut() {
        let outputs = RecordingOutputs()
        let p = pipeline(following, outputs)
        let spacing = 30 / surface.width
        var time: TimeInterval = 10
        func frame(_ y: CGFloat) -> ContactFrame {
            ContactFrame(time: time, contacts: (0..<3).map { Contact(id: $0, position: CGPoint(x: 0.45 + CGFloat($0) * spacing, y: y)) })
        }
        p.handle(frame(0.6))
        for step in 1...20 {
            time += 0.01
            p.handle(frame(0.6 - CGFloat(step) * 0.01))
        }
        time += 0.01
        p.handle(ContactFrame(time: time, contacts: []))
        XCTAssertEqual(outputs.record.dockEvents, [])
        XCTAssertEqual(outputs.shortcuts, 1)
    }

    // MARK: - Every way it stops (Review Focus 1)

    /// A swipe 30 mm in: open.
    private func halfASwipe(_ p: TouchPipeline, _ outputs: RecordingOutputs) -> SwipeScript {
        var script = SwipeScript(p, surface: surface, at: 10)
        script.land()
        script.move(-30)
        XCTAssertTrue(outputs.dockSwipes.isOpen, "open")
        return script
    }

    private func assertClosedOnce(_ outputs: RecordingOutputs, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(outputs.dockSwipeEvents.filter(\.isEnd).map(\.phase), [.cancelled], name, file: file, line: line)
        XCTAssertEqual(outputs.shortcuts, 0, "\(name): no shortcut", file: file, line: line)
        XCTAssertFalse(outputs.dockSwipes.isOpen, name, file: file, line: line)
    }

    func testStoppingDrivingClosesTheSwipeFirst() {
        let outputs = RecordingOutputs()
        let p = pipeline(following, outputs)
        var script = halfASwipe(p, outputs)
        p.cancel(at: script.time, reason: .stoppedDriving)
        assertClosedOnce(outputs, "stopped driving")
        let end = try? XCTUnwrap(outputs.record.log.first("dock cancelled"))
        let shown = try? XCTUnwrap(outputs.record.log.first("arrow shown"))
        XCTAssertLessThan(end ?? .max, shown ?? .min, "the swipe is closed before anything else")
        // The rest of the touch, and the engine's own end, change nothing.
        script.move(-20)
        script.lift()
        p.tick(at: script.time + 1)
        assertClosedOnce(outputs, "after")
    }

    func testTheSilenceRuleClosesTheSwipe() {
        let outputs = RecordingOutputs()
        let p = pipeline(following, outputs)
        let script = halfASwipe(p, outputs)
        p.tick(at: script.time + TouchPipeline.silenceLimit + 0.1)
        assertClosedOnce(outputs, "silence")
        XCTAssertEqual(outputs.record.arrowHidden, [true, false])
    }

    func testAPalmClosesTheSwipe() {
        let outputs = RecordingOutputs()
        let p = pipeline(following, outputs)
        var script = halfASwipe(p, outputs)
        // One of the fingers loses the panel's confidence: a palm.
        script.time += 0.01
        p.handle(ContactFrame(time: script.time, contacts: script.fingers.map {
            Contact(id: $0.id, position: CGPoint(x: $0.x, y: $0.y), isConfident: $0.id != 1)
        }))
        assertClosedOnce(outputs, "palm")
        let end = try? XCTUnwrap(outputs.record.log.first("dock cancelled"))
        let shown = try? XCTUnwrap(outputs.record.log.first("arrow shown"))
        XCTAssertLessThan(end ?? .max, shown ?? .min)
        script.move(-20)
        script.lift()
        p.tick(at: script.time + 1)
        assertClosedOnce(outputs, "after the palm")
    }

    /// The model closes it (a display change that doesn't move this touchscreen's touches), and the
    /// fingers go on and lift going forward: the Dock has already slid back, so the shortcut moves
    /// the Desktop. The person loses the following, never the swipe; one move, never two.
    func testClosedFromOutsideThenCompletedIsTheShortcut() {
        let outputs = RecordingOutputs()
        let p = pipeline(following, outputs)
        var script = halfASwipe(p, outputs)
        outputs.dockSwipes.closeIfOpen()
        script.move(-20)
        script.lift()
        p.tick(at: script.time + 1)
        XCTAssertEqual(outputs.dockSwipeEvents.filter(\.isEnd).map(\.phase), [.cancelled], "the close")
        XCTAssertEqual(outputs.shortcuts, 1, "and exactly one shortcut")
        XCTAssertFalse(outputs.dockSwipes.isOpen)
    }

    func testClosedFromOutsideThenMovingBackIsNothing() {
        let outputs = RecordingOutputs()
        let p = pipeline(following, outputs)
        var script = halfASwipe(p, outputs)
        outputs.dockSwipes.closeIfOpen()
        script.move(25, steps: 10)  // back, and lifting while moving back
        script.lift()
        p.tick(at: script.time + 1)
        assertClosedOnce(outputs, "closed from outside, then cancelled by the fingers")
    }

    /// The reviewer's P3, against a twin whose sender refuses every swipe (its shortcuts are the
    /// engine's completions): closed from outside and then completed is one move, as the twin's.
    func testClosedFromOutsideThenCompletedIsOneMoveAsTheTwinMakes() {
        let main = RecordingOutputs()
        let twin = RecordingOutputs()
        twin.dockSurroundings.defaultSpaces = nil
        let mp = pipeline(following, main)
        let tp = pipeline(following, twin)
        var ms = SwipeScript(mp, surface: surface, at: 10)
        var ts = SwipeScript(tp, surface: surface, at: 10)
        ms.land(); ts.land()
        ms.move(-30); ts.move(-30)
        main.dockSwipes.closeIfOpen()
        ms.move(-20); ts.move(-20)
        ms.lift(); ts.lift()
        mp.tick(at: ms.time + 1); tp.tick(at: ts.time + 1)
        XCTAssertEqual(twin.shortcuts, 1, "the engine completed it")
        XCTAssertEqual(main.dockPhases.filter { $0 == .ended }.count + main.shortcuts, 1)
    }

    // MARK: - The pointer stays while the end is repeated

    func testThePointerStaysOnTheDisplayWhileTheEndIsRepeated() {
        // An engine that ends its session soon after the lift: sooner than the repeated end.
        var constants = GestureConstants.standard
        constants.tapInterval = 0.05
        let outputs = RecordingOutputs()
        let p = pipeline(following, outputs, constants: constants)
        var script = SwipeScript(p, surface: surface, at: 10)
        script.land()
        script.move(-50)
        script.lift()
        let lift = script.time
        XCTAssertEqual(outputs.dockSwipeEvents.filter(\.isEnd).map(\.phase), [.ended])
        var time = lift
        while time < lift + 0.19 {
            time += 0.01
            p.tick(at: time)
        }
        XCTAssertEqual(outputs.record.warps, [], "not home within the repeat's delay")
        XCTAssertEqual(outputs.arbiter.owner, Desk.ilitekID, "the pointer is still the ILITEK's")
        XCTAssertTrue(p.needsTicks)
        p.tick(at: lift + DockSwipeSender.endRepeatDelay + 0.01)
        XCTAssertEqual(outputs.record.warps, [Desk.pointerHome], "then home")
        XCTAssertNil(outputs.arbiter.owner)
        XCTAssertFalse(p.needsTicks)
    }

    func testWithTheEnginesOwnTimingThePointerGoesHomeAfterTheRepeat() {
        XCTAssertGreaterThanOrEqual(GestureConstants.standard.tapInterval, DockSwipeSender.endRepeatDelay,
                                    "a session ends no sooner than the repeat")
        let outputs = RecordingOutputs()
        let p = pipeline(following, outputs)
        var script = SwipeScript(p, surface: surface, at: 10)
        script.land()
        script.move(-50)
        script.lift()
        let lift = script.time
        var time = lift
        while outputs.record.warps.isEmpty, time < lift + 2 {
            time += 0.01
            p.tick(at: time)
        }
        XCTAssertEqual(outputs.record.warps, [Desk.pointerHome])
        XCTAssertGreaterThanOrEqual(time - lift, DockSwipeSender.endRepeatDelay)
    }

    func testTheOtherTouchscreenCannotTakeThePointerWhileTheEndIsRepeated() {
        let outputs = RecordingOutputs()
        var takeOvers: [TouchscreenID] = []
        var pipelines: [TouchscreenID: TouchPipeline] = [:]
        let cancelOther: @MainActor (TouchscreenID, TimeInterval) -> Void = { other, time in
            takeOvers.append(other)
            pipelines[other]?.cancel(at: time, reason: .takenOver)
        }
        let ilitek = TouchPipeline(id: Desk.ilitekID, driving: following, outputs: outputs, cancelOther: cancelOther)
        let strip = TouchPipeline(id: Desk.stripID, driving: Desk.driving(on: Desk.strip, diagonal: 12.3, options: Desk.noGestures),
                                  outputs: outputs, cancelOther: cancelOther)
        pipelines = [Desk.ilitekID: ilitek, Desk.stripID: strip]
        var script = SwipeScript(ilitek, surface: surface, at: 10)
        script.land()
        script.move(-50)
        script.lift()
        let lift = script.time

        // A tap on the strip 0.1 s after: ignored, drawn hollow.
        strip.handle(glassFrame(lift + 0.1, (0, 0.5, 0.5)))
        strip.handle(glassFrame(lift + 0.15))
        XCTAssertEqual(takeOvers, [])
        XCTAssertEqual(outputs.count(.down), 0)
        XCTAssertTrue(outputs.record.circles.contains(.show(display: Desk.strip.displayID, fingers: [0: CGPoint(x: 0.5, y: 0.5)],
                                                            hollow: [0])))
        // Once the session has ended, a tap on the strip works.
        ilitek.tick(at: lift + 1)
        strip.handle(glassFrame(lift + 1.1, (0, 0.5, 0.5)))
        strip.handle(glassFrame(lift + 1.2))
        XCTAssertEqual(outputs.count(.down), 1)
    }

    /// The reviewer's P1: a followed swipe on the ILITEK, all fingers lifting together; a tap on
    /// the strip `after` seconds after the lift, then the ILITEK's session ends, then the strip's
    /// finger lifts. Returns the take-overs and the presses.
    private func tapOnTheStrip(after: TimeInterval, follow: Bool) -> (takeOvers: Int, downs: Int) {
        let outputs = RecordingOutputs()
        var takeOvers = 0
        var pipelines: [TouchscreenID: TouchPipeline] = [:]
        let cancelOther: @MainActor (TouchscreenID, TimeInterval) -> Void = { other, time in
            takeOvers += 1
            pipelines[other]?.cancel(at: time, reason: .takenOver)
        }
        let ilitek = TouchPipeline(id: Desk.ilitekID, driving: Desk.driving(on: Desk.hdmi, diagonal: 23.8, swipesFollowFingers: follow),
                                   outputs: outputs, cancelOther: cancelOther)
        let strip = TouchPipeline(id: Desk.stripID, driving: Desk.driving(on: Desk.strip, diagonal: 12.3, options: Desk.noGestures),
                                  outputs: outputs, cancelOther: cancelOther)
        pipelines = [Desk.ilitekID: ilitek, Desk.stripID: strip]
        var script = SwipeScript(ilitek, surface: surface, at: 10)
        script.land()
        script.move(-50)
        script.lift()
        let lift = script.time
        var time = lift
        while time < lift + after - 0.005 {
            time += 0.01
            ilitek.tick(at: time)
        }
        strip.handle(glassFrame(lift + after, (0, 0.5, 0.5)))
        ilitek.tick(at: lift + 0.45)
        ilitek.tick(at: lift + 0.5)
        strip.handle(glassFrame(lift + after + 0.25, (0, 0.5, 0.5)))
        strip.handle(glassFrame(lift + after + 0.3))
        return (takeOvers, outputs.count(.down))
    }

    /// Two pipelines on one set of outputs, the ILITEK's following its swipes; take-overs counted
    /// and carried out.
    private func twoTouchscreens() -> (outputs: RecordingOutputs, ilitek: TouchPipeline, strip: TouchPipeline, takeOvers: () -> Int) {
        let outputs = RecordingOutputs()
        var takeOvers = 0
        var pipelines: [TouchscreenID: TouchPipeline] = [:]
        let cancelOther: @MainActor (TouchscreenID, TimeInterval) -> Void = { other, time in
            takeOvers += 1
            pipelines[other]?.cancel(at: time, reason: .takenOver)
        }
        let ilitek = TouchPipeline(id: Desk.ilitekID, driving: Desk.driving(on: Desk.hdmi, diagonal: 23.8, swipesFollowFingers: true),
                                   outputs: outputs, cancelOther: cancelOther)
        let strip = TouchPipeline(id: Desk.stripID, driving: Desk.driving(on: Desk.strip, diagonal: 12.3, swipesFollowFingers: false),
                                  outputs: outputs, cancelOther: cancelOther)
        pipelines = [Desk.ilitekID: ilitek, Desk.stripID: strip]
        return (outputs, ilitek, strip, { takeOvers })
    }

    /// The re-reviewer's probe: a finger lands on the same touchscreen during the hold after a
    /// followed swipe and rests past it. The hold's end must not tell the arbiter the fingers are
    /// up under it: a tap on the other touchscreen after the hold is ignored.
    func testAFingerLandingDuringTheHoldKeepsThePointer() {
        let (outputs, ilitek, strip, takeOvers) = twoTouchscreens()
        var script = SwipeScript(ilitek, surface: surface, at: 10)
        script.land()
        script.move(-50)
        script.lift()
        let lift = script.time
        XCTAssertEqual(outputs.dockPhases.filter { $0 != .changed }, [.began, .ended])
        // A finger lands on the ILITEK 0.1 s after the lift and rests; the ILITEK reports every
        // 0.1 s, ticks come every 10 ms; the strip is tapped 0.25 s after the lift, past the hold.
        var time = lift
        var nextReport = lift + 0.1
        var tapped = false
        while time < lift + 0.6 {
            time += 0.01
            if time >= nextReport - 0.0001 {
                ilitek.handle(glassFrame(nextReport, (7, 0.5, 0.5)))
                nextReport += 0.1
            }
            ilitek.tick(at: time)
            if !tapped, time >= lift + 0.25 {
                tapped = true
                strip.handle(glassFrame(time + 0.001, (0, 0.5, 0.5)))
                strip.handle(glassFrame(time + 0.03))
            }
        }
        XCTAssertEqual(takeOvers(), 0, "the ILITEK's finger is down: the strip must not take the pointer")
        XCTAssertEqual(outputs.arbiter.owner, Desk.ilitekID)
    }

    /// The re-reviewer's probe: a tap on the same touchscreen within the hold, lifting within it.
    /// The hold still ends, and the other touchscreen then takes over, as with the setting off.
    func testATapWithinTheHoldStillLetsTheOtherTouchscreenIn() {
        let (outputs, ilitek, strip, takeOvers) = twoTouchscreens()
        var script = SwipeScript(ilitek, surface: surface, at: 10)
        script.land()
        script.move(-50)
        script.lift()
        let lift = script.time
        ilitek.handle(glassFrame(lift + 0.05, (7, 0.5, 0.5)))
        ilitek.handle(glassFrame(lift + 0.08))
        var time = lift
        while time < lift + 0.25 {
            time += 0.01
            ilitek.tick(at: time)
        }
        strip.handle(glassFrame(lift + 0.26, (0, 0.5, 0.5)))
        XCTAssertEqual(takeOvers(), 1)
        XCTAssertEqual(outputs.arbiter.owner, Desk.stripID)
    }

    func testATapOnTheOtherTouchscreenAfterTheHoldTakesOverAsWithTheSettingOff() {
        for after in [0.25, 0.3, 0.38] {
            let off = tapOnTheStrip(after: after, follow: false)
            let on = tapOnTheStrip(after: after, follow: true)
            XCTAssertEqual(off.takeOvers, 1, "\(after)")
            XCTAssertEqual(on.takeOvers, off.takeOvers, "\(after) s after the lift, beyond the 0.2 s hold")
            XCTAssertEqual(on.downs, off.downs, "\(after)")
        }
        // Within the hold, still kept off.
        let early = tapOnTheStrip(after: 0.1, follow: true)
        XCTAssertEqual(early.takeOvers, 0)
        XCTAssertEqual(early.downs, 0)
    }

    // MARK: - The property, through a pipeline

    /// Random three- and four-finger sessions, followed or not, available or not, cut short at
    /// random in every way a pipeline stops: every Dock `began` has exactly one end, no end comes
    /// without a `began`, and a swipe the Dock moved never also posts the shortcut; one the Dock slid
    /// back posts it only when it was closed from outside and the fingers completed it.
    func testEveryBeganHasExactlyOneEndAndNeverBoth() {
        var generator = SplitMix64(seed: 0x5_2D0C)
        var began = 0, completed = 0, cancelled = 0, shortcuts = 0
        for session in 0..<600 {
            let outputs = RecordingOutputs()
            outputs.dockSurroundings.isSpaceSwipeEnabled = Int.random(in: 0..<5, using: &generator) != 0
            let followsSetting = Int.random(in: 0..<4, using: &generator) != 0
            let p = pipeline(Desk.driving(on: Desk.hdmi, diagonal: 23.8, swipesFollowFingers: followsSetting), outputs)
            var script = SwipeScript(p, surface: surface, at: 10, fingers: Int.random(in: 3...4, using: &generator))
            script.land()
            for _ in 0..<Int.random(in: 1...4, using: &generator) {
                script.move(Double.random(in: -40...40, using: &generator), steps: Int.random(in: 2...15, using: &generator))
            }
            var closedFromOutside = false
            switch Int.random(in: 0..<6, using: &generator) {
            case 0: p.cancel(at: script.time, reason: .stoppedDriving)
            case 1: p.tick(at: script.time + TouchPipeline.silenceLimit + 0.1)
            case 2:
                closedFromOutside = outputs.dockSwipes.isOpen
                outputs.dockSwipes.closeIfOpen()
            case 3:
                script.time += 0.01
                p.handle(ContactFrame(time: script.time, contacts: script.fingers.map {
                    Contact(id: $0.id, position: CGPoint(x: $0.x, y: $0.y), isConfident: $0.id != 0)
                }))
            default: break
            }
            script.move(Double.random(in: -20...20, using: &generator), steps: 3)
            script.lift()
            p.tick(at: script.time + 2)

            let phases = outputs.dockPhases
            let label = "session \(session): \(phases)"
            let begun = phases.filter { $0 == .began }.count
            let ends = phases.filter { $0 == .ended || $0 == .cancelled }.count
            XCTAssertLessThanOrEqual(begun, 1, label)
            XCTAssertEqual(begun, ends, label)
            if begun > 0 {
                XCTAssertEqual(phases.first, .began, label)
                XCTAssertTrue(phases.last == .ended || phases.last == .cancelled, label)
                // Never both: a Dock end that moved the Desktop is never followed by the shortcut,
                // and a swipe the Dock slid back gets the shortcut only when closed from outside.
                if phases.contains(.ended) || !closedFromOutside {
                    XCTAssertEqual(outputs.shortcuts, 0, "\(label): never both")
                }
            }
            XCTAssertFalse(outputs.dockSwipes.isOpen, label)
            XCTAssertLessThanOrEqual(outputs.shortcuts, 1, label)
            XCTAssertEqual(outputs.count(.down), outputs.count(.up), label)
            began += begun
            completed += phases.filter { $0 == .ended }.count
            cancelled += phases.filter { $0 == .cancelled }.count
            shortcuts += outputs.shortcuts
        }
        XCTAssertGreaterThan(began, 100)
        XCTAssertGreaterThan(completed, 20)
        XCTAssertGreaterThan(cancelled, 50)
        XCTAssertGreaterThan(shortcuts, 30)
    }

    // MARK: - Two touchscreens, both following, one sender

    /// One touchscreen's random touches: one or two touches of three or four fingers 25 mm apart,
    /// each moving one to three times (one move in six mostly vertical), sometimes with a finger
    /// lifting first, then all lifting; 0.05 to 0.4 s between touches. Contact IDs from `base`.
    private func randomTouches(_ generator: inout SplitMix64, from start: TimeInterval, surface: CGSize,
                               base: Int) -> [ContactFrame] {
        var frames: [ContactFrame] = []
        var time = start
        let spacing = 25 / surface.width
        for touch in 0..<Int.random(in: 1...2, using: &generator) {
            var fingers: [(id: Int, x: CGFloat, y: CGFloat)] = (0..<Int.random(in: 3...4, using: &generator)).map {
                (id: base + touch * 10 + $0, x: 0.4 + CGFloat($0) * spacing, y: 0.5)
            }
            func frame() -> ContactFrame {
                ContactFrame(time: time, contacts: fingers.map { Contact(id: $0.id, position: CGPoint(x: $0.x, y: $0.y)) })
            }
            frames.append(frame())
            for _ in 0..<Int.random(in: 1...3, using: &generator) {
                var dx = Double.random(in: -45...45, using: &generator)
                var dy = Double.random(in: -6...6, using: &generator)
                if Int.random(in: 0..<6, using: &generator) == 0 { swap(&dx, &dy) }
                let steps = Int.random(in: 2...15, using: &generator)
                for _ in 0..<steps {
                    time += 0.01
                    fingers = fingers.map {
                        ($0.id, $0.x + CGFloat(dx) / CGFloat(steps) / surface.width,
                         $0.y + CGFloat(dy) / CGFloat(steps) / surface.height)
                    }
                    frames.append(frame())
                }
            }
            if Bool.random(using: &generator) {
                time += 0.01
                fingers.removeFirst()
                frames.append(frame())
            }
            time += 0.01
            frames.append(ContactFrame(time: time, contacts: []))
            time += Double.random(in: 0.05...0.4, using: &generator)
        }
        return frames
    }

    /// What is done at one random step of a session, before its frame or tick.
    private enum TwoTouchscreenStop: CaseIterable {
        case none, stopILITEK, stopStrip, closeFromOutside
    }

    /// The final review's probe B. Both touchscreens follow their swipes, through one shared sender;
    /// their random touches are interleaved on one timeline, both pipelines ticked every 10 ms, with
    /// at one random step a stop of either or a close from outside; take-overs are carried out as the
    /// model does. Over 1,500 seeded sessions: no swipe begins while another is open (but at a stop's
    /// step), no shortcut is posted while a Dock swipe stays open, every began has one end and no end
    /// comes without one, and at the end nothing is open, no button is held, and no touchscreen owns
    /// the pointer.
    func testTwoTouchscreensBothFollowingShareOneSenderSafely() {
        var generator = SplitMix64(seed: 0xB0B_F00D)
        var failures = 0
        var began = 0, sessionsWhereBothFollowed = 0, takeOvers = 0
        let ilitekDriving = Desk.driving(on: Desk.hdmi, diagonal: 23.8, swipesFollowFingers: true)
        let stripDriving = Desk.driving(on: Desk.lg, diagonal: 27, swipesFollowFingers: true)
        for session in 0..<1500 {
            let outputs = RecordingOutputs()
            var pipelines: [TouchscreenID: TouchPipeline] = [:]
            let cancelOther: @MainActor (TouchscreenID, TimeInterval) -> Void = { other, time in
                takeOvers += 1
                pipelines[other]?.cancel(at: time, reason: .takenOver)
            }
            let ilitek = TouchPipeline(id: Desk.ilitekID, driving: ilitekDriving, outputs: outputs, cancelOther: cancelOther)
            let strip = TouchPipeline(id: Desk.stripID, driving: stripDriving, outputs: outputs, cancelOther: cancelOther)
            pipelines = [Desk.ilitekID: ilitek, Desk.stripID: strip]
            let ilitekFrames = randomTouches(&generator, from: 10, surface: ilitekDriving.surfaceSizeMM, base: 0)
            let stripFrames = randomTouches(&generator, from: 10 + Double.random(in: -0.2...0.5, using: &generator),
                                            surface: stripDriving.surfaceSizeMM, base: 100)
            // One timeline: each frame to its pipeline, and both ticked every 10 ms.
            enum Step { case ilitek(ContactFrame), strip(ContactFrame), tick(TimeInterval) }
            var steps: [(time: TimeInterval, order: Int, step: Step)] =
                ilitekFrames.map { ($0.time, 0, .ilitek($0)) } + stripFrames.map { ($0.time, 1, .strip($0)) }
            let end = max(ilitekFrames.last?.time ?? 10, stripFrames.last?.time ?? 10) + 1
            var t = 9.8
            while t < end {
                t += 0.01
                steps.append((t, 2, .tick(t)))
            }
            steps.sort { $0.time != $1.time ? $0.time < $1.time : $0.order < $1.order }
            let stopAt = Int.random(in: 0..<steps.count, using: &generator)
            let stop = TwoTouchscreenStop.allCases[Int.random(in: 0..<TwoTouchscreenStop.allCases.count, using: &generator)]

            var why: String?
            var ilitekFollowed = false, stripFollowed = false
            for (index, (time, _, step)) in steps.enumerated() {
                let wasOpen = outputs.dockSwipes.isOpen
                let phasesBefore = outputs.dockPhases.count
                let shortcutsBefore = outputs.shortcuts
                var stopped = false
                if index == stopAt {
                    stopped = stop != .none
                    switch stop {
                    case .none: break
                    case .stopILITEK: ilitek.cancel(at: time, reason: .stoppedDriving)
                    case .stopStrip: strip.cancel(at: time, reason: .stoppedDriving)
                    case .closeFromOutside: outputs.dockSwipes.closeIfOpen()
                    }
                }
                switch step {
                case .ilitek(let frame):
                    ilitek.handle(frame)
                case .strip(let frame):
                    strip.handle(frame)
                case .tick(let time):
                    ilitek.tick(at: time)
                    strip.tick(at: time)
                }
                let new = outputs.dockPhases.dropFirst(phasesBefore)
                if new.contains(.began) {
                    if case .ilitek = step { ilitekFollowed = true }
                    if case .strip = step { stripFollowed = true }
                }
                if wasOpen, !stopped, new.contains(.began) {
                    why = why ?? "step \(index): a swipe began while another was open: \(Array(new))"
                }
                if wasOpen, outputs.dockSwipes.isOpen, outputs.shortcuts > shortcutsBefore, !new.contains(.began) {
                    why = why ?? "step \(index): a shortcut while a Dock swipe stayed open"
                }
            }
            ilitek.tick(at: end + 2)
            strip.tick(at: end + 2)
            if ilitekFollowed && stripFollowed { sessionsWhereBothFollowed += 1 }

            let phases = outputs.dockPhases
            var open = false
            for phase in phases {
                switch phase {
                case .began:
                    if open { why = why ?? "a began while open: \(phases)" }
                    open = true
                case .changed:
                    if !open { why = why ?? "a changed while closed: \(phases)" }
                case .ended, .cancelled:
                    if !open { why = why ?? "an end while closed: \(phases)" }
                    open = false
                }
            }
            began += phases.filter { $0 == .began }.count
            if open || outputs.dockSwipes.isOpen { why = why ?? "left open" }
            if outputs.count(.down) != outputs.count(.up) { why = why ?? "a button left held" }
            if let owner = outputs.arbiter.owner { why = why ?? "the pointer still owned by \(owner)" }
            if let why {
                failures += 1
                if failures <= 10 { XCTFail("session \(session), \(stop) at step \(stopAt): \(why)") }
            }
        }
        XCTAssertEqual(failures, 0)
        // The sessions do what they are for: many followed swipes, sessions in which both
        // touchscreens' swipes were followed, and the pointer taken over between them.
        // Seeded: 2,219 began, 360 sessions where both followed, 451 take-overs.
        XCTAssertGreaterThan(began, 1000)
        XCTAssertGreaterThan(sessionsWhereBothFollowed, 150)
        XCTAssertGreaterThan(takeOvers, 200)
    }

    func testTheRepeatedEndGoesOnceAndNotAfterANewSwipe() {
        let outputs = RecordingOutputs()
        let p = pipeline(following, outputs)
        swipeLeft(p, at: 10, surface: surface)
        XCTAssertEqual(outputs.dockSwipeEvents.filter(\.isEnd).count, 1)
        outputs.runDockScheduled()
        XCTAssertEqual(outputs.dockSwipeEvents.filter(\.isEnd).map(\.phase), [.ended, .ended], "repeated once")

        // A new swipe begins before the first's repeat is due: that repeat never goes.
        swipeLeft(p, at: 20, surface: surface)
        var script = SwipeScript(p, surface: surface, at: 30)
        script.land()
        script.move(-30)
        outputs.runDockScheduled()
        XCTAssertEqual(outputs.dockSwipeEvents.filter(\.isEnd).map(\.phase), [.ended, .ended, .ended],
                       "the second swipe's end, and no repeat of it while the third is open")
        XCTAssertTrue(outputs.dockSwipes.isOpen)
        p.cancel(at: script.time, reason: .stoppedDriving)
        XCTAssertFalse(outputs.dockSwipes.isOpen)
    }
}
