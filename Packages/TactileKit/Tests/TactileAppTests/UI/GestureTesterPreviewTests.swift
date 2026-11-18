import Foundation
import Observation
import TactileScreens
import XCTest

@testable import TactileApp

/// The gesture tester on the preview desk, driven by the same four commands the model takes, and the
/// window's own observer following it.
@MainActor
final class GestureTesterPreviewTests: XCTestCase {
    private let ilitek = UIFixtures.ilitek
    private let strip = UIFixtures.strip

    private func displayID(_ name: String, _ model: PreviewModel) throws -> UInt32 {
        try XCTUnwrap(UIFixtures.displayID(named: name, in: model.snapshot))
    }

    func testClosedUntilOpened() {
        XCTAssertNil(PreviewModel(.desk).snapshot.gestureTester)
    }

    func testItOpensForTheMultiTouchILITEKOnItsDisplay() throws {
        let model = PreviewModel(.desk)
        model.perform(.openGestureTester(ilitek))
        let tester = try XCTUnwrap(model.snapshot.gestureTester)
        XCTAssertEqual(tester.touchscreen, ilitek)
        XCTAssertEqual(tester.touchscreenName, "ILITEK-TP")
        XCTAssertEqual(tester.displayID, try displayID("HDMI", model))
        XCTAssertTrue(tester.multiTouch)
        XCTAssertFalse(tester.performsSwipes, "held each time it opens")
        XCTAssertEqual(tester.fingersDown, 2)
        XCTAssertEqual(Set(tester.recent.map(\.kind)), Set(RecognisedGesture.Kind.allCases), "every kind in the feed")
        XCTAssertEqual(tester.recent.map(\.id), tester.recent.map(\.id).sorted(by: >), "newest first, numbers rising")
        for kind in RecognisedGesture.Kind.allCases {
            XCTAssertEqual(tester.seen.first { $0.id == kind }?.count, tester.recent.filter { $0.kind == kind }.count,
                           "\(kind)")
        }
    }

    func testOpeningItForTheStripMovesItThere() throws {
        let model = PreviewModel(.desk)
        model.perform(.openGestureTester(ilitek))
        model.perform(.openGestureTester(strip))
        let tester = try XCTUnwrap(model.snapshot.gestureTester)
        XCTAssertEqual(tester.touchscreen, strip)
        XCTAssertEqual(tester.touchscreenName, "TouchScreen")
        XCTAssertEqual(tester.displayID, try displayID("12.3FHD", model))
        XCTAssertFalse(tester.multiTouch)
        XCTAssertEqual(tester.fingersDown, 1)
        XCTAssertTrue(tester.recent.allSatisfy { $0.fingers <= 1 || $0.kind == .ignored },
                      "one finger's gestures; a second finger only as ignored")
        XCTAssertFalse(tester.recent.contains { $0.kind == .pinch || $0.kind == .swipe })
    }

    func testOpeningTheOneOpenAgainChangesNothing() throws {
        let model = PreviewModel(.desk)
        model.perform(.openGestureTester(ilitek))
        model.perform(.clearGestureTester)
        model.perform(.openGestureTester(ilitek))
        XCTAssertEqual(model.snapshot.gestureTester?.recent, [], "not opened afresh")
    }

    func testTheCommandsDriveIt() throws {
        let model = PreviewModel(.desk)
        model.perform(.setGestureTesterPerformsSwipes(true))
        model.perform(.clearGestureTester)
        XCTAssertNil(model.snapshot.gestureTester, "nothing to change while it is closed")

        model.perform(.openGestureTester(ilitek))
        model.perform(.setGestureTesterPerformsSwipes(true))
        XCTAssertEqual(model.snapshot.gestureTester?.performsSwipes, true)
        model.perform(.clearGestureTester)
        XCTAssertEqual(model.snapshot.gestureTester?.recent, [])
        XCTAssertEqual(model.snapshot.gestureTester?.seen, [])
        XCTAssertEqual(model.snapshot.gestureTester?.performsSwipes, true, "Clear keeps the swipes as they are")
        model.perform(.closeGestureTester)
        XCTAssertNil(model.snapshot.gestureTester)
        model.perform(.openGestureTester(ilitek))
        XCTAssertEqual(model.snapshot.gestureTester?.performsSwipes, false, "held again on opening")
    }

    func testAGestureSeenByHandJoinsTheFeed() throws {
        var desk = PreviewDesk(.desk)
        desk.apply(.openGestureTester(ilitek))
        desk.apply(.clearGestureTester)
        desk.testerSaw(.pinch, fingers: 2, summary: "zoom 1.4×")
        desk.testerSaw(.pinch, fingers: 2, summary: "zoom 0.8×")
        desk.testerFingers(0)
        let tester = try XCTUnwrap(PreviewModel(desk: desk).snapshot.gestureTester)
        XCTAssertEqual(tester.recent.map(\.summary), ["zoom 0.8×", "zoom 1.4×"])
        XCTAssertEqual(tester.seen, [GestureSeenCount(id: .pinch, count: 2)])
        XCTAssertEqual(tester.fingersDown, 0)
    }

    func testTheFeedKeepsForty() throws {
        var desk = PreviewDesk(.desk)
        desk.apply(.openGestureTester(ilitek))
        for _ in 0..<60 { desk.testerSaw(.tap, fingers: 1, summary: "") }
        let tester = try XCTUnwrap(desk.testerSnapshot())
        XCTAssertEqual(tester.recent.count, 40)
        XCTAssertGreaterThan(tester.seen.first { $0.id == .tap }?.count ?? 0, 40, "seen counts them all")
    }

    func testItDoesNotOpenWhereGestureTesterIsDisabled() {
        for variant in [PreviewModel.Variant.nothingPaired, .tactileOff, .accessibilityMissing, .displayUnplugged] {
            let model = PreviewModel(variant)
            model.perform(.openGestureTester(ilitek))
            XCTAssertNil(model.snapshot.gestureTester, "\(variant)")
        }
        let model = PreviewModel(.desk)
        model.perform(.openGestureTester(UIFixtures.oldPanel))
        XCTAssertNil(model.snapshot.gestureTester, "not connected")
    }

    func testItClosesWhenItsTouchscreenCanNoLongerHaveOne() throws {
        let closers: [(String, [AppCommand])] = [
            ("Tactile off", [.setOn(false)]),
            ("switched off", [.setTouchscreenOn(ilitek, false)]),
            ("unpaired", [.unpair(ilitek)]),
            ("a set-up begun", [.beginSetUp(ilitek, .test)]),
            ("a set-up of the other one", [.beginSetUp(strip, .calibrate)]),
        ]
        for (why, commands) in closers {
            let model = PreviewModel(.desk)
            model.perform(.openGestureTester(ilitek))
            for command in commands { model.perform(command) }
            XCTAssertNil(model.snapshot.gestureTester, why)
        }
        let model = PreviewModel(.desk)
        model.perform(.openGestureTester(ilitek))
        model.perform(.setOn(false))
        model.perform(.setOn(true))
        XCTAssertNil(model.snapshot.gestureTester, "closed stays closed")
        model.perform(.openGestureTester(ilitek))
        model.perform(.setOneFinger(ilitek, .alwaysScroll))
        model.perform(.setGestures(ilitek, .oneFingerOnly(keeping: .all)))
        XCTAssertNotNil(model.snapshot.gestureTester, "changing its settings keeps it open")
    }

    // MARK: - The window's observer

    private var told: [GestureTesterSnapshot?] = []

    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    func testTheWindowsObserverFollowsTheTester() async throws {
        let model = PreviewModel(.desk)
        let follower = GestureTesterFollower(model: model) { [unowned self] in self.told.append($0) }
        follower.start()
        XCTAssertEqual(told.count, 1)
        XCTAssertNil(told[0], "told at once: nothing open")

        model.perform(.setDebugLogging(true))
        await settle()
        XCTAssertEqual(told.count, 1, "another change: nothing told")

        model.perform(.openGestureTester(ilitek))
        await settle()
        XCTAssertEqual(told.last??.touchscreen, ilitek)

        model.perform(.setGestureTesterPerformsSwipes(true))
        await settle()
        XCTAssertEqual(told.last??.performsSwipes, true, "each change to it told")
        let count = told.count

        model.perform(.closeGestureTester)
        await settle()
        XCTAssertEqual(told.count, count + 1)
        XCTAssertNil(told.last ?? nil)
        follower.stop()
    }
}
