import AppKit
import Foundation
import TactileScreens
import XCTest

@testable import TactileApp

/// The first-run window: a close at quit isn't Not Now; a Set Up… that didn't start brings the
/// window back while the offer stands. An offer names one touchscreen or several; a touchscreen
/// plugged in changes it.
@MainActor
final class FirstRunPresenterTests: XCTestCase {
    // MARK: - The first-run window

    private let bothOffer = FirstRunOffer(touchscreens: [UIFixtures.ilitek, UIFixtures.strip],
                                          names: ["ILITEK-TP", "TouchScreen"])
    private let stripOffer = FirstRunOffer(touchscreens: [UIFixtures.strip], names: ["TouchScreen"])

    func testTheWindowFollowsTheOffer() {
        var presenter = FirstRunPresenter()
        XCTAssertEqual(presenter.told(nil), .nothing)
        XCTAssertEqual(presenter.told(bothOffer), .show(bothOffer))
        XCTAssertEqual(presenter.told(bothOffer), .nothing)
        XCTAssertEqual(presenter.told(stripOffer), .show(stripOffer))
        XCTAssertEqual(presenter.told(nil), .close("the offer was withdrawn"))
        XCTAssertEqual(presenter.told(nil), .nothing)
    }

    func testASetUpThatStartsClosesTheWindow() {
        var presenter = FirstRunPresenter()
        _ = presenter.told(bothOffer)
        XCTAssertEqual(presenter.pressedSetUp(), .awaitSetUp(bothOffer, wait: 1))
        XCTAssertEqual(presenter.told(nil), .nothing, "the set-up began: no offer while it runs; already down")
        XCTAssertEqual(presenter.graceOver(wait: 1), .nothing)
    }

    /// Set Up… during a sub-second display reconfiguration: the model refuses, its offer stands, and
    /// nothing in the snapshot changes. The window comes back.
    func testASetUpThatDidNotStartBringsTheWindowBack() {
        var presenter = FirstRunPresenter()
        _ = presenter.told(bothOffer)
        XCTAssertEqual(presenter.pressedSetUp(), .awaitSetUp(bothOffer, wait: 1))
        XCTAssertEqual(presenter.graceOver(wait: 1), .show(bothOffer))
        XCTAssertEqual(presenter.told(bothOffer), .nothing, "it is up again")
        XCTAssertEqual(presenter.pressedSetUp(), .awaitSetUp(bothOffer, wait: 2), "and can be pressed again")
    }

    func testWhileWaitingAnotherOfferIsShown() {
        var presenter = FirstRunPresenter()
        _ = presenter.told(bothOffer)
        _ = presenter.pressedSetUp()
        XCTAssertEqual(presenter.told(bothOffer), .nothing, "the same offer: still waiting")
        XCTAssertEqual(presenter.told(stripOffer), .show(stripOffer))
        XCTAssertEqual(presenter.graceOver(wait: 1), .nothing)
    }

    /// Each wait is its own: an earlier press's timer never ends a later press's wait.
    func testAnEarlierWaitNeverEndsALaterOne() {
        var presenter = FirstRunPresenter()
        _ = presenter.told(bothOffer)
        XCTAssertEqual(presenter.pressedSetUp(), .awaitSetUp(bothOffer, wait: 1))
        XCTAssertEqual(presenter.told(stripOffer), .show(stripOffer), "another offer, while the first wait runs")
        XCTAssertEqual(presenter.pressedSetUp(), .awaitSetUp(stripOffer, wait: 2))
        XCTAssertEqual(presenter.graceOver(wait: 1), .nothing, "the first press's timer: spent")
        XCTAssertEqual(presenter.graceOver(wait: 2), .show(stripOffer), "the second press's own")
    }

    func testTwoRefusedPressesInARow() {
        var presenter = FirstRunPresenter()
        _ = presenter.told(bothOffer)
        _ = presenter.pressedSetUp()
        XCTAssertEqual(presenter.graceOver(wait: 1), .show(bothOffer))
        XCTAssertEqual(presenter.pressedSetUp(), .awaitSetUp(bothOffer, wait: 2))
        XCTAssertEqual(presenter.graceOver(wait: 1), .nothing, "a stale timer")
        XCTAssertEqual(presenter.graceOver(wait: 2), .show(bothOffer))
    }

    func testNotNow() {
        var presenter = FirstRunPresenter()
        XCTAssertEqual(presenter.pressedNotNow(), .nothing, "no window")
        _ = presenter.told(bothOffer)
        XCTAssertEqual(presenter.pressedNotNow(), .close("Not Now"))
        XCTAssertEqual(presenter.graceOver(wait: 0), .nothing)
        XCTAssertEqual(presenter.told(stripOffer), .show(stripOffer), "a touchscreen plugged in later: an offer of its own")
    }

    /// Only the person closing the window is Not Now: never Tactile quitting, and never a close
    /// nobody asked for.
    func testOnlyThePersonClosingTheWindowIsNotNow() {
        var presenter = FirstRunPresenter()
        _ = presenter.told(bothOffer)
        XCTAssertEqual(presenter.closed(byPerson: true, quitting: false), .notNow(bothOffer))

        _ = presenter.told(stripOffer)
        XCTAssertEqual(presenter.closed(byPerson: false, quitting: true), .quietly("Tactile is quitting"))
        _ = presenter.told(bothOffer)
        XCTAssertEqual(presenter.closed(byPerson: true, quitting: true), .quietly("Tactile is quitting"))
        _ = presenter.told(stripOffer)
        XCTAssertEqual(presenter.closed(byPerson: false, quitting: false), .quietly("closed by macOS"))
        XCTAssertEqual(presenter.closed(byPerson: true, quitting: false), .quietly("no window up"),
                       "nothing shown: nothing to decline")
    }
}
