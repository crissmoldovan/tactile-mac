import CoreGraphics
import XCTest
@testable import TactileGestures

final class SwipeTrackingTests: XCTestCase {

    // MARK: - Nothing followed: the engine as it was

    func testWithNothingFollowedNoRandomSessionTracksASwipe() {
        var generator = SplitMix64(seed: 0xF011_0BED)
        for options in [GestureOptions.all, GestureOptions.oneFingerOnly(keeping: .all)] {
            for _ in 0..<300 {
                let s = TouchScript(options: options)
                playRandomSession(into: s, using: &generator)
                XCTAssertFalse(s.actions.contains(where: isTracking))
            }
        }
    }

    /// The gate into followed swipes leaves everything else alone: over the same random sessions,
    /// an engine following nothing and one following one axis say exactly the same in every
    /// session where the second never follows a swipe, one-shot swipes along the other axis included.
    func testFollowingOneAxisChangesNothingWhereNoSwipeIsFollowed() {
        for axis in [SwipeAxis.vertical, .horizontal] {
            var generator = SplitMix64(seed: 0x7_1215)
            var compared = 0, followed = 0, oneShots = 0
            for session in 0..<1500 {
                let intent: OneFingerIntent = Bool.random(using: &generator) ? .drag : .scroll
                let plain = TouchScript(intent: intent)
                let following = TouchScript(intent: intent)
                following.engine.followedSwipeAxes = [axis]
                var same = generator
                playRandomSession(into: plain, using: &generator)
                playRandomSession(into: following, using: &same)
                guard !following.actions.contains(where: isTracking) else {
                    followed += 1
                    continue
                }
                XCTAssertEqual(plain.actions, following.actions, "\(axis), session \(session)")
                compared += 1
                oneShots += plain.swipes.count
            }
            // Both kinds of session, and one-shot swipes through the gate, often.
            XCTAssertGreaterThan(compared, 1000, "\(axis)")
            XCTAssertGreaterThan(followed, 50, "\(axis)")
            XCTAssertGreaterThan(oneShots, 30, "\(axis)")
        }
    }

    // MARK: - Following the fingers

    private let three: [(Int, Double, Double)] = [(0, 200, 150), (1, 230, 150), (2, 260, 150)]
    private let four: [(Int, Double, Double)] = [(0, 200, 150), (1, 230, 150), (2, 260, 150), (3, 290, 150)]

    /// A script whose engine follows `axes`.
    private func following(_ axes: Set<SwipeAxis>, options: GestureOptions = .all) -> TouchScript {
        let s = TouchScript(options: options)
        s.engine.followedSwipeAxes = axes
        return s
    }

    /// Moves `fingers` from where they are by (dx, dy) millimetres over `steps` frames.
    private func shift(_ s: TouchScript, _ fingers: [(Int, Double, Double)], by dx: Double, _ dy: Double,
                       steps: Int, every dt: TimeInterval = 0.01) -> [(Int, Double, Double)] {
        s.move(fingers.map { ($0.0, ($0.1, $0.2), ($0.1 + dx, $0.2 + dy)) }, steps: steps, every: dt)
        return fingers.map { ($0.0, $0.1 + dx, $0.2 + dy) }
    }

    func testThreeFingersLeftBeginNear8mmFollowAndComplete() {
        let s = following([.horizontal])
        s.frame(three)
        _ = shift(s, three, by: -40, 0, steps: 20)   // 200 mm/s
        s.lift()

        let tracking = s.tracking
        XCTAssertEqual(tracking.map(\.phase.name).collapsed, ["began", "changed", "completed"])
        XCTAssertTrue(tracking.allSatisfy { $0.axis == .horizontal })
        guard let began = tracking.first, let end = tracking.last else { return }
        XCTAssertLessThanOrEqual(began.offset, -8 / 500 + 1e-9, "not before 8 mm")
        XCTAssertGreaterThanOrEqual(began.offset, -10 / 500 - 1e-9, "by the frame after 8 mm")
        let offsets = tracking.dropLast().map(\.offset)
        XCTAssertTrue(zip(offsets, offsets.dropFirst()).allSatisfy { $1 < $0 }, "each changed further left")
        XCTAssertEqual(end.offset, -40 / 500, accuracy: 1e-9)
        guard case .completed(let velocity) = end.phase else { return XCTFail("\(end.phase)") }
        XCTAssertEqual(velocity, -200 / 500, accuracy: 0.01, "fractions of the width per second, leftwards")
        XCTAssertEqual(s.swipes, [], "no one-shot swipe as well")
    }

    func testAFollowedSwipeEndsTheSessionNormally() {
        let s = following([.horizontal])
        s.frame(three)
        _ = shift(s, three, by: -40, 0, steps: 20)
        s.lift()
        s.wait(1)
        XCTAssertEqual(s.names, ["session began", "move", "tracking began", "tracking changed", "tracking completed",
                                 "session ended"])
        XCTAssertFalse(s.engine.needsTicks)
    }

    func testFingersComingBackAndLiftingWhileMovingBackCancel() {
        let s = following([.horizontal])
        s.frame(three)
        let out = shift(s, three, by: -40, 0, steps: 20)
        _ = shift(s, out, by: 20, 0, steps: 10)
        s.lift()
        XCTAssertEqual(s.tracking.last?.phase, .cancelled)
        XCTAssertEqual(s.tracking.last?.offset ?? 0, -20 / 500, accuracy: 1e-9)
    }

    func testLiftingWhileMovingBackCancelsEvenPastTheSwipeDistance() {
        let s = following([.horizontal])
        s.frame(three)
        let out = shift(s, three, by: -45, 0, steps: 20)
        // Back at 100 mm/s for the whole 0.1 s the speed is measured over; still 35 mm out.
        _ = shift(s, out, by: 10, 0, steps: 10)
        s.lift()
        XCTAssertEqual(s.tracking.last?.phase, .cancelled)
    }

    func testFarEnoughAndStillCompletes() {
        let s = following([.horizontal])
        s.frame(three)
        let out = shift(s, three, by: -40, 0, steps: 20)
        for _ in 0..<30 { s.frame(out) }   // resting 0.3 s
        s.lift()
        guard case .completed(let velocity) = s.tracking.last?.phase else {
            return XCTFail("\(String(describing: s.tracking.last))")
        }
        XCTAssertEqual(velocity, 0, accuracy: 1e-9)
        XCTAssertEqual(s.tracking.map(\.phase.name).collapsed, ["began", "changed", "completed"],
                       "resting frames say nothing")
    }

    func testAQuickShortFlickCompletesAndASlowShortDragCancels() {
        let flick = following([.horizontal])
        flick.frame(three)
        _ = shift(flick, three, by: -15, 0, steps: 5)   // 300 mm/s
        flick.lift()
        guard case .completed(let velocity) = flick.tracking.last?.phase else {
            return XCTFail("\(String(describing: flick.tracking.last))")
        }
        XCTAssertLessThan(velocity, 0)

        let slow = following([.horizontal])
        slow.frame(three)
        _ = shift(slow, three, by: -15, 0, steps: 30, every: 0.02)   // 25 mm/s
        slow.lift()
        XCTAssertEqual(slow.tracking.first?.phase, .began)
        XCTAssertEqual(slow.tracking.last?.phase, .cancelled)
    }

    func testACancelMidSwipeSaysCancelledThenSessionCancelledAndNothingMore() {
        let s = following([.horizontal])
        s.frame(three)
        let out = shift(s, three, by: -20, 0, steps: 10)
        let before = s.tracking.last?.offset
        s.cancel()
        XCTAssertEqual(s.names.suffix(2), ["tracking cancelled", "session cancelled"])
        XCTAssertEqual(s.tracking.last?.offset, before, "it closes where it was")

        let count = s.actions.count
        _ = shift(s, out, by: -30, 0, steps: 10)
        s.lift()
        s.wait(1)
        XCTAssertEqual(s.actions.count, count)
    }

    func testOneFingerLiftingEndsItAtThatFrameAndLaterMovementSaysNothing() {
        let s = following([.horizontal])
        s.frame(three)
        let out = shift(s, three, by: -40, 0, steps: 20)
        let count = s.actions.count
        let two = Array(out.prefix(2)).map { ($0.0, $0.1 - 2, $0.2) }
        s.frame(two)   // finger 2 lifts; the others moved on 2 mm
        let atLift = s.actions[count...].map(TouchScript.name(of:))
        XCTAssertEqual(atLift, ["tracking completed"])

        let after = s.actions.count
        _ = shift(s, two, by: -40, 0, steps: 20)
        s.lift()
        XCTAssertEqual(s.actions.count, after, "the swipe is over: no more tracking, and no one-shot swipe")
        s.wait(1)
        XCTAssertEqual(s.names.last, "session ended")
    }

    func testFollowingHorizontalOnlyAVerticalSwipeIsStillOneSwipeUpAt30mm() {
        let s = following([.horizontal])
        s.frame(three)
        let nearly = shift(s, three, by: 0, -29, steps: 29)
        XCTAssertEqual(s.swipes, [], "not at 29 mm")
        _ = shift(s, nearly, by: 0, -2, steps: 2)
        XCTAssertEqual(s.swipes, [.up], "by 31 mm")
        s.lift()
        XCTAssertTrue(s.tracking.isEmpty)
    }

    func testFollowingVerticalUpIsNegative() {
        let s = following([.vertical])
        s.frame(three)
        _ = shift(s, three, by: 0, -40, steps: 20)
        s.lift()
        XCTAssertTrue(s.tracking.allSatisfy { $0.axis == .vertical })
        XCTAssertEqual(s.tracking.last?.offset ?? 0, -40 / 300, accuracy: 1e-9, "a fraction of the height")
        XCTAssertEqual(s.swipes, [])
    }

    func testMovementAcrossTheAxisIsIgnored() {
        let s = following([.horizontal])
        s.frame(three)
        let out = shift(s, three, by: -40, 12, steps: 20)   // 17° below horizontal
        let count = s.actions.count
        _ = shift(s, out, by: 0, 15, steps: 10)            // straight down: the offset doesn't change
        XCTAssertEqual(s.actions.count, count)
        s.lift()
        XCTAssertEqual(s.tracking.last?.offset ?? 0, -40 / 500, accuracy: 1e-9)
    }

    func testADiagonalMovementIsNotFollowed() {
        let s = following([.horizontal, .vertical])
        s.frame(three)
        _ = shift(s, three, by: 30, 30, steps: 20)
        s.lift()
        XCTAssertTrue(s.tracking.isEmpty)
        XCTAssertEqual(s.swipes, [])
    }

    func testOffsetsAreFractionsOfTheRightDimensionOnAWideSurface() {
        let surface = CGSize(width: 1600, height: 600)
        for (axis, dx, dy, expected) in [(SwipeAxis.horizontal, -40.0, 0.0, -40.0 / 1600), (.vertical, 0, -40, -40.0 / 600)] {
            let s = following([axis])
            var time: TimeInterval = 100
            func send(_ x: Double, _ y: Double) {
                time += 0.01
                let fingers = (0..<3).map { Finger(id: $0, location: CGPoint(x: (x + Double($0) * 30) / 1600, y: y / 600)) }
                s.send(TouchFrame(time: time, fingers: fingers, surfaceSize: surface))
            }
            send(800, 300)
            for step in 1...20 { send(800 + dx * Double(step) / 20, 300 + dy * Double(step) / 20) }
            s.send(TouchFrame(time: time + 0.01, fingers: [], surfaceSize: surface))

            let tracking = s.tracking
            XCTAssertEqual(tracking.map(\.phase.name).collapsed, ["began", "changed", "completed"], "\(axis)")
            XCTAssertEqual(tracking.last?.offset ?? 0, expected, accuracy: 1e-9, "\(axis)")
            // Begun once the fingers had moved 8 mm, in millimetres of this surface.
            let beganAt = abs(tracking.first?.offset ?? 0) * (axis == .horizontal ? 1600 : 600)
            XCTAssertTrue((8 - 1e-6...10 + 1e-6).contains(beganAt), "\(axis): began at \(beganAt) mm")
        }
    }

    func testFourFingersBehaveAsThree() {
        func run(_ fingers: [(Int, Double, Double)]) -> [(phase: String, offset: Double)] {
            let s = following([.horizontal])
            s.frame(fingers)
            let out = shift(s, fingers, by: -41, 0, steps: 20)   // 2.05 mm a frame: clear of 8 mm
            _ = shift(s, out, by: 10, 0, steps: 5)
            s.lift()
            return s.tracking.map { ($0.phase.name, $0.offset) }
        }
        let byThree = run(three)
        let byFour = run(four)
        XCTAssertEqual(byThree.map(\.phase), byFour.map(\.phase))
        XCTAssertEqual(byThree.count, byFour.count)
        for (a, b) in zip(byThree, byFour) { XCTAssertEqual(a.offset, b.offset, accuracy: 1e-9) }
        XCTAssertEqual(byFour.last?.phase, "cancelled")
    }

    func testWithSwipesOffNothingIsFollowed() {
        var options = GestureOptions.all
        options.swipes = false
        let s = following([.horizontal, .vertical], options: options)
        s.frame(three)
        _ = shift(s, three, by: -40, 0, steps: 20)
        s.lift()
        XCTAssertTrue(s.tracking.isEmpty)
        XCTAssertEqual(s.swipes, [])
    }

    func testFollowedAxesChangedMidSwipeDoNotCutItShort() {
        let s = following([.horizontal])
        s.frame(three)
        let out = shift(s, three, by: -20, 0, steps: 10)
        s.engine.followedSwipeAxes = []
        _ = shift(s, out, by: -20, 0, steps: 10)
        s.lift()
        XCTAssertEqual(s.tracking.map(\.phase.name).collapsed, ["began", "changed", "completed"])
    }

    /// The promise the Dock depends on: over many random sessions, whatever is followed, every
    /// `began` is followed by exactly one end before the session ends (normally or cancelled),
    /// there is never a `changed` or an end without a `began`, while a swipe is open nothing else is
    /// said, and at the end the engine needs no more ticks. The sessions include time going
    /// backwards, options and the surface changing mid-session, and fingers moving separately.
    func testEveryBeganHasExactlyOneEndBeforeTheSessionEnds() {
        var generator = SplitMix64(seed: 0xD0C5_11DE)
        var began = 0, completed = 0, cancelled = 0, cutShort = 0
        let choices: [Set<SwipeAxis>] = [[.horizontal], [.vertical], [.horizontal, .vertical]]
        for session in 0..<3000 {
            let s = following(choices[session % choices.count])
            playRandomSession(into: s, using: &generator) { s, g in
                // Now and then the followed axes change mid-session, as a setting would.
                if Int.random(in: 0..<8, using: &g) == 0 { s.engine.followedSwipeAxes = choices.randomElement(using: &g)! }
            }
            var open: SwipeAxis?
            for (index, action) in s.actions.enumerated() {
                let label = "session \(session), action \(index): \(TouchScript.name(of: action))"
                switch action {
                case .swipeTracking(let axis, let offset, .began):
                    XCTAssertNil(open, label)
                    XCTAssertFalse(offset.isNaN, label)
                    // 8 mm moved, within 30° of the axis: at least 8 × cos 30° along it, in
                    // millimetres of the surface of the frame that began it.
                    if let surface = s.surface(atAction: index) {
                        let along = abs(offset) * Double(axis == .horizontal ? surface.width : surface.height)
                        XCTAssertGreaterThanOrEqual(along, 8 * cos(.pi / 6) - 1e-6, label)
                    } else {
                        XCTFail("\(label): no frame before it")
                    }
                    open = axis
                    began += 1
                case .swipeTracking(let axis, _, .changed):
                    XCTAssertEqual(open, axis, label)
                case .swipeTracking(let axis, let offset, .completed(let velocity)):
                    XCTAssertEqual(open, axis, label)
                    XCTAssertNotEqual(offset, 0, label)
                    XCTAssertFalse(velocity.isNaN, label)
                    open = nil
                    completed += 1
                case .swipeTracking(let axis, _, .cancelled):
                    XCTAssertEqual(open, axis, label)
                    open = nil
                    cancelled += 1
                    if index + 1 < s.actions.count, s.actions[index + 1] == .sessionCancelled { cutShort += 1 }
                default:
                    XCTAssertNil(open, label)
                }
            }
            XCTAssertNil(open, "session \(session) ended with a swipe open")
            XCTAssertFalse(s.engine.needsTicks, "session \(session) still needs ticks")
        }
        XCTAssertEqual(began, completed + cancelled)
        // The scripts reach every path, often.
        XCTAssertGreaterThan(completed, 100)
        XCTAssertGreaterThan(cancelled, 100)
        XCTAssertGreaterThan(cutShort, 20)
    }
}

private extension TouchScript {
    /// Every `swipeTracking` action, in order.
    var tracking: [(axis: SwipeAxis, offset: Double, phase: SwipeTrackingPhase)] {
        actions.compactMap {
            if case .swipeTracking(let axis, let offset, let phase) = $0 { return (axis, offset, phase) }
            return nil
        }
    }
}

private extension SwipeTrackingPhase {
    var name: String {
        switch self {
        case .began: return "began"
        case .changed: return "changed"
        case .completed: return "completed"
        case .cancelled: return "cancelled"
        }
    }
}

private func isTracking(_ action: GestureAction) -> Bool {
    if case .swipeTracking = action { return true }
    return false
}

private extension Array where Element == String {
    /// Consecutive repeats collapsed.
    var collapsed: [String] {
        reduce(into: []) { result, name in if result.last != name { result.append(name) } }
    }
}

// MARK: - Random sessions

/// A seeded generator, so a random script fails the same way every time.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Plays one random touch session into `s`, the same every time for the generator's state:
/// fingers landing together or one after another; moving together, mostly along an axis but also
/// across or anywhere, there and back, at different speeds, or each its own way, some not at all;
/// some lifting early; pauses with ticks; a cancel, with fingers left down; time going backwards,
/// in a frame or a tick; swipes switched off or on mid-session; and the surface changing size. It
/// always ends with every finger lifted and four seconds of ticks, so whatever the session started
/// has ended. `eachStep`, if given, runs before each step and may draw from the generator.
func playRandomSession(into s: TouchScript, using g: inout SplitMix64,
                       eachStep: ((TouchScript, inout SplitMix64) -> Void)? = nil) {
    var down: [(id: Int, x: Double, y: Double)] = []
    var nextID = 0
    var surface = TouchScript.surface
    func send(after dt: TimeInterval) {
        let fingers = down.map { Finger(id: $0.id, location: CGPoint(x: $0.x / surface.width, y: $0.y / surface.height)) }
        s.send(TouchFrame(time: s.time + dt, fingers: fingers, surfaceSize: surface))
    }
    func kept(_ x: Double, _ y: Double) -> (Double, Double) {
        (min(Double(surface.width), max(0, x)), min(Double(surface.height), max(0, y)))
    }
    for _ in 0..<Int.random(in: 1...12, using: &g) {
        eachStep?(s, &g)
        switch Int.random(in: 0..<16, using: &g) {
        case 0..<3:
            // Fingers land side by side, together or one after another.
            let count = [1, 2, 3, 3, 3, 4, 4].randomElement(using: &g)!
            let x = Double.random(in: 60...380, using: &g)
            let y = Double.random(in: 40...260, using: &g)
            let together = Bool.random(using: &g)
            for i in 0..<count where down.count < 5 {
                down.append((nextID, x + Double(i) * Double.random(in: 18...35, using: &g),
                             y + Double.random(in: -6...6, using: &g)))
                nextID += 1
                if !together { send(after: Double.random(in: 0.005...0.12, using: &g)) }
            }
            if together { send(after: 0.01) }
        case 3..<8:
            // The fingers move in a straight line: all the same way, or each its own way, at its
            // own speed, some not at all.
            guard !down.isEmpty else { continue }
            let kind = Int.random(in: 0..<20, using: &g)
            let base: Double = kind < 12 ? [0, 180].randomElement(using: &g)!
                : kind < 17 ? [90, 270].randomElement(using: &g)! : Double.random(in: 0..<360, using: &g)
            let angle = base + (kind < 17 ? Double.random(in: -25...25, using: &g) : 0)
            let distance = Double.random(in: 0...65, using: &g)
            let steps = Int.random(in: 1...25, using: &g)
            let dt = [0.004, 0.008, 0.01, 0.01, 0.02].randomElement(using: &g)!
            let separately = Int.random(in: 0..<3, using: &g) == 0
            let ways: [Int: (dx: Double, dy: Double)] = Dictionary(uniqueKeysWithValues: down.map { finger in
                let own = separately ? angle + Double.random(in: -30...30, using: &g) : angle
                let speed = separately ? [0, 0.5, 1, 1, 1.5].randomElement(using: &g)! : 1
                let length = distance * speed / Double(steps)
                return (finger.id, (cos(own * .pi / 180) * length, sin(own * .pi / 180) * length))
            })
            for _ in 0..<steps {
                down = down.map { finger in
                    let way = ways[finger.id] ?? (0, 0)
                    let (x, y) = kept(finger.x + way.dx, finger.y + way.dy)
                    return (finger.id, x, y)
                }
                send(after: dt)
            }
        case 8:
            // Some fingers lift, the others stay.
            guard !down.isEmpty else { continue }
            down.shuffle(using: &g)
            down.removeFirst(Int.random(in: 1...down.count, using: &g))
            down.sort { $0.id < $1.id }
            send(after: 0.01)
        case 9:
            // A pause: ticks only, or one frame of resting fingers.
            if Bool.random(using: &g) {
                s.wait(Double.random(in: 0...0.6, using: &g))
            } else {
                send(after: Double.random(in: 0.01...0.3, using: &g))
            }
        case 10:
            s.cancel()
        case 11:
            // Time goes backwards: in a frame, or in a tick.
            if Bool.random(using: &g) {
                send(after: -Double.random(in: 0.001...0.5, using: &g))
            } else {
                s.tick(at: s.time - Double.random(in: 0.001...0.3, using: &g))
            }
        case 12:
            // Swipes are switched off, or back on, mid-session.
            s.engine.options.swipes.toggle()
        case 13:
            // The surface changes size, the fingers where they were in millimetres.
            surface = [CGSize(width: 500, height: 300), CGSize(width: 1600, height: 600), CGSize(width: 300, height: 500)]
                .randomElement(using: &g)!
            down = down.map { finger in
                let (x, y) = kept(finger.x, finger.y)
                return (finger.id, x, y)
            }
            send(after: 0.01)
        default:
            down = []
            send(after: 0.01)
        }
    }
    down = []
    send(after: 0.01)
    s.wait(4)
}
