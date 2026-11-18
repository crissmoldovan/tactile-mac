// Delivery 3, M2, and Delivery 5: set-up in the resolver and the model, a full set-up through set-up
// mode. Through the model with its fakes: no device, event, window or pointer; the settings folder is
// temporary. Set-up mode's own rules are in `SetUpModeModelTests` and `SetUpSessionTests`.

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
final class SetUpModelTests: XCTestCase {
    private let ilitek = Desk.ilitekID
    private let strip = Desk.stripID
    /// How the ILITEK's glass is fitted in these tests: turned half round, the picture a little in
    /// from its edges.
    private let turned = Orientation(quarterTurns: 2, isFlipped: false)
    private let rect = SetUpDesk.offCentre

    // MARK: - Helpers

    private func makeHarness(settings: TactileSettings? = nil) throws -> ModelHarness {
        let harness = try ModelHarness(settings: settings)
        addTeardownBlock { @MainActor in harness.cleanUp() }
        harness.source.statusWhenTaken[Desk.stripHandle] = Desk.taken(origin: .mouseInterface, inputMode: .switchedToMultiTouch)
        return harness
    }

    /// The desk's settings with the ILITEK unpaired and never offered set-up.
    private var ilitekUnpaired: TactileSettings {
        with(Desk.settings) { $0.touchscreens[Desk.ilitekID]?.unpair() }
    }

    private func step(_ harness: ModelHarness) -> SetUpStep? {
        harness.model.snapshot.setUp?.step
    }

    /// A tap at glass point `p` of `handle`: landing now, held still 0.1 s in frames 10 ms apart.
    private func tap(_ p: CGPoint, _ harness: ModelHarness, _ handle: DeviceHandle = Desk.ilitekHandle, id: Int = 1) {
        let t = harness.clock
        harness.send((0..<10).map { glassFrame(t + Double($0) * 0.01, (id, p.x, p.y)) } + [glassFrame(t + 0.1)], from: handle)
    }

    /// Set-up mode's stage, as the overview draws it; nil when the mode is off.
    private func stage(_ harness: ModelHarness) -> SetUpModeSnapshot.Stage? {
        harness.model.snapshot.setUpMode?.stage
    }

    /// In set-up mode (begun here when it is off): past the mode's first second, the person clicks
    /// `display`'s card, and half a second later touches the middle of `handle`'s glass. The flow
    /// then runs for that touchscreen at the corners on `display`.
    private func chooseAndTouch(_ display: DisplayFacts, _ harness: ModelHarness,
                                _ handle: DeviceHandle = Desk.ilitekHandle) {
        if harness.model.snapshot.setUpMode == nil { harness.model.perform(.beginSetUpMode) }
        harness.tick(after: 1.1)
        harness.model.perform(.setUpChoose(displayID: display.displayID))
        harness.tick(after: 0.5)
        tap(CGPoint(x: 0.5, y: 0.5), harness, handle)
    }

    /// A tap on each corner target in turn, each well after the target appeared (and after the
    /// flow's first second, in which every landing is ignored).
    private func tapCorners(on display: DisplayFacts, _ harness: ModelHarness) {
        for point in SetUpDesk.cornerTaps(on: display, orientation: turned, rect: rect) {
            harness.tick(after: 1.1)
            tap(point, harness)
        }
    }

    /// In set-up mode, sets the ILITEK up on `display` and taps the corners: the flow at the size
    /// step.
    private func pairAndFit(_ display: DisplayFacts, _ harness: ModelHarness) {
        chooseAndTouch(display, harness)
        guard case .corners(display.displayID, _, 0, nil)? = step(harness) else {
            return XCTFail("not at the corners: \(String(describing: step(harness)))")
        }
        tapCorners(on: display, harness)
    }

    /// The person looks at the check before pressing Done or Redo: the flow takes neither within its
    /// reaction time of the check appearing, so that a double Return on the size card can't skip it.
    private func lookAtTheCheck(_ harness: ModelHarness) {
        harness.tick(after: 0.5)
    }

    /// Where a touch at picture point `p` of `display` lands on the desktop.
    private func desktop(_ p: CGPoint, on display: DisplayFacts) -> CGPoint {
        Desk.mapping(on: display).desktopPoint(forDisplay: p)
    }

    private func assertAlignment(_ alignment: GlassAlignment?, _ expected: CGRect, file: StaticString = #filePath,
                                 line: UInt = #line) {
        guard let picture = alignment?.pictureRect else { return XCTFail("no alignment", file: file, line: line) }
        for (a, b) in [(picture.minX, expected.minX), (picture.minY, expected.minY), (picture.width, expected.width),
                       (picture.height, expected.height)] {
            XCTAssertEqual(Double(a), Double(b), accuracy: 1e-6, file: file, line: line)
        }
    }

    // MARK: - The plan's tests

    func testSetUpEndToEnd() throws {
        let harness = try makeHarness(settings: ilitekUnpaired)
        harness.source.plugIn(Desk.ilitek())
        harness.source.plugIn(Desk.stripScreen())
        harness.model.start()
        XCTAssertEqual(harness.touchscreen(ilitek)?.status, .notSetUp)
        XCTAssertEqual(harness.touchscreen(ilitek)?.canBeSetUp, true)
        XCTAssertEqual(harness.model.snapshot.offerSetUpTo, [ilitek])

        harness.model.perform(.beginSetUpMode)
        XCTAssertEqual(stage(harness), .choosing)
        XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .settingUp)
        XCTAssertEqual(harness.touchscreen(strip)?.mode, .settingUp, "no touchscreen drives while the mode is on")
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .taken)
        XCTAssertEqual(harness.model.snapshot.offerSetUpTo, [], "not while a set-up runs")
        XCTAssertEqual(harness.model.snapshot.setUpMode?.displays.map(\.id),
                       [Desk.display.displayID, Desk.hdmi.displayID, Desk.strip.displayID, Desk.lg.displayID],
                       "every external display, in screen order")
        XCTAssertEqual(harness.ticker.interval, 0.1, "10 Hz in the mode")

        pairAndFit(Desk.hdmi, harness)
        XCTAssertEqual(stage(harness), .running)
        guard case .size(Desk.hdmi.displayID, let displayReports, let touchscreenReports, let current)? = step(harness) else {
            return XCTFail("size: \(String(describing: step(harness)))")
        }
        XCTAssertEqual(displayReports ?? 0, 27, accuracy: 0.1)
        XCTAssertEqual(touchscreenReports ?? 0, 21.5, accuracy: 0.1)
        XCTAssertEqual(current, 23.8, "the override in force")
        XCTAssertEqual(harness.ticker.interval, 0.1, "ticked in every step, so the flow's time limits apply")
        harness.model.perform(.setUpConfirmSize(inches: 23.8))
        XCTAssertEqual(step(harness), .check(display: Desk.hdmi.displayID))

        // In the check step a touch is shown where it lands, and does nothing else.
        let quarter = CGPoint(x: 0.25, y: 0.25)
        tap(SetUpDesk.glassPoint(touching: quarter, on: Desk.hdmi, orientation: turned, rect: rect), harness)
        let shown = harness.outputs.record.circles.compactMap { call -> CGPoint? in
            if case .show(Desk.hdmi.displayID, let fingers, [], []) = call { return fingers[1] }
            return nil
        }
        XCTAssertFalse(shown.isEmpty)
        XCTAssertEqual(Double(shown.first?.x ?? 0), 0.25, accuracy: 1e-6)
        XCTAssertEqual(Double(shown.first?.y ?? 0), 0.25, accuracy: 1e-6)
        XCTAssertEqual(harness.outputs.events, [], "nothing moved or clicked during the whole set-up")
        XCTAssertEqual(harness.savedSettings()?.touchscreens[ilitek]?.pairing, nil, "nothing stored before Done")

        lookAtTheCheck(harness)
        harness.model.perform(.setUpDone)
        XCTAssertNil(harness.model.snapshot.setUp)
        XCTAssertNil(harness.model.setUpFlow)
        XCTAssertEqual(stage(harness), .choosing, "back to the screens")
        XCTAssertEqual(harness.model.snapshot.setUpMode?.justSetUp, ilitek)
        XCTAssertEqual(harness.model.snapshot.setUpMode?.displays.first { $0.id == Desk.hdmi.displayID }?.touchscreen,
                       ilitek, "confirmed on its card")
        let saved = try XCTUnwrap(harness.savedSettings()?.touchscreens[ilitek])
        XCTAssertEqual(saved.pairing?.display, DisplayIdentity(Desk.hdmi))
        XCTAssertEqual(saved.pairing?.orientation, turned)
        assertAlignment(saved.pairing?.alignment, rect)
        XCTAssertEqual(saved.diagonalInches, 23.8)
        XCTAssertTrue(saved.wasOfferedSetUp)
        XCTAssertEqual(saved.pairing?.displayName, "HDMI")
        XCTAssertEqual(harness.savedSettings()?.touchscreens[strip], Desk.settings.touchscreens[strip].map {
            with($0) {
                $0.pairing?.displayName = "12.3FHD"
                $0.lastGaveOneFinger = true
            }
        }, "the strip untouched, but for what it gives, remembered")

        // Finish: every touchscreen back to what the table gives.
        harness.model.perform(.cancelSetUp)
        XCTAssertNil(harness.model.snapshot.setUpMode)
        let snapshot = try XCTUnwrap(harness.touchscreen(ilitek))
        XCTAssertEqual(snapshot.mode, .driving)
        XCTAssertEqual(snapshot.pairedDisplayID, Desk.hdmi.displayID)
        XCTAssertEqual(snapshot.orientation, turned, "the fitted orientation")
        XCTAssertTrue(snapshot.isCalibrated)
        XCTAssertEqual(harness.touchscreen(strip)?.mode, .driving)

        // A tap then clicks there.
        harness.tick(after: 1)
        tap(SetUpDesk.glassPoint(touching: CGPoint(x: 0.5, y: 0.5), on: Desk.hdmi, orientation: turned, rect: rect), harness)
        let click = try XCTUnwrap(harness.outputs.events(.down).first)
        let middle = desktop(CGPoint(x: 0.5, y: 0.5), on: Desk.hdmi)
        XCTAssertEqual(click.location.x, middle.x, accuracy: 0.01)
        XCTAssertEqual(click.location.y, middle.y, accuracy: 0.01)
        XCTAssertEqual(harness.outputs.count(.up), 1)
    }

    func testNothingMovesThePointerDuringSetUp() throws {
        let harness = try deskHarness(self)
        let drag = try SurveyTakes.ilitek(take: 11)
        /// Everything a touchscreen can send, landing half a second from now: a drag, then a
        /// two-finger tap.
        func everything(_ handle: DeviceHandle = Desk.ilitekHandle) {
            let start = harness.clock + 0.5
            harness.send(drag.map { ContactFrame(time: $0.time - drag[0].time + start, contacts: $0.contacts) },
                         from: handle)
            let t = harness.clock + 0.5
            harness.send([glassFrame(t, (0, 0.4, 0.4), (1, 0.6, 0.4)), glassFrame(t + 0.1), glassFrame(t + 0.2)],
                         from: handle)
            XCTAssertNil(harness.outputs.arbiter.owner, "never the pointer")
        }

        harness.model.perform(.beginSetUpMode)
        harness.tick(after: 0.5)
        // In the overview: a touch is judged whole, at its lift; whatever it answers, nothing
        // reaches the pointer. On either touchscreen.
        everything()
        everything(Desk.stripHandle)
        guard case .touchedFirst(strip, _)? = stage(harness) else {
            return XCTFail("the strip's touch answered last: \(String(describing: stage(harness)))")
        }
        harness.model.perform(.setUpBack)
        chooseAndTouch(Desk.display, harness)
        guard case .corners(Desk.display.displayID, _, 0, _)? = step(harness) else { return XCTFail("corners") }
        everything()  // In the corners: a slide and two fingers, each refused.
        guard case .corners(_, _, 0, let problem)? = step(harness) else { return XCTFail("still the first corner") }
        XCTAssertNotNil(problem)
        everything(Desk.stripHandle)  // The other touchscreen, while a flow runs: nothing.
        tapCorners(on: Desk.display, harness)
        harness.model.perform(.setUpConfirmSize(inches: nil))
        XCTAssertEqual(step(harness), .check(display: Desk.display.displayID))
        everything()  // In the check step: shown, nothing more.
        harness.tick(after: 2)
        XCTAssertEqual(harness.outputs.events, [])
        XCTAssertEqual(harness.outputs.record.arrowHidden, [])
        XCTAssertEqual(harness.outputs.record.warps, [])
        XCTAssertTrue(harness.outputs.record.circles.allSatisfy {
            if case .show(_, _, [], []) = $0 { return true }
            if case .hide = $0 { return true }
            return false
        }, "only the check step's circles")
    }

    func testCancelLeavesEverythingAsItWas() throws {
        // Offered before, and both paired: leaving the mode has nothing at all to store.
        var settings = Desk.settings
        settings.touchscreens[ilitek]?.wasOfferedSetUp = true
        let harness = try deskHarness(self, settings: settings)
        let before = try Data(contentsOf: harness.settingsURL)

        let atEachStage: [(String, (ModelHarness) -> Void)] = [
            ("choosing", { _ in }),
            ("waiting for a touch", { $0.tick(after: 1.1); $0.model.perform(.setUpChoose(displayID: Desk.display.displayID)) }),
            ("touched first", { $0.tick(after: 1.1); self.tap(CGPoint(x: 0.5, y: 0.5), $0) }),
            ("corners", { self.chooseAndTouch(Desk.display, $0) }),
            ("size", { self.pairAndFit(Desk.display, $0) }),
            ("check", { self.pairAndFit(Desk.display, $0); $0.model.perform(.setUpConfirmSize(inches: 18)) }),
            ("check after a redo", {
                self.pairAndFit(Desk.display, $0)
                $0.model.perform(.setUpConfirmSize(inches: 18))
                self.lookAtTheCheck($0)
                $0.model.perform(.setUpRedo)
            }),
        ]
        for (name, reach) in atEachStage {
            harness.model.perform(.beginSetUpMode)
            reach(harness)
            XCTAssertNotNil(harness.model.snapshot.setUpMode, name)
            harness.model.perform(.cancelSetUp)
            XCTAssertNil(harness.model.snapshot.setUpMode, name)
            XCTAssertNil(harness.model.snapshot.setUp, name)
            XCTAssertEqual(try Data(contentsOf: harness.settingsURL), before, "\(name): the file byte for byte")
            XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .driving, "\(name): back to what it was doing")
            XCTAssertEqual(harness.touchscreen(ilitek)?.pairedDisplayID, Desk.hdmi.displayID, name)
            harness.tick(after: 1)
        }

        // And it works as before.
        tap(CGPoint(x: 0.5, y: 0.5), harness)
        XCTAssertEqual(harness.outputs.events(.down).map(\.location), [desktop(CGPoint(x: 0.5, y: 0.5), on: Desk.hdmi)])
    }

    func testCancellingAFullSetUpMarksItOffered() throws {
        let harness = try makeHarness(settings: ilitekUnpaired)
        harness.source.plugIn(Desk.ilitek())
        harness.model.start()
        harness.model.perform(.beginSetUp(ilitek, .full))
        XCTAssertNotNil(harness.model.snapshot.setUpMode, "a full set-up is set-up mode")
        harness.model.perform(.cancelSetUp)
        let saved = try XCTUnwrap(harness.savedSettings()?.touchscreens[ilitek])
        XCTAssertTrue(saved.wasOfferedSetUp)
        XCTAssertNil(saved.pairing)
        XCTAssertEqual(harness.model.snapshot.offerSetUpTo, [])
    }

    /// Review Focus 3.
    func testUnplugDuringSetUp() throws {
        let harness = try deskHarness(self)
        let before = try Data(contentsOf: harness.settingsURL)
        harness.model.perform(.beginSetUp(ilitek, .calibrate))
        harness.tick(after: 1.1)
        tap(SetUpDesk.cornerTaps(on: Desk.hdmi)[0], harness)
        XCTAssertEqual(step(harness).map { if case .corners(_, _, 1, _) = $0 { return true } else { return false } }, true)

        harness.source.unplug(Desk.ilitekHandle)
        XCTAssertNil(harness.model.snapshot.setUp)
        XCTAssertEqual(try Data(contentsOf: harness.settingsURL), before, "nothing stored")
        XCTAssertEqual(harness.touchscreen(Desk.stripID)?.mode, .driving, "the strip undisturbed")

        harness.source.plugIn(Desk.ilitek(handle: DeviceHandle(rawValue: 7)))
        XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .driving, "back as it was")
        XCTAssertEqual(harness.touchscreen(ilitek)?.pairedDisplayID, Desk.hdmi.displayID)
    }

    /// Review Focus 3: the display being set up goes.
    func testTheDisplayGoingEndsSetUp() throws {
        // Offered before: leaving has nothing at all to store.
        let harness = try deskHarness(self, settings: with(Desk.settings) {
            $0.touchscreens[Desk.ilitekID]?.wasOfferedSetUp = true
        })
        let before = try Data(contentsOf: harness.settingsURL)
        chooseAndTouch(Desk.display, harness)
        XCTAssertEqual(step(harness).map { if case .corners(Desk.display.displayID, _, _, _) = $0 { return true } else { return false } }, true)

        harness.displays.set(Desk.displays.filter { $0.displayID != Desk.display.displayID })
        XCTAssertNil(harness.model.snapshot.setUp)
        XCTAssertEqual(stage(harness), .choosing, "back to the screens")
        XCTAssertEqual(harness.model.snapshot.setUpMode?.notice, .displayGone(name: "Display"))
        XCTAssertEqual(try Data(contentsOf: harness.settingsURL), before)
        harness.model.perform(.cancelSetUp)
        XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .driving, "back on HDMI, as it was")
        XCTAssertEqual(try Data(contentsOf: harness.settingsURL), before)
    }

    /// Review Focus 4.
    func testSetUpOnATouchscreenThatIsOff() throws {
        var settings = Desk.settings
        settings.touchscreens[ilitek]?.isOn = false
        settings.touchscreens[ilitek]?.whenOff = .leaveToMacOS
        let harness = try deskHarness(self, settings: settings)
        XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .released)
        XCTAssertEqual(harness.touchscreen(ilitek)?.canBeSetUp, true)

        harness.model.perform(.beginSetUp(ilitek, .calibrate))
        XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .settingUp)
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .taken, "taken, so its touches reach the flow")
        XCTAssertEqual(harness.touchscreen(ilitek)?.status, .off, "its status as it would otherwise be")
        tapCorners(on: Desk.hdmi, harness)
        XCTAssertEqual(step(harness), .check(display: Desk.hdmi.displayID), "calibrate has no size step")
        lookAtTheCheck(harness)
        harness.model.perform(.setUpDone)

        let saved = try XCTUnwrap(harness.savedSettings()?.touchscreens[ilitek])
        XCTAssertEqual(saved.pairing?.orientation, turned)
        assertAlignment(saved.pairing?.alignment, rect)
        XCTAssertEqual(saved.isOn, false, "still off")
        XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .released, "left to macOS again")
        XCTAssertEqual(harness.outputs.events, [])
    }

    /// A drag on the strip goes on through the ILITEK's whole calibration, outside set-up mode.
    func testTheOtherTouchscreenKeepsThePointer() throws {
        // A finger that moves at once drags on the strip, as Automatic gives it here.
        let harness = try deskHarness(self, settings: with(Desk.settings) { $0.touchscreens[Desk.stripID]?.oneFinger = .automatic })
        var stripTime = harness.clock
        var stripX: CGFloat = 0.2
        /// The strip's finger, a step further, every 50 ms up to `time`.
        func dragStrip(until time: TimeInterval) {
            while stripTime + 0.05 <= time {
                stripTime += 0.05
                stripX = min(0.8, stripX + 0.002)
                harness.source.send(glassFrame(stripTime, (0, stripX, 0.5)), from: Desk.stripHandle)
            }
        }
        harness.send([glassFrame(stripTime, (0, stripX, 0.5))], from: Desk.stripHandle)
        stripTime = harness.clock
        dragStrip(until: harness.clock + 1)
        harness.clock = stripTime
        XCTAssertEqual(harness.outputs.arbiter.owner, strip)
        XCTAssertEqual(harness.outputs.count(.down), 1, "the strip's drag has begun")

        harness.model.perform(.beginSetUp(ilitek, .calibrate))
        // The ILITEK's set-up, with the strip's frames going on between its frames and ticks.
        for point in SetUpDesk.cornerTaps(on: Desk.hdmi, orientation: turned, rect: rect) {
            harness.clock += 1.1
            dragStrip(until: harness.clock)
            harness.model.tickPipelines()
            harness.clock = max(harness.clock, stripTime)
            tap(point, harness)
            dragStrip(until: harness.clock)
            XCTAssertEqual(harness.outputs.arbiter.owner, strip, "the strip keeps the pointer")
        }
        XCTAssertEqual(step(harness), .check(display: Desk.hdmi.displayID))
        harness.clock += 0.5
        dragStrip(until: harness.clock)
        tap(CGPoint(x: 0.3, y: 0.3), harness)
        harness.model.perform(.setUpDone)
        XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .driving)
        XCTAssertEqual(harness.savedSettings()?.touchscreens[ilitek]?.pairing?.orientation, turned)

        dragStrip(until: harness.clock + 0.5)
        harness.clock = stripTime + 0.05
        harness.send([glassFrame(harness.clock)], from: Desk.stripHandle)
        harness.tick(after: 1)
        XCTAssertEqual(harness.outputs.count(.down), 1, "one press")
        XCTAssertEqual(harness.outputs.count(.up), 1, "one release, at the end")
        XCTAssertGreaterThan(harness.outputs.count(.drag), 50, "the drag went on throughout")
        XCTAssertTrue(harness.outputs.events.allSatisfy { Desk.strip.frame.contains($0.location) }, "every event the strip's")
        XCTAssertEqual(harness.outputs.record.arrowHidden, [true], "never cancelled")
    }

    func testLockEndsSetUp() throws {
        let harness = try deskHarness(self)
        let before = try Data(contentsOf: harness.settingsURL)
        harness.model.perform(.beginSetUp(ilitek, .calibrate))
        tapCorners(on: Desk.hdmi, harness)
        XCTAssertEqual(step(harness), .check(display: Desk.hdmi.displayID))

        harness.conditions.setSessionActive(false)
        XCTAssertNil(harness.model.snapshot.setUp)
        XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .released)
        XCTAssertEqual(try Data(contentsOf: harness.settingsURL), before)

        harness.conditions.setSessionActive(true)
        XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .driving)
        XCTAssertNil(harness.model.snapshot.setUp, "it doesn't come back")
    }

    func testEverythingThatEndsDrivingEndsSetUp() throws {
        let endings: [(String, (ModelHarness) -> Void, (ModelHarness) -> Void)] = [
            ("Tactile off", { $0.model.perform(.setOn(false)) }, { $0.model.perform(.setOn(true)) }),
            ("Accessibility gone", { $0.conditions.setAccessibility(false) }, { $0.conditions.setAccessibility(true) }),
            ("sleep", { $0.conditions.sleep() }, { $0.conditions.wake() }),
            ("its touches unreadable", { $0.source.change(Desk.ilitekHandle) { $0.status.touchOrigin = .unreadable } },
             { $0.source.change(Desk.ilitekHandle) { $0.status.touchOrigin = .touchInterface } }),
        ]
        for (name, end, undo) in endings {
            let harness = try deskHarness(self)
            let before = try Data(contentsOf: harness.settingsURL)
            harness.model.perform(.beginSetUp(ilitek, .calibrate))
            XCTAssertNotNil(harness.model.snapshot.setUp, name)
            end(harness)
            XCTAssertNil(harness.model.snapshot.setUp, name)
            XCTAssertNotEqual(harness.touchscreen(ilitek)?.mode, .settingUp, name)
            undo(harness)
            XCTAssertEqual(harness.savedSettings()?.touchscreens[ilitek], DeskFixture.settings.touchscreens[ilitek].map {
                with($0) {
                    $0.pairing?.displayName = "HDMI"
                    $0.lastGaveOneFinger = false
                }
            }, name)
            if name != "Tactile off" {
                XCTAssertEqual(try Data(contentsOf: harness.settingsURL), before, name)
            }
        }

        // Quitting.
        let harness = try deskHarness(self)
        harness.model.perform(.beginSetUp(ilitek, .calibrate))
        harness.model.shutDown()
        XCTAssertNil(harness.model.setUpFlow)
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .released)
    }

    func testOfferIsMadeOnce() throws {
        let harness = try makeHarness()
        harness.source.plugIn(Desk.ilitek())
        harness.model.start()
        XCTAssertEqual(harness.model.snapshot.offerSetUpTo, [ilitek], "a new touchscreen")

        harness.model.perform(.declineSetUp(ilitek))
        XCTAssertEqual(harness.model.snapshot.offerSetUpTo, [])
        XCTAssertEqual(harness.savedSettings()?.touchscreens[ilitek]?.wasOfferedSetUp, true)
        XCTAssertEqual(harness.touchscreen(ilitek)?.canBeSetUp, true, "still in the pane and the menu")

        // Relaunched: not offered again.
        harness.model.shutDown()
        let again = try makeHarness(settings: harness.savedSettings())
        again.source.plugIn(Desk.ilitek())
        again.model.start()
        XCTAssertEqual(again.touchscreen(ilitek)?.status, .notSetUp)
        XCTAssertEqual(again.model.snapshot.offerSetUpTo, [])

        // A touchscreen that is paired, or one that can't be set up, is never offered.
        let desk = try deskHarness(self)
        XCTAssertEqual(desk.model.snapshot.offerSetUpTo, [])
        var noExternalDisplay = Desk.inputs
        noExternalDisplay.settings.touchscreens[ilitek]?.unpair()
        noExternalDisplay.displays = [Desk.builtIn]
        let resolved = Resolver.resolve(noExternalDisplay).snapshot
        XCTAssertEqual(resolved.touchscreens.first { $0.id == ilitek }?.canBeSetUp, false)
        XCTAssertEqual(resolved.offerSetUpTo, [])
        var unreadable = Desk.inputs
        unreadable.settings.touchscreens[ilitek]?.unpair()
        unreadable.connected[0].status.touchOrigin = .unreadable
        XCTAssertEqual(Resolver.resolve(unreadable).snapshot.offerSetUpTo, [])
    }

    /// The first-run offer is kept through a display reconfiguration. It names the same touchscreen
    /// before, during and after, while `canBeSetUp` is false during it (the button is disabled for
    /// that moment), so the first-run window isn't put up again.
    func testTheOfferIsKeptThroughAReconfiguration() throws {
        let harness = try makeHarness()
        harness.source.plugIn(Desk.ilitek())
        harness.model.start()
        XCTAssertEqual(harness.model.snapshot.offerSetUpTo, [ilitek], "before")
        XCTAssertEqual(harness.touchscreen(ilitek)?.canBeSetUp, true)
        harness.displays.set([])
        XCTAssertEqual(harness.model.snapshot.offerSetUpTo, [ilitek], "during")
        XCTAssertEqual(harness.touchscreen(ilitek)?.canBeSetUp, false, "the button disabled during it")
        harness.displays.set(Desk.displays)
        XCTAssertEqual(harness.model.snapshot.offerSetUpTo, [ilitek], "after")
        XCTAssertEqual(harness.touchscreen(ilitek)?.canBeSetUp, true)

        // Settling without a display it could be set up on does withdraw it.
        harness.displays.set([])
        harness.displays.set([Desk.builtIn])
        XCTAssertEqual(harness.model.snapshot.offerSetUpTo, [], "no external display left")
    }

    /// Review Focus 5 in part (see `SetUpModeModelTests` for the rest): with no candidate display,
    /// set-up is neither possible in the pane nor offered, and beginning the mode is refused.
    /// Displays that mirror each other are candidates now: the person chooses, by a click.
    func testNoCandidateDisplayIsNoSetUp() throws {
        var inputs = Desk.inputs
        inputs.settings.touchscreens[ilitek]?.unpair()
        inputs.displays = [Desk.builtIn]
        let resolved = Resolver.resolve(inputs).snapshot
        XCTAssertEqual(resolved.touchscreens.first { $0.id == ilitek }?.canBeSetUp, false)
        XCTAssertEqual(resolved.offerSetUpTo, [])
        XCTAssertEqual(Resolver.setUpModeRefusal(inputs)?.words, "there is no display to set one up on")
        XCTAssertEqual(Resolver.setUpModeRefusal(inputs)?.refusal, .noDisplayToChoose)
        XCTAssertEqual(resolved.setUpModeRefusal, .noDisplayToChoose)

        let mirroring = with(Desk.hdmi) { $0.mirrors = Desk.lg.displayID }
        inputs.displays = [Desk.builtIn, Desk.lg, mirroring, Desk.strip]
        XCTAssertNil(Resolver.setUpModeRefusal(inputs))
        XCTAssertEqual(Resolver.setUpScene(inputs).scene.cards.map(\.id), [Desk.strip.displayID],
                       "neither of the mirror set: a click couldn't tell them apart")

        // Through the model: no offer, and beginning is refused.
        let harness = try deskHarness(self, settings: ilitekUnpaired)
        harness.displays.set([Desk.builtIn])
        XCTAssertEqual(harness.touchscreen(ilitek)?.canBeSetUp, false)
        XCTAssertEqual(harness.model.snapshot.offerSetUpTo, [])
        harness.model.perform(.beginSetUpMode)
        XCTAssertNil(harness.model.snapshot.setUpMode)

        // A display: the offer is made again.
        harness.displays.set([Desk.builtIn, Desk.display])
        XCTAssertEqual(harness.touchscreen(ilitek)?.canBeSetUp, true)
        XCTAssertEqual(harness.model.snapshot.offerSetUpTo, [ilitek])
    }

    /// Through the model: a hand whose contacts arrive over several frames answers nothing; a
    /// finger afterwards does.
    func testAHandArrivingOverSeveralFramesPicksNothing() throws {
        let harness = try deskHarness(self, settings: ilitekUnpaired)
        harness.model.perform(.beginSetUpMode)
        harness.tick(after: 1.1)
        harness.model.perform(.setUpChoose(displayID: Desk.hdmi.displayID))
        harness.tick(after: 0.5)
        let t = harness.clock
        harness.send([
            glassFrame(t, (1, 0.5, 0.5)),
            glassFrame(t + 0.02, (1, 0.5, 0.5), (2, 0.6, 0.5), (3, 0.7, 0.5)),
            glassFrame(t + 0.04, (1, 0.5, 0.5), (2, 0.6, 0.5), (3, 0.7, 0.5), (4, 0.6, 0.6), (5, 0.5, 0.6)),
            glassFrame(t + 0.06, (1, 0.5, 0.5)),
            glassFrame(t + 0.08),
        ], from: Desk.ilitekHandle)
        harness.tick(after: 0.05)
        XCTAssertEqual(stage(harness), .waitingForTouch(display: Desk.hdmi.displayID), "a hand answers nothing")
        XCTAssertEqual(harness.outputs.events, [])

        // A finger then answers.
        harness.tick(after: 0.2)
        tap(CGPoint(x: 0.5, y: 0.5), harness)
        guard case .corners(Desk.hdmi.displayID, _, 0, nil)? = step(harness) else {
            return XCTFail("a finger answers: \(String(describing: step(harness)))")
        }
    }

    /// Through the model: a touch whose finger moves from the mouse interface to the touch interface
    /// is one touch. The reader's empty frame between the two (its end of the mouse finger) never
    /// reaches the mode, so the finger arriving on the touch interface is no new landing: a touch
    /// that landed when it couldn't answer (here, in the mode's first second) answers nothing, even
    /// though it continues and lifts later.
    func testAnOriginChangeMidTouchLandedInTheModesFirstSecondAnswersNothing() throws {
        let harness = try deskHarness(self, settings: with(Desk.settings) { $0.touchscreens[Desk.stripID]?.unpair() })
        harness.model.perform(.beginSetUpMode)
        // The finger lands in the mode's first second, on the mouse interface, and stays.
        let begun = harness.clock
        let t = harness.clock + 0.2
        harness.send((0..<12).map { glassFrame(t + Double($0) * 0.1, (0, 0.5, 0.5)) }, from: Desk.stripHandle)
        harness.clock = t + 1.2
        XCTAssertGreaterThan(harness.clock - begun, 1.0)
        // Its touches now come from the touch interface: the reader ends the mouse finger with an
        // empty frame, and the same finger arrives there.
        harness.source.change(Desk.stripHandle) { $0.status.touchOrigin = .touchInterface }
        let u = harness.clock
        harness.send([glassFrame(u)] + (1...4).map { glassFrame(u + Double($0) * 0.05, (3, 0.5, 0.5)) } + [glassFrame(u + 0.3)],
                     from: Desk.stripHandle)
        harness.tick(after: 0.05)
        XCTAssertEqual(stage(harness), .choosing, "one touch, landed too early, answers nothing")
        XCTAssertEqual(harness.outputs.events, [])
    }

    func testCalibrateOnly() throws {
        let harness = try deskHarness(self)
        harness.model.perform(.beginSetUp(ilitek, .calibrate))
        guard case .corners(Desk.hdmi.displayID, _, 0, nil)? = step(harness) else { return XCTFail("straight to the corners") }
        XCTAssertEqual(harness.ticker.interval, 0.1, "ticked in every step")
        tapCorners(on: Desk.hdmi, harness)
        XCTAssertEqual(step(harness), .check(display: Desk.hdmi.displayID))

        // Redo goes back to the corners; a second round replaces the first.
        lookAtTheCheck(harness)
        harness.model.perform(.setUpRedo)
        guard case .corners(_, _, 0, nil)? = step(harness) else { return XCTFail("corners again") }
        // Another fit that 16:9 glass can have on a 16:9 picture: turned half round and flipped.
        let other = Orientation(quarterTurns: 2, isFlipped: true)
        for point in SetUpDesk.cornerTaps(on: Desk.hdmi, orientation: other, rect: SetUpDesk.wholeGlass) {
            harness.tick(after: 1.1)
            tap(point, harness)
        }
        lookAtTheCheck(harness)
        harness.model.perform(.setUpDone)
        let saved = try XCTUnwrap(harness.savedSettings()?.touchscreens[ilitek])
        XCTAssertEqual(saved.pairing?.display, DisplayIdentity(Desk.hdmi), "the same display")
        XCTAssertEqual(saved.pairing?.orientation, other)
        XCTAssertEqual(saved.diagonalInches, 23.8, "the size as it was")
        XCTAssertEqual(saved.pairing?.displayName, "HDMI", "its remembered name kept")
        XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .driving)
    }

    func testDoneTooSoonAfterTheCheckAppearsIsNotTaken() throws {
        // After the corners: the check appears as the last tap lifts, 0.1 s after it landed.
        let harness = try deskHarness(self)
        harness.model.perform(.beginSetUp(ilitek, .calibrate))
        tapCorners(on: Desk.hdmi, harness)
        XCTAssertEqual(step(harness), .check(display: Desk.hdmi.displayID))
        harness.clock += 0.15
        harness.model.perform(.setUpDone)
        XCTAssertEqual(step(harness), .check(display: Desk.hdmi.displayID), "Done 0.05 s after the check appeared")
        harness.clock += 0.45
        harness.model.perform(.setUpDone)
        XCTAssertNil(harness.model.snapshot.setUp, "Done 0.5 s after")
        XCTAssertEqual(harness.savedSettings()?.touchscreens[ilitek]?.pairing?.orientation, turned)

        // Return twice on the size card, in set-up mode: the second press lands on the check, 0.05 s later.
        let full = try makeHarness(settings: ilitekUnpaired)
        full.source.plugIn(Desk.ilitek())
        full.source.plugIn(Desk.stripScreen())
        full.model.start()
        pairAndFit(Desk.hdmi, full)
        guard case .size? = step(full) else { return XCTFail("size: \(String(describing: step(full)))") }
        full.tick(after: 1)
        full.model.perform(.setUpConfirmSize(inches: 23.8))
        full.clock += 0.05
        full.model.perform(.setUpDone)
        XCTAssertEqual(step(full), .check(display: Desk.hdmi.displayID), "the check stays")
        XCTAssertNil(full.savedSettings()?.touchscreens[ilitek]?.pairing, "nothing stored")
        full.clock += 0.45
        full.model.perform(.setUpDone)
        XCTAssertNil(full.model.snapshot.setUp)
        XCTAssertEqual(full.savedSettings()?.touchscreens[ilitek]?.pairing?.display, DisplayIdentity(Desk.hdmi))
    }

    func testTestOnly() throws {
        let harness = try deskHarness(self)
        let before = try Data(contentsOf: harness.settingsURL)
        harness.model.perform(.beginSetUp(ilitek, .test))
        XCTAssertEqual(step(harness), .check(display: Desk.hdmi.displayID), "the check step alone")
        tap(CGPoint(x: 0.25, y: 0.75), harness)
        XCTAssertTrue(harness.outputs.record.circles.contains(
            .show(display: Desk.hdmi.displayID, fingers: [1: CGPoint(x: 0.25, y: 0.75)], hollow: [], ringed: [])),
                      "shown with the mapping it has")
        // Past the check's reaction time, so that only the purpose can refuse the Redo.
        lookAtTheCheck(harness)
        harness.model.perform(.setUpRedo)
        XCTAssertEqual(step(harness), .check(display: Desk.hdmi.displayID), "no redo for a test")
        XCTAssertEqual(harness.outputs.record.circles.last,
                       .show(display: Desk.hdmi.displayID, fingers: [:], hollow: [], ringed: []), "faded as it lifted")
        // Done with a finger down: its circle goes.
        harness.send([glassFrame(harness.clock + 0.5, (2, 0.5, 0.5))], from: Desk.ilitekHandle)
        harness.model.perform(.setUpDone)
        XCTAssertNil(harness.model.snapshot.setUp)
        XCTAssertEqual(harness.outputs.record.circles.last, .hide(display: Desk.hdmi.displayID), "its circles go")
        XCTAssertEqual(try Data(contentsOf: harness.settingsURL), before, "nothing stored")
        XCTAssertEqual(harness.outputs.events, [])
    }

    /// A Done or Redo the flow ignores as too soon gets a line of its own, written from the flow as
    /// the model has ticked it at the command's moment; one it takes gets none, so the lines a taken
    /// command leaves are as before.
    func testADoneOrRedoIgnoredAsTooSoonIsLogged() throws {
        var driver = try FlowDriver(SetUpDesk.start())
        driver.taps(SetUpDesk.cornerTaps(on: SetUpDesk.hdmi), from: 2)
        var lines: [String?] = []
        driver.press { lines.append(TactileModel.tooSoonLine("Done", after: $0)); return $0.confirmSize(inches: 23.8) }
        driver.press(after: 0.05) { lines.append(TactileModel.tooSoonLine("Done", after: $0)); return $0.done() }
        driver.press(after: 0.05) { lines.append(TactileModel.tooSoonLine("Redo", after: $0)); return $0.redo() }
        driver.press(after: 0.4) { lines.append(TactileModel.tooSoonLine("Done", after: $0)); return $0.done() }
        XCTAssertEqual(lines, [
            nil,
            "Set-up: Done ignored, the check has only just appeared",
            "Set-up: Redo ignored, the check has only just appeared",
            nil,
        ])
        guard case .finished(.some) = driver.last else { return XCTFail("taken: \(driver.last)") }
    }

    // MARK: - More

    func testAFingerAlreadyDownIsNotATouch() throws {
        let harness = try makeHarness(settings: ilitekUnpaired)
        harness.source.plugIn(Desk.ilitek())
        harness.model.start()
        // The finger rests on the glass, held (unpaired), before set-up mode begins.
        let t = harness.clock
        harness.send((0..<20).map { glassFrame(t + Double($0) * 0.01, (3, 0.5, 0.5)) }, from: Desk.ilitekHandle)
        harness.model.perform(.beginSetUpMode)
        XCTAssertEqual(stage(harness), .choosing)
        // It carries on resting, past the mode's first second: still no touch.
        let rest = harness.clock
        harness.send((1...150).map { glassFrame(rest + Double($0) * 0.01, (3, 0.5, 0.5)) }, from: Desk.ilitekHandle)
        harness.model.tickPipelines()
        harness.send([glassFrame(harness.clock + 0.01)], from: Desk.ilitekHandle)
        XCTAssertEqual(stage(harness), .choosing, "it lifted: still no answer")
        // A new touch answers.
        harness.tick(after: 0.2)
        tap(CGPoint(x: 0.5, y: 0.5), harness)
        guard case .touchedFirst(ilitek, _)? = stage(harness) else {
            return XCTFail("answered: \(String(describing: stage(harness)))")
        }
    }

    func testBeginningSetUpMidDragCancelsTheTouchFirst() throws {
        let harness = try deskHarness(self)
        let frames = try SurveyTakes.ilitek(take: 11)
        harness.send(frames.prefix(frames.count / 2), from: Desk.ilitekHandle)
        XCTAssertEqual(harness.outputs.count(.down), 1)
        let lastDrag = try XCTUnwrap(harness.outputs.events(.drag).last)

        harness.model.perform(.beginSetUp(ilitek, .calibrate))
        XCTAssertEqual(harness.outputs.events.last?.kind, .up, "the button released at once")
        XCTAssertEqual(harness.outputs.events.last?.location, lastDrag.location)
        XCTAssertEqual(harness.outputs.record.arrowHidden, [true, false], "cancelled: the arrow is back")
        XCTAssertNil(harness.outputs.arbiter.owner)
        let up = try XCTUnwrap(harness.log.first("event up"))
        XCTAssertNil(harness.log.entries.dropFirst(up).first { $0.hasPrefix("source.setState \(Desk.ilitekHandle)") },
                     "it stays taken: nothing asked of its device")

        // The rest of that touch is the finger already down: no corner tap, nothing posted.
        let before = harness.outputs.events.count
        harness.send(frames.dropFirst(frames.count / 2), from: Desk.ilitekHandle)
        XCTAssertEqual(harness.outputs.events.count, before)
        guard case .corners(_, _, 0, nil)? = step(harness) else { return XCTFail("still the first corner, no problem") }
    }

    func testAReconfigurationDoesNotDisturbARunningSetUp() throws {
        let harness = try deskHarness(self)
        harness.model.perform(.beginSetUp(ilitek, .calibrate))
        let taps = SetUpDesk.cornerTaps(on: Desk.hdmi, orientation: turned, rect: rect)
        harness.tick(after: 1.1)
        tap(taps[0], harness)
        harness.displays.set([])
        XCTAssertNotNil(harness.model.snapshot.setUp, "the moment with no displays is no change for it")
        XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .settingUp)
        harness.displays.set(Desk.displays)
        guard case .corners(_, _, 1, _)? = step(harness) else { return XCTFail("the first tap kept") }
        for point in taps.dropFirst() {
            harness.tick(after: 1.1)
            tap(point, harness)
        }
        XCTAssertEqual(step(harness), .check(display: Desk.hdmi.displayID))

        // When the displays settle without its display, it has really gone: the set-up ends.
        harness.displays.set([])
        XCTAssertNotNil(harness.model.snapshot.setUp)
        harness.displays.set(Desk.displays.filter { $0.displayID != Desk.hdmi.displayID })
        XCTAssertNil(harness.model.snapshot.setUp)
        XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .held, "back to what it does without its display")
    }

    /// Ticks move the session's and the flow's clocks, not what is published.
    func testTicksChangeNeitherTheSnapshotNorTheStateFile() throws {
        let harness = try deskHarness(self, writesStateFile: true)
        harness.model.perform(.beginSetUpMode)
        let shown = harness.model.snapshot
        let file = try Data(contentsOf: harness.stateURL)
        for _ in 0..<30 { harness.tick(after: 0.1) }
        XCTAssertEqual(harness.model.snapshot, shown)
        XCTAssertEqual(try Data(contentsOf: harness.stateURL), file, "the state file not written again")
        harness.model.perform(.setUpChoose(displayID: Desk.hdmi.displayID))
        XCTAssertNotEqual(harness.model.snapshot.setUpMode, shown.setUpMode, "the choice is published")

        // The same in the corners: ticks there change nothing shown.
        harness.model.perform(.cancelSetUp)
        harness.model.perform(.beginSetUp(ilitek, .calibrate))
        let corners = harness.model.snapshot
        let cornersFile = try Data(contentsOf: harness.stateURL)
        for _ in 0..<30 { harness.tick(after: 0.1) }
        XCTAssertEqual(harness.model.snapshot, corners)
        XCTAssertEqual(try Data(contentsOf: harness.stateURL), cornersFile)
    }

    /// Begin with a finger down, a silence longer than the mode's first second (so that only the
    /// frame handed over at the start can make the difference) but within the silence limit, then
    /// frames of that finger: nothing answers.
    func testAFingerDownWhenItBeginsThenSilenceThenFramesPicksNothing() throws {
        let harness = try makeHarness(settings: ilitekUnpaired)
        harness.source.plugIn(Desk.ilitek())
        harness.model.start()
        let t = harness.clock
        harness.send((0..<10).map { glassFrame(t + Double($0) * 0.01, (4, 0.5, 0.5)) }, from: Desk.ilitekHandle)
        harness.model.perform(.beginSetUpMode)
        XCTAssertEqual(stage(harness), .choosing)
        harness.tick(after: 1.4)
        XCTAssertLessThan(1.4, TouchPipeline.silenceLimit)
        let resume = harness.clock
        harness.send((1...100).map { glassFrame(resume + Double($0) * 0.01, (4, 0.5, 0.5)) }, from: Desk.ilitekHandle)
        harness.send([glassFrame(harness.clock + 0.01)], from: Desk.ilitekHandle)
        XCTAssertEqual(stage(harness), .choosing, "nothing answered")
    }

    func testOneSetUpAtATime() throws {
        let harness = try deskHarness(self)
        harness.model.perform(.beginSetUp(ilitek, .calibrate))
        harness.model.perform(.beginSetUp(strip, .calibrate))
        XCTAssertEqual(harness.model.snapshot.setUp?.touchscreen, ilitek)
        XCTAssertEqual(harness.touchscreen(strip)?.mode, .driving)
        harness.model.perform(.beginSetUp(ilitek, .full))
        harness.model.perform(.beginSetUpMode)
        XCTAssertEqual(harness.model.snapshot.setUp?.purpose, .calibrate, "the running one goes on")
        XCTAssertNil(harness.model.snapshot.setUpMode, "the mode doesn't begin over it")
    }

    func testAPairingTheFlowCannotUseCannotBeginCalibrateOrTest() throws {
        let harness = try deskHarness(self)
        harness.displays.set(Desk.displays.filter { $0.displayID != Desk.hdmi.displayID })
        harness.model.perform(.beginSetUp(ilitek, .calibrate))
        XCTAssertNil(harness.model.snapshot.setUp, "its display isn't connected")
        harness.model.perform(.beginSetUp(ilitek, .test))
        XCTAssertNil(harness.model.snapshot.setUp)
        harness.model.perform(.beginSetUp(ilitek, .full))
        XCTAssertNotNil(harness.model.snapshot.setUpMode, "a full set-up is set-up mode, on any display")
    }

    func testTheTickRates() throws {
        let harness = try deskHarness(self)
        harness.model.perform(.beginSetUp(ilitek, .calibrate))
        XCTAssertEqual(harness.ticker.interval, 0.1)
        // The strip touched: 60 Hz while it needs it.
        harness.send([glassFrame(harness.clock + 0.01, (0, 0.5, 0.5))], from: Desk.stripHandle)
        XCTAssertEqual(harness.ticker.interval, TickRate.touchInterval)
        harness.send([glassFrame(harness.clock + 0.05)], from: Desk.stripHandle)
        harness.tick(after: 1)
        XCTAssertEqual(harness.ticker.interval, 0.1, "back to the set-up's rate")
        harness.model.perform(.cancelSetUp)
        XCTAssertFalse(harness.ticker.isRunning)

        // Set-up mode: 10 Hz, and the strip's touch is set-up input, not a touch that needs more.
        harness.tick(after: 1)
        harness.model.perform(.beginSetUpMode)
        XCTAssertEqual(harness.ticker.interval, 0.1)
        harness.send([glassFrame(harness.clock + 0.01, (0, 0.5, 0.5))], from: Desk.stripHandle)
        XCTAssertEqual(harness.ticker.interval, 0.1)
        harness.send([glassFrame(harness.clock + 0.05)], from: Desk.stripHandle)
        harness.model.perform(.cancelSetUp)
        XCTAssertFalse(harness.ticker.isRunning)
    }

    func testThePairRoundGoesRoundAndTimesOut() throws {
        let harness = try makeHarness(settings: ilitekUnpaired)
        harness.source.plugIn(Desk.ilitek())
        harness.model.start()
        harness.model.perform(.beginSetUpMode)
        let begun = harness.clock
        for _ in 0..<1300 {
            if harness.model.snapshot.setUpMode == nil { break }
            harness.tick(after: 0.1)
        }
        XCTAssertNil(harness.model.snapshot.setUpMode, "ended by itself")
        XCTAssertEqual(harness.clock - begun, SetUpFlow.idleTimeout, accuracy: 0.15, "after two minutes")
        XCTAssertEqual(harness.savedSettings()?.touchscreens[ilitek]?.wasOfferedSetUp, true)
        XCTAssertNil(harness.savedSettings()?.touchscreens[ilitek]?.pairing)
        XCTAssertFalse(harness.ticker.isRunning)
    }

    // MARK: - The resolver

    func testTheSetUpRowOfTheModeTable() throws {
        var inputs = Desk.inputs
        inputs.setUp = SetUpSnapshot(touchscreen: ilitek, touchscreenName: "ILITEK-TP", purpose: .full,
                                     step: .check(display: Desk.hdmi.displayID))
        let cases: [(String, (inout AppInputs) -> Void, TouchscreenMode)] = [
            ("paired", { _ in }, .settingUp),
            ("unpaired", { $0.settings.touchscreens[Desk.ilitekID]?.unpair() }, .settingUp),
            ("off, ignoring", { $0.settings.touchscreens[Desk.ilitekID]?.isOn = false }, .settingUp),
            ("off, left to macOS", {
                $0.settings.touchscreens[Desk.ilitekID]?.isOn = false
                $0.settings.touchscreens[Desk.ilitekID]?.whenOff = .leaveToMacOS
            }, .settingUp),
            ("its display away", { $0.displays.removeAll { $0.displayID == Desk.hdmi.displayID } }, .settingUp),
            ("Tactile off", { $0.settings.isOn = false }, .released),
            ("no Accessibility", { $0.hasAccessibilityAccess = false }, .released),
            ("locked", { $0.isSessionActive = false }, .released),
            ("asleep", { $0.isAsleep = true }, .released),
            ("quitting", { $0.isQuitting = true }, .released),
            ("unreadable", { $0.connected[0].status.touchOrigin = .unreadable }, .held),
            ("mouse mode, shared with macOS", {
                $0.connected[0].status.touchOrigin = .mouseInterface
                $0.connected[0].status.exclusive = .failed
            }, .held),
        ]
        for (name, change, mode) in cases {
            let resolution = Resolver.resolve(with(inputs, change))
            let resolved = try XCTUnwrap(resolution.touchscreens.first { $0.id == ilitek }, name)
            XCTAssertEqual(resolved.mode, mode, name)
            XCTAssertNil(resolved.driving, "\(name): never a pipeline")
            if mode == .settingUp {
                XCTAssertEqual(resolved.deviceState, .taken, name)
                XCTAssertEqual(resolved.rule, .settingUp, name)
            }
            XCTAssertEqual(resolution.touchscreens.first { $0.id == strip }?.mode,
                           mode == .released && name != "unreadable" ? .released : .driving, "\(name): the strip")
            XCTAssertEqual(resolution.snapshot.setUp, inputs.setUp)
        }
    }

    func testCanBeSetUpAndItsCandidates() throws {
        // A full set-up starts only in set-up mode; a calibration on its own display.
        XCTAssertNil(Resolver.setUpStart(for: ilitek, purpose: .full, in: Desk.inputs))
        let start = try XCTUnwrap(Resolver.setUpStart(for: ilitek, purpose: .calibrate, in: Desk.inputs))
        XCTAssertEqual(start.candidates, [Desk.hdmi])
        XCTAssertEqual(start.allDisplays, Desk.displays)
        XCTAssertEqual(start.current, Desk.inputs.settings.touchscreens[ilitek]?.pairing)
        XCTAssertEqual(start.currentDiagonal, 23.8)
        XCTAssertEqual(start.reportedSizeMM, CGSize(width: 476, height: 268))
        XCTAssertEqual(start.touchscreenName, "ILITEK-TP")

        // Set-up mode's candidates: every external display, the strip's own and the ILITEK's own
        // included, in screen order.
        let scene = Resolver.setUpScene(Desk.inputs).scene
        XCTAssertEqual(scene.cards.map(\.id), [Desk.display.displayID, Desk.hdmi.displayID, Desk.strip.displayID,
                                               Desk.lg.displayID])
        XCTAssertEqual(scene.displays, Desk.displays)

        // A display only a remembered touchscreen claims is a candidate; Done moves the claim.
        var remembered = Desk.inputs
        let old = TouchscreenID(rawValue: "1234:5678:R")
        remembered.settings.touchscreens[old] = Desk.paired("Old panel", with: Desk.lg)
        XCTAssertTrue(Resolver.setUpScene(remembered).scene.cards.contains { $0.id == Desk.lg.displayID })
        let outcome = SetUpFlow.Outcome(display: DisplayIdentity(Desk.lg), orientation: .asFitted, alignment: .wholeGlass,
                                        diagonalInches: 27)
        let after = Resolver.applySetUp(outcome, purpose: .full, to: ilitek, in: remembered, endedByThePerson: true)
        XCTAssertNil(after.touchscreens[old]?.pairing, "the old claim cleared, as pairing does")
        XCTAssertEqual(after.touchscreens[ilitek]?.pairing?.display, DisplayIdentity(Desk.lg))
        XCTAssertEqual(after.touchscreens[ilitek]?.pairing?.displayName, "LG HDR 4K", "named as it is now, in the same change")
        XCTAssertEqual(after.touchscreens[ilitek]?.diagonalInches, 27)
        XCTAssertEqual(after.touchscreens[strip], remembered.settings.touchscreens[strip], "the strip untouched")

        // Never set up: no external display; touches that can't be read; macOS acting on it too; no
        // record; Tactile unable to take it.
        let cannot: [(String, (inout AppInputs) -> Void)] = [
            ("no external display", { $0.displays = [Desk.builtIn] }),
            ("unreadable", { $0.connected[0].status.touchOrigin = .unreadable }),
            ("mouse mode, shared", {
                $0.connected[0].status.touchOrigin = .mouseInterface
                $0.connected[0].status.exclusive = .failed
            }),
            ("no record", { $0.records[Desk.ilitekHandle] = nil }),
            ("Tactile off", { $0.settings.isOn = false }),
            ("no Accessibility", { $0.hasAccessibilityAccess = false }),
        ]
        for (name, change) in cannot {
            let inputs = with(Desk.inputs, change)
            let snapshot = Resolver.resolve(inputs).snapshot.touchscreens.first { $0.handle(in: inputs) == Desk.ilitekHandle }
            XCTAssertEqual(snapshot?.canBeSetUp, false, name)
        }
        XCTAssertEqual(Resolver.resolve(Desk.inputs).snapshot.touchscreens.map(\.canBeSetUp), [true, true])
        XCTAssertNil(Resolver.setUpStart(for: TouchscreenID(rawValue: "#1:222a:0001:V06.00.00.00"), purpose: .calibrate,
                                         in: Desk.inputs))
    }

    /// Every connected display goes to the flow, those others mirror included; calibrate's one
    /// candidate is exactly the display the matcher found; and set-up mode offers no card for a
    /// display whose picture another candidate shows.
    func testMirroredDisplaysGoToTheFlow() throws {
        var inputs = Desk.inputs
        let mirroring = with(Desk.hdmi) {
            $0.mirrors = Desk.lg.displayID
            $0.name = "Display"
        }
        inputs.displays = Desk.displays.map { $0.displayID == Desk.hdmi.displayID ? mirroring : $0 }
        let calibrate = try XCTUnwrap(Resolver.setUpStart(for: ilitek, purpose: .calibrate, in: inputs))
        XCTAssertEqual(calibrate.candidates, [mirroring], "the display its pairing resolves to")
        XCTAssertEqual(calibrate.allDisplays, inputs.displays, "the LG it mirrors included")
        XCTAssertNotNil(SetUpFlow(calibrate, at: 1), "the flow finds the picture through the LG")
        let scene = Resolver.setUpScene(inputs).scene
        XCTAssertEqual(scene.displays, inputs.displays)
        XCTAssertEqual(scene.cards.map(\.id), [Desk.display.displayID, Desk.strip.displayID],
                       "HDMI mirrors LG: neither; never the built-in display")
    }

    func testANilOutcomeStoresNothingButTheOffer() {
        var inputs = Desk.inputs
        inputs.settings.touchscreens[ilitek]?.wasOfferedSetUp = false
        for purpose in [SetUpPurpose.calibrate, .test] {
            XCTAssertEqual(Resolver.applySetUp(nil, purpose: purpose, to: ilitek, in: inputs, endedByThePerson: true),
                           inputs.settings)
        }
        XCTAssertEqual(Resolver.applySetUp(nil, purpose: .full, to: ilitek, in: inputs, endedByThePerson: true),
                       with(inputs.settings) { $0.touchscreens[Desk.ilitekID]?.wasOfferedSetUp = true })
        XCTAssertEqual(Resolver.applySetUp(nil, purpose: .full, to: ilitek, in: inputs, endedByThePerson: false),
                       inputs.settings, "an ending the person didn't choose")
    }

    // MARK: - Review, fix round 1

    /// `seconds` of ticks 10 times a second, with no input; a finger resting on the ILITEK
    /// throughout when `resting` (its frames come with each tick).
    private func idle(_ harness: ModelHarness, _ seconds: Double, resting: Int? = nil) {
        for _ in 0..<Int((seconds * 10).rounded()) {
            harness.clock += 0.1
            if let resting { harness.source.send(glassFrame(harness.clock, (resting, 0.5, 0.5)), from: Desk.ilitekHandle) }
            harness.model.tickPipelines()
        }
    }

    /// Item 1 (Important): a forgotten set-up ends by itself after `SetUpFlow.idleTimeout` without
    /// input, in every step, storing nothing.
    func testAForgottenSetUpEndsByItselfInEveryStep() throws {
        // Offered before, and paired: leaving has nothing at all to store.
        let settings = with(Desk.settings) { $0.touchscreens[Desk.ilitekID]?.wasOfferedSetUp = true }
        let calibrate: (ModelHarness) -> Void = { $0.model.perform(.beginSetUp(self.ilitek, .calibrate)) }
        let mode: (ModelHarness) -> Void = { $0.model.perform(.beginSetUpMode) }
        let steps: [(String, (ModelHarness) -> Void, (ModelHarness) -> Void)] = [
            ("corners", calibrate, { _ in }),
            ("corners, two taps in", calibrate, { harness in
                for point in SetUpDesk.cornerTaps(on: Desk.hdmi).prefix(2) {
                    harness.tick(after: 1.1)
                    self.tap(point, harness)
                }
            }),
            ("check", calibrate, { self.tapCorners(on: Desk.hdmi, $0) }),
            ("the mode, choosing", mode, { _ in }),
            ("the mode, waiting for a touch", mode, { $0.model.perform(.setUpChoose(displayID: Desk.display.displayID)) }),
            ("the mode, size", mode, { self.pairAndFit(Desk.display, $0) }),
            ("the mode, check after the size", mode, {
                self.pairAndFit(Desk.display, $0)
                $0.model.perform(.setUpConfirmSize(inches: 18))
            }),
        ]
        for (name, begin, reach) in steps {
            let harness = try deskHarness(self, settings: settings)
            let before = try Data(contentsOf: harness.settingsURL)
            begin(harness)
            reach(harness)
            XCTAssertTrue(harness.model.snapshot.setUp != nil || harness.model.snapshot.setUpMode != nil, name)
            idle(harness, SetUpFlow.idleTimeout - 1)
            XCTAssertTrue(harness.model.snapshot.setUp != nil || harness.model.snapshot.setUpMode != nil,
                          "\(name): not yet")
            idle(harness, 1.5)
            XCTAssertNil(harness.model.snapshot.setUp, "\(name): ended by itself")
            XCTAssertNil(harness.model.snapshot.setUpMode, "\(name): ended by itself")
            XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .driving, "\(name): back to what the table gives")
            XCTAssertEqual(try Data(contentsOf: harness.settingsURL), before, "\(name): nothing stored")
            XCTAssertFalse(harness.ticker.isRunning, "\(name): the clock stopped")
            XCTAssertEqual(harness.outputs.events, [], name)
        }
    }

    /// Item 1: a finger resting on the glass when the set-up ends by itself is not a touch. In the
    /// check step too: since the flow's second fix round only a landing or real movement there is
    /// input, so a finger resting through the time limit no longer keeps the step open.
    func testAFingerRestingWhenASetUpEndsByItselfGivesNoClick() throws {
        let settings = with(Desk.settings) { $0.touchscreens[Desk.ilitekID]?.wasOfferedSetUp = true }
        let calibrate: (ModelHarness) -> Void = { $0.model.perform(.beginSetUp(self.ilitek, .calibrate)) }
        let mode: (ModelHarness) -> Void = { $0.model.perform(.beginSetUpMode) }
        // The check step's display, where its circles are shown, for the two check steps.
        let steps: [(String, (ModelHarness) -> Void, UInt32?, (ModelHarness) -> Void)] = [
            ("corners", calibrate, nil, { $0.tick(after: 1.1) }),
            ("check", calibrate, Desk.hdmi.displayID, { self.tapCorners(on: Desk.hdmi, $0) }),
            ("the mode, choosing", mode, nil, { $0.tick(after: 1.1) }),
            ("the mode, size", mode, nil, { self.pairAndFit(Desk.display, $0) }),
            ("the mode, check after the size", mode, Desk.display.displayID, {
                self.pairAndFit(Desk.display, $0)
                $0.model.perform(.setUpConfirmSize(inches: 18))
            }),
        ]
        for (name, begin, checkDisplay, reach) in steps {
            let harness = try deskHarness(self, settings: settings)
            begin(harness)
            reach(harness)
            if let checkDisplay { XCTAssertEqual(step(harness), .check(display: checkDisplay), name) }
            let circlesBefore = harness.outputs.record.circles.count
            // A finger lands, and rests: its frames go on, and are no input after its landing.
            idle(harness, SetUpFlow.idleTimeout + 1, resting: 7)
            XCTAssertNil(harness.model.snapshot.setUp, "\(name): ended with the finger down")
            XCTAssertNil(harness.model.snapshot.setUpMode, "\(name): ended with the finger down")
            if let checkDisplay {
                XCTAssertTrue(harness.outputs.record.circles[circlesBefore...].contains(.hide(display: checkDisplay)),
                              "\(name): the check step's circles hidden as it ends")
            }
            XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .driving, name)
            idle(harness, 0.5, resting: 7)
            harness.send([glassFrame(harness.clock + 0.05)], from: Desk.ilitekHandle)
            harness.tick(after: 1)
            XCTAssertEqual(harness.outputs.events, [], "\(name): no click when it lifts")
            XCTAssertNil(harness.outputs.arbiter.owner, name)

            tap(CGPoint(x: 0.5, y: 0.5), harness)
            XCTAssertEqual(harness.outputs.count(.down), 1, "\(name): the next tap clicks")
        }
    }

    /// Item 2: while a set-up runs, nothing else changes a pairing, an orientation, an alignment or a
    /// diagonal, so Done never undoes such a change nor is undone by it.
    func testCommandsThatChangeAFitChangeNothingWhileASetUpRuns() throws {
        // A diagonal set during a calibration: refused; Done stores the fit and the diagonal as it was.
        let diagonal = try deskHarness(self)
        diagonal.model.perform(.beginSetUp(ilitek, .calibrate))
        let before = try Data(contentsOf: diagonal.settingsURL)
        diagonal.model.perform(.setDiagonal(ilitek, inches: 27))
        XCTAssertEqual(try Data(contentsOf: diagonal.settingsURL), before)
        tapCorners(on: Desk.hdmi, diagonal)
        lookAtTheCheck(diagonal)
        diagonal.model.perform(.setUpDone)
        let fitted = try XCTUnwrap(diagonal.savedSettings()?.touchscreens[ilitek])
        XCTAssertEqual(fitted.diagonalInches, 23.8)
        XCTAssertEqual(fitted.pairing?.orientation, turned, "the fit stored")

        // Unpairing during a calibration: refused; Done stores the fit on the display it had.
        let unpair = try deskHarness(self)
        unpair.model.perform(.beginSetUp(ilitek, .calibrate))
        unpair.model.perform(.unpair(ilitek))
        XCTAssertEqual(unpair.savedSettings()?.touchscreens[ilitek]?.pairing?.display, DisplayIdentity(Desk.hdmi))
        tapCorners(on: Desk.hdmi, unpair)
        lookAtTheCheck(unpair)
        unpair.model.perform(.setUpDone)
        XCTAssertEqual(unpair.savedSettings()?.touchscreens[ilitek]?.pairing?.display, DisplayIdentity(Desk.hdmi))
        XCTAssertEqual(unpair.savedSettings()?.touchscreens[ilitek]?.pairing?.orientation, turned)

        // Pairing the strip with HDMI during the ILITEK's calibration: refused, and Done leaves the
        // strip on its own display.
        let pair = try deskHarness(self)
        pair.model.perform(.beginSetUp(ilitek, .calibrate))
        pair.model.perform(.pair(strip, displayID: Desk.hdmi.displayID))
        XCTAssertEqual(pair.savedSettings()?.touchscreens[strip]?.pairing?.display, DisplayIdentity(Desk.strip))
        XCTAssertEqual(pair.savedSettings()?.touchscreens[ilitek]?.pairing?.display, DisplayIdentity(Desk.hdmi))
        tapCorners(on: Desk.hdmi, pair)
        lookAtTheCheck(pair)
        pair.model.perform(.setUpDone)
        XCTAssertEqual(pair.savedSettings()?.touchscreens[strip]?.pairing?.display, DisplayIdentity(Desk.strip))
        XCTAssertEqual(pair.touchscreen(strip)?.mode, .driving)

        // Behaviour, on and off, and names still apply.
        pair.model.perform(.beginSetUp(ilitek, .calibrate))
        pair.model.perform(.setOneFinger(strip, .alwaysDrag))
        pair.model.perform(.rename(strip, to: "Strip"))
        pair.model.perform(.setTouchscreenOn(strip, false))
        let saved = try XCTUnwrap(pair.savedSettings()?.touchscreens[strip])
        XCTAssertEqual(saved.oneFinger, .alwaysDrag)
        XCTAssertEqual(saved.customName, "Strip")
        XCTAssertFalse(saved.isOn)
    }

    func testTheResolverRefusesFitCommandsWhileASetUpRuns() {
        var inputs = Desk.inputs
        let remembered = TouchscreenID(rawValue: "1234:5678:R")
        inputs.settings.touchscreens[remembered] = Desk.paired("Old panel", with: Desk.lg)
        inputs.setUp = SetUpSnapshot(touchscreen: ilitek, touchscreenName: "ILITEK-TP", purpose: .calibrate,
                                     step: .corners(display: Desk.hdmi.displayID, target: CGPoint(x: 0.12, y: 0.12),
                                                    index: 0, problem: nil))
        for id in [ilitek, strip, remembered] {
            for command: AppCommand in [
                .pair(id, displayID: Desk.display.displayID), .unpair(id), .forget(id),
                .setOrientation(id, Orientation(quarterTurns: 2, isFlipped: true)), .clearCalibration(id),
                .setDiagonal(id, inches: 30),
            ] {
                XCTAssertEqual(Resolver.apply(command, to: inputs), inputs.settings, "\(command)")
            }
            XCTAssertNotEqual(Resolver.apply(.setOneFinger(id, .alwaysScroll), to: inputs), inputs.settings)
        }
        inputs.setUp = nil
        XCTAssertNotEqual(Resolver.apply(.setDiagonal(ilitek, inches: 30), to: inputs), inputs.settings, "with none running")

        // A calibration keeps the stored diagonal, whatever its outcome says.
        let outcome = SetUpFlow.Outcome(display: DisplayIdentity(Desk.hdmi), orientation: turned, alignment: .wholeGlass,
                                        diagonalInches: 27)
        XCTAssertEqual(Resolver.applySetUp(outcome, purpose: .calibrate, to: ilitek, in: inputs, endedByThePerson: true)
                        .touchscreens[ilitek]?.diagonalInches, 23.8)
    }

    /// Item 3: one Done writes the settings file once, the display's name included.
    func testOneDoneWritesTheSettingsOnce() throws {
        let harness = try makeHarness(settings: ilitekUnpaired)
        harness.source.plugIn(Desk.ilitek())
        harness.source.plugIn(Desk.stripScreen())
        harness.model.start()
        pairAndFit(Desk.hdmi, harness)
        harness.model.perform(.setUpConfirmSize(inches: 23.8))
        lookAtTheCheck(harness)
        let saves = harness.model.saves
        harness.model.perform(.setUpDone)
        XCTAssertEqual(harness.model.saves - saves, 1, "full, onto a new display")
        XCTAssertEqual(harness.savedSettings()?.touchscreens[ilitek]?.pairing?.displayName, "HDMI")

        // A calibration to another fit, from a card in the mode: one write. (The same fit again
        // would change nothing, and write nothing.)
        harness.model.perform(.beginSetUp(ilitek, .calibrate))
        XCTAssertEqual(stage(harness), .running, "inside the mode")
        for point in SetUpDesk.cornerTaps(on: Desk.hdmi, orientation: Orientation(quarterTurns: 2, isFlipped: true)) {
            harness.tick(after: 1.1)
            tap(point, harness)
        }
        lookAtTheCheck(harness)
        let again = harness.model.saves
        harness.model.perform(.setUpDone)
        XCTAssertEqual(harness.model.saves - again, 1, "calibrate")
        XCTAssertEqual(stage(harness), .choosing, "back to the screens")

        // The pure part: the name comes with the pairing.
        var inputs = Desk.inputs
        inputs.settings.touchscreens[ilitek]?.unpair()
        let outcome = SetUpFlow.Outcome(display: DisplayIdentity(Desk.hdmi), orientation: .asFitted, alignment: .wholeGlass,
                                        diagonalInches: nil)
        XCTAssertEqual(Resolver.applySetUp(outcome, purpose: .full, to: ilitek, in: inputs, endedByThePerson: true)
                        .touchscreens[ilitek]?.pairing?.displayName, "HDMI")
    }

    /// Only the person's endings of set-up mode (Finish, Esc, its own time limit) and Not Now count as
    /// the offer made; an interruption doesn't.
    func testOnlyThePersonsEndingsCountAsOffered() throws {
        let endings: [(String, (ModelHarness) -> Void, (ModelHarness) -> Void)] = [
            ("lock", { $0.conditions.setSessionActive(false) }, { $0.conditions.setSessionActive(true) }),
            ("sleep", { $0.conditions.sleep() }, { $0.conditions.wake() }),
            ("Tactile off", { $0.model.perform(.setOn(false)) }, { $0.model.perform(.setOn(true)) }),
            ("Accessibility gone", { $0.conditions.setAccessibility(false) }, { $0.conditions.setAccessibility(true) }),
        ]
        for (name, end, undo) in endings {
            let harness = try makeHarness(settings: ilitekUnpaired)
            harness.source.plugIn(Desk.ilitek())
            harness.source.plugIn(Desk.stripScreen())
            harness.model.start()
            XCTAssertEqual(harness.model.snapshot.offerSetUpTo, [ilitek], name)
            harness.model.perform(.beginSetUpMode)
            end(harness)
            XCTAssertNil(harness.model.snapshot.setUpMode, name)
            undo(harness)
            XCTAssertEqual(harness.savedSettings()?.touchscreens[ilitek]?.wasOfferedSetUp, false, name)
            XCTAssertEqual(harness.model.snapshot.offerSetUpTo, [ilitek], "\(name): offered again")
        }

        // Quitting.
        let quit = try makeHarness(settings: ilitekUnpaired)
        quit.source.plugIn(Desk.ilitek())
        quit.model.start()
        quit.model.perform(.beginSetUpMode)
        quit.model.shutDown()
        XCTAssertEqual(quit.savedSettings()?.touchscreens[ilitek]?.wasOfferedSetUp, false)

        // The person's endings: Finish or Esc, and the mode's own time limit.
        for (name, end) in [("Finish", { (h: ModelHarness) in h.model.perform(.cancelSetUp) }),
                            ("time limit", { (h: ModelHarness) in self.idle(h, SetUpFlow.idleTimeout + 1) })] {
            let harness = try makeHarness(settings: ilitekUnpaired)
            harness.source.plugIn(Desk.ilitek())
            harness.model.start()
            harness.model.perform(.beginSetUpMode)
            end(harness)
            XCTAssertNil(harness.model.snapshot.setUpMode, name)
            XCTAssertEqual(harness.savedSettings()?.touchscreens[ilitek]?.wasOfferedSetUp, true, name)
            XCTAssertEqual(harness.model.snapshot.offerSetUpTo, [], "\(name): not offered again")
        }
    }

    /// Set Up is never shown possible when it would be refused.
    func testCanBeSetUpIsFalseWhenSetUpWouldBeRefused() throws {
        var running = Desk.inputs
        running.setUp = SetUpSnapshot(touchscreen: ilitek, touchscreenName: "ILITEK-TP", purpose: .test,
                                      step: .check(display: Desk.hdmi.displayID))
        XCTAssertEqual(Resolver.resolve(running).snapshot.touchscreens.map(\.canBeSetUp), [false, false],
                       "while a set-up runs, for every touchscreen")
        var mode = Desk.inputs
        mode.setUpMode = SetUpModeSnapshot(stage: .choosing, displays: [], touchscreens: [], justSetUp: nil, notice: nil)
        XCTAssertEqual(Resolver.resolve(mode).snapshot.touchscreens.map(\.canBeSetUp), [false, false],
                       "while set-up mode is on")
        var reconfiguring = Desk.inputs
        reconfiguring.displays = []
        reconfiguring.lastKnownDisplays = Desk.displays
        XCTAssertEqual(Resolver.resolve(reconfiguring).snapshot.touchscreens.map(\.canBeSetUp), [false, false],
                       "while the displays reconfigure")
        XCTAssertEqual(Resolver.setUpModeRefusal(reconfiguring)?.words, "the displays are reconfiguring")
        XCTAssertEqual(Resolver.resolve(reconfiguring).snapshot.setUpModeRefusal, .notNow)

        let harness = try deskHarness(self)
        harness.displays.set([])
        XCTAssertEqual(harness.touchscreen(ilitek)?.canBeSetUp, false)
        harness.displays.set(Desk.displays)
        XCTAssertEqual(harness.touchscreen(ilitek)?.canBeSetUp, true)
        harness.model.perform(.beginSetUp(ilitek, .calibrate))
        XCTAssertEqual(harness.touchscreen(strip)?.canBeSetUp, false)
        harness.model.perform(.cancelSetUp)
        XCTAssertEqual(harness.touchscreen(strip)?.canBeSetUp, true)
    }

    // MARK: - Carried over from 2b's final review

    func testTheDisplaysStayInTheSnapshotWhileTheyReconfigure() throws {
        let harness = try deskHarness(self)
        let displays = harness.model.snapshot.displays
        let pane = try XCTUnwrap(harness.touchscreen(ilitek))
        harness.displays.set([])
        let during = try XCTUnwrap(harness.touchscreen(ilitek))
        XCTAssertEqual(during.mode, .held, "nothing is mapped")
        XCTAssertEqual(harness.model.snapshot.displays, displays, "the displays seen last")
        XCTAssertEqual(during.pairedDisplayID, pane.pairedDisplayID, "the Display pop-up doesn't flash \"not connected\"")
        XCTAssertEqual(during.displayChoices, pane.displayChoices)
        XCTAssertEqual(DisplayPick(during), .display(Desk.hdmi.displayID))

        harness.displays.set(Desk.displays.filter { $0.displayID != Desk.hdmi.displayID })
        XCTAssertNil(harness.touchscreen(ilitek)?.pairedDisplayID, "settled without it: gone")
        XCTAssertEqual(harness.model.snapshot.displays.count, 4)
    }
}

private extension TouchscreenSnapshot {
    /// The handle of the connected touchscreen this snapshot shows, by its ID or provisional ID.
    func handle(in inputs: AppInputs) -> DeviceHandle? {
        if let record = inputs.records.first(where: { $0.value == id }) { return record.key }
        return id.rawValue.hasPrefix("#1:") ? DeviceHandle(rawValue: 1) : nil
    }
}
