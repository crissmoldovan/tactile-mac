// One touchscreen's path from frames of contacts to actions carried out.

import CoreGraphics
import Foundation
import TactileGestures
import TactileOutput
import TactileReading
import TactileScreens
import os

/// One driving touchscreen's path from frames of contacts to the events that carry them out.
///
/// Every frame, in this order (the contract between engine, keeper and arbiter):
/// 1. Each contact is mapped onto the display, as a `Finger` with its ID, size in millimetres and
///    confidence.
/// 2. The contact filter decides which fingers count, with its finger limit and this touchscreen's
///    rejection rules, given the frame's time and the glass's size. If it refused a contact that had
///    counted (a palm), the touch is cut short before the engine sees the frame: the engine's
///    session is cancelled, its actions carried out, and the keeper told the session was cancelled.
///    The fingers still down are then not acted on until none counts: they are drawn hollow and
///    never reach the arbiter, so they can't hold the pointer against another touchscreen.
/// 3. The arbiter decides, from the fingers that count, whether this touchscreen may use the
///    pointer. `.ignore`: every finger is drawn hollow, and the frame goes no further.
///    `.processAfterCancelling(other)`: the touchscreen that had the pointer is cancelled first,
///    through `cancelOther`.
/// 4. The gesture engine turns the frame into actions, and they are carried out.
/// 5. Circles: the fingers that count solid, the ones the filter refused hollow, and the one finger
///    whose lift will right-click (the engine's `longPressReady`) ringed, until the engine's next
///    action, whatever it is. `longPressReady` can come from a tick: the circles are drawn again then.
///
/// Locations go to the desktop through the mapping; scroll distances are fractions of the display
/// and become points of the picture's frame. `sessionBegan` hands the pointer keeper the picture's
/// frame and this touchscreen's return setting; `sessionEnded` tells the keeper and frees the
/// pointer; `sessionCancelled` only frees the pointer.
///
/// **Silence.** Neither reader lifts a finger by itself: if a panel's one lift report is lost, the
/// finger would stay down, and the button with it. So while fingers are down `needsTicks` is true,
/// and a tick more than `silenceLimit` after the last frame cancels the touch as `.stoppedDriving`
/// does; the pipeline then starts afresh, with a new engine and filter, and stays in use. If the
/// silence was the main thread stalling rather than a lost lift, the reports made meanwhile arrive
/// afterwards, timed before the cancel; if the panel itself went quiet with the finger held, its
/// reports resume after the cancel with the same contact. Either way the fingers are the touch that
/// was cancelled, and are ignored until they lift, so a drag is never split in two: the first frame
/// after the cancel is taken for the same touch when it is timed before the cancel, or when it
/// shares a contact ID with the touch and comes within `silenceLimit` of the cancel. (Taking a new
/// touch for the old one costs one tap; the other way round, a press nobody made.)
///
/// **Followed swipes** (experimental). At the start of each session the engine is told to follow
/// horizontal swipes when the general setting is on (`Driving.swipesFollowFingers`) and the shared
/// Dock-swipe sender says it can (`isAvailable(.horizontal)`, which reads the person's settings);
/// never mid-swipe. Each `swipeTracking` goes to the sender, with the picture's display and width.
/// When the sender returns false for a `completed` (it couldn't follow the swipe), today's shortcut
/// is posted for the direction of the offset, as it is for a swipe something else closed meanwhile
/// (the model, on a display change); for a `cancelled`, nothing; never both. A swipe left
/// open is a failure of the same kind as a button left held: every way this pipeline stops (it
/// stops driving, the silence rule, a palm, a take-over) first closes its open swipe with
/// `closeIfOpen()`, then cancels the engine as always, whose later end for that swipe the sender
/// then handles with nothing. Only its own open swipe: the sender is shared, and another
/// touchscreen's can't be open while this one's fingers are down. The sender repeats an end
/// `DockSwipeSender.endRepeatDelay` after it, at the display under the pointer, so for that long
/// after this touchscreen's swipe ends the pointer stays: its session's end (and the keeper's
/// return home) waits for it, and the arbiter is told its fingers are still down, so no other
/// touchscreen takes the pointer; then, on a tick, that they are up.
///
/// **The gesture tester.** While it is open for this touchscreen, `observer` is told every frame (the
/// contacts on the glass, and those not acted on, with why), every action once carried out, and
/// every touch cut short, with why; with no observer none of it is worked out. One thing changes
/// while it observes: a three- or four-finger swipe that begins while it `holdsSwipes` is held, and
/// nothing is posted for it, neither shortcut nor Dock swipe; a followed swipe keeps what it began
/// with to its end, so it is never left open and never gets two ends.
///
/// Main thread only, like everything it calls.
@MainActor
public final class TouchPipeline {

    /// How long a touchscreen may send nothing while fingers are down before the touch is taken to
    /// have ended unseen. Both real panels repeat their reports while touched; the longest silence
    /// recorded with a finger down is 0.45 s, on the strip.
    public static let silenceLimit: TimeInterval = 1.5

    public enum CancelReason: Sendable {
        /// Its touchscreen stopped driving: unplugged, turned off, display lost, locked, quitting.
        /// The model also uses it when where its touches land changes in the middle of a touch,
        /// and then starts a fresh pipeline.
        case stoppedDriving
        /// Another touchscreen took the pointer while this one's fingers were up.
        case takenOver
    }

    public let id: TouchscreenID
    /// What it drives with now.
    public private(set) var driving: Driving
    /// While frames are recorded: every frame the engine is given is appended to it first.
    public var recorder: FrameRecorder?
    private let outputs: PipelineOutputs
    private let cancelOther: @MainActor (TouchscreenID, TimeInterval) -> Void

    private var filter: ContactFilter
    /// Made on first use, so that its question about a finger can reach this pipeline.
    private lazy var engine = makeEngine()
    /// Whether the last frame had fingers on the glass, and when it came.
    private var fingersOnGlass = false
    private var lastFrameTime: TimeInterval = 0
    /// The contact IDs of the last frame.
    private var lastContactIDs: Set<Int> = []
    /// When the silence watchdog last cancelled a touch, and that touch's contact IDs, until the
    /// next frame.
    private var silenced: (at: TimeInterval, contacts: Set<Int>)?
    /// Fingers that were already down when this pipeline began are not acted on; it waits for a
    /// frame with none.
    private var waitingForClear: Bool
    /// The display circles were last shown on, while any may still be showing.
    private var circlesShownOn: UInt32?
    /// Set by `cancel(at:reason: .stoppedDriving)`: nothing more is done.
    private var hasStopped = false
    /// New options arrived while fingers were down: they reach the engine and the filter when the
    /// glass is next clear.
    private var optionsWaitForClearGlass = false
    /// The filter cut a touch short: the fingers that still count are not acted on until a frame in
    /// which none does.
    private var ignoringUntilNoneCounts = false
    /// Whether the finger whose lift will right-click is ringed.
    private var isRinged = false
    /// What the circles last showed, to draw them again when the ring changes on a tick.
    private var lastCircles: (fingers: [Finger], hollow: Set<Int>)?
    /// The engine's thresholds.
    let constants: GestureConstants
    /// Whether this touchscreen's followed swipe is open in the shared sender: its `began` was
    /// posted, and its end hasn't been handed over or closed.
    private var ownsOpenSwipe = false
    /// When this touchscreen's last followed swipe ended: the pointer stays until
    /// `DockSwipeSender.endRepeatDelay` after.
    private var swipeEndedAt: TimeInterval?
    /// A session end held back until then.
    private var sessionEndDue: TimeInterval?
    /// The arbiter was told this touchscreen's fingers were down only because its swipe's end was
    /// being repeated: it is told they are up once that is over.
    private var fingersDownForTheHoldOnly = false
    /// The gesture tester, while it is open for this touchscreen; nil otherwise.
    public weak var observer: (any TouchPipelineObserver)?
    /// The followed swipe under way began while the tester held swipes: nothing is posted for it.
    private var swipeIsHeld = false
    /// Where this pipeline last moved the pointer, on the desktop: where a touch's first finger
    /// landed, or two fingers' scroll began. A scroll is posted there.
    private var pointerMovedTo: CGPoint?

    /// `cancelOther` is how a take-over reaches the touchscreen that had the pointer: the model
    /// answers by calling that pipeline's `cancel(at:reason: .takenOver)`.
    ///
    /// `fingersAlreadyDown`: the touchscreen has fingers on the glass already, from a touch that
    /// began before it was driving (while it was held, say). They are drawn hollow and not acted on
    /// until a frame arrives with none, so half a touch never starts.
    ///
    /// `constants`: the engine's thresholds, the standard ones but in a test.
    public init(id: TouchscreenID, driving: Driving, outputs: PipelineOutputs,
                cancelOther: @escaping @MainActor (TouchscreenID, TimeInterval) -> Void,
                fingersAlreadyDown: Bool = false, constants: GestureConstants = .standard) {
        self.id = id
        self.driving = driving
        self.outputs = outputs
        self.cancelOther = cancelOther
        self.constants = constants
        filter = ContactFilter(fingerLimit: driving.options.fingerLimit, rules: driving.rejection)
        waitingForClear = fingersAlreadyDown
    }

    /// Settings or the display changed while driving. A touch in flight carries on: if where touches
    /// land has changed, the caller cancels first (the model starts a fresh pipeline then).
    ///
    /// Each setting applies from the next frame, except the gestures: the options and the filter's
    /// finger limit change together, and only once the glass is clear, so a change applies to
    /// fingers that land afterwards and never turns a touch in progress into another gesture. Until
    /// then the touch goes on as it began. One-finger mode is read when a finger starts moving, the
    /// pointer's return when a session begins, the rejection rules from the next frame (a palm rule
    /// switched on can refuse a palm already down), and circles switched off go at once.
    public func update(_ driving: Driving) {
        guard !hasStopped else { return }
        let previous = self.driving
        self.driving = driving
        filter.rules = driving.rejection
        if fingersOnGlass {
            optionsWaitForClearGlass = previous.options != driving.options || optionsWaitForClearGlass
        } else {
            applyOptions()
        }
        if let shown = circlesShownOn, !driving.showsCircles || shown != driving.displayID {
            outputs.hideCircles(onDisplay: shown)
            circlesShownOn = nil
        }
        if previous.options != driving.options {
            let when = optionsWaitForClearGlass ? " from the next touch" : ""
            ModelLog.model.info("\(self.id.rawValue, privacy: .public): gestures now \(Self.describe(driving.options), privacy: .public)\(when, privacy: .public)")
        }
    }

    /// The options in `driving` reach the engine and the filter's finger limit, together.
    private func applyOptions() {
        optionsWaitForClearGlass = false
        filter.fingerLimit = driving.options.fingerLimit
        engine.options = driving.options
    }

    public func handle(_ frame: ContactFrame) {
        guard !hasStopped else { return }
        fingersOnGlass = !frame.contacts.isEmpty
        // Options that waited for the glass to clear apply once this frame, the lift, is done.
        defer { if optionsWaitForClearGlass, !fingersOnGlass, !hasStopped { applyOptions() } }
        lastFrameTime = frame.time
        let contactIDs = Set(frame.contacts.map(\.id))
        lastContactIDs = contactIDs
        if let silenced {
            self.silenced = nil
            let madeDuringAStall = frame.time <= silenced.at
            let sameFingerResumed = frame.time - silenced.at <= Self.silenceLimit
                && !contactIDs.isDisjoint(with: silenced.contacts)
            if !contactIDs.isEmpty, madeDuringAStall || sameFingerResumed { waitingForClear = true }
        }
        let mapping = driving.mapping
        let surface = driving.surfaceSizeMM
        var seen = Set<Int>()
        let fingers = frame.contacts.filter { seen.insert($0.id).inserted }.map { contact in
            Finger(id: contact.id, location: mapping.displayPoint(forGlass: contact.position),
                   size: Self.millimetres(contact.size, orientation: mapping.orientation, surface: surface),
                   isConfident: contact.isConfident)
        }

        if waitingForClear {
            if fingers.isEmpty { waitingForClear = false }
            if observer != nil { observeFrame(fingers, refusedBy: nil, rest: .alreadyDown, surface: surface, at: frame.time) }
            drawCircles(fingers, hollow: Set(fingers.map(\.id)))
            return
        }

        let live = filter.live(fingers, at: frame.time, surfaceSize: surface)
        if filter.mustCancel { cutShort(at: frame.time, fingersStillCounting: !live.isEmpty) }
        if ignoringUntilNoneCounts {
            if observer != nil {
                observeFrame(fingers, refusedBy: filter, rest: .restOfATouchCutShort, surface: surface, at: frame.time)
            }
            if live.isEmpty {
                // The engine, cancelled with fingers down, ignores them until a frame with none.
                ignoringUntilNoneCounts = false
                carryOut(process(TouchFrame(time: frame.time, fingers: [], surfaceSize: surface)), at: frame.time)
            }
            drawCircles(fingers, hollow: Set(fingers.map(\.id)))
            return
        }

        // While its followed swipe's end is repeated, the pointer is still this touchscreen's.
        let holding = outputs.arbiter.owner == id && holdsPointerForSwipe(at: frame.time)
        fingersDownForTheHoldOnly = holding && live.isEmpty
        switch outputs.arbiter.verdict(for: id, fingersDown: !live.isEmpty || holding) {
        case .ignore:
            if observer != nil {
                observeFrame(fingers, refusedBy: filter, rest: .otherTouchscreenHasThePointer, surface: surface, at: frame.time)
            }
            drawCircles(fingers, hollow: Set(fingers.map(\.id)))
            return
        case .processAfterCancelling(let other):
            ModelLog.model.info("\(self.id.rawValue, privacy: .public) takes the pointer over from \(other.rawValue, privacy: .public)")
            cancelOther(other, frame.time)
        case .process:
            break
        }
        if observer != nil { observeFrame(fingers, refusedBy: filter, rest: nil, surface: surface, at: frame.time) }
        carryOut(process(TouchFrame(time: frame.time, fingers: live, surfaceSize: surface)), at: frame.time)
        drawCircles(fingers, hollow: filter.refused)
    }

    /// Gives the engine `frame`, recording it first when frames are recorded.
    private func process(_ frame: TouchFrame) -> [GestureAction] {
        recorder?.append(frame)
        return engine.process(frame)
    }

    /// The filter refused a contact that had counted: the session is cancelled before the engine
    /// sees the frame, so the vanished contact is not read as a lift. Nothing happens when the
    /// engine had no session (its fingers were ignored by the arbiter).
    private func cutShort(at time: TimeInterval, fingersStillCounting: Bool) {
        closeOwnSwipe(at: time)
        let heldPointer = outputs.arbiter.owner == id
        let actions = engine.cancel(at: time)
        guard actions.contains(.sessionCancelled) else { return }
        ModelLog.model.info("\(self.id.rawValue, privacy: .public): session cancelled, a contact was refused (palm or hand)")
        observer?.pipeline(self, saw: .cutShort(.palm), at: time)
        carryOut(actions, at: time)
        if heldPointer { outputs.keeper.sessionCancelled() }
        ignoringUntilNoneCounts = fingersStillCounting
    }

    /// A contact's size as a share of the glass (`share`), in millimetres on it: the glass's axes
    /// are the display's turned by the orientation. Nil, as for a panel that reports no size, unless
    /// both sides are strictly between 0 and 1: the reader today passes a panel's size fields in
    /// their own whole units, which are never a share of the glass, and treating one as a share
    /// would make every finger a palm. So the too-wide rule acts only once the reader gives shares.
    static func millimetres(_ share: CGSize?, orientation: Orientation, surface: CGSize) -> CGSize? {
        guard let share, share.width > 0, share.width < 1, share.height > 0, share.height < 1 else { return nil }
        let glass = orientation.quarterTurns % 2 == 0 ? surface : CGSize(width: surface.height, height: surface.width)
        return CGSize(width: share.width * glass.width, height: share.height * glass.height)
    }

    public func tick(at time: TimeInterval) {
        guard !hasStopped else { return }
        if fingersOnGlass, time - lastFrameTime > Self.silenceLimit {
            ModelLog.model.error("\(self.id.rawValue, privacy: .public): nothing for \(time - self.lastFrameTime, privacy: .public) s with fingers down; the lift was lost, the touch is cancelled")
            cancelInFlight(at: time, because: .silence)
            engine = makeEngine()
            filter = makeFilter()
            optionsWaitForClearGlass = false
            fingersOnGlass = false
            waitingForClear = false
            ignoringUntilNoneCounts = false
            silenced = (time, lastContactIDs)
            observer?.pipeline(self, saw: .frame(onGlass: [], ignored: [:]), at: time)
            return
        }
        if let due = sessionEndDue, time >= due {
            sessionEndDue = nil
            endSession()
        }
        // The hold is over: no later frame will tell the arbiter the fingers are up, so this does,
        // and the other touchscreen can take the pointer as it could without a followed swipe.
        if fingersDownForTheHoldOnly, !holdsPointerForSwipe(at: time) {
            fingersDownForTheHoldOnly = false
            if outputs.arbiter.owner == id { _ = outputs.arbiter.verdict(for: id, fingersDown: false) }
        }
        let ringed = isRinged
        carryOut(engine.tick(at: time), at: time)
        // `longPressReady` comes from a tick when the finger rests and the panel is quiet.
        if isRinged != ringed, let last = lastCircles { drawCircles(last.fingers, hollow: last.hollow) }
    }

    /// Whether it is waiting on time, for its engine or for the next frame while fingers are down:
    /// call `tick(at:)` about 60 times a second while it is.
    public var needsTicks: Bool {
        !hasStopped && (engine.needsTicks || fingersOnGlass || sessionEndDue != nil)
    }

    /// Stops now and closes whatever is in flight.
    ///
    /// - `.stoppedDriving`: whether this touchscreen holds the pointer is noted first; the engine's
    ///   cancel is carried out with the mapping it had; if it held the pointer, the keeper is told
    ///   the session was cancelled (the arrow comes back, the pointer is not sent home); the arbiter
    ///   forgets it; its circles go. The pipeline is never used again.
    /// - `.takenOver`: the engine's cancel is carried out, and nothing else. The keeper gets
    ///   nothing: the new touchscreen's session is the hand-over. The pipeline lives on, with the
    ///   same engine and filter, for its touchscreen's next touch.
    public func cancel(at time: TimeInterval, reason: CancelReason) {
        guard !hasStopped else { return }
        switch reason {
        case .takenOver:
            closeOwnSwipe(at: time)
            sessionEndDue = nil
            fingersDownForTheHoldOnly = false
            let actions = engine.cancel(at: time)
            if actions.contains(.sessionCancelled) {
                ModelLog.model.info("\(self.id.rawValue, privacy: .public): session cancelled, taken over")
                observer?.pipeline(self, saw: .cutShort(.takenOver), at: time)
            }
            carryOut(actions, at: time)
        case .stoppedDriving:
            ModelLog.model.info("\(self.id.rawValue, privacy: .public): stopped driving")
            cancelInFlight(at: time)
            hasStopped = true
            // Its frames go nowhere from now on (a touchscreen held while the displays reconfigure,
            // say), so the lift may never be seen here: the tester is told the glass is clear, as
            // the silence rule tells it.
            observer?.pipeline(self, saw: .frame(onGlass: [], ignored: [:]), at: time)
        }
    }

    // MARK: - Private

    /// A filter with this touchscreen's finger limit and rejection rules.
    private func makeFilter() -> ContactFilter {
        ContactFilter(fingerLimit: driving.options.fingerLimit, rules: driving.rejection)
    }

    private func makeEngine() -> GestureEngine {
        GestureEngine(constants: constants, options: driving.options) { [weak self] location in
            self?.intent(atDisplayPoint: location) ?? .drag
        }
    }

    /// Whether this touchscreen holds the pointer is noted first; the engine's cancel is carried
    /// out with the mapping it had; if it held the pointer, the keeper is told the session was
    /// cancelled; the arbiter forgets it; its circles go. `reason` is for the gesture tester.
    private func cancelInFlight(at time: TimeInterval, because reason: CutShortBecause = .stopped) {
        closeOwnSwipe(at: time)
        sessionEndDue = nil
        fingersDownForTheHoldOnly = false
        let heldPointer = outputs.arbiter.owner == id
        let actions = engine.cancel(at: time)
        if actions.contains(.sessionCancelled) {
            ModelLog.model.info("\(self.id.rawValue, privacy: .public): session cancelled")
            observer?.pipeline(self, saw: .cutShort(reason), at: time)
        }
        carryOut(actions, at: time)
        if heldPointer { outputs.keeper.sessionCancelled() }
        outputs.arbiter.removed(id)
        if let shown = circlesShownOn {
            outputs.hideCircles(onDisplay: shown)
            circlesShownOn = nil
        }
    }

    /// Carries out the engine's actions, which it gave at `time`.
    private func carryOut(_ actions: [GestureAction], at time: TimeInterval) {
        let mapping = driving.mapping
        let sender = outputs.sender
        func desktop(_ point: CGPoint) -> CGPoint { mapping.desktopPoint(forDisplay: point) }
        for action in actions {
            // The ring comes down on the engine's next action, whatever it is.
            if isRinged { isRinged = false }
            // A swipe the gesture tester holds: nothing is posted for it.
            var held = false
            switch action {
            case .sessionBegan:
                ModelLog.model.info("\(self.id.rawValue, privacy: .public): session began")
                // A session held back for a swipe's repeated end: this one carries on from it.
                sessionEndDue = nil
                engine.followedSwipeAxes = driving.swipesFollowFingers && outputs.dockSwipes.isAvailable(.horizontal)
                    ? [.horizontal] : []
                outputs.keeper.sessionBegan(touchscreenFrame: driving.displayFrame, returnMode: driving.pointerReturn)
            case .movePointer(let point):
                pointerMovedTo = desktop(point)
                sender.movePointer(to: desktop(point))
            case .click(let point, let count):
                sender.click(at: desktop(point), count: count)
            case .press(let point, let count):
                sender.press(at: desktop(point), count: count)
            case .drag(let point):
                sender.drag(to: desktop(point))
            case .release(let point):
                sender.release(at: desktop(point))
            case .rightClick(let point):
                sender.rightClick(at: desktop(point))
            case .longPressReady:
                isRinged = true
            case .longPressWithdrawn:
                break  // the ring is down
            case .scroll(let distance, let phase):
                if phase == .began {
                    sender.scroll(by: points(distance), phase: phase, match: matchForScrollBeginning())
                } else {
                    sender.scroll(by: points(distance), phase: phase)
                }
            case .momentum(let distance, let phase):
                sender.momentum(by: points(distance), phase: phase)
            case .pinch(let magnification, let phase):
                sender.pinch(by: magnification, phase: phase)
            case .rotate(let degrees, let phase):
                sender.rotate(by: degrees, phase: phase)
            case .swipe(let direction):
                held = observer?.holdsSwipes == true
                if !held { sender.swipe(direction) }
            case .sessionEnded:
                if let due = swipeEndedAt.map({ $0 + DockSwipeSender.endRepeatDelay }), time < due {
                    ModelLog.model.info("\(self.id.rawValue, privacy: .public): session ended; the pointer stays until the swipe's end has been repeated")
                    sessionEndDue = due
                } else {
                    endSession()
                }
            case .sessionCancelled:
                outputs.arbiter.sessionEnded(for: id)
            case .swipeTracking(let axis, let offset, let phase):
                held = followSwipe(axis: axis, offset: offset, phase: phase, at: time)
            }
            observer?.pipeline(self, saw: .action(action, held: held), at: time)
        }
    }

    /// The session ended normally: the keeper may send the pointer home, and the pointer is free.
    private func endSession() {
        ModelLog.model.info("\(self.id.rawValue, privacy: .public): session ended")
        outputs.keeper.sessionEnded()
        outputs.arbiter.sessionEnded(for: id)
    }

    // MARK: - Followed swipes

    /// One `swipeTracking` action, to the shared sender. A `completed` it couldn't post is today's
    /// shortcut, and so is one for a swipe closed from outside (the model, on a display change that
    /// didn't move these touches): the Dock has slid back, so the shortcut is the one move. The
    /// person loses the following, never the swipe. A `cancelled` is nothing either way.
    ///
    /// A swipe that begins while the gesture tester holds swipes is held to its end: nothing reaches
    /// the sender, and no shortcut is posted. Returns whether this one was held.
    private func followSwipe(axis: SwipeAxis, offset: Double, phase: SwipeTrackingPhase, at time: TimeInterval) -> Bool {
        if case .began = phase { swipeIsHeld = observer?.holdsSwipes == true }
        if swipeIsHeld {
            switch phase {
            case .began, .changed: break
            case .completed, .cancelled: swipeIsHeld = false
            }
            return true
        }
        let closedFromOutside = ownsOpenSwipe && !outputs.dockSwipes.isOpen
        let handled = outputs.dockSwipes.handle(axis: axis, offset: offset, phase: phase, displayID: driving.displayID,
                                                displayWidth: Double(driving.displayFrame.width))
        switch phase {
        case .began:
            ownsOpenSwipe = handled
            ModelLog.model.info("\(self.id.rawValue, privacy: .public): swipe \(handled ? "followed" : "not followed: the shortcut at the lift", privacy: .public)")
        case .changed:
            break
        case .completed:
            endOwnSwipe(at: time)
            if !handled || closedFromOutside {
                let direction: SwipeDirection = axis == .horizontal ? (offset < 0 ? .left : .right) : (offset < 0 ? .up : .down)
                outputs.sender.swipe(direction)
            }
        case .cancelled:
            endOwnSwipe(at: time)
        }
        return false
    }

    /// This touchscreen's swipe has had its end.
    private func endOwnSwipe(at time: TimeInterval) {
        guard ownsOpenSwipe else { return }
        ownsOpenSwipe = false
        swipeEndedAt = time
    }

    /// Closes this touchscreen's open swipe, if it has one, before anything else a stop does. The
    /// engine's later end for it is then handled by the sender with nothing.
    private func closeOwnSwipe(at time: TimeInterval) {
        guard ownsOpenSwipe else { return }
        ModelLog.model.info("\(self.id.rawValue, privacy: .public): its open swipe closed")
        outputs.dockSwipes.closeIfOpen()
        endOwnSwipe(at: time)
    }

    /// Whether the pointer is still this touchscreen's for its followed swipe: open, or ended less
    /// than `DockSwipeSender.endRepeatDelay` ago.
    private func holdsPointerForSwipe(at time: TimeInterval) -> Bool {
        ownsOpenSwipe || (swipeEndedAt.map { time < $0 + DockSwipeSender.endRepeatDelay } ?? false)
    }

    /// A distance in fractions of the display, in points of the picture's frame.
    private func points(_ distance: CGVector) -> CGVector {
        CGVector(dx: distance.dx * driving.displayFrame.width, dy: distance.dy * driving.displayFrame.height)
    }

    /// How a scroll beginning now is posted, decided once, from the app whose window is under the
    /// pointer: matched to VS Code's scrolling in the editors on Monaco, as moved elsewhere and over
    /// no app's window. The sender keeps it for the scroll and its momentum.
    private func matchForScrollBeginning() -> ScrollMatch {
        guard let point = pointerMovedTo else { return .asMoved }
        let app = outputs.app(atDesktopPoint: point)?.bundleIdentifier
        let match = ScrollMatch.forApp(app)
        if let line = match.logLine(forApp: app) { ModelLog.model.debug("\(line, privacy: .public)") }
        return match
    }

    /// Drag or scroll for a finger that starts moving from `location`, a display point. Automatic
    /// asks the app whose window is under it, and drags over no app's window.
    private func intent(atDisplayPoint location: CGPoint) -> OneFingerIntent {
        switch driving.oneFinger {
        case .alwaysDrag: return .drag
        case .alwaysScroll: return .scroll
        case .automatic:
            let point = driving.mapping.desktopPoint(forDisplay: location)
            guard let app = outputs.app(atDesktopPoint: point) else { return .drag }
            return outputs.intent(atDesktopPoint: point, inApp: app.pid)
        }
    }

    /// Shows `fingers`, those in `hollow` hollow and, while the ring is up, the others ringed, when
    /// circles are on. A frame with no fingers fades out what is showing, once.
    private func drawCircles(_ fingers: [Finger], hollow: Set<Int>) {
        lastCircles = fingers.isEmpty ? nil : (fingers, hollow)
        guard driving.showsCircles else { return }
        let displayID = driving.displayID
        if fingers.isEmpty {
            guard let shown = circlesShownOn else { return }
            outputs.showCircles([:], hollow: [], ringed: [], onDisplay: shown)
            circlesShownOn = nil
            return
        }
        if let shown = circlesShownOn, shown != displayID { outputs.hideCircles(onDisplay: shown) }
        let points = Dictionary(fingers.map { ($0.id, $0.location) }, uniquingKeysWith: { first, _ in first })
        let solid = Set(points.keys).subtracting(hollow)
        outputs.showCircles(points, hollow: hollow.intersection(points.keys), ringed: isRinged ? solid : [],
                            onDisplay: displayID)
        circlesShownOn = displayID
    }

    private static func describe(_ options: GestureOptions) -> String {
        let on = [("scroll", options.twoFingerScroll), ("pinch", options.pinch), ("two-finger tap", options.twoFingerTap),
                  ("swipes", options.swipes), ("rotate", options.rotate)].filter(\.1).map(\.0)
        return (on.isEmpty ? "one finger only" : on.joined(separator: ", "))
            + (options.longPress ? "; long-press" : "; no long-press")
    }
}
