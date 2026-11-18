// Set-up mode's session on its own, pure: every row of the plan's table, the answer rule across
// touchscreens, what is connected changing, its time limit, its log lines, and hostile input.

import CoreGraphics
import Foundation
@testable import TactileApp
import TactileReading
import TactileScreens
import XCTest

private typealias Desk = SetUpDesk
private typealias Driver = SessionDriver

private let ilitek = SetUpDesk.ilitekID
private let strip = SetUpDesk.stripID
private let odd = SessionDesk.oddID

/// The corners step as a flow starts: the first target, no problem.
private func corners(on display: UInt32) -> SetUpStep {
    .corners(display: display, target: Calibration.targets[0], index: 0, problem: nil)
}

final class SetUpSessionTests: XCTestCase {

    // MARK: - The table, row by row

    func testItBeginsChoosingWithEveryCardAndLine() throws {
        let driver = try Driver()
        XCTAssertEqual(driver.snapshot, SetUpModeSnapshot(
            stage: .choosing, displays: SessionDesk.cards, touchscreens: SessionDesk.scene.touchscreens.map(\.line),
            justSetUp: nil, notice: nil))
        XCTAssertNil(driver.session.flow)
        XCTAssertFalse(driver.session.hasEnded)
    }

    func testChoosingThenAnAnswerFromOneThatCanBeSetUpIsTouchedFirst() throws {
        var driver = try Driver()
        XCTAssertEqual(driver.touch(ilitek, at: 1.2), [.touchedFirst(touchscreen: ilitek, name: "ILITEK-TP")])
        XCTAssertEqual(driver.stage, .touchedFirst(touchscreen: ilitek, name: "ILITEK-TP"))
    }

    func testChoosingThenAnAnswerFromOneThatCannotIsANotice() throws {
        var driver = try Driver()
        XCTAssertEqual(driver.touch(odd, at: 1.2), [.cannotBeSetUp(touchscreen: odd, name: "Panel")])
        XCTAssertEqual(driver.stage, .choosing, "the stage stays")
        XCTAssertEqual(driver.snapshot.notice, .cannotBeSetUp(touchscreen: odd, name: "Panel"))

        // In the other stages that take answers too, and the notice goes at the next stage change.
        driver.choose(3, at: 2)
        XCTAssertNil(driver.snapshot.notice, "a stage change")
        driver.touch(odd, at: 2.5)
        XCTAssertEqual(driver.stage, .waitingForTouch(display: 3))
        XCTAssertEqual(driver.snapshot.notice, .cannotBeSetUp(touchscreen: odd, name: "Panel"))
        driver.back(at: 3)
        driver.touch(ilitek, at: 3.5)
        driver.touch(odd, at: 4)
        XCTAssertEqual(driver.stage, .touchedFirst(touchscreen: ilitek, name: "ILITEK-TP"))
        XCTAssertEqual(driver.snapshot.notice, .cannotBeSetUp(touchscreen: odd, name: "Panel"))
    }

    func testChoosingThenAClickIsWaitingForATouch() throws {
        var driver = try Driver()
        XCTAssertEqual(driver.choose(3, at: 0.5), [.chose(display: 3, name: "HDMI")])
        XCTAssertEqual(driver.stage, .waitingForTouch(display: 3))
        XCTAssertEqual(driver.choose(99, at: 0.6), [], "a display with no card")
        XCTAssertEqual(driver.choose(Desk.builtIn.displayID, at: 0.7), [], "the built-in display has no card")
        XCTAssertEqual(driver.stage, .waitingForTouch(display: 3))
    }

    func testWaitingForATouchThenAnAnswerStartsAFullFlowThere() throws {
        var driver = try Driver()
        driver.choose(3, at: 1)
        let events = driver.touch(ilitek, at: 1.5)
        XCTAssertEqual(events.first, .answered(touchscreen: ilitek, name: "ILITEK-TP", displayName: "HDMI"))
        guard case .flowStarted(let start)? = events.last, events.count == 2 else { return XCTFail("\(events)") }
        XCTAssertEqual(start.touchscreen, ilitek)
        XCTAssertEqual(start.purpose, .full)
        XCTAssertEqual(start.candidates, [Desk.hdmi])
        XCTAssertEqual(start.allDisplays, Desk.all)
        XCTAssertEqual(start.reportedSizeMM, Desk.ilitekGlass)
        XCTAssertEqual(start.currentDiagonal, 23.8)
        XCTAssertNil(start.current)
        XCTAssertEqual(driver.stage, .running)
        XCTAssertEqual(driver.step, corners(on: 3))
        XCTAssertEqual(driver.session.flow?.snapshot.touchscreen, ilitek)
    }

    func testWaitingForATouchThenAnotherClickMovesIt() throws {
        var driver = try Driver()
        driver.choose(3, at: 1)
        XCTAssertEqual(driver.choose(4, at: 2), [.chose(display: 4, name: "12.3FHD")])
        XCTAssertEqual(driver.stage, .waitingForTouch(display: 4))
        XCTAssertEqual(driver.choose(4, at: 3), [], "the same one again: nothing")
    }

    func testBackFromWaitingOrTouchedFirstIsChoosing() throws {
        var driver = try Driver()
        driver.choose(3, at: 1)
        XCTAssertEqual(driver.back(at: 2), [.backToTheScreens(.back)])
        XCTAssertEqual(driver.stage, .choosing)
        driver.touch(strip, at: 3)
        XCTAssertEqual(driver.stage, .touchedFirst(touchscreen: strip, name: "TouchScreen"))
        XCTAssertEqual(driver.back(at: 4), [.backToTheScreens(.back)])
        XCTAssertEqual(driver.stage, .choosing)
        XCTAssertEqual(driver.back(at: 5), [], "nothing to go back from")
    }

    func testTouchedFirstThenAClickStartsAFullFlowThere() throws {
        var driver = try Driver()
        driver.touch(ilitek, at: 1.2)
        let events = driver.choose(5, at: 2)
        XCTAssertEqual(events.first, .chose(display: 5, name: "Display"))
        guard case .flowStarted(let start)? = events.last, events.count == 2 else { return XCTFail("\(events)") }
        XCTAssertEqual(start.touchscreen, ilitek)
        XCTAssertEqual(start.candidates, [Desk.display])
        XCTAssertEqual(driver.stage, .running)
        XCTAssertEqual(driver.step, corners(on: 5))
    }

    func testTouchedFirstThenAnotherTouchscreensAnswerMovesIt() throws {
        var driver = try Driver()
        driver.touch(ilitek, at: 1.2)
        XCTAssertEqual(driver.touch(strip, at: 2), [.touchedFirst(touchscreen: strip, name: "TouchScreen")])
        XCTAssertEqual(driver.stage, .touchedFirst(touchscreen: strip, name: "TouchScreen"))
        XCTAssertEqual(driver.touch(strip, at: 3), [], "the same one again: nothing")
        XCTAssertEqual(driver.stage, .touchedFirst(touchscreen: strip, name: "TouchScreen"))
    }

    func testACardsTestRunsATestFlowInTheMode() throws {
        var driver = try Driver()
        let events = driver.call { $0.begin(.test, of: strip, at: Driver.time(1)) }
        guard case .flowStarted(let start)? = events.first, events.count == 1 else { return XCTFail("\(events)") }
        XCTAssertEqual(start.purpose, .test)
        XCTAssertEqual(start.candidates, [Desk.strip])
        XCTAssertEqual(driver.stage, .running)
        XCTAssertEqual(driver.step, .check(display: 4))

        // Its Done stores nothing, and the overview is back.
        XCTAssertEqual(driver.done(at: 2), [
            .flowFinished(touchscreen: strip, name: "TouchScreen", purpose: .test, outcome: nil),
            .backToTheScreens(.tested(name: "TouchScreen")),
        ])
        XCTAssertEqual(driver.stage, .choosing)
        XCTAssertNil(driver.snapshot.justSetUp)

        // Calibrate, from a pane, runs in the mode too.
        driver.call { $0.begin(.calibrate, of: strip, at: Driver.time(3)) }
        XCTAssertEqual(driver.step, corners(on: 4))
        driver.back(at: 4)

        // Not for one that isn't paired, or can't be set up; never a full one; and not over a flow.
        XCTAssertEqual(driver.call { $0.begin(.test, of: ilitek, at: Driver.time(5)) }, [])
        XCTAssertEqual(driver.call { $0.begin(.test, of: odd, at: Driver.time(5)) }, [])
        XCTAssertEqual(driver.call { $0.begin(.full, of: strip, at: Driver.time(5)) }, [])
        XCTAssertEqual(driver.stage, .choosing)
        driver.call { $0.begin(.test, of: strip, at: Driver.time(6)) }
        XCTAssertEqual(driver.call { $0.begin(.calibrate, of: strip, at: Driver.time(7)) }, [])
        XCTAssertEqual(driver.session.flow?.snapshot.purpose, .test)
    }

    func testDoneStoresTheOutcomeAndReturnsToTheOverview() throws {
        var driver = try Driver()
        let orientation = Orientation(quarterTurns: 2, isFlipped: false)
        driver.chooseAndTouch(3, ilitek, at: 1)  // the flow starts as the touch lifts, at 1.6
        driver.taps(Desk.cornerTaps(on: Desk.hdmi, orientation: orientation, rect: Desk.offCentre), ilitek, from: 3)
        guard case .size? = driver.step else { return XCTFail("\(String(describing: driver.step))") }
        XCTAssertEqual(driver.confirmSize(23.8, at: 7), [])
        XCTAssertEqual(driver.step, .check(display: 3))
        XCTAssertEqual(driver.done(at: 7.1), [], "too soon after the check appeared")
        let events = driver.done(at: 7.6)
        guard case .flowFinished(ilitek, "ILITEK-TP", .full, let outcome?)? = events.first else {
            return XCTFail("\(events)")
        }
        XCTAssertEqual(outcome.display, DisplayIdentity(Desk.hdmi))
        XCTAssertEqual(outcome.orientation, orientation)
        XCTAssertEqual(outcome.diagonalInches, 23.8)
        XCTAssertEqual(events.last, .backToTheScreens(.done(name: "ILITEK-TP", displayName: "HDMI")))
        XCTAssertEqual(driver.stage, .choosing)
        XCTAssertEqual(driver.snapshot.justSetUp, ilitek)
        XCTAssertNil(driver.snapshot.notice)
        XCTAssertNil(driver.session.flow)
        XCTAssertEqual(driver.stored.count, 1, "stored once, by Done")
    }

    func testAFlowThatFinishesWithNothingReturnsWithTheMatchingNotice() throws {
        // Back.
        var driver = try Driver()
        driver.chooseAndTouch(3, ilitek, at: 1)
        XCTAssertEqual(driver.back(at: 3), [
            .flowFinished(touchscreen: ilitek, name: "ILITEK-TP", purpose: .full, outcome: nil),
            .backToTheScreens(.back),
        ])
        XCTAssertEqual(driver.stage, .choosing)
        XCTAssertNil(driver.snapshot.notice)

        // Its display gone.
        driver.chooseAndTouch(3, ilitek, at: 4)
        let withoutHDMI = SessionDesk.scene {
            $0.displays.removeAll { $0.displayID == 3 }
            $0.cards.removeAll { $0.id == 3 }
        }
        XCTAssertEqual(driver.scene(withoutHDMI, at: 6), [
            .flowFinished(touchscreen: ilitek, name: "ILITEK-TP", purpose: .full, outcome: nil),
            .backToTheScreens(.displayGone(name: "HDMI")),
        ])
        XCTAssertEqual(driver.snapshot.notice, .displayGone(name: "HDMI"))
        XCTAssertEqual(driver.snapshot.displays.map(\.id), [5, 4, 2], "the card gone")

        // The touchscreen gone.
        driver.scene(SessionDesk.scene, at: 7)
        driver.chooseAndTouch(5, ilitek, at: 8)
        let withoutILITEK = SessionDesk.scene { $0.touchscreens.removeAll { $0.id == ilitek } }
        XCTAssertEqual(driver.scene(withoutILITEK, at: 10).last, .backToTheScreens(.touchscreenGone(name: "ILITEK-TP")))
        XCTAssertEqual(driver.snapshot.notice, .touchscreenGone(name: "ILITEK-TP"))
        XCTAssertEqual(driver.snapshot.touchscreens.map(\.id), [strip, odd], "its line gone")

        // The touchscreen still there, but no longer one that can be set up.
        driver.scene(SessionDesk.scene, at: 11)
        driver.chooseAndTouch(5, ilitek, at: 12)
        let unreadable = SessionDesk.scene { $0.touchscreens[0].line.state = .cannotBeSetUp }
        XCTAssertEqual(driver.scene(unreadable, at: 14).last, .backToTheScreens(.cannotBeSetUp(name: "ILITEK-TP")))
        XCTAssertEqual(driver.snapshot.notice, .cannotBeSetUp(touchscreen: ilitek, name: "ILITEK-TP"))

        XCTAssertEqual(driver.stored, [], "nothing stored by any of them")
        XCTAssertNil(driver.ending, "the mode goes on")
    }

    func testAFlowsOwnTimeLimitReturnsToTheOverviewWhileTheModeHasInput() throws {
        var driver = try Driver()
        driver.chooseAndTouch(3, ilitek, at: 1)  // the flow's last input: its start, as the touch lifts at 1.6
        driver.touch(strip, at: 60)  // input for the mode, nothing for the flow
        for k in 61...122 { driver.tick(Double(k)) }
        XCTAssertEqual(driver.stage, .choosing, "the flow's two minutes are up")
        XCTAssertTrue(driver.events.contains(.backToTheScreens(.flowTimedOut)))
        XCTAssertNil(driver.ending, "the mode's are not")
        for k in 123...181 { driver.tick(Double(k)) }
        guard case .ended(.timedOut, _, _)? = driver.ending else { return XCTFail("\(driver.events)") }
    }

    func testFinishEndsTheModeAtEveryStageStoringNothing() throws {
        for (name, reach) in Self.stages {
            var driver = try Driver()
            reach(&driver)
            let before = driver.stored
            let events = driver.finish(at: driver.latest + 0.5)
            XCTAssertEqual(events, [.ended(.finished, markOffered: [ilitek], setUp: [])], name)
            XCTAssertTrue(driver.session.hasEnded, name)
            XCTAssertNil(driver.session.flow, name)
            XCTAssertEqual(driver.stored, before, "\(name): nothing more stored")
        }
    }

    func testTwoMinutesWithoutInputEndTheModeAtEveryStage() throws {
        for (name, reach) in Self.stages {
            var driver = try Driver()
            reach(&driver)
            let from = driver.latest
            var k = 1
            while driver.ending == nil, k < 1300 {
                driver.tick(from + Double(k) / 10)
                k += 1
            }
            guard case .ended(.timedOut, let marked, [])? = driver.ending else {
                return XCTFail("\(name): \(driver.events)")
            }
            XCTAssertEqual(marked, [ilitek], name)
            XCTAssertLessThanOrEqual(Double(k) / 10, SetUpFlow.idleTimeout + 0.2, "\(name): within two minutes of the last input")
            XCTAssertEqual(driver.stored, [], name)
        }
    }

    func testAnInterruptionEndsTheModeMarkingNothing() throws {
        for (name, reach) in Self.stages {
            var driver = try Driver()
            reach(&driver)
            XCTAssertEqual(driver.call { $0.interrupt("the session isn't active") },
                           [.ended(.interrupted("the session isn't active"), markOffered: [], setUp: [])], name)
            XCTAssertNil(driver.session.flow, name)
        }
    }

    /// Each stage the mode can be in, reached from its beginning.
    private static let stages: [(String, (inout Driver) -> Void)] = [
        ("choosing", { _ in }),
        ("waiting for a touch", { $0.choose(3, at: 1) }),
        ("touched first", { $0.touch(ilitek, at: 1.2) }),
        ("corners", { $0.chooseAndTouch(3, ilitek, at: 1) }),
        ("size", {
            $0.chooseAndTouch(3, ilitek, at: 1)
            $0.taps(Desk.cornerTaps(on: Desk.hdmi), ilitek, from: 3)
        }),
        ("check", {
            $0.chooseAndTouch(3, ilitek, at: 1)
            $0.taps(Desk.cornerTaps(on: Desk.hdmi), ilitek, from: 3)
            $0.confirmSize(nil, at: 7)
        }),
        ("a test", { $0.begin(.test, of: strip, at: 1) }),
    ]

    // MARK: - The answer rule

    /// Review Focus 1: both touchscreens touched at once. The first to lift answers; the other's
    /// touch is ignored with all its fingers, even when it lifts later.
    func testTheFirstAnswerToLiftWins() throws {
        for (first, second) in [(ilitek, strip), (strip, ilitek)] {
            var driver = try Driver()
            driver.choose(3, at: 1)
            driver.frame(2.0, first, [Contact(id: 1, position: CGPoint(x: 0.5, y: 0.5))])
            driver.frame(2.02, second, [Contact(id: 1, position: CGPoint(x: 0.5, y: 0.5))])
            driver.frame(2.1, second, [Contact(id: 1, position: CGPoint(x: 0.5, y: 0.5))])
            driver.lift(2.1, first)
            XCTAssertEqual(driver.session.flow?.snapshot.touchscreen, first, "\(first) lifted first")
            XCTAssertEqual(driver.step, corners(on: 3), "on the display chosen, whichever touchscreen it is")
            XCTAssertEqual(driver.lift(2.2, second), [], "the other's touch answers nothing")
            XCTAssertEqual(driver.session.flow?.snapshot.touchscreen, first)
        }

        // In the overview: the first is touched first, the other ignored.
        var driver = try Driver()
        driver.frame(2.0, ilitek, [Contact(id: 1, position: CGPoint(x: 0.5, y: 0.5))])
        driver.frame(2.0, strip, [Contact(id: 1, position: CGPoint(x: 0.5, y: 0.5))])
        driver.lift(2.1, strip)
        driver.lift(2.15, ilitek)
        XCTAssertEqual(driver.stage, .touchedFirst(touchscreen: strip, name: "TouchScreen"))
    }

    /// Review Focus 2: a finger already resting when the mode begins.
    func testAFingerRestingWhenTheModeBeginsIsNoAnswer() throws {
        // The model hands its latest frame straight away, timed before the start.
        var driver = try Driver()
        driver.frame(-0.2, ilitek, [Contact(id: 4, position: CGPoint(x: 0.5, y: 0.5))])
        for k in 1...20 { driver.frame(Double(k) / 10, ilitek, [Contact(id: 4, position: CGPoint(x: 0.5, y: 0.5))]) }
        XCTAssertEqual(driver.lift(2.1, ilitek), [], "it lifts: no answer")
        XCTAssertEqual(driver.stage, .choosing)
        driver.touch(ilitek, at: 2.5)
        XCTAssertEqual(driver.stage, .touchedFirst(touchscreen: ilitek, name: "ILITEK-TP"), "landing again: an answer")

        // A panel that says nothing while a finger rests: its first frame comes in the first second.
        driver = try Driver()
        driver.touch(ilitek, at: 0.5, hold: 0.6)
        XCTAssertEqual(driver.stage, .choosing)
        driver.touch(ilitek, at: 1.3)
        XCTAssertEqual(driver.stage, .touchedFirst(touchscreen: ilitek, name: "ILITEK-TP"))
    }

    /// Review Focus 2: fingers down when a stage changes are no answer until they lift and land again.
    func testFingersDownWhenTheStageChangesAreNoAnswer() throws {
        var driver = try Driver()
        driver.frame(2.0, ilitek, [Contact(id: 1, position: CGPoint(x: 0.5, y: 0.5))])
        driver.choose(3, at: 2.1)  // the click while the finger is down
        XCTAssertEqual(driver.lift(2.3, ilitek), [])
        XCTAssertEqual(driver.stage, .waitingForTouch(display: 3))
        driver.touch(ilitek, at: 2.6)
        XCTAssertEqual(driver.stage, .running)

        // A finger resting when a flow ends (Done with the mouse, a finger on the glass in the check).
        driver = try Driver()
        driver.chooseAndTouch(3, ilitek, at: 1)
        driver.taps(Desk.cornerTaps(on: Desk.hdmi), ilitek, from: 3)
        driver.confirmSize(nil, at: 7)
        driver.frame(7.2, ilitek, [Contact(id: 1, position: CGPoint(x: 0.5, y: 0.5))])
        driver.done(at: 7.8)
        XCTAssertEqual(driver.stage, .choosing)
        XCTAssertEqual(driver.lift(8.5, ilitek), [], "lifting after the flow ended: no answer")
        XCTAssertEqual(driver.stage, .choosing)

        // The other touchscreen's finger resting through a flow.
        driver = try Driver()
        driver.chooseAndTouch(3, ilitek, at: 1)
        driver.frame(3, strip, [Contact(id: 1, position: CGPoint(x: 0.5, y: 0.5))])
        driver.back(at: 4)
        XCTAssertEqual(driver.lift(5, strip), [])
        XCTAssertEqual(driver.stage, .choosing)
    }

    func testALandingTooSoonAfterAChangeIsNoAnswer() throws {
        var driver = try Driver()
        driver.choose(3, at: 2)
        driver.touch(ilitek, at: 2.3)  // 0.3 s after the click: meant for what was shown before
        XCTAssertEqual(driver.stage, .waitingForTouch(display: 3))
        driver.touch(ilitek, at: 2.5)
        XCTAssertEqual(driver.stage, .running, "0.5 s after")

        // A landing timed before the latest change, arriving after it.
        driver = try Driver()
        driver.choose(3, at: 3)
        driver.frame(2.9, ilitek, [Contact(id: 1, position: CGPoint(x: 0.5, y: 0.5))])
        driver.lift(3.5, ilitek)
        XCTAssertEqual(driver.stage, .waitingForTouch(display: 3))

        // Or not timed at all.
        driver.call { $0.handle(ContactFrame(time: .nan, contacts: [Contact(id: 1, position: .zero)]), from: ilitek) }
        driver.call { $0.handle(ContactFrame(time: .nan, contacts: []), from: ilitek) }
        XCTAssertEqual(driver.stage, .waitingForTouch(display: 3))
    }

    func testAPalmAHandOrThreeFingersAnswerNothingTwoFingersDo() throws {
        let palm = [Contact(id: 1, position: CGPoint(x: 0.5, y: 0.5), isConfident: false)]
        let palmLate = [Contact(id: 1, position: CGPoint(x: 0.5, y: 0.5), isConfident: true)]
        func contacts(_ count: Int) -> [Contact] {
            (1...count).map { Contact(id: $0, position: CGPoint(x: 0.3 + Double($0) / 20, y: 0.5)) }
        }
        let touches: [(String, [[Contact]], Bool)] = [
            ("a palm", [palm, palm], false),
            ("a palm the panel recognises late", [palmLate, palm, palmLate], false),
            ("three fingers", [contacts(3)], false),
            ("a hand arriving over several frames", [contacts(1), contacts(3), contacts(5), contacts(1)], false),
            ("two fingers", [contacts(2)], true),
            ("one finger", [contacts(1)], true),
        ]
        for (name, frames, answers) in touches {
            var driver = try Driver()
            driver.choose(3, at: 1)
            for (i, contacts) in frames.enumerated() { driver.frame(2 + Double(i) / 100, ilitek, contacts) }
            driver.lift(2.2, ilitek)
            XCTAssertEqual(driver.stage, answers ? .running : .waitingForTouch(display: 3), name)
        }
    }

    func testALiftThatNeverComesLosesOneTouchNeverMakesOneUp() throws {
        var driver = try Driver()
        driver.choose(3, at: 1)
        driver.frame(2, ilitek, [Contact(id: 1, position: CGPoint(x: 0.5, y: 0.5), isConfident: false)])  // a palm
        // Its lift is lost; the next touch is taken for the same fingers.
        driver.frame(3, ilitek, [Contact(id: 2, position: CGPoint(x: 0.5, y: 0.5))])
        driver.lift(3.1, ilitek)
        XCTAssertEqual(driver.stage, .waitingForTouch(display: 3))
        driver.touch(ilitek, at: 3.5)
        XCTAssertEqual(driver.stage, .running, "the one after counts")
    }

    /// Fix round 1, item 2: a touch that lands before a reconfiguration and lifts during it is no
    /// answer, in any stage that takes answers; nor once the displays have settled.
    func testATouchLiftingDuringAReconfigurationIsNoAnswer() throws {
        for chooseFirst in [false, true] {
            var driver = try Driver()
            if chooseFirst { driver.choose(3, at: 1.5) }
            let stage = driver.stage
            driver.frame(2.0, ilitek, [Contact(id: 1, position: CGPoint(x: 0.5, y: 0.5))])
            XCTAssertEqual(driver.scene(SessionDesk.reconfiguring, at: 2.05), [])
            XCTAssertEqual(driver.lift(2.1, ilitek), [], "\(stage): no answer")
            XCTAssertEqual(driver.stage, stage, "\(stage): no stage change")
            XCTAssertNil(driver.snapshot.notice)

            // Landing before, lifting once they have settled: no answer either.
            driver.frame(2.5, ilitek, [Contact(id: 1, position: CGPoint(x: 0.5, y: 0.5))])
            driver.scene(SessionDesk.reconfiguring, at: 2.55)
            driver.scene(SessionDesk.scene, at: 2.6)
            XCTAssertEqual(driver.lift(2.7, ilitek), [], "\(stage): settled before it lifted")

            // The next touch, once they have settled, answers.
            XCTAssertFalse(driver.touch(ilitek, at: 3.0).isEmpty, "\(stage): the next touch answers")
        }
    }

    /// Fix round 1, item 3: Finish, Esc and the time limit mark offered every touchscreen the session
    /// card showed as not set up at any moment of the mode: one connected during it, and one a Done
    /// left unpaired. One that only ever showed "can't be set up" is not marked: it never had the
    /// offer. An interruption marks none.
    func testLeavingMarksEveryTouchscreenShownAsNotSetUpAtAnyMoment() throws {
        let newcomerID = TouchscreenID(rawValue: "aaaa:bbbb:new")
        let newcomer = SetUpSession.Touchscreen(
            line: SetUpTouchscreenLine(id: newcomerID, name: "New", state: .notSetUp, reason: nil),
            reportedSizeMM: nil, pairing: nil, diagonalInches: nil, ownDisplay: nil)
        func reach(_ driver: inout Driver) {
            // Connected during the mode.
            driver.scene(SessionDesk.scene { $0.touchscreens.append(newcomer) }, at: 1)
            // The strip unpaired by another's Done, then unplugged.
            driver.scene(SessionDesk.scene {
                $0.touchscreens[1].line.state = .notSetUp
                $0.touchscreens[1].pairing = nil
                $0.touchscreens.append(newcomer)
            }, at: 2)
            driver.scene(SessionDesk.scene { $0.touchscreens.removeAll { $0.id == strip } }, at: 3)
        }
        var finished = try Driver()
        reach(&finished)
        XCTAssertEqual(finished.finish(at: 4), [.ended(.finished, markOffered: [ilitek, newcomerID, strip], setUp: [])])

        var timedOut = try Driver()
        reach(&timedOut)
        timedOut.tick(130)
        guard case .ended(.timedOut, let marked, _)? = timedOut.ending else { return XCTFail("\(timedOut.events)") }
        XCTAssertEqual(marked, [ilitek, newcomerID, strip])

        var interrupted = try Driver()
        reach(&interrupted)
        XCTAssertEqual(interrupted.call { $0.interrupt("the Mac is asleep") },
                       [.ended(.interrupted("the Mac is asleep"), markOffered: [], setUp: [])])
    }

    // MARK: - What is connected

    func testWhileTheDisplaysReconfigureNothingIsTakenForGoneAndNoAnswerIsTaken() throws {
        var driver = try Driver()
        driver.choose(3, at: 1)
        driver.scene(SessionDesk.reconfiguring, at: 1.5)
        XCTAssertEqual(driver.stage, .waitingForTouch(display: 3))
        XCTAssertEqual(driver.snapshot.displays, SessionDesk.cards, "the cards as last known")
        driver.touch(ilitek, at: 2)
        XCTAssertEqual(driver.stage, .waitingForTouch(display: 3), "no answer while they reconfigure")
        driver.choose(5, at: 2.5)
        XCTAssertEqual(driver.stage, .waitingForTouch(display: 5), "a click still chooses")
        // Settled without "Display": gone.
        let withoutDisplay = SessionDesk.scene {
            $0.displays.removeAll { $0.displayID == 5 }
            $0.cards.removeAll { $0.id == 5 }
        }
        XCTAssertEqual(driver.scene(withoutDisplay, at: 3), [.backToTheScreens(.displayGone(name: "Display"))])
        XCTAssertEqual(driver.stage, .choosing)
        XCTAssertEqual(driver.snapshot.notice, .displayGone(name: "Display"))

        // Touched first, then a click while they reconfigure: no flow can start, the stage stays.
        driver.touch(ilitek, at: 4)
        driver.scene(SessionDesk.reconfiguring, at: 4.5)
        XCTAssertEqual(driver.choose(3, at: 5), [])
        XCTAssertEqual(driver.stage, .touchedFirst(touchscreen: ilitek, name: "ILITEK-TP"))
    }

    func testAFlowHearsTheDisplaysOnlyOnceTheyHaveSettled() throws {
        var driver = try Driver()
        driver.chooseAndTouch(3, ilitek, at: 1)
        let taps = Desk.cornerTaps(on: Desk.hdmi)
        driver.taps([taps[0]], ilitek, from: 3)
        XCTAssertEqual(driver.scene(SessionDesk.reconfiguring, at: 3.5), [])
        XCTAssertEqual(driver.stage, .running)
        XCTAssertEqual(driver.scene(SessionDesk.scene, at: 3.8), [])
        guard case .corners(3, _, 1, _)? = driver.step else { return XCTFail("the tap kept: \(String(describing: driver.step))") }
    }

    func testAChosenDisplayReplacedUnderItsIDHasGone() throws {
        var driver = try Driver()
        driver.choose(3, at: 1)
        let replaced = SessionDesk.scene {
            $0.displays = $0.displays.map { $0.displayID == 3 ? changed(Desk.display) { $0.displayID = 3 } : $0 }
        }
        XCTAssertEqual(driver.scene(replaced, at: 2), [.backToTheScreens(.displayGone(name: "HDMI"))])
    }

    func testTheTouchscreenThatAnsweredFirstGoing() throws {
        var driver = try Driver()
        driver.touch(ilitek, at: 1.2)
        let without = SessionDesk.scene { $0.touchscreens.removeAll { $0.id == ilitek } }
        XCTAssertEqual(driver.scene(without, at: 2), [.backToTheScreens(.touchscreenGone(name: "ILITEK-TP"))])
        XCTAssertEqual(driver.stage, .choosing)
        XCTAssertEqual(driver.snapshot.notice, .touchscreenGone(name: "ILITEK-TP"))

        driver.scene(SessionDesk.scene, at: 3)
        driver.touch(ilitek, at: 3.5)
        let unreadable = SessionDesk.scene { $0.touchscreens[0].line.state = .cannotBeSetUp }
        XCTAssertEqual(driver.scene(unreadable, at: 4), [.backToTheScreens(.cannotBeSetUp(name: "ILITEK-TP"))])
        XCTAssertEqual(driver.snapshot.notice, .cannotBeSetUp(touchscreen: ilitek, name: "ILITEK-TP"))
    }

    func testATouchscreenConnectedDuringTheModeJoinsIt() throws {
        let newcomerID = TouchscreenID(rawValue: "aaaa:bbbb:new")
        let newcomer = SetUpSession.Touchscreen(
            line: SetUpTouchscreenLine(id: newcomerID, name: "New", state: .notSetUp, reason: nil),
            reportedSizeMM: nil, pairing: nil, diagonalInches: nil, ownDisplay: nil)
        var driver = try Driver()
        driver.touch(newcomerID, at: 1.2)
        XCTAssertEqual(driver.stage, .choosing, "not yet connected: its touch answers nothing")
        driver.scene(SessionDesk.scene { $0.touchscreens.append(newcomer) }, at: 2)
        XCTAssertEqual(driver.snapshot.touchscreens.last, newcomer.line)
        driver.touch(newcomerID, at: 2.5)
        XCTAssertEqual(driver.stage, .touchedFirst(touchscreen: newcomerID, name: "New"))
    }

    /// The snapshot is complete in every stage: every card, every line, as the scene has them now.
    func testTheSnapshotIsCompleteInEveryStage() throws {
        let renamed = SessionDesk.scene {
            $0.cards[1].name = "Top"
            $0.cards[1].touchscreen = ilitek
            $0.cards[1].touchscreenName = "ILITEK-TP"
            $0.touchscreens[0].line.state = .setUp(displayName: "Top")
        }
        for (name, reach) in Self.stages {
            var driver = try Driver()
            reach(&driver)
            XCTAssertEqual(driver.snapshot.displays, SessionDesk.cards, name)
            XCTAssertEqual(driver.snapshot.touchscreens, SessionDesk.scene.touchscreens.map(\.line), name)
            driver.scene(renamed, at: driver.latest + 0.1)
            XCTAssertEqual(driver.snapshot.displays, renamed.cards, name)
            XCTAssertEqual(driver.snapshot.touchscreens, renamed.touchscreens.map(\.line), name)
            let data = try JSONEncoder().encode(driver.snapshot)
            XCTAssertEqual(try JSONDecoder().decode(SetUpModeSnapshot.self, from: data), driver.snapshot, name)
        }
    }

    // MARK: - Input and time

    func testInputIsALandingACommandOrTheFlowsInput() throws {
        // A landing on a touchscreen that can be set up, even one that answers nothing: a finger
        // that rests and never lifts.
        var driver = try Driver()
        driver.frame(100, ilitek, [Contact(id: 1, position: CGPoint(x: 0.5, y: 0.5))])
        driver.tick(219.9)
        XCTAssertNil(driver.ending)
        driver.tick(220.2)
        XCTAssertNotNil(driver.ending)

        // An answer: a touch held long, counted again as it lifts and answers.
        driver = try Driver()
        driver.touch(ilitek, at: 100, hold: 30)
        XCTAssertEqual(driver.stage, .touchedFirst(touchscreen: ilitek, name: "ILITEK-TP"))
        driver.tick(249.9)
        XCTAssertNil(driver.ending, "two minutes from the answer")
        driver.tick(250.2)
        XCTAssertNotNil(driver.ending)

        // A command, even one that changes nothing.
        driver = try Driver()
        driver.choose(99, at: 100)
        driver.tick(219.9)
        XCTAssertNil(driver.ending)
        driver.tick(220.2)
        XCTAssertNotNil(driver.ending)

        // In a test's check step, a finger moving further than a tap may: the flow's input.
        driver = try Driver()
        driver.call { $0.begin(.test, of: strip, at: Driver.time(1)) }
        driver.frame(10, strip, [Contact(id: 1, position: CGPoint(x: 0.3, y: 0.5))])
        driver.frame(100, strip, [Contact(id: 1, position: CGPoint(x: 0.6, y: 0.5))])
        driver.tick(219.9)
        XCTAssertNil(driver.ending, "two minutes from the flow's input")
        driver.tick(220.2)
        XCTAssertNotNil(driver.ending)

        // Ticks are not input, nor is something going away.
        driver = try Driver()
        driver.choose(3, at: 10)
        let withoutHDMI = SessionDesk.scene {
            $0.displays.removeAll { $0.displayID == 3 }
            $0.cards.removeAll { $0.id == 3 }
        }
        driver.scene(withoutHDMI, at: 100)
        driver.tick(130.2)
        guard case .ended(.timedOut, _, _)? = driver.ending else { return XCTFail("\(driver.events)") }
    }

    /// Only input that can move the mode on counts: a touchscreen that can't be set up, or one the
    /// scene doesn't have, landing again and again, keeps nothing on. A noisy panel can't keep every
    /// touchscreen held.
    func testLandingsFromATouchscreenThatCantBeSetUpAreNotInput() throws {
        for id in [odd, TouchscreenID(rawValue: "0eef:0001:UNKNOWN")] {
            var driver = try Driver()
            driver.choose(3, at: 10)
            var t = 10.0
            while driver.ending == nil, t < 160 {
                t += 0.5
                driver.touch(id, at: t)
            }
            guard case .ended(.timedOut, _, _)? = driver.ending else {
                return XCTFail("\(id.rawValue): still on at \(t) s; last \(driver.events.suffix(2))")
            }
            XCTAssertLessThanOrEqual(t, 10 + SetUpFlow.idleTimeout + 0.6, "\(id.rawValue): two minutes from the choice")
            XCTAssertGreaterThanOrEqual(t, 10 + SetUpFlow.idleTimeout, id.rawValue)
        }
    }

    func testTimeGoingBackOrNotATimeMovesNothing() throws {
        var driver = try Driver()
        driver.choose(3, at: 50)
        XCTAssertEqual(driver.tick(10), [])
        XCTAssertEqual(driver.call { $0.tick(at: .nan) }, [])
        XCTAssertEqual(driver.call { $0.tick(at: -.infinity) }, [])
        XCTAssertEqual(driver.stage, .waitingForTouch(display: 3))
        // A command given an earlier time is taken at the latest moment: no reaction-time guard
        // is cheated by it.
        driver.choose(4, at: 20)
        XCTAssertEqual(driver.stage, .waitingForTouch(display: 4))
        driver.touch(ilitek, at: 50.2)
        XCTAssertEqual(driver.stage, .waitingForTouch(display: 4), "0.2 s after the click, as the session saw it")
        XCTAssertEqual(driver.call { $0.tick(at: .greatestFiniteMagnitude) }.count, 1, "ended by the time limit")
    }

    func testOnceEndedEveryCallChangesNothing() throws {
        var driver = try Driver()
        driver.chooseAndTouch(3, ilitek, at: 1)
        driver.finish(at: 3)
        let ended = driver.session
        let calls: [(String, (inout SetUpSession) -> [SetUpSession.Event])] = [
            ("handle", { $0.handle(ContactFrame(time: Driver.time(4), contacts: [Contact(id: 1, position: .zero)]), from: ilitek) }),
            ("tick", { $0.tick(at: Driver.time(500)) }),
            ("choose", { $0.choose(display: 5, at: Driver.time(5)) }),
            ("back", { $0.back(at: Driver.time(5)) }),
            ("begin", { $0.begin(.test, of: strip, at: Driver.time(5)) }),
            ("confirmSize", { $0.confirmSize(inches: nil, at: Driver.time(5)) }),
            ("redo", { $0.redo(at: Driver.time(5)) }),
            ("done", { $0.done(at: Driver.time(5)) }),
            ("finish", { $0.finish(at: Driver.time(5)) }),
            ("interrupt", { $0.interrupt("why") }),
            ("sceneChanged", { $0.sceneChanged(SessionDesk.reconfiguring, at: Driver.time(5)) }),
        ]
        for (name, call) in calls {
            var session = ended
            XCTAssertEqual(call(&session), [], name)
            XCTAssertEqual(session, ended, name)
        }
    }

    func testItCannotBeginWithNothingToSetUp() {
        XCTAssertNil(SetUpSession(SessionDesk.scene { $0.cards = [] }, at: Driver.t0), "no candidate display")
        XCTAssertNil(SetUpSession(SessionDesk.scene { $0.touchscreens = [SessionDesk.odd] }, at: Driver.t0),
                     "no touchscreen that can be set up")
        XCTAssertNil(SetUpSession(SessionDesk.scene { $0.touchscreens = [] }, at: Driver.t0), "no touchscreen")
        XCTAssertNil(SetUpSession(SessionDesk.reconfiguring, at: Driver.t0), "the displays reconfiguring")
        XCTAssertNil(SetUpSession(SessionDesk.scene, at: .nan), "a start that isn't a time")
        XCTAssertTrue(SetUpSession.couldBegin(SessionDesk.scene))
    }

    // MARK: - The log

    func testItsLogLines() throws {
        let driver = try Driver()
        XCTAssertEqual(driver.session.beganLogLine,
                       "Set-up mode began: 3 touchscreens (ILITEK-TP, TouchScreen, Panel), candidates 5 \"Display\", "
                           + "3 \"HDMI\", 4 \"12.3FHD\", 2 \"LG HDR 4K\"")
        let lines = [
            SetUpSession.Event.chose(display: 3, name: "HDMI"),
            .answered(touchscreen: ilitek, name: "ILITEK-TP", displayName: "HDMI"),
            .touchedFirst(touchscreen: strip, name: "TouchScreen"),
            .cannotBeSetUp(touchscreen: odd, name: "Panel"),
            .backToTheScreens(.back),
            .backToTheScreens(.done(name: "ILITEK-TP", displayName: "HDMI")),
            .backToTheScreens(.displayGone(name: "HDMI")),
            .ended(.finished, markOffered: [], setUp: ["ILITEK-TP", "TouchScreen"]),
            .ended(.timedOut, markOffered: [], setUp: []),
            .ended(.interrupted("the Mac is asleep"), markOffered: [], setUp: []),
        ].map(\.logLine)
        XCTAssertEqual(lines, [
            "Set-up mode: chose display 3 \"HDMI\"",
            "Set-up mode: ILITEK-TP [222a:0001:V06.00.00.00] answered on HDMI",
            "Set-up mode: TouchScreen [27c0:0859:TEST-SERIAL-0001] touched first; waiting for a display",
            "Set-up mode: Panel [#9:1111:2222:X] can't be set up; touch ignored",
            "Set-up mode: back to the screens (Back)",
            "Set-up mode: back to the screens (done: ILITEK-TP on HDMI)",
            "Set-up mode: back to the screens (display gone: HDMI)",
            "Set-up mode ended (Finish or Esc); set up in this session: ILITEK-TP, TouchScreen",
            "Set-up mode ended (timeout); set up in this session: none",
            "Set-up mode ended (interruption: the Mac is asleep); set up in this session: none",
        ])
        XCTAssertNil(SetUpSession.Event.flowFinished(touchscreen: ilitek, name: "x", purpose: .full, outcome: nil).logLine,
                     "the model writes the flow's own lines")
    }

    // MARK: - The answer rule against an oracle (fix round 1, item 4: the reviewer's probe)

    /// What the oracle knows of one touchscreen's touch, from its landing.
    private struct OracleTouch {
        var eligible: Bool
        var mostContacts: Int
        var palm: Bool
        var stageChanged: Bool
        var sawReconfiguration: Bool
    }

    /// Seeded interleavings, with fingers held across steps (one to four contacts, palms, three
    /// touchscreens), clicks, Back, Test, Calibrate, Done, reconfigurations and a display going,
    /// against an oracle of the answer rule: every answer comes, at its lift, from a landing that could
    /// answer (no flow, not reconfiguring, not within the reaction time or the first second), by at
    /// most two fingers and no palm, with no stage change and no reconfiguration while it was down;
    /// every full flow runs for the touchscreen that answered on the display that was clicked; every
    /// outcome comes from Done and is stored on the flow's display.
    func testTheAnswerRuleAndThePairingHoldAgainstAnOracle() throws {
        var generator = Seeded(state: 0x5E7_0505)
        let ids = [ilitek, strip, odd]
        let displays: [UInt32] = [2, 3, 4, 5, 1]
        var answers = 0, fullFlows = 0, outcomes = 0
        for run in 0..<300 {
            let t0 = SessionDriver.t0
            var session = try XCTUnwrap(SetUpSession(SessionDesk.scene, at: t0))
            var scene = SessionDesk.scene
            var clock = t0
            var sessionNow = t0
            var lastChange = t0
            var touches: [TouchscreenID: OracleTouch] = [:]
            /// Fingers down now, per touchscreen, as the generator holds them.
            var fingers: [TouchscreenID: [Contact]] = [:]
            var runningDisplay: DisplayFacts?
            var runningPurpose: SetUpPurpose?
            var runningTouchscreen: TouchscreenID?
            for stepIndex in 0..<500 {
                let at = "run \(run) step \(stepIndex)"
                clock += .random(in: 0.0...0.6, using: &generator)
                let stageBefore = session.snapshot.stage
                let flowBefore = session.flow
                var events: [SetUpSession.Event] = []
                var frameFrom: TouchscreenID?
                var landing = false
                var calledDone = false
                var chose: UInt32?
                var began: (SetUpPurpose, TouchscreenID)?
                switch Int.random(in: 0..<100, using: &generator) {
                case 0..<45:
                    // A frame from one touchscreen: a finger lands, another lands, a palm, or all lift.
                    let id = ids.randomElement(using: &generator)!
                    var contacts = fingers[id] ?? []
                    switch Int.random(in: 0..<10, using: &generator) {
                    case 0..<4:
                        contacts = []
                    case 4..<7:
                        if contacts.isEmpty { contacts = [Contact(id: 1, position: CGPoint(x: 0.5, y: 0.5))] }
                    case 7..<9:
                        contacts.append(Contact(id: contacts.count + 1, position: CGPoint(x: 0.4, y: 0.4)))
                    default:
                        contacts.append(Contact(id: contacts.count + 1, position: CGPoint(x: 0.3, y: 0.3), isConfident: false))
                    }
                    fingers[id] = contacts
                    frameFrom = id
                    landing = !contacts.isEmpty && touches[id] == nil
                    events = session.handle(ContactFrame(time: clock, contacts: contacts), from: id)
                case 45..<60:
                    events = session.tick(at: clock)
                case 60..<72:
                    // While a corners step shows, sometimes a tap of the running touchscreen.
                    if let flow = session.flow, case .corners(_, let target, _, _) = flow.snapshot.step,
                       Bool.random(using: &generator) {
                        let id = flow.snapshot.touchscreen
                        fingers[id] = []
                        _ = session.tick(at: clock + 1)
                        _ = session.handle(ContactFrame(time: clock + 1, contacts: [Contact(id: 1, position: target)]), from: id)
                        events = session.handle(ContactFrame(time: clock + 1.05, contacts: []), from: id)
                        clock += 1.05
                        touches[id] = nil
                    } else {
                        let display = displays.randomElement(using: &generator)!
                        chose = display
                        events = session.choose(display: display, at: clock)
                    }
                case 72..<76:
                    events = session.back(at: clock)
                case 76..<80:
                    let purpose = [SetUpPurpose.test, .calibrate, .full].randomElement(using: &generator)!
                    let id = ids.randomElement(using: &generator)!
                    began = (purpose, id)
                    events = session.begin(purpose, of: id, at: clock)
                case 80..<85:
                    events = session.confirmSize(inches: nil, at: clock)
                case 85..<92:
                    calledDone = true
                    events = session.done(at: clock)
                case 92..<97:
                    let scenes = [
                        SessionDesk.scene, SessionDesk.scene, SessionDesk.reconfiguring,
                        SessionDesk.scene { $0.displays.removeAll { $0.displayID == 3 }; $0.cards.removeAll { $0.id == 3 } },
                    ]
                    scene = scenes.randomElement(using: &generator)!
                    events = session.sceneChanged(scene, at: clock)
                    if scene.isReconfiguring {
                        for (id, var touch) in touches where !(fingers[id] ?? []).isEmpty {
                            touch.sawReconfiguration = true
                            touches[id] = touch
                        }
                    }
                default:
                    clock += 0.5
                    events = session.tick(at: clock)
                }
                sessionNow = max(sessionNow, clock)

                // The oracle's view of the touch on `frameFrom`.
                if let id = frameFrom {
                    let contacts = fingers[id] ?? []
                    if landing {
                        let stageChangedInCall = session.snapshot.stage != stageBefore
                            && !events.contains {
                                if case .touchedFirst = $0 { return true }
                                if case .answered = $0 { return true }
                                return false
                            }
                        touches[id] = OracleTouch(
                            eligible: flowBefore == nil && !scene.isReconfiguring && !stageChangedInCall
                                && clock >= lastChange + SetUpFlow.reactionTime && clock >= t0 + SetUpFlow.startQuiet,
                            mostContacts: contacts.count, palm: contacts.contains { $0.isConfident == false },
                            stageChanged: false, sawReconfiguration: false)
                    } else if !contacts.isEmpty, var touch = touches[id] {
                        touch.mostContacts = max(touch.mostContacts, contacts.count)
                        touch.palm = touch.palm || contacts.contains { $0.isConfident == false }
                        touches[id] = touch
                    }
                }

                var ended = false
                for event in events {
                    switch event {
                    case .touchedFirst(let id, _), .answered(let id, _, _):
                        answers += 1
                        XCTAssertEqual(id, frameFrom, "\(at): answered by another's frame")
                        XCTAssertTrue((fingers[id] ?? []).isEmpty, "\(at): decided at its lift")
                        XCTAssertFalse(scene.isReconfiguring, "\(at): an answer while the displays reconfigure")
                        if let touch = touches[id] {
                            XCTAssertTrue(touch.eligible, "\(at): \(event) from a landing that was no answer")
                            XCTAssertFalse(touch.stageChanged, "\(at): \(event) though the stage changed while it was down")
                            XCTAssertFalse(touch.sawReconfiguration, "\(at): \(event) though the displays reconfigured")
                            XCTAssertLessThanOrEqual(touch.mostContacts, 2, "\(at): a hand answered")
                            XCTAssertFalse(touch.palm, "\(at): a palm answered")
                        } else {
                            XCTFail("\(at): \(event) with no touch")
                        }
                        XCTAssertNotEqual(id, odd, "\(at): one that can't be set up answered")
                    case .flowStarted(let start):
                        XCTAssertNil(runningPurpose, "\(at): a flow over a flow")
                        runningPurpose = start.purpose
                        runningTouchscreen = start.touchscreen
                        runningDisplay = start.candidates.first
                        if start.purpose == .full {
                            fullFlows += 1
                            if let chose {
                                guard case .touchedFirst(let first, _) = stageBefore else {
                                    XCTFail("\(at): a full flow from a click while \(stageBefore)")
                                    continue
                                }
                                XCTAssertEqual(start.touchscreen, first, "\(at): the touchscreen that touched first")
                                XCTAssertEqual(start.candidates.first?.displayID, chose, "\(at): on the display clicked")
                            } else if let from = frameFrom {
                                guard case .waitingForTouch(let display) = stageBefore else {
                                    XCTFail("\(at): a full flow from a touch while \(stageBefore)")
                                    continue
                                }
                                XCTAssertEqual(start.touchscreen, from, "\(at): the touchscreen that answered")
                                XCTAssertEqual(start.candidates.first?.displayID, display, "\(at): on the display chosen")
                            } else {
                                XCTFail("\(at): a full flow from neither a click nor a touch")
                            }
                            XCTAssertTrue(scene.cards.contains { $0.id == start.candidates.first?.displayID }, "\(at): a card's")
                        } else {
                            XCTAssertEqual(began?.0, start.purpose, at)
                            XCTAssertEqual(began?.1, start.touchscreen, at)
                            let own = scene.touchscreens.first { $0.id == start.touchscreen }?.ownDisplay
                            XCTAssertEqual(start.candidates.first?.displayID, own, "\(at): its own display")
                        }
                    case .flowFinished(let id, _, let purpose, let outcome):
                        XCTAssertEqual(id, runningTouchscreen, at)
                        XCTAssertEqual(purpose, runningPurpose, at)
                        if let outcome {
                            outcomes += 1
                            XCTAssertTrue(calledDone, "\(at): an outcome without Done")
                            XCTAssertNotEqual(purpose, .test, at)
                            if let runningDisplay {
                                XCTAssertEqual(outcome.display, DisplayIdentity(runningDisplay), "\(at): stored on the flow's display")
                            }
                        }
                        runningPurpose = nil
                        runningTouchscreen = nil
                        runningDisplay = nil
                    case .ended:
                        ended = true
                    default:
                        break
                    }
                }
                if session.snapshot.stage != stageBefore {
                    lastChange = sessionNow
                    // Every touch down now saw a change, but one that lifted in this call.
                    for (id, var touch) in touches where !(fingers[id] ?? []).isEmpty {
                        touch.stageChanged = true
                        touches[id] = touch
                    }
                }
                for id in ids where (fingers[id] ?? []).isEmpty { touches[id] = nil }
                if ended { break }
            }
        }
        XCTAssertGreaterThan(answers, 500, "answers taken")
        XCTAssertGreaterThan(fullFlows, 200, "full flows started")
        XCTAssertGreaterThan(outcomes, 0, "outcomes stored")
    }

    // MARK: - Anything in any order

    /// Thousands of random calls, from a fixed seed, against what must always hold: nothing traps;
    /// the snapshot survives JSON and is complete; a flow runs exactly when the stage says so; an
    /// outcome comes only from Done, of a flow in its check step, for a touchscreen that can be set up,
    /// on a display that isn't built in; nothing answers for a touchscreen that can't be set up; the
    /// mode ends once, and changes nothing after.
    func testAnythingInAnyOrder() throws {
        let scenes: [SetUpSession.Scene] = [
            SessionDesk.scene, SessionDesk.reconfiguring,
            SessionDesk.scene { $0.displays.removeAll { $0.displayID == 3 }; $0.cards.removeAll { $0.id == 3 } },
            SessionDesk.scene { $0.touchscreens.removeAll { $0.id == ilitek } },
            SessionDesk.scene { $0.touchscreens[0].line.state = .cannotBeSetUp },
            SessionDesk.scene { $0.displays = $0.displays.map { $0.displayID == 3 ? Desk.hdmiTurned : $0 } },
        ]
        let ids = [ilitek, strip, odd, TouchscreenID(rawValue: "nobody")]
        let displays: [UInt32] = [2, 3, 4, 5, 1, 99]
        let numbers: [CGFloat] = [0, 0.12, 0.5, 0.88, 1, -0.01, 7, .nan, .infinity]
        var generator = Seeded(state: 515)
        var outcomes = 0, flows = 0
        for _ in 0..<150 {
            var session = try XCTUnwrap(SetUpSession(SessionDesk.scene, at: SessionDriver.t0))
            var scene = SessionDesk.scene
            var clock = SessionDriver.t0
            var ended = false
            for _ in 0..<400 {
                clock += .random(in: -0.2...1.2, using: &generator)
                let time: TimeInterval = Int.random(in: 0..<60, using: &generator) == 0 ? .nan : clock
                let before = session
                var calledDone = false
                var target: CGPoint?
                if case .corners(_, let shown, _, _)? = session.flow?.snapshot.step { target = shown }
                // Done is pressed more often while the check is shown, so that it is reached.
                var inCheck = false
                if case .check? = session.flow?.snapshot.step { inCheck = true }
                let events: [SetUpSession.Event]
                switch Int.random(in: 0..<100, using: &generator) {
                case 0..<25 where inCheck:
                    calledDone = true
                    events = session.done(at: time)
                case 0..<15 where target != nil && session.flow != nil:
                    // A clean tap of the running flow's touchscreen on the target, where an unturned
                    // display fitted straight puts it.
                    let id = session.flow!.snapshot.touchscreen
                    _ = session.handle(ContactFrame(time: time, contacts: [Contact(id: 1, position: target!)]), from: id)
                    events = session.handle(ContactFrame(time: time + 0.05, contacts: []), from: id)
                case 0..<50:
                    let count = [0, 0, 0, 1, 1, 2, 3].randomElement(using: &generator)!
                    let contacts = (0..<count).map { _ in
                        Contact(id: Int.random(in: 0...2, using: &generator),
                                position: CGPoint(x: numbers.randomElement(using: &generator)!,
                                                  y: numbers.randomElement(using: &generator)!),
                                isConfident: Int.random(in: 0..<10, using: &generator) == 0 ? false : nil)
                    }
                    events = session.handle(ContactFrame(time: time, contacts: contacts),
                                            from: ids.randomElement(using: &generator)!)
                case 50..<68:
                    events = session.tick(at: time)
                case 68..<76:
                    events = session.choose(display: displays.randomElement(using: &generator)!, at: time)
                case 76..<80:
                    events = session.back(at: time)
                case 80..<83:
                    let purpose = [SetUpPurpose.full, .calibrate, .test].randomElement(using: &generator)!
                    events = session.begin(purpose, of: ids.randomElement(using: &generator)!, at: time)
                case 83..<87:
                    events = session.confirmSize(inches: [nil, 23.8, 0, .nan].randomElement(using: &generator)!, at: time)
                case 87..<89:
                    events = session.redo(at: time)
                case 89..<95:
                    calledDone = true
                    events = session.done(at: time)
                case 95..<98:
                    scene = scenes.randomElement(using: &generator)!
                    events = session.sceneChanged(scene, at: time)
                case 98:
                    events = session.finish(at: time)
                default:
                    events = Int.random(in: 0..<4, using: &generator) == 0 ? session.interrupt("why") : []
                }

                if ended {
                    XCTAssertEqual(events, [])
                    XCTAssertEqual(session, before)
                    continue
                }
                var flowRunning = before.flow != nil
                for event in events {
                    switch event {
                    case .flowFinished(_, _, let purpose, let outcome?):
                        flowRunning = false
                        outcomes += 1
                        XCTAssertTrue(calledDone, "an outcome from anything but Done")
                        XCTAssertNotEqual(purpose, .test)
                        guard case .check(let display)? = before.flow?.snapshot.step else {
                            XCTFail("an outcome from outside the check step")
                            continue
                        }
                        XCTAssertNotEqual(display, Desk.builtIn.displayID)
                        XCTAssertNotEqual(outcome.display, DisplayIdentity(Desk.builtIn))
                    case .flowFinished:
                        flowRunning = false
                    case .flowStarted(let start):
                        flows += 1
                        XCTAssertFalse(flowRunning, "a flow over a flow")
                        flowRunning = true
                        XCTAssertEqual(start.candidates.count, 1)
                        XCTAssertTrue(scene.touchscreens.first { $0.id == start.touchscreen }?.canBeSetUp ?? false)
                    case .touchedFirst(let id, _), .answered(let id, _, _):
                        XCTAssertTrue(scene.touchscreens.first { $0.id == id }?.canBeSetUp ?? false, "\(event)")
                    case .ended:
                        ended = true
                    default:
                        break
                    }
                }
                if ended {
                    XCTAssertNil(session.flow)
                    continue
                }
                let snapshot = session.snapshot
                XCTAssertEqual(snapshot.stage == .running, session.flow != nil)
                XCTAssertEqual(snapshot.displays, scene.cards)
                XCTAssertEqual(snapshot.touchscreens, scene.touchscreens.map(\.line))
                let data = try JSONEncoder().encode(snapshot)
                XCTAssertEqual(try JSONDecoder().decode(SetUpModeSnapshot.self, from: data), snapshot)
            }
        }
        XCTAssertGreaterThan(flows, 50, "the random calls started flows")
        XCTAssertGreaterThan(outcomes, 0, "the random calls reached Done in the check step at least once")
    }
}
