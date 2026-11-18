// What every touch pipeline carries its actions out through. One set, shared by every pipeline:
// there is one pointer, one mouse button and one arrow.

import CoreGraphics
import Foundation
import TactileGestures
import TactileOutput
import TactileScreens

@MainActor
public protocol PipelineOutputs: AnyObject {
    var sender: EventSender { get }
    var keeper: PointerKeeper { get }
    var arbiter: PointerArbiter<TouchscreenID> { get }
    /// The one Dock-swipe sender, for the app's life: a followed swipe's open state and its
    /// repeated end live in it. The arbiter lets only one touchscreen drive it at a time.
    var dockSwipes: DockSwipeSender { get }
    /// Sends at once whatever the Dock-swipe sender is waiting to send (its repeated end), for
    /// quitting: the wait would die with the process.
    func sendDockSwipeWaitsNow()
    /// The app whose window is under `point`, a global desktop point, Tactile's own windows left
    /// out; nil over no app's window. Asked for drag or scroll, and as a scroll begins.
    func app(atDesktopPoint point: CGPoint) -> AppUnderPoint?
    /// Drag or scroll, for a finger that starts moving from `point`, a global desktop point, over a
    /// window of the app `pid`: asked of that app alone.
    func intent(atDesktopPoint point: CGPoint, inApp pid: pid_t) -> OneFingerIntent
    /// Shows a circle at each finger on display `displayID`, at display points 0…1, and fades out
    /// the circles of fingers no longer listed. The contact IDs in `hollow` are drawn hollow; those
    /// in `ringed` carry a ring outside the circle: lifting that finger now will right-click.
    func showCircles(_ fingers: [Int: CGPoint], hollow: Set<Int>, ringed: Set<Int>, onDisplay displayID: UInt32)
    /// Fades out every circle on display `displayID`.
    func hideCircles(onDisplay displayID: UInt32)
}
