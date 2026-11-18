// Delivery 5, Part T1: the gesture tester in the model: when it opens, every way it closes, what it
// shows, how often, and that its touchscreen still drives, its swipes held unless let through.
// Through the model with its fakes: no device, event, window or pointer; the settings folder is
// temporary.

import CoreGraphics
import Foundation
import Observation
@testable import TactileApp
import TactileDevices
import TactileGestures
import TactileReading
import TactileScreens
import XCTest

private typealias Desk = DeskFixture

@MainActor
final class GestureTesterModelTests: XCTestCase {
    private let ilitek = Desk.ilitekID
    private let strip = Desk.stripID
    private let ilitekSurface = Desk.driving(on: Desk.hdmi, diagonal: 23.8).surfaceSizeMM

    private func tester(_ harness: ModelHarness) -> GestureTesterSnapshot? {
        harness.model.snapshot.gestureTester
    }

    /// The desk with the tester open on the ILITEK.
    private func openOnILITEK() throws -> ModelHarness {
        let harness = try deskHarness(self)
        harness.model.perform(.openGestureTester(ilitek))
        XCTAssertEqual(tester(harness)?.touchscreen, ilitek)
        return harness
    }

    /// A tap at the middle of `handle`'s glass, now.
    private func tap(_ harness: ModelHarness, _ handle: DeviceHandle = Desk.ilitekHandle) {
        let t = harness.clock + 0.5
        harness.send([glassFrame(t, (0, 0.5, 0.5)), glassFrame(t + 0.05, (0, 0.5, 0.5)), glassFrame(t + 0.1)], from: handle)
    }

    /// Three fingers on the ILITEK moving 60 mm left, then lifting; then a second for the session to end.
    private func swipeLeft(_ harness: ModelHarness) {
        var glass = Glass(ilitekSurface, at: harness.clock + 0.5)
        glass.land((0..<3).map { ($0, 180 + 25 * Double($0), 150) })
        glass.move(-60, 0, steps: 20)
        glass.lift()
        harness.send(glass.frames, from: Desk.ilitekHandle)
        settle(harness)
    }

    /// Ticks 60 times a second for `seconds`, as the model's clock would.
    private func settle(_ harness: ModelHarness, _ seconds: TimeInterval = 1) {
        for _ in 0..<Int(seconds * 60) { harness.tick(after: 1.0 / 60) }
    }

    // MARK: - Opening

    func testItOpensForAPairedTouchscreenOfEitherKind() throws {
        let harness = try deskHarness(self)
        XCTAssertNil(tester(harness), "closed until asked")
        harness.model.perform(.openGestureTester(ilitek))
        XCTAssertEqual(tester(harness), GestureTesterSnapshot(
            touchscreen: ilitek, touchscreenName: "ILITEK-TP", displayID: Desk.hdmi.displayID, multiTouch: true,
            performsSwipes: false, fingersDown: 0, recent: [], seen: []))

        harness.model.perform(.openGestureTester(strip))
        XCTAssertEqual(tester(harness), GestureTesterSnapshot(
            touchscreen: strip, touchscreenName: "TouchScreen", displayID: Desk.strip.displayID, multiTouch: false,
            performsSwipes: false, fingersDown: 0, recent: [], seen: []), "moved, afresh; the strip gives one finger")
    }

    func testOpeningItForAnotherTouchscreenMovesItAndLetsTheFirstsSwipesGo() throws {
        let harness = try openOnILITEK()
        harness.model.perform(.openGestureTester(strip))
        XCTAssertEqual(tester(harness)?.touchscreen, strip)
        swipeLeft(harness)
        XCTAssertEqual(harness.outputs.shortcuts, 1, "the ILITEK's swipes are no longer held")
        XCTAssertEqual(tester(harness)?.recent, [], "and not in the strip's feed")
    }

    func testOpeningItAgainForTheSameTouchscreenKeepsItsFeed() throws {
        let harness = try openOnILITEK()
        harness.model.perform(.setGestureTesterPerformsSwipes(true))
        tap(harness)
        settle(harness)
        XCTAssertEqual(tester(harness)?.recent.map(\.kind), [.tap])
        harness.model.perform(.openGestureTester(ilitek))
        XCTAssertEqual(tester(harness)?.recent.map(\.kind), [.tap])
        XCTAssertEqual(tester(harness)?.performsSwipes, true)
    }

    func testItIsRefusedWhenItCannotBeOpen() throws {
        let unknown = TouchscreenID(rawValue: "1111:2222:gone")
        let refusals: [(String, (ModelHarness) -> Void, TouchscreenID)] = [
            ("unknown", { _ in }, unknown),
            ("unpaired", { $0.model.perform(.unpair(Desk.ilitekID)) }, ilitek),
            ("Tactile off", { $0.model.perform(.setOn(false)) }, ilitek),
            ("no Accessibility", { $0.conditions.setAccessibility(false) }, ilitek),
            ("locked", { $0.conditions.setSessionActive(false) }, ilitek),
            ("asleep", { $0.conditions.sleep() }, ilitek),
            ("display gone", { $0.displays.set(Desk.displays.filter { $0 != Desk.hdmi }) }, ilitek),
            ("switched off", { $0.model.perform(.setTouchscreenOn(Desk.ilitekID, false)) }, ilitek),
            ("switched off, left to macOS", {
                $0.model.perform(.setWhenOff(Desk.ilitekID, .leaveToMacOS))
                $0.model.perform(.setTouchscreenOn(Desk.ilitekID, false))
            }, ilitek),
            ("its touches can't be read", { $0.source.change(Desk.ilitekHandle) { $0.status = Desk.taken(origin: .unreadable) } }, ilitek),
            ("macOS also handles it", { $0.source.change(Desk.stripHandle) {
                $0.status = Desk.taken(origin: .mouseInterface, inputMode: .switchedToMultiTouch, exclusive: .failed)
            } }, strip),
            ("the displays reconfiguring", { $0.displays.set([]) }, ilitek),
            ("set-up of the other", { $0.model.perform(.beginSetUp(Desk.stripID, .test)) }, ilitek),
            ("set-up of itself", { $0.model.perform(.beginSetUp(Desk.ilitekID, .calibrate)) }, ilitek),
        ]
        for (name, make, id) in refusals {
            let harness = try deskHarness(self)
            make(harness)
            harness.model.perform(.openGestureTester(id))
            XCTAssertNil(tester(harness), name)
            XCTAssertNil(harness.model.gestureTester, name)
        }
        // Unplugged: remembered, not connected.
        let harness = try deskHarness(self)
        harness.source.unplug(Desk.ilitekHandle)
        harness.model.perform(.openGestureTester(ilitek))
        XCTAssertNil(tester(harness))
    }

    func testATouchscreenThatCannotBeToldApartIsRefused() throws {
        // Two identical panels with no USB location: neither has a record.
        let facts = TouchscreenFacts(vendorID: 0x1234, productID: 0x5678, serial: "", locationID: 0, name: "Panel")
        let harness = try deskHarness(self)
        harness.source.plugIn(Desk.ilitek(handle: DeviceHandle(rawValue: 7), facts: facts))
        harness.source.plugIn(Desk.ilitek(handle: DeviceHandle(rawValue: 8), facts: facts))
        let twins = harness.model.snapshot.touchscreens.filter { $0.notes.contains(.cannotBeToldApart) }
        XCTAssertEqual(twins.count, 2)
        for twin in twins {
            harness.model.perform(.openGestureTester(twin.id))
            XCTAssertNil(tester(harness))
        }
    }

    // MARK: - Every way it closes

    func testEveryWayItCloses() throws {
        let closings: [(String, (ModelHarness) -> Void)] = [
            ("its close button or Esc", { $0.model.perform(.closeGestureTester) }),
            ("unplugged", { $0.source.unplug(Desk.ilitekHandle) }),
            ("unpaired", { $0.model.perform(.unpair(Desk.ilitekID)) }),
            ("its display paired with the other", { $0.model.perform(.pair(Desk.stripID, displayID: Desk.hdmi.displayID)) }),
            ("its display gone", { $0.displays.set(Desk.displays.filter { $0 != Desk.hdmi }) }),
            ("its display gone once the displays settle", {
                $0.displays.set([])
                $0.displays.set(Desk.displays.filter { $0 != Desk.hdmi })
            }),
            ("switched off", { $0.model.perform(.setTouchscreenOn(Desk.ilitekID, false)) }),
            ("its touches can't be read", { $0.source.change(Desk.ilitekHandle) { $0.status = Desk.taken(origin: .unreadable) } }),
            ("macOS also handles it", { $0.source.change(Desk.ilitekHandle) {
                $0.status = Desk.taken(origin: .mouseInterface, exclusive: .failed)
            } }),
            ("Tactile off", { $0.model.perform(.setOn(false)) }),
            ("Accessibility gone", { $0.conditions.setAccessibility(false) }),
            ("lock", { $0.conditions.setSessionActive(false) }),
            ("sleep", { $0.conditions.sleep() }),
            ("set-up of itself", { $0.model.perform(.beginSetUp(Desk.ilitekID, .calibrate)) }),
            ("set-up of the other", { $0.model.perform(.beginSetUp(Desk.stripID, .test)) }),
        ]
        for (name, close) in closings {
            let harness = try openOnILITEK()
            close(harness)
            XCTAssertNil(tester(harness), name)
            XCTAssertNil(harness.model.gestureTester, name)
        }

        // Quitting.
        let harness = try openOnILITEK()
        harness.model.shutDown()
        XCTAssertNil(harness.model.gestureTester)
        XCTAssertNil(tester(harness))
    }

    /// Fix round 1, item 1: while the displays reconfigure every touchscreen is held for a moment; the
    /// tester stays open, and is decided once they settle. Its touchscreen's fresh pipeline is
    /// observed, and its swipes held.
    func testItStaysOpenThroughADisplayReconfiguration() throws {
        let harness = try openOnILITEK()
        let before = tester(harness)
        harness.displays.set([])
        XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .held, "every touchscreen held while they settle")
        XCTAssertEqual(tester(harness), before, "still open, as it was")
        XCTAssertNotNil(harness.model.gestureTester)
        harness.displays.set(Desk.displays)
        XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .driving)
        XCTAssertEqual(tester(harness)?.touchscreen, ilitek, "still open once they settle")
        swipeLeft(harness)
        XCTAssertEqual(harness.outputs.shortcuts, 0, "the fresh pipeline is observed: its swipe held")
        XCTAssertEqual(tester(harness)?.recent.map(\.kind), [.swipe])
    }

    /// The join, from the fix rounds' re-review: a touch that lifts while the displays reconfigure
    /// (its touchscreen held, its frames dropped) leaves no fingers on the glass in the feed. The
    /// pipeline that stopped driving says the glass is clear, as the silence rule does; so the
    /// fingers down read 0, and a quick drag seconds later reads "Drag", not "Hold, then drag".
    func testATouchLiftingWhileTheDisplaysReconfigureLeavesNoFingersInTheFeed() throws {
        let harness = try openOnILITEK()
        harness.model.perform(.setOneFinger(ilitek, .alwaysDrag))
        var scroll = Glass(ilitekSurface, at: harness.clock + 0.5)
        scroll.land([(0, 200, 150), (1, 230, 150)])
        scroll.move(0, 30, steps: 10)
        harness.send(scroll.frames, from: Desk.ilitekHandle)
        XCTAssertEqual(harness.model.gestureTester?.narrator.fingersOnGlass, 2)

        harness.displays.set([])
        harness.send([ContactFrame(time: harness.clock + 0.02, contacts: [])], from: Desk.ilitekHandle)  // the lift, held
        harness.displays.set(Desk.displays)
        settle(harness, 2)
        XCTAssertEqual(tester(harness)?.fingersDown, 0, "no finger on the glass")
        XCTAssertTrue(harness.model.gestureTester?.narrator.isIdle ?? false)

        var drag = Glass(ilitekSurface, at: harness.clock + 3)
        drag.land([(5, 100, 100)])
        drag.move(40, 0, steps: 4)
        drag.rest(0.1)
        drag.lift()
        harness.send(drag.frames, from: Desk.ilitekHandle)
        settle(harness)
        XCTAssertEqual(tester(harness)?.recent.first?.kind, .drag, "a quick drag, not hold-then-drag")
        XCTAssertEqual(tester(harness)?.fingersDown, 0)
    }

    /// Opening it while the displays reconfigure is refused: its touchscreen isn't driving, as the
    /// window's button says.
    func testItDoesNotOpenWhileTheDisplaysReconfigure() throws {
        let harness = try deskHarness(self)
        harness.displays.set([])
        harness.model.perform(.openGestureTester(ilitek))
        XCTAssertNil(tester(harness))
        harness.displays.set(Desk.displays)
        XCTAssertNil(tester(harness), "it doesn't open by itself once they settle")
    }

    /// Fix round 1, item 4: closing it detaches its observer from every pipeline, even if something
    /// still holds the session: the swipes are done again.
    func testClosingItDetachesItsObserverEvenIfTheSessionLivesOn() throws {
        let harness = try openOnILITEK()
        let kept = harness.model.gestureTester
        harness.model.perform(.closeGestureTester)
        XCTAssertNil(tester(harness))
        swipeLeft(harness)
        XCTAssertEqual(harness.outputs.shortcuts, 1, "not held")
        XCTAssertEqual(kept?.narrator.recent, [], "and not observed")

        // Moved to the strip, the ILITEK's old session kept: the ILITEK's swipes are done.
        let moved = try openOnILITEK()
        let old = moved.model.gestureTester
        moved.model.perform(.openGestureTester(strip))
        swipeLeft(moved)
        XCTAssertEqual(moved.outputs.shortcuts, 1)
        XCTAssertEqual(old?.narrator.recent, [])
        withExtendedLifetime((kept, old)) {}
    }

    /// After a lock, or a set-up, it stays closed; it opens again when asked.
    func testItCanBeOpenedAgainAfterItClosed() throws {
        let harness = try openOnILITEK()
        harness.conditions.setSessionActive(false)
        harness.conditions.setSessionActive(true)
        XCTAssertNil(tester(harness), "it doesn't come back by itself")
        harness.model.perform(.openGestureTester(ilitek))
        XCTAssertEqual(tester(harness)?.touchscreen, ilitek)
        XCTAssertEqual(tester(harness)?.performsSwipes, false, "swipes held again: the default each time it opens")
    }

    /// Set-up mode is published in the snapshot: while it is on, or a flow runs, the tester can't be open.
    func testSetUpModeOrAFlowRefusesIt() throws {
        let harness = try deskHarness(self)
        var snapshot = harness.model.snapshot
        XCTAssertNil(Resolver.gestureTesterRefusal(for: ilitek, in: snapshot))
        snapshot.setUpMode = SetUpModeSnapshot(stage: .choosing, displays: [], touchscreens: [], justSetUp: nil, notice: nil)
        XCTAssertEqual(Resolver.gestureTesterRefusal(for: ilitek, in: snapshot), .settingUp)
        snapshot.setUpMode = nil
        snapshot.setUp = SetUpSnapshot(touchscreen: strip, touchscreenName: "TouchScreen", purpose: .test,
                                       step: .check(display: Desk.strip.displayID))
        XCTAssertEqual(Resolver.gestureTesterRefusal(for: ilitek, in: snapshot), .settingUp)
    }

    func testTheRefusalsReasons() throws {
        let harness = try deskHarness(self)
        let base = harness.model.snapshot
        func refusal(_ change: (inout AppSnapshot) -> Void) -> GestureTesterRefusal? {
            Resolver.gestureTesterRefusal(for: ilitek, in: with(base, change))
        }
        XCTAssertNil(refusal { _ in })
        XCTAssertEqual(refusal { $0.touchscreens.removeAll { $0.id == Desk.ilitekID } }, .notConnected)
        XCTAssertEqual(refusal { $0.touchscreens[0].isConnected = false }, .notConnected)
        XCTAssertEqual(refusal { $0.isOn = false }, .tactileOff)
        XCTAssertEqual(refusal { $0.warnings = [.accessibilityMissing] }, .accessibilityMissing)
        XCTAssertEqual(refusal { $0.touchscreens[0].notes = [.cannotBeToldApart] }, .cannotBeToldApart)
        XCTAssertEqual(refusal { $0.touchscreens[0].pairedDisplayID = nil }, .notPaired)
        XCTAssertEqual(refusal { $0.touchscreens[0].mode = .released }, .touchscreensReleased)
        XCTAssertEqual(refusal { $0.touchscreens[0].isOn = false }, .switchedOff)
        XCTAssertEqual(refusal { $0.touchscreens[0].mode = .released; $0.touchscreens[0].isOn = false }, .switchedOff)
        XCTAssertEqual(refusal { $0.touchscreens[0].mode = .held }, .notDriving, "held: macOS also handles it, say")
        XCTAssertEqual(refusal { $0.touchscreens[0].mode = .settingUp }, .notDriving)
        XCTAssertEqual(refusal { $0.touchscreens[0].mode = nil }, .notDriving)
    }

    func testTheClosingWords() {
        XCTAssertEqual(TactileModel.closing(.touchscreensReleased, rule: .sessionNotActive, status: nil), "locked")
        XCTAssertEqual(TactileModel.closing(.touchscreensReleased, rule: .asleep, status: nil), "asleep")
        XCTAssertEqual(TactileModel.closing(.touchscreensReleased, rule: .quitting, status: nil), "quitting")
        XCTAssertEqual(TactileModel.closing(.notPaired, rule: .displayNotConnected, status: .displayNotConnected(name: "HDMI")),
                       "its display has gone")
        XCTAssertEqual(TactileModel.closing(.notPaired, rule: .notPaired, status: .notSetUp), "the touchscreen was unpaired")
        XCTAssertEqual(TactileModel.closing(.settingUp, rule: nil, status: nil), "set-up began")
        XCTAssertEqual(TactileModel.closing(.notDriving, rule: .mouseModeShared, status: nil), "macOS also handles the touchscreen")
        XCTAssertEqual(TactileModel.closing(.notDriving, rule: .touchesUnreadable, status: nil), "its touches can't be read")
        XCTAssertEqual(TactileModel.closing(.switchedOff, rule: .offIgnoringTouches, status: nil), "the touchscreen was switched off")
    }

    // MARK: - It still drives

    func testItsTouchscreenStillDrivesAndItsFeedSaysWhat() throws {
        let harness = try openOnILITEK()
        tap(harness)
        settle(harness)
        XCTAssertEqual(harness.outputs.count(.down), 1, "the tap clicked")
        XCTAssertEqual(harness.outputs.count(.up), 1)
        XCTAssertEqual(tester(harness)?.recent.map(\.kind), [.tap])
        XCTAssertEqual(tester(harness)?.recent.first?.summary, "a click")
        XCTAssertEqual(tester(harness)?.seen, [GestureSeenCount(id: .tap, count: 1)])
    }

    func testItsSwipesAreHeldUntilLetThrough() throws {
        let harness = try openOnILITEK()
        swipeLeft(harness)
        XCTAssertEqual(harness.outputs.shortcuts, 0, "held: no shortcut")
        XCTAssertEqual(tester(harness)?.recent.first?.summary, "left: next Desktop" + GestureNarrator.heldNote)

        harness.model.perform(.setGestureTesterPerformsSwipes(true))
        XCTAssertEqual(tester(harness)?.performsSwipes, true)
        swipeLeft(harness)
        XCTAssertEqual(harness.outputs.shortcuts, 1, "let through: the shortcut")
        XCTAssertEqual(tester(harness)?.recent.first?.summary, "left: next Desktop")

        harness.model.perform(.setGestureTesterPerformsSwipes(false))
        swipeLeft(harness)
        XCTAssertEqual(harness.outputs.shortcuts, 1, "held again")
        XCTAssertEqual(tester(harness)?.seen, [GestureSeenCount(id: .swipe, count: 3)])
    }

    func testFollowedSwipesAreHeldThroughTheModelToo() throws {
        let harness = try openOnILITEK()
        harness.model.perform(.setSwipesFollowFingers(true))
        XCTAssertTrue(harness.model.snapshot.canFollowSwipes)
        swipeLeft(harness)
        XCTAssertEqual(harness.outputs.record.dockEvents, [], "no Dock swipe")
        XCTAssertEqual(harness.outputs.shortcuts, 0)
        XCTAssertEqual(tester(harness)?.recent.first?.kind, .followedSwipe)

        harness.model.perform(.setGestureTesterPerformsSwipes(true))
        swipeLeft(harness)
        XCTAssertEqual(harness.outputs.dockPhases.filter { $0 != .changed }, [.began, .ended])
        XCTAssertFalse(harness.outputs.dockSwipes.isOpen)
    }

    /// The tester open on the strip: the ILITEK's swipes are done as always.
    func testTheOtherTouchscreensSwipesAreNotHeld() throws {
        let harness = try deskHarness(self)
        harness.model.perform(.openGestureTester(strip))
        swipeLeft(harness)
        XCTAssertEqual(harness.outputs.shortcuts, 1)
        XCTAssertEqual(tester(harness)?.recent, [])
    }

    func testLettingSwipesThroughWhenClosedChangesNothing() throws {
        let harness = try deskHarness(self)
        harness.model.perform(.setGestureTesterPerformsSwipes(true))
        harness.model.perform(.clearGestureTester)
        harness.model.perform(.closeGestureTester)
        XCTAssertNil(tester(harness))
        swipeLeft(harness)
        XCTAssertEqual(harness.outputs.shortcuts, 1)
    }

    /// Its pipeline started afresh (a new orientation) is observed too.
    func testAFreshPipelineIsObserved() throws {
        let harness = try openOnILITEK()
        harness.model.perform(.setOrientation(ilitek, Orientation(quarterTurns: 2, isFlipped: false)))
        tap(harness)
        settle(harness)
        XCTAssertEqual(tester(harness)?.recent.map(\.kind), [.tap])
    }

    func testItFollowsItsTouchscreensName() throws {
        let harness = try openOnILITEK()
        harness.model.perform(.rename(ilitek, to: "Desk"))
        XCTAssertEqual(tester(harness)?.touchscreenName, "Desk")
    }

    func testClearingEmptiesTheFeedAndTheCounts() throws {
        let harness = try openOnILITEK()
        tap(harness)
        settle(harness)
        XCTAssertEqual(tester(harness)?.recent.count, 1)
        harness.model.perform(.clearGestureTester)
        XCTAssertEqual(tester(harness)?.recent, [])
        XCTAssertEqual(tester(harness)?.seen, [])
        tap(harness)
        settle(harness)
        XCTAssertEqual(tester(harness)?.seen, [GestureSeenCount(id: .tap, count: 1)])
    }

    // MARK: - How often it changes

    /// A scroll with frames every 10 ms and the clock ticking 60 times a second: the tester's part of
    /// the snapshot changes at most every 0.1 s while it goes on; once it is over, what was last
    /// seen is published, and the clock stops.
    func testTheFeedChangesAtMostTenTimesASecond() throws {
        let harness = try openOnILITEK()
        harness.model.perform(.setOneFinger(ilitek, .alwaysScroll))
        var glass = Glass(ilitekSurface, at: harness.clock + 0.5)
        glass.land([(0, 200, 250)])
        glass.move(0, -150, steps: 100)  // a second of scrolling
        glass.rest(0.3)
        glass.lift()
        var changes: [TimeInterval] = []
        var last = tester(harness)
        var nextTick = glass.frames.first?.time ?? 0
        for frame in glass.frames {
            while nextTick < frame.time {
                harness.clock = nextTick
                harness.model.tickPipelines()
                if tester(harness) != last { changes.append(harness.clock); last = tester(harness) }
                nextTick += 1.0 / 60
            }
            harness.send([frame], from: Desk.ilitekHandle)
            if tester(harness) != last { changes.append(harness.clock); last = tester(harness) }
        }
        for _ in 0..<60 {
            harness.tick(after: 1.0 / 60)
            if tester(harness) != last { changes.append(harness.clock); last = tester(harness) }
        }
        XCTAssertGreaterThan(changes.count, 8, "it does change while the scroll goes on")
        for (earlier, later) in zip(changes, changes.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later - earlier, 0.1 - 1e-9, "\(changes)")
        }
        XCTAssertEqual(tester(harness), harness.model.gestureTester?.snapshot, "nothing left unpublished")
        XCTAssertEqual(tester(harness)?.recent.map(\.kind), [.scroll])
        XCTAssertEqual(tester(harness)?.fingersDown, 0)
        XCTAssertFalse(harness.ticker.isRunning, "the clock stops")
    }

    /// The windows that don't show the feed read `steadySnapshot`: through a whole scroll and the
    /// glide after it, which change `snapshot` again and again and add two entries to the counts, it
    /// is never set, so nothing that reads it is told.
    func testAGestureInTheTesterLeavesTheSteadySnapshotAlone() throws {
        let harness = try openOnILITEK()
        harness.model.perform(.setOneFinger(ilitek, .alwaysScroll))
        let steady = harness.model.steadySnapshot
        XCTAssertEqual(steady, harness.model.snapshot.withoutTesterFeed)
        XCTAssertEqual(steady.gestureTester?.touchscreen, ilitek, "it says the tester is open, and for which")
        let told = Told()
        withObservationTracking { _ = harness.model.steadySnapshot } onChange: { told.value = true }
        var changes = 0
        var last = tester(harness)
        var glass = Glass(ilitekSurface, at: harness.clock + 0.5)
        glass.land([(0, 200, 250)])
        glass.move(0, -150, steps: 100)
        glass.lift()
        for frame in glass.frames {
            harness.send([frame], from: Desk.ilitekHandle)
            harness.tick(after: 0.01)
            if tester(harness) != last { changes += 1; last = tester(harness) }
        }
        settle(harness)
        XCTAssertGreaterThan(changes, 8, "the feed changed while the scroll went on")
        XCTAssertEqual(tester(harness)?.recent.map(\.kind), [.flick, .scroll], "the scroll, and its glide: two counted")
        XCTAssertFalse(told.value, "the steady snapshot was never set")
        XCTAssertEqual(harness.model.steadySnapshot, steady)
        XCTAssertEqual(harness.model.steadySnapshot, harness.model.snapshot.withoutTesterFeed)

        harness.model.perform(.closeGestureTester)
        XCTAssertTrue(told.value, "closing the tester changes it")
        XCTAssertNil(harness.model.steadySnapshot.gestureTester)
    }

    /// `steadySnapshot` follows `snapshot` by construction, whoever writes it: a write that changes
    /// only the tester's feed, whole or in place, leaves it alone and is never told; a write that
    /// changes anything else sets it.
    func testTheSteadySnapshotFollowsEveryWriteOfTheSnapshot() throws {
        let harness = try openOnILITEK()
        let steady = harness.model.steadySnapshot
        let told = Told()
        withObservationTracking { _ = harness.model.steadySnapshot } onChange: { told.value = true }

        var feedOnly = harness.model.snapshot
        feedOnly.gestureTester?.fingersDown = 3
        harness.model.snapshot = feedOnly
        harness.model.snapshot.gestureTester?.fingersDown = 2
        XCTAssertEqual(tester(harness)?.fingersDown, 2)
        XCTAssertFalse(told.value, "a write of the feed alone never sets it")
        XCTAssertEqual(harness.model.steadySnapshot, steady)

        var changed = harness.model.snapshot
        changed.isOn.toggle()
        harness.model.snapshot = changed
        XCTAssertTrue(told.value, "a write of anything else sets it")
        XCTAssertEqual(harness.model.steadySnapshot, changed.withoutTesterFeed)
        XCTAssertEqual(harness.model.steadySnapshot.gestureTester?.fingersDown, 0, "still without the feed")
    }

    func testFingersDownFollowsTheGlass() throws {
        let harness = try openOnILITEK()
        let t = harness.clock + 0.5
        harness.send([glassFrame(t, (0, 0.4, 0.5), (1, 0.6, 0.5))], from: Desk.ilitekHandle)
        harness.tick(after: 0.11)
        XCTAssertEqual(tester(harness)?.fingersDown, 2)
        harness.send([glassFrame(harness.clock + 0.01, (1, 0.6, 0.5))], from: Desk.ilitekHandle)
        harness.tick(after: 0.11)
        XCTAssertEqual(tester(harness)?.fingersDown, 1)
        harness.send([glassFrame(harness.clock + 0.01)], from: Desk.ilitekHandle)
        harness.tick(after: 0.11)
        XCTAssertEqual(tester(harness)?.fingersDown, 0)
    }

    /// A touch no pipeline acts on (a palm alone) leaves no pipeline ticking once it lifts: the
    /// tester's own news keeps the clock going until it is published, then the clock stops.
    func testNewsNoPipelineWaitsForKeepsTheClockGoing() throws {
        let harness = try openOnILITEK()
        let t = harness.clock + 0.5
        let palm = Contact(id: 0, position: CGPoint(x: 0.5, y: 0.5), isConfident: false)
        harness.send([ContactFrame(time: t, contacts: [palm])], from: Desk.ilitekHandle)
        XCTAssertEqual(tester(harness)?.fingersDown, 1, "published at once: the first change in a while")
        harness.send([ContactFrame(time: t + 0.03, contacts: [])], from: Desk.ilitekHandle)
        XCTAssertEqual(tester(harness)?.fingersDown, 1, "the lift waits: 0.1 s haven't passed")
        XCTAssertTrue(harness.ticker.isRunning, "the clock runs for the tester's news")
        for _ in 0..<12 { harness.tick(after: 1.0 / 60) }
        XCTAssertEqual(tester(harness)?.fingersDown, 0)
        XCTAssertEqual(tester(harness)?.recent.map(\.summary), ["a palm"])
        XCTAssertFalse(harness.ticker.isRunning, "nothing left to publish")
    }

    /// The other touchscreen has the pointer: the touch is ignored, and said so.
    func testATouchIgnoredForTheOtherTouchscreenIsSaidSo() throws {
        let harness = try openOnILITEK()
        let t = harness.clock + 0.5
        harness.send([glassFrame(t, (0, 0.5, 0.5))], from: Desk.stripHandle)  // the strip has the pointer
        harness.send([glassFrame(t + 0.01, (0, 0.3, 0.3))], from: Desk.ilitekHandle)
        harness.send([glassFrame(t + 0.02, (0, 0.5, 0.5))], from: Desk.stripHandle)
        harness.send([glassFrame(t + 0.03)], from: Desk.ilitekHandle)
        harness.send([glassFrame(t + 0.04)], from: Desk.stripHandle)
        for _ in 0..<60 { harness.tick(after: 1.0 / 60) }
        XCTAssertEqual(tester(harness)?.recent.map(\.summary), ["the other touchscreen has the pointer"])
        XCTAssertEqual(tester(harness)?.fingersDown, 0)
        XCTAssertEqual(harness.outputs.count(.down), 1, "the strip's tap clicked; the ILITEK's touch didn't")
        XCTAssertFalse(harness.ticker.isRunning)
    }

    /// Fix round 1, item 2: while the tester is open, the state file is written at most once a
    /// second, plus a last time when a gesture's last change is published; the snapshot still changes
    /// up to ten times a second, and the file ends equal to it.
    func testTheStateFileIsWrittenAtMostOnceASecondWhileTheTesterIsOpen() throws {
        let harness = try deskHarness(self, writesStateFile: true)
        harness.model.perform(.openGestureTester(ilitek))
        var glass = Glass(ilitekSurface, at: harness.clock + 0.5)
        glass.land([(0, 200, 150), (1, 230, 150)])
        // 10 s of two-finger scrolling, down and up, drifting down 5 mm each time, so that every write
        // of the file differs from the one before.
        for move in 0..<50 { glass.move(0, move % 2 == 0 ? 40 : -35, steps: 20) }
        glass.rest(0.3)  // still before lifting: no flick
        glass.lift()
        var file = try Data(contentsOf: harness.stateURL)
        var writes = 0, snapshotChanges = 0
        var last = harness.model.snapshot
        func look() throws {
            let now = try Data(contentsOf: harness.stateURL)
            if now != file { writes += 1; file = now }
            if harness.model.snapshot != last { snapshotChanges += 1; last = harness.model.snapshot }
        }
        var nextTick = glass.frames[0].time
        for frame in glass.frames {
            while nextTick < frame.time {
                harness.clock = nextTick
                harness.model.tickPipelines()
                try look()
                nextTick += 1.0 / 60
            }
            harness.send([frame], from: Desk.ilitekHandle)
            try look()
        }
        for _ in 0..<120 {
            harness.tick(after: 1.0 / 60)
            try look()
        }
        XCTAssertGreaterThan(snapshotChanges, 80, "the snapshot changes about ten times a second")
        XCTAssertLessThanOrEqual(writes, 11, "the file at most once a second, and once at the end")
        XCTAssertGreaterThanOrEqual(writes, 9)
        let written = try JSONDecoder().decode(AppSnapshot.self, from: file)
        XCTAssertEqual(written, harness.model.snapshot, "the file ends equal to the snapshot")
        XCTAssertEqual(written.gestureTester?.recent.map(\.kind), [.scroll])
        XCTAssertFalse(harness.ticker.isRunning)
    }

    /// The last change of a flick (its momentum ending) reaches the file too, and a tap's at once.
    func testTheStateFileCatchesUpAtTheEndOfEachGesture() throws {
        let harness = try deskHarness(self, writesStateFile: true)
        harness.model.perform(.openGestureTester(ilitek))
        harness.model.perform(.setOneFinger(ilitek, .alwaysScroll))
        var glass = Glass(ilitekSurface, at: harness.clock + 0.5)
        glass.land([(0, 200, 250)])
        glass.move(0, -150)
        glass.lift()
        harness.send(glass.frames, from: Desk.ilitekHandle)
        settle(harness, 3)
        func written() throws -> AppSnapshot {
            try JSONDecoder().decode(AppSnapshot.self, from: Data(contentsOf: harness.stateURL))
        }
        XCTAssertEqual(tester(harness)?.recent.map(\.kind), [.flick, .scroll])
        XCTAssertEqual(try written(), harness.model.snapshot)
        tap(harness)
        XCTAssertEqual(try written(), harness.model.snapshot, "the tap's last change, written at once")
        settle(harness, 0.5)
        XCTAssertEqual(try written(), harness.model.snapshot)
        XCTAssertFalse(harness.ticker.isRunning)
    }

    func testTheStateFileHasTheFeed() throws {
        let harness = try deskHarness(self, writesStateFile: true)
        harness.model.perform(.openGestureTester(ilitek))
        tap(harness)
        settle(harness)
        let written = try JSONDecoder().decode(AppSnapshot.self, from: Data(contentsOf: harness.stateURL))
        XCTAssertEqual(written.gestureTester, tester(harness))
        XCTAssertEqual(written.gestureTester?.recent.map(\.kind), [.tap])
        XCTAssertEqual(written, harness.model.snapshot)
    }
}

/// Whether an observation's change was told: set from its `onChange`, read once the test's own
/// calls have returned, all on the main thread.
final class Told: @unchecked Sendable {
    var value = false
}
