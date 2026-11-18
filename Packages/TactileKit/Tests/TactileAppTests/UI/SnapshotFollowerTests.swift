import Foundation
import Observation
import TactileScreens
import XCTest

@testable import TactileApp

/// The set-up screens and the first-run window follow the snapshot through their own observer, not
/// through the menu-bar label: they come down after Cancel even if the label stops updating, and an
/// offer made later is noticed.
@MainActor
final class SnapshotFollowerTests: XCTestCase {
    private var setUps: [SetUpPresentation] = []
    private var offers: [FirstRunOffer?] = []

    private func follower(_ model: any AppModel) -> SnapshotFollower {
        SnapshotFollower(
            model: model,
            showSetUp: { [unowned self] in self.setUps.append($0) },
            showFirstRun: { [unowned self] in self.offers.append($0) })
    }

    /// Lets the observer's re-armed tracking run.
    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    func testTheSetUpScreensFollowTheSnapshot() async throws {
        let model = PreviewModel(.desk)
        let follower = follower(model)
        follower.start()
        XCTAssertEqual(setUps.map(\.change), [.takeDown], "told at once: nothing to show")

        model.perform(.beginSetUp(UIFixtures.ilitek, .calibrate))
        await settle()
        let shown = try XCTUnwrap(setUps.last)
        XCTAssertEqual(shown.change, .show)
        XCTAssertFalse(shown.plan.isEmpty)

        model.touchSetUp()
        await settle()
        XCTAssertEqual(setUps.last?.plan, SetUpScreens.plan(model.snapshot), "each change followed")

        model.perform(.cancelSetUp)
        await settle()
        XCTAssertEqual(setUps.last?.change, .takeDown)
        XCTAssertEqual(setUps.last?.plan, [])
        follower.stop()
    }

    func testNothingIsRepeatedWhenNothingChanges() async {
        let model = PreviewModel(.desk)
        let follower = follower(model)
        follower.start()
        model.perform(.setDebugLogging(true))
        await settle()
        model.perform(.setOneFinger(UIFixtures.ilitek, .alwaysScroll))
        await settle()
        XCTAssertEqual(setUps.count, 1)
        XCTAssertEqual(offers.count, 1)
        follower.stop()
    }

    /// The model offers set-up only once Accessibility is granted: the offer comes after launch, and
    /// the first-run window is asked for once.
    func testAnOfferMadeLaterIsShownOnce() async {
        var desk = PreviewDesk(.nothingPaired)
        desk.hasAccessibility = false
        let model = PreviewModel(desk: desk)
        let follower = follower(model)
        follower.start()
        XCTAssertEqual(offers, [nil])

        model.perform(.askForAccessibility)
        await settle()
        let both = FirstRunOffer(touchscreens: [UIFixtures.ilitek, UIFixtures.strip], names: ["ILITEK-TP", "TouchScreen"])
        XCTAssertEqual(offers, [nil, both])
        model.perform(.setDebugLogging(true))
        await settle()
        XCTAssertEqual(offers.count, 2, "asked for once")

        model.perform(.declineSetUp(UIFixtures.ilitek))
        await settle()
        XCTAssertEqual(offers.last, FirstRunOffer(touchscreens: [UIFixtures.strip], names: ["TouchScreen"]))
        follower.stop()
    }

    /// Set Up… begins set-up mode: the offer goes while the mode is on, and the overview is shown;
    /// Finish takes the screens down, and offers neither touchscreen again.
    func testSetUpModeIsFollowedAndTakesTheOfferAway() async throws {
        let model = PreviewModel(.nothingPaired)
        let follower = follower(model)
        follower.start()
        let offer = try XCTUnwrap(offers.last ?? nil)
        model.perform(offer.setUpCommand)
        await settle()
        XCTAssertEqual(offers.last, .some(nil))
        let shown = try XCTUnwrap(setUps.last)
        XCTAssertEqual(shown.change, .show)
        XCTAssertEqual(shown.plan.count, model.snapshot.displays.count)
        model.perform(.cancelSetUp)
        await settle()
        XCTAssertEqual(setUps.last?.change, .takeDown)
        XCTAssertEqual(offers.last, .some(nil), "leaving by Finish marks both offered")
        follower.stop()
    }

    /// The model keeps its offer through a display reconfiguration, with `canBeSetUp` false for that
    /// moment (the pane's button disabled). The first-run window is told the offer once: it never
    /// sees a nil in between, so it isn't put up again after every wake or display change.
    func testAnOfferKeptThroughAReconfigurationIsShownOnce() async {
        let offered = UIFixtures.snapshot(.nothingPaired)
        XCTAssertEqual(offered.offerSetUpTo, [UIFixtures.ilitek, UIFixtures.strip])
        let both = FirstRunOffer(touchscreens: [UIFixtures.ilitek, UIFixtures.strip], names: ["ILITEK-TP", "TouchScreen"])
        let model = SnapshotModel(offered)
        let follower = follower(model)
        follower.start()
        XCTAssertEqual(offers, [both])

        var reconfiguring = offered
        for index in reconfiguring.touchscreens.indices { reconfiguring.touchscreens[index].canBeSetUp = false }
        model.snapshot = reconfiguring
        await settle()
        model.snapshot = offered
        await settle()
        XCTAssertEqual(offers, [both], "told once, no nil")
        follower.stop()
    }

    func testStartingTwiceFollowsOnce() async {
        let model = PreviewModel(.desk)
        let follower = follower(model)
        follower.start()
        follower.start()
        model.perform(.beginSetUp(UIFixtures.ilitek, .test))
        await settle()
        XCTAssertEqual(setUps.map(\.change), [.takeDown, .show])
        follower.stop()
    }
}

/// A model whose snapshot a test sets directly.
@MainActor
@Observable
private final class SnapshotModel: AppModel {
    var snapshot: AppSnapshot
    init(_ snapshot: AppSnapshot) { self.snapshot = snapshot }
    func perform(_ command: AppCommand) {}
}
