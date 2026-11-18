// Delivery 5, Part T1: a pipeline with the gesture tester open drives exactly as without it, but for
// the swipes it holds; holding never leaves a Dock swipe open, never posts one and never posts a
// shortcut for it; and every followed-swipe rule of 0.4.0 holds when swipes are let through.
// Nothing is posted: the outputs are recorded.

import CoreGraphics
import Foundation
@testable import TactileApp
import TactileGestures
import TactileOutput
import TactileReading
import TactileScreens
import XCTest

private typealias Desk = DeskFixture

@MainActor
final class TesterPipelineTests: XCTestCase {
    private let ilitek = Desk.driving(on: Desk.hdmi, diagonal: 23.8)
    private let strip = Desk.driving(on: Desk.strip, diagonal: 12.3, options: Desk.noGestures)
    private let following = Desk.driving(on: Desk.hdmi, diagonal: 23.8, swipesFollowFingers: true)

    /// How a run is observed: not at all, by a tester letting swipes through, or by one holding them.
    private enum Watch: CaseIterable {
        case none, lettingThrough, holding
    }

    /// Everything the outputs were asked to do, in order.
    private struct Record: Equatable {
        let log: [String]
        let events: [PostedEvent]
        let dock: [DockEvent]
        let circles: [CircleCall]
        let warps: [CGPoint]
        let arrow: [Bool]
        let owner: TouchscreenID?
    }

    /// `frames` through a pipeline driving with `driving`, observed as `watch` says, ticked 60 times a
    /// second in between and for a second after; then cut short at `stopAt` (an index into the
    /// frames) when given.
    private func run(_ frames: [ContactFrame], _ driving: Driving, id: TouchscreenID = Desk.ilitekID, watch: Watch,
                     stopAt: Int? = nil) -> (Record, NarratingObserver?) {
        let outputs = RecordingOutputs()
        let pipeline = TouchPipeline(id: id, driving: driving, outputs: outputs, cancelOther: { _, _ in })
        let observer: NarratingObserver? = watch == .none ? nil : NarratingObserver(holdsSwipes: watch == .holding)
        pipeline.observer = observer
        var time = frames.first?.time ?? 0
        for (index, frame) in frames.enumerated() {
            while time + 1.0 / 60 < frame.time {
                time += 1.0 / 60
                pipeline.tick(at: time)
            }
            time = frame.time
            if index == stopAt { pipeline.cancel(at: time, reason: .stoppedDriving) }
            pipeline.handle(frame)
        }
        for _ in 0..<60 {
            time += 1.0 / 60
            pipeline.tick(at: time)
        }
        outputs.runDockScheduled()
        let record = outputs.record
        return (Record(log: record.log.entries, events: record.events, dock: record.dockEvents, circles: record.circles,
                       warps: record.warps, arrow: record.arrowHidden, owner: outputs.arbiter.owner), observer)
    }

    /// The survey's takes, both touchscreens, with what each drives with.
    private func takes() throws -> [(String, TouchscreenID, Driving, [ContactFrame])] {
        var takes: [(String, TouchscreenID, Driving, [ContactFrame])] = []
        for number in SurveyTakes.ilitekTakes {
            for (oneFinger, name) in [(OneFingerMode.automatic, "automatic"), (.alwaysScroll, "always scroll")] {
                takes.append(("ILITEK \(number), \(name)", Desk.ilitekID, with(ilitek) { $0.oneFinger = oneFinger },
                              try SurveyTakes.ilitek(take: number)))
            }
        }
        for number in SurveyTakes.stripTakes {
            takes.append(("strip \(number)", Desk.stripID, strip, try SurveyTakes.strip(take: number)))
        }
        return takes
    }

    // MARK: - Nothing else changes

    /// Every take of the survey, on both touchscreens: observed or not, holding swipes or letting
    /// them through, the outputs are asked exactly the same things in the same order, and cut short
    /// at random the same way too.
    func testTheSurveysTakesDriveTheSameWithTheTesterOpen() throws {
        var generator = SplitMix64(seed: 0x7E57_E401)
        var compared = 0
        for (name, id, driving, frames) in try takes() where !frames.isEmpty {
            let stop = Int.random(in: 0..<frames.count, using: &generator)
            for stopAt in [nil, stop] {
                let (plain, _) = run(frames, driving, id: id, watch: .none, stopAt: stopAt)
                for watch in [Watch.lettingThrough, .holding] {
                    let (watched, observer) = run(frames, driving, id: id, watch: watch, stopAt: stopAt)
                    XCTAssertEqual(watched, plain, "\(name), \(watch), cut at \(stopAt.map(String.init) ?? "none")")
                    if stopAt != 0 { XCTAssertFalse(observer?.observations.isEmpty ?? true, "\(name): it was told") }
                    compared += 1
                }
            }
        }
        XCTAssertEqual(compared, (15 * 2 + 20) * 2 * 2)
    }

    /// Random three- and four-finger touches with following on: letting swipes through changes
    /// nothing at all.
    func testLettingSwipesThroughChangesNothing() {
        var generator = SplitMix64(seed: 0x5_EE5_0FF)
        var followed = 0, shortcuts = 0
        for session in 0..<300 {
            let frames = randomSwipes(&generator, surface: following.surfaceSizeMM)
            let stopAt = Int.random(in: 0..<4, using: &generator) == 0 ? Int.random(in: 0..<frames.count, using: &generator) : nil
            let (plain, _) = run(frames, following, watch: .none, stopAt: stopAt)
            let (through, _) = run(frames, following, watch: .lettingThrough, stopAt: stopAt)
            XCTAssertEqual(through, plain, "session \(session)")
            followed += plain.dock.filter { $0.isSwipe && $0.phase == .began }.count
            shortcuts += plain.events.filter { $0.kind == .keyDown }.count
        }
        XCTAssertGreaterThan(followed, 100, "the sessions follow swipes")
        XCTAssertGreaterThan(shortcuts, 20, "and post shortcuts")
    }

    // MARK: - Holding

    /// One touch of `count` fingers 25 mm apart moving `dx` mm in `steps` frames, then lifting.
    private func swipe(_ count: Int, _ dx: Double, dy: Double = 0, steps: Int = 20, at start: TimeInterval = 10,
                       surface: CGSize) -> [ContactFrame] {
        var glass = Glass(surface, at: start)
        glass.land((0..<count).map { ($0, 180 + 25 * Double($0), 150) })
        glass.move(dx, dy, steps: steps)
        glass.lift()
        return glass.frames
    }

    func testAHeldSwipePostsNothingFollowedOrNot() {
        for (name, driving) in [("one-shot", ilitek), ("followed", following)] {
            for (count, dx, dy) in [(3, -60.0, 0.0), (4, 60, 0), (3, 0, -60), (4, 0, 60)] {
                let (record, observer) = run(swipe(count, dx, dy: dy, surface: driving.surfaceSizeMM), driving, watch: .holding)
                let label = "\(name), \(count) fingers, \(dx), \(dy)"
                XCTAssertEqual(record.dock, [], "\(label): no Dock swipe")
                XCTAssertEqual(record.events.filter { $0.kind == .keyDown || $0.kind == .keyUp }, [], "\(label): no shortcut")
                XCTAssertEqual(observer?.kinds.count, 1, "\(label): \(observer?.described ?? "")")
                XCTAssertTrue(observer?.summaries.first?.hasSuffix(GestureNarrator.heldNote) == true, label)
                XCTAssertNil(record.owner, "\(label): the session ended")
            }
        }
    }

    /// A followed swipe begun while held is held to its end, whatever happens to the tester meanwhile;
    /// one begun while let through is done to its end. Never two ends, never a shortcut with a Dock
    /// swipe, never one left open.
    func testHoldingIsDecidedWhenTheSwipeBegins() {
        // Held, then let through, mid-swipe: still held.
        do {
            let outputs = RecordingOutputs()
            let tested = ObservedPipeline(Desk.ilitekID, following, outputs: outputs, holdsSwipes: true)
            var script = SwipeScript(tested.pipeline, surface: following.surfaceSizeMM, at: 10)
            script.land()
            script.move(-30)
            tested.observer.holdsSwipes = false
            script.move(-30)
            script.lift()
            tested.pipeline.tick(at: script.time + 1)
            XCTAssertEqual(outputs.record.dockEvents, [], "held from its beginning")
            XCTAssertEqual(outputs.shortcuts, 0)
            XCTAssertEqual(tested.observer.summaries, ["left: next Desktop" + GestureNarrator.heldNote])
        }
        // Held, then the tester closes mid-swipe: still held.
        do {
            let outputs = RecordingOutputs()
            var observer: NarratingObserver? = NarratingObserver(holdsSwipes: true)
            let pipeline = TouchPipeline(id: Desk.ilitekID, driving: following, outputs: outputs, cancelOther: { _, _ in })
            pipeline.observer = observer
            var script = SwipeScript(pipeline, surface: following.surfaceSizeMM, at: 10)
            script.land()
            script.move(-30)
            observer = nil
            XCTAssertNil(pipeline.observer, "the pipeline holds its observer weakly")
            script.move(-30)
            script.lift()
            pipeline.tick(at: script.time + 1)
            XCTAssertEqual(outputs.record.dockEvents, [])
            XCTAssertEqual(outputs.shortcuts, 0)
        }
        // Let through, then held mid-swipe: done, with one end.
        do {
            let outputs = RecordingOutputs()
            let tested = ObservedPipeline(Desk.ilitekID, following, outputs: outputs, holdsSwipes: false)
            var script = SwipeScript(tested.pipeline, surface: following.surfaceSizeMM, at: 10)
            script.land()
            script.move(-30)
            XCTAssertTrue(outputs.dockSwipes.isOpen)
            tested.observer.holdsSwipes = true
            script.move(-30)
            script.lift()
            tested.pipeline.tick(at: script.time + 1)
            XCTAssertEqual(outputs.dockSwipeEvents.filter(\.isEnd).map(\.phase), [.ended])
            XCTAssertFalse(outputs.dockSwipes.isOpen)
            XCTAssertEqual(outputs.shortcuts, 0)
            XCTAssertEqual(tested.observer.summaries, ["left: next Desktop"])
        }
        // Opened mid-swipe, holding: the swipe begun without it is done.
        do {
            let outputs = RecordingOutputs()
            let observer = NarratingObserver(holdsSwipes: true)
            let pipeline = TouchPipeline(id: Desk.ilitekID, driving: following, outputs: outputs, cancelOther: { _, _ in })
            var script = SwipeScript(pipeline, surface: following.surfaceSizeMM, at: 10)
            script.land()
            script.move(-30)
            pipeline.observer = observer
            script.move(-30)
            script.lift()
            pipeline.tick(at: script.time + 1)
            XCTAssertEqual(outputs.dockSwipeEvents.filter(\.isEnd).map(\.phase), [.ended])
            XCTAssertEqual(observer.kinds, [.followedSwipe], "its entry starts where the tester came in")
            XCTAssertEqual(observer.summaries, ["left: next Desktop"])
        }
    }

    /// Random three- and four-finger sessions, following or not, available or not, observed by a
    /// tester that holds or lets through, flips its mind at a random moment and may close; cut
    /// short at random in every way a pipeline stops. Every Dock `began` has exactly one end, no end
    /// comes without one, nothing is left open, a Dock swipe never also gets the shortcut, and a swipe
    /// begun while held posts nothing at all.
    func testHoldingNeverLeavesASwipeOpenOrDoesHalfOfIt() {
        var generator = SplitMix64(seed: 0x401D_5_1DE)
        var heldSwipes = 0, doneSwipes = 0, began = 0
        for session in 0..<800 {
            let outputs = RecordingOutputs()
            outputs.dockSurroundings.isSpaceSwipeEnabled = Int.random(in: 0..<5, using: &generator) != 0
            let follows = Int.random(in: 0..<4, using: &generator) != 0
            let driving = Desk.driving(on: Desk.hdmi, diagonal: 23.8, swipesFollowFingers: follows)
            var observer: NarratingObserver? = NarratingObserver(holdsSwipes: Bool.random(using: &generator))
            let p = TouchPipeline(id: Desk.ilitekID, driving: driving, outputs: outputs, cancelOther: { _, _ in })
            p.observer = observer
            var script = SwipeScript(p, surface: driving.surfaceSizeMM, at: 10, fingers: Int.random(in: 3...4, using: &generator))
            script.land()
            let moves = Int.random(in: 1...4, using: &generator)
            let flipAt = Int.random(in: 0...moves, using: &generator)
            for move in 0..<moves {
                if move == flipAt {
                    switch Int.random(in: 0..<3, using: &generator) {
                    case 0: observer?.holdsSwipes.toggle()
                    case 1: observer = nil
                    default: break
                    }
                }
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
            let label = "session \(session): \(phases), \(observer?.described ?? "closed")"
            let begun = phases.filter { $0 == .began }.count
            XCTAssertLessThanOrEqual(begun, 1, label)
            XCTAssertEqual(begun, phases.filter { $0 == .ended || $0 == .cancelled }.count, label)
            if begun > 0 {
                XCTAssertEqual(phases.first, .began, label)
                if phases.contains(.ended) || !closedFromOutside { XCTAssertEqual(outputs.shortcuts, 0, "\(label): never both") }
            }
            XCTAssertFalse(outputs.dockSwipes.isOpen, label)
            XCTAssertLessThanOrEqual(outputs.shortcuts, 1, label)
            XCTAssertEqual(outputs.count(.down), outputs.count(.up), label)
            // A swipe the tester saw decided while it held: nothing posted for it.
            let decidedHeld = observer?.observations.contains { observation in
                guard case .action(let action, held: true) = observation else { return false }
                switch action {
                case .swipe, .swipeTracking(_, _, .began): return true
                default: return false
                }
            } ?? false
            if decidedHeld {
                heldSwipes += 1
                XCTAssertEqual(outputs.record.dockEvents, [], "\(label): held, no Dock swipe")
                XCTAssertEqual(outputs.shortcuts, 0, "\(label): held, no shortcut")
            } else if begun > 0 || outputs.shortcuts > 0 {
                doneSwipes += 1
            }
            began += begun
        }
        XCTAssertGreaterThan(heldSwipes, 100, "many swipes were held")
        XCTAssertGreaterThan(doneSwipes, 100, "and many were done")
        XCTAssertGreaterThan(began, 50)
    }

    // MARK: - Helpers

    /// One or two touches of three or four fingers moving at random, mostly sideways, then lifting.
    private func randomSwipes(_ generator: inout SplitMix64, surface: CGSize) -> [ContactFrame] {
        var glass = Glass(surface, at: 10)
        for touch in 0..<Int.random(in: 1...2, using: &generator) {
            let count = Int.random(in: 3...4, using: &generator)
            glass.land((0..<count).map { (touch * 10 + $0, 150 + 25 * Double($0), 150) }, after: 0.3)
            for _ in 0..<Int.random(in: 1...3, using: &generator) {
                var dx = Double.random(in: -45...45, using: &generator)
                var dy = Double.random(in: -6...6, using: &generator)
                if Int.random(in: 0..<6, using: &generator) == 0 { swap(&dx, &dy) }
                glass.move(dx, dy, steps: Int.random(in: 2...15, using: &generator))
            }
            glass.lift()
        }
        return glass.frames
    }
}
