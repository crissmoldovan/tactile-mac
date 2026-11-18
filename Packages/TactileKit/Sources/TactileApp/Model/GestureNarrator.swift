// The gesture tester's feed: what one touchscreen's pipeline did, in plain words.

import CoreGraphics
import Foundation
import TactileGestures

/// Writes the gesture tester's feed from what the tested touchscreen's pipeline tells it, in order
/// (`TouchObservation`): the contacts on its glass, what it didn't act on and why, its engine's
/// actions, and the touches it cut short. Pure: the same observations give the same feed.
///
/// The gesture rules, as the feed tells them, each with its `fingers`:
/// - **Tap, double tap, triple tap** (1): each click, by its count, as macOS gets it: a double tap
///   is a tap, then a double tap. A fourth click in a row is a triple tap that says so.
/// - **Drag** (1): press, drag, release, one entry. **Hold, then drag** (1): a press whose finger
///   rested at least the engine's hold time before it moved, which the engine makes a drag whatever
///   the one-finger setting, or one that follows the ring (`longPressReady`); a press any sooner is
///   a drag.
/// - **Scroll** (1 or 2, the fingers that scrolled): one entry per scroll, with how far, updated in
///   place while it goes on. **Flick** (its scroll's): the momentum after it, how far it coasted.
/// - **Pinch** (2): the overall zoom factor, to two decimals near 1× ("zoom unchanged" at 1.00×). **Rotate** (2): the overall degrees and their direction.
///   Each one entry, updated in place.
/// - **Right-click**: from a long press (1) when the ring came first, else from a two-finger tap (2).
/// - **Swipe** (3 or 4): direction and what it does, or would do when the tester holds swipes.
///   **Followed swipe** (3 or 4): one entry, completed or slid back.
/// - **Ignored** (the contacts on the glass then): a contact not acted on, once until it lifts,
///   grouped by why in each frame. What is left of a touch cut short is not said again.
/// - **Cancelled** (the contacts on the glass then): a touch cut short, with what was cut (the
///   gesture under way, the long press, or the touch) and why; nothing when nothing was under way
///   (fingers up, no flick).
///
/// Distances are the fingers' net movement, in points of the display, as the events carry them: the
/// content moves with the fingers. An action whose start it missed (the tester opened, or was
/// cleared, mid-gesture) starts its entry where it comes.
struct GestureNarrator: Equatable {
    typealias Kind = RecognisedGesture.Kind

    /// The most entries `recent` keeps.
    static let mostRecent = 40

    /// Newest first, at most `mostRecent`.
    private(set) var recent: [RecognisedGesture] = []
    /// How many of each kind since it began or was cleared.
    private(set) var counts: [Kind: Int] = [:]
    /// Every contact on the glass in the last frame, counted or not.
    private(set) var fingersOnGlass = 0
    /// Rises whenever anything shown changes: `recent`, `counts` or `fingersOnGlass`.
    private(set) var version = 0

    private var nextID = 1
    /// The fingers that count (not ignored) in the last frame.
    private var counting = 0
    /// The most that counted at once in the touch now, or the last one.
    private var touchFingers = 0
    /// When the touch now, or the last one, began: the frame its first counting finger came in.
    /// Nil until a touch has been seen from its start.
    private var touchLandedAt: TimeInterval?
    /// Contacts already said as ignored, until they lift.
    private var saidIgnored: Set<Int> = []
    /// The last action was `longPressReady`: lifting right-clicks, moving drags.
    private var ringed = false
    /// The entry updated in place.
    private var open: Open?
    /// The flick coasting now.
    private var coast: Coast?
    private var lastScrollFingers = 1
    /// The touch is being cut short, and why; until the engine's `sessionCancelled`.
    private var cut: CutShortBecause?
    /// What the cut closed, if it closed a gesture.
    private var cutWhat: String?
    /// The entries finished by the current observation, for the log.
    private var finishing: [Int] = []

    private enum Open: Equatable {
        case drag(id: Int, count: Int, from: CGPoint, to: CGPoint)
        case scroll(id: Int, moved: CGVector)
        case pinch(id: Int, factor: Double)
        case rotate(id: Int, degrees: Double)
        case swipe(id: Int, axis: SwipeAxis, offset: Double, held: Bool)

        var id: Int {
            switch self {
            case .drag(let id, _, _, _), .scroll(let id, _), .pinch(let id, _), .rotate(let id, _),
                 .swipe(let id, _, _, _):
                return id
            }
        }
    }

    private struct Coast: Equatable {
        var id: Int
        var moved: CGVector
    }

    /// One count per kind seen, in the order of `Kind.allCases`.
    var seen: [GestureSeenCount] {
        Kind.allCases.compactMap { kind in counts[kind].map { GestureSeenCount(id: kind, count: $0) } }
    }

    /// Empties `recent` and the counts. A gesture under way goes on in a new entry.
    mutating func clear() {
        recent = []
        counts = [:]
        open = nil
        coast = nil
        version += 1
    }

    /// Nothing under way: no finger on the glass, no entry being updated, no flick coasting. What it
    /// shows now is what it will show until the next touch.
    var isIdle: Bool {
        fingersOnGlass == 0 && open == nil && coast == nil
    }

    /// Takes in one observation, made at `time`, on a display `displaySize` points big, from a
    /// pipeline whose engine forces a drag after `holdTime` (`GestureConstants.holdTime`). Returns the
    /// entries it finished: said once, or ended after being updated in place.
    @discardableResult
    mutating func see(_ observation: TouchObservation, at time: TimeInterval, displaySize: CGSize,
                      holdTime: TimeInterval) -> [RecognisedGesture] {
        finishing = []
        switch observation {
        case .frame(let onGlass, let ignored):
            frame(onGlass: onGlass, ignored: ignored, at: time)
        case .action(let action, let held):
            act(action, held: held, at: time, size: displaySize, holdTime: holdTime)
        case .cutShort(let why):
            cut = why
            cutWhat = nil
        }
        let finished = finishing
        finishing = []
        return finished.compactMap { id in recent.first { $0.id == id } }
    }

    // MARK: - Frames

    private mutating func frame(onGlass: Set<Int>, ignored: [Int: IgnoredBecause], at time: TimeInterval) {
        if fingersOnGlass != onGlass.count {
            fingersOnGlass = onGlass.count
            version += 1
        }
        saidIgnored.formIntersection(onGlass)
        let nowCounting = onGlass.subtracting(ignored.keys).count
        if nowCounting > 0, counting == 0 { touchLandedAt = time }
        if nowCounting > 0 { touchFingers = counting == 0 ? nowCounting : max(touchFingers, nowCounting) }
        counting = nowCounting
        let fresh = ignored.filter { !saidIgnored.contains($0.key) }
        saidIgnored.formUnion(fresh.keys)
        for reason in IgnoredBecause.allCases where reason != .restOfATouchCutShort {
            let contacts = fresh.values.filter { $0 == reason }.count
            if contacts > 0 { say(.ignored, fingers: onGlass.count, Self.ignored(reason), at: time) }
        }
    }

    // MARK: - Actions

    private mutating func act(_ action: GestureAction, held: Bool, at time: TimeInterval, size: CGSize,
                              holdTime: TimeInterval) {
        func points(_ vector: CGVector) -> CGVector {
            CGVector(dx: vector.dx * size.width, dy: vector.dy * size.height)
        }
        switch action {
        case .sessionBegan, .movePointer:
            break

        case .click(_, let count):
            ringed = false
            let kind: Kind = count >= 3 ? .tripleTap : count == 2 ? .doubleTap : .tap
            say(kind, fingers: 1, Self.clicks(count), at: time)

        case .press(let at, let count):
            // The engine's own test: the finger rested `holdTime` before it crossed the slop.
            let rested = touchLandedAt.map { time - $0 >= holdTime } ?? false
            let kind: Kind = ringed || rested ? .holdThenDrag : .drag
            ringed = false
            finishOpen()
            let id = add(kind, fingers: 1, Self.dragged(.zero, count: count), at: time)
            open = .drag(id: id, count: count, from: at, to: at)

        case .drag(let to):
            guard case .drag(let id, let count, let from, _) = open else {
                let id = add(.drag, fingers: 1, Self.dragged(.zero, count: 1), at: time)
                open = .drag(id: id, count: 1, from: to, to: to)
                return
            }
            open = .drag(id: id, count: count, from: from, to: to)
            update(id, Self.dragged(points(to - from), count: count))

        case .release(let at):
            guard case .drag(let id, let count, let from, _) = open else { return }
            let note = noteCut("the drag")
            update(id, Self.dragged(points(at - from), count: count) + note)
            finishOpen()

        case .rightClick:
            let fromLongPress = ringed
            ringed = false
            say(.rightClick, fingers: fromLongPress ? 1 : 2,
                fromLongPress ? "from a long press" : "from a two-finger tap", at: time)

        case .longPressReady:
            ringed = true

        case .longPressWithdrawn:
            ringed = false

        case .scroll(let by, let phase):
            switch (phase, open) {
            case (.changed, .scroll(let id, let moved)):
                let now = moved + points(by)
                open = .scroll(id: id, moved: now)
                update(id, Self.distance(now))
            case (.ended, .scroll(let id, let moved)):
                let note = noteCut("the scroll")
                update(id, Self.distance(moved) + note)
                finishOpen()
            case (.ended, _):
                break
            case (.began, _), (.changed, _):
                finishOpen()
                let fingers = min(max(counting, 1), 2)
                lastScrollFingers = fingers
                let moved = points(by)
                open = .scroll(id: add(.scroll, fingers: fingers, Self.distance(moved), at: time), moved: moved)
            }

        case .momentum(let by, let phase):
            switch (phase, coast) {
            case (.changed, var flick?):
                flick.moved = flick.moved + points(by)
                coast = flick
                update(flick.id, Self.coasted(flick.moved))
            case (.ended, let flick?):
                let ending = counting > 0 && cut == nil ? ", stopped by a touch" : noteCut("the flick")
                update(flick.id, Self.coasted(flick.moved) + ending)
                finishing.append(flick.id)
                coast = nil
            case (.ended, nil):
                break
            case (.began, _), (.changed, nil):
                if let flick = coast { finishing.append(flick.id) }
                let moved = points(by)
                coast = Coast(id: add(.flick, fingers: lastScrollFingers, Self.coasted(moved), at: time), moved: moved)
            }

        case .pinch(let by, let phase):
            switch (phase, open) {
            case (.changed, .pinch(let id, let factor)), (.ended, .pinch(let id, let factor)):
                let now = factor * (1 + by)
                open = .pinch(id: id, factor: now)
                let note = phase == .ended ? noteCut("the pinch") : ""
                update(id, Self.zoom(now) + note)
                if phase == .ended { finishOpen() }
            case (.ended, _):
                break
            case (.began, _), (.changed, _):
                finishOpen()
                open = .pinch(id: add(.pinch, fingers: 2, Self.zoom(1 + by), at: time), factor: 1 + by)
            }

        case .rotate(let by, let phase):
            switch (phase, open) {
            case (.changed, .rotate(let id, let degrees)), (.ended, .rotate(let id, let degrees)):
                let now = degrees + by
                open = .rotate(id: id, degrees: now)
                let note = phase == .ended ? noteCut("the rotation") : ""
                update(id, Self.turned(now) + note)
                if phase == .ended { finishOpen() }
            case (.ended, _):
                break
            case (.began, _), (.changed, _):
                finishOpen()
                open = .rotate(id: add(.rotate, fingers: 2, Self.turned(by), at: time), degrees: by)
            }

        case .swipe(let direction):
            say(.swipe, fingers: swipeFingers, Self.swiped(direction, held: held), at: time)

        case .swipeTracking(let axis, let offset, let phase):
            let id: Int
            var wasHeld = held
            if case .swipe(let openID, _, _, let openHeld) = open, phase != .began {
                id = openID
                wasHeld = openHeld
            } else {
                finishOpen()
                id = add(.followedSwipe, fingers: swipeFingers, Self.following(axis, offset), at: time)
            }
            open = .swipe(id: id, axis: axis, offset: offset, held: wasHeld)
            switch phase {
            case .began, .changed:
                update(id, Self.following(axis, offset))
            case .completed:
                update(id, Self.followed(axis, offset, completed: true, held: wasHeld))
                finishOpen()
            case .cancelled:
                let note = noteCut("the swipe")
                update(id, Self.followed(axis, offset, completed: false, held: wasHeld) + note)
                finishOpen()
            }

        case .sessionEnded:
            ringed = false
            finishOpen()

        case .sessionCancelled:
            let what = cutWhat ?? open.map(Self.what) ?? (ringed ? "the long press" : counting > 0 ? "the touch" : nil)
            if let what {
                say(.cancelled, fingers: fingersOnGlass, "\(what) cut short: \(Self.because(cut ?? .stopped))", at: time)
            }
            finishOpen()
            if let flick = coast { finishing.append(flick.id) }
            coast = nil
            ringed = false
            cut = nil
            cutWhat = nil
        }
    }

    /// A swipe's fingers: 3 or 4, the most that counted in its touch.
    private var swipeFingers: Int {
        min(4, max(3, touchFingers))
    }

    // MARK: - Entries

    /// A new entry, newest first; counted. Returns its ID.
    private mutating func add(_ kind: Kind, fingers: Int, _ summary: String, at time: TimeInterval) -> Int {
        let id = nextID
        nextID += 1
        recent.insert(RecognisedGesture(id: id, kind: kind, fingers: fingers, summary: summary, at: time), at: 0)
        if recent.count > Self.mostRecent { recent.removeLast(recent.count - Self.mostRecent) }
        counts[kind, default: 0] += 1
        version += 1
        return id
    }

    /// A new entry said once: finished as it is said.
    private mutating func say(_ kind: Kind, fingers: Int, _ summary: String, at time: TimeInterval) {
        finishing.append(add(kind, fingers: fingers, summary, at: time))
    }

    private mutating func update(_ id: Int, _ summary: String) {
        guard let index = recent.firstIndex(where: { $0.id == id }), recent[index].summary != summary else { return }
        recent[index].summary = summary
        version += 1
    }

    /// The entry updated in place is finished.
    private mutating func finishOpen() {
        guard let open else { return }
        finishing.append(open.id)
        self.open = nil
    }

    /// ", cut short" while the touch is being cut short, noting what was cut; else nothing.
    private mutating func noteCut(_ what: String) -> String {
        guard cut != nil else { return "" }
        cutWhat = what
        return ", cut short"
    }

    // MARK: - Words

    private static func what(_ open: Open) -> String {
        switch open {
        case .drag: return "the drag"
        case .scroll: return "the scroll"
        case .pinch: return "the pinch"
        case .rotate: return "the rotation"
        case .swipe: return "the swipe"
        }
    }

    static func clicks(_ count: Int) -> String {
        switch count {
        case ...1: return "a click"
        case 2: return "a double-click"
        case 3: return "a triple-click"
        default: return "\(count) clicks in a row"
        }
    }

    /// "240 pt right", and the press's count when it follows taps.
    static func dragged(_ moved: CGVector, count: Int) -> String {
        switch count {
        case ...1: return distance(moved)
        case 2: return "\(distance(moved)), as a double-click drag"
        default: return "\(distance(moved)), as a triple-click drag"
        }
    }

    /// "340 pt down"; "240 pt right, 120 pt down" when the other way is at least a third as far and
    /// 10 pt or more. Down and right are the display's.
    static func distance(_ moved: CGVector) -> String {
        let across = Int(abs(moved.dx).rounded()), along = Int(abs(moved.dy).rounded())
        if across == 0, along == 0 { return "0 pt" }
        let horizontal = "\(across) pt \(moved.dx < 0 ? "left" : "right")"
        let vertical = "\(along) pt \(moved.dy < 0 ? "up" : "down")"
        let (major, minor, majorValue, minorValue) = along >= across
            ? (vertical, horizontal, along, across) : (horizontal, vertical, across, along)
        return minorValue >= 10 && minorValue * 3 >= majorValue ? "\(major), \(minor)" : major
    }

    static func coasted(_ moved: CGVector) -> String {
        "coasted \(distance(moved))"
    }

    /// "zoom in, 1.4×"; "zoom out, 0.7×"; near 1×, two decimals: "zoom in, 1.04×"; and "zoom
    /// unchanged" when that is 1.00×.
    static func zoom(_ factor: Double) -> String {
        let near = factor > 0.9 && factor < 1.1
        let shown = String(format: near ? "%.2f" : "%.1f", factor)
        if shown == "1.00" { return "zoom unchanged" }
        return "zoom \(factor >= 1 ? "in" : "out"), \(shown)\u{00D7}"
    }

    /// "35° anticlockwise": positive is anticlockwise, as the rotate events have it.
    static func turned(_ degrees: Double) -> String {
        "\(Int(abs(degrees).rounded()))\u{00B0} \(degrees >= 0 ? "anticlockwise" : "clockwise")"
    }

    /// What a swipe in `direction` does: the Mission Control shortcut the pipeline posts for it.
    static func does(_ direction: SwipeDirection) -> String {
        switch direction {
        case .left: return "left: next Desktop"
        case .right: return "right: previous Desktop"
        case .up: return "up: Mission Control"
        case .down: return "down: App Expos\u{00E9}"
        }
    }

    static let heldNote = "; not done: the tester holds swipes"

    static func swiped(_ direction: SwipeDirection, held: Bool) -> String {
        does(direction) + (held ? heldNote : "")
    }

    /// The direction a followed swipe's offset is going, as the pipeline reads it for the shortcut.
    private static func direction(_ axis: SwipeAxis, _ offset: Double) -> SwipeDirection {
        axis == .horizontal ? (offset < 0 ? .left : .right) : (offset < 0 ? .up : .down)
    }

    private static func name(_ direction: SwipeDirection) -> String {
        switch direction {
        case .left: return "left"
        case .right: return "right"
        case .up: return "up"
        case .down: return "down"
        }
    }

    static func following(_ axis: SwipeAxis, _ offset: Double) -> String {
        offset == 0 ? "following the fingers" : "\(name(direction(axis, offset))), following the fingers"
    }

    static func followed(_ axis: SwipeAxis, _ offset: Double, completed: Bool, held: Bool) -> String {
        let direction = direction(axis, offset)
        let outcome = completed ? does(direction) : "\(name(direction)), slid back"
        return outcome + (held ? heldNote : "")
    }

    static func ignored(_ reason: IgnoredBecause) -> String {
        switch reason {
        case .palm: return "a palm"
        case .hand: return "a whole hand"
        case .edge: return "a touch at the edge"
        case .beyondOneFinger: return "a second finger on a one-finger touchscreen"
        case .otherTouchscreenHasThePointer: return "the other touchscreen has the pointer"
        case .alreadyDown: return "a touch from before: lift and touch again"
        case .restOfATouchCutShort: return "the rest of a touch cut short"
        }
    }

    static func because(_ why: CutShortBecause) -> String {
        switch why {
        case .palm: return "a palm or a hand landed"
        case .takenOver: return "the other touchscreen took the pointer"
        case .silence: return "the touchscreen went quiet"
        case .stopped: return "Tactile stopped following this touch"
        }
    }
}

private func + (a: CGVector, b: CGVector) -> CGVector {
    CGVector(dx: a.dx + b.dx, dy: a.dy + b.dy)
}

private func - (a: CGPoint, b: CGPoint) -> CGVector {
    CGVector(dx: a.x - b.x, dy: a.y - b.y)
}
