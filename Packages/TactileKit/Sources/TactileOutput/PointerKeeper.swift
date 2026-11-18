import AppKit

/// Hides the arrow while fingers are on the glass, and decides where the pointer ends up afterwards.
@MainActor
public final class PointerKeeper {
    private let pointerLocation: () -> CGPoint
    private let setArrowHidden: (Bool) -> Void
    private let warp: (CGPoint) -> Void
    /// Whether to bring the arrow back on the first real mouse movement. Only `init()` does.
    private let watchesRealMouse: Bool

    /// Where the pointer was before any touching; nil while no session is open, and once a cancel
    /// or real mouse movement has forgotten it.
    private var home: CGPoint?
    /// The frame and return setting of the touchscreen holding the pointer.
    private var touchscreenFrame = CGRect.null
    private var returnMode: PointerReturn = .backWhereItWas
    /// Whether this keeper has hidden the arrow and not shown it again.
    private var arrowHidden = false
    private var mouseMonitor: Any?

    /// A keeper that reads, hides and moves the real pointer, and shows the arrow again on the first
    /// mouse or trackpad movement Tactile didn't post itself.
    public convenience init() {
        let cursor = CursorVisibility()
        self.init(pointerLocation: { EventSender.pointerLocation },
                  setArrowHidden: { hidden in
                      if hidden { cursor.hide() } else { cursor.show() }
                  },
                  warp: { point in
                      CGWarpMouseCursorPosition(point)
                      // Warping briefly decouples the mouse from the pointer; couple them again straight away.
                      CGAssociateMouseAndMouseCursorPosition(1)
                  },
                  watchesRealMouse: true)
    }

    /// The same keeper with its three contacts with the system replaced: where the pointer is,
    /// hiding or showing the arrow, and moving the pointer. It installs no event monitors.
    ///
    /// `setArrowHidden` may be called again with the value it already has, such as `true` on a
    /// hand-over, and must tolerate that.
    public convenience init(pointerLocation: @escaping () -> CGPoint,
                            setArrowHidden: @escaping (Bool) -> Void,
                            warp: @escaping (CGPoint) -> Void) {
        self.init(pointerLocation: pointerLocation, setArrowHidden: setArrowHidden, warp: warp,
                  watchesRealMouse: false)
    }

    private init(pointerLocation: @escaping () -> CGPoint,
                 setArrowHidden: @escaping (Bool) -> Void,
                 warp: @escaping (CGPoint) -> Void,
                 watchesRealMouse: Bool) {
        self.pointerLocation = pointerLocation
        self.setArrowHidden = setArrowHidden
        self.warp = warp
        self.watchesRealMouse = watchesRealMouse
    }

    /// The first finger of a session landed. `touchscreenFrame` is in global coordinates with the
    /// origin at the top left; `returnMode` is that touchscreen's setting.
    ///
    /// Called again while a session is open, another touchscreen has taken the pointer over: the
    /// first home is kept, so the pointer still returns to where it was before any touching, and
    /// the new touchscreen's frame and return setting are taken, since it holds the pointer now.
    public func sessionBegan(touchscreenFrame: CGRect, returnMode: PointerReturn) {
        if home == nil { home = pointerLocation() }
        self.touchscreenFrame = touchscreenFrame
        self.returnMode = returnMode
        setArrowHidden(true)
        arrowHidden = true
        if watchesRealMouse { watchForRealMouse() }
    }

    /// The session ended normally. Sends the pointer home if the return setting says so and home is
    /// on another screen. The arrow stays hidden until the mouse moves, unless the mouse monitor
    /// couldn't be installed: then it comes back now. Does nothing when no session is open.
    public func sessionEnded() {
        if let home, Self.shouldReturn(home: home, touchscreenFrame: touchscreenFrame, mode: returnMode) {
            warp(home)
        }
        home = nil
        // If the mouse monitor couldn't be installed, nothing else would ever bring the arrow back.
        if watchesRealMouse, arrowHidden, mouseMonitor == nil { showArrow() }
    }

    /// The session was cut short: its touchscreen left or turned off, or the screen locked.
    /// Forgets where the pointer was and, if this keeper hid the arrow and hasn't shown it since,
    /// shows it again, even after `sessionEnded()`. Never moves the pointer. Does nothing when
    /// nothing is hidden and no session is open.
    ///
    /// Not for a hand-over to another touchscreen: there, the new touchscreen's `sessionBegan`
    /// keeps home.
    public func sessionCancelled() {
        home = nil
        if arrowHidden { showArrow() }
    }

    /// The mouse or trackpad moved, and Tactile didn't post the movement: a hand has taken the
    /// mouse. Shows the arrow and forgets home, so the pointer is never pulled out from under that
    /// hand. The mouse monitor calls this; tests call it directly.
    func realMouseMoved() {
        home = nil
        showArrow()
    }

    /// Only a pointer that started on another screen goes back.
    static func shouldReturn(home: CGPoint, touchscreenFrame: CGRect, mode: PointerReturn) -> Bool {
        mode == .backWhereItWas && !touchscreenFrame.contains(home)
    }

    /// Whether an event came from Tactile rather than a real mouse or trackpad.
    static func isFromTactile(_ event: CGEvent?, now: TimeInterval) -> Bool {
        if event?.getIntegerValueField(.eventSourceUserData) == EventSender.tag { return true }
        // In case the tag doesn't survive delivery: anything right after one of our own events.
        return now - EventSender.lastPostTime < 0.05
    }

    /// Calls `realMouseMoved()` on the first movement Tactile didn't post itself.
    private func watchForRealMouse() {
        guard mouseMonitor == nil else { return }
        let kinds: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel]
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: kinds) { [weak self] event in
            guard !Self.isFromTactile(event.cgEvent, now: ProcessInfo.processInfo.systemUptime) else { return }
            self?.realMouseMoved()
        }
    }

    /// Shows the arrow and stops watching the mouse, which has nothing left to do.
    private func showArrow() {
        setArrowHidden(false)
        arrowHidden = false
        if let monitor = mouseMonitor { NSEvent.removeMonitor(monitor) }
        mouseMonitor = nil
    }
}
