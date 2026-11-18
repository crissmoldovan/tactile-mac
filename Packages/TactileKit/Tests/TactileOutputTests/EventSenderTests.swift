import AppKit
import CoreGraphics
import XCTest
@testable import TactileOutput

@MainActor
final class EventSenderTests: XCTestCase {

    func testScrollAndMomentumPhasesUseTheTrackpadValues() {
        XCTAssertEqual([.began, .changed, .ended].map(EventSender.scrollPhase), [1, 2, 4])
        XCTAssertEqual([.began, .changed, .ended].map(EventSender.momentumPhase), [1, 2, 3])
    }

    // Whole pixels and the fractions carried, as moved and matched to an app: `ScrollMatchTests`.

    /// Compiles only while the tag is readable off the main actor, as an event tap's callback needs.
    nonisolated func testTheTagIsReadableFromAnyThread() {
        XCTAssertEqual(EventSender.tag, 0x5441_4354)
    }

    func testSwipesPostTheMissionControlArrowKeys() {
        XCTAssertEqual(EventSender.keyCode(for: .left), 124)
        XCTAssertEqual(EventSender.keyCode(for: .right), 123)
        XCTAssertEqual(EventSender.keyCode(for: .up), 126)
        XCTAssertEqual(EventSender.keyCode(for: .down), 125)
    }

    // MARK: - What the sender delivers
    //
    // Every sender below hands its events to an array instead of posting them, so nothing here
    // reaches the system or moves the pointer.

    private let point = CGPoint(x: 300, y: 200)

    func testEveryDeliveredEventCarriesTheTag() {
        var events: [CGEvent] = []
        let sender = EventSender(deliver: { events.append($0) })
        let point = self.point
        let calls: [(String, () -> Void)] = [
            ("movePointer", { sender.movePointer(to: point) }),
            ("click", { sender.click(at: point, count: 1) }),
            ("press", { sender.press(at: point, count: 1) }),
            ("drag", { sender.drag(to: point) }),
            ("release", { sender.release(at: point) }),
            ("rightClick", { sender.rightClick(at: point) }),
            ("scroll", { sender.scroll(by: CGVector(dx: 0, dy: 12), phase: .began) }),
            ("momentum", { sender.momentum(by: CGVector(dx: 0, dy: 12), phase: .began) }),
            ("pinch", { sender.pinch(by: 0.1, phase: .began) }),
            ("swipe", { sender.swipe(.up) }),
        ]
        for (name, call) in calls {
            let before = events.count
            call()
            XCTAssertGreaterThan(events.count, before, "\(name) delivered no event")
        }
        for event in events {
            XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), EventSender.tag)
        }
    }

    func testAClickIsADownAndAnUpAtThePointWithItsCount() {
        var events: [CGEvent] = []
        let sender = EventSender(deliver: { events.append($0) })
        sender.click(at: point, count: 2)

        XCTAssertEqual(events.count, 2)
        guard events.count == 2 else { return }
        XCTAssertEqual(events[0].type, .leftMouseDown)
        XCTAssertEqual(events[1].type, .leftMouseUp)
        for event in events {
            XCTAssertEqual(event.location, point)
            XCTAssertEqual(event.getIntegerValueField(.mouseEventClickState), 2)
        }
    }

    func testPressDragAndReleaseUseTheLeftButton() {
        var events: [CGEvent] = []
        let sender = EventSender(deliver: { events.append($0) })
        sender.press(at: point, count: 1)
        sender.drag(to: CGPoint(x: 340, y: 200))
        sender.release(at: CGPoint(x: 340, y: 200))

        XCTAssertEqual(events.count, 3)
        guard events.count == 3 else { return }
        XCTAssertEqual(events.map(\.type), [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
    }

    func testADragAndReleaseCarryThePressCount() {
        var events: [CGEvent] = []
        let sender = EventSender(deliver: { events.append($0) })
        sender.press(at: point, count: 2)
        sender.drag(to: CGPoint(x: 340, y: 200))
        sender.release(at: CGPoint(x: 340, y: 200))

        XCTAssertEqual(events.map(\.type), [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
        XCTAssertEqual(events.map { $0.getIntegerValueField(.mouseEventClickState) }, [2, 2, 2])
    }

    func testARightClickIsARightDownAndUp() {
        var events: [CGEvent] = []
        let sender = EventSender(deliver: { events.append($0) })
        sender.rightClick(at: point)

        XCTAssertEqual(events.count, 2)
        guard events.count == 2 else { return }
        XCTAssertEqual(events.map(\.type), [.rightMouseDown, .rightMouseUp])
    }

    func testScrollEventsAreContinuousAndCarryTheirPhase() {
        var events: [CGEvent] = []
        let sender = EventSender(deliver: { events.append($0) })
        sender.scroll(by: CGVector(dx: 0, dy: 12), phase: .began)

        XCTAssertEqual(events.count, 1)
        guard events.count == 1 else { return }
        let scroll = events[0]
        XCTAssertEqual(scroll.type, .scrollWheel)
        XCTAssertEqual(scroll.getIntegerValueField(.scrollWheelEventIsContinuous), 1)
        XCTAssertEqual(scroll.getIntegerValueField(.scrollWheelEventScrollPhase), EventSender.scrollPhase(.began))
        XCTAssertEqual(abs(scroll.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)), 12)

        sender.momentum(by: CGVector(dx: 0, dy: 12), phase: .began)

        XCTAssertEqual(events.count, 2)
        guard events.count == 2 else { return }
        let momentum = events[1]
        XCTAssertEqual(momentum.type, .scrollWheel)
        XCTAssertEqual(momentum.getIntegerValueField(.scrollWheelEventMomentumPhase),
                       EventSender.momentumPhase(.began))
    }

    func testHorizontalScrollUsesTheOtherAxis() {
        var events: [CGEvent] = []
        let sender = EventSender(deliver: { events.append($0) })
        sender.scroll(by: CGVector(dx: 12, dy: 0), phase: .began)

        XCTAssertEqual(events.count, 1)
        guard let scroll = events.first else { return }
        XCTAssertEqual(abs(scroll.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)), 12)
        XCTAssertEqual(scroll.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 0)
    }

    func testASwipeIsItsArrowKeyDownAndUpWithControlHeld() {
        var events: [CGEvent] = []
        let sender = EventSender(deliver: { events.append($0) })
        sender.swipe(.up)

        XCTAssertEqual(events.count, 2)
        guard events.count == 2 else { return }
        XCTAssertEqual(events.map(\.type), [.keyDown, .keyUp])
        for event in events {
            XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode), Int64(EventSender.keyCode(for: .up)))
            XCTAssertTrue(event.flags.contains(.maskControl))
        }
    }

    func testARotateDeliversOneTaggedEventPerCall() {
        var events: [CGEvent] = []
        let sender = EventSender(deliver: { events.append($0) })
        for (count, phase) in [GesturePhase.began, .changed, .ended].enumerated() {
            sender.rotate(by: 5, phase: phase)
            XCTAssertEqual(events.count, count + 1, "\(phase)")
        }
        for event in events {
            XCTAssertEqual(event.type.rawValue, 29)      // the gesture event type, as for a pinch
            XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), EventSender.tag)
        }
    }

    /// The rotate event's fields are undocumented. AppKit, converting it in this process as it
    /// converts a posted event in the app that receives it, reads it as a rotate gesture with the
    /// degrees and phase given. Nothing is posted.
    func testAppKitReadsARotateAsARotateGestureWithItsDegreesAndPhase() {
        var events: [CGEvent] = []
        let sender = EventSender(deliver: { events.append($0) })
        sender.rotate(by: 12.5, phase: .began)
        sender.rotate(by: -3.25, phase: .changed)
        sender.rotate(by: 0, phase: .ended)

        let read = events.compactMap(NSEvent.init(cgEvent:))
        XCTAssertEqual(read.count, 3)
        guard read.count == 3 else { return }
        XCTAssertEqual(read.map(\.type), [.rotate, .rotate, .rotate])
        XCTAssertEqual(read.map(\.phase), [.began, .changed, .ended])
        XCTAssertEqual(Double(read[0].rotation), 12.5, accuracy: 1e-4)    // anticlockwise, as given
        XCTAssertEqual(Double(read[1].rotation), -3.25, accuracy: 1e-4)
        XCTAssertEqual(Double(read[2].rotation), 0, accuracy: 1e-4)
    }

    /// The same check for the pinch the rotate is modelled on.
    func testAppKitReadsAPinchAsAMagnifyGestureWithItsChangeAndPhase() {
        var events: [CGEvent] = []
        let sender = EventSender(deliver: { events.append($0) })
        sender.pinch(by: 0.1, phase: .began)
        sender.pinch(by: -0.05, phase: .changed)
        sender.pinch(by: 0, phase: .ended)

        let read = events.compactMap(NSEvent.init(cgEvent:))
        XCTAssertEqual(read.map(\.type), [.magnify, .magnify, .magnify])
        XCTAssertEqual(read.map(\.phase), [.began, .changed, .ended])
        XCTAssertEqual(read.map { Double($0.magnification) }.first ?? 0, 0.1, accuracy: 1e-4)
    }

    func testDeliveringAnEventRecordsWhenItWasPosted() {
        var events: [CGEvent] = []
        let sender = EventSender(deliver: { events.append($0) })
        let before = ProcessInfo.processInfo.systemUptime
        sender.click(at: point, count: 1)

        XCTAssertFalse(events.isEmpty)
        XCTAssertGreaterThanOrEqual(EventSender.lastPostTime, before)
    }
}
