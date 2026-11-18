// Set-up mode in the model: one `SetUpSession` while it is on, fed every touchscreen's frames, the
// person's commands, what is connected, and the time; and what it answers, applied.

import CoreGraphics
import Foundation
import TactileDevices
import TactileReading
import TactileScreens

/// **Set-up mode.** The model holds at most one `SetUpSession`. It begins (`beginSetUpMode`, or
/// `beginSetUp(_, .full)`) only when `Resolver.setUpModeRefusal` has nothing against it: Tactile on,
/// Accessibility granted, the session active, the displays settled, no other set-up running, a
/// connected touchscreen that can be set up and a candidate display. Otherwise it is refused, logged,
/// and nothing changes.
///
/// While it is on, every connected touchscreen is setting up (or held, when it can't be set up: see
/// `Resolver`'s mode table), whatever the table gave it before; a touchscreen connected during the
/// mode joins it. So no touchscreen drives: each one's pipeline is cancelled first, as for any
/// touchscreen that stops driving, and its frames go to the session, never to a pipeline or the
/// arbiter. Every touch is set-up input: never a click, a drag or a moved pointer. The mouse and
/// trackpad keep working, for the cards.
///
/// The session is ticked 10 times a second, on the clock frames are timed on, and is told what is
/// connected (`Resolver.setUpScene`) at the start of every round in which that changed. What is
/// published is its `snapshot` (and its running flow's, as `AppSnapshot.setUp`), which change only
/// when what they show changes. In the check step of a flow, its touches are shown as circles,
/// mapped with the flow's `checkMapping`.
///
/// What the session answers is applied in order:
/// - a flow's Done is stored in one change to the settings, as a flow outside the mode is
///   (`Resolver.applySetUp`), which also unpairs the display's previous touchscreen, if another, in
///   the same write; a flow that finishes with nil stores nothing;
/// - the mode ending puts every touchscreen back to the table's mode through the next resolve, with
///   no button held. Leaving by Finish, Esc or the mode's time limit marks every touchscreen the
///   session card showed as not set up at any moment as offered set-up (as Not Now does), in one
///   write: it had the offer. An interruption (a lock, sleep, Tactile off, Accessibility lost,
///   quitting) marks none.
///
/// While the mode is on the commands that change a fit stay refused, between its flows too.
extension TactileModel {

    // MARK: - Commands

    /// Carries out `command` if it is set-up mode's, or a set-up command while the mode is on, and
    /// says whether it did. `beginSetUp(_, .full)` is read as `beginSetUpMode`.
    func performInSetUpMode(_ command: AppCommand) -> Bool {
        switch command {
        case .beginSetUpMode, .beginSetUp(_, .full):
            beginSetUpMode()
        case .beginSetUp(let id, let purpose):
            guard setUpMode != nil else { return false }
            let events = stepSetUpMode { $0.begin(purpose, of: id, at: $1) }
            if !events.contains(where: { if case .flowStarted = $0 { return true } else { return false } }) {
                ModelLog.model.info("Set-up of \(id.rawValue, privacy: .public) (\(purpose.rawValue, privacy: .public)) can't begin now, in set-up mode")
            }
        case .setUpChoose(let displayID):
            guard setUpMode != nil else {
                ModelLog.model.info("Command \(String(describing: command), privacy: .public) refused: set-up mode is off")
                return true
            }
            if stepSetUpMode({ $0.choose(display: displayID, at: $1) }).isEmpty {
                ModelLog.model.info("Set-up mode: choosing display \(displayID) changed nothing")
            }
        case .setUpBack:
            guard setUpMode != nil else {
                ModelLog.model.info("Command \(String(describing: command), privacy: .public) refused: set-up mode is off")
                return true
            }
            stepSetUpMode { $0.back(at: $1) }
        case .setUpConfirmSize(let inches):
            guard setUpMode != nil else { return false }
            ModelLog.model.info("Set-up: confirm size \(inches.map { "\($0)″" } ?? "as reported", privacy: .public)")
            stepSetUpMode { $0.confirmSize(inches: inches, at: $1) }
        case .setUpRedo:
            guard setUpMode != nil else { return false }
            ModelLog.model.info("Set-up: redo")
            stepSetUpMode(tooSoonAs: "Redo") { $0.redo(at: $1) }
        case .setUpDone:
            guard setUpMode != nil else { return false }
            ModelLog.model.info("Set-up: done")
            stepSetUpMode(tooSoonAs: "Done") { $0.done(at: $1) }
        case .cancelSetUp:
            guard setUpMode != nil else { return false }
            stepSetUpMode { $0.finish(at: $1) }
        default:
            return false
        }
        return true
    }

    /// Begins set-up mode, if it can begin now.
    private func beginSetUpMode() {
        guard hasStarted else { return }
        noteSetUpInInputs()
        if let refusal = Resolver.setUpModeRefusal(inputs) {
            ModelLog.model.info("Set-up mode not begun: \(refusal.words, privacy: .public)")
            return
        }
        let time = now()
        let scene = Resolver.setUpScene(inputs)
        guard var session = SetUpSession(scene.scene, at: time) else {
            ModelLog.model.info("Set-up mode not begun: nothing to set up")
            return
        }
        ModelLog.model.info("\(session.beganLogLine, privacy: .public)")
        // A finger already resting when it begins is not a touch: the session sees it first, timed
        // before its start, and ignores it until it lifts.
        for (handle, id) in scene.touchscreens.sorted(by: { $0.key.rawValue < $1.key.rawValue })
        where hasFingersDown(handle, at: time) {
            if let frame = lastFrames[handle] { _ = session.handle(frame, from: id) }
        }
        setUpMode = session
        setUpModeScene = scene
        resolveAndApply()
    }

    /// One of the person's commands for the mode, at the moment it is made.
    /// `tooSoonAs`: for Done and Redo, the name a line gives the command when the running flow
    /// ignores it as too soon after the check appeared (see `tooSoonLine`).
    @discardableResult
    private func stepSetUpMode(
        tooSoonAs: String? = nil, _ step: (inout SetUpSession, TimeInterval) -> [SetUpSession.Event]
    ) -> [SetUpSession.Event] {
        guard var session = setUpMode else { return [] }
        let time = now()
        if let tooSoonAs, var flow = session.flow, flow.tick(at: time) == .stillRunning,
           let line = Self.tooSoonLine(tooSoonAs, after: flow) {
            ModelLog.model.info("\(line, privacy: .public)")
        }
        let events = step(&session, time)
        setUpMode = session
        applySetUpModeEvents(events)
        resolveAndApply()
        return events
    }

    // MARK: - Frames, ticks and changes

    /// A frame of `handle`'s, while the mode is on: for the session, and in a flow's check step, for
    /// its circles.
    func feedSetUpMode(_ frame: ContactFrame, from handle: DeviceHandle) {
        guard var session = setUpMode, let id = setUpModeScene?.touchscreens[handle] else { return }
        let before = session.snapshot
        let flowBefore = session.flow?.snapshot
        let roundBefore = session.flow?.lastCornersReport?.round
        let events = session.handle(frame, from: id)
        setUpMode = session
        // A round of the corners ends only on a frame: its taps' distances, for tuning the limits.
        if let report = session.flow?.lastCornersReport, report.round != roundBefore {
            ModelLog.model.info("\(report.logLine, privacy: .public)")
        }
        if let flow = session.flow, flow.snapshot.touchscreen == id {
            drawSetUpCircles(frame, with: flow.checkMapping)
        }
        applySetUpModeEvents(events)
        if !events.isEmpty || session.snapshot != before || session.flow?.snapshot != flowBefore {
            resolveAndApply()
        }
    }

    /// The time passing, while the mode is on.
    func tickSetUpMode(at time: TimeInterval) {
        guard var session = setUpMode else { return }
        let before = session.snapshot
        let flowBefore = session.flow?.snapshot
        let events = session.tick(at: time)
        setUpMode = session
        applySetUpModeEvents(events)
        if !events.isEmpty || session.snapshot != before || session.flow?.snapshot != flowBefore {
            resolveAndApply()
        }
    }

    /// At every round: the mode's own time limit first, which is the person's ending; then what
    /// ends it at once (`Resolver.setUpModeInterruption`); then what is connected, when it changed.
    func settleSetUpMode() {
        guard var session = setUpMode else { return }
        let time = now()
        var events = session.tick(at: time)
        if !session.hasEnded, let why = Resolver.setUpModeInterruption(inputs) {
            events += session.interrupt(why)
        }
        if !session.hasEnded {
            let scene = Resolver.setUpScene(inputs)
            if scene != setUpModeScene {
                if scene.scene != setUpModeScene?.scene { events += session.sceneChanged(scene.scene, at: time) }
                setUpModeScene = scene
            }
        }
        setUpMode = session
        applySetUpModeEvents(events)
    }

    /// What the resolver is told of the set-up running: the flow (in the mode or outside it) and the
    /// mode.
    func noteSetUpInInputs() {
        inputs.setUp = setUp?.flow.snapshot ?? setUpMode?.flow?.snapshot
        inputs.setUpMode = setUpMode?.snapshot
    }

    // MARK: - What the session answers

    /// Applies `events`, in order: the log, a Done stored, the mode ended.
    private func applySetUpModeEvents(_ events: [SetUpSession.Event]) {
        for event in events {
            if let line = event.logLine { ModelLog.model.info("\(line, privacy: .public)") }
            switch event {
            case .flowStarted(let start):
                ModelLog.model.info("\(Self.setUpBeganLine(start), privacy: .public)")
            case .flowFinished(let id, let name, let purpose, let outcome):
                hideSetUpCircles()
                ModelLog.model.info("\(Self.setUpEndedLine(name, id, purpose, outcome), privacy: .public)")
                guard let outcome else { break }
                // One write: the pairing, the fit and the size, and the display's previous
                // touchscreen, if another, unpaired.
                let settings = Resolver.applySetUp(outcome, purpose: purpose, to: id, in: inputs, endedByThePerson: true)
                if settings != inputs.settings {
                    inputs.settings = settings
                    save()
                }
            case .ended(_, let markOffered, _):
                setUpMode = nil
                setUpModeScene = nil
                hideSetUpCircles()
                var settings = inputs.settings
                for id in markOffered {
                    var offering = inputs
                    offering.settings = settings
                    offering.setUpMode = nil
                    settings = Resolver.apply(.declineSetUp(id), to: offering)
                }
                if settings != inputs.settings {
                    inputs.settings = settings
                    save()
                }
            case .chose, .answered, .touchedFirst, .cannotBeSetUp, .backToTheScreens:
                break
            }
        }
        if setUpMode?.flow?.checkMapping == nil, setUp == nil { hideSetUpCircles() }
    }

    // MARK: - Lines

    /// The line for a flow beginning, in set-up mode or outside it.
    static func setUpBeganLine(_ start: SetUpFlow.Start) -> String {
        let candidates = start.candidates.map { "\($0.displayID) \"\($0.name)\"" }.joined(separator: ", ")
        return "Set-up began: \(start.touchscreenName) [\(start.touchscreen.rawValue)], \(start.purpose.rawValue), "
            + "candidates \(candidates)"
    }

    /// The line for a flow ending: what Done stored, or that nothing was.
    static func setUpEndedLine(
        _ name: String, _ id: TouchscreenID, _ purpose: SetUpPurpose, _ outcome: SetUpFlow.Outcome?
    ) -> String {
        guard let outcome else { return "Set-up ended with nothing stored: \(name) [\(id.rawValue)], \(purpose.rawValue)" }
        let orientation = "\(outcome.orientation.quarterTurns * 90)°" + (outcome.orientation.isFlipped ? " flipped" : "")
        return "Set-up done: \(name) [\(id.rawValue)] on \(outcome.display.uuid), orientation \(orientation), "
            + "alignment \(String(describing: outcome.alignment.pictureRect)), "
            + "diagonal \(outcome.diagonalInches.map { "\($0)″" } ?? "as reported")"
    }
}
