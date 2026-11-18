import CoreGraphics
import Foundation

/// Turns touch frames into gesture actions.
///
/// Pure logic, so recorded sessions replay exactly: time comes only from frames and from
/// `tick(at:)`, and the one outside question (should this finger drag or scroll?) is answered by
/// the `intentForTouch` closure.
///
/// Every frame must already have been through a `ContactFilter(fingerLimit: options.fingerLimit)`:
/// on a one-finger-only touchscreen the engine relies on the filter to keep a second contact out.
/// Change `options` and the filter's `fingerLimit` together. When the filter's `mustCancel` is true
/// after a frame, call `cancel(at:)` before giving the engine that frame.
///
/// Not thread-safe: call every method on the main thread.
public final class GestureEngine {

    /// Answers drag or scroll for a finger that starts moving from `location` (relative to the
    /// display, 0…1).
    public typealias IntentProvider = (_ location: CGPoint) -> OneFingerIntent

    public let constants: GestureConstants
    /// Which gestures beyond one finger are on. Read when a gesture is decided, so a change
    /// applies from the next decision. Change the contact filter's `fingerLimit` to
    /// `options.fingerLimit` at the same time.
    public var options: GestureOptions
    /// The axes whose three- and four-finger swipes follow the fingers, with `swipeTracking`
    /// actions, instead of the one-shot `swipe`. Empty by default: every swipe is the one-shot kind,
    /// exactly as before followed swipes existed. Read when a swipe is decided, like `options`, so a
    /// change applies from the next one; a followed swipe already begun runs to its end. Not part of
    /// `options`, which are saved: followed swipes are an experiment.
    public var followedSwipeAxes: Set<SwipeAxis> = []
    private let intentForTouch: IntentProvider

    public init(constants: GestureConstants = .standard, options: GestureOptions = .all,
                intentForTouch: @escaping IntentProvider) {
        self.constants = constants
        self.options = options
        self.intentForTouch = intentForTouch
    }

    /// True while the engine is waiting on time: fingers are down in a session, momentum is running,
    /// or the session hasn't settled. Call `tick(at:)` about 60 times a second while this is true.
    public var needsTicks: Bool {
        switch phase {
        case .idle, .ignoringUntilClear: return false
        case .touching, .coasting, .settling: return true
        }
    }

    /// Cuts the session short at once: closes whatever is in flight so no button stays held and no
    /// scroll, pinch or momentum stays open, then ends with `sessionCancelled`, never
    /// `sessionEnded`. Fingers still on the glass are then ignored until a frame arrives with none.
    /// Returns nothing when there is no session.
    public func cancel(at time: TimeInterval) -> [GestureAction] {
        var actions: [GestureAction] = []
        switch phase {
        case .idle, .ignoringUntilClear:
            return []
        case .touching(.dragging):
            if let contact = participants.first.flatMap({ contacts[$0] }) {
                actions.append(.release(at: contact.current))
            }
        case .touching(.scrollingOne), .touching(.scrollingTwo):
            actions.append(.scroll(by: .zero, phase: .ended))
        case .touching(.pinching):
            actions.append(.pinch(by: 0, phase: .ended))
        case .touching(.rotating):
            actions.append(.rotate(by: 0, phase: .ended))
        case .coasting:
            actions.append(.momentum(by: .zero, phase: .ended))
        case .touching(.swipeTracking(let axis, let lastOffset)):
            actions.append(.swipeTracking(axis: axis, offset: lastOffset, phase: .cancelled))
        case .touching, .settling:
            break
        }
        phase = contacts.isEmpty ? .idle : .ignoringUntilClear
        contacts = [:]
        participants = []
        scrollSamples = []
        lastTap = nil
        return actions + [.sessionCancelled]
    }

    // MARK: - State

    private struct Contact {
        let landedAt: TimeInterval
        let start: CGPoint
        var previous: CGPoint
        var current: CGPoint
    }

    /// A scroll's speed when its fingers lifted, and when it last moved.
    private struct Flick {
        /// In mm/s.
        let velocity: CGVector
        /// The time of the scroll's last movement sample.
        let lastSampleTime: TimeInterval
    }

    private enum Gesture {
        /// One finger, still within the slop. `stoppedMomentum`: it landed on a coasting scroll, so
        /// lifting it without moving only stops the scroll; it doesn't click, and never long-presses.
        case pending(stoppedMomentum: Bool)
        /// One finger that has rested `longPressDuration` within the slop, and been told it is
        /// ready: lifting it right-clicks, moving it drags, and a second finger withdraws it.
        case longPressReady
        case dragging
        case scrollingOne
        /// Two fingers, not yet a tap, scroll, pinch or rotate. `startAngle`: the direction of the
        /// line from the first to the second when the second landed, which a rotate turns from.
        case twoPending(secondLandedAt: TimeInterval, startAngle: Double?)
        /// One finger of a two-finger tap lifted; waiting for the other before the deadline.
        case twoTapLifting(deadline: TimeInterval, at: CGPoint)
        case scrollingTwo
        case pinching(lastDistance: Double)
        /// `lastAngle`: the line's direction at the previous rotate event.
        case rotating(lastAngle: Double)
        /// Three or four fingers, not yet far enough for a swipe.
        case swipePending
        /// Three or four fingers moving along a followed axis; `lastOffset`: the offset last said.
        case swipeTracking(axis: SwipeAxis, lastOffset: Double)
        /// The gesture is over. Fingers still down are ignored until they lift; `momentum` is the
        /// flick to coast with once they have, if they lift soon enough after it.
        case finished(momentum: Flick?)
    }

    private enum Phase {
        case idle
        case touching(Gesture)
        /// Fingers up and coasting; `velocity` is in mm/s.
        case coasting(velocity: CGVector, lastTime: TimeInterval)
        /// Fingers up, waiting out the double-tap window before ending the session.
        case settling(since: TimeInterval)
        /// Cancelled with fingers still down. There is no session; every frame is ignored until
        /// one arrives with no fingers.
        case ignoringUntilClear
    }

    private var phase: Phase = .idle
    private var contacts: [Int: Contact] = [:]
    /// Fingers taking part in the current gesture, in landing order. Other fingers are ignored.
    private var participants: [Int] = []
    private var surface = CGSize(width: 1, height: 1)
    private var lastTap: (liftedAt: TimeInterval, location: CGPoint, count: Int)?
    /// Recent scroll positions in millimetres, for the flick speed at lift.
    private var scrollSamples: [(time: TimeInterval, point: CGPoint)] = []

    // MARK: - Input

    /// Feeds one frame and returns the actions to perform, in order. Call on the main thread, with a
    /// frame that has already been through `ContactFilter(fingerLimit: options.fingerLimit)`.
    public func process(_ frame: TouchFrame) -> [GestureAction] {
        if frame.surfaceSize.width > 0, frame.surfaceSize.height > 0 { surface = frame.surfaceSize }
        // A panel can list one contact twice in a report. It is still one finger; its first entry counts.
        var present = Set<Int>()
        let fingers = frame.fingers.filter { present.insert($0.id).inserted }
        if case .ignoringUntilClear = phase {
            if fingers.isEmpty { phase = .idle }
            return []
        }
        // Time passes before this frame's news is read, as a tick would have passed it: a finger
        // last seen resting has rested until now. So a frame and a tick give the same result.
        var actions = longPressIfDue(at: frame.time)

        for finger in fingers {
            guard var contact = contacts[finger.id] else { continue }
            contact.previous = contact.current
            contact.current = finger.location
            contacts[finger.id] = contact
        }

        let lifted = contacts.keys.filter { !present.contains($0) }.sorted()
        if !lifted.isEmpty { actions += lift(lifted, at: frame.time) }

        // Fingers landing in this report join the gesture before its movement is judged, so a
        // finger landing as the first one crosses the slop still makes it a two-finger gesture.
        // Fingers landing together count lowest contact ID first, whatever order the panel lists them in.
        let landed = fingers.filter { contacts[$0.id] == nil }.sorted { $0.id < $1.id }
        if !landed.isEmpty { actions += land(landed, at: frame.time) }
        if !contacts.isEmpty { actions += move(at: frame.time) }
        return actions
    }

    /// Advances time without a new frame: for long-press, momentum, two-finger-tap deadlines and
    /// settling.
    public func tick(at time: TimeInterval) -> [GestureAction] {
        switch phase {
        case .touching(.twoTapLifting(let deadline, _)):
            if time > deadline { phase = .touching(.finished(momentum: nil)) }
            return []

        case .touching(.pending):
            return longPressIfDue(at: time)

        case .idle, .touching, .ignoringUntilClear:
            return []

        case .coasting(let velocity, let lastTime):
            let dt = time - lastTime
            guard dt > 0 else { return [] }
            let speed = velocity.scaled(by: exp(-dt / constants.momentumTimeConstant))
            if speed.length < constants.momentumStopSpeed {
                phase = .settling(since: time)
                return [.momentum(by: .zero, phase: .ended)]
            }
            phase = .coasting(velocity: speed, lastTime: time)
            return [.momentum(by: relative(speed.scaled(by: dt)), phase: .changed)]

        case .settling(let since):
            guard time - since >= constants.tapInterval else { return [] }
            phase = .idle
            lastTap = nil
            return [.sessionEnded]
        }
    }

    // MARK: - Landing

    private func land(_ fingers: [Finger], at time: TimeInterval) -> [GestureAction] {
        for finger in fingers {
            contacts[finger.id] = Contact(landedAt: time, start: finger.location,
                                          previous: finger.location, current: finger.location)
        }

        var actions: [GestureAction] = []
        var stoppedMomentum = false
        switch phase {
        case .touching(let gesture):
            return join(fingers.map(\.id), gesture: gesture, at: time)
        case .coasting:
            actions.append(.momentum(by: .zero, phase: .ended))
            stoppedMomentum = true
        // Never .ignoringUntilClear: process(_:) drops every frame in that phase; listed for exhaustiveness.
        case .idle, .ignoringUntilClear:
            actions.append(.sessionBegan)
        case .settling:
            break
        }

        // With swipes off, a third or fourth finger landing with the others doesn't take part, and
        // the first two keep their gesture.
        participants = fingers.prefix(options.swipes ? fingers.count : 2).map(\.id)
        actions.append(.movePointer(to: fingers[0].location))
        switch participants.count {
        case 1: phase = .touching(.pending(stoppedMomentum: stoppedMomentum))
        case 2: phase = .touching(.twoPending(secondLandedAt: time, startAngle: participantsLineAngle()))
        default: phase = .touching(.swipePending)
        }
        return actions
    }

    /// Decides whether fingers landing during a gesture take part in it. Only gestures that
    /// haven't committed yet take more fingers; a third or fourth finger counts only if swipes are
    /// on and it lands within `swipeLanding` of the first.
    private func join(_ ids: [Int], gesture: Gesture, at time: TimeInterval) -> [GestureAction] {
        guard let first = participants.first.flatMap({ contacts[$0] }) else { return [] }
        let inSwipeWindow = options.swipes && time - first.landedAt <= constants.swipeLanding
        switch gesture {
        case .pending, .longPressReady:
            participants += ids
            if participants.count >= 3, inSwipeWindow {
                phase = .touching(.swipePending)
            } else {
                participants = Array(participants.prefix(2))
                phase = .touching(.twoPending(secondLandedAt: time, startAngle: participantsLineAngle()))
            }
            // A finger resting long enough to long-press hasn't committed to anything: a second
            // finger still makes a two-finger gesture, so lifting no longer right-clicks.
            if case .longPressReady = gesture { return [.longPressWithdrawn] }
        case .twoPending:
            guard inSwipeWindow else { return [] }
            participants += ids
            phase = .touching(.swipePending)
        case .swipePending:
            if inSwipeWindow { participants += ids }
        default:
            break  // a committed gesture ignores extra fingers
        }
        return []
    }

    // MARK: - Movement

    private func move(at time: TimeInterval) -> [GestureAction] {
        guard case .touching(let gesture) = phase else { return [] }
        switch gesture {
        case .pending:
            guard let id = participants.first, let contact = contacts[id],
                  millimetres(contact.current - contact.start).length >= constants.slop else { return [] }
            let held = time - contact.landedAt >= constants.holdTime
            if held || intentForTouch(contact.start) == .drag {
                phase = .touching(.dragging)
                let count = clickCount(at: contact.start, landedAt: contact.landedAt)
                return [.press(at: contact.start, count: count), .drag(to: contact.current)]
            }
            phase = .touching(.scrollingOne)
            scrollSamples = [(time, millimetres(contact.current))]
            return [.scroll(by: contact.current - contact.start, phase: .began)]

        case .longPressReady:
            // It has rested longer than `holdTime`, so moving drags, whatever the intent.
            guard let id = participants.first, let contact = contacts[id],
                  millimetres(contact.current - contact.start).length >= constants.slop else { return [] }
            phase = .touching(.dragging)
            let count = clickCount(at: contact.start, landedAt: contact.landedAt)
            return [.press(at: contact.start, count: count), .drag(to: contact.current)]

        case .dragging:
            guard let id = participants.first, let contact = contacts[id],
                  contact.current != contact.previous else { return [] }
            return [.drag(to: contact.current)]

        case .scrollingOne:
            guard let id = participants.first, let contact = contacts[id] else { return [] }
            recordScrollSample(millimetres(contact.current), at: time)
            let delta = contact.current - contact.previous
            return delta == .zero ? [] : [.scroll(by: delta, phase: .changed)]

        case .twoPending(_, let startAngle):
            return classifyTwoFingers(at: time, startAngle: startAngle)

        case .twoTapLifting:
            // The finger still down moved too far for a tap.
            if let id = participants.first, let contact = contacts[id],
               millimetres(contact.current - contact.start).length >= constants.slop {
                phase = .touching(.finished(momentum: nil))
            }
            return []

        case .scrollingTwo:
            let pair = participants.compactMap { contacts[$0] }
            guard pair.count == 2 else { return [] }
            let now = midpoint(pair[0].current, pair[1].current)
            let before = midpoint(pair[0].previous, pair[1].previous)
            recordScrollSample(millimetres(now), at: time)
            let delta = now - before
            return delta == .zero ? [] : [.scroll(by: delta, phase: .changed)]

        case .pinching(let lastDistance):
            let pair = participants.compactMap { contacts[$0] }
            guard pair.count == 2, lastDistance > 0 else { return [] }
            let distance = millimetres(pair[0].current - pair[1].current).length
            phase = .touching(.pinching(lastDistance: distance))
            let change = distance / lastDistance - 1
            return change == 0 ? [] : [.pinch(by: change, phase: .changed)]

        case .rotating(let lastAngle):
            guard let angle = participantsLineAngle() else { return [] }
            phase = .touching(.rotating(lastAngle: angle))
            let change = turnDegrees(from: lastAngle, to: angle)
            return change == 0 ? [] : [.rotate(by: change, phase: .changed)]

        case .swipePending:
            if !followedSwipeAxes.isEmpty, let began = beginFollowedSwipe(at: time) { return began }
            return classifySwipe()

        case .swipeTracking(let axis, let lastOffset):
            return followSwipe(axis: axis, lastOffset: lastOffset, at: time)

        case .finished:
            return []
        }
    }

    /// Two fingers become a pinch once the distance between them changes enough, a scroll once
    /// both move the same way, or a rotate once the line between them has turned far enough from
    /// `startAngle` while their distance holds: 12° when both have moved and are going round each
    /// other, 25° when one still rests where it landed and they landed 30 mm apart or more. They
    /// are judged in that order, so a pinch
    /// wins a frame in which both the distance and the line cross, and fingers moving together
    /// scroll even if their line turns. Any other turn decides nothing: a two-finger scroll that
    /// one finger starts alone turns the line as a twist does, at first. Until then they could
    /// still be a tap. A gesture that is switched off is never chosen.
    private func classifyTwoFingers(at time: TimeInterval, startAngle: Double?) -> [GestureAction] {
        let pair = participants.compactMap { contacts[$0] }
        guard pair.count == 2 else { return [] }
        let (a, b) = (pair[0], pair[1])
        let moveA = millimetres(a.current - a.start)
        let moveB = millimetres(b.current - b.start)
        guard max(moveA.length, moveB.length) >= constants.slop else { return [] }

        let startDistance = millimetres(a.start - b.start).length
        let distance = millimetres(a.current - b.current).length
        if options.pinch, startDistance > 0, abs(distance / startDistance - 1) > constants.pinchRatio {
            phase = .touching(.pinching(lastDistance: distance))
            return [.movePointer(to: midpoint(a.current, b.current)),
                    .pinch(by: distance / startDistance - 1, phase: .began)]
        }
        if options.twoFingerScroll, moveA.length >= constants.slop, moveB.length >= constants.slop,
           angleDegrees(moveA, moveB) <= constants.scrollAngle {
            phase = .touching(.scrollingTwo)
            let start = midpoint(a.start, b.start)
            let now = midpoint(a.current, b.current)
            scrollSamples = [(time, millimetres(now))]
            return [.movePointer(to: start), .scroll(by: now - start, phase: .began)]
        }
        if options.rotate, let startAngle, let angle = participantsLineAngle(), startDistance > 0,
           abs(distance / startDistance - 1) < constants.pinchRatio {
            let turn = abs(turnDegrees(from: startAngle, to: angle))
            // Both have moved, in directions more than 90° apart: they are going round each other.
            let goingRound = moveA.length >= constants.slop && moveB.length >= constants.slop
                && angleDegrees(moveA, moveB) > 90
            // One is still within the slop of where it landed, and they landed far enough apart
            // for a thumb and a finger: a twist about a resting finger.
            let aboutOne = min(moveA.length, moveB.length) < constants.slop
                && startDistance >= constants.rotatePivotMinimumSpanMM
            if (goingRound && turn > constants.rotateThresholdDegrees)
                || (aboutOne && turn > constants.rotatePivotThresholdDegrees) {
                phase = .touching(.rotating(lastAngle: angle))
                return [.movePointer(to: midpoint(a.current, b.current)),
                        .rotate(by: turnDegrees(from: startAngle, to: angle), phase: .began)]
            }
        }
        return []
    }

    /// Three or four fingers swipe once their centre has moved far enough, close to an axis.
    private func classifySwipe() -> [GestureAction] {
        let fingers = participants.compactMap { contacts[$0] }
        guard options.swipes, !fingers.isEmpty else { return [] }
        let move = millimetres(centroid(fingers.map(\.current)) - centroid(fingers.map(\.start)))
        guard move.length >= constants.swipeDistance else { return [] }
        let horizontal = abs(move.dx) >= abs(move.dy)
        let along = Double(horizontal ? abs(move.dx) : abs(move.dy))
        let across = Double(horizontal ? abs(move.dy) : abs(move.dx))
        guard atan2(across, along) * 180 / .pi <= constants.swipeAngle else { return [] }
        phase = .touching(.finished(momentum: nil))
        let direction: SwipeDirection = horizontal ? (move.dx < 0 ? .left : .right) : (move.dy < 0 ? .up : .down)
        return [.swipe(direction)]
    }

    // MARK: - Swipes that follow the fingers

    /// Three or four fingers begin a followed swipe once their centre has moved `swipeTrackingStart`
    /// within `swipeAngle` of an axis in `followedSwipeAxes`. `nil` until then, and for an axis that
    /// isn't followed, so `classifySwipe` decides as it always has.
    private func beginFollowedSwipe(at time: TimeInterval) -> [GestureAction]? {
        let fingers = participants.compactMap { contacts[$0] }
        guard options.swipes, !fingers.isEmpty else { return nil }
        let now = centroid(fingers.map(\.current))
        let move = millimetres(now - centroid(fingers.map(\.start)))
        guard move.length >= constants.swipeTrackingStart else { return nil }
        let horizontal = abs(move.dx) >= abs(move.dy)
        let axis: SwipeAxis = horizontal ? .horizontal : .vertical
        let along = Double(horizontal ? abs(move.dx) : abs(move.dy))
        let across = Double(horizontal ? abs(move.dy) : abs(move.dx))
        guard followedSwipeAxes.contains(axis), atan2(across, along) * 180 / .pi <= constants.swipeAngle else {
            return nil
        }
        let offset = swipeOffset(along: axis)
        phase = .touching(.swipeTracking(axis: axis, lastOffset: offset))
        scrollSamples = [(time, millimetres(now))]
        return [.swipeTracking(axis: axis, offset: offset, phase: .began)]
    }

    /// Says where a followed swipe has got to, when that changed. Movement across the axis is ignored.
    private func followSwipe(axis: SwipeAxis, lastOffset: Double, at time: TimeInterval) -> [GestureAction] {
        let fingers = participants.compactMap { contacts[$0] }
        guard !fingers.isEmpty else { return [] }
        recordScrollSample(millimetres(centroid(fingers.map(\.current))), at: time)
        let offset = swipeOffset(along: axis)
        guard offset != lastOffset else { return [] }
        phase = .touching(.swipeTracking(axis: axis, lastOffset: offset))
        return [.swipeTracking(axis: axis, offset: offset, phase: .changed)]
    }

    /// The one end of a followed swipe, when its first finger lifts. It completes if the fingers
    /// went `swipeDistance` and aren't coming back faster than `momentumStopSpeed`, or are going on
    /// at `momentumMinSpeed` or more (a flick); otherwise it is cancelled, and the transition slides
    /// back. With no travel at all it is cancelled: there is no way to go on.
    private func endFollowedSwipe(axis: SwipeAxis, at time: TimeInterval) -> GestureAction {
        let offset = swipeOffset(along: axis)
        let size = Double(axis == .horizontal ? surface.width : surface.height)
        let flick = flickVelocity(at: time)
        let speed = Double(axis == .horizontal ? flick.dx : flick.dy)   // mm/s, signed as `offset`
        let onwards: Double = offset < 0 ? -1 : offset > 0 ? 1 : 0
        let forwardSpeed = speed * onwards
        let completes = onwards != 0
            && ((abs(offset) * size >= constants.swipeDistance && forwardSpeed >= -constants.momentumStopSpeed)
                || forwardSpeed >= constants.momentumMinSpeed)
        return .swipeTracking(axis: axis, offset: offset,
                              phase: completes ? .completed(velocity: speed / size) : .cancelled)
    }

    /// How far the participants' centre has moved along `axis` since they landed, as a fraction of
    /// the display's width or height: locations are already fractions of the display.
    private func swipeOffset(along axis: SwipeAxis) -> Double {
        let fingers = participants.compactMap { contacts[$0] }
        let travel = centroid(fingers.map(\.current)) - centroid(fingers.map(\.start))
        return Double(axis == .horizontal ? travel.dx : travel.dy)
    }

    // MARK: - Lifting

    private func lift(_ ids: [Int], at time: TimeInterval) -> [GestureAction] {
        var actions: [GestureAction] = []
        let liftedParticipants = ids.filter(participants.contains)
        if case .touching(let gesture) = phase, !liftedParticipants.isEmpty {
            actions += end(gesture, lifted: liftedParticipants, at: time)
        }
        for id in ids { contacts[id] = nil }
        participants.removeAll(where: ids.contains)
        if contacts.isEmpty { actions += allLifted(at: time) }
        return actions
    }

    private func end(_ gesture: Gesture, lifted: [Int], at time: TimeInterval) -> [GestureAction] {
        switch gesture {
        case .pending(let stoppedMomentum):
            guard let contact = contacts[lifted[0]] else { return [] }
            phase = .touching(.finished(momentum: nil))
            // A touch that stopped a coasting scroll only stops it: on a web page, a click would
            // follow the link under the finger.
            if stoppedMomentum {
                lastTap = nil
                return []
            }
            let count = clickCount(at: contact.start, landedAt: contact.landedAt)
            lastTap = (time, contact.start, count)
            return [.click(at: contact.start, count: count)]

        case .longPressReady:
            guard let contact = contacts[lifted[0]] else { return [] }
            phase = .touching(.finished(momentum: nil))
            // A long-press neither starts nor continues a double-click.
            lastTap = nil
            return [.rightClick(at: contact.start)]

        case .dragging:
            guard let contact = contacts[lifted[0]] else { return [] }
            phase = .touching(.finished(momentum: nil))
            lastTap = nil
            return [.release(at: contact.current)]

        case .scrollingOne, .scrollingTwo:
            let lastSampleTime = scrollSamples.last?.time ?? time
            phase = .touching(.finished(momentum: Flick(velocity: flickVelocity(at: time),
                                                        lastSampleTime: lastSampleTime)))
            return [.scroll(by: .zero, phase: .ended)]

        case .twoPending(let secondLandedAt, _):
            let pair = participants.compactMap { contacts[$0] }
            let deadline = secondLandedAt + constants.twoFingerTapTime
            let stayedStill = pair.allSatisfy { millimetres($0.current - $0.start).length < constants.slop }
            guard options.twoFingerTap, pair.count == 2, stayedStill, time <= deadline else {
                phase = .touching(.finished(momentum: nil))
                return []
            }
            let point = midpoint(pair[0].start, pair[1].start)
            if lifted.count == 2 {
                phase = .touching(.finished(momentum: nil))
                return [.rightClick(at: point)]
            }
            phase = .touching(.twoTapLifting(deadline: deadline, at: point))
            return []

        case .twoTapLifting(let deadline, let point):
            phase = .touching(.finished(momentum: nil))
            return options.twoFingerTap && time <= deadline ? [.rightClick(at: point)] : []

        case .pinching:
            phase = .touching(.finished(momentum: nil))
            return [.pinch(by: 0, phase: .ended)]

        case .rotating:
            phase = .touching(.finished(momentum: nil))
            return [.rotate(by: 0, phase: .ended)]

        case .swipePending:
            return []  // the fingers still down can still swipe

        case .swipeTracking(let axis, _):
            // The first finger to lift ends it: a trackpad has no two-of-three-fingers swipe.
            phase = .touching(.finished(momentum: nil))
            return [endFollowedSwipe(axis: axis, at: time)]

        case .finished:
            return []
        }
    }

    private func allLifted(at time: TimeInterval) -> [GestureAction] {
        participants = []
        // A flick coasts only if the last finger lifts within `flickWindow` of the scroll's last
        // movement: fingers that rested on the glass first get no momentum, rather than late momentum.
        if case .touching(.finished(let flick?)) = phase, flick.velocity.length >= constants.momentumMinSpeed,
           time - flick.lastSampleTime <= constants.flickWindow {
            phase = .coasting(velocity: flick.velocity, lastTime: time)
            return [.momentum(by: .zero, phase: .began)]
        }
        phase = .settling(since: time)
        return []
    }

    // MARK: - Long-press

    /// Says `longPressReady` once one finger has rested `longPressDuration` within the slop, unless
    /// it stopped a coasting scroll. Called by ticks and at the start of each frame, so it is said
    /// at whichever comes first.
    private func longPressIfDue(at time: TimeInterval) -> [GestureAction] {
        guard options.longPress, case .touching(.pending(stoppedMomentum: false)) = phase,
              let id = participants.first, let contact = contacts[id],
              time - contact.landedAt >= constants.longPressDuration else { return [] }
        phase = .touching(.longPressReady)
        return [.longPressReady(at: contact.start)]
    }

    // MARK: - Helpers

    /// 1 for a lone tap; one more than the previous tap's count when this one lands soon after
    /// it and close by.
    private func clickCount(at location: CGPoint, landedAt: TimeInterval) -> Int {
        guard let last = lastTap,
              landedAt - last.liftedAt <= constants.tapInterval,
              millimetres(location - last.location).length <= constants.tapDistance else { return 1 }
        return last.count + 1
    }

    private func recordScrollSample(_ point: CGPoint, at time: TimeInterval) {
        scrollSamples.append((time, point))
        scrollSamples.removeAll { time - $0.time > constants.flickWindow }
    }

    /// The scroll speed in mm/s over the last `flickWindow` before `time`. Zero if the fingers stopped.
    private func flickVelocity(at time: TimeInterval) -> CGVector {
        let recent = scrollSamples.filter { time - $0.time <= constants.flickWindow }
        guard let first = recent.first, let last = recent.last,
              last.time - first.time > constants.flickMinimumSpan else { return .zero }
        return (last.point - first.point).scaled(by: 1 / (last.time - first.time))
    }

    /// The direction of the line from the first participant to the second, in millimetres on the
    /// glass, as `directionDegrees` measures it; `nil` without two participants apart.
    private func participantsLineAngle() -> Double? {
        let pair = participants.prefix(2).compactMap { contacts[$0] }
        guard pair.count == 2 else { return nil }
        return directionDegrees(millimetres(pair[1].current - pair[0].current))
    }

    private func millimetres(_ vector: CGVector) -> CGVector {
        CGVector(dx: vector.dx * surface.width, dy: vector.dy * surface.height)
    }

    private func millimetres(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * surface.width, y: point.y * surface.height)
    }

    private func relative(_ vector: CGVector) -> CGVector {
        CGVector(dx: vector.dx / surface.width, dy: vector.dy / surface.height)
    }
}
