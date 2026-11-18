import XCTest
@testable import TactileOutput

final class PointerArbiterTests: XCTestCase {

    func testTheFirstTouchscreenTouchedTakesThePointer() {
        let arbiter = PointerArbiter<String>()
        XCTAssertNil(arbiter.owner)
        XCTAssertEqual(arbiter.verdict(for: "a", fingersDown: true), .process)
        XCTAssertEqual(arbiter.owner, "a")
    }

    func testTheOwnersFramesAlwaysProcess() {
        let arbiter = PointerArbiter<String>()
        XCTAssertEqual(arbiter.verdict(for: "a", fingersDown: true), .process)
        XCTAssertEqual(arbiter.verdict(for: "a", fingersDown: true), .process)
        XCTAssertEqual(arbiter.verdict(for: "a", fingersDown: false), .process)
        XCTAssertEqual(arbiter.owner, "a")
    }

    func testAnotherTouchscreenIsIgnoredWhileTheOwnerHasFingersDown() {
        let arbiter = PointerArbiter<String>()
        _ = arbiter.verdict(for: "a", fingersDown: true)
        XCTAssertEqual(arbiter.verdict(for: "b", fingersDown: true), .ignore)
        XCTAssertEqual(arbiter.owner, "a")
    }

    func testIgnoredFingersStayIgnoredUntilTheyLift() {
        let arbiter = PointerArbiter<String>()
        _ = arbiter.verdict(for: "a", fingersDown: true)
        XCTAssertEqual(arbiter.verdict(for: "b", fingersDown: true), .ignore)
        _ = arbiter.verdict(for: "a", fingersDown: false)
        arbiter.sessionEnded(for: "a")
        XCTAssertNil(arbiter.owner)
        XCTAssertEqual(arbiter.verdict(for: "b", fingersDown: true), .ignore)    // the same fingers, still down
        XCTAssertEqual(arbiter.verdict(for: "b", fingersDown: false), .ignore)   // their lift
        XCTAssertEqual(arbiter.verdict(for: "b", fingersDown: true), .process)   // a new touch
        XCTAssertEqual(arbiter.owner, "b")
    }

    func testATouchElsewhereTakesOverOnceTheOwnersFingersAreUp() {
        let arbiter = PointerArbiter<String>()
        _ = arbiter.verdict(for: "a", fingersDown: true)
        _ = arbiter.verdict(for: "a", fingersDown: false)   // lifted; momentum or the double-tap wait
        XCTAssertEqual(arbiter.verdict(for: "b", fingersDown: true), .processAfterCancelling("a"))
        XCTAssertEqual(arbiter.owner, "b")
    }

    func testTheCancelledPreviousOwnersSessionEndChangesNothing() {
        let arbiter = PointerArbiter<String>()
        _ = arbiter.verdict(for: "a", fingersDown: true)
        _ = arbiter.verdict(for: "a", fingersDown: false)
        XCTAssertEqual(arbiter.verdict(for: "b", fingersDown: true), .processAfterCancelling("a"))
        arbiter.sessionEnded(for: "a")   // a's engine, cancelled by the take-over, ends its session
        XCTAssertEqual(arbiter.owner, "b")
        XCTAssertEqual(arbiter.verdict(for: "b", fingersDown: true), .process)
    }

    func testThreeTouchscreens() {
        let arbiter = PointerArbiter<String>()
        XCTAssertEqual(arbiter.verdict(for: "a", fingersDown: true), .process)
        XCTAssertEqual(arbiter.verdict(for: "b", fingersDown: true), .ignore)
        XCTAssertEqual(arbiter.verdict(for: "c", fingersDown: true), .ignore)
        XCTAssertEqual(arbiter.verdict(for: "a", fingersDown: false), .process)
        arbiter.sessionEnded(for: "a")
        XCTAssertEqual(arbiter.verdict(for: "b", fingersDown: false), .ignore)   // b lifts
        XCTAssertEqual(arbiter.verdict(for: "c", fingersDown: true), .ignore)    // c, still down
        XCTAssertEqual(arbiter.verdict(for: "b", fingersDown: true), .process)   // b touches again
        XCTAssertEqual(arbiter.owner, "b")
    }

    func testEndingTheSessionFreesThePointer() {
        let arbiter = PointerArbiter<String>()
        _ = arbiter.verdict(for: "a", fingersDown: true)
        _ = arbiter.verdict(for: "a", fingersDown: false)
        arbiter.sessionEnded(for: "a")
        XCTAssertNil(arbiter.owner)
        XCTAssertEqual(arbiter.verdict(for: "b", fingersDown: true), .process)
    }

    func testEndingAnotherTouchscreensSessionChangesNothing() {
        let arbiter = PointerArbiter<String>()
        _ = arbiter.verdict(for: "a", fingersDown: true)
        arbiter.sessionEnded(for: "b")
        XCTAssertEqual(arbiter.owner, "a")
    }

    /// An unplugged owner can never send the lift or the session end that would free the pointer.
    func testUnpluggingTheOwnerFreesThePointerAtOnce() {
        let arbiter = PointerArbiter<String>()
        _ = arbiter.verdict(for: "a", fingersDown: true)
        arbiter.removed("a")
        XCTAssertNil(arbiter.owner)
        XCTAssertEqual(arbiter.verdict(for: "b", fingersDown: true), .process)
    }

    func testUnpluggingAnIgnoredTouchscreenForgetsItsFingers() {
        let arbiter = PointerArbiter<String>()
        _ = arbiter.verdict(for: "a", fingersDown: true)
        _ = arbiter.verdict(for: "b", fingersDown: true)    // ignored
        arbiter.removed("b")
        arbiter.removed("a")
        XCTAssertEqual(arbiter.verdict(for: "b", fingersDown: true), .process)   // plugged back in, touched
    }

    /// After an engine cancel the session is over but the fingers are still down.
    func testEndingASessionWithSomethingStillOnTheGlassLetsThatTouchscreenGoOn() {
        let arbiter = PointerArbiter<String>()
        _ = arbiter.verdict(for: "a", fingersDown: true)
        arbiter.sessionEnded(for: "a")
        XCTAssertNil(arbiter.owner)
        XCTAssertEqual(arbiter.verdict(for: "a", fingersDown: true), .process)   // its next frame
        XCTAssertEqual(arbiter.owner, "a")
        XCTAssertEqual(arbiter.verdict(for: "b", fingersDown: true), .ignore)    // a's fingers are still down
    }

    func testAFrameWithNoFingersFromANonOwnerIsIgnored() {
        let arbiter = PointerArbiter<String>()
        XCTAssertEqual(arbiter.verdict(for: "b", fingersDown: false), .ignore)
        XCTAssertNil(arbiter.owner)
    }
}
