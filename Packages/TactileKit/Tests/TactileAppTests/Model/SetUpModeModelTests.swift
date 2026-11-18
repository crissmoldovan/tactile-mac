// Delivery 5, Part S: set-up mode through the model, with its fakes: no device, event, window or
// pointer; the settings folder is temporary. The plan's Review Focus 1 to 5, every way of leaving at
// every stage, the offers, and random interleavings holding the anti-goals.

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
final class SetUpModeModelTests: XCTestCase {
    private let ilitek = Desk.ilitekID
    private let strip = Desk.stripID
    /// How the ILITEK's glass is fitted in these tests: turned half round, the picture a little in
    /// from its edges.
    private let turned = Orientation(quarterTurns: 2, isFlipped: false)
    private let rect = SetUpDesk.offCentre

    // MARK: - Helpers

    /// The desk's settings with the ILITEK unpaired and never offered set-up; the strip on its own
    /// display.
    private var ilitekUnpaired: TactileSettings {
        with(Desk.settings) { $0.touchscreens[Desk.ilitekID]?.unpair() }
    }

    private func stage(_ harness: ModelHarness) -> SetUpModeSnapshot.Stage? {
        harness.model.snapshot.setUpMode?.stage
    }

    private func step(_ harness: ModelHarness) -> SetUpStep? {
        harness.model.snapshot.setUp?.step
    }

    /// A tap at glass point `p` of `handle`: landing now, held still 0.1 s in frames 10 ms apart.
    private func tap(_ p: CGPoint, _ harness: ModelHarness, _ handle: DeviceHandle = Desk.ilitekHandle) {
        let t = harness.clock
        harness.send((0..<10).map { glassFrame(t + Double($0) * 0.01, (1, p.x, p.y)) } + [glassFrame(t + 0.1)], from: handle)
    }

    /// Past the last change by more than a reaction, the person clicks `display`'s card, and half a
    /// second later touches the middle of `handle`'s glass.
    private func chooseAndTouch(_ display: DisplayFacts, _ harness: ModelHarness,
                                _ handle: DeviceHandle = Desk.ilitekHandle) {
        harness.tick(after: 1.1)
        harness.model.perform(.setUpChoose(displayID: display.displayID))
        harness.tick(after: 0.5)
        tap(CGPoint(x: 0.5, y: 0.5), harness, handle)
    }

    /// The four corners on `display`, for a glass fitted `orientation` over `rect`, each well after
    /// the target appeared.
    private func tapCorners(on display: DisplayFacts, _ harness: ModelHarness, _ handle: DeviceHandle = Desk.ilitekHandle,
                            orientation: Orientation = .asFitted, rect: CGRect = SetUpDesk.wholeGlass) {
        for point in SetUpDesk.cornerTaps(on: display, orientation: orientation, rect: rect) {
            harness.tick(after: 1.1)
            tap(point, harness, handle)
        }
    }

    /// The whole of one touchscreen's set-up in the mode, from the overview to Done: `handle`'s
    /// touchscreen on `display`, fitted as given, its size confirmed as `inches`.
    private func setUp(_ handle: DeviceHandle, on display: DisplayFacts, _ harness: ModelHarness,
                       orientation: Orientation = .asFitted, rect: CGRect = SetUpDesk.wholeGlass, inches: Double?) {
        chooseAndTouch(display, harness, handle)
        tapCorners(on: display, harness, handle, orientation: orientation, rect: rect)
        harness.model.perform(.setUpConfirmSize(inches: inches))
        harness.tick(after: 0.5)
        harness.model.perform(.setUpDone)
    }

    /// What a set-up stores for each touchscreen, as saved: its display, orientation and alignment,
    /// and its size. The pairing's remembered name is left out: the model remembers it whenever the
    /// display is seen.
    private func fits(_ harness: ModelHarness) -> [TouchscreenID: String] {
        (harness.savedSettings()?.touchscreens ?? [:]).mapValues { screen in
            let pairing = screen.pairing.map { "\($0.display) \($0.orientation) \($0.alignment)" } ?? "unpaired"
            return pairing + " \(String(describing: screen.diagonalInches))"
        }
    }

    /// The UUIDs of the displays each stored touchscreen is paired with, by touchscreen.
    private func pairings(_ harness: ModelHarness) -> [TouchscreenID: String] {
        (harness.savedSettings()?.touchscreens ?? [:]).compactMapValues { $0.pairing?.display.uuid }
    }

    // MARK: - The mode, through the model

    func testWhileTheModeIsOnEveryTouchscreenIsSetUpInputAndNoneDrives() throws {
        let harness = try deskHarness(self)
        let drag = try SurveyTakes.ilitek(take: 11)
        harness.send(drag.prefix(drag.count / 2), from: Desk.ilitekHandle)
        XCTAssertEqual(harness.outputs.count(.down), 1, "the ILITEK's drag has begun")

        harness.model.perform(.beginSetUpMode)
        XCTAssertEqual(harness.outputs.count(.up), 1, "its button released at once")
        XCTAssertNil(harness.outputs.arbiter.owner)
        XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .settingUp)
        XCTAssertEqual(harness.touchscreen(strip)?.mode, .settingUp)
        guard case .pairedWith("HDMI", _)? = harness.touchscreen(ilitek)?.status else {
            return XCTFail("its status as it would otherwise be: \(String(describing: harness.touchscreen(ilitek)?.status))")
        }

        // The rest of the drag, a strip take, taps: nothing posted, nothing moved.
        let before = harness.outputs.events.count
        harness.send(drag.dropFirst(drag.count / 2), from: Desk.ilitekHandle)
        let stripTake = try SurveyTakes.strip(take: 9)
        harness.send(stripTake.map { ContactFrame(time: $0.time - stripTake[0].time + harness.clock + 0.5, contacts: $0.contacts) },
                     from: Desk.stripHandle)
        harness.tick(after: 1)
        tap(CGPoint(x: 0.3, y: 0.3), harness, Desk.stripHandle)
        XCTAssertEqual(harness.outputs.events.count, before, "no click, no drag, no pointer moved")
        XCTAssertEqual(harness.outputs.record.warps, [])

        // A touchscreen that can't be set up is held, never driving: its touches are set-up input too.
        harness.source.change(Desk.stripHandle) { $0.status.touchOrigin = .unreadable }
        XCTAssertEqual(harness.touchscreen(strip)?.mode, .held)
        XCTAssertEqual(harness.model.snapshot.setUpMode?.touchscreens.first { $0.id == strip }?.state, .cannotBeSetUp)
        XCTAssertEqual(harness.model.snapshot.setUpMode?.touchscreens.first { $0.id == strip }?.reason,
                       "Its touches can’t be read.", "as the pane words it")
        harness.source.change(Desk.stripHandle) { $0.status.touchOrigin = .mouseInterface }

        // One that is off and left to macOS is taken for the mode, and let go again after it.
        harness.model.perform(.cancelSetUp)
        harness.model.perform(.setTouchscreenOn(strip, false))
        harness.model.perform(.setWhenOff(strip, .leaveToMacOS))
        XCTAssertEqual(harness.touchscreen(strip)?.mode, .released)
        harness.model.perform(.beginSetUpMode)
        XCTAssertEqual(harness.touchscreen(strip)?.mode, .settingUp)
        XCTAssertEqual(harness.source.state(of: Desk.stripHandle), .taken)
        harness.model.perform(.cancelSetUp)
        XCTAssertEqual(harness.touchscreen(strip)?.mode, .released)
    }

    func testATouchscreenConnectedDuringTheModeJoinsIt() throws {
        let harness = try deskHarness(self)
        harness.model.perform(.beginSetUpMode)
        let other = Desk.ilitek(handle: DeviceHandle(rawValue: 5), facts: TouchscreenFacts(
            vendorID: 0x222a, productID: 0x0001, serial: "OTHER", locationID: 0x0120_0000, name: "ILITEK-TP"))
        harness.source.plugIn(other)
        let id = TouchscreenIdentity.baseID(vendorID: 0x222a, productID: 0x0001, serial: "OTHER")
        XCTAssertEqual(harness.touchscreen(id)?.mode, .settingUp, "it joins: setting up, not driving")
        XCTAssertEqual(harness.model.snapshot.setUpMode?.touchscreens.map(\.id), [ilitek, strip, id])
        XCTAssertEqual(harness.model.snapshot.setUpMode?.touchscreens.last?.state, .notSetUp)
        harness.tick(after: 1.1)
        tap(CGPoint(x: 0.5, y: 0.5), harness, DeviceHandle(rawValue: 5))
        XCTAssertEqual(stage(harness), .touchedFirst(touchscreen: id, name: "ILITEK-TP"))
    }

    func testFitCommandsAreRefusedWhileTheModeIsOn() throws {
        let harness = try deskHarness(self)
        harness.model.perform(.beginSetUpMode)
        let before = try Data(contentsOf: harness.settingsURL)
        for command: AppCommand in [
            .pair(strip, displayID: Desk.hdmi.displayID), .unpair(ilitek), .setOrientation(ilitek, turned),
            .clearCalibration(strip), .setDiagonal(ilitek, inches: 30),
        ] {
            harness.model.perform(command)
            XCTAssertEqual(try Data(contentsOf: harness.settingsURL), before, "\(command), between the mode's flows")
        }
        chooseAndTouch(Desk.display, harness)
        harness.model.perform(.setDiagonal(ilitek, inches: 30))
        XCTAssertEqual(try Data(contentsOf: harness.settingsURL), before, "while a flow runs in it")
        harness.model.perform(.setOneFinger(strip, .alwaysDrag))
        XCTAssertEqual(harness.savedSettings()?.touchscreens[strip]?.oneFinger, .alwaysDrag, "behaviour still applies")

        // The resolver's part.
        var inputs = Desk.inputs
        inputs.setUpMode = harness.model.snapshot.setUpMode
        XCTAssertEqual(Resolver.apply(.unpair(ilitek), to: inputs), inputs.settings)
        XCTAssertNotEqual(Resolver.apply(.rename(ilitek, to: "Top"), to: inputs), inputs.settings)
    }

    // MARK: - Review Focus 1: the wrong touchscreen answers

    func testTheWrongTouchscreenAnsweringGetsTheFlowAndBackIsTheWayOut() throws {
        let harness = try deskHarness(self, settings: ilitekUnpaired)
        let before = try Data(contentsOf: harness.settingsURL)
        harness.model.perform(.beginSetUpMode)
        // The person chose HDMI, meaning the ILITEK, and touched the strip.
        chooseAndTouch(Desk.hdmi, harness, Desk.stripHandle)
        XCTAssertEqual(harness.model.snapshot.setUp?.touchscreen, strip, "the strip's flow")
        XCTAssertEqual(step(harness), .corners(display: Desk.hdmi.displayID, target: Calibration.targets[0], index: 0,
                                               problem: nil), "its corners on the display chosen")
        XCTAssertEqual(stage(harness), .running)
        XCTAssertEqual(try Data(contentsOf: harness.settingsURL), before, "nothing stored before Done")

        // The ILITEK's touches meanwhile answer nothing.
        harness.tick(after: 1.1)
        tap(CGPoint(x: 0.5, y: 0.5), harness)
        XCTAssertEqual(harness.model.snapshot.setUp?.touchscreen, strip)

        harness.model.perform(.setUpBack)
        XCTAssertEqual(stage(harness), .choosing)
        XCTAssertNil(harness.model.snapshot.setUp)
        XCTAssertEqual(try Data(contentsOf: harness.settingsURL), before, "Back stores nothing")
        XCTAssertEqual(harness.outputs.events, [])
    }

    func testBothTouchedAtOnceTheFirstToLiftWins() throws {
        let harness = try deskHarness(self, settings: ilitekUnpaired)
        harness.model.perform(.beginSetUpMode)
        harness.tick(after: 1.1)
        harness.model.perform(.setUpChoose(displayID: Desk.hdmi.displayID))
        harness.tick(after: 0.5)
        let t = harness.clock
        harness.source.send(glassFrame(t, (1, 0.5, 0.5)), from: Desk.ilitekHandle)
        harness.source.send(glassFrame(t + 0.01, (1, 0.5, 0.5)), from: Desk.stripHandle)
        harness.source.send(glassFrame(t + 0.05, (1, 0.5, 0.5)), from: Desk.stripHandle)
        harness.clock = t + 0.06
        harness.source.send(glassFrame(t + 0.06), from: Desk.ilitekHandle)
        XCTAssertEqual(harness.model.snapshot.setUp?.touchscreen, ilitek, "the ILITEK lifted first")
        harness.clock = t + 0.2
        harness.source.send(glassFrame(t + 0.2), from: Desk.stripHandle)
        XCTAssertEqual(harness.model.snapshot.setUp?.touchscreen, ilitek, "the strip's touch was ignored")
        guard case .corners(Desk.hdmi.displayID, _, 0, nil)? = step(harness) else {
            return XCTFail("\(String(describing: step(harness)))")
        }
    }

    // MARK: - Review Focus 2: a finger already resting

    func testAFingerRestingWhenAStageChangesIsNoAnswer() throws {
        let harness = try deskHarness(self, settings: ilitekUnpaired)
        harness.model.perform(.beginSetUpMode)
        harness.tick(after: 1.5)
        // The ILITEK's finger lands in the overview, and the click comes while it rests.
        let t = harness.clock
        harness.send((0..<5).map { glassFrame(t + Double($0) * 0.01, (2, 0.5, 0.5)) }, from: Desk.ilitekHandle)
        harness.model.perform(.setUpChoose(displayID: Desk.hdmi.displayID))
        harness.send((5..<60).map { glassFrame(t + Double($0) * 0.01, (2, 0.5, 0.5)) } + [glassFrame(t + 0.6)],
                     from: Desk.ilitekHandle)
        XCTAssertEqual(stage(harness), .waitingForTouch(display: Desk.hdmi.displayID), "it lifted: no answer")
        harness.tick(after: 0.3)
        tap(CGPoint(x: 0.5, y: 0.5), harness)
        XCTAssertEqual(stage(harness), .running, "landing again answers")
    }

    // MARK: - Review Focus 3: leaving at every stage

    /// Every way of leaving, at every stage, after one touchscreen was Done in the same session:
    /// exactly what was Done is stored; every touchscreen returns to the table's mode; no button is
    /// held; nothing of the mode is left showing.
    func testLeavingAtEveryStageStoresExactlyWhatWasDone() throws {
        let stages: [(String, (ModelHarness) -> Void)] = [
            ("choosing", { _ in }),
            ("waiting for a touch", { $0.tick(after: 1.1); $0.model.perform(.setUpChoose(displayID: Desk.display.displayID)) }),
            ("touched first", { $0.tick(after: 1.1); self.tap(CGPoint(x: 0.5, y: 0.5), $0, Desk.stripHandle) }),
            ("corners", { self.chooseAndTouch(Desk.display, $0, Desk.stripHandle) }),
            ("size", {
                self.chooseAndTouch(Desk.display, $0, Desk.stripHandle)
                self.tapCorners(on: Desk.display, $0, Desk.stripHandle)
            }),
            ("check", {
                self.chooseAndTouch(Desk.display, $0, Desk.stripHandle)
                self.tapCorners(on: Desk.display, $0, Desk.stripHandle)
                $0.model.perform(.setUpConfirmSize(inches: 18))
                // A finger on the glass in the check: shown, and down as the mode ends.
                $0.send([glassFrame($0.clock + 0.2, (1, 0.5, 0.5))], from: Desk.stripHandle)
            }),
            ("a test", { $0.tick(after: 0.5); $0.model.perform(.beginSetUp(self.ilitek, .test)) }),
        ]
        let routes: [(String, (ModelHarness) -> Void, (ModelHarness) -> Void)] = [
            ("Finish or Esc", { $0.model.perform(.cancelSetUp) }, { _ in }),
            ("the time limit", { harness in
                for _ in 0..<1220 where harness.model.snapshot.setUpMode != nil { harness.tick(after: 0.1) }
            }, { _ in }),
            ("lock", { $0.conditions.setSessionActive(false) }, { $0.conditions.setSessionActive(true) }),
            ("sleep", { $0.conditions.sleep() }, { $0.conditions.wake() }),
            ("Tactile off", { $0.model.perform(.setOn(false)) }, { $0.model.perform(.setOn(true)) }),
            ("Accessibility lost", { $0.conditions.setAccessibility(false) }, { $0.conditions.setAccessibility(true) }),
        ]
        for (stageName, reach) in stages {
            for (routeName, leave, undo) in routes {
                let name = "\(stageName), \(routeName)"
                let harness = try deskHarness(self, settings: ilitekUnpaired)
                harness.model.perform(.beginSetUpMode)
                setUp(Desk.ilitekHandle, on: Desk.hdmi, harness, orientation: turned, rect: rect, inches: 23.8)
                XCTAssertEqual(harness.model.snapshot.setUpMode?.justSetUp, ilitek, name)
                let done = try XCTUnwrap(harness.savedSettings(), name)
                reach(harness)
                XCTAssertNotNil(harness.model.snapshot.setUpMode, name)
                leave(harness)
                XCTAssertNil(harness.model.snapshot.setUpMode, "\(name): the mode has ended")
                XCTAssertNil(harness.model.snapshot.setUp, "\(name): its flow too")
                XCTAssertNil(harness.model.setUpFlow, name)
                undo(harness)
                let saved = try XCTUnwrap(harness.savedSettings(), name)
                XCTAssertEqual(saved.touchscreens[ilitek], done.touchscreens[ilitek], "\(name): the Done stored, as it was")
                XCTAssertEqual(saved.touchscreens[ilitek]?.pairing?.display, DisplayIdentity(Desk.hdmi), name)
                XCTAssertEqual(saved.touchscreens[strip]?.pairing, done.touchscreens[strip]?.pairing,
                               "\(name): nothing more stored")
                XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .driving, "\(name): back to the table's mode")
                XCTAssertEqual(harness.touchscreen(ilitek)?.pairedDisplayID, Desk.hdmi.displayID, name)
                XCTAssertEqual(harness.touchscreen(strip)?.mode, .driving, name)
                XCTAssertEqual(harness.touchscreen(strip)?.pairedDisplayID, Desk.strip.displayID, name)
                XCTAssertEqual(harness.outputs.events, [], "\(name): no button pressed, none held")
                XCTAssertNil(harness.outputs.arbiter.owner, name)
                if case .show? = harness.outputs.record.circles.last { XCTFail("\(name): circles left showing") }
            }
        }
    }

    func testQuittingInTheModeStoresExactlyWhatWasDoneAndLetsGo() throws {
        for reachCorners in [false, true] {
            let harness = try deskHarness(self, settings: ilitekUnpaired)
            harness.model.perform(.beginSetUpMode)
            setUp(Desk.ilitekHandle, on: Desk.hdmi, harness, inches: nil)
            if reachCorners { chooseAndTouch(Desk.display, harness, Desk.stripHandle) }
            let done = harness.savedSettings()
            harness.model.shutDown()
            XCTAssertEqual(harness.savedSettings()?.touchscreens, done?.touchscreens)
            XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .released)
            XCTAssertEqual(harness.source.state(of: Desk.stripHandle), .released)
            XCTAssertNil(harness.model.setUpFlow)
            XCTAssertEqual(harness.outputs.events, [])
        }
    }

    /// The chosen display or the answering touchscreen going: back to the overview, saying so;
    /// nothing stored; the mode goes on.
    func testTheChosenDisplayOrTheAnsweringTouchscreenGoing() throws {
        let harness = try deskHarness(self, settings: ilitekUnpaired)
        let before = try Data(contentsOf: harness.settingsURL)
        harness.model.perform(.beginSetUpMode)

        // The chosen display unplugged while waiting for a touch.
        harness.tick(after: 1.1)
        harness.model.perform(.setUpChoose(displayID: Desk.display.displayID))
        harness.displays.set(Desk.displays.filter { $0.displayID != Desk.display.displayID })
        XCTAssertEqual(stage(harness), .choosing)
        XCTAssertEqual(harness.model.snapshot.setUpMode?.notice, .displayGone(name: "Display"))
        XCTAssertFalse(harness.model.snapshot.setUpMode?.displays.contains { $0.id == Desk.display.displayID } ?? true)

        // The chosen display unplugged while its flow runs.
        harness.displays.set(Desk.displays)
        chooseAndTouch(Desk.display, harness)
        harness.displays.set(Desk.displays.filter { $0.displayID != Desk.display.displayID })
        XCTAssertEqual(stage(harness), .choosing)
        XCTAssertNil(harness.model.snapshot.setUp)
        XCTAssertEqual(harness.model.snapshot.setUpMode?.notice, .displayGone(name: "Display"))

        // The answering touchscreen unplugged while its flow runs.
        harness.displays.set(Desk.displays)
        chooseAndTouch(Desk.display, harness)
        harness.source.unplug(Desk.ilitekHandle)
        XCTAssertEqual(stage(harness), .choosing)
        XCTAssertEqual(harness.model.snapshot.setUpMode?.notice, .touchscreenGone(name: "ILITEK-TP"))
        XCTAssertEqual(harness.model.snapshot.setUpMode?.touchscreens.map(\.id), [strip], "its line gone")

        // Plugged in again, it joins the mode; touched first, then unplugged.
        harness.source.plugIn(Desk.ilitek(handle: DeviceHandle(rawValue: 8)))
        XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .settingUp)
        harness.tick(after: 1.1)
        tap(CGPoint(x: 0.5, y: 0.5), harness, DeviceHandle(rawValue: 8))
        XCTAssertEqual(stage(harness), .touchedFirst(touchscreen: ilitek, name: "ILITEK-TP"))
        harness.source.unplug(DeviceHandle(rawValue: 8))
        XCTAssertEqual(stage(harness), .choosing)
        XCTAssertEqual(harness.model.snapshot.setUpMode?.notice, .touchscreenGone(name: "ILITEK-TP"))

        XCTAssertEqual(try Data(contentsOf: harness.settingsURL), before, "nothing stored")
        XCTAssertEqual(harness.outputs.events, [])
        harness.model.perform(.cancelSetUp)
        XCTAssertEqual(harness.touchscreen(strip)?.mode, .driving)
    }

    /// While the displays reconfigure (none published for a moment), the stage and the cards stay as
    /// last known, no answer is taken, and nothing is taken for gone.
    func testAReconfigurationKeepsTheOverviewAndTakesNoAnswer() throws {
        let harness = try deskHarness(self, settings: ilitekUnpaired)
        harness.model.perform(.beginSetUpMode)
        harness.tick(after: 1.1)
        harness.model.perform(.setUpChoose(displayID: Desk.hdmi.displayID))
        let before = try XCTUnwrap(harness.model.snapshot.setUpMode)
        harness.displays.set([])
        XCTAssertEqual(harness.model.snapshot.setUpMode, before, "as last known")
        XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .settingUp)
        harness.tick(after: 0.5)
        tap(CGPoint(x: 0.5, y: 0.5), harness)
        XCTAssertEqual(stage(harness), .waitingForTouch(display: Desk.hdmi.displayID), "no answer meanwhile")
        harness.displays.set(Desk.displays)
        harness.tick(after: 0.5)
        tap(CGPoint(x: 0.5, y: 0.5), harness)
        XCTAssertEqual(stage(harness), .running, "settled: a touch answers")
    }

    // MARK: - Fix round 1, item 1: a mirror set

    /// A display whose picture another candidate also shows gets no card: a click couldn't tell the
    /// members of a mirror set apart, and Done would store a guess. One alone with its picture keeps
    /// its card.
    func testAMirrorSetGetsNoCardAndCannotBeChosen() throws {
        let lgMirroringHDMI = with(Desk.lg) { $0.mirrors = Desk.hdmi.displayID }
        let mirrored = [Desk.builtIn, lgMirroringHDMI, Desk.hdmi, Desk.strip, Desk.display]
        let harness = try deskHarness(self, settings: ilitekUnpaired)
        harness.displays.set(mirrored)
        harness.model.perform(.beginSetUpMode)
        XCTAssertEqual(harness.model.snapshot.setUpMode?.displays.map(\.id), [Desk.display.displayID, Desk.strip.displayID],
                       "neither member of the mirror set")
        // The ILITEK (on HDMI) touched, then LG's picture clicked: nothing chosen, nothing started.
        harness.tick(after: 1.5)
        tap(CGPoint(x: 0.5, y: 0.5), harness)
        XCTAssertEqual(stage(harness), .touchedFirst(touchscreen: ilitek, name: "ILITEK-TP"))
        harness.tick(after: 1.1)
        harness.model.perform(.setUpChoose(displayID: Desk.lg.displayID))
        harness.model.perform(.setUpChoose(displayID: Desk.hdmi.displayID))
        XCTAssertEqual(stage(harness), .touchedFirst(touchscreen: ilitek, name: "ILITEK-TP"))
        XCTAssertNil(harness.model.snapshot.setUp)

        // The strip mirroring the built-in display, which is never a candidate: alone with its
        // picture, it keeps its card.
        var inputs = Desk.inputs
        inputs.displays = [Desk.builtIn, Desk.lg, Desk.hdmi, with(Desk.strip) { $0.mirrors = Desk.builtIn.displayID }, Desk.display]
        XCTAssertTrue(Resolver.setUpScene(inputs).scene.cards.contains { $0.id == Desk.strip.displayID })
        // A mirror set with nothing else: nothing to set up on.
        inputs.displays = [Desk.builtIn, lgMirroringHDMI, Desk.hdmi]
        XCTAssertEqual(Resolver.setUpScene(inputs).scene.cards, [])
        XCTAssertEqual(Resolver.setUpModeRefusal(inputs)?.words, "there is no display to set one up on")
        XCTAssertEqual(Resolver.resolve(inputs).snapshot.setUpModeRefusal, .noDisplayToChoose)
    }

    func testMirroringStartingWhileWaitingOnOneOfTheSetIsTheDisplayGone() throws {
        let harness = try deskHarness(self, settings: ilitekUnpaired)
        harness.model.perform(.beginSetUpMode)
        harness.tick(after: 1.1)
        harness.model.perform(.setUpChoose(displayID: Desk.hdmi.displayID))
        XCTAssertEqual(stage(harness), .waitingForTouch(display: Desk.hdmi.displayID))
        harness.displays.set([Desk.builtIn, with(Desk.lg) { $0.mirrors = Desk.hdmi.displayID }, Desk.hdmi, Desk.strip,
                              Desk.display])
        XCTAssertEqual(stage(harness), .choosing)
        XCTAssertEqual(harness.model.snapshot.setUpMode?.notice, .displayGone(name: "HDMI"))
        harness.tick(after: 0.5)
        tap(CGPoint(x: 0.5, y: 0.5), harness)
        XCTAssertNil(harness.model.snapshot.setUp, "no flow on either")
    }

    // MARK: - Fix round 1, item 3: the offers after Finish

    func testATouchscreenConnectedDuringTheModeIsNotOfferedAfterFinish() throws {
        let harness = try ModelHarness(settings: ilitekUnpaired)
        addTeardownBlock { @MainActor in harness.cleanUp() }
        harness.source.statusWhenTaken[Desk.stripHandle] = Desk.taken(origin: .mouseInterface, inputMode: .switchedToMultiTouch)
        harness.source.plugIn(Desk.stripScreen())
        harness.model.start()
        harness.model.perform(.beginSetUpMode)
        harness.source.plugIn(Desk.ilitek())
        XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .settingUp, "it joins")
        XCTAssertEqual(harness.model.snapshot.setUpMode?.touchscreens.first { $0.id == ilitek }?.state, .notSetUp)
        harness.model.perform(.cancelSetUp)
        XCTAssertEqual(harness.model.snapshot.offerSetUpTo, [], "the session card showed it: the offer was made")
        XCTAssertEqual(harness.savedSettings()?.touchscreens[ilitek]?.wasOfferedSetUp, true)
    }

    func testATouchscreenUnpairedByAnothersDoneIsNotOfferedAfterFinish() throws {
        let harness = try deskHarness(self)
        harness.model.perform(.beginSetUpMode)
        // The strip set up on HDMI, the ILITEK's display: one write, the ILITEK unpaired.
        setUp(Desk.stripHandle, on: Desk.hdmi, harness, inches: nil)
        XCTAssertNil(harness.savedSettings()?.touchscreens[ilitek]?.pairing)
        XCTAssertEqual(harness.model.snapshot.setUpMode?.touchscreens.first { $0.id == ilitek }?.state, .notSetUp)
        harness.model.perform(.cancelSetUp)
        XCTAssertEqual(harness.model.snapshot.offerSetUpTo, [])
        XCTAssertEqual(harness.savedSettings()?.touchscreens[ilitek]?.wasOfferedSetUp, true)

        // Interrupted instead: nothing marked, and the offer is made.
        let interrupted = try deskHarness(self)
        interrupted.model.perform(.beginSetUpMode)
        setUp(Desk.stripHandle, on: Desk.hdmi, interrupted, inches: nil)
        interrupted.conditions.setSessionActive(false)
        interrupted.conditions.setSessionActive(true)
        XCTAssertEqual(interrupted.model.snapshot.offerSetUpTo, [ilitek])
    }

    // MARK: - Fix round 1, item 4: the reviewer's probes

    /// One finger on `handle`, frames every 10 ms for `seconds`, moving `dx` of the glass overall
    /// from `x`.
    private func rest(_ harness: ModelHarness, _ handle: DeviceHandle, for seconds: Double, from x: Double = 0.5,
                      dx: Double = 0) {
        let t = harness.clock
        let n = max(1, Int(seconds / 0.01))
        harness.send((1...n).map { glassFrame(t + Double($0) * 0.01, (1, x + dx * Double($0) / Double(n), 0.5)) },
                     from: handle)
    }

    private func lift(_ harness: ModelHarness, _ handle: DeviceHandle) {
        harness.send([glassFrame(harness.clock + 0.01)], from: handle)
    }

    /// Review Focus 3: a finger resting at the moment of leaving, at every stage, on either
    /// touchscreen, by Finish or by the time limit (resting all along), never clicks or drags when it
    /// then moves and lifts; a new tap clicks.
    func testAFingerRestingAtLeavingNeverClicksOrDrags() throws {
        let stages: [(String, (ModelHarness) -> Void)] = [
            ("choosing", { $0.tick(after: 1.5) }),
            ("waiting", { $0.tick(after: 1.5); $0.model.perform(.setUpChoose(displayID: Desk.lg.displayID)) }),
            ("touched first by the strip", { $0.tick(after: 1.5); self.tap(CGPoint(x: 0.5, y: 0.5), $0, Desk.stripHandle) }),
            ("the ILITEK's flow", { self.chooseAndTouch(Desk.lg, $0, Desk.ilitekHandle) }),
            ("the strip's flow", { self.chooseAndTouch(Desk.lg, $0, Desk.stripHandle) }),
        ]
        let routes: [(String, (ModelHarness, DeviceHandle) -> Void)] = [
            ("Finish", { harness, _ in harness.model.perform(.cancelSetUp) }),
            ("the time limit, the finger resting all along", { harness, handle in
                for _ in 0..<1300 where harness.model.snapshot.setUpMode != nil {
                    self.rest(harness, handle, for: 0.1)
                    harness.tick(after: 0.001)
                }
            }),
        ]
        for (stageName, reach) in stages {
            for handle in [Desk.ilitekHandle, Desk.stripHandle] {
                for (routeName, leave) in routes {
                    let name = "\(stageName), \(handle == Desk.ilitekHandle ? "the ILITEK" : "the strip"), \(routeName)"
                    let harness = try deskHarness(self)
                    harness.model.perform(.beginSetUpMode)
                    reach(harness)
                    harness.tick(after: 0.6)
                    rest(harness, handle, for: 0.3)
                    leave(harness, handle)
                    XCTAssertNil(harness.model.snapshot.setUpMode, "\(name): ended")
                    XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .driving, name)
                    XCTAssertEqual(harness.touchscreen(strip)?.mode, .driving, name)
                    let before = harness.outputs.events.count
                    rest(harness, handle, for: 0.8, dx: 0.3)
                    lift(harness, handle)
                    harness.tick(after: 0.5)
                    XCTAssertEqual(Array(harness.outputs.events.dropFirst(before)).map(\.kind), [],
                                   "\(name): the resting finger, moved and lifted after leaving, posts nothing")
                    harness.tick(after: 1)
                    tap(CGPoint(x: 0.4, y: 0.4), harness, handle)
                    harness.tick(after: 0.5)
                    XCTAssertGreaterThan(harness.outputs.count(.down), 0, "\(name): a new tap clicks")
                }
            }
        }
    }

    /// Review Focus 2: a finger resting when the mode begins, the panel then silent for longer than
    /// the mode's first second but within `TouchPipeline.silenceLimit`, then frames of that finger:
    /// the same touch, no answer. (After the silence limit, a lost lift is assumed, and a later
    /// frame is a new touch.)
    func testAFingerRestingAtTheBeginningThenSilenceIsNoAnswer() throws {
        for silence in [0.5, 1.2, 1.4] {
            XCTAssertLessThan(silence, TouchPipeline.silenceLimit)
            let harness = try deskHarness(self, settings: ilitekUnpaired)
            rest(harness, Desk.ilitekHandle, for: 0.2)
            harness.model.perform(.beginSetUpMode)
            harness.tick(after: silence)
            rest(harness, Desk.ilitekHandle, for: 0.2, dx: 0.01)
            lift(harness, Desk.ilitekHandle)
            XCTAssertEqual(stage(harness), .choosing, "silence \(silence): no answer")
        }
    }

    /// A strip scrolling (its default) when the mode begins: its scroll is ended, and nothing more is
    /// posted while the mode is on; no button held.
    func testATouchscreenScrollingWhenTheModeBeginsPostsNothingMore() throws {
        let harness = try deskHarness(self)
        XCTAssertEqual(harness.touchscreen(strip)?.behaviour.oneFinger, .alwaysScroll)
        harness.tick(after: 1)
        rest(harness, Desk.stripHandle, for: 0.3, dx: 0.3)
        XCTAssertGreaterThan(harness.outputs.count(.scroll), 0, "scrolling")
        harness.model.perform(.beginSetUpMode)
        let begun = harness.outputs.events.count
        rest(harness, Desk.stripHandle, for: 0.5, dx: 0.3)
        lift(harness, Desk.stripHandle)
        for _ in 0..<30 { harness.tick(after: 0.1) }
        XCTAssertEqual(harness.outputs.events.dropFirst(begun).map(\.kind), [], "nothing once the mode is on")
        XCTAssertEqual(harness.outputs.count(.down), harness.outputs.count(.up))
    }

    /// Calibrate Corners… while the mode waits for a touch: it runs in the mode, writes once, keeps
    /// the size, and returns to the overview.
    func testCalibrateInsideTheModeFromWaiting() throws {
        let harness = try deskHarness(self)
        harness.model.perform(.beginSetUpMode)
        harness.tick(after: 1.1)
        harness.model.perform(.setUpChoose(displayID: Desk.lg.displayID))
        harness.model.perform(.beginSetUp(ilitek, .calibrate))
        XCTAssertEqual(harness.model.snapshot.setUp?.purpose, .calibrate)
        XCTAssertEqual(stage(harness), .running)
        tapCorners(on: Desk.hdmi, harness, rect: SetUpDesk.offCentre)
        harness.tick(after: 0.5)
        let saves = harness.model.saves
        harness.model.perform(.setUpDone)
        XCTAssertEqual(harness.model.saves - saves, 1)
        XCTAssertEqual(stage(harness), .choosing)
        XCTAssertEqual(harness.savedSettings()?.touchscreens[ilitek]?.diagonalInches, 23.8, "the size kept")
        XCTAssertEqual(harness.savedSettings()?.touchscreens[ilitek]?.pairing?.display, DisplayIdentity(Desk.hdmi))
    }

    // MARK: - Review Focus 4: a display paired with another touchscreen

    func testSettingUpOnAnotherTouchscreensDisplayMovesThePairingInOneWrite() throws {
        let harness = try deskHarness(self)
        harness.model.perform(.setOneFinger(strip, .alwaysDrag))
        harness.model.perform(.rename(strip, to: "Strip"))
        let before = try XCTUnwrap(harness.savedSettings())
        harness.model.perform(.beginSetUpMode)
        XCTAssertEqual(harness.model.snapshot.setUpMode?.displays.first { $0.id == Desk.strip.displayID }?.touchscreen,
                       strip, "the strip's display says so on its card")

        // **Set Up Again Here** on the strip's card, and the ILITEK touched.
        chooseAndTouch(Desk.strip, harness)
        XCTAssertEqual(harness.model.snapshot.setUp?.touchscreen, ilitek)
        tapCorners(on: Desk.strip, harness)
        harness.model.perform(.setUpConfirmSize(inches: 12.3))
        harness.tick(after: 0.5)
        let saves = harness.model.saves
        harness.model.perform(.setUpDone)
        XCTAssertEqual(harness.model.saves - saves, 1, "one write")

        let saved = try XCTUnwrap(harness.savedSettings())
        XCTAssertEqual(saved.touchscreens[ilitek]?.pairing?.display, DisplayIdentity(Desk.strip), "the new one paired there")
        XCTAssertEqual(saved.touchscreens[ilitek]?.diagonalInches, 12.3)
        XCTAssertNil(saved.touchscreens[strip]?.pairing, "the old one unpaired")
        XCTAssertEqual(Set(pairings(harness).values).count, pairings(harness).count, "never two on one display")
        // Never one touchscreen's settings on another.
        XCTAssertEqual(saved.touchscreens[strip]?.oneFinger, .alwaysDrag)
        XCTAssertEqual(saved.touchscreens[strip]?.customName, "Strip")
        XCTAssertEqual(saved.touchscreens[strip]?.diagonalInches, before.touchscreens[strip]?.diagonalInches)
        XCTAssertNil(saved.touchscreens[ilitek]?.oneFinger)
        XCTAssertNil(saved.touchscreens[ilitek]?.customName)

        let mode = try XCTUnwrap(harness.model.snapshot.setUpMode)
        XCTAssertEqual(mode.displays.first { $0.id == Desk.strip.displayID }?.touchscreen, ilitek)
        XCTAssertNil(mode.displays.first { $0.id == Desk.hdmi.displayID }?.touchscreen, "HDMI free now")
        XCTAssertEqual(mode.touchscreens.first { $0.id == strip }?.state, .notSetUp)
        XCTAssertEqual(mode.touchscreens.first { $0.id == ilitek }?.state, .setUp(displayName: "12.3FHD"))

        harness.model.perform(.cancelSetUp)
        XCTAssertEqual(harness.touchscreen(ilitek)?.pairedDisplayID, Desk.strip.displayID)
        XCTAssertEqual(harness.touchscreen(strip)?.status, .notSetUp)
        XCTAssertEqual(harness.touchscreen(strip)?.mode, .held)
    }

    // MARK: - Review Focus 5: nothing to set up

    func testTheModeDoesNotBeginWithNothingToSetUp() throws {
        // No connected touchscreen can be set up: the strip alone, in mouse mode macOS still sees.
        let shared = try ModelHarness(settings: Desk.settings)
        addTeardownBlock { @MainActor in shared.cleanUp() }
        shared.source.statusWhenTaken[Desk.stripHandle] = Desk.taken(
            origin: .mouseInterface, inputMode: .switchedToMultiTouch, exclusive: .failed)
        shared.source.plugIn(Desk.stripScreen())
        shared.model.start()
        XCTAssertEqual(shared.touchscreen(strip)?.canBeSetUp, false)
        shared.model.perform(.beginSetUpMode)
        XCTAssertNil(shared.model.snapshot.setUpMode)
        XCTAssertEqual(shared.touchscreen(strip)?.mode, .held)
        let sharedInputs = with(Desk.inputs) {
            $0.connected = [Desk.stripScreen(status: Desk.taken(origin: .mouseInterface, exclusive: .failed))]
        }
        XCTAssertEqual(Resolver.setUpModeRefusal(sharedInputs)?.words, "no connected touchscreen can be set up")
        XCTAssertEqual(Resolver.resolve(sharedInputs).snapshot.setUpModeRefusal, .noTouchscreenCanBeSetUp)

        // No touchscreen at all.
        let none = try ModelHarness(settings: Desk.settings)
        addTeardownBlock { @MainActor in none.cleanUp() }
        none.model.start()
        none.model.perform(.beginSetUpMode)
        XCTAssertNil(none.model.snapshot.setUpMode)

        // No candidate display.
        let harness = try deskHarness(self)
        harness.displays.set([Desk.builtIn])
        XCTAssertEqual(harness.model.snapshot.touchscreens.map(\.canBeSetUp), [false, false])
        harness.model.perform(.beginSetUpMode)
        harness.model.perform(.beginSetUp(ilitek, .full))
        XCTAssertNil(harness.model.snapshot.setUpMode)
        XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .held, "the table's mode, unchanged")

        // And whatever else would refuse it: the words for the log, and the reason the snapshot
        // carries for the menu and the panes.
        let refusals: [(String, SetUpModeRefusal, (inout AppInputs) -> Void)] = [
            ("Tactile is off", .tactileOff, { $0.settings.isOn = false }),
            ("no Accessibility access", .accessibilityMissing, { $0.hasAccessibilityAccess = false }),
            ("the session isn't active", .notNow, { $0.isSessionActive = false }),
            ("the Mac is asleep", .notNow, { $0.isAsleep = true }),
            ("Tactile is quitting", .notNow, { $0.isQuitting = true }),
            ("the displays are reconfiguring", .notNow, { $0.displays = []; $0.lastKnownDisplays = Desk.displays }),
            ("no display is connected", .noDisplay, { $0.displays = [] }),
            ("set-up mode is already on", .running, {
                $0.setUpMode = SetUpModeSnapshot(stage: .choosing, displays: [], touchscreens: [], justSetUp: nil, notice: nil)
            }),
            ("a set-up of 222a:0001:V06.00.00.00 is running", .running, {
                $0.setUp = SetUpSnapshot(touchscreen: Desk.ilitekID, touchscreenName: "ILITEK-TP", purpose: .test,
                                         step: .check(display: Desk.hdmi.displayID))
            }),
            ("there is no display to set one up on", .noDisplayToChoose, { $0.displays = [Desk.builtIn] }),
        ]
        for (reason, refusal, change) in refusals {
            let inputs = with(Desk.inputs, change)
            XCTAssertEqual(Resolver.setUpModeRefusal(inputs)?.words, reason)
            XCTAssertEqual(Resolver.setUpModeRefusal(inputs)?.refusal, refusal, reason)
            let snapshot = Resolver.resolve(inputs).snapshot
            XCTAssertEqual(snapshot.setUpModeRefusal, refusal, reason)
            XCTAssertEqual(snapshot.touchscreens.map(\.canBeSetUp), [false, false], reason)
        }
        XCTAssertNil(Resolver.setUpModeRefusal(Desk.inputs))
        XCTAssertNil(Resolver.resolve(Desk.inputs).snapshot.setUpModeRefusal)
    }

    // MARK: - Offers

    func testTheOffersNameEveryTouchscreenNotSetUp() throws {
        var settings = Desk.settings
        settings.touchscreens[ilitek]?.unpair()
        settings.touchscreens[strip]?.unpair()
        let harness = try deskHarness(self, settings: settings)
        XCTAssertEqual(harness.model.snapshot.offerSetUpTo, [ilitek, strip])

        harness.model.perform(.declineSetUp(strip))
        XCTAssertEqual(harness.model.snapshot.offerSetUpTo, [ilitek], "Not Now for one")
        harness.model.perform(.beginSetUpMode)
        XCTAssertEqual(harness.model.snapshot.offerSetUpTo, [], "not while the mode is on")

        // Leaving by Finish marks every one not set up when it began.
        harness.model.perform(.cancelSetUp)
        XCTAssertEqual(harness.model.snapshot.offerSetUpTo, [])
        XCTAssertEqual(harness.savedSettings()?.touchscreens[ilitek]?.wasOfferedSetUp, true)

        // Off: not offered. Tactile off, or no Accessibility: not offered.
        var fresh = Desk.inputs
        fresh.settings = settings
        XCTAssertEqual(Resolver.resolve(fresh).snapshot.offerSetUpTo, [ilitek, strip])
        XCTAssertEqual(Resolver.resolve(with(fresh) { $0.settings.touchscreens[Desk.ilitekID]?.isOn = false })
                        .snapshot.offerSetUpTo, [strip])
        XCTAssertEqual(Resolver.resolve(with(fresh) { $0.settings.isOn = false }).snapshot.offerSetUpTo, [])
        XCTAssertEqual(Resolver.resolve(with(fresh) { $0.hasAccessibilityAccess = false }).snapshot.offerSetUpTo, [])
        XCTAssertEqual(Resolver.resolve(with(fresh) {
            $0.setUpMode = SetUpModeSnapshot(stage: .choosing, displays: [], touchscreens: [], justSetUp: nil, notice: nil)
        }).snapshot.offerSetUpTo, [])
    }

    // MARK: - One finger, set up in the mode

    func testAFlowInTheModeShowsItsCheckCircles() throws {
        let harness = try deskHarness(self, settings: ilitekUnpaired)
        harness.model.perform(.beginSetUpMode)
        chooseAndTouch(Desk.hdmi, harness)
        tapCorners(on: Desk.hdmi, harness, orientation: turned, rect: rect)
        harness.model.perform(.setUpConfirmSize(inches: nil))
        harness.tick(after: 0.5)
        tap(SetUpDesk.glassPoint(touching: CGPoint(x: 0.25, y: 0.75), on: Desk.hdmi, orientation: turned, rect: rect), harness)
        let shown = harness.outputs.record.circles.compactMap { call -> CGPoint? in
            if case .show(Desk.hdmi.displayID, let fingers, [], []) = call { return fingers[1] }
            return nil
        }
        XCTAssertEqual(Double(shown.first?.x ?? 0), 0.25, accuracy: 1e-6)
        XCTAssertEqual(Double(shown.first?.y ?? 0), 0.75, accuracy: 1e-6)
        // A strip touch meanwhile is not shown.
        tap(CGPoint(x: 0.5, y: 0.5), harness, Desk.stripHandle)
        XCTAssertFalse(harness.outputs.record.circles.contains {
            if case .show(Desk.strip.displayID, _, _, _) = $0 { return true }
            return false
        })
        harness.send([glassFrame(harness.clock + 0.3, (2, 0.5, 0.5))], from: Desk.ilitekHandle)
        harness.model.perform(.setUpBack)
        XCTAssertEqual(harness.outputs.record.circles.last, .hide(display: Desk.hdmi.displayID), "its circles go")
    }

    // MARK: - The time limit

    /// The mode's two minutes count only input that can move it on: 150 s of landings from a
    /// touchscreen that can't be set up (the strip in mouse mode, macOS also handling it) end the
    /// mode at 120 s, every touchscreen back to the table's mode.
    func testLandingsFromATouchscreenThatCantBeSetUpDoNotKeepTheModeOn() throws {
        let harness = try deskHarness(self)
        harness.model.perform(.beginSetUpMode)
        let begun = harness.clock
        harness.source.change(Desk.stripHandle) { $0.status = Desk.taken(origin: .mouseInterface, exclusive: .failed) }
        XCTAssertNotNil(harness.model.snapshot.setUpMode)
        XCTAssertEqual(harness.model.snapshot.setUpMode?.touchscreens.first { $0.id == strip }?.state, .cannotBeSetUp)
        var endedAt: TimeInterval?
        for _ in 0..<150 {
            for _ in 0..<10 { harness.tick(after: 0.1) }
            let t = harness.clock + 0.01
            harness.send([glassFrame(t, (1, 0.5, 0.5)), glassFrame(t + 0.05)], from: Desk.stripHandle)
            if endedAt == nil, harness.model.snapshot.setUpMode == nil { endedAt = harness.clock }
        }
        let ended = try XCTUnwrap(endedAt, "150 s of landings kept the mode on")
        XCTAssertEqual(ended - begun, SetUpFlow.idleTimeout, accuracy: 1.2, "two minutes from its beginning")
        XCTAssertEqual(harness.touchscreen(ilitek)?.mode, .driving, "the table's mode again")
    }

    // MARK: - Anything in any order

    /// Random interleavings, from a fixed seed, of the mode's commands, frames from both
    /// touchscreens, ticks, locks, sleep, display changes, unplugging and switching off, against the
    /// anti-goals: while the mode is on no touchscreen drives, nothing is posted, and no button is
    /// held; nothing is stored but by a Done; never two touchscreens on one display.
    func testAnythingInAnyOrder() throws {
        var generator = SplitMix64(seed: 2026_11_15)
        var modes = 0, dones = 0
        for _ in 0..<12 {
            let harness = try deskHarness(self, settings: ilitekUnpaired)
            var ilitekHandle = Desk.ilitekHandle
            var ilitekPlugged = true
            for _ in 0..<300 {
                let modeWasOn = harness.model.snapshot.setUpMode != nil
                let eventsBefore = harness.outputs.events.count
                let fitsBefore = fits(harness)
                var calledDone = false
                // A flow's corners and its check are reached more often than chance would: a clean
                // tap on the target shown (on these unturned displays, fitted straight, a target's
                // place on the glass is the target itself), and Done once the check has been seen.
                let running = harness.model.snapshot.setUp
                var target: CGPoint?
                var inCheck = false
                switch running?.step {
                case .corners(_, let shown, _, _)?: target = shown
                case .check?: inCheck = true
                default: break
                }
                let runningHandle = running?.touchscreen == strip ? Desk.stripHandle : ilitekHandle
                switch Int.random(in: 0..<100, using: &generator) {
                case 0..<30 where target != nil:
                    harness.tick(after: 1.1)
                    tap(target!, harness, runningHandle)
                case 0..<30 where inCheck:
                    harness.tick(after: 0.5)
                    calledDone = true
                    harness.model.perform(.setUpDone)
                case 0..<6:
                    harness.model.perform(.beginSetUpMode)
                case 6..<14:
                    let ids = Desk.displays.map(\.displayID) + [99]
                    harness.model.perform(.setUpChoose(displayID: ids.randomElement(using: &generator)!))
                case 14..<17:
                    harness.model.perform(.setUpBack)
                case 17..<20:
                    harness.model.perform(.setUpConfirmSize(inches: [nil, 23.8, 12.3].randomElement(using: &generator)!))
                case 20..<26:
                    calledDone = true
                    harness.model.perform(.setUpDone)
                case 26..<28:
                    harness.model.perform(.setUpRedo)
                case 28..<30:
                    harness.model.perform(.cancelSetUp)
                case 30..<32:
                    harness.model.perform(.beginSetUp([ilitek, strip].randomElement(using: &generator)!,
                                                      [.test, .calibrate].randomElement(using: &generator)!))
                case 32..<62:
                    // A touch on either touchscreen: a tap, or a short slide.
                    let handle = Bool.random(using: &generator) ? ilitekHandle : Desk.stripHandle
                    let start = CGPoint(x: .random(in: 0...1, using: &generator), y: .random(in: 0...1, using: &generator))
                    let slide = Bool.random(using: &generator) ? 0.1 : 0
                    let t = harness.clock
                    harness.send((0..<8).map { glassFrame(t + Double($0) * 0.02, (1, start.x + slide * Double($0) / 8, start.y)) }
                                 + [glassFrame(t + 0.17)], from: handle)
                case 62..<85:
                    harness.tick(after: .random(in: 0.05...2, using: &generator))
                case 85..<87:
                    harness.conditions.setSessionActive(false)
                    harness.conditions.setSessionActive(true)
                case 87..<88:
                    harness.conditions.sleep()
                    harness.conditions.wake()
                case 88..<91:
                    let sets = [Desk.displays, Desk.displays.filter { $0.displayID != Desk.hdmi.displayID }, [],
                                Desk.displays.filter { $0.displayID != Desk.display.displayID }]
                    harness.displays.set(sets.randomElement(using: &generator)!)
                case 91..<93:
                    if ilitekPlugged {
                        harness.source.unplug(ilitekHandle)
                    } else {
                        ilitekHandle = DeviceHandle(rawValue: ilitekHandle.rawValue + 10)
                        harness.source.plugIn(Desk.ilitek(handle: ilitekHandle))
                    }
                    ilitekPlugged.toggle()
                case 93..<95:
                    harness.model.perform(.setOn(false))
                    harness.model.perform(.setOn(true))
                case 95..<96:
                    harness.conditions.setAccessibility(false)
                    harness.conditions.setAccessibility(true)
                default:
                    harness.tick(after: 121)
                }

                let modeIsOn = harness.model.snapshot.setUpMode != nil
                if modeIsOn { modes += 1 }
                if modeWasOn && modeIsOn {
                    XCTAssertEqual(harness.outputs.events.count, eventsBefore, "nothing posted while the mode is on")
                }
                if modeIsOn {
                    XCTAssertFalse(harness.model.snapshot.touchscreens.contains { $0.mode == .driving }, "none drives")
                    XCTAssertNil(harness.outputs.arbiter.owner)
                    XCTAssertEqual(harness.outputs.count(.down), harness.outputs.count(.up), "no button held")
                }
                let fitsAfter = fits(harness)
                if fitsAfter != fitsBefore {
                    XCTAssertTrue(calledDone, "a pairing, a fit or a size stored but by Done")
                    dones += 1
                }
                let paired = pairings(harness)
                XCTAssertEqual(Set(paired.values).count, paired.count, "never two touchscreens on one display")
            }
            harness.model.shutDown()
        }
        XCTAssertGreaterThan(modes, 100, "the mode was on for a good part of it")
        XCTAssertGreaterThan(dones, 0, "a Done was reached")
    }

    // MARK: - Anything in any order, across the mode and the tester

    /// A touch in progress on one touchscreen, in glass points 0…1.
    private struct Touch {
        var handle: DeviceHandle
        var fingers: [(id: Int, x: Double, y: Double)]
        var dx: Double
        var dy: Double
    }

    /// The Dock phases (`changed` aside) read as swipes: each a began, one end, and at most one
    /// repeat of that end. Nil when they don't read so; else how many began, and whether the last is
    /// still open.
    private func dockSwipes(_ phases: [DockEvent.Phase]) -> (count: Int, open: Bool)? {
        var count = 0, open = false, repeatable = false
        for phase in phases where phase != .changed {
            switch phase {
            case .began:
                if open { return nil }
                open = true
                repeatable = false
                count += 1
            case .ended, .cancelled:
                if open {
                    open = false
                    repeatable = true
                } else if repeatable {
                    repeatable = false
                } else {
                    return nil
                }
            case .changed:
                break
            }
        }
        return (count, open)
    }

    /// The final review's cross-feature property: random interleavings, from a fixed seed, of set-up
    /// mode (both ways in, every way out), the gesture tester (opened, moved, closed, cleared,
    /// swipes held or let through), followed and held swipes, drags and touches on both
    /// touchscreens mid-way through anything, the one-finger setting, locks, sleep, display sets
    /// with a mirror set, unplugging and switching off. After every step: the tester is never open
    /// in the mode or in a flow; nothing is posted while the mode stays on; none drives in the mode,
    /// and no button is held there; at most one button is down; the Dock phases read as swipes
    /// each with one end, and the sender agrees whether one is open; the tester's touchscreen
    /// drives. At the end of each run: every Dock swipe begun has ended, no button is held, and the
    /// state file equals the snapshot.
    func testAnythingInAnyOrderAcrossTheModeAndTheTester() throws {
        var generator = SplitMix64(seed: 2026_11_16)
        var stats = (modes: 0, testers: 0, began: 0, modeBeganMidTouch: 0, testerChangedMidTouch: 0)
        for run in 0..<120 {
            let harness = try deskHarness(self, writesStateFile: true)
            harness.model.perform(.setSwipesFollowFingers(Bool.random(using: &generator)))
            var touch: Touch?
            var ilitekPlugged = true
            var ilitekHandle = Desk.ilitekHandle
            func send(_ touch: Touch) {
                let frame = ContactFrame(time: harness.clock, contacts: touch.fingers.map {
                    Contact(id: $0.id, position: CGPoint(x: $0.x, y: $0.y))
                })
                harness.source.send(frame, from: touch.handle)
            }
            for step in 0..<400 {
                let name = "run \(run) step \(step)"
                let modeWasOn = harness.model.snapshot.setUpMode != nil
                let before = harness.outputs.events.count
                var r = Int.random(in: 0..<100, using: &generator)
                if touch != nil, Int.random(in: 0..<10, using: &generator) < 7 { r = 0 }
                switch r {
                case 0..<25:
                    // A touch: it lands, moves, and lifts over several steps.
                    if var current = touch {
                        harness.clock += 0.016
                        if Int.random(in: 0..<25, using: &generator) == 0 {
                            current.fingers = []
                            send(current)
                            touch = nil
                        } else {
                            current.fingers = current.fingers.map {
                                ($0.id, min(0.98, max(0.02, $0.x + current.dx)), min(0.98, max(0.02, $0.y + current.dy)))
                            }
                            send(current)
                            touch = current
                        }
                    } else {
                        let handle = (Bool.random(using: &generator) || !ilitekPlugged) ? Desk.stripHandle : ilitekHandle
                        let count = handle == Desk.stripHandle ? 1 : [1, 2, 3, 3, 3, 4, 4].randomElement(using: &generator)!
                        let x = Double.random(in: 0.3...0.6, using: &generator)
                        let fingers = (0..<count).map { (id: $0, x: x + 0.05 * Double($0), y: 0.5) }
                        let horizontal = Bool.random(using: &generator)
                        let speed = [-0.012, 0.012, -0.004, 0.004].randomElement(using: &generator)!
                        let new = Touch(handle: handle, fingers: fingers, dx: horizontal ? speed : 0, dy: horizontal ? 0 : speed)
                        harness.clock += 0.3
                        send(new)
                        touch = new
                    }
                case 25..<40:
                    harness.tick(after: touch != nil ? 1.0 / 60 : [1.0 / 60, 0.1, 0.5].randomElement(using: &generator)!)
                case 40..<46:
                    let hadTester = harness.model.snapshot.gestureTester != nil
                    harness.model.perform(.openGestureTester([ilitek, strip].randomElement(using: &generator)!))
                    if touch != nil, hadTester != (harness.model.snapshot.gestureTester != nil) {
                        stats.testerChangedMidTouch += 1
                    }
                case 46..<49:
                    if touch != nil, harness.model.snapshot.gestureTester != nil { stats.testerChangedMidTouch += 1 }
                    harness.model.perform(.closeGestureTester)
                case 49..<53:
                    harness.model.perform(.setGestureTesterPerformsSwipes(Bool.random(using: &generator)))
                case 53..<57:
                    let wasOff = harness.model.snapshot.setUpMode == nil
                    harness.model.perform([AppCommand.beginSetUpMode, .beginSetUp(strip, .full)].randomElement(using: &generator)!)
                    if wasOff, touch != nil, harness.model.snapshot.setUpMode != nil { stats.modeBeganMidTouch += 1 }
                case 57..<61:
                    harness.model.perform(.cancelSetUp)
                case 61..<64:
                    harness.model.perform(.setUpChoose(displayID: Desk.displays.map(\.displayID).randomElement(using: &generator)!))
                case 64..<66:
                    harness.model.perform(.setUpBack)
                case 66..<68:
                    harness.conditions.setSessionActive(false)
                    harness.conditions.setSessionActive(true)
                case 68..<69:
                    harness.conditions.sleep()
                    harness.conditions.wake()
                case 69..<72:
                    let mirrored = [Desk.builtIn, Desk.lg, with(Desk.hdmi) { $0.mirrors = Desk.lg.displayID }, Desk.strip, Desk.display]
                    let sets = [Desk.displays, [], Desk.displays.filter { $0 != Desk.hdmi }, mirrored]
                    harness.displays.set(sets.randomElement(using: &generator)!)
                case 72..<74:
                    if ilitekPlugged {
                        if touch?.handle == ilitekHandle { touch = nil }
                        harness.source.unplug(ilitekHandle)
                    } else {
                        ilitekHandle = DeviceHandle(rawValue: ilitekHandle.rawValue + 10)
                        harness.source.plugIn(Desk.ilitek(handle: ilitekHandle))
                    }
                    ilitekPlugged.toggle()
                case 74..<76:
                    harness.model.perform(.setOn(false))
                    harness.model.perform(.setOn(true))
                case 76..<77:
                    harness.conditions.setAccessibility(false)
                    harness.conditions.setAccessibility(true)
                case 77..<79:
                    let id = [ilitek, strip].randomElement(using: &generator)!
                    harness.model.perform(.setTouchscreenOn(id, false))
                    harness.model.perform(.setTouchscreenOn(id, true))
                case 79..<82:
                    harness.model.perform(.setOneFinger([ilitek, strip].randomElement(using: &generator)!,
                                                        [nil, .automatic, .alwaysScroll, .alwaysDrag].randomElement(using: &generator)!))
                case 82..<84:
                    harness.model.perform(.beginSetUp([ilitek, strip].randomElement(using: &generator)!,
                                                      [.test, .calibrate].randomElement(using: &generator)!))
                case 84..<86:
                    harness.model.perform(.clearGestureTester)
                case 86..<88:
                    harness.model.perform(.setSwipesFollowFingers(Bool.random(using: &generator)))
                default:
                    harness.outputs.runDockScheduled()
                }

                let snapshot = harness.model.snapshot
                let modeIsOn = snapshot.setUpMode != nil
                if modeIsOn { stats.modes += 1 }
                if snapshot.gestureTester != nil { stats.testers += 1 }
                if modeIsOn { XCTAssertNil(snapshot.gestureTester, "\(name): one owner: the tester is closed in the mode") }
                if snapshot.setUp != nil { XCTAssertNil(snapshot.gestureTester, "\(name): no tester in a flow") }
                if modeWasOn && modeIsOn {
                    XCTAssertEqual(harness.outputs.events.count, before, "\(name): nothing posted in the mode")
                }
                if modeIsOn {
                    XCTAssertFalse(snapshot.touchscreens.contains { $0.mode == .driving }, "\(name): none drives")
                    XCTAssertEqual(harness.outputs.count(.down), harness.outputs.count(.up), "\(name): no button held")
                }
                let downs = harness.outputs.count(.down) - harness.outputs.count(.up)
                XCTAssertTrue((0...1).contains(downs), "\(name): buttons \(downs)")
                let read = dockSwipes(harness.outputs.dockPhases)
                XCTAssertNotNil(read, "\(name): Dock phases \(harness.outputs.dockPhases.filter { $0 != .changed })")
                if let read { XCTAssertEqual(read.open, harness.outputs.dockSwipes.isOpen, name) }
                if let tester = snapshot.gestureTester {
                    XCTAssertTrue(snapshot.touchscreens.contains { $0.id == tester.touchscreen && $0.mode == .driving }
                                  || harness.model.inputs.lastKnownDisplays != nil, "\(name): the tester's touchscreen drives")
                }
            }
            // Lift, and let everything end.
            if var current = touch {
                harness.clock += 0.016
                current.fingers = []
                send(current)
            }
            for _ in 0..<300 { harness.tick(after: 1.0 / 60) }
            harness.outputs.runDockScheduled()
            for _ in 0..<60 { harness.tick(after: 1.0 / 60) }
            let read = dockSwipes(harness.outputs.dockPhases)
            stats.began += read?.count ?? 0
            XCTAssertEqual(read?.open, false,
                           "run \(run): every Dock swipe begun has one end: \(harness.outputs.dockPhases.filter { $0 != .changed })")
            XCTAssertFalse(harness.outputs.dockSwipes.isOpen, "run \(run)")
            XCTAssertEqual(harness.outputs.count(.down), harness.outputs.count(.up), "run \(run): no button held")
            if let data = try? Data(contentsOf: harness.stateURL),
               let written = try? JSONDecoder().decode(AppSnapshot.self, from: data) {
                XCTAssertEqual(written, harness.model.snapshot, "run \(run): the state file ends equal to the snapshot")
            } else {
                XCTFail("run \(run): no state file")
            }
            harness.model.shutDown()
        }
        // What it reached (on this seed: the mode on 10,708 steps, the tester open 5,272, 47 Dock
        // swipes, the mode begun mid-touch 298 times, the tester changed mid-touch 288).
        XCTAssertGreaterThan(stats.modes, 1000, "the mode was on for a good part of it")
        XCTAssertGreaterThan(stats.testers, 1000, "the tester was open for a good part of it")
        XCTAssertGreaterThan(stats.began, 10, "followed swipes reached the Dock")
        XCTAssertGreaterThan(stats.modeBeganMidTouch, 10, "the mode began mid-touch")
        XCTAssertGreaterThan(stats.testerChangedMidTouch, 10, "the tester opened, moved or closed mid-touch")
    }
}
