import CoreGraphics
import Foundation
import TactileApp
import TactileGestures
import TactileOutput
import TactileReading
import TactileScreens
import XCTest

private typealias Desk = DeskFixture

/// Two or more pipelines sharing one set of outputs, with a take-over wired as the model wires it:
/// the touchscreen that had the pointer is cancelled, `.takenOver`. With `observed`, each has the
/// gesture tester's observer, holding swipes as the tester does by default.
@MainActor
private final class Pipelines {
    let outputs: RecordingOutputs
    private let observed: Bool
    private(set) var byID: [TouchscreenID: TouchPipeline] = [:]
    private(set) var takeOvers: [TouchscreenID] = []
    private var observers: [NarratingObserver] = []

    init(outputs: RecordingOutputs? = nil, observed: Bool = false) {
        self.outputs = outputs ?? RecordingOutputs()
        self.observed = observed
    }

    @discardableResult
    func add(_ id: TouchscreenID, _ driving: Driving, fingersAlreadyDown: Bool = false) -> TouchPipeline {
        let pipeline = TouchPipeline(
            id: id, driving: driving, outputs: outputs,
            cancelOther: { [unowned self] other, time in
                takeOvers.append(other)
                byID[other]?.cancel(at: time, reason: .takenOver)
            },
            fingersAlreadyDown: fingersAlreadyDown)
        if observed {
            let observer = NarratingObserver()
            observers.append(observer)
            pipeline.observer = observer
        }
        byID[id] = pipeline
        return pipeline
    }
}

@MainActor
class TouchPipelineTests: XCTestCase {
    /// Whether this run has every behaviour after 0.2.0 off (see `DeskFixture.newOptionsOff`).
    class var newOptionsOff: Bool { false }
    /// Whether every pipeline made here has the gesture tester open on it (`TouchPipelineTestsWithATesterOpen`).
    class var testerIsOpen: Bool { false }
    /// The testers' observers, kept while the test runs: a pipeline holds its observer weakly.
    private var observers: [NarratingObserver] = []

    override func setUp() async throws {
        DeskFixture.newOptionsOff = Self.newOptionsOff
    }

    override func tearDown() async throws {
        DeskFixture.newOptionsOff = false
    }

    // Made when used, so that they follow `DeskFixture.newOptionsOff`.
    private var ilitekDriving: Driving { Desk.driving(on: Desk.hdmi, diagonal: 23.8) }
    private var stripDriving: Driving { Desk.driving(on: Desk.strip, diagonal: 12.3, options: Desk.noGestures) }

    /// Where `driving` puts a glass point on the desktop.
    private func desktop(_ glass: CGPoint, _ driving: Driving) -> CGPoint {
        driving.mapping.desktopPoint(forDisplay: driving.mapping.displayPoint(forGlass: glass))
    }

    private func single(_ id: TouchscreenID, _ driving: Driving, outputs: RecordingOutputs) -> TouchPipeline {
        observed(TouchPipeline(id: id, driving: driving, outputs: outputs, cancelOther: { other, _ in
            XCTFail("nothing to take over from \(other)")
        }))
    }

    /// `pipeline`, with the tester open on it when it is open in this run.
    private func observed(_ pipeline: TouchPipeline) -> TouchPipeline {
        if Self.testerIsOpen {
            let observer = NarratingObserver()
            observers.append(observer)
            pipeline.observer = observer
        }
        return pipeline
    }

    /// Pipelines sharing `outputs`, observed when the tester is open in this run.
    private func pipelines(outputs: RecordingOutputs? = nil) -> Pipelines {
        Pipelines(outputs: outputs, observed: Self.testerIsOpen)
    }

    // MARK: - The plan's tests

    func testATapClicksAtTheMappedPoint() throws {
        let frames = try SurveyTakes.ilitek(take: 9)
        let outputs = RecordingOutputs()
        let pipeline = single(Desk.ilitekID, ilitekDriving, outputs: outputs)
        frames.forEach(pipeline.handle)

        let glass = try XCTUnwrap(frames.first?.contacts.first?.position)
        let point = desktop(glass, ilitekDriving)
        XCTAssertTrue(Desk.hdmi.frame.contains(point), "\(point)")
        let buttons = outputs.events.filter { $0.kind == .down || $0.kind == .up }
        XCTAssertEqual(buttons.map(\.kind), [.down, .up])
        XCTAssertEqual(buttons.map(\.location), [point, point])
        XCTAssertEqual(buttons.map(\.clickState), [1, 1])
        XCTAssertEqual(outputs.events.map(\.kind), [.move, .down, .up], "the pointer moves to the finger, then one click")

        // The session ends once the double-tap window has passed, and the pointer goes home.
        XCTAssertTrue(pipeline.needsTicks)
        pipeline.tick(at: try XCTUnwrap(frames.last?.time) + 0.5)
        XCTAssertFalse(pipeline.needsTicks)
        XCTAssertEqual(outputs.record.warps, [Desk.pointerHome])
        XCTAssertNil(outputs.arbiter.owner)
    }

    func testTheStripTapsOnItsOwnDisplay() throws {
        let frames = try SurveyTakes.strip(take: 9)
        let outputs = RecordingOutputs()
        // The finger rests 1.78 s: with long-press off, a tap. Long-press through the pipeline is
        // covered in M5.
        let pipeline = single(Desk.stripID, with(stripDriving) { $0.options.longPress = false }, outputs: outputs)
        frames.forEach(pipeline.handle)

        XCTAssertEqual(outputs.count(.down), 1)
        XCTAssertEqual(outputs.count(.up), 1)
        for event in outputs.events {
            XCTAssertTrue(Desk.strip.frame.contains(event.location), "\(event.kind) at \(event.location)")
        }
    }

    /// Review Focus 1.
    func testUnpluggedMidDrag() throws {
        let frames = try SurveyTakes.ilitek(take: 11)
        let outputs = RecordingOutputs()
        let pipelines = pipelines(outputs: outputs)
        let ilitek = pipelines.add(Desk.ilitekID, ilitekDriving)
        let half = frames.count / 2
        frames.prefix(half).forEach(ilitek.handle)
        XCTAssertEqual(outputs.count(.down), 1, "the drag has started")
        XCTAssertGreaterThan(outputs.count(.drag), 0)
        XCTAssertEqual(outputs.count(.up), 0)
        let lastDrag = try XCTUnwrap(outputs.events(.drag).last)

        ilitek.cancel(at: frames[half - 1].time, reason: .stoppedDriving)

        XCTAssertEqual(outputs.events.last?.kind, .up, "the button is released")
        XCTAssertEqual(outputs.events.last?.location, lastDrag.location, "where the finger was, on its display")
        XCTAssertEqual(outputs.record.arrowHidden, [true, false], "the keeper was told cancelled: the arrow is back")
        XCTAssertEqual(outputs.record.warps, [], "never ended: the pointer is not sent home")
        XCTAssertNil(outputs.arbiter.owner)
        XCTAssertFalse(ilitek.needsTicks)
        XCTAssertEqual(outputs.record.circles.last, .hide(display: Desk.hdmi.displayID))

        // The rest of the take reaches nothing: the pipeline is never used again.
        let before = outputs.events.count
        frames.dropFirst(half).forEach(ilitek.handle)
        XCTAssertEqual(outputs.events.count, before)

        // The pointer is free for the other touchscreen.
        let strip = pipelines.add(Desk.stripID, stripDriving)
        let t = try XCTUnwrap(frames.last?.time) + 1
        strip.handle(glassFrame(t, (0, 0.5, 0.5)))
        strip.handle(glassFrame(t + 0.05))
        XCTAssertEqual(outputs.count(.down), 2)
        XCTAssertEqual(outputs.count(.up), 2)
        XCTAssertEqual(pipelines.takeOvers, [])
    }

    /// Review Focus 2.
    func testTakeOverDuringMomentum() throws {
        let pipelines = pipelines()
        let outputs = pipelines.outputs
        let ilitek = pipelines.add(Desk.ilitekID, with(ilitekDriving) { $0.oneFinger = .alwaysScroll })
        let strip = pipelines.add(Desk.stripID, stripDriving)

        // A one-finger flick upwards on the ILITEK, lifting while it moves fast.
        let t0: TimeInterval = 100
        for step in 0...10 {
            ilitek.handle(glassFrame(t0 + Double(step) * 0.01, (0, 0.5, 0.8 - CGFloat(step) * 0.03)))
        }
        ilitek.handle(glassFrame(t0 + 0.11))
        ilitek.tick(at: t0 + 0.12)
        ilitek.tick(at: t0 + 0.13)
        XCTAssertEqual(outputs.events.filter { $0.momentumPhase == 1 }.count, 1, "it coasts")
        XCTAssertTrue(ilitek.needsTicks)
        let onHDMI = outputs.record.pointer
        XCTAssertTrue(Desk.hdmi.frame.contains(onHDMI), "the pointer is on the ILITEK's display now")

        // The strip is touched while the ILITEK coasts.
        let firstStripEvent = outputs.events.count
        strip.handle(glassFrame(t0 + 0.2, (0, 0.5, 0.5)))
        XCTAssertEqual(pipelines.takeOvers, [Desk.ilitekID])
        let afterTouch = Array(outputs.events.dropFirst(firstStripEvent))
        XCTAssertEqual(afterTouch.first?.momentumPhase, 3, "the ILITEK's momentum ends first")
        XCTAssertEqual(afterTouch.dropFirst().first?.kind, .move, "then the strip's session begins")
        XCTAssertTrue(Desk.strip.frame.contains(afterTouch.dropFirst().first?.location ?? .zero))
        XCTAssertFalse(ilitek.needsTicks)
        XCTAssertEqual(outputs.arbiter.owner, Desk.stripID)

        strip.handle(glassFrame(t0 + 0.3))
        strip.tick(at: t0 + 0.8)
        XCTAssertEqual(outputs.count(.down), 1)
        XCTAssertEqual(outputs.record.arrowHidden, [true, true], "the keeper saw no cancel")
        XCTAssertEqual(outputs.record.warps, [Desk.pointerHome], "home is where the pointer was before any touching")
        XCTAssertNil(outputs.arbiter.owner)
    }

    func testTouchWhileTheOtherHoldsThePointer() throws {
        let pipelines = pipelines()
        let outputs = pipelines.outputs
        let ilitek = pipelines.add(Desk.ilitekID, ilitekDriving)
        let strip = pipelines.add(Desk.stripID, stripDriving)

        ilitek.handle(glassFrame(1.00, (0, 0.3, 0.3)))
        let afterILITEK = outputs.events.count
        let circlesBefore = outputs.record.circles.count
        strip.handle(glassFrame(1.02, (0, 0.5, 0.5)))
        ilitek.handle(glassFrame(1.04, (0, 0.3, 0.3)))
        strip.handle(glassFrame(1.06, (0, 0.5, 0.5)))
        XCTAssertEqual(outputs.events.count, afterILITEK, "the strip's touch gives no events")
        let stripCircles = outputs.record.circles.dropFirst(circlesBefore).filter {
            if case .show(Desk.strip.displayID, _, _, _) = $0 { return true }
            return false
        }
        XCTAssertEqual(stripCircles, Array(repeating: .show(display: Desk.strip.displayID, fingers: [0: CGPoint(x: 0.5, y: 0.5)],
                                                             hollow: [0]), count: 2), "drawn hollow")

        // The ILITEK lifts: its tap clicks. The strip's finger, still down, stays ignored: half a
        // gesture never starts.
        ilitek.handle(glassFrame(1.08))
        XCTAssertEqual(outputs.count(.down), 1)
        let afterTap = outputs.events.count
        strip.handle(glassFrame(1.10, (0, 0.5, 0.5)))
        strip.handle(glassFrame(1.12))
        XCTAssertEqual(outputs.events.count, afterTap)
        XCTAssertEqual(pipelines.takeOvers, [])

        // A new touch on the strip takes over.
        strip.handle(glassFrame(1.20, (0, 0.5, 0.5)))
        strip.handle(glassFrame(1.25))
        XCTAssertEqual(pipelines.takeOvers, [Desk.ilitekID])
        XCTAssertEqual(outputs.count(.down), 2)
        let stripDown = try XCTUnwrap(outputs.events(.down).dropFirst().first, "the strip's touch presses")
        XCTAssertTrue(Desk.strip.frame.contains(stripDown.location))
    }

    func testOptionsAndLimitMoveTogether() {
        // A two-finger tap with every gesture on is a right-click.
        let control = RecordingOutputs()
        let allOn = single(Desk.ilitekID, ilitekDriving, outputs: control)
        twoFingerTap(allOn)
        XCTAssertEqual(control.count(.rightDown), 1)

        // After `update` with every gesture off, the second finger is refused and drawn hollow; the
        // first one's tap clicks.
        let outputs = RecordingOutputs()
        let pipeline = single(Desk.ilitekID, ilitekDriving, outputs: outputs)
        pipeline.update(with(ilitekDriving) { $0.options = Desk.noGestures })
        twoFingerTap(pipeline)
        XCTAssertEqual(outputs.count(.rightDown), 0)
        XCTAssertEqual(outputs.count(.down), 1)
        XCTAssertTrue(outputs.record.circles.contains(.show(
            display: Desk.hdmi.displayID, fingers: [0: CGPoint(x: 0.4, y: 0.4), 1: CGPoint(x: 0.6, y: 0.4)], hollow: [1])))
    }

    private func twoFingerTap(_ pipeline: TouchPipeline) {
        pipeline.handle(glassFrame(1.00, (0, 0.4, 0.4)))
        pipeline.handle(glassFrame(1.02, (0, 0.4, 0.4), (1, 0.6, 0.4)))
        pipeline.handle(glassFrame(1.10, (0, 0.4, 0.4), (1, 0.6, 0.4)))
        pipeline.handle(glassFrame(1.15))
    }

    func testCirclesOffShowsNone() throws {
        let outputs = RecordingOutputs()
        let pipeline = single(Desk.ilitekID, with(ilitekDriving) { $0.showsCircles = false }, outputs: outputs)
        try SurveyTakes.ilitek(take: 11).prefix(40).forEach(pipeline.handle)
        pipeline.cancel(at: 1e6, reason: .stoppedDriving)
        XCTAssertGreaterThan(outputs.events.count, 0)
        XCTAssertEqual(outputs.record.circles, [])
    }

    func testTurningCirclesOffHidesThem() {
        let outputs = RecordingOutputs()
        let pipeline = single(Desk.ilitekID, ilitekDriving, outputs: outputs)
        pipeline.handle(glassFrame(1.0, (0, 0.5, 0.5)))
        pipeline.update(with(ilitekDriving) { $0.showsCircles = false })
        XCTAssertEqual(outputs.record.circles.last, .hide(display: Desk.hdmi.displayID))
        let count = outputs.record.circles.count
        pipeline.handle(glassFrame(1.1, (0, 0.5, 0.5)))
        XCTAssertEqual(outputs.record.circles.count, count)
    }

    func testScrollDistancesAreInPointsOfTheDisplay() {
        // 0.2 − 0.1 is exactly 0.1 in binary floating point, and 0.1 × 1440 exactly 144.
        for (start, end, axis) in [((0.5, 0.1), (0.5, 0.2), "vertical"), ((0.1, 0.5), (0.2, 0.5), "horizontal")] {
            let outputs = RecordingOutputs()
            let pipeline = single(Desk.ilitekID, with(ilitekDriving) { $0.oneFinger = .alwaysScroll }, outputs: outputs)
            pipeline.handle(glassFrame(1.00, (0, start.0, start.1)))
            pipeline.handle(glassFrame(1.01, (0, end.0, end.1)))
            pipeline.handle(glassFrame(1.30))
            let scrolls = outputs.events(.scroll)
            XCTAssertEqual(scrolls.map(\.scrollPhase), [1, 4], axis)
            if axis == "vertical" {
                XCTAssertEqual(abs(scrolls.map(\.scrollY).reduce(0, +)), 144, "10% of 1440 points")
                XCTAssertEqual(scrolls.map(\.scrollX).reduce(0, +), 0)
            } else {
                XCTAssertEqual(abs(scrolls.map(\.scrollX).reduce(0, +)), 256, "10% of 2560 points")
                XCTAssertEqual(scrolls.map(\.scrollY).reduce(0, +), 0)
            }
        }
    }

    func testEveryPressHasItsRelease() throws {
        var generator = SplitMix64(seed: 0x7AC7_11E0)
        var takes: [(String, TouchscreenID, Driving, [ContactFrame])] = []
        for number in SurveyTakes.ilitekTakes {
            takes.append(("ILITEK take \(number)", Desk.ilitekID, ilitekDriving, try SurveyTakes.ilitek(take: number)))
        }
        for number in SurveyTakes.stripTakes {
            takes.append(("strip take \(number)", Desk.stripID, stripDriving, try SurveyTakes.strip(take: number)))
        }
        var cancelledMidTouch = 0
        for (name, id, driving, frames) in takes where !frames.isEmpty {
            for reason in [TouchPipeline.CancelReason.stoppedDriving, .takenOver] {
                let cut = Int.random(in: 1...frames.count, using: &generator)
                let outputs = RecordingOutputs()
                let pipeline = single(id, driving, outputs: outputs)
                for frame in frames.prefix(cut) {
                    pipeline.handle(frame)
                    pipeline.tick(at: frame.time)
                }
                if !frames[cut - 1].contacts.isEmpty { cancelledMidTouch += 1 }
                pipeline.cancel(at: frames[cut - 1].time, reason: reason)
                let label = "\(name), cut at \(cut) of \(frames.count), \(reason)"
                XCTAssertEqual(outputs.count(.down), outputs.count(.up), label)
                XCTAssertEqual(outputs.count(.rightDown), outputs.count(.rightUp), label)
                let scrolls = outputs.events(.scroll)
                XCTAssertEqual(scrolls.filter { $0.scrollPhase == 1 }.count, scrolls.filter { $0.scrollPhase == 4 }.count, label)
                XCTAssertEqual(scrolls.filter { $0.momentumPhase == 1 }.count, scrolls.filter { $0.momentumPhase == 3 }.count, label)
                let pinches = outputs.events(.gesture)
                XCTAssertEqual(pinches.filter { $0.gesturePhase == 1 }.count, pinches.filter { $0.gesturePhase == 4 }.count, label)
                // A pipeline taken over lives on: with fingers still down it waits for their frames.
                XCTAssertEqual(pipeline.needsTicks, reason == .takenOver && !frames[cut - 1].contacts.isEmpty, label)
            }
        }
        XCTAssertGreaterThan(cancelledMidTouch, 20, "most cuts fall while a finger is down")
    }

    func testATakenOverPipelineWorksAgain() {
        let pipelines = pipelines()
        let outputs = pipelines.outputs
        let ilitek = pipelines.add(Desk.ilitekID, ilitekDriving)
        let strip = pipelines.add(Desk.stripID, stripDriving)

        ilitek.handle(glassFrame(1.0, (0, 0.3, 0.3)))
        ilitek.handle(glassFrame(1.1))
        strip.handle(glassFrame(1.2, (0, 0.5, 0.5)))
        XCTAssertEqual(pipelines.takeOvers, [Desk.ilitekID])
        strip.handle(glassFrame(1.3))
        strip.tick(at: 1.8)
        XCTAssertNil(outputs.arbiter.owner, "the strip's session has ended")

        ilitek.handle(glassFrame(2.0, (0, 0.3, 0.3)))
        ilitek.handle(glassFrame(2.1))
        let ilitekClicks = outputs.events(.down).filter { Desk.hdmi.frame.contains($0.location) }
        XCTAssertEqual(ilitekClicks.count, 2)
        XCTAssertEqual(ilitekClicks.last?.clickState, 1, "a fresh tap, not a double-click across the take-over")
    }

    func testALostLiftIsCancelledAfterSilence() {
        let pipelines = pipelines()
        let outputs = pipelines.outputs
        let ilitek = pipelines.add(Desk.ilitekID, with(ilitekDriving) { $0.oneFinger = .alwaysDrag })

        // A drag, and then nothing: the lift report was lost.
        ilitek.handle(glassFrame(10.00, (0, 0.30, 0.3)))
        ilitek.handle(glassFrame(10.05, (0, 0.35, 0.3)))
        XCTAssertEqual(outputs.count(.down), 1)
        XCTAssertTrue(ilitek.needsTicks)
        var time = 10.05
        while time < 10.05 + 1.4 {
            time += 1.0 / 60
            ilitek.tick(at: min(time, 10.05 + 1.4))
        }
        XCTAssertEqual(outputs.count(.up), 0, "1.4 s of silence is not enough")
        XCTAssertEqual(outputs.arbiter.owner, Desk.ilitekID)

        ilitek.tick(at: 10.05 + 1.6)
        XCTAssertEqual(outputs.events.last?.kind, .up, "the button is released")
        XCTAssertEqual(outputs.record.arrowHidden, [true, false], "cancelled, as when it stops driving")
        XCTAssertEqual(outputs.record.warps, [])
        XCTAssertNil(outputs.arbiter.owner, "the pointer is free")
        XCTAssertFalse(ilitek.needsTicks)

        // The pipeline is still in use: the next touch works. (One with the same contact ID within
        // the silence limit of the cancel would be taken for the lost one: see the next test.)
        ilitek.handle(glassFrame(13.5, (0, 0.5, 0.5)))
        ilitek.handle(glassFrame(13.6))
        XCTAssertEqual(outputs.count(.down), 2)
        XCTAssertEqual(outputs.count(.up), 2)
        XCTAssertEqual(outputs.events.last?.location, desktop(CGPoint(x: 0.5, y: 0.5), ilitekDriving))
    }

    func testAStallDoesNotSplitADrag() throws {
        let frames = try SurveyTakes.ilitek(take: 11)
        let outputs = RecordingOutputs()
        let pipeline = single(Desk.ilitekID, ilitekDriving, outputs: outputs)
        let half = frames.count / 2
        frames.prefix(half).forEach(pipeline.handle)
        XCTAssertEqual(outputs.count(.down), 1)

        // The main thread stalls for 1.6 s. The first tick after it cancels the touch.
        let lastTime = frames[half - 1].time
        pipeline.tick(at: lastTime + 1.6)
        XCTAssertEqual(outputs.count(.up), 1)

        // Then the reports made during the stall arrive, timed inside it, and the drag goes on.
        let rest = frames.dropFirst(half).enumerated().map { index, frame in
            ContactFrame(time: lastTime + 0.01 * Double(index + 1), contacts: frame.contacts)
        }
        XCTAssertLessThan(try XCTUnwrap(rest.first?.time), lastTime + 1.6)
        rest.forEach(pipeline.handle)
        pipeline.tick(at: (rest.last?.time ?? lastTime) + 2)
        XCTAssertEqual(outputs.count(.down), 1, "one press")
        XCTAssertEqual(outputs.count(.up), 1, "one release")
        XCTAssertEqual(outputs.count(.drag), outputs.events.prefix { $0.kind != .up }.filter { $0.kind == .drag }.count,
                       "no drag after the release")

        // The next touch works.
        let next = (rest.last?.time ?? lastTime) + 3
        pipeline.handle(glassFrame(next, (0, 0.5, 0.5)))
        pipeline.handle(glassFrame(next + 0.1))
        XCTAssertEqual(outputs.count(.down), 2)
    }

    func testAFingerStillDownAfterASilenceIsNotANewTouch() {
        // The panel itself goes quiet for 1.7 s with the finger held, mid-drag.
        func dragThenSilence() -> (TouchPipeline, RecordingOutputs) {
            let outputs = RecordingOutputs()
            let pipeline = single(Desk.ilitekID, with(ilitekDriving) { $0.oneFinger = .alwaysDrag }, outputs: outputs)
            for step in 0...10 {
                pipeline.handle(glassFrame(100 + Double(step) * 0.05, (7, 0.3 + CGFloat(step) * 0.02, 0.5)))
            }
            pipeline.tick(at: 102.2)
            XCTAssertEqual(outputs.count(.up), 1, "cancelled by the silence")
            return (pipeline, outputs)
        }

        // The same contact comes back soon after the cancel: the same touch, ignored until it lifts.
        let (same, sameOutputs) = dragThenSilence()
        for time in stride(from: 102.25, through: 102.6, by: 0.05) {
            same.handle(glassFrame(time, (7, 0.5 + CGFloat(time - 102.25), 0.5)))
        }
        same.handle(glassFrame(102.65))
        same.tick(at: 104)
        XCTAssertEqual(sameOutputs.count(.down), 1, "one press")
        XCTAssertEqual(sameOutputs.count(.up), 1, "one release")

        // Another contact: a new touch.
        let (other, otherOutputs) = dragThenSilence()
        other.handle(glassFrame(102.25, (8, 0.5, 0.5)))
        other.handle(glassFrame(102.35))
        XCTAssertEqual(otherOutputs.count(.down), 2)

        // The same contact, but longer after the cancel than the silence limit: a new touch.
        let (late, lateOutputs) = dragThenSilence()
        late.handle(glassFrame(102.2 + TouchPipeline.silenceLimit + 0.1, (7, 0.5, 0.5)))
        late.handle(glassFrame(102.2 + TouchPipeline.silenceLimit + 0.2))
        XCTAssertEqual(lateOutputs.count(.down), 2)
    }

    func testAFingerHeldStillIsNeverCancelledWhileItsFramesArrive() {
        let outputs = RecordingOutputs()
        // Long-press off, so held then lifted is a click. Long-press through the pipeline is
        // covered in M5.
        let pipeline = single(Desk.ilitekID, with(ilitekDriving) { $0.options.longPress = false }, outputs: outputs)
        var tick = 20.0
        for frame in stride(from: 20.0, through: 25.0, by: 0.4) {
            while tick < frame {
                pipeline.tick(at: tick)
                tick += 1.0 / 60
            }
            pipeline.handle(glassFrame(frame, (0, 0.5, 0.5)))
        }
        XCTAssertEqual(outputs.count(.up), 0, "five seconds, never cancelled")
        XCTAssertEqual(outputs.record.arrowHidden, [true])
        pipeline.handle(glassFrame(25.2))
        XCTAssertEqual(outputs.count(.down), 1)
        XCTAssertEqual(outputs.count(.up), 1, "held, then lifted: a click")
    }

    // MARK: - More

    func testFingersAlreadyDownAreIgnoredUntilTheyLift() {
        let outputs = RecordingOutputs()
        let pipeline = observed(TouchPipeline(id: Desk.ilitekID, driving: ilitekDriving, outputs: outputs,
                                              cancelOther: { _, _ in }, fingersAlreadyDown: true))
        pipeline.handle(glassFrame(1.0, (0, 0.5, 0.5)))
        pipeline.handle(glassFrame(1.1, (0, 0.6, 0.5)))
        XCTAssertEqual(outputs.events, [])
        XCTAssertNil(outputs.arbiter.owner, "a finger that is not acted on doesn't hold the pointer")
        XCTAssertEqual(outputs.record.circles.last,
                       .show(display: Desk.hdmi.displayID, fingers: [0: CGPoint(x: 0.6, y: 0.5)], hollow: [0]))
        pipeline.handle(glassFrame(1.2))
        pipeline.handle(glassFrame(1.3, (0, 0.5, 0.5)))
        pipeline.handle(glassFrame(1.4))
        XCTAssertEqual(outputs.count(.down), 1, "the next touch counts")
    }

    func testOneFingerAsksWhatIsUnderTheFingerOnlyInAutomatic() {
        for (mode, asks, kind) in [(OneFingerMode.automatic, true, PostedEvent.Kind.scroll), (.alwaysDrag, false, .drag),
                                   (.alwaysScroll, false, .scroll)] {
            let outputs = RecordingOutputs()
            outputs.intentAnswer = .scroll
            let pipeline = single(Desk.ilitekID, with(ilitekDriving) { $0.oneFinger = mode }, outputs: outputs)
            pipeline.handle(glassFrame(1.00, (0, 0.25, 0.5)))
            pipeline.handle(glassFrame(1.05, (0, 0.30, 0.5)))
            pipeline.handle(glassFrame(1.10))
            let landing = desktop(CGPoint(x: 0.25, y: 0.5), ilitekDriving)
            XCTAssertEqual(outputs.record.intentQuestions, asks ? [landing] : [], "\(mode)")
            XCTAssertGreaterThan(outputs.count(kind), 0, "\(mode)")
        }
    }

    func testAnUpdateKeepsATouchGoing() {
        let outputs = RecordingOutputs()
        let pipeline = single(Desk.ilitekID, ilitekDriving, outputs: outputs)
        pipeline.handle(glassFrame(1.0, (0, 0.5, 0.5)))
        pipeline.update(with(ilitekDriving) { $0.pointerReturn = .staysWhereTouched; $0.surfaceSizeMM.width += 1 })
        pipeline.handle(glassFrame(1.1))
        pipeline.tick(at: 2)
        XCTAssertEqual(outputs.count(.down), 1)
        XCTAssertEqual(outputs.record.warps, [Desk.pointerHome], "the setting read when the session began applies")
        XCTAssertEqual(pipeline.driving.pointerReturn, .staysWhereTouched)
    }
}

/// The 2b pipeline tests again, with long-press, rotate and the rejection rules off: what 0.2.0 did
/// is still what these test.
final class TouchPipelineTestsWithNewOptionsOff: TouchPipelineTests {
    override class var newOptionsOff: Bool { true }
}

/// The 2b pipeline tests again, with the gesture tester open on every pipeline they make, holding
/// swipes as it does by default: nothing else about driving changes, on this touchscreen or the
/// other.
final class TouchPipelineTestsWithATesterOpen: TouchPipelineTests {
    override class var testerIsOpen: Bool { true }
}
