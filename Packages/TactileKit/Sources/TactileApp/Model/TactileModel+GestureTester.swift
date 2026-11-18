// The gesture tester, model side: which touchscreen it is open for, its feed, and when it closes.

import CoreGraphics
import Foundation
import TactileDevices
import TactileGestures
import TactileScreens
import os

/// The gesture tester while it is open: one touchscreen, the narrator writing its feed, and whether
/// its three- and four-finger swipes are let through. It is the observer of that touchscreen's
/// pipeline (`TouchPipeline.observer`), which tells it everything the pipeline does with a touch.
///
/// The feed is published at most every `publishInterval`, once the model has handed a frame or a tick
/// to the pipelines (so all one frame's news goes at once), or at the end of a round; what changes
/// in between waits for the model's next tick. The state file, which holds the snapshot, is written
/// with it at most every `stateFileInterval`, and once more when the narrator is idle, so it always
/// ends equal to the snapshot. The model ticks while either waits (`needsTicks`).
@MainActor
final class GestureTesterSession: TouchPipelineObserver {
    /// The snapshot's tester changes at most this often while a gesture goes on.
    static let publishInterval: TimeInterval = 0.1
    /// While it is open, the state file is written at most this often, but for a gesture's last change.
    static let stateFileInterval: TimeInterval = 1

    let touchscreen: TouchscreenID
    var touchscreenName: String
    var displayID: UInt32
    var multiTouch: Bool
    /// False, the default each time it opens: three- and four-finger swipes are held.
    var performsSwipes = false
    private(set) var narrator = GestureNarrator()
    /// The feed has changed since it was last published.
    private(set) var hasNews = false
    private var publishedAt = -TimeInterval.infinity
    private var publishedVersion = 0
    /// The model's snapshot has had news from it that the state file hasn't.
    private(set) var stateFileOwed = false
    private var stateFileWrittenAt = -TimeInterval.infinity

    init(touchscreen: TouchscreenID, touchscreenName: String, displayID: UInt32, multiTouch: Bool) {
        self.touchscreen = touchscreen
        self.touchscreenName = touchscreenName
        self.displayID = displayID
        self.multiTouch = multiTouch
    }

    var holdsSwipes: Bool { !performsSwipes }

    var snapshot: GestureTesterSnapshot {
        GestureTesterSnapshot(
            touchscreen: touchscreen, touchscreenName: touchscreenName, displayID: displayID, multiTouch: multiTouch,
            performsSwipes: performsSwipes, fingersDown: narrator.fingersOnGlass, recent: narrator.recent,
            seen: narrator.seen)
    }

    func pipeline(_ pipeline: TouchPipeline, saw observation: TouchObservation, at time: TimeInterval) {
        guard pipeline.id == touchscreen else { return }
        let finished = narrator.see(observation, at: time, displaySize: pipeline.driving.displayFrame.size,
                                    holdTime: pipeline.constants.holdTime)
        for gesture in finished {
            ModelLog.model.debug("Gesture tester: \(gesture.kind.rawValue, privacy: .public), \(gesture.fingers) finger\(gesture.fingers == 1 ? "" : "s", privacy: .public): \(gesture.summary, privacy: .public)")
        }
        if narrator.version != publishedVersion { hasNews = true }
    }

    /// Empties the feed and the counts. The model's round that follows publishes it.
    func clear() {
        narrator.clear()
    }

    /// Whether the model must keep ticking: news to publish, or a state file to write.
    var needsTicks: Bool { hasNews || stateFileOwed }

    /// Its snapshot, to publish, when it has news and it has been `publishInterval` since the last
    /// time; nil otherwise.
    func newsIfDue(at time: TimeInterval) -> GestureTesterSnapshot? {
        guard hasNews, time - publishedAt >= Self.publishInterval else { return nil }
        published(at: time)
        return snapshot
    }

    /// The model has published `snapshot` as it is now, at `time`.
    func published(at time: TimeInterval) {
        publishedAt = time
        publishedVersion = narrator.version
        hasNews = false
    }

    /// The snapshot has news the state file hasn't.
    func owesStateFile() {
        stateFileOwed = true
    }

    /// Whether to write the state file now: it owes one, and either it has been `stateFileInterval`
    /// since the last, or nothing is under way (the gesture's last change is in).
    func stateFileIsDue(at time: TimeInterval) -> Bool {
        stateFileOwed && (narrator.isIdle || time - stateFileWrittenAt >= Self.stateFileInterval)
    }

    /// The state file has been written with the snapshot as it is now.
    func stateFileWritten(at time: TimeInterval) {
        stateFileOwed = false
        stateFileWrittenAt = time
    }
}

extension TactileModel {

    /// The gesture tester's commands. The round that follows (see `perform`) attaches it to its
    /// touchscreen's pipeline and publishes it.
    func performGestureTester(_ command: AppCommand) {
        switch command {
        case .openGestureTester(let id):
            openGestureTester(id)
        case .closeGestureTester:
            if gestureTester != nil { closeGestureTester(because: "closed") }
        case .setGestureTesterPerformsSwipes(let isOn):
            guard let tester = gestureTester else {
                ModelLog.model.info("Gesture tester: letting swipes through refused: it isn't open")
                return
            }
            guard tester.performsSwipes != isOn else { return }
            tester.performsSwipes = isOn
            ModelLog.model.info("Gesture tester: swipes \(isOn ? "let through" : "held", privacy: .public)")
        case .clearGestureTester:
            gestureTester?.clear()
        default:
            break
        }
    }

    /// Opens the tester for `id` when it can be open (`Resolver.gestureTesterRefusal`); one open for
    /// another touchscreen moves to this one, afresh. Opening it again for the same one changes nothing.
    private func openGestureTester(_ id: TouchscreenID) {
        let shown = snapshot.touchscreens.first { $0.id == id }
        let name = shown?.name ?? id.rawValue
        if let refusal = Resolver.gestureTesterRefusal(for: id, in: snapshot) {
            ModelLog.model.info("Gesture tester not opened for \(name, privacy: .public) [\(id.rawValue, privacy: .public)]: \(String(describing: refusal), privacy: .public)")
            return
        }
        guard let shown, let displayID = shown.pairedDisplayID else { return }
        if let current = gestureTester {
            if current.touchscreen == id { return }
            closeGestureTester(because: "moved to \(name)")
        }
        gestureTester = GestureTesterSession(touchscreen: id, touchscreenName: name, displayID: displayID,
                                             multiTouch: shown.behaviour.multiFingerAvailable)
        ModelLog.model.info("Gesture tester opened for \(name, privacy: .public) [\(id.rawValue, privacy: .public)] on \(shown.pairedDisplayName ?? "its display", privacy: .public)")
    }

    /// Its pipeline's observer is taken away in the round that follows (`withGestureTester`). A
    /// followed swipe it held runs to its end held.
    private func closeGestureTester(because why: String) {
        guard gestureTester != nil else { return }
        gestureTester = nil
        ModelLog.model.info("Gesture tester closed (\(why, privacy: .public))")
    }

    /// The tester's part of a round, once the pipelines are as they will be: `resolution`'s snapshot
    /// with the tester in it. The tester closes when it can no longer be open, except while the
    /// displays reconfigure (`displaysSettling`: none published for a moment, so every touchscreen is
    /// held), when it stays as it is and the round after they settle decides. Otherwise it follows its
    /// touchscreen's name and display. Its touchscreen's pipeline, a fresh one included, has it as
    /// its observer, and every other pipeline none; with no tester open, no pipeline has one.
    func withGestureTester(_ resolution: Resolution, pipelines: [DeviceHandle: TouchPipeline],
                           at time: TimeInterval, displaysSettling: Bool) -> AppSnapshot {
        var shown = resolution.snapshot
        var observed: DeviceHandle?
        if let tester = gestureTester {
            let id = tester.touchscreen
            let resolved = resolution.touchscreens.first { $0.id == id }
            let refusal = Resolver.gestureTesterRefusal(for: id, in: shown)
            let settling = displaysSettling && refusal == .notDriving && resolved?.rule == .displayNotConnected
            if let refusal, !settling {
                closeGestureTester(because: Self.closing(refusal, rule: resolved?.rule,
                                                         status: shown.touchscreens.first { $0.id == id }?.status))
            } else {
                if refusal == nil, let touchscreen = shown.touchscreens.first(where: { $0.id == id }),
                   let displayID = touchscreen.pairedDisplayID {
                    tester.touchscreenName = touchscreen.name
                    tester.displayID = displayID
                    tester.multiTouch = touchscreen.behaviour.multiFingerAvailable
                }
                observed = resolved?.handle
                shown.gestureTester = tester.snapshot
                tester.published(at: time)
                // The round writes the state file when what it shows has changed.
                if shown != snapshot { tester.stateFileWritten(at: time) }
            }
        }
        for (handle, pipeline) in pipelines {
            if let tester = gestureTester, handle == observed {
                if pipeline.observer !== tester { pipeline.observer = tester }
            } else if pipeline.observer != nil {
                pipeline.observer = nil
            }
        }
        return shown
    }

    /// Whether the tester has news to publish, or a state file to write: the clock runs until it hasn't.
    var gestureTesterNeedsTicks: Bool {
        gestureTester?.needsTicks ?? false
    }

    /// After a frame or a tick has been through the pipelines: the tester's news into the snapshot, if
    /// it is due; and the state file, if it is due (see `GestureTesterSession`).
    func publishGestureTesterIfDue(at time: TimeInterval) {
        guard let tester = gestureTester else { return }
        if let news = tester.newsIfDue(at: time), snapshot.gestureTester?.touchscreen == news.touchscreen,
           snapshot.gestureTester != news {
            snapshot.gestureTester = news
            tester.owesStateFile()
        }
        if tester.stateFileIsDue(at: time) {
            writeStateFile()
            tester.stateFileWritten(at: time)
        }
    }

    /// The log's words for why the tester closed.
    static func closing(_ refusal: GestureTesterRefusal, rule: ModeRule?, status: TouchscreenStatus?) -> String {
        switch refusal {
        case .notConnected: return "the touchscreen was unplugged"
        case .cannotBeToldApart: return "the touchscreen can't be told apart from another"
        case .notPaired:
            if case .displayNotConnected? = status { return "its display has gone" }
            return "the touchscreen was unpaired"
        case .tactileOff: return "Tactile off"
        case .accessibilityMissing: return "Accessibility gone"
        case .switchedOff: return "the touchscreen was switched off"
        case .notDriving:
            switch rule {
            case .mouseModeShared?: return "macOS also handles the touchscreen"
            case .touchesUnreadable?: return "its touches can't be read"
            case .displayNotConnected?: return "its display isn't available (the displays are changing)"
            default: return "the touchscreen stopped driving"
            }
        case .touchscreensReleased:
            switch rule {
            case .sessionNotActive?: return "locked"
            case .asleep?: return "asleep"
            case .quitting?: return "quitting"
            default: return "the touchscreens were released"
            }
        case .settingUp: return "set-up began"
        }
    }
}
