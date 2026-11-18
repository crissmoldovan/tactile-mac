import CoreGraphics
import Foundation

/// What one moving finger should do: grab what's under it, or scroll the content.
public enum OneFingerIntent: Equatable, Sendable {
    case drag
    case scroll
}

public enum GesturePhase: Equatable, Sendable {
    case began
    case changed
    case ended
}

public enum SwipeDirection: Equatable, Sendable {
    case left
    case right
    case up
    case down
}

/// The axis a swipe that follows the fingers moves along.
public enum SwipeAxis: Equatable, Sendable {
    case horizontal
    case vertical
}

/// Where a swipe that follows the fingers has got to.
public enum SwipeTrackingPhase: Equatable, Sendable {
    case began
    case changed
    /// The fingers lifted going on: finish the transition. `velocity` is along the axis at lift,
    /// in fractions of the display per second, signed as `offset`.
    case completed(velocity: Double)
    /// Slide back: the fingers lifted moving back, or too short and slow, or the touch was cut short.
    case cancelled
}

/// What the engine asks the app to do.
///
/// Locations are relative to the display the touchscreen is paired with: 0…1 on each axis, origin
/// top-left. Distances are relative too, as fractions of that display's width and height.
public enum GestureAction: Equatable, Sendable {
    /// The first finger of a touch session landed: remember where the pointer is and hide the arrow.
    case sessionBegan
    /// Move the pointer without pressing a button.
    case movePointer(to: CGPoint)
    /// Press and release the left button. `count` is 2 for a double-click and 3 for a triple-click.
    case click(at: CGPoint, count: Int)
    /// Press the left button to start a drag.
    case press(at: CGPoint, count: Int)
    case drag(to: CGPoint)
    case release(at: CGPoint)
    case rightClick(at: CGPoint)
    /// One finger has rested long enough that lifting it now right-clicks, at `at`, where it landed.
    /// Said once, the moment it becomes true. Ring that finger's circle until the engine's next
    /// action, which is always one of `rightClick` (it lifted), `press` (it moved: a drag),
    /// `longPressWithdrawn` (a second finger landed) or `sessionCancelled`.
    case longPressReady(at: CGPoint)
    /// Lifting no longer right-clicks: a second finger landed after `longPressReady`, so the fingers
    /// are now judged as two. Take the ring down.
    case longPressWithdrawn
    /// The fingers moved by `by` while scrolling. The content should move the same way.
    case scroll(by: CGVector, phase: GesturePhase)
    /// Coasting after a flick, in the same direction as the scroll before it.
    case momentum(by: CGVector, phase: GesturePhase)
    /// Zoom. The value is the change in size since the previous pinch event: 0.05 is 5% larger.
    case pinch(by: Double, phase: GesturePhase)
    /// Turn. The value is the degrees the fingers turned since the previous rotate event, positive
    /// anticlockwise as the person sees the display, as `NSEvent.rotation` has it. The events add up
    /// to the whole turn since the second finger landed.
    case rotate(by: Double, phase: GesturePhase)
    case swipe(SwipeDirection)
    /// Three or four fingers moving together along `axis`, for a transition that follows them.
    /// `offset` is how far their centre has moved along the axis since they landed, as a fraction of
    /// the display's width or height, negative leftwards or upwards. The last one of a swipe is always
    /// `completed` or `cancelled`, also when the session is cancelled. Only for the engine's
    /// `followedSwipeAxes`; a swipe along any other axis is a `swipe`.
    case swipeTracking(axis: SwipeAxis, offset: Double, phase: SwipeTrackingPhase)
    /// The session ended normally; the pointer may go back where it was.
    case sessionEnded
    /// The touch was cut short. Whatever was in flight has been closed by the actions before this
    /// one. It is not an end: the pointer keeper must not send the pointer home because of it.
    case sessionCancelled
}
