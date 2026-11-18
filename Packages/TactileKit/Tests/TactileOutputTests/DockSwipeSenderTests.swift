import CoreGraphics
import XCTest
@testable import TactileOutput

/// Every sender here hands its events to an array instead of posting them, and keeps time with a
/// clock and a scheduler the test drives: nothing reaches the system, and nothing waits.
@MainActor
final class DockSwipeSenderTests: XCTestCase {

    // MARK: - The test's surroundings, clock and record

    private struct Surroundings: DockSwipeSurroundings {
        var macOSMajorVersion = 26
        var spaces: Int? = 3
        var isSpaceSwipeEnabled = true
        func spaceCount(forDisplay displayID: UInt32) -> Int? { spaces }
    }

    /// Surroundings that can change under a sender, as the person's settings can.
    private final class Changing: DockSwipeSurroundings {
        var value = Surroundings()
        var macOSMajorVersion: Int { value.macOSMajorVersion }
        var isSpaceSwipeEnabled: Bool { value.isSpaceSwipeEnabled }
        func spaceCount(forDisplay displayID: UInt32) -> Int? { value.spaces }
    }

    /// A clock that moves only when told to, and runs what was scheduled once its time has come,
    /// exactly at its deadline. Work that keeps rescheduling itself fails the test instead of hanging it.
    private final class TestClock {
        var now: TimeInterval
        private var pending: [(at: TimeInterval, order: Int, work: @MainActor () -> Void)] = []
        private var order = 0
        private var runs = 0
        var scheduledCount: Int { pending.count }

        init(now: TimeInterval = 0) {
            self.now = now
        }

        func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
            order += 1
            pending.append((now + delay, order, work))
        }

        @MainActor
        func advance(by seconds: TimeInterval) {
            let end = now + seconds
            while let next = pending.filter({ $0.at <= end }).min(by: { ($0.at, $0.order) < ($1.at, $1.order) }) {
                pending.removeAll { $0.order == next.order }
                runs += 1
                guard runs <= 10_000 else {
                    XCTFail("scheduled work ran more than 10 000 times")
                    pending = []
                    break
                }
                now = max(now, next.at)
                next.work()
            }
            now = end
        }
    }

    private let width = 1512.0   // points: a 14-inch MacBook Pro's display
    /// An event keeps its gesture fields as 32-bit floats: what is read back is the value set,
    /// to about seven digits.
    private let precision = 1e-6
    private let display: UInt32 = 7

    private var delivered: [CGEvent] = []
    private var clock = TestClock()

    override func setUp() {
        super.setUp()
        delivered = []
        clock = TestClock()
    }

    private func makeSender(_ surroundings: DockSwipeSurroundings = Surroundings()) -> DockSwipeSender {
        let clock = self.clock
        return DockSwipeSender(deliver: { [unowned self] in delivered.append($0) }, surroundings: surroundings,
                               clock: { clock.now }, schedule: { clock.schedule(after: $0, $1) })
    }

    @discardableResult
    private func send(_ sender: DockSwipeSender, _ offset: Double, _ phase: SwipeTrackingPhase,
                      axis: SwipeAxis = .horizontal) -> Bool {
        sender.handle(axis: axis, offset: offset, phase: phase, displayID: display, displayWidth: width)
    }

    /// The Dock-control events (type 30) delivered, in order.
    private var dockEvents: [CGEvent] { delivered.filter { $0.type.rawValue == 30 } }
    private var phases: [Int64] { dockEvents.map { $0.integer(132) } }
    private var progresses: [Double] { dockEvents.map { $0.double(124) } }

    /// The Dock's units for one Space, on a display with `spaces` Spaces: n/(n−1).
    private func perSpace(_ spaces: Int) -> Double { spaces <= 1 ? 2 : Double(spaces) / Double(spaces - 1) }
    /// The progress for an offset: one display width plus the 63-point gap is one Space.
    private func progress(_ offset: Double, spaces: Int) -> Double {
        -offset * width / (width + 63) * perSpace(spaces)
    }

    // MARK: - The log

    /// A sender logs nothing until the app asks, by either initialiser: these tests, which never ask,
    /// write nothing under Tactile's log subsystem however many swipes they make.
    func testASenderLogsNothingUnlessAsked() {
        XCTAssertEqual(makeSender().logging, .quiet)
        XCTAssertEqual(DockSwipeSender(deliver: { _ in }, surroundings: Surroundings()).logging, .quiet)
        XCTAssertEqual(DockSwipeLogging.quiet, DockSwipeLogging(swipes: false, events: false))
    }

    // MARK: - A whole swipe

    func testAWholeSwipeIsBeganChangedAndOneEndWithProgressOfTheRightSignAndScale() {
        for spaces in [2, 5] {
            delivered = []
            clock = TestClock()
            let sender = makeSender(Surroundings(spaces: spaces))
            XCTAssertTrue(send(sender, -0.02, .began))
            for offset in [-0.1, -0.2, -0.3] {
                clock.advance(by: 0.01)
                XCTAssertTrue(send(sender, offset, .changed))
            }
            clock.advance(by: 0.01)
            XCTAssertTrue(send(sender, -0.35, .completed(velocity: -0.5)))
            XCTAssertFalse(sender.isOpen)

            XCTAssertEqual(phases, [1, 2, 2, 2, 4], "\(spaces) Spaces")
            let expected = [-0.02, -0.1, -0.2, -0.3, -0.35].map { progress($0, spaces: spaces) }
            XCTAssertEqual(progresses.count, expected.count)
            for (got, want) in zip(progresses, expected) {
                XCTAssertEqual(got, want, accuracy: precision, "\(spaces) Spaces")
                XCTAssertGreaterThan(got, 0, "fingers moving left show the Space on the right")
            }
        }
        // The scale itself, worked by hand: 0.3 × 1512/1575 = 0.288 of a Space; 2 Spaces count
        // one Space as 2, 5 Spaces as 1.25.
        XCTAssertEqual(progress(-0.3, spaces: 2), 0.576, accuracy: precision)
        XCTAssertEqual(progress(-0.3, spaces: 5), 0.36, accuracy: precision)
    }

    func testFingersMovingRightGiveNegativeProgress() {
        let sender = makeSender()
        send(sender, 0.02, .began)
        clock.advance(by: 0.01)
        send(sender, 0.2, .changed)
        clock.advance(by: 0.01)
        send(sender, 0.25, .completed(velocity: 0.4))
        XCTAssertTrue(progresses.allSatisfy { $0 < 0 })
        XCTAssertLessThan(dockEvents.last?.double(129) ?? 0, 0)
    }

    func testProgressIsClampedToOneSpaceEitherWay() {
        let sender = makeSender(Surroundings(spaces: 4))
        send(sender, -0.02, .began)
        clock.advance(by: 0.01)
        send(sender, -1.5, .changed)
        clock.advance(by: 0.01)
        send(sender, 1.5, .cancelled)
        XCTAssertEqual(progresses.count, 3)
        XCTAssertEqual(progresses[1], perSpace(4), accuracy: precision)
        XCTAssertEqual(progresses[2], -perSpace(4), accuracy: precision)
    }

    func testEachDockEventIsFollowedByAnEmptyGestureEvent() {
        let sender = makeSender()
        send(sender, -0.02, .began)
        clock.advance(by: 0.01)
        send(sender, -0.1, .changed)
        clock.advance(by: 0.01)
        send(sender, -0.1, .cancelled)
        XCTAssertEqual(delivered.map(\.type.rawValue), [30, 29, 30, 29, 30, 29])
        for companion in delivered where companion.type.rawValue == 29 {
            for field: UInt32 in [110, 123, 124, 132] { XCTAssertEqual(companion.integer(field), 0, "field \(field)") }
        }
    }

    func testTheFieldsOfADockSwipeAreTheDocksForMacOS12To26() {
        let sender = makeSender()
        send(sender, -0.02, .began)
        clock.advance(by: 0.01)
        send(sender, -0.1, .changed)
        clock.advance(by: 0.01)
        send(sender, -0.4, .completed(velocity: -0.5))
        XCTAssertEqual(dockEvents.count, 3)
        for (event, phase) in zip(dockEvents, [Int64(1), 2, 4]) {
            XCTAssertEqual(event.type.rawValue, 30, "kCGSEventDockControl")
            XCTAssertEqual(event.integer(55), 30, "kCGSEventTypeField")
            XCTAssertEqual(event.integer(110), 23, "kCGEventGestureHIDType: kIOHIDEventTypeDockSwipe")
            XCTAssertEqual(event.integer(123), 1, "kCGEventGestureSwipeMotion: horizontal")
            XCTAssertEqual(event.integer(132), phase, "kCGEventGesturePhase")
            XCTAssertEqual(event.integer(134), phase, "kCGEventGestureSwipeMask, the phase copied")
            XCTAssertEqual(event.integer(138), 3, "kCGEventGestureFlavor: Dock primary")
            // Fields the sender leaves alone are as a new event has them (a
            // new event fills some itself: 41 is the posting process's ID).
            guard let fresh = CGEvent(source: nil) else { return XCTFail("no event") }
            for field: UInt32 in [41, 119, 136, 139] {
                XCTAssertEqual(event.integer(field), fresh.integer(field), "field \(field)")
            }
            // 165 isn't set either: in a Dock swipe it reads back the motion, as 135 overlaps 124.
            XCTAssertEqual(event.integer(165), event.integer(123), "field 165")
            for field: UInt32 in [125, 126] { XCTAssertEqual(event.double(field), fresh.double(field), "field \(field)") }
        }
        // Velocity only on the end.
        XCTAssertEqual(dockEvents[0].double(129), 0)
        XCTAssertEqual(dockEvents[1].double(129), 0)
    }

    // MARK: - The end

    func testCompletedCarriesItsVelocityInProgressPerSecond() {
        let sender = makeSender(Surroundings(spaces: 3))
        send(sender, -0.02, .began)
        clock.advance(by: 0.01)
        send(sender, -0.4, .completed(velocity: -0.5))
        let end = dockEvents.last
        let expected = 0.5 * width / (width + 63) * perSpace(3)   // the offset's scale
        XCTAssertEqual(end?.double(129) ?? 0, expected, accuracy: precision)
        XCTAssertEqual(end?.double(130) ?? 0, expected, accuracy: precision, "the same in Y, as a trackpad sends")
    }

    func testAVeryFastCompletionIsClampedAndOneComingBackSendsNoVelocity() {
        let fast = makeSender()
        send(fast, -0.02, .began)
        send(fast, -0.4, .completed(velocity: -400))
        XCTAssertEqual(dockEvents.last?.double(129), 50, "clamped: a large speed skips the animation")

        delivered = []
        let back = makeSender()
        send(back, -0.02, .began)
        send(back, -0.4, .completed(velocity: 0.01))   // going on left, the fingers drifting back
        XCTAssertEqual(dockEvents.last?.integer(132), 4)
        XCTAssertEqual(dockEvents.last?.double(129), 0, "never a speed against the way it goes")
    }

    func testCancelledGivesTheCancelPhaseAndNoSpeed() {
        let sender = makeSender()
        send(sender, -0.02, .began)
        clock.advance(by: 0.01)
        send(sender, -0.15, .changed)
        clock.advance(by: 0.01)
        XCTAssertTrue(send(sender, -0.1, .cancelled))
        XCTAssertEqual(phases, [1, 2, 8])
        XCTAssertEqual(progresses.last ?? 0, progress(-0.1, spaces: 3), accuracy: precision)
        XCTAssertEqual(dockEvents.last?.double(129), 0)
        XCTAssertEqual(dockEvents.last?.double(130), 0)
        XCTAssertFalse(sender.isOpen)
    }

    func testCloseIfOpenPostsOneCancelledEndAtTheLastPosition() {
        let sender = makeSender()
        sender.closeIfOpen()
        XCTAssertTrue(delivered.isEmpty, "nothing open, nothing posted")

        send(sender, -0.02, .began)
        clock.advance(by: 0.01)
        send(sender, -0.2, .changed)
        XCTAssertTrue(sender.isOpen)
        sender.closeIfOpen()
        sender.closeIfOpen()
        XCTAssertEqual(phases, [1, 2, 8])
        XCTAssertEqual(progresses.last ?? 0, progress(-0.2, spaces: 3), accuracy: precision)
        XCTAssertFalse(sender.isOpen)

        // Its end, closed early, is handled with nothing more.
        XCTAssertTrue(send(sender, -0.3, .completed(velocity: -1)))
        XCTAssertEqual(phases, [1, 2, 8])
    }

    func testChangedOrAnEndWithoutBeganPostNothingAndAreFalse() {
        let sender = makeSender()
        XCTAssertFalse(send(sender, -0.1, .changed))
        XCTAssertFalse(send(sender, -0.1, .completed(velocity: -1)))
        XCTAssertFalse(send(sender, -0.1, .cancelled))
        clock.advance(by: 1)
        XCTAssertTrue(delivered.isEmpty)
        XCTAssertFalse(sender.isOpen)
    }

    func testASecondBeganFirstClosesTheOpenOneAsCancelled() {
        let sender = makeSender()
        send(sender, -0.02, .began)
        clock.advance(by: 0.01)
        send(sender, -0.2, .changed)
        clock.advance(by: 0.01)
        XCTAssertTrue(send(sender, 0.03, .began))
        XCTAssertEqual(phases, [1, 2, 8, 1])
        XCTAssertEqual(progresses[2], progress(-0.2, spaces: 3), accuracy: precision, "the first closes where it was")
        clock.advance(by: 0.01)
        send(sender, 0.1, .cancelled)
        XCTAssertEqual(phases, [1, 2, 8, 1, 8])
    }

    // MARK: - When it can't be followed

    func testEachUnavailabilityGivesNothingAndFalseForEveryPhase() {
        let cases: [(String, Surroundings, SwipeAxis)] = [
            ("vertical", Surroundings(), .vertical),
            ("macOS 27", Surroundings(macOSMajorVersion: 27), .horizontal),
            ("macOS 11", Surroundings(macOSMajorVersion: 11), .horizontal),
            ("no space count", Surroundings(spaces: nil), .horizontal),
            ("no Spaces at all", Surroundings(spaces: 0), .horizontal),
            ("the gesture off", Surroundings(isSpaceSwipeEnabled: false), .horizontal),
        ]
        for (name, surroundings, axis) in cases {
            delivered = []
            let sender = makeSender(surroundings)
            XCTAssertFalse(sender.isAvailable(axis, onDisplay: display), name)
            XCTAssertFalse(send(sender, -0.02, .began, axis: axis), name)
            XCTAssertFalse(sender.isOpen, name)
            XCTAssertFalse(send(sender, -0.1, .changed, axis: axis), name)
            XCTAssertFalse(send(sender, -0.4, .completed(velocity: -1), axis: axis), name)
            XCTAssertFalse(send(sender, -0.4, .cancelled, axis: axis), name)
            sender.closeIfOpen()
            clock.advance(by: 1)
            XCTAssertTrue(delivered.isEmpty, name)
        }
    }

    func testAvailableForHorizontalOnMacOS12To26WithTheGestureOn() {
        for version in [12, 14, 26] {
            XCTAssertTrue(makeSender(Surroundings(macOSMajorVersion: version)).isAvailable(.horizontal), "\(version)")
        }
        XCTAssertFalse(makeSender().isAvailable(.vertical), "vertical never, in this delivery")
        XCTAssertFalse(makeSender(Surroundings(macOSMajorVersion: 27)).isAvailable(.horizontal))
        XCTAssertFalse(makeSender(Surroundings(isSpaceSwipeEnabled: false)).isAvailable(.horizontal))
        // Without a display, the space count can't be asked; with one, it must be known.
        XCTAssertTrue(makeSender(Surroundings(spaces: nil)).isAvailable(.horizontal))
        XCTAssertFalse(makeSender(Surroundings(spaces: nil)).isAvailable(.horizontal, onDisplay: display))
        XCTAssertTrue(makeSender().isAvailable(.horizontal, onDisplay: display))
    }

    func testOneSpaceCountsTwoUnits() {
        let sender = makeSender(Surroundings(spaces: 1))
        send(sender, -0.1, .began)
        XCTAssertEqual(progresses.first ?? 0, progress(-0.1, spaces: 1), accuracy: precision)
        XCTAssertEqual(progress(-0.1, spaces: 1), 0.1 * width / (width + 63) * 2, accuracy: precision)
    }

    func testAnOpenSwipeIsFinishedEvenIfItBecomesUnavailable() {
        let surroundings = Changing()
        let sender = makeSender(surroundings)
        send(sender, -0.02, .began)
        surroundings.value.isSpaceSwipeEnabled = false
        surroundings.value.spaces = nil
        clock.advance(by: 0.01)
        XCTAssertTrue(send(sender, -0.2, .changed))
        clock.advance(by: 0.01)
        XCTAssertTrue(send(sender, -0.4, .completed(velocity: -1)))
        XCTAssertEqual(phases, [1, 2, 4], "decided at began; never cut off mid-swipe")
        XCTAssertFalse(sender.isAvailable(.horizontal))
    }

    // MARK: - Closed early, and the other axis

    func testAfterAnEarlyCloseTheSwipesLaterActionsAreHandledWithNothing() {
        let sender = makeSender()
        XCTAssertTrue(send(sender, -0.02, .began))
        clock.advance(by: 0.01)
        send(sender, -0.2, .changed)
        sender.closeIfOpen()   // the displays changed, or the Mac is going to sleep, fingers still down
        clock.advance(by: 0.01)
        XCTAssertTrue(send(sender, -0.3, .changed), "handled: nothing to post")
        XCTAssertTrue(send(sender, -0.4, .completed(velocity: -1)),
                      "handled: the Dock has slid back, and no shortcut should follow")
        XCTAssertEqual(phases, [1, 2, 8])
        XCTAssertFalse(sender.isOpen)

        XCTAssertTrue(send(sender, -0.02, .began), "the next swipe works normally")
        clock.advance(by: 0.01)
        XCTAssertTrue(send(sender, -0.4, .completed(velocity: -1)))
        XCTAssertEqual(phases, [1, 2, 8, 1, 4])
        XCTAssertFalse(send(sender, -0.4, .cancelled), "that one ended normally: a stray end is refused again")
    }

    func testAfterAnEarlyCloseTheSwipesCancelIsHandledWithNothing() {
        let sender = makeSender()
        send(sender, -0.02, .began)
        sender.closeIfOpen()
        XCTAssertTrue(send(sender, -0.1, .cancelled))
        clock.advance(by: 0.1)
        XCTAssertEqual(phases, [1, 8])
    }

    func testTheEarlyCloseEndsWithTheClosedSwipesOwnEnd() {
        for end in [SwipeTrackingPhase.completed(velocity: -1), .cancelled] {
            delivered = []
            let sender = makeSender()
            send(sender, -0.02, .began)
            sender.closeIfOpen()
            XCTAssertTrue(send(sender, -0.4, end), "the closed swipe's own end: handled")
            XCTAssertFalse(send(sender, -0.1, .changed), "\(end): a changed with no began")
            XCTAssertFalse(send(sender, -0.4, .completed(velocity: -1)), "\(end): a completed with no began")
            XCTAssertEqual(phases, [1, 8])
        }
    }

    /// A swipe that a new `began` closed is remembered as closed early too, whichever swipe's end
    /// comes first; its own end posts nothing and returns true, and the refused swipe's returns false.
    func testASwipeClosedByABeganForTheOtherAxisIsClosedEarly() {
        for closedFirst in [true, false] {
            delivered = []
            let sender = makeSender()
            XCTAssertTrue(send(sender, -0.02, .began))
            XCTAssertFalse(send(sender, -0.02, .began, axis: .vertical), "refused: vertical")
            let ends: [(SwipeAxis, Bool)] = closedFirst ? [(.horizontal, true), (.vertical, false)]
                                                        : [(.vertical, false), (.horizontal, true)]
            for (axis, handled) in ends {
                XCTAssertEqual(send(sender, -0.3, .changed, axis: axis), handled, "\(axis), closed first: \(closedFirst)")
                XCTAssertEqual(send(sender, -0.4, .completed(velocity: -1), axis: axis), handled,
                               "\(axis), closed first: \(closedFirst)")
            }
            clock.advance(by: 0.1)
            XCTAssertEqual(phases, [1, 8], "closed first: \(closedFirst)")
        }
    }

    func testASwipeClosedByAnAcceptedBeganOnTheSameAxisGivesWayToIt() {
        let sender = makeSender()
        send(sender, -0.02, .began)
        XCTAssertTrue(send(sender, 0.02, .began))
        clock.advance(by: 0.01)
        XCTAssertTrue(send(sender, 0.2, .changed), "the new swipe's")
        XCTAssertTrue(send(sender, 0.4, .completed(velocity: 1)))
        XCTAssertEqual(phases, [1, 8, 1, 2, 4])
    }

    func testANewSwipeThatCantBeginForgetsTheEarlyClose() {
        let surroundings = Changing()
        let sender = makeSender(surroundings)
        send(sender, -0.02, .began)
        sender.closeIfOpen()
        surroundings.value.isSpaceSwipeEnabled = false
        XCTAssertFalse(send(sender, -0.02, .began))
        XCTAssertFalse(send(sender, -0.4, .completed(velocity: -1)), "a swipe never begun: the shortcut")
        XCTAssertEqual(phases, [1, 8])
    }

    func testACallForTheOtherAxisFirstClosesTheOpenSwipe() {
        let calls: [(String, SwipeTrackingPhase)] = [
            ("cancelled", .cancelled), ("completed", .completed(velocity: -1)), ("changed", .changed), ("began", .began),
        ]
        for (name, phase) in calls {
            delivered = []
            let sender = makeSender()
            send(sender, -0.02, .began)
            clock.advance(by: 0.01)
            XCTAssertFalse(send(sender, -0.2, phase, axis: .vertical), name)
            XCTAssertFalse(sender.isOpen, name)
            XCTAssertEqual(phases, [1, 8], name)
            XCTAssertEqual(progresses.last ?? 0, progress(-0.02, spaces: 3), accuracy: precision,
                           "\(name): closed at its latest progress")
        }
    }

    // MARK: - Every event

    func testEveryEventCarriesTheTagAndCountsAsTactilesLastPost() {
        let sender = makeSender()
        let before = ProcessInfo.processInfo.systemUptime
        send(sender, -0.02, .began)
        clock.advance(by: 0.01)
        send(sender, -0.2, .changed)
        clock.advance(by: 0.01)
        send(sender, -0.3, .completed(velocity: -1))
        clock.advance(by: 1)   // the repeated end
        send(sender, 0.02, .began)
        sender.closeIfOpen()
        XCTAssertEqual(delivered.count, 12)
        for event in delivered {
            XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), EventSender.tag)
        }
        XCTAssertGreaterThanOrEqual(EventSender.lastPostTime, before)
    }

    // MARK: - The repeated end

    func testTheEndIsDeliveredOnceMoreAfterTheDelay() {
        let sender = makeSender()
        send(sender, -0.02, .began)
        clock.advance(by: 0.01)
        send(sender, -0.4, .completed(velocity: -0.5))
        XCTAssertEqual(phases, [1, 4])
        let end = dockEvents[1]

        clock.advance(by: DockSwipeSender.endRepeatDelay - 0.01)
        XCTAssertEqual(phases, [1, 4], "not yet")
        clock.advance(by: 0.02)
        XCTAssertEqual(phases, [1, 4, 4])
        XCTAssertEqual(delivered.map(\.type.rawValue), [30, 29, 30, 29, 30, 29])
        let again = dockEvents[2]
        for field: UInt32 in [110, 123, 132, 134, 138] { XCTAssertEqual(again.integer(field), end.integer(field)) }
        for field: UInt32 in [124, 129, 130] { XCTAssertEqual(again.double(field), end.double(field)) }

        clock.advance(by: 5)
        XCTAssertEqual(phases, [1, 4, 4], "once only")
        XCTAssertFalse(sender.isOpen)
    }

    func testACancelledEndAndACloseAreRepeatedToo() {
        let cancelled = makeSender()
        send(cancelled, -0.02, .began)
        send(cancelled, -0.03, .cancelled)
        clock.advance(by: 1)
        XCTAssertEqual(phases, [1, 8, 8])

        delivered = []
        let closed = makeSender()
        send(closed, -0.02, .began)
        closed.closeIfOpen()
        clock.advance(by: 1)
        XCTAssertEqual(phases, [1, 8, 8])
    }

    func testTheRepeatIsDroppedWhenANewSwipeHasBegun() {
        let sender = makeSender()
        send(sender, -0.02, .began)
        send(sender, -0.4, .completed(velocity: -0.5))
        clock.advance(by: 0.1)
        send(sender, -0.02, .began)
        clock.advance(by: 1)
        XCTAssertEqual(phases, [1, 4, 1], "no repeat of the first end inside the second swipe")
        XCTAssertTrue(sender.isOpen)
        send(sender, -0.4, .completed(velocity: -0.5))
        clock.advance(by: 1)
        XCTAssertEqual(phases, [1, 4, 1, 4, 4], "the second end is repeated")
    }

    func testTheRepeatStillGoesWhenTheNextSwipeCouldNotBegin() {
        let surroundings = Changing()
        let sender = makeSender(surroundings)
        send(sender, -0.02, .began)
        send(sender, -0.4, .completed(velocity: -0.5))
        surroundings.value.isSpaceSwipeEnabled = false
        clock.advance(by: 0.1)
        XCTAssertFalse(send(sender, -0.02, .began))
        clock.advance(by: 1)
        XCTAssertEqual(phases, [1, 4, 4])
    }

    // MARK: - The rate of changed events

    func testChangedEventsAreAtMostOneEvery8msAndTheLatestPositionFollows() {
        let sender = makeSender()
        send(sender, -0.02, .began)
        clock.advance(by: 0.002)
        XCTAssertTrue(send(sender, -0.03, .changed), "held back, not refused")
        clock.advance(by: 0.002)
        XCTAssertTrue(send(sender, -0.04, .changed))
        XCTAssertEqual(phases, [1], "within 8 ms of the began")

        clock.advance(by: 0.005)   // 9 ms after the began; it went at 8
        XCTAssertEqual(phases, [1, 2])
        XCTAssertEqual(progresses.last ?? 0, progress(-0.04, spaces: 3), accuracy: precision, "only the latest")

        clock.advance(by: 0.01)
        send(sender, -0.05, .changed)
        XCTAssertEqual(phases, [1, 2, 2], "more than 8 ms later: at once")
        clock.advance(by: 0.1)
        XCTAssertEqual(phases, [1, 2, 2], "nothing held back")
    }

    /// On a clock that runs work exactly at its deadline, far from zero, the held-back position
    /// still goes out once.
    func testAHeldBackChangedGoesOutOnAClockFarFromZero() {
        for start in [10.0, 100.0] {
            delivered = []
            clock = TestClock(now: start)
            let sender = makeSender()
            send(sender, -0.02, .began)
            clock.advance(by: 0.002)
            XCTAssertTrue(send(sender, -0.1, .changed))
            clock.advance(by: 0.01)
            XCTAssertEqual(phases, [1, 2], "clock at \(start)")
            XCTAssertEqual(progresses.last ?? 0, progress(-0.1, spaces: 3), accuracy: precision)
        }
    }

    func testAHeldBackPositionGoesOutWithTheEnd() {
        let sender = makeSender()
        send(sender, -0.02, .began)
        clock.advance(by: 0.002)
        send(sender, -0.1, .changed)
        send(sender, -0.12, .completed(velocity: -2))
        XCTAssertEqual(phases, [1, 4])
        XCTAssertEqual(progresses.last ?? 0, progress(-0.12, spaces: 3), accuracy: precision)
        clock.advance(by: 0.006)
        XCTAssertEqual(phases, [1, 4], "the held-back changed is not posted after the end")
    }

    func testCloseIfOpenUsesAHeldBackPosition() {
        let sender = makeSender()
        send(sender, -0.02, .began)
        clock.advance(by: 0.002)
        send(sender, -0.1, .changed)
        sender.closeIfOpen()
        XCTAssertEqual(phases, [1, 8])
        XCTAssertEqual(progresses.last ?? 0, progress(-0.1, spaces: 3), accuracy: precision)
    }

    // MARK: - The person's gesture setting

    /// The decision from the trackpad keys found, domain by domain, without reading any settings.
    func testTheSpaceSwipeGestureIsOnOnlyWhenAKeyFoundSaysSo() {
        let three = "TrackpadThreeFingerHorizSwipeGesture", four = "TrackpadFourFingerHorizSwipeGesture"
        func isOn(_ domains: [[String: Any]]) -> Bool { SpaceSwipeSetting.isOn(foundIn: domains) }
        XCTAssertEqual(SpaceSwipeSetting.keys, [three, four])
        XCTAssertEqual(SpaceSwipeSetting.domains,
                       ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"])
        XCTAssertFalse(isOn([[:], [:]]), "no key anywhere, as on a Mac without a trackpad: the shortcut")
        XCTAssertFalse(isOn([]))
        XCTAssertTrue(isOn([[three: 2], [:]]), "three fingers")
        XCTAssertTrue(isOn([[four: 2], [:]]), "four fingers, three missing")
        XCTAssertTrue(isOn([[three: 1, four: 2], [:]]), "three swipe pages, four switch Spaces")
        XCTAssertFalse(isOn([[three: 1, four: 0], [:]]), "switched off")
        XCTAssertFalse(isOn([[three: 0], [:]]), "three off, four missing")
        XCTAssertTrue(isOn([[:], [three: 2]]), "only the Bluetooth trackpad's settings")
        XCTAssertTrue(isOn([[three: 2], [three: 2]]), "both domains agree")
        XCTAssertTrue(isOn([[three: 1, four: 2], [three: 0, four: 2]]), "both off for three, both on for four")
        XCTAssertFalse(isOn([[three: 0], [three: 2]]), "the domains disagree: unavailable")
        XCTAssertFalse(isOn([[three: 2], [three: 0]]), "the domains disagree, the other way")
        XCTAssertFalse(isOn([[three: 2, four: 2], [three: 0, four: 2]]), "a disagreement on either key")
        XCTAssertFalse(isOn([[three: "2"], [:]]), "not a number: unavailable")
        XCTAssertFalse(isOn([[three: "2", four: 2], [:]]), "not a number, even beside an on")
        XCTAssertFalse(isOn([[four: 2], [four: true]]), "a yes-or-no isn't a gesture setting")
    }

    // MARK: - An event that can't be built

    func testABeganThatCantBeBuiltPostsNothing() {
        let sender = makeSender()
        sender.makeEvent = { nil }
        XCTAssertFalse(send(sender, -0.02, .began))
        XCTAssertFalse(sender.isOpen)
        XCTAssertTrue(delivered.isEmpty)
    }

    /// The end is built before the began is posted, so an end can't be lost to a failure later.
    func testAnEndThatCantBeBuiltFallsBackToTheCancelBuiltBeforeTheBegan() {
        let sender = makeSender()
        XCTAssertTrue(send(sender, -0.02, .began))
        sender.makeEvent = { nil }
        clock.advance(by: 0.01)
        XCTAssertFalse(send(sender, -0.2, .changed), "nothing could be posted for it")
        XCTAssertTrue(sender.isOpen)
        XCTAssertFalse(send(sender, -0.4, .completed(velocity: -1)),
                       "completed, but only a cancel could go: the shortcut should follow")
        XCTAssertEqual(phases, [1, 8])
        XCTAssertFalse(sender.isOpen)
        XCTAssertEqual(delivered.map(\.type.rawValue), [30, 29, 30, 29])
        for event in delivered { XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), EventSender.tag) }
    }
}

private extension CGEvent {
    func integer(_ field: UInt32) -> Int64 {
        CGEventField(rawValue: field).map { getIntegerValueField($0) } ?? -1
    }

    func double(_ field: UInt32) -> Double {
        CGEventField(rawValue: field).map { getDoubleValueField($0) } ?? .nan
    }
}
