import Foundation

/// Thresholds for recognising gestures. Distances are millimetres on the glass; times are seconds.
public struct GestureConstants: Sendable {
    /// Movement below this still counts as a tap.
    public var slop: Double = 3
    /// Resting this long before moving forces a drag.
    public var holdTime: TimeInterval = 0.4
    /// Resting this long, then lifting, right-clicks, when long-press is on.
    public var longPressDuration: TimeInterval = 0.6
    /// The most time between taps for a double- or triple-click.
    public var tapInterval: TimeInterval = 0.4
    /// The furthest apart taps can be for a double- or triple-click.
    public var tapDistance: Double = 8
    /// Both fingers of a two-finger tap must lift within this time of the second landing.
    public var twoFingerTapTime: TimeInterval = 0.3
    /// Two fingers scroll when their directions are within this many degrees of each other.
    public var scrollAngle: Double = 45
    /// Two fingers pinch when the distance between them changes by more than this fraction.
    public var pinchRatio: Double = 0.08
    /// Two fingers going round each other (each moved `slop`, in directions more than 90° apart)
    /// rotate when the line between them turns more than this many degrees, while their distance
    /// has changed less than `pinchRatio`.
    public var rotateThresholdDegrees: Double = 12
    /// A twist about a resting finger (one still within `slop` of where it landed) rotates when
    /// the line turns more than this many degrees, while the distance has changed less than
    /// `pinchRatio`. Larger than `rotateThresholdDegrees`, because a two-finger scroll that one
    /// finger starts alone looks the same at first.
    public var rotatePivotThresholdDegrees: Double = 25
    /// A twist about a resting finger counts only when the fingers landed at least this far apart.
    /// Thumb-and-finger twists are wider than this; fingers scrolling side by side are 15–22 mm
    /// apart, and one of them starting alone, with the hand turned a little, can turn their line
    /// 25° while their gap holds.
    public var rotatePivotMinimumSpanMM: Double = 30
    /// Three or four fingers must all land within this time of the first.
    public var swipeLanding: TimeInterval = 0.2
    /// How far the fingers must move together for a swipe.
    public var swipeDistance: Double = 30
    /// How far the fingers move, within `swipeAngle` of an axis that is followed, before a swipe that
    /// follows them begins. Such a swipe completes, without a flick, once they have gone
    /// `swipeDistance` and aren't coming back.
    public var swipeTrackingStart: Double = 8
    /// A swipe must be within this many degrees of horizontal or vertical.
    public var swipeAngle: Double = 30
    /// A flick's speed is measured over this much time before the fingers lift.
    public var flickWindow: TimeInterval = 0.1
    /// Scroll samples spanning less time than this give no flick speed.
    public var flickMinimumSpan: TimeInterval = 0.01
    /// The slowest flick, in mm/s at lift, that coasts.
    public var momentumMinSpeed: Double = 100
    /// Coasting stops below this speed, in mm/s.
    public var momentumStopSpeed: Double = 20
    /// Coasting speed falls by a factor of e every this many seconds.
    public var momentumTimeConstant: TimeInterval = 0.325
    /// With palm rejection on, a contact whose width or height is over this is a palm.
    public var palmWidthMM: Double = 25
    /// With palm rejection on, this many contacts or more down that all landed within `swipeLanding`
    /// of the first of them are a hand or a forearm.
    public var handContactCount: Int = 5

    public init() {}

    public static let standard = GestureConstants()
}
