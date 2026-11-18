// A pipeline observer for tests, as the gesture tester is one: it keeps what it was told, and
// narrates it with a real `GestureNarrator`.

import CoreGraphics
import Foundation
@testable import TactileApp
import TactileGestures
import TactileReading
import TactileScreens

@MainActor
final class NarratingObserver: TouchPipelineObserver {
    var holdsSwipes: Bool
    private(set) var narrator = GestureNarrator()
    private(set) var observations: [TouchObservation] = []
    /// The entries each observation finished, in order.
    private(set) var finished: [RecognisedGesture] = []

    init(holdsSwipes: Bool = true) {
        self.holdsSwipes = holdsSwipes
    }

    func pipeline(_ pipeline: TouchPipeline, saw observation: TouchObservation, at time: TimeInterval) {
        observations.append(observation)
        finished += narrator.see(observation, at: time, displaySize: pipeline.driving.displayFrame.size,
                                 holdTime: pipeline.constants.holdTime)
    }

    func clear() {
        narrator.clear()
    }

    /// The feed, oldest first.
    var feed: [RecognisedGesture] { narrator.recent.reversed() }
    var kinds: [RecognisedGesture.Kind] { feed.map(\.kind) }
    var summaries: [String] { feed.map(\.summary) }
    var fingers: [Int] { feed.map(\.fingers) }

    /// The feed as "kind fingers: summary", oldest first, for messages.
    var described: String {
        feed.map { "\($0.kind.rawValue) \($0.fingers): \($0.summary)" }.joined(separator: " | ")
    }

    /// The engine's actions it was told of, in order.
    var actions: [GestureAction] {
        observations.compactMap { if case .action(let action, _) = $0 { return action } else { return nil } }
    }
}

/// A pipeline with its observer, on recording outputs: nothing is posted.
@MainActor
struct ObservedPipeline {
    let pipeline: TouchPipeline
    let observer: NarratingObserver
    let outputs: RecordingOutputs

    init(_ id: TouchscreenID, _ driving: Driving, outputs: RecordingOutputs? = nil,
         holdsSwipes: Bool = true, fingersAlreadyDown: Bool = false,
         cancelOther: @escaping @MainActor (TouchscreenID, TimeInterval) -> Void = { _, _ in }) {
        let outputs = outputs ?? RecordingOutputs()
        self.outputs = outputs
        observer = NarratingObserver(holdsSwipes: holdsSwipes)
        pipeline = TouchPipeline(id: id, driving: driving, outputs: outputs, cancelOther: cancelOther,
                                 fingersAlreadyDown: fingersAlreadyDown)
        pipeline.observer = observer
    }

    /// Feeds `frames` at their own times, ticking 60 times a second in between as the model's clock
    /// does, then lets `settle` seconds pass, ticking, so momentum and the session can end.
    func play(_ frames: [ContactFrame], settle: TimeInterval = 1) {
        play(frames, into: pipeline, settle: settle)
    }

    func play(_ frames: [ContactFrame], into pipeline: TouchPipeline, settle: TimeInterval = 1) {
        guard var time = frames.first?.time else { return }
        for frame in frames {
            while time + 1.0 / 60 < frame.time {
                time += 1.0 / 60
                pipeline.tick(at: time)
            }
            time = frame.time
            pipeline.handle(frame)
        }
        let end = time + settle
        while time < end {
            time = min(end, time + 1.0 / 60)
            pipeline.tick(at: time)
        }
    }
}

/// Builds touches on a glass of a known size, in millimetres, as frames of glass points 10 ms apart.
struct Glass {
    let surface: CGSize
    private(set) var time: TimeInterval
    private(set) var frames: [ContactFrame] = []
    /// Each finger down now, by contact ID, in millimetres.
    private var down: [(id: Int, x: Double, y: Double)] = []

    init(_ surface: CGSize, at time: TimeInterval = 100) {
        self.surface = surface
        self.time = time
    }

    private func contact(_ finger: (id: Int, x: Double, y: Double)) -> Contact {
        Contact(id: finger.id, position: CGPoint(x: finger.x / surface.width, y: finger.y / surface.height))
    }

    private mutating func emit() {
        frames.append(ContactFrame(time: time, contacts: down.map(contact)))
    }

    /// Fingers landing (id, x mm, y mm), `after` seconds after the last frame.
    mutating func land(_ fingers: [(Int, Double, Double)], after: TimeInterval = 0.01) {
        time += frames.isEmpty ? 0 : after
        down += fingers.map { (id: $0.0, x: $0.1, y: $0.2) }
        emit()
    }

    /// The fingers down stay still for `seconds`, reported every 10 ms.
    mutating func rest(_ seconds: TimeInterval) {
        for _ in 0..<Int((seconds / 0.01).rounded()) {
            time += 0.01
            emit()
        }
    }

    /// Every finger down (or those in `only`) moved by `dx`, `dy` millimetres over `steps` frames 10 ms apart.
    mutating func move(_ dx: Double, _ dy: Double, steps: Int = 10, only: Set<Int>? = nil) {
        for _ in 0..<steps {
            time += 0.01
            down = down.map { finger in
                guard only?.contains(finger.id) ?? true else { return finger }
                return (finger.id, finger.x + dx / Double(steps), finger.y + dy / Double(steps))
            }
            emit()
        }
    }

    /// Each finger moved to where `place` puts it at each of `steps` steps, 10 ms apart.
    mutating func trace(steps: Int, _ place: (_ id: Int, _ step: Int) -> (Double, Double)) {
        for step in 1...steps {
            time += 0.01
            down = down.map { finger in
                let (x, y) = place(finger.id, step)
                return (finger.id, x, y)
            }
            emit()
        }
    }

    /// The fingers with these IDs lift (all of them when nil).
    mutating func lift(_ ids: Set<Int>? = nil, after: TimeInterval = 0.01) {
        time += after
        down.removeAll { ids?.contains($0.id) ?? true }
        emit()
    }

    /// A frame of these contacts as they are, with `change` made to each.
    mutating func report(after: TimeInterval = 0.01, _ change: (inout Contact) -> Void) {
        time += after
        frames.append(ContactFrame(time: time, contacts: down.map { finger in
            var contact = contact(finger)
            change(&contact)
            return contact
        }))
    }

    /// Time passes with no frames.
    mutating func wait(_ seconds: TimeInterval) {
        time += seconds
    }
}
