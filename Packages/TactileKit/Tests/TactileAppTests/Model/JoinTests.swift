// Delivery 5, Part J: what only the four streams together can show. Set-up mode (S) and the
// gesture tester (T1) in one model; the tester's button and checklist (T2) against the model's own
// rule and the real narrator; set-up mode's menu item and pane button (U) against the model's
// refusal; and the preview's `justSetUp` against the model's. Through the model with its fakes and
// a real gesture engine: no device, event, window or pointer; the settings folder is temporary.

import CoreGraphics
import Foundation
@testable import TactileApp
import TactileDevices
import TactileGestures
import TactileReading
import TactileScreens
import XCTest

private typealias Desk = DeskFixture

@MainActor
final class JoinTests: XCTestCase {
    private let ilitek = Desk.ilitekID
    private let strip = Desk.stripID
    private let ilitekSurface = Desk.driving(on: Desk.hdmi, diagonal: 23.8).surfaceSizeMM
    private let lgMirroringHDMI = with(Desk.lg) { $0.mirrors = Desk.hdmi.displayID }

    private func shown(_ id: TouchscreenID, _ harness: ModelHarness) -> TouchscreenSnapshot? {
        harness.model.snapshot.touchscreens.first { $0.id == id }
    }

    /// Ticks 60 times a second for `seconds`, as the model's clock would.
    private func settle(_ harness: ModelHarness, _ seconds: TimeInterval = 1) {
        for _ in 0..<Int(seconds * 60) { harness.tick(after: 1.0 / 60) }
    }

    /// A tap at glass point `p` of `handle`: landing now, held still 0.1 s in frames 10 ms apart.
    private func tap(_ p: CGPoint, _ harness: ModelHarness, _ handle: DeviceHandle = Desk.ilitekHandle) {
        let t = harness.clock
        harness.send((0..<10).map { glassFrame(t + Double($0) * 0.01, (1, p.x, p.y)) } + [glassFrame(t + 0.1)], from: handle)
    }

    /// Feeds `frames` with 60 Hz ticks between them, as the model's clock would.
    private func play(_ frames: [ContactFrame], _ harness: ModelHarness, from handle: DeviceHandle) {
        for frame in frames {
            while harness.clock + 1.0 / 60 < frame.time { harness.tick(after: 1.0 / 60) }
            harness.send([frame], from: handle)
        }
    }

    // MARK: - The tester closes when set-up begins

    /// T1 closes the tester when the resolved snapshot carries `setUp` or `setUpMode` at step 4 of a
    /// round; S puts the mode into the snapshot through `inputs.setUpMode` before that step. Both
    /// routes into the mode (the menu's item and a pane's Set Up by Touch…, which sends
    /// `beginSetUp(_, .full)`) close it, and it can't be opened while the mode is on, for either
    /// touchscreen; once the mode ends it can.
    func testSetUpModeBeginningClosesTheTesterAndItCannotOpenWhileTheModeIsOn() throws {
        for begin in [AppCommand.beginSetUpMode, .beginSetUp(Desk.stripID, .full)] {
            let harness = try deskHarness(self)
            harness.model.perform(.openGestureTester(ilitek))
            XCTAssertEqual(harness.model.snapshot.gestureTester?.touchscreen, ilitek)

            harness.model.perform(begin)
            XCTAssertNotNil(harness.model.snapshot.setUpMode, "\(begin)")
            XCTAssertNil(harness.model.snapshot.gestureTester, "\(begin): closed as set-up began")
            XCTAssertNil(harness.model.gestureTester, "\(begin)")

            for id in [ilitek, strip] {
                harness.model.perform(.openGestureTester(id))
                XCTAssertNil(harness.model.snapshot.gestureTester, "\(begin): refused for \(id) while the mode is on")
                let touchscreen = try XCTUnwrap(shown(id, harness))
                XCTAssertEqual(GestureTesterAvailability.of(touchscreen, in: harness.model.snapshot),
                               .unavailable(.setUpRunning), "\(begin): the button says so")
            }

            harness.model.perform(.cancelSetUp)
            XCTAssertNil(harness.model.snapshot.setUpMode)
            harness.model.perform(.openGestureTester(strip))
            XCTAssertEqual(harness.model.snapshot.gestureTester?.touchscreen, strip, "\(begin): it opens again after")
        }
    }

    // MARK: - A swipe or a drag under way when set-up mode begins

    /// A followed three-finger swipe under way in the tester, held there or let through, when set-up
    /// mode begins (the first-run window, the menu, the pane): the tester closes; a held swipe has
    /// posted nothing and posts nothing; a let-through one gets exactly one end, never two, never
    /// none; never the shortcut; no button held. The rest of the swipe, and its lift, answer nothing
    /// in the mode, and the tester stays closed after Finish.
    func testAFollowedSwipeTheTesterHoldsOrLetsThroughWhenSetUpModeBegins() throws {
        for letThrough in [false, true] {
            let name = letThrough ? "let through" : "held"
            let harness = try deskHarness(self)
            harness.model.perform(.setSwipesFollowFingers(true))
            harness.model.perform(.openGestureTester(ilitek))
            if letThrough { harness.model.perform(.setGestureTesterPerformsSwipes(true)) }
            XCTAssertNotNil(harness.model.snapshot.gestureTester, name)
            var glass = Glass(ilitekSurface, at: harness.clock + 0.5)
            glass.land((0..<3).map { ($0, 180 + 25 * Double($0), 150) })
            glass.move(-40, 0, steps: 20)
            play(glass.frames, harness, from: Desk.ilitekHandle)
            XCTAssertEqual(harness.outputs.dockPhases.filter { $0 == .began }.count, letThrough ? 1 : 0,
                           "\(name): the followed swipe under way")

            harness.model.perform(.beginSetUpMode)
            XCTAssertNotNil(harness.model.snapshot.setUpMode, name)
            XCTAssertNil(harness.model.snapshot.gestureTester, "\(name): closed as the mode began")
            var rest = Glass(ilitekSurface, at: harness.clock + 0.01)
            rest.land((0..<3).map { ($0, 140 + 25 * Double($0), 150) })
            rest.move(-30, 0, steps: 10)
            rest.lift()
            play(rest.frames, harness, from: Desk.ilitekHandle)
            settle(harness, 2)
            let phases = harness.outputs.dockPhases.filter { $0 != .changed }
            XCTAssertEqual(phases.filter { $0 == .began }.count, letThrough ? 1 : 0, "\(name): \(phases)")
            XCTAssertEqual(phases.filter { $0 == .ended || $0 == .cancelled }.count, letThrough ? 1 : 0,
                           "\(name): exactly one end: \(phases)")
            XCTAssertFalse(harness.outputs.dockSwipes.isOpen, name)
            XCTAssertEqual(harness.outputs.shortcuts, 0, "\(name): never the shortcut")
            XCTAssertEqual(harness.outputs.count(.down), harness.outputs.count(.up), "\(name): no button held")
            XCTAssertEqual(harness.model.snapshot.setUpMode?.stage, .choosing, "\(name): the lift answered nothing")

            harness.model.perform(.cancelSetUp)
            XCTAssertNil(harness.model.snapshot.setUpMode, name)
            XCTAssertNil(harness.model.snapshot.gestureTester, "\(name): the tester stays closed")
        }
    }

    /// A one-finger drag holding the button (Always drag) with the tester open, when set-up mode
    /// begins: the button comes up, once; nothing more is posted while the mode is on.
    func testADragHeldWhenSetUpModeBeginsLetsTheButtonUpOnce() throws {
        let harness = try deskHarness(self)
        harness.model.perform(.setOneFinger(ilitek, .alwaysDrag))
        harness.model.perform(.openGestureTester(ilitek))
        var glass = Glass(ilitekSurface, at: harness.clock + 0.5)
        glass.land([(0, 200, 150)])
        glass.move(40, 0, steps: 20)
        play(glass.frames, harness, from: Desk.ilitekHandle)
        XCTAssertEqual(harness.outputs.count(.down), 1)
        XCTAssertEqual(harness.outputs.count(.up), 0, "the button held")

        harness.model.perform(.beginSetUpMode)
        XCTAssertEqual(harness.outputs.count(.up), 1, "the button came up")
        let before = harness.outputs.events.count
        var rest = Glass(ilitekSurface, at: harness.clock + 0.01)
        rest.land([(0, 240, 150)])
        rest.move(30, 0, steps: 10)
        rest.lift()
        play(rest.frames, harness, from: Desk.ilitekHandle)
        settle(harness, 1)
        XCTAssertEqual(harness.outputs.events.count, before, "nothing posted in the mode")
        harness.model.perform(.cancelSetUp)
        XCTAssertEqual(harness.outputs.count(.down), 1, "pressed once")
        XCTAssertEqual(harness.outputs.count(.up), 1, "up once")
    }

    // MARK: - The tester's button: one rule with the model

    /// Gesture Tester…, in the pane and the menu, is enabled exactly when the model would open the
    /// tester, in every situation of the desk, and its reason is the model's refusal in words.
    func testTheTestersButtonIsEnabledExactlyWhenTheModelWouldOpenIt() throws {
        typealias Reason = GestureTesterAvailability.Reason
        let situations: [(String, (ModelHarness) -> Void, ilitek: Reason?, strip: Reason?)] = [
            ("the desk", { _ in }, nil, nil),
            ("Tactile off", { $0.model.perform(.setOn(false)) }, .tactileOff, .tactileOff),
            ("Accessibility missing", { $0.conditions.setAccessibility(false) }, .accessibilityMissing, .accessibilityMissing),
            ("locked", { $0.conditions.setSessionActive(false) }, .notDriving, .notDriving),
            ("asleep", { $0.conditions.sleep() }, .notDriving, .notDriving),
            ("the ILITEK switched off", { $0.model.perform(.setTouchscreenOn(Desk.ilitekID, false)) }, .off, nil),
            ("the ILITEK switched off, left to macOS", {
                $0.model.perform(.setWhenOff(Desk.ilitekID, .leaveToMacOS))
                $0.model.perform(.setTouchscreenOn(Desk.ilitekID, false))
            }, .off, nil),
            ("the ILITEK unpaired", { $0.model.perform(.unpair(Desk.ilitekID)) }, .notSetUp, nil),
            ("HDMI unplugged", { $0.displays.set(Desk.displays.filter { $0 != Desk.hdmi }) }, .displayNotConnected, nil),
            ("the displays settling", { $0.displays.set([]) }, .notDriving, .notDriving),
            ("HDMI mirroring LG", { $0.displays.set([Desk.builtIn, with(Desk.hdmi) { $0.mirrors = Desk.lg.displayID }, Desk.lg,
                                                     Desk.strip, Desk.display]) }, nil, nil),
            ("the ILITEK's touches unreadable", {
                $0.source.change(Desk.ilitekHandle) { $0.status = Desk.taken(origin: .unreadable) }
            }, .touchesCannotBeRead, nil),
            ("macOS also handles the strip", {
                $0.source.change(Desk.stripHandle) { $0.status = Desk.taken(origin: .mouseInterface, exclusive: .failed) }
            }, nil, .macOSAlsoHandlesIt),
            ("set-up mode", { $0.model.perform(.beginSetUpMode) }, .setUpRunning, .setUpRunning),
            ("a test of the strip", { $0.model.perform(.beginSetUp(Desk.stripID, .test)) }, .setUpRunning, .setUpRunning),
            ("the ILITEK unplugged", { $0.source.unplug(Desk.ilitekHandle) }, .notConnected, nil),
        ]
        for (name, change, ilitekReason, stripReason) in situations {
            for (id, expected) in [(ilitek, ilitekReason), (strip, stripReason)] {
                let harness = try deskHarness(self)
                change(harness)
                let snapshot = harness.model.snapshot
                let touchscreen = try XCTUnwrap(snapshot.touchscreens.first { $0.id == id }, name)
                let availability = GestureTesterAvailability.of(touchscreen, in: snapshot)
                XCTAssertEqual(availability, expected.map { .unavailable($0) } ?? .available, "\(name): \(id)")
                if let refusal = Resolver.gestureTesterRefusal(for: id, in: snapshot) {
                    XCTAssertEqual(availability, .unavailable(Reason(refusal, touchscreen)), "\(name): \(id): the model's refusal")
                }
                // The menu: its details offer the item with the pane's rule; where they say it can't
                // be used at all, they offer nothing, and the model would refuse it too.
                let details = MenuTouchscreenDetails(touchscreen, in: snapshot)
                if details.unusable != nil {
                    XCTAssertNotEqual(availability, .available, "\(name): \(id): nothing offered that would work")
                } else {
                    XCTAssertEqual(details.controls?.gestureTester, touchscreen.isConnected ? availability : nil,
                                   "\(name): \(id): the menu says the same")
                }

                harness.model.perform(.openGestureTester(id))
                let opened = harness.model.snapshot.gestureTester?.touchscreen == id
                XCTAssertEqual(opened, availability == .available, "\(name): \(id): the model did what the button said")
            }
        }

        // Two identical panels with no USB location: neither has a record. The model's reason, not
        // "set it up first": no set-up could help.
        let facts = TouchscreenFacts(vendorID: 0x1234, productID: 0x5678, serial: "", locationID: 0, name: "Panel")
        let harness = try deskHarness(self)
        harness.source.plugIn(Desk.ilitek(handle: DeviceHandle(rawValue: 7), facts: facts))
        harness.source.plugIn(Desk.ilitek(handle: DeviceHandle(rawValue: 8), facts: facts))
        let twins = harness.model.snapshot.touchscreens.filter { $0.notes.contains(.cannotBeToldApart) }
        XCTAssertEqual(twins.count, 2)
        for twin in twins {
            XCTAssertEqual(GestureTesterAvailability.of(twin, in: harness.model.snapshot), .unavailable(.cannotBeToldApart))
            harness.model.perform(.openGestureTester(twin.id))
            XCTAssertNil(harness.model.snapshot.gestureTester)
        }
    }

    // MARK: - The narrator ticks the checklist

    /// The real narrator, through the model and a real engine, fills the tester's feed; the window's
    /// checklist counts it. The rows that tell a kind apart by its fingers tick: one- and two-finger
    /// scrolls and their flicks, the right-click from a long press and from a two-finger tap, and
    /// three- and four-finger swipes; the rows of whole kinds count the model's `seen`.
    func testTheNarratorTicksTheChecklistsRowsThatCountByFingers() throws {
        let harness = try deskHarness(self)
        harness.model.perform(.setOneFinger(ilitek, .alwaysScroll))
        harness.model.perform(.openGestureTester(ilitek))
        var tally = GestureTally()
        func play(_ make: (inout Glass) -> Void, settling seconds: TimeInterval = 1.5) {
            var glass = Glass(ilitekSurface, at: harness.clock + 0.5)
            make(&glass)
            harness.send(glass.frames, from: Desk.ilitekHandle)
            settle(harness, seconds)
            tally.follow(harness.model.snapshot.gestureTester)
        }
        // One finger: a slow scroll that stops, then a flick.
        play { $0.land([(0, 200, 200)]); $0.move(0, -40, steps: 40); $0.rest(0.3); $0.lift() }
        play({ $0.land([(0, 200, 220)]); $0.move(0, -120, steps: 8); $0.lift() }, settling: 3)
        // Two fingers: the same.
        play { $0.land([(0, 200, 200), (1, 240, 200)]); $0.move(0, -40, steps: 40); $0.rest(0.3); $0.lift() }
        play({ $0.land([(0, 200, 220), (1, 240, 220)]); $0.move(0, -120, steps: 8); $0.lift() }, settling: 3)
        // A long press, and a two-finger tap: each a right-click.
        play { $0.land([(0, 200, 150)]); $0.rest(1.0); $0.lift() }
        play { $0.land([(0, 200, 150), (1, 240, 150)]); $0.rest(0.1); $0.lift() }
        // Three fingers left, four fingers up.
        play { $0.land((0..<3).map { ($0, 180 + 25 * Double($0), 150) }); $0.move(-60, 0, steps: 20); $0.lift() }
        play { $0.land((0..<4).map { ($0, 180 + 25 * Double($0), 150) }); $0.move(0, -60, steps: 20); $0.lift() }

        let tester = try XCTUnwrap(harness.model.snapshot.gestureTester)
        let feed = tester.recent.reversed().map { "\($0.kind.rawValue) \($0.fingers): \($0.summary)" }
        let touchscreen = try XCTUnwrap(shown(ilitek, harness))
        let rows = GestureTesterRow.rows(
            behaviour: touchscreen.behaviour, multiTouch: tester.multiTouch,
            swipesFollowFingers: harness.model.snapshot.swipesFollowFingers,
            canFollowSwipes: harness.model.snapshot.canFollowSwipes)
        func count(_ kind: GestureTesterRow.Kind) throws -> Int {
            try XCTUnwrap(rows.first { $0.kind == kind }, "\(kind)").count(seen: tester.seen, tally: tally)
        }
        XCTAssertEqual(try count(.oneFinger), 3, "two one-finger scrolls and a flick: \(feed)")
        XCTAssertEqual(try count(.twoFingerScroll), 3, "two two-finger scrolls and a flick: \(feed)")
        XCTAssertEqual(try count(.longPress), 1, "the long press's right-click: \(feed)")
        XCTAssertEqual(try count(.twoFingerTap), 1, "the two-finger tap's right-click: \(feed)")
        XCTAssertEqual(try count(.threeFingerSwipes), 1, "\(feed)")
        XCTAssertEqual(try count(.fourFingerSwipes), 1, "\(feed)")
        XCTAssertEqual(try count(.tap), 0, "nothing here was a tap: \(feed)")
        XCTAssertEqual(harness.outputs.shortcuts, 0, "the swipes were held")
    }

    /// On the strip, one finger only: its one-finger scroll (Always scroll, its default) and its
    /// long press tick their rows; a hold, then a drag ticks the drag row.
    func testTheStripsOneFingerRowsTick() throws {
        let harness = try deskHarness(self)
        XCTAssertEqual(shown(strip, harness)?.behaviour.oneFinger, .alwaysScroll, "its default")
        harness.model.perform(.openGestureTester(strip))
        let surface = Desk.driving(on: Desk.strip, diagonal: 12.3).surfaceSizeMM
        var tally = GestureTally()
        func play(_ make: (inout Glass) -> Void) {
            var glass = Glass(surface, at: harness.clock + 0.5)
            make(&glass)
            harness.send(glass.frames, from: Desk.stripHandle)
            settle(harness, 3)
            tally.follow(harness.model.snapshot.gestureTester)
        }
        play { $0.land([(0, 100, 60)]); $0.move(0, -30, steps: 30); $0.rest(0.3); $0.lift() }
        play { $0.land([(0, 100, 40)]); $0.rest(1.0); $0.lift() }
        play { $0.land([(0, 100, 40)]); $0.rest(0.5); $0.move(40, 0, steps: 20); $0.lift() }

        let tester = try XCTUnwrap(harness.model.snapshot.gestureTester)
        XCTAssertFalse(tester.multiTouch)
        let feed = tester.recent.reversed().map { "\($0.kind.rawValue) \($0.fingers): \($0.summary)" }
        let touchscreen = try XCTUnwrap(shown(strip, harness))
        let rows = GestureTesterRow.rows(behaviour: touchscreen.behaviour, multiTouch: false,
                                         swipesFollowFingers: false, canFollowSwipes: true)
        func count(_ kind: GestureTesterRow.Kind) throws -> Int {
            try XCTUnwrap(rows.first { $0.kind == kind }, "\(kind)").count(seen: tester.seen, tally: tally)
        }
        XCTAssertEqual(try count(.oneFinger), 1, "\(feed)")
        XCTAssertEqual(try count(.longPress), 1, "\(feed)")
        XCTAssertEqual(try count(.drag), 1, "hold, then drag: \(feed)")
    }

    // MARK: - One finger: the tester's picker and the pane's

    /// The tester's one-finger picker is the pane's: on the strip at its default, Automatic then
    /// Always scroll chosen in the tester store a choice; the tester's Default gives the default
    /// back, as the pane's does, with the tester still open.
    func testTheTestersOneFingerPickerGivesTheDefaultBack() throws {
        let harness = try deskHarness(self)
        harness.model.perform(.openGestureTester(strip))
        func picker() throws -> OneFingerPicker {
            let touchscreen = try XCTUnwrap(shown(strip, harness))
            let snapshot = harness.model.snapshot
            let rows = GestureTesterRow.rows(
                for: touchscreen, multiTouch: false, swipesFollowFingers: snapshot.swipesFollowFingers,
                canFollowSwipes: snapshot.canFollowSwipes)
            return try XCTUnwrap(rows.first { $0.kind == .oneFinger }?.oneFingerPicker)
        }
        func choose(_ option: OneFingerMode?) throws {
            if let command = try picker().command(option, for: strip) { harness.model.perform(command) }
        }
        XCTAssertNil(try picker().choice)
        XCTAssertEqual(try picker().inForce, .alwaysScroll, "its default")
        try choose(.automatic)
        try choose(.alwaysScroll)
        XCTAssertEqual(shown(strip, harness)?.behaviour.oneFingerChoice, .alwaysScroll, "a choice, stored")
        try choose(nil)
        XCTAssertNil(shown(strip, harness)?.behaviour.oneFingerChoice, "the default, given back from the tester")
        XCTAssertEqual(shown(strip, harness)?.behaviour.oneFinger, .alwaysScroll)
        XCTAssertEqual(try picker(), OneFingerPicker(try XCTUnwrap(shown(strip, harness))), "the pane's picker")
        XCTAssertEqual(harness.model.snapshot.gestureTester?.touchscreen, strip, "the tester stays open")
    }

    // MARK: - The card just set up: the model and the preview agree

    /// In set-up mode a calibration's Done marks its touchscreen as just set up and a test's Done
    /// marks nothing: in the model (S) as in the preview the screens were drawn from (U).
    func testACalibrationIsJustSetUpAndATestIsNotInTheModelAsInThePreview() throws {
        let harness = try deskHarness(self)
        harness.model.perform(.beginSetUpMode)
        harness.tick(after: 1.1)
        harness.model.perform(.beginSetUp(ilitek, .test))
        XCTAssertEqual(harness.model.snapshot.setUp?.purpose, .test)
        harness.tick(after: 0.6)
        harness.model.perform(.setUpDone)
        XCTAssertNil(harness.model.snapshot.setUp)
        XCTAssertEqual(harness.model.snapshot.setUpMode?.stage, .choosing)
        XCTAssertNil(harness.model.snapshot.setUpMode?.justSetUp, "the model: a test sets nothing up")

        harness.model.perform(.beginSetUp(ilitek, .calibrate))
        XCTAssertEqual(harness.model.snapshot.setUp?.purpose, .calibrate)
        for point in SetUpDesk.cornerTaps(on: Desk.hdmi, orientation: .asFitted, rect: SetUpDesk.wholeGlass) {
            harness.tick(after: 1.1)
            tap(point, harness)
        }
        guard case .check? = harness.model.snapshot.setUp?.step else {
            return XCTFail("at the check: \(String(describing: harness.model.snapshot.setUp))")
        }
        harness.tick(after: 0.6)
        harness.model.perform(.setUpDone)
        XCTAssertEqual(harness.model.snapshot.setUpMode?.justSetUp, ilitek, "the model: a calibration's Done")

        let preview = PreviewModel(.desk)
        preview.perform(.beginSetUpMode)
        preview.perform(.beginSetUp(ilitek, .test))
        preview.perform(.setUpDone)
        XCTAssertEqual(preview.snapshot.setUpMode?.stage, .choosing)
        XCTAssertNil(preview.snapshot.setUpMode?.justSetUp, "the preview: a test sets nothing up")
        preview.perform(.beginSetUp(ilitek, .calibrate))
        XCTAssertEqual(preview.snapshot.setUp?.purpose, .calibrate)
        for _ in 0..<4 { preview.touchSetUp() }
        preview.perform(.setUpDone)
        XCTAssertEqual(preview.snapshot.setUpMode?.justSetUp, ilitek, "the preview: a calibration's Done")
    }

    // MARK: - Set Up Touchscreens… and Set Up by Touch… against the model

    /// The menu's item and each pane's button are enabled exactly when the model would begin the
    /// mode, in every situation where it can't, and each says a reason that fits: Tactile off,
    /// Accessibility missing, locked, the displays settling, another set-up running, no touchscreen
    /// that can be set up, no display to set one up on, and mirror sets that leave none, whether a
    /// touchscreen drives or none does.
    func testSetUpModesMenuItemAndPaneButtonFollowTheModel() throws {
        typealias Reason = SetUpModeAvailability.Reason
        let mirrorsOnly = [Desk.builtIn, lgMirroringHDMI, Desk.hdmi]
        let situations: [(String, (ModelHarness) -> Void, Reason?)] = [
            ("the desk", { _ in }, nil),
            ("Tactile off", { $0.model.perform(.setOn(false)) }, .tactileOff),
            ("Accessibility missing", { $0.conditions.setAccessibility(false) }, .accessibilityMissing),
            ("locked", { $0.conditions.setSessionActive(false) }, .notNow),
            ("the displays settling", { $0.displays.set([]) }, .notNow),
            ("another set-up running", { $0.model.perform(.beginSetUp(Desk.stripID, .test)) }, .running),
            ("set-up mode on", { $0.model.perform(.beginSetUpMode) }, .running),
            ("no touchscreen can be set up", {
                $0.source.change(Desk.ilitekHandle) { $0.status = Desk.taken(origin: .unreadable) }
                $0.source.change(Desk.stripHandle) { $0.status = Desk.taken(origin: .mouseInterface, exclusive: .failed) }
            }, .noneCanBeSetUp),
            ("no touchscreen connected", {
                $0.source.unplug(Desk.ilitekHandle)
                $0.source.unplug(Desk.stripHandle)
            }, .noTouchscreen),
            ("only the built-in display", { $0.displays.set([Desk.builtIn]) }, .noExternalDisplay),
            ("a mirror set and nothing else", { $0.displays.set(mirrorsOnly) }, .noDisplayToChoose),
            // No touchscreen drives in these two: only the model can say why, and it is not a
            // passing reason.
            ("a mirror set and a touchscreen never set up", {
                $0.source.unplug(Desk.ilitekHandle)
                $0.source.unplug(Desk.stripHandle)
                $0.source.plugIn(Desk.ilitek(handle: DeviceHandle(rawValue: 9), facts: TouchscreenFacts(
                    vendorID: 0x222a, productID: 0x0001, serial: "NEW", locationID: 0x0120_0000, name: "ILITEK-TP")))
                $0.displays.set(mirrorsOnly)
            }, .noDisplayToChoose),
            ("a mirror set and the ILITEK switched off", {
                $0.source.unplug(Desk.stripHandle)
                $0.model.perform(.setTouchscreenOn(Desk.ilitekID, false))
                $0.displays.set(mirrorsOnly)
            }, .noDisplayToChoose),
            ("a mirror set beside the strip", {
                $0.displays.set([Desk.builtIn, self.lgMirroringHDMI, Desk.hdmi, Desk.strip])
            }, nil),
        ]
        for (name, change, expected) in situations {
            let harness = try deskHarness(self)
            change(harness)
            let snapshot = harness.model.snapshot
            let menu = SetUpModeAvailability(snapshot)
            XCTAssertEqual(menu, expected.map { .unavailable($0) } ?? .available, name)
            for touchscreen in snapshot.touchscreens where touchscreen.isConnected && touchscreen.canBeSetUpByTouch {
                let pane = SetUpAvailability.full(touchscreen, in: snapshot)
                XCTAssertEqual(pane == .available, menu == .available, "\(name): \(touchscreen.name)'s pane")
            }
            if let reason = menu.reason {
                XCTAssertFalse(Wording.setUpModeUnavailable(reason).isEmpty, name)
            }
            // Where the model alone knows why, the pane says what the menu says.
            for touchscreen in snapshot.touchscreens where touchscreen.isConnected && touchscreen.canBeSetUpByTouch {
                switch menu.reason {
                case .notNow?:
                    XCTAssertEqual(SetUpAvailability.full(touchscreen, in: snapshot), .unavailable(.notNow), name)
                case .noDisplayToChoose?:
                    XCTAssertEqual(SetUpAvailability.full(touchscreen, in: snapshot), .unavailable(.noDisplayToChoose), name)
                    XCTAssertEqual(Wording.setUpUnavailable(.noDisplayToChoose), Wording.setUpModeUnavailable(.noDisplayToChoose))
                default:
                    break
                }
            }
            harness.model.perform(.beginSetUpMode)
            let began = snapshot.setUpMode == nil && harness.model.snapshot.setUpMode != nil
            XCTAssertEqual(began, menu == .available, "\(name): the model began the mode only when the menu said it could")
        }
    }

    /// While the mode is on, a touchscreen that can't be set up has a line on the session card with
    /// the reason its pane gives: the twin, one whose touches can't be read, one macOS also handles.
    func testTheSessionCardsReasonIsThePanes() throws {
        let cases: [(String, (ModelHarness) -> Void, SetUpAvailability.Reason)] = [
            ("touches unreadable", {
                $0.source.change(Desk.stripHandle) { $0.status = Desk.taken(origin: .unreadable) }
            }, .touchesCannotBeRead),
            ("macOS also handles it", {
                $0.source.change(Desk.stripHandle) { $0.status = Desk.taken(origin: .mouseInterface, exclusive: .failed) }
            }, .macOSAlsoHandlesIt),
        ]
        for (name, change, reason) in cases {
            let harness = try deskHarness(self)
            change(harness)
            let pane = try XCTUnwrap(shown(strip, harness))
            XCTAssertEqual(SetUpAvailability.full(pane, in: harness.model.snapshot), .unavailable(reason), name)
            harness.model.perform(.beginSetUpMode)
            let line = try XCTUnwrap(harness.model.snapshot.setUpMode?.touchscreens.first { $0.id == strip }, name)
            XCTAssertEqual(line.state, .cannotBeSetUp, name)
            XCTAssertEqual(line.reason, Wording.setUpUnavailable(reason), name)
        }
    }

    // MARK: - macOS also handles it, before the first touch after a launch

    /// Re-review of S, the may-wait item: a touchscreen remembered as giving one finger, which
    /// Tactile couldn't take for itself, and which hasn't been touched since the launch. Its pane says
    /// macOS also handles it (the remembered one-finger note with "macOS may also respond"), so
    /// Calibrate, Test and Set Up by Touch… are unavailable; the model, by the same rule, holds it,
    /// runs no set-up of it, and gives the same reason on the session card.
    func testATouchscreenRememberedAsOneFingerThatMacOSAlsoHandlesIsHeldBeforeItsFirstTouch() throws {
        var settings = Desk.settings
        settings.touchscreens[strip]?.lastGaveOneFinger = true
        let harness = try ModelHarness(settings: settings)
        addTeardownBlock { @MainActor in harness.cleanUp() }
        harness.source.statusWhenTaken[Desk.stripHandle] = Desk.taken(origin: .undetermined, exclusive: .failed)
        harness.source.plugIn(Desk.ilitek())
        harness.source.plugIn(Desk.stripScreen())
        harness.model.start()

        let pane = try XCTUnwrap(shown(strip, harness))
        XCTAssertTrue(pane.macOSAlsoHandlesIt, "the pane: \(pane.notes)")
        XCTAssertEqual(SetUpAvailability.onItsDisplay(pane, in: harness.model.snapshot), .unavailable(.macOSAlsoHandlesIt))
        XCTAssertEqual(SetUpAvailability.full(pane, in: harness.model.snapshot), .unavailable(.macOSAlsoHandlesIt))
        XCTAssertEqual(pane.mode, .held, "the model holds it: driving it too would handle every touch twice")
        XCTAssertFalse(pane.canBeSetUp)
        XCTAssertEqual(GestureTesterAvailability.of(pane, in: harness.model.snapshot), .unavailable(.macOSAlsoHandlesIt))

        harness.model.perform(.beginSetUp(strip, .test))
        XCTAssertNil(harness.model.snapshot.setUp, "no test of it")
        harness.model.perform(.beginSetUpMode)
        let line = try XCTUnwrap(harness.model.snapshot.setUpMode?.touchscreens.first { $0.id == strip })
        XCTAssertEqual(line.state, .cannotBeSetUp)
        XCTAssertEqual(line.reason, Wording.setUpUnavailable(.macOSAlsoHandlesIt))
        harness.model.perform(.cancelSetUp)

        // Its first touch from its touch interface: it gives every finger after all, so macOS doesn't
        // handle it, and it drives.
        harness.source.change(Desk.stripHandle) { $0.status = Desk.taken(origin: .touchInterface, exclusive: .failed) }
        XCTAssertEqual(shown(strip, harness)?.mode, .driving)
        XCTAssertFalse(try XCTUnwrap(shown(strip, harness)).macOSAlsoHandlesIt)
    }
}
