import CoreGraphics
import Foundation
@testable import TactileGestures

/// Drives a `GestureEngine` through a touch session on a 500 × 300 mm surface.
///
/// Positions are given in millimetres. Frames come 10 ms apart unless a test says otherwise.
/// Every frame passes through a `ContactFilter` before the engine sees it, as in the app, and when
/// the filter says a contact it had let through is now refused, the engine is cancelled first.
final class TouchScript {
    static let surface = CGSize(width: 500, height: 300)

    var intent: OneFingerIntent
    private(set) var time: TimeInterval = 100
    private(set) var actions: [GestureAction] = []
    private(set) var intentRequests: [CGPoint] = []
    /// The surface of every frame sent, with the index in `actions` of the first action it could give.
    private(set) var frameSurfaces: [(firstAction: Int, size: CGSize)] = []

    private let options: GestureOptions
    private var filter: ContactFilter

    private(set) lazy var engine = GestureEngine(options: options) { [unowned self] location in
        intentRequests.append(location)
        return intent
    }

    /// `rules`: the filter's rejection rules; none by default, as the filter's own default.
    init(intent: OneFingerIntent = .drag, options: GestureOptions = .all, rules: RejectionRules = .none) {
        self.intent = intent
        self.options = options
        self.filter = ContactFilter(fingerLimit: options.fingerLimit, rules: rules)
    }

    /// The relative location of a point given in millimetres.
    static func at(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: x / surface.width, y: y / surface.height)
    }

    /// Sends one frame `dt` seconds after the previous one. Fingers are (id, x mm, y mm), in the
    /// order the panel lists them.
    func frame(after dt: TimeInterval = 0.01, _ fingers: [(Int, Double, Double)]) {
        time += dt
        let list = fingers.map { Finger(id: $0.0, location: Self.at($0.1, $0.2)) }
        process(TouchFrame(time: time, fingers: list, surfaceSize: Self.surface))
    }

    /// Sends a ready-made frame at its own time.
    func send(_ frame: TouchFrame) {
        time = frame.time
        process(frame)
    }

    /// Cancels the session at the current time, as the app does when a touch is interrupted.
    func cancel() {
        actions += engine.cancel(at: time)
    }

    /// Ticks the engine at `time`, which may be earlier than the script's own time: time going
    /// backwards. The script's time doesn't change.
    func tick(at time: TimeInterval) {
        actions += engine.tick(at: time)
    }

    /// Sends a frame with no fingers: everything lifts.
    func lift(after dt: TimeInterval = 0.01) {
        frame(after: dt, [])
    }

    /// Moves fingers in a straight line from `from` to `to` over `steps` frames.
    func move(_ fingers: [(id: Int, from: (Double, Double), to: (Double, Double))],
              steps: Int, every dt: TimeInterval = 0.01) {
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            frame(after: dt, fingers.map {
                ($0.id, $0.from.0 + ($0.to.0 - $0.from.0) * t, $0.from.1 + ($0.to.1 - $0.from.1) * t)
            })
        }
    }

    /// Feeds recorded frames at their own times, ticking 60 times a second in between as the app
    /// does, then lets two seconds pass so momentum and the session can finish.
    func replay(_ frames: [TouchFrame]) {
        guard let first = frames.first else { return }
        time = first.time
        for frame in frames {
            while time + 1.0 / 60 < frame.time {
                time += 1.0 / 60
                actions += engine.tick(at: time)
            }
            time = frame.time
            process(frame)
        }
        wait(2)
    }

    /// Passes the frame's fingers through the contact filter, then the frame to the engine. If the
    /// filter refused a contact it had let through, the engine is cancelled first, as the app does,
    /// so the vanished contact isn't read as a lift.
    private func process(_ frame: TouchFrame) {
        frameSurfaces.append((actions.count, frame.surfaceSize))
        var live = frame
        live.fingers = filter.live(frame.fingers, at: frame.time, surfaceSize: frame.surfaceSize)
        if filter.mustCancel { actions += engine.cancel(at: frame.time) }
        actions += engine.process(live)
    }

    /// Lets time pass with no frames, ticking 60 times a second.
    func wait(_ seconds: TimeInterval) {
        let end = time + seconds
        while time < end {
            time = min(end, time + 1.0 / 60)
            actions += engine.tick(at: time)
        }
    }

    /// The size of the surface when `actions[index]` was said: that of the last frame sent before it.
    func surface(atAction index: Int) -> CGSize? {
        frameSurfaces.last { $0.firstAction <= index }?.size
    }

    /// The actions as short names, with consecutive repeats collapsed.
    var names: [String] {
        var result: [String] = []
        for action in actions {
            let name = Self.name(of: action)
            if result.last != name { result.append(name) }
        }
        return result
    }

    var clickCounts: [Int] {
        actions.compactMap { if case .click(_, let count) = $0 { return count } else { return nil } }
    }

    var pointerMoves: [CGPoint] {
        actions.compactMap { if case .movePointer(let point) = $0 { return point } else { return nil } }
    }

    var rightClicks: [CGPoint] {
        actions.compactMap { if case .rightClick(let point) = $0 { return point } else { return nil } }
    }

    var longPressReadies: [CGPoint] {
        actions.compactMap { if case .longPressReady(let point) = $0 { return point } else { return nil } }
    }

    var swipes: [SwipeDirection] {
        actions.compactMap { if case .swipe(let direction) = $0 { return direction } else { return nil } }
    }

    /// The sum of every scroll movement, relative to the screen.
    var totalScroll: CGVector {
        actions.reduce(CGVector.zero) { total, action in
            guard case .scroll(let delta, _) = action else { return total }
            return CGVector(dx: total.dx + delta.dx, dy: total.dy + delta.dy)
        }
    }

    var momentumSteps: [CGVector] {
        actions.compactMap { if case .momentum(let delta, .changed) = $0 { return delta } else { return nil } }
    }

    /// The overall zoom factor: every pinch change multiplied together.
    var totalZoom: Double {
        actions.reduce(1.0) { total, action in
            guard case .pinch(let change, _) = action else { return total }
            return total * (1 + change)
        }
    }

    /// Every rotate event's degrees, in order.
    var rotations: [Double] {
        actions.compactMap { if case .rotate(let degrees, _) = $0 { return degrees } else { return nil } }
    }

    /// The overall turn: every rotate event's degrees added up. Positive is anticlockwise.
    var totalRotation: Double {
        rotations.reduce(0, +)
    }

    static func name(of action: GestureAction) -> String {
        switch action {
        case .sessionBegan: return "session began"
        case .movePointer: return "move"
        case .click(_, let count): return "click \(count)"
        case .press(_, let count): return "press \(count)"
        case .drag: return "drag"
        case .release: return "release"
        case .rightClick: return "right-click"
        case .longPressReady: return "long-press ready"
        case .longPressWithdrawn: return "long-press withdrawn"
        case .scroll(_, let phase): return "scroll \(phase)"
        case .momentum(_, let phase): return "momentum \(phase)"
        case .pinch(_, let phase): return "pinch \(phase)"
        case .rotate(_, let phase): return "rotate \(phase)"
        case .swipe(let direction): return "swipe \(direction)"
        case .swipeTracking(_, _, .began): return "tracking began"
        case .swipeTracking(_, _, .changed): return "tracking changed"
        case .swipeTracking(_, _, .completed): return "tracking completed"
        case .swipeTracking(_, _, .cancelled): return "tracking cancelled"
        case .sessionEnded: return "session ended"
        case .sessionCancelled: return "session cancelled"
        }
    }
}

/// Points from millimetre arithmetic differ in the last bits; compare them with a tolerance.
func isClose(_ a: CGPoint, _ b: CGPoint) -> Bool {
    abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9
}
