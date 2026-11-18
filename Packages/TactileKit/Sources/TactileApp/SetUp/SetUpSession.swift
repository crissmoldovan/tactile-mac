// Set-up mode: every touchscreen in a single pass. Which display comes from a click on its card,
// which touchscreen from a touch; then that pair's flow. A pure state machine, fed every
// touchscreen's frames, the person's commands, what is connected, and the time.

import CoreGraphics
import Foundation
import TactileReading
import TactileScreens

/// Set-up mode, from its beginning to its end.
///
/// It has no window, no device and no clock of its own. The model builds one when the mode begins
/// and holds it; feeds it the frames of every connected touchscreen (each with its ID), ticks it,
/// passes on the person's commands, and gives it a new `Scene` whenever what is connected (or what
/// is stored about it) changes. It answers each with the `Event`s the model applies, in order, and
/// its `snapshot` is what the overview draws. Every time is on the host's uptime clock, the clock
/// frames are timed on. It holds at most one `SetUpFlow` (corners, size and check for one
/// touchscreen on one display) and never stores anything itself: a flow's outcome reaches the model
/// only in `flowFinished`, from the flow's Done, and the model stores it then. Leaving the mode by
/// any route stores nothing more.
///
/// **No timer decides.** Which display comes only from a click on its card (`choose`); which
/// touchscreen only from a touch (an *answer*). Either may come first:
///
/// | Stage | Input | Then |
/// |---|---|---|
/// | `choosing` | an answer from T that can be set up | `touchedFirst(T)` |
/// | `choosing` | an answer from one that can't | stay; `notice = .cannotBeSetUp` |
/// | `choosing` | `choose(D)` | `waitingForTouch(D)` |
/// | `waitingForTouch(D)` | an answer from T that can be set up | a `.full` flow for T on D: `running` |
/// | `waitingForTouch(D)` | `choose(E)` | `waitingForTouch(E)` |
/// | `waitingForTouch`, `touchedFirst` | `back` | `choosing` |
/// | `touchedFirst(T)` | `choose(D)` | a `.full` flow for T on D: `running` |
/// | `touchedFirst(T)` | an answer from another touchscreen U | `touchedFirst(U)` |
/// | not `running` | `begin(.test or .calibrate, T)` (a card's **Test**) | that flow for T: `running` |
/// | `running` | the flow's Done, with an outcome | `flowFinished` with it; `choosing`, `justSetUp = T` |
/// | `running` | the flow finishes with nil (`back`, its idle timeout, its display gone, T gone) | `choosing`, the matching notice |
/// | any | `finish` (Finish, Esc) | the mode ends; a running flow stores nothing |
/// | any | `idleTimeout` without input | the mode ends, as `finish` would |
/// | any | `interrupt` (lock, sleep, Tactile off, Accessibility lost, quit) | the mode ends, as an interruption |
///
/// An answer from a touchscreen that can't be set up only sets the notice, in any stage that takes
/// answers. In `waitingForTouch` and `touchedFirst` too: the stage stays.
///
/// **An answer** is what the old pair step called one. A *landing* is a frame with a contact after a
/// frame with none, on any touchscreen. Whether it answers is decided when it lifts: it never had
/// more than `mostFingersToAnswer` contacts, and the panel never marked one of them not confident. A
/// hand whose contacts arrive over several frames, or a palm the panel recognises late, answers
/// nothing. A landing is no answer, and is ignored with every finger of it until that touchscreen's
/// glass clears, when it comes:
/// - while a flow runs (its own touchscreen's frames are the flow's), or while the displays
///   reconfigure (`Scene.isReconfiguring`);
/// - within `SetUpFlow.reactionTime` after the stage last changed, timed before the change, or not
///   timed at all: a person can't react sooner, and a frame that arrives late is never taken for
///   what was shown after it;
/// - in the first `SetUpFlow.startQuiet` after the mode begins, so that a finger already resting on
///   a glass is not a touch, even on a panel that says nothing while a finger rests.
///
/// Fingers already down when the stage changes are no answer either: every touch in progress is
/// then ignored until its glass clears. So with two touchscreens touched at once, the first answer
/// to lift wins, and the other's touch is ignored with all its fingers. If the model knows fingers
/// are down when the mode begins, it should hand the session their latest frame straight away:
/// timed before the start, it is ignored as a landing, and so are those fingers until they lift.
/// When a flow starts for a touchscreen whose fingers are down, the session hands the flow their
/// latest frame the same way.
///
/// **Can be set up** is the scene's to say, for each touchscreen (`Scene.Touchscreen.canBeSetUp`):
/// the rule the resolver uses, which never asks whether a display is free. The person chooses the
/// display, and taking one from another touchscreen is allowed: the model's Done unpairs the other
/// one in the same write.
///
/// **What is connected.** The candidate displays are the scene's cards, in screen order. A chosen
/// display that goes away (no card with its ID, or another display under its ID) returns
/// `waitingForTouch` to `choosing` with `.displayGone`; a running flow hears the displays through
/// `SetUpFlow.displaysChanged`, and finishing with nil there is `.displayGone` too. The touchscreen
/// that answered first, or whose flow runs, going away returns to `choosing` with
/// `.touchscreenGone`; one that is still connected but can no longer be set up, with
/// `.cannotBeSetUp`. While the displays reconfigure the cards stay as last known, the stage stays,
/// no display is taken for gone, and no answer is taken: not from a touch that lands then, nor from
/// one already down when they start reconfiguring, which answers nothing until its glass clears.
///
/// **Input** is only what can move the mode on: a landing on a touchscreen that can be set up,
/// whatever comes of it, and its answer; every command; and, while a flow runs, whatever is input
/// to the flow (`SetUpFlow.lastInputAt`). A touchscreen that can't be set up, or that the scene
/// doesn't have, gives none, however often it lands. After `SetUpFlow.idleTimeout` without input,
/// in any stage, the mode ends by itself, as `finish` would. So a forgotten mode doesn't keep every
/// touchscreen out of use, as long as it is ticked (about ten times a second), nor does a noisy
/// panel keep it on.
///
/// **Hostile input.** Times are taken as they come, but the session's clock never goes back: a
/// frame, tick or command earlier than the latest is not a later moment, and a change it makes is
/// timed at the latest moment. A frame for a touchscreen the scene doesn't have is tracked, and
/// answers nothing. Once the mode has ended, every call returns no event and changes nothing.
/// Nothing traps.
///
/// A value, cheap to copy: the model holds it.
public struct SetUpSession: Equatable, Sendable {

    /// What the session knows of what is connected. The model builds it (`Resolver.setUpScene`) and
    /// gives it again whenever it changes.
    public struct Scene: Equatable, Sendable {
        /// Every connected display: what a flow maps onto. Empty while the displays reconfigure.
        public var displays: [DisplayFacts]
        /// The candidate displays, in screen order, each with its card: every connected display a
        /// `.full` flow could start on (`SetUpFlow.canStartFull`), never the built-in one. While the
        /// displays reconfigure, as last known.
        public var cards: [SetUpDisplayCard]
        /// Every connected touchscreen, in the order they connected.
        public var touchscreens: [Touchscreen]
        /// macOS publishes no displays for a moment while they reconfigure.
        public var isReconfiguring: Bool

        public init(displays: [DisplayFacts], cards: [SetUpDisplayCard], touchscreens: [Touchscreen],
                    isReconfiguring: Bool) {
            self.displays = displays
            self.cards = cards
            self.touchscreens = touchscreens
            self.isReconfiguring = isReconfiguring
        }
    }

    /// One connected touchscreen, as the session needs it: its line on the session card, and what
    /// a flow for it starts from.
    public struct Touchscreen: Equatable, Sendable {
        public var line: SetUpTouchscreenLine
        /// The size of its glass as it reports it, in millimetres, in the glass's own axes.
        public var reportedSizeMM: CGSize?
        /// Its pairing now; nil when it is not set up.
        public var pairing: Pairing?
        /// Its diagonal override now, when the engine would use it; nil for as reported.
        public var diagonalInches: Double?
        /// The connected display its pairing means now, found for certain: where `.calibrate` and
        /// `.test` run.
        public var ownDisplay: UInt32?

        public init(line: SetUpTouchscreenLine, reportedSizeMM: CGSize?, pairing: Pairing?, diagonalInches: Double?,
                    ownDisplay: UInt32?) {
            self.line = line
            self.reportedSizeMM = reportedSizeMM
            self.pairing = pairing
            self.diagonalInches = diagonalInches
            self.ownDisplay = ownDisplay
        }

        public var id: TouchscreenID { line.id }
        public var name: String { line.name }
        /// Whether a touch from it answers: its line doesn't say it can't be set up.
        public var canBeSetUp: Bool { line.state != .cannotBeSetUp }
    }

    /// Why the overview is back: one line in the log.
    public enum Why: Equatable, Sendable {
        /// The person's **Back**.
        case back
        /// A flow's Done was stored: this touchscreen on this display.
        case done(name: String, displayName: String)
        /// A test's Done: nothing to store.
        case tested(name: String)
        /// The flow's own time limit.
        case flowTimedOut
        case displayGone(name: String)
        case touchscreenGone(name: String)
        case cannotBeSetUp(name: String)

        public var text: String {
            switch self {
            case .back: return "Back"
            case .done(let name, let displayName): return "done: \(name) on \(displayName)"
            case .tested(let name): return "tested: \(name)"
            case .flowTimedOut: return "the set-up's time limit"
            case .displayGone(let name): return "display gone: \(name)"
            case .touchscreenGone(let name): return "touchscreen gone: \(name)"
            case .cannotBeSetUp(let name): return "\(name) can't be set up now"
            }
        }

        /// What the overview says about it until the stage next changes.
        fileprivate func notice(for touchscreen: TouchscreenID?) -> SetUpModeNotice? {
            switch self {
            case .displayGone(let name): return .displayGone(name: name)
            case .touchscreenGone(let name): return .touchscreenGone(name: name)
            case .cannotBeSetUp(let name): return touchscreen.map { .cannotBeSetUp(touchscreen: $0, name: name) }
            case .back, .done, .tested, .flowTimedOut: return nil
            }
        }
    }

    /// How the mode ended.
    public enum Ending: Equatable, Sendable {
        /// **Finish** or Esc: `cancelSetUp`, which can't tell them apart.
        case finished
        /// `SetUpFlow.idleTimeout` without input.
        case timedOut
        /// A lock, sleep, Tactile off, Accessibility lost or quitting, said in words.
        case interrupted(String)

        public var text: String {
            switch self {
            case .finished: return "Finish or Esc"
            case .timedOut: return "timeout"
            case .interrupted(let why): return "interruption: \(why)"
            }
        }

        /// Whether leaving this way counts as the first-run offer made: the person's own endings do,
        /// an interruption doesn't.
        public var marksOffered: Bool {
            if case .interrupted = self { return false }
            return true
        }
    }

    /// What the model applies, in order.
    public enum Event: Equatable, Sendable {
        /// The display chosen by a click on its card.
        case chose(display: UInt32, name: String)
        /// The touch that answered while a display was chosen: its flow starts there.
        case answered(touchscreen: TouchscreenID, name: String, displayName: String)
        /// The touch that answered while no display was chosen: waiting for a click.
        case touchedFirst(touchscreen: TouchscreenID, name: String)
        /// A touch from a touchscreen that can't be set up, ignored.
        case cannotBeSetUp(touchscreen: TouchscreenID, name: String)
        /// A flow started, from `start`: `flow` has it now.
        case flowStarted(SetUpFlow.Start)
        /// The running flow finished. An outcome, from its Done, is for the model to store, as
        /// `Resolver.applySetUp` stores one; nil stores nothing.
        case flowFinished(touchscreen: TouchscreenID, name: String, purpose: SetUpPurpose, outcome: SetUpFlow.Outcome?)
        /// Back to the overview (`choosing`), and why.
        case backToTheScreens(Why)
        /// The mode ended. `markOffered`: the touchscreens to mark as offered set-up, as Not Now
        /// marks one: every one the session card showed as not set up at any moment of the mode (it
        /// had the offer), in the order they first showed so; none after an interruption. `setUp`:
        /// the names of those Done in this session, in order.
        case ended(Ending, markOffered: [TouchscreenID], setUp: [String])

        /// The model's log line for it; nil for those the model writes its own lines for (a flow
        /// starting and finishing).
        public var logLine: String? {
            switch self {
            case .chose(let display, let name):
                return "Set-up mode: chose display \(display) \"\(name)\""
            case .answered(let id, let name, let displayName):
                return "Set-up mode: \(name) [\(id.rawValue)] answered on \(displayName)"
            case .touchedFirst(let id, let name):
                return "Set-up mode: \(name) [\(id.rawValue)] touched first; waiting for a display"
            case .cannotBeSetUp(let id, let name):
                return "Set-up mode: \(name) [\(id.rawValue)] can't be set up; touch ignored"
            case .flowStarted, .flowFinished:
                return nil
            case .backToTheScreens(let why):
                return "Set-up mode: back to the screens (\(why.text))"
            case .ended(let ending, _, let names):
                return "Set-up mode ended (\(ending.text)); set up in this session: "
                    + (names.isEmpty ? "none" : names.joined(separator: ", "))
            }
        }
    }

    // MARK: - Constants

    /// The most contacts a landing may have and be an answer: more is a hand.
    public static let mostFingersToAnswer = 2

    // MARK: - State

    private enum Stage: Equatable, Sendable {
        case choosing
        /// The display as it was when chosen, and its card's name.
        case waitingForTouch(DisplayFacts, name: String)
        /// The touchscreen whose touch answered, and its name then.
        case touchedFirst(TouchscreenID, name: String)
        case running(Running)
    }

    private struct Running: Equatable, Sendable {
        var flow: SetUpFlow
        let touchscreen: TouchscreenID
        let name: String
        let purpose: SetUpPurpose
        /// The display it runs on, by its card's name: for the log and the notice when it goes.
        let displayName: String
    }

    private enum Glass: Equatable, Sendable {
        /// Fingers down that answer nothing; waiting for the glass to clear.
        case ignored
        /// A touch that may answer, decided when it lifts.
        case answering(Answer)
    }

    /// A touch that may answer, from its landing.
    private struct Answer: Equatable, Sendable {
        /// The most contacts any of its frames had.
        var mostContacts = 0
        /// Whether the panel marked any of its contacts not confident, in any frame.
        var sawPalm = false

        init(_ contacts: [Contact]) {
            see(contacts)
        }

        mutating func see(_ contacts: [Contact]) {
            mostContacts = max(mostContacts, contacts.count)
            sawPalm = sawPalm || contacts.contains { $0.isConfident == false }
        }

        /// A finger or two, never a hand or a palm.
        var answers: Bool { mostContacts <= SetUpSession.mostFingersToAnswer && !sawPalm }
    }

    private var scene: Scene
    /// The displays as last published, kept while they reconfigure: what a chosen display is
    /// found among.
    private var knownDisplays: [DisplayFacts]
    /// The displays the running flow was last told of.
    private var flowDisplays: [DisplayFacts] = []
    private var stage: Stage = .choosing
    /// What is on each touchscreen's glass, as far as the session is concerned; absent: clear.
    private var glass: [TouchscreenID: Glass] = [:]
    /// Each touchscreen's latest frame while fingers are on its glass, for a flow that starts then.
    private var lastFrames: [TouchscreenID: ContactFrame] = [:]
    private var justSetUp: TouchscreenID?
    private var notice: SetUpModeNotice?
    /// When the mode began: a landing before `startedAt + startQuiet` is no answer.
    private let startedAt: TimeInterval
    /// The latest time the session has been given. It never goes back.
    private var now: TimeInterval
    /// When the stage last changed: a landing before `changedAt + reactionTime` is no answer.
    private var changedAt: TimeInterval
    /// When the session last had input: `idleTimeout` runs from it (or from the flow's, if later).
    private var lastInput: TimeInterval
    /// Every touchscreen the session card has shown as not set up, at any moment, in the order they
    /// first showed so.
    private var shownNotSetUp: [TouchscreenID] = []
    /// The names of the touchscreens Done in this session, in order.
    private var setUpNames: [String] = []
    /// How the mode ended, once it has.
    private var ending: Ending?

    // MARK: - Beginning

    /// Whether the mode could begin with `scene`: the displays settled, at least one candidate
    /// display, and at least one connected touchscreen that can be set up.
    public static func couldBegin(_ scene: Scene) -> Bool {
        !scene.isReconfiguring && !scene.displays.isEmpty && !scene.cards.isEmpty
            && scene.touchscreens.contains(where: \.canBeSetUp)
    }

    /// The mode at its beginning, `choosing`, at `time`; nil when it can't begin (`couldBegin`), or
    /// `time` isn't finite.
    public init?(_ scene: Scene, at time: TimeInterval) {
        guard time.isFinite, Self.couldBegin(scene) else { return nil }
        self.scene = scene
        knownDisplays = scene.displays
        startedAt = time
        now = time
        changedAt = time
        lastInput = time
        noteNotSetUp(scene)
    }

    /// The model's line for the beginning.
    public var beganLogLine: String {
        let names = scene.touchscreens.map(\.name).joined(separator: ", ")
        let candidates = scene.cards.map { "\($0.id) \"\($0.name)\"" }.joined(separator: ", ")
        return "Set-up mode began: \(scene.touchscreens.count) touchscreens (\(names)), candidates \(candidates)"
    }

    // MARK: - What the interface draws

    public var snapshot: SetUpModeSnapshot {
        let shown: SetUpModeSnapshot.Stage
        switch stage {
        case .choosing: shown = .choosing
        case .waitingForTouch(let display, _): shown = .waitingForTouch(display: display.displayID)
        case .touchedFirst(let id, let name):
            shown = .touchedFirst(touchscreen: id, name: entry(id)?.name ?? name)
        case .running: shown = .running
        }
        return SetUpModeSnapshot(
            stage: shown, displays: scene.cards, touchscreens: scene.touchscreens.map(\.line), justSetUp: justSetUp,
            notice: notice)
    }

    /// The flow running now; nil in every other stage, and once the mode has ended.
    public var flow: SetUpFlow? {
        guard ending == nil, case .running(let running) = stage else { return nil }
        return running.flow
    }

    /// Whether the mode has ended. The model drops it when it says so.
    public var hasEnded: Bool { ending != nil }

    // MARK: - What the model feeds it

    /// A frame of the touchscreen `touchscreen`. While a flow runs, its own touchscreen's frames go
    /// to the flow.
    public mutating func handle(_ frame: ContactFrame, from touchscreen: TouchscreenID) -> [Event] {
        guard ending == nil else { return [] }
        var events = advance(to: frame.time)
        guard ending == nil else { return events }
        if case .running(var running) = stage, running.touchscreen == touchscreen {
            let event = running.flow.handle(frame)
            stage = .running(running)
            events += track(frame, from: touchscreen)
            if case .finished(let outcome) = event {
                // A frame ends a flow only by its time limit.
                events += flowFinished(outcome, why: .flowTimedOut)
            }
            return events
        }
        return events + track(frame, from: touchscreen)
    }

    /// The time passing: about ten times a second, in every stage.
    public mutating func tick(at time: TimeInterval) -> [Event] {
        advance(to: time)
    }

    /// A card's **This one** (or **Set Up Again Here**). Nothing for a display that has no card, or
    /// while a flow runs.
    public mutating func choose(display id: UInt32, at time: TimeInterval) -> [Event] {
        guard let events = command(at: time) else { return [] }
        guard let card = scene.cards.first(where: { $0.id == id }),
              let display = knownDisplays.first(where: { $0.displayID == id })
        else { return events }
        switch stage {
        case .choosing, .waitingForTouch:
            if case .waitingForTouch(let chosen, _) = stage, chosen.displayID == id { return events }
            change(to: .waitingForTouch(display, name: card.name))
            return events + [.chose(display: id, name: card.name)]
        case .touchedFirst(let touchscreen, _):
            guard let started = start(.full, of: touchscreen, on: display, displayName: card.name) else { return events }
            return events + [.chose(display: id, name: card.name), .flowStarted(started)]
        case .running:
            return events
        }
    }

    /// **Back**: from a flow, back to the overview storing nothing; from `waitingForTouch` or
    /// `touchedFirst`, back to `choosing`. Nothing in `choosing`.
    public mutating func back(at time: TimeInterval) -> [Event] {
        guard let events = command(at: time) else { return [] }
        switch stage {
        case .choosing:
            return events
        case .waitingForTouch, .touchedFirst:
            change(to: .choosing)
            return events + [.backToTheScreens(.back)]
        case .running(var running):
            _ = running.flow.cancel()
            stage = .running(running)
            return events + flowFinished(nil, why: .back)
        }
    }

    /// A `.calibrate` or `.test` flow for `touchscreen` on its own display, from a card's **Test**
    /// (or a pane's Calibrate Corners…): only while no flow runs, for a touchscreen that can be set
    /// up and is paired with a connected display, and only when the flow can start there. Anything
    /// else, `.full` included, changes nothing.
    public mutating func begin(_ purpose: SetUpPurpose, of touchscreen: TouchscreenID, at time: TimeInterval) -> [Event] {
        guard let events = command(at: time) else { return [] }
        guard purpose != .full, !isRunning, let entry = entry(touchscreen), let own = entry.ownDisplay,
              let display = scene.displays.first(where: { $0.displayID == own })
        else { return events }
        let displayName = scene.cards.first { $0.id == own }?.name ?? display.name
        guard let started = start(purpose, of: touchscreen, on: display, displayName: displayName) else { return events }
        return events + [.flowStarted(started)]
    }

    /// The size step's answer, for the running flow.
    public mutating func confirmSize(inches: Double?, at time: TimeInterval) -> [Event] {
        step(at: time) { $0.confirmSize(inches: inches) }
    }

    /// The check step's Redo, for the running flow.
    public mutating func redo(at time: TimeInterval) -> [Event] {
        step(at: time) { $0.redo() }
    }

    /// The check step's Done, for the running flow: its outcome goes to the model in `flowFinished`.
    public mutating func done(at time: TimeInterval) -> [Event] {
        step(at: time) { $0.done() }
    }

    /// **Finish** or Esc: the mode ends. A running flow stores nothing.
    public mutating func finish(at time: TimeInterval) -> [Event] {
        guard ending == nil else { return [] }
        let events = advance(to: time)
        guard ending == nil else { return events }
        return events + end(.finished)
    }

    /// Something that releases every touchscreen happened (a lock, sleep, Tactile off, Accessibility
    /// lost, quitting), said in `why`: the mode ends, as an interruption. A running flow stores
    /// nothing.
    public mutating func interrupt(_ why: String) -> [Event] {
        guard ending == nil else { return [] }
        return end(.interrupted(why))
    }

    /// What is connected changed: see *What is connected*.
    public mutating func sceneChanged(_ new: Scene, at time: TimeInterval) -> [Event] {
        guard ending == nil else { return [] }
        var events = advance(to: time)
        guard ending == nil else { return events }
        let before = scene
        scene = new
        noteNotSetUp(new)
        if new.isReconfiguring {
            // A touch down as they start reconfiguring answers nothing, as one landing meanwhile.
            for (id, state) in glass where state != .ignored { glass[id] = .ignored }
        } else {
            knownDisplays = new.displays
        }
        let connected = Set(new.touchscreens.map(\.id))
        for id in Array(glass.keys) where !connected.contains(id) { glass[id] = nil }
        for id in Array(lastFrames.keys) where !connected.contains(id) { lastFrames[id] = nil }

        switch stage {
        case .choosing:
            break
        case .waitingForTouch(let display, let name):
            guard !new.isReconfiguring else { break }
            if new.cards.contains(where: { $0.id == display.displayID }),
               let present = new.displays.first(where: { $0.displayID == display.displayID }),
               DisplayIdentity(present) == DisplayIdentity(display) {
                stage = .waitingForTouch(present, name: new.cards.first { $0.id == display.displayID }?.name ?? name)
            } else {
                events += back(because: .displayGone(name: name), for: nil)
            }
        case .touchedFirst(let id, let name):
            if let entry = entry(id) {
                if !entry.canBeSetUp { events += back(because: .cannotBeSetUp(name: entry.name), for: id) }
            } else {
                events += back(because: .touchscreenGone(name: before.touchscreens.first { $0.id == id }?.name ?? name),
                               for: id)
            }
        case .running(var running):
            if let entry = entry(running.touchscreen) {
                if !entry.canBeSetUp {
                    _ = running.flow.cancel()
                    stage = .running(running)
                    events += flowFinished(nil, why: .cannotBeSetUp(name: entry.name))
                } else if !new.isReconfiguring, new.displays != flowDisplays {
                    flowDisplays = new.displays
                    let event = running.flow.displaysChanged(new.displays, at: now)
                    stage = .running(running)
                    if case .finished(let outcome) = event {
                        events += flowFinished(outcome, why: .displayGone(name: running.displayName))
                    }
                }
            } else {
                _ = running.flow.cancel()
                stage = .running(running)
                events += flowFinished(nil, why: .touchscreenGone(name: running.name))
            }
        }
        return events
    }

    // MARK: - Private: time and commands

    private var isRunning: Bool {
        if case .running = stage { return true }
        return false
    }

    /// Brings the clock to `time`, unless it is earlier than the latest or isn't a time; then the
    /// end, after `idleTimeout` without input; else the running flow ticked.
    private mutating func advance(to time: TimeInterval) -> [Event] {
        guard ending == nil, time.isFinite, time >= now else { return [] }
        now = time
        var latestInput = lastInput
        if case .running(let running) = stage { latestInput = max(latestInput, running.flow.lastInputAt) }
        if now - latestInput >= SetUpFlow.idleTimeout { return end(.timedOut) }
        guard case .running(var running) = stage else { return [] }
        let event = running.flow.tick(at: now)
        stage = .running(running)
        if case .finished(let outcome) = event { return flowFinished(outcome, why: .flowTimedOut) }
        return []
    }

    /// The person's command at `time`: the clock brought there, and the command counted as input.
    /// Nil once the mode has ended, by then or before; otherwise what bringing the clock there
    /// gave.
    private mutating func command(at time: TimeInterval) -> [Event]? {
        guard ending == nil else { return nil }
        let events = advance(to: time)
        guard ending == nil else { return nil }
        lastInput = now
        return events
    }

    /// A command for the running flow, given as the model gives one: the flow ticked at the
    /// command's moment, the command, and a tick at the same moment, which times a change it made.
    private mutating func step(at time: TimeInterval, _ action: (inout SetUpFlow) -> SetUpFlow.Event) -> [Event] {
        guard var events = command(at: time) else { return [] }
        guard case .running(var running) = stage else { return events }
        var event = running.flow.tick(at: now)
        if event == .stillRunning { event = action(&running.flow) }
        if event == .stillRunning { event = running.flow.tick(at: now) }
        stage = .running(running)
        guard case .finished(let outcome) = event else { return events }
        let why: Why
        if outcome != nil {
            why = .done(name: running.name, displayName: running.displayName)
        } else if running.purpose == .test {
            why = .tested(name: running.name)
        } else {
            why = .flowTimedOut
        }
        events += flowFinished(outcome, why: why)
        return events
    }

    private mutating func end(_ how: Ending) -> [Event] {
        ending = how
        return [.ended(how, markOffered: how.marksOffered ? shownNotSetUp : [], setUp: setUpNames)]
    }

    /// Notes the touchscreens `scene`'s lines show as not set up.
    private mutating func noteNotSetUp(_ scene: Scene) {
        for screen in scene.touchscreens where screen.line.state == .notSetUp && !shownNotSetUp.contains(screen.id) {
            shownNotSetUp.append(screen.id)
        }
    }

    // MARK: - Private: stages

    /// A change of stage, now: what the overview shows changed, so the notice goes, and every touch in
    /// progress answers nothing.
    private mutating func change(to new: Stage) {
        stage = new
        changedAt = now
        notice = nil
        for (id, state) in glass where state != .ignored { glass[id] = .ignored }
    }

    /// Back to `choosing` from `waitingForTouch` or `touchedFirst`, because of `why`.
    private mutating func back(because why: Why, for touchscreen: TouchscreenID?) -> [Event] {
        change(to: .choosing)
        notice = why.notice(for: touchscreen)
        return [.backToTheScreens(why)]
    }

    /// The running flow finished with `outcome`: back to `choosing`, saying why.
    private mutating func flowFinished(_ outcome: SetUpFlow.Outcome?, why: Why) -> [Event] {
        guard case .running(let running) = stage else { return [] }
        change(to: .choosing)
        flowDisplays = []
        if outcome != nil {
            justSetUp = running.touchscreen
            setUpNames.append(running.name)
        }
        notice = why.notice(for: running.touchscreen)
        return [
            .flowFinished(touchscreen: running.touchscreen, name: running.name, purpose: running.purpose, outcome: outcome),
            .backToTheScreens(why),
        ]
    }

    /// Starts a flow of `purpose` for `touchscreen` on `display` (as known, found again among the
    /// displays now): `running`, and what it started from; nil, and nothing changed, when it can't
    /// (the touchscreen can't be set up, the displays are reconfiguring, or the flow won't start).
    private mutating func start(
        _ purpose: SetUpPurpose, of touchscreen: TouchscreenID, on display: DisplayFacts, displayName: String
    ) -> SetUpFlow.Start? {
        guard !scene.isReconfiguring, let entry = entry(touchscreen), entry.canBeSetUp,
              let present = scene.displays.first(where: {
                  $0.displayID == display.displayID && DisplayIdentity($0) == DisplayIdentity(display)
              })
        else { return nil }
        let start = SetUpFlow.Start(
            touchscreen: touchscreen, touchscreenName: entry.name, purpose: purpose, candidates: [present],
            allDisplays: scene.displays, reportedSizeMM: entry.reportedSizeMM, current: entry.pairing,
            currentDiagonal: entry.diagonalInches)
        guard var flow = SetUpFlow(start, at: now) else { return nil }
        // Fingers already down are no tap: the flow sees their latest frame first, timed before its
        // start, and ignores them until they lift.
        if glass[touchscreen] != nil, let frame = lastFrames[touchscreen] { _ = flow.handle(frame) }
        change(to: .running(Running(
            flow: flow, touchscreen: touchscreen, name: entry.name, purpose: purpose, displayName: displayName)))
        flowDisplays = scene.displays
        return start
    }

    // MARK: - Private: touches

    /// What the session makes of a frame of `touchscreen`'s, outside its flow: a landing, a touch
    /// going on, or the glass clearing, which may answer.
    private mutating func track(_ frame: ContactFrame, from touchscreen: TouchscreenID) -> [Event] {
        if frame.contacts.isEmpty {
            let lifted = glass.removeValue(forKey: touchscreen)
            lastFrames[touchscreen] = nil
            guard case .answering(let answer)? = lifted, answer.answers else { return [] }
            return answered(by: touchscreen)
        }
        lastFrames[touchscreen] = frame
        switch glass[touchscreen] {
        case nil:
            // A landing is input, whatever comes of it, from a touchscreen that can be set up: one
            // that can't moves the mode on in no way, and a noisy one would keep it on.
            if entry(touchscreen)?.canBeSetUp == true { lastInput = now }
            // Not a number fails these too.
            let isAnswer = !isRunning && !scene.isReconfiguring
                && frame.time >= changedAt + SetUpFlow.reactionTime
                && frame.time >= startedAt + SetUpFlow.startQuiet
            glass[touchscreen] = isAnswer ? .answering(Answer(frame.contacts)) : .ignored
        case .ignored?:
            break
        case .answering(var answer)?:
            answer.see(frame.contacts)
            glass[touchscreen] = .answering(answer)
        }
        return []
    }

    /// `touchscreen`'s touch answered.
    private mutating func answered(by touchscreen: TouchscreenID) -> [Event] {
        guard let entry = entry(touchscreen) else { return [] }
        guard entry.canBeSetUp else {
            notice = .cannotBeSetUp(touchscreen: touchscreen, name: entry.name)
            return [.cannotBeSetUp(touchscreen: touchscreen, name: entry.name)]
        }
        lastInput = now  // an answer is input, as its landing was
        switch stage {
        case .choosing:
            change(to: .touchedFirst(touchscreen, name: entry.name))
            return [.touchedFirst(touchscreen: touchscreen, name: entry.name)]
        case .waitingForTouch(let display, let name):
            guard let started = start(.full, of: touchscreen, on: display, displayName: name) else { return [] }
            return [.answered(touchscreen: touchscreen, name: entry.name, displayName: name), .flowStarted(started)]
        case .touchedFirst(let first, _):
            guard first != touchscreen else { return [] }
            change(to: .touchedFirst(touchscreen, name: entry.name))
            return [.touchedFirst(touchscreen: touchscreen, name: entry.name)]
        case .running:
            return []
        }
    }

    private func entry(_ id: TouchscreenID) -> Touchscreen? {
        scene.touchscreens.first { $0.id == id }
    }
}
