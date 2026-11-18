import CoreGraphics
import Foundation
import TactileGestures

/// Posts the mouse, scroll, zoom and keyboard events that gestures turn into. Main thread only.
@MainActor
public final class EventSender {

    /// Stored in every event Tactile posts, so Tactile can tell its own events from real input.
    /// Readable from any thread.
    public nonisolated static let tag: Int64 = 0x5441_4354  // "TACT"

    /// When Tactile last posted an event, on the `ProcessInfo.processInfo.systemUptime` clock.
    public internal(set) static var lastPostTime: TimeInterval = 0

    /// Where the pointer is now, in global coordinates with the origin at the top left.
    public static var pointerLocation: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private let deliver: (CGEvent) -> Void
    private var pressCount = 1
    /// The scroll under way, or the momentum after it: how it is posted, and what it carries.
    private var scrolling = ScrollQuantiser(.asMoved)

    /// A sender that posts its events to the system.
    public convenience init() {
        self.init(deliver: { $0.post(tap: .cghidEventTap) })
    }

    /// A sender that hands each finished event to `deliver` instead of posting it.
    public init(deliver: @escaping (CGEvent) -> Void) {
        self.deliver = deliver
    }

    // MARK: - Pointer and buttons

    public func movePointer(to point: CGPoint) {
        postMouse(.mouseMoved, at: point, button: .left, count: 0)
    }

    public func click(at point: CGPoint, count: Int) {
        postMouse(.leftMouseDown, at: point, button: .left, count: count)
        postMouse(.leftMouseUp, at: point, button: .left, count: count)
    }

    public func press(at point: CGPoint, count: Int) {
        pressCount = count
        postMouse(.leftMouseDown, at: point, button: .left, count: count)
    }

    public func drag(to point: CGPoint) {
        postMouse(.leftMouseDragged, at: point, button: .left, count: pressCount)
    }

    public func release(at point: CGPoint) {
        postMouse(.leftMouseUp, at: point, button: .left, count: pressCount)
    }

    public func rightClick(at point: CGPoint) {
        postMouse(.rightMouseDown, at: point, button: .right, count: 1)
        postMouse(.rightMouseUp, at: point, button: .right, count: 1)
    }

    // MARK: - Scrolling

    /// Scrolls by the fingers' movement in points. The content moves the same way.
    ///
    /// `match` is read at `.began` only: it is how this scroll and the momentum after it are
    /// posted, and nothing carries over from the scroll before. As moved, today's posting, unless
    /// the app the scroll begins over needs another (`ScrollMatch.forApp(_:)`).
    public func scroll(by delta: CGVector, phase: GesturePhase, match: ScrollMatch = .asMoved) {
        if phase == .began { scrolling = ScrollQuantiser(match) }
        postScroll(delta, scrollPhase: Self.scrollPhase(phase), momentumPhase: 0)
    }

    /// Coasts after a flick, posted as the scroll before it was.
    public func momentum(by delta: CGVector, phase: GesturePhase) {
        postScroll(delta, scrollPhase: 0, momentumPhase: Self.momentumPhase(phase))
    }

    /// The trackpad's scroll phases (`CGScrollPhase`): began 1, changed 2, ended 4.
    static func scrollPhase(_ phase: GesturePhase) -> Int64 {
        switch phase {
        case .began: return 1
        case .changed: return 2
        case .ended: return 4
        }
    }

    /// The trackpad's momentum phases (`CGMomentumScrollPhase`): begin 1, continue 2, end 3.
    static func momentumPhase(_ phase: GesturePhase) -> Int64 {
        switch phase {
        case .began: return 1
        case .changed: return 2
        case .ended: return 3
        }
    }

    /// Posts whole pixels (whole steps of the scroll's match) and carries the rest, so slow scrolls
    /// still move; an end drops what is left over.
    private func postScroll(_ delta: CGVector, scrollPhase: Int64, momentumPhase: Int64) {
        let isLast = scrollPhase == Self.scrollPhase(.ended) || momentumPhase == Self.momentumPhase(.ended)
        let whole = scrolling.post(delta, isLast: isLast)

        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                  wheel1: Int32(whole.dy), wheel2: Int32(whole.dx), wheel3: 0) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        post(event)
    }

    // MARK: - Zoom and swipes

    /// Posts a trackpad zoom gesture. The gesture event type (29) and its fields are undocumented;
    /// Touch Up has used them since 1.0. Field 132 takes the gesture phase: began 1, changed 2,
    /// ended 4. Touch Up sent the touch phase there instead, so its zooms ended as cancelled.
    public func pinch(by magnification: Double, phase: GesturePhase) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                  mouseCursorPosition: Self.pointerLocation, mouseButton: .left),
              let gestureType = CGEventType(rawValue: 29) else { return }
        event.type = gestureType
        event.flags = []
        for field: UInt32 in [113, 114, 116, 118] {
            if let key = CGEventField(rawValue: field) { event.setDoubleValueField(key, value: magnification) }
        }
        let integers: [(UInt32, Int64)] = [(50, 248), (101, 4), (110, 8), (132, Self.scrollPhase(phase))]
        for (field, value) in integers {
            if let key = CGEventField(rawValue: field) { event.setIntegerValueField(key, value: value) }
        }
        post(event)
    }

    /// Posts a trackpad rotate gesture: `degrees` turned since the previous one, positive
    /// anticlockwise, as `NSEvent.rotation` reads it. Built like `pinch`, the same undocumented
    /// gesture event (type 29), with the rotation subtype in field 110: 5, `kIOHIDEventTypeRotation`
    /// in IOKit's `IOHIDEventTypes.h` (the zoom is 8). Source of the fields: Calf Trail's
    /// `TouchEvents.c`, which Hammerspoon ships for its synthetic gestures
    /// (github.com/Hammerspoon/hammerspoon, extensions/eventtap): type 29, subtype in 0x6E (110),
    /// phase in 0x84 (132), and for subtype 5 the rotation in degrees in 0x72 (114), where subtype
    /// 8 puts the magnification in 0x71 (113). In a `CGEvent` 113 and 114 are one slot. Checked
    /// without posting: AppKit's own `NSEvent(cgEvent:)` reads this event as `.rotate`, with these
    /// degrees and phase. Fields 50 and 101 are copied from `pinch`, unexplained.
    public func rotate(by degrees: Double, phase: GesturePhase) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                  mouseCursorPosition: Self.pointerLocation, mouseButton: .left),
              let gestureType = CGEventType(rawValue: 29) else { return }
        event.type = gestureType
        event.flags = []
        if let key = CGEventField(rawValue: 114) { event.setDoubleValueField(key, value: degrees) }
        let integers: [(UInt32, Int64)] = [(50, 248), (101, 4), (110, 5), (132, Self.scrollPhase(phase))]
        for (field, value) in integers {
            if let key = CGEventField(rawValue: field) { event.setIntegerValueField(key, value: value) }
        }
        post(event)
    }

    /// Posts the Mission Control shortcut for a swipe. Fingers moving left reveal the desktop on
    /// the right, as on a trackpad.
    public func swipe(_ direction: SwipeDirection) {
        let key = Self.keyCode(for: direction)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: isDown) else { continue }
            // The system's own definitions of these shortcuts carry the Fn flag for arrow keys.
            event.flags = [.maskControl, .maskSecondaryFn]
            post(event)
        }
    }

    static func keyCode(for direction: SwipeDirection) -> CGKeyCode {
        switch direction {
        case .left: return 124   // Ctrl+→: the desktop to the right
        case .right: return 123  // Ctrl+←: the desktop to the left
        case .up: return 126     // Ctrl+↑: Mission Control
        case .down: return 125   // Ctrl+↓: App Exposé
        }
    }

    // MARK: - Posting

    private func postMouse(_ type: CGEventType, at point: CGPoint, button: CGMouseButton, count: Int) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: button) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(count))
        post(event)
    }

    private func post(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: Self.tag)
        Self.lastPostTime = ProcessInfo.processInfo.systemUptime
        deliver(event)
    }
}
