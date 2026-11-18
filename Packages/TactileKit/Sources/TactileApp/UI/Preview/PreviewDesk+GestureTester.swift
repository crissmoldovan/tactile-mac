// The gesture tester on the preview desk: opened for either touchscreen by the same commands the
// model takes, with a feed to show. The desk has no touches, so opening fills the feed with what a
// person trying every gesture would see: on the ILITEK every kind; on the strip, which gives one
// finger, what one finger can make. `testerSaw` and `testerFingers` add to it by hand.

import Foundation
import TactileScreens

extension PreviewDesk {

    /// The tester while it is open.
    struct Tester: Equatable, Sendable {
        var touchscreen: TouchscreenID
        var performsSwipes = false
        var fingersDown = 0
        /// Newest first, at most `testerFeedLimit`.
        var recent: [RecognisedGesture] = []
        var seen: [RecognisedGesture.Kind: Int] = [:]
        var nextID = 1
    }

    /// As many as the model keeps.
    static let testerFeedLimit = 40

    /// The four tester commands. Opening needs what the interface offers it for
    /// (`GestureTesterAvailability`); opening it for another touchscreen moves it.
    mutating func applyTester(_ command: AppCommand, at now: TimeInterval) {
        switch command {
        case .openGestureTester(let id):
            guard tester?.touchscreen != id else { return }
            let snapshot = snapshot()
            guard let touchscreen = snapshot.touchscreens.first(where: { $0.id == id }),
                GestureTesterAvailability.of(touchscreen, in: snapshot) == .available
            else { return }
            tester = Tester(touchscreen: id)
            for (kind, fingers, summary) in Self.sampleFeed(multiTouch: touchscreen.behaviour.multiFingerAvailable) {
                testerSaw(kind, fingers: fingers, summary: summary, at: now)
            }
            testerFingers(touchscreen.behaviour.multiFingerAvailable ? 2 : 1)
        case .closeGestureTester:
            tester = nil
        case .setGestureTesterPerformsSwipes(let on):
            tester?.performsSwipes = on
        case .clearGestureTester:
            guard var cleared = tester else { return }
            cleared.recent = []
            cleared.seen = [:]
            tester = cleared
        default:
            break
        }
    }

    /// Closes the tester when its touchscreen can't have one any more: unplugged, unpaired, its
    /// display gone, Tactile off, a set-up begun. Called after every command.
    mutating func closeTesterIfItMustClose() {
        guard let open = tester else { return }
        let snapshot = snapshot()
        guard let touchscreen = snapshot.touchscreens.first(where: { $0.id == open.touchscreen }),
            GestureTesterAvailability.of(touchscreen, in: snapshot) == .available
        else {
            tester = nil
            return
        }
    }

    /// A gesture the tester saw, newest first.
    mutating func testerSaw(_ kind: RecognisedGesture.Kind, fingers: Int, summary: String, at now: TimeInterval = 0) {
        guard var open = tester else { return }
        open.recent.insert(RecognisedGesture(id: open.nextID, kind: kind, fingers: fingers, summary: summary, at: now), at: 0)
        open.recent = Array(open.recent.prefix(Self.testerFeedLimit))
        open.nextID += 1
        open.seen[kind, default: 0] += 1
        tester = open
    }

    mutating func testerFingers(_ count: Int) {
        tester?.fingersDown = max(0, count)
    }

    /// The snapshot's `gestureTester`.
    func testerSnapshot() -> GestureTesterSnapshot? {
        guard let open = tester, let panel = panels.first(where: { $0.id == open.touchscreen }),
            let uuid = panel.pairedUUID, let screen = screens.first(where: { $0.uuid == uuid && $0.isConnected })
        else { return nil }
        return GestureTesterSnapshot(
            touchscreen: open.touchscreen, touchscreenName: panel.name, displayID: screen.id,
            multiTouch: !panel.notes.contains(.oneFingerOnly), performsSwipes: open.performsSwipes,
            fingersDown: open.fingersDown, recent: open.recent,
            seen: RecognisedGesture.Kind.allCases.compactMap { kind in
                open.seen[kind].map { GestureSeenCount(id: kind, count: $0) }
            })
    }

    /// What a person trying every gesture would leave in the feed, oldest first. In the words the
    /// plan gives the model's narrator; what was ignored, in the narrator's own words, and only what
    /// each touchscreen can recognise (the ILITEK reports no size: a whole hand, not a palm).
    static func sampleFeed(multiTouch: Bool) -> [(RecognisedGesture.Kind, Int, String)] {
        let oneFinger: [(RecognisedGesture.Kind, Int, String)] = [
            (.tap, 1, "on Tap Me"),
            (.doubleTap, 1, "a word selected"),
            (.tripleTap, 1, "a paragraph selected"),
            (.scroll, 1, "340 pt down"),
            (.flick, 1, "glided 820 pt down"),
            (.holdThenDrag, 1, "held 0.6 s, then 210 pt"),
            (.drag, 1, "180 pt right"),
            (.rightClick, 1, "from a long press"),
            (.ignored, 2, GestureNarrator.ignored(.beyondOneFinger)),
            (.cancelled, 1, "the touch was cut short"),
        ]
        guard multiTouch else { return oneFinger }
        return oneFinger.filter { $0.0 != .ignored } + [
            (.scroll, 2, "120 pt up"),
            (.flick, 2, "glided 460 pt up"),
            (.pinch, 2, "zoom 1.4×"),
            (.rotate, 2, "turned 35° anticlockwise"),
            (.rightClick, 2, "from a two-finger tap"),
            (.swipe, 3, "left: next Desktop · not done: the tester holds swipes"),
            (.swipe, 4, "up: Mission Control · not done: the tester holds swipes"),
            (.followedSwipe, 3, "right: slid back"),
            (.ignored, 5, GestureNarrator.ignored(.hand)),
            (.ignored, 1, GestureNarrator.ignored(.edge)),
        ]
    }
}
