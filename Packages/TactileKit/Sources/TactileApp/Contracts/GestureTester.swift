import Foundation
import TactileScreens

/// The gesture tester, while it is open: one touchscreen, its gestures, and how the person can
/// interact with things, on both kinds of touchscreen (one finger only, and full touch). Its window
/// opens on the display the touchscreen is paired with. While it is open the touchscreen still
/// drives, exactly as it does otherwise, so the tester's controls react to the real thing; the one
/// difference is that its three- and four-finger swipes are recorded and not done, unless
/// `performsSwipes`.
public struct GestureTesterSnapshot: Equatable, Codable, Sendable {
    public var touchscreen: TouchscreenID
    public var touchscreenName: String
    public var displayID: UInt32               // the display it is paired with: the tester's window opens there
    public var multiTouch: Bool                // false: it gives one finger (multi-finger gestures can't happen)
    public var performsSwipes: Bool            // false: three- and four-finger swipes are shown, not done
    public var fingersDown: Int                // updated when the count changes
    public var recent: [RecognisedGesture]     // newest first, at most 40
    public var seen: [GestureSeenCount]        // one per kind seen since opening or clearing

    public init(
        touchscreen: TouchscreenID,
        touchscreenName: String,
        displayID: UInt32,
        multiTouch: Bool,
        performsSwipes: Bool,
        fingersDown: Int,
        recent: [RecognisedGesture],
        seen: [GestureSeenCount]
    ) {
        self.touchscreen = touchscreen
        self.touchscreenName = touchscreenName
        self.displayID = displayID
        self.multiTouch = multiTouch
        self.performsSwipes = performsSwipes
        self.fingersDown = fingersDown
        self.recent = recent
        self.seen = seen
    }
}

/// One gesture the tester saw, in plain words: written by the model from the touchscreen's engine
/// actions, the fingers down, and what the pipeline ignored.
public struct RecognisedGesture: Equatable, Codable, Sendable, Identifiable {
    public enum Kind: String, CaseIterable, Equatable, Codable, Sendable {
        /// Tap, double tap, triple tap: from the click count.
        case tap, doubleTap, tripleTap
        /// Press, drag, release.
        case drag
        /// A press after the ring (`longPressReady`): hold, then drag.
        case holdThenDrag
        /// With its fingers and distance in points; one entry per scroll, updated while it goes on.
        case scroll
        /// The momentum that follows a scroll.
        case flick
        /// Zoom in or out, the overall factor.
        case pinch
        /// The overall degrees and direction.
        case rotate
        /// From a long press, or from a two-finger tap.
        case rightClick
        /// Fingers, direction, and what it does or would do ("next Desktop", "Mission Control"…).
        case swipe
        /// A swipe that follows the fingers: completed or slid back.
        case followedSwipe
        /// A palm, the edge, a second finger on a one-finger touchscreen.
        case ignored
        /// Cancelled, and why.
        case cancelled
    }

    public var id: Int                         // a sequence number, rising
    public var kind: Kind
    public var fingers: Int
    public var summary: String                 // plain words: "340 pt down", "zoom 1.4×", "left: next Desktop", "a palm"
    public var at: TimeInterval                // host uptime

    public init(id: Int, kind: Kind, fingers: Int, summary: String, at: TimeInterval) {
        self.id = id
        self.kind = kind
        self.fingers = fingers
        self.summary = summary
        self.at = at
    }
}

/// How many gestures of one kind the tester has seen since it opened or was cleared.
public struct GestureSeenCount: Equatable, Codable, Sendable, Identifiable {
    public var id: RecognisedGesture.Kind
    public var count: Int

    public init(id: RecognisedGesture.Kind, count: Int) {
        self.id = id
        self.count = count
    }
}
