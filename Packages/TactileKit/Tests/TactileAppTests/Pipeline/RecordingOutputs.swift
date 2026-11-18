// A pipeline's outputs, recorded instead of carried out: a capturing event sender, a pointer keeper
// with stand-ins for the pointer, the arrow and the warp, a real arbiter, recorded circles, and a
// Dock-swipe sender whose events are captured and whose surroundings are a fake. Nothing here posts
// an event, a Dock swipe or anything else, moves the pointer, hides the arrow or opens a window.

import CoreGraphics
import Foundation
import TactileApp
import TactileGestures
import TactileOutput
import TactileScreens

/// Calls made on the fakes, in order, shared by several fakes when a test needs to know which came
/// first.
@MainActor
final class CallLog {
    private(set) var entries: [String] = []

    func add(_ entry: String) {
        entries.append(entry)
    }

    /// The index of the first entry that starts with `prefix`.
    func first(_ prefix: String) -> Int? {
        entries.firstIndex { $0.hasPrefix(prefix) }
    }

    /// The index of the last entry that starts with `prefix`.
    func last(_ prefix: String) -> Int? {
        entries.lastIndex { $0.hasPrefix(prefix) }
    }
}

/// One event the sender would have posted.
struct PostedEvent: Equatable {
    enum Kind: String {
        case move, down, up, drag, rightDown, rightUp, scroll, gesture, keyDown, keyUp, other
    }

    let kind: Kind
    let location: CGPoint
    let clickState: Int64
    let scrollPhase: Int64
    let momentumPhase: Int64
    /// Points, vertical and horizontal.
    let scrollY: Int64
    let scrollX: Int64
    /// The phase of a zoom or rotate gesture event (field 132).
    let gesturePhase: Int64
    /// What a gesture event is (field 110): 8 a zoom, 5 a rotation.
    let gestureSubtype: Int64
    /// A rotation's degrees (field 114, a double).
    let rotation: Double

    init(_ event: CGEvent) {
        switch event.type {
        case .mouseMoved: kind = .move
        case .leftMouseDown: kind = .down
        case .leftMouseUp: kind = .up
        case .leftMouseDragged: kind = .drag
        case .rightMouseDown: kind = .rightDown
        case .rightMouseUp: kind = .rightUp
        case .scrollWheel: kind = .scroll
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        default: kind = event.type.rawValue == 29 ? .gesture : .other
        }
        // A scroll, a zoom or rotate gesture and a key carry the place the Mac's own pointer is when
        // they are made (`CGEvent` fills it in, and `EventSender.pointerLocation` reads it): where the
        // test machine's mouse happens to be, which moves under the person's hand between two runs
        // of the same frames. Tactile chooses the place only of the mouse events, so only theirs is
        // kept; the others read zero, and two runs compare equal however the real mouse moved.
        switch kind {
        case .scroll, .gesture, .keyDown, .keyUp: location = .zero
        case .move, .down, .up, .drag, .rightDown, .rightUp, .other: location = event.location
        }
        clickState = event.getIntegerValueField(.mouseEventClickState)
        scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        scrollY = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        scrollX = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        gesturePhase = CGEventField(rawValue: 132).map { event.getIntegerValueField($0) } ?? 0
        gestureSubtype = CGEventField(rawValue: 110).map { event.getIntegerValueField($0) } ?? 0
        rotation = CGEventField(rawValue: 114).map { event.getDoubleValueField($0) } ?? 0
    }

    var isRotation: Bool { kind == .gesture && gestureSubtype == 5 }
    var isZoom: Bool { kind == .gesture && gestureSubtype == 8 }

    /// Whether it moves the pointer to `location`, as the system would.
    var movesPointer: Bool {
        [.move, .down, .up, .drag, .rightDown, .rightUp].contains(kind)
    }
}

/// One Dock-swipe event the sender would have posted: a Dock control event (type 30) or its empty
/// gesture companion (type 29).
struct DockEvent: Equatable {
    enum Phase: Int64 {
        case began = 1, changed = 2, ended = 4, cancelled = 8
    }

    let type: Int64
    let phase: Phase?
    let progress: Double

    init(_ event: CGEvent) {
        type = Int64(event.type.rawValue)
        phase = CGEventField(rawValue: 132).flatMap { Phase(rawValue: event.getIntegerValueField($0)) }
        progress = CGEventField(rawValue: 124).map { event.getDoubleValueField($0) } ?? 0
    }

    var isSwipe: Bool { type == 30 }
    var isEnd: Bool { isSwipe && (phase == .ended || phase == .cancelled) }
}

/// The Mac as a fake: a macOS the sender knows, the person's gesture on, three Spaces on every
/// display. A test changes any of it.
final class FakeDockSwipeSurroundings: DockSwipeSurroundings {
    var macOSMajorVersion = 15
    var isSpaceSwipeEnabled = true
    /// The Spaces on each display; `defaultSpaces` for one not listed.
    var spaces: [UInt32: Int?] = [:]
    var defaultSpaces: Int? = 3

    func spaceCount(forDisplay displayID: UInt32) -> Int? {
        spaces[displayID] ?? defaultSpaces
    }
}

/// What the circles were asked to do.
enum CircleCall: Equatable {
    case show(display: UInt32, fingers: [Int: CGPoint], hollow: Set<Int>, ringed: Set<Int> = [])
    case hide(display: UInt32)

    /// The ringed contact IDs of a `show`; nil for a `hide`.
    var ringed: Set<Int>? {
        if case .show(_, _, _, let ringed) = self { return ringed }
        return nil
    }
}

/// Where everything the outputs are asked to do goes. A class of its own, so the sender's and the
/// keeper's closures can reach it before the outputs exist.
@MainActor
final class OutputsRecord {
    var events: [PostedEvent] = []
    /// Where the pointer is: it starts at `DeskFixture.pointerHome` and follows the mouse events, as
    /// the real pointer follows the real ones.
    var pointer = DeskFixture.pointerHome
    var arrowHidden: [Bool] = []
    var warps: [CGPoint] = []
    var circles: [CircleCall] = []
    var intentQuestions: [CGPoint] = []
    /// The app each of those questions went to.
    var intentApps: [pid_t] = []
    /// Where the pipeline asked which app's window is under a point: for drag or scroll, and as a
    /// scroll began.
    var appQuestions: [CGPoint] = []
    /// What the Dock-swipe sender delivered, and the waits it asked for (its repeated ends), which
    /// run only when a test runs them.
    var dockEvents: [DockEvent] = []
    var dockScheduled: [(delay: TimeInterval, work: @MainActor () -> Void)] = []
    /// The Dock-swipe sender's clock: a second more at each reading, so no `changed` is held back.
    var dockClock: TimeInterval = 0
    let log: CallLog

    init(log: CallLog) {
        self.log = log
    }
}

@MainActor
final class RecordingOutputs: PipelineOutputs {
    let record: OutputsRecord
    let sender: EventSender
    let keeper: PointerKeeper
    let arbiter = PointerArbiter<TouchscreenID>()
    let dockSwipes: DockSwipeSender
    let dockSurroundings = FakeDockSwipeSurroundings()
    /// What `intent(atDesktopPoint:)` answers.
    var intentAnswer: OneFingerIntent = .drag
    /// What `app(atDesktopPoint:)` answers for a point: everywhere, an app with no bundle identifier
    /// (so a scroll is posted as moved), unless a test says.
    var appAnswer: (CGPoint) -> AppUnderPoint? = { _ in AppUnderPoint(pid: 4242, bundleIdentifier: nil) }

    init(log: CallLog? = nil) {
        let record = OutputsRecord(log: log ?? CallLog())
        self.record = record
        dockSwipes = DockSwipeSender(
            deliver: { event in
                MainActor.assumeIsolated {
                    let dock = DockEvent(event)
                    record.dockEvents.append(dock)
                    if dock.isSwipe { record.log.add("dock \(dock.phase.map { "\($0)" } ?? "?")") }
                }
            },
            surroundings: dockSurroundings,
            clock: { MainActor.assumeIsolated { record.dockClock += 1; return record.dockClock } },
            schedule: { delay, work in MainActor.assumeIsolated { record.dockScheduled.append((delay, work)) } })
        sender = EventSender(deliver: { event in
            MainActor.assumeIsolated {
                let posted = PostedEvent(event)
                record.events.append(posted)
                record.log.add("event \(posted.kind.rawValue)")
                if posted.movesPointer { record.pointer = posted.location }
            }
        })
        keeper = PointerKeeper(
            pointerLocation: { MainActor.assumeIsolated { record.pointer } },
            setArrowHidden: { hidden in
                MainActor.assumeIsolated {
                    record.arrowHidden.append(hidden)
                    record.log.add(hidden ? "arrow hidden" : "arrow shown")
                }
            },
            warp: { point in
                MainActor.assumeIsolated {
                    record.warps.append(point)
                    record.pointer = point
                    record.log.add("warp")
                }
            })
    }

    var events: [PostedEvent] { record.events }

    /// The Dock swipe events delivered (not their companions).
    var dockSwipeEvents: [DockEvent] { record.dockEvents.filter(\.isSwipe) }

    /// The Dock swipe events' phases, in order.
    var dockPhases: [DockEvent.Phase] { dockSwipeEvents.compactMap(\.phase) }

    /// The keyboard shortcuts posted: one key-down each.
    var shortcuts: Int { count(.keyDown) }

    func sendDockSwipeWaitsNow() {
        runDockScheduled()
    }

    /// Runs the waits the Dock-swipe sender asked for, as time passing would.
    func runDockScheduled() {
        let due = record.dockScheduled
        record.dockScheduled = []
        for (_, work) in due { work() }
    }

    func events(_ kind: PostedEvent.Kind) -> [PostedEvent] {
        record.events.filter { $0.kind == kind }
    }

    func count(_ kind: PostedEvent.Kind) -> Int {
        events(kind).count
    }

    func intent(atDesktopPoint point: CGPoint, inApp pid: pid_t) -> OneFingerIntent {
        record.intentQuestions.append(point)
        record.intentApps.append(pid)
        return intentAnswer
    }

    func app(atDesktopPoint point: CGPoint) -> AppUnderPoint? {
        record.appQuestions.append(point)
        return appAnswer(point)
    }

    func showCircles(_ fingers: [Int: CGPoint], hollow: Set<Int>, ringed: Set<Int>, onDisplay displayID: UInt32) {
        record.circles.append(.show(display: displayID, fingers: fingers, hollow: hollow, ringed: ringed))
        record.log.add("circles show")
    }

    func hideCircles(onDisplay displayID: UInt32) {
        record.circles.append(.hide(display: displayID))
        record.log.add("circles hide")
    }
}
