import CoreGraphics
import Foundation
@testable import TactileApp
import TactileDevices
import TactileReading
import TactileScreens
import XCTest

private typealias Desk = DeskFixture

/// `frames` moved in time so that the first is at `start`.
private func retimed(_ frames: [ContactFrame], startingAt start: TimeInterval) -> [ContactFrame] {
    guard let first = frames.first?.time else { return frames }
    return frames.map { ContactFrame(time: $0.time - first + start, contacts: $0.contacts) }
}

@MainActor
class TactileModelTests: XCTestCase {
    private var harness: ModelHarness!

    /// Whether this run has every behaviour after 0.2.0 off in the desk's settings (see
    /// `DeskFixture.newOptionsOff`). A touchscreen the model gives a new record starts from the
    /// defaults whatever this says.
    class var newOptionsOff: Bool { false }
    /// The touchscreen the gesture tester is open on in the desk's harness, if any
    /// (`TactileModelTestsWithATesterOpen`).
    class var testerOn: TouchscreenID? { nil }

    override func setUp() async throws {
        DeskFixture.newOptionsOff = Self.newOptionsOff
    }

    override func tearDown() async throws {
        DeskFixture.newOptionsOff = false
    }

    /// A harness for this test, cleaned up when it ends.
    private func makeHarness(
        settings: TactileSettings? = nil, fileBytes: Data? = nil, writesStateFile: Bool = false
    ) throws -> ModelHarness {
        let harness = try ModelHarness(settings: settings, fileBytes: fileBytes, writesStateFile: writesStateFile)
        addTeardownBlock { @MainActor in harness.cleanUp() }
        return harness
    }

    /// The desk, both touchscreens plugged in and started, long-press stored as `longPress`.
    private func deskHarness(writesStateFile: Bool = false, longPress: Bool = true) throws -> ModelHarness {
        var settings = Desk.settings
        // The second pass (`TactileModelTestsWithNewOptionsOff`) keeps long-press off, as `Desk.settings` gives it.
        for id in settings.touchscreens.keys {
            settings.touchscreens[id]?.gestures.longPress = longPress && !DeskFixture.newOptionsOff
        }
        let harness = try makeHarness(settings: settings, writesStateFile: writesStateFile)
        harness.source.statusWhenTaken[Desk.stripHandle] = Desk.taken(origin: .mouseInterface, inputMode: .switchedToMultiTouch)
        harness.source.plugIn(Desk.ilitek())
        harness.source.plugIn(Desk.stripScreen())
        harness.model.start()
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .driving)
        XCTAssertEqual(harness.touchscreen(Desk.stripID)?.mode, .driving)
        if let id = Self.testerOn {
            harness.model.perform(.openGestureTester(id))
            XCTAssertEqual(harness.model.snapshot.gestureTester?.touchscreen, id)
        }
        return harness
    }

    /// Half of the ILITEK's drag take, sent: the button is down.
    private func dragHalfWay(_ harness: ModelHarness) throws -> [ContactFrame] {
        let frames = try SurveyTakes.ilitek(take: 11)
        harness.send(frames.prefix(frames.count / 2), from: Desk.ilitekHandle)
        XCTAssertEqual(harness.outputs.count(.down), 1, "the drag has started")
        XCTAssertEqual(harness.outputs.count(.up), 0)
        return Array(frames.dropFirst(frames.count / 2))
    }

    // MARK: - The plan's tests

    func testPlugInPairAndTap() throws {
        let harness = try makeHarness()
        harness.model.start()
        harness.source.plugIn(Desk.ilitek())
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .held)
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.status, .notSetUp)
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .taken, "the source was asked to take it")
        XCTAssertEqual(harness.savedSettings()?.touchscreens[Desk.ilitekID]?.lastSeenName, "ILITEK-TP",
                       "a new record is saved at once")

        harness.model.perform(.pair(Desk.ilitekID, displayID: Desk.hdmi.displayID))
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .driving)

        let frames = try SurveyTakes.ilitek(take: 9)
        harness.send(frames, from: Desk.ilitekHandle)
        XCTAssertEqual(harness.outputs.count(.down), 1)
        XCTAssertEqual(harness.outputs.count(.up), 1)
        let click = try XCTUnwrap(harness.outputs.events(.down).first)
        XCTAssertTrue(Desk.hdmi.frame.contains(click.location), "a click on HDMI, at \(click.location)")

        XCTAssertEqual(harness.savedSettings()?.touchscreens[Desk.ilitekID]?.pairing?.display, DisplayIdentity(Desk.hdmi),
                       "the settings file on disk has the pairing")
    }

    /// Review Focus 1, from the device layer.
    func testUnplugMidDragThroughTheModel() throws {
        // The strip's take rests 1.78 s: with long-press off, a tap. Long-press through the model is
        // covered in M5.
        let harness = try deskHarness(longPress: false)
        let rest = try dragHalfWay(harness)
        let setStatesBefore = harness.log.entries.filter { $0.hasPrefix("source.setState") }.count

        harness.source.unplug(Desk.ilitekHandle)

        XCTAssertEqual(harness.outputs.events.last?.kind, .up, "the button is released")
        XCTAssertTrue(Desk.hdmi.frame.contains(harness.outputs.events.last?.location ?? .zero))
        XCTAssertEqual(harness.outputs.record.arrowHidden, [true, false], "cancelled, not ended: the arrow is back")
        XCTAssertEqual(harness.outputs.record.warps, [], "the pointer is not sent home")
        XCTAssertNil(harness.outputs.arbiter.owner)
        XCTAssertEqual(harness.log.entries.filter { $0.hasPrefix("source.setState") }.count, setStatesBefore,
                       "nothing is asked of a device that has gone")
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.isConnected, false)
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.status, .notConnected)

        // Frames still arriving for it reach nothing.
        let before = harness.outputs.events.count
        harness.send(rest, from: Desk.ilitekHandle)
        XCTAssertEqual(harness.outputs.events.count, before)

        // The pointer is free for the strip.
        harness.send(retimed(try SurveyTakes.strip(take: 9), startingAt: harness.clock + 1), from: Desk.stripHandle)
        XCTAssertEqual(harness.outputs.count(.down), 2)
        let stripDown = try XCTUnwrap(harness.outputs.events(.down).dropFirst().first, "the strip's tap clicks")
        XCTAssertTrue(Desk.strip.frame.contains(stripDown.location))
    }

    /// Review Focus 3.
    func testAccessibilityRevokedMidTouch() throws {
        let harness = try deskHarness()
        let rest = try dragHalfWay(harness)

        harness.conditions.setAccessibility(false)

        XCTAssertEqual(harness.outputs.count(.up), 1, "the button is released")
        let up = try XCTUnwrap(harness.log.first("event up"))
        for handle in [Desk.ilitekHandle, Desk.stripHandle] {
            let released = try XCTUnwrap(harness.log.first("source.setState \(handle) released"), "\(handle) released")
            XCTAssertLessThan(up, released, "the touch is cancelled before the touchscreen is let go")
            XCTAssertEqual(harness.source.state(of: handle), .released)
        }
        XCTAssertEqual(harness.model.snapshot.warnings, [.accessibilityMissing])
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.status, .accessibilityMissing)

        // Nothing is posted afterwards, whatever arrives.
        let before = harness.outputs.events.count
        harness.send(rest, from: Desk.ilitekHandle)
        harness.send(retimed(try SurveyTakes.strip(take: 9), startingAt: harness.clock + 1), from: Desk.stripHandle)
        harness.tick(after: 1)
        XCTAssertEqual(harness.outputs.events.count, before)
        XCTAssertFalse(harness.model.isTicking)
    }

    func testLockAndUnlock() throws {
        let harness = try deskHarness()
        _ = try dragHalfWay(harness)

        harness.conditions.setSessionActive(false)
        XCTAssertEqual(harness.outputs.count(.up), 1, "cancelled")
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .released)
        XCTAssertEqual(harness.source.state(of: Desk.stripHandle), .released)
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .released)

        harness.conditions.setSessionActive(true)
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .taken)
        XCTAssertEqual(harness.source.state(of: Desk.stripHandle), .taken)
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .driving)

        harness.send(retimed(try SurveyTakes.ilitek(take: 9), startingAt: harness.clock + 5), from: Desk.ilitekHandle)
        XCTAssertEqual(harness.outputs.count(.down), 2, "a tap works")
        XCTAssertEqual(harness.outputs.count(.up), 2)
    }

    /// Review Focus 4, mid-touch.
    func testDisplayUnpluggedMidTouch() throws {
        let harness = try deskHarness()
        let rest = try dragHalfWay(harness)
        let lastDrag = try XCTUnwrap(harness.outputs.events(.drag).last)

        harness.displays.set(Desk.displays.filter { $0.displayID != Desk.hdmi.displayID })
        XCTAssertEqual(harness.outputs.events.last?.kind, .up, "cancelled")
        XCTAssertEqual(harness.outputs.events.last?.location, lastDrag.location, "released where it was, on the mapping it had")
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .held)
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.status, .displayNotConnected(name: "HDMI"))
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .taken, "held, not let go")
        XCTAssertNil(harness.log.first("source.setState \(Desk.ilitekHandle) released"))
        XCTAssertEqual(harness.touchscreen(Desk.stripID)?.mode, .driving)

        // The finger carries on while the display is away: nothing.
        let half = rest.count / 2
        let before = harness.outputs.events.count
        harness.send(rest.prefix(half), from: Desk.ilitekHandle)
        XCTAssertEqual(harness.outputs.events.count, before)

        // Back, with a new ID, while the finger is still down: driving again, and that finger is
        // ignored until it lifts.
        let back = with(Desk.hdmi) { $0.displayID = 33 }
        harness.displays.set(Desk.displays.map { $0.displayID == Desk.hdmi.displayID ? back : $0 })
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .driving)
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.pairedDisplayID, 33)
        harness.send(rest.dropFirst(half), from: Desk.ilitekHandle)
        XCTAssertEqual(harness.outputs.events.count, before, "half a touch never starts")

        harness.send(retimed(try SurveyTakes.ilitek(take: 9), startingAt: harness.clock + 1), from: Desk.ilitekHandle)
        XCTAssertEqual(harness.outputs.count(.down), 2, "the next tap clicks")
        let nextDown = try XCTUnwrap(harness.outputs.events(.down).dropFirst().first, "the next tap clicks")
        XCTAssertTrue(Desk.hdmi.frame.contains(nextDown.location))
    }

    func testTurningATouchscreenOff() throws {
        let harness = try deskHarness()
        harness.model.perform(.setTouchscreenOn(Desk.ilitekID, false))
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .held, "off, ignoring touches")
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.status, .off)
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .taken)
        XCTAssertEqual(harness.savedSettings()?.touchscreens[Desk.ilitekID]?.isOn, false)

        harness.model.perform(.setWhenOff(Desk.ilitekID, .leaveToMacOS))
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .released, "off, left to macOS")
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .released)

        harness.model.perform(.setTouchscreenOn(Desk.ilitekID, true))
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .driving)
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .taken)
    }

    func testPipelineIsCancelledBeforeTheDeviceIsReleased() throws {
        let harness = try deskHarness()
        harness.model.perform(.setWhenOff(Desk.ilitekID, .leaveToMacOS))
        _ = try dragHalfWay(harness)

        harness.model.perform(.setTouchscreenOn(Desk.ilitekID, false))

        let up = try XCTUnwrap(harness.log.first("event up"))
        let shown = try XCTUnwrap(harness.log.first("arrow shown"))
        let released = try XCTUnwrap(harness.log.first("source.setState \(Desk.ilitekHandle) released"))
        XCTAssertLessThan(up, released)
        XCTAssertLessThan(shown, released)
        XCTAssertEqual(harness.outputs.record.warps, [])
    }

    func testFramesForHeldAndUnknownTouchscreensPostNothing() throws {
        let harness = try deskHarness()
        harness.model.perform(.unpair(Desk.ilitekID))
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .held)

        harness.send(try SurveyTakes.ilitek(take: 9), from: Desk.ilitekHandle)
        harness.send(try SurveyTakes.ilitek(take: 9), from: DeviceHandle(rawValue: 99))
        harness.tick(after: 1)
        XCTAssertEqual(harness.outputs.events, [])
        XCTAssertEqual(harness.outputs.record.circles, [])
    }

    func testSameTouchscreenOnAnotherPortKeepsItsSettings() throws {
        let harness = try deskHarness()
        harness.source.unplug(Desk.ilitekHandle)
        var moved = Desk.ilitekFacts
        moved.locationID = 0x0120_0000
        harness.source.plugIn(Desk.ilitek(handle: DeviceHandle(rawValue: 7), facts: moved))

        let snapshot = try XCTUnwrap(harness.touchscreen(Desk.ilitekID), "the same record")
        XCTAssertTrue(snapshot.isConnected)
        XCTAssertEqual(snapshot.location, "01200000")
        XCTAssertEqual(snapshot.mode, .driving, "still paired")
        XCTAssertEqual(snapshot.pairedDisplayID, Desk.hdmi.displayID)
        XCTAssertEqual(harness.model.snapshot.touchscreens.count, 2)
    }

    func testTwoIdenticalTouchscreensGetTwoRecords() throws {
        let harness = try makeHarness()
        harness.model.start()
        harness.source.plugIn(Desk.ilitek())
        var twin = Desk.ilitekFacts
        twin.locationID = 0x0115_0000
        harness.source.plugIn(Desk.ilitek(handle: DeviceHandle(rawValue: 8), facts: twin))

        let connected = harness.model.snapshot.touchscreens.filter(\.isConnected)
        XCTAssertEqual(connected.count, 2)
        XCTAssertEqual(Set(connected.map(\.id)).count, 2, "two records")
        XCTAssertEqual(connected.filter { TouchscreenIdentity.isByPort($0.id) }.count, 1, "one under a port ID")
        XCTAssertEqual(connected.first { TouchscreenIdentity.isByPort($0.id) }?.notes, [.macOSIgnoresIt, .rememberedByPort])
        XCTAssertEqual(harness.savedSettings()?.touchscreens.count, 2)
    }

    func testMouseOriginArrivingLaterTurnsGesturesOff() throws {
        let harness = try makeHarness(settings: Desk.settings)
        harness.source.statusWhenTaken[Desk.stripHandle] = Desk.taken(origin: .undetermined, inputMode: .switchedToMultiTouch)
        harness.source.plugIn(Desk.stripScreen())
        harness.model.start()
        XCTAssertEqual(harness.touchscreen(Desk.stripID)?.mode, .driving)
        XCTAssertEqual(harness.touchscreen(Desk.stripID)?.notes, [])

        // While its origin is undetermined, its stored gestures apply: a two-finger tap right-clicks.
        twoFingerTap(harness, at: 100)
        XCTAssertEqual(harness.outputs.count(.rightDown), 1)

        harness.source.change(Desk.stripHandle) { $0.status.touchOrigin = .mouseInterface }
        XCTAssertEqual(harness.touchscreen(Desk.stripID)?.notes, [.oneFingerOnly])
        XCTAssertEqual(harness.touchscreen(Desk.stripID)?.mode, .driving)

        // Now the second finger is refused: the first one's tap clicks.
        twoFingerTap(harness, at: 200)
        XCTAssertEqual(harness.outputs.count(.rightDown), 1)
        XCTAssertEqual(harness.outputs.count(.down), 1)
    }

    func testATakeReportedBackAtOnceIsAppliedInOneGo() throws {
        // Taking the strip reports back, before `setState` returns, that its touches come from its
        // mouse interface.
        let harness = try makeHarness(settings: Desk.settings)
        harness.source.statusWhenTaken[Desk.stripHandle] = Desk.taken(origin: .mouseInterface, inputMode: .switchedToMultiTouch)
        harness.source.plugIn(Desk.ilitek())
        harness.source.plugIn(Desk.stripScreen())
        harness.model.start()

        XCTAssertEqual(harness.source.requests(for: Desk.stripHandle), 1, "each device asked once")
        XCTAssertEqual(harness.source.requests(for: Desk.ilitekHandle), 1)
        XCTAssertEqual(harness.touchscreen(Desk.stripID)?.notes, [.oneFingerOnly])
        XCTAssertEqual(harness.touchscreen(Desk.stripID)?.mode, .driving)

        // Its pipeline is set for one finger: a second finger is refused.
        twoFingerTap(harness, at: 100)
        XCTAssertEqual(harness.outputs.count(.rightDown), 0)
        XCTAssertEqual(harness.outputs.count(.down), 1)
        XCTAssertTrue(harness.outputs.record.circles.contains {
            if case .show(Desk.strip.displayID, _, [1], _) = $0 { return true }
            return false
        }, "the refused finger is drawn hollow")
    }

    private func twoFingerTap(_ harness: ModelHarness, at time: TimeInterval) {
        harness.send([
            glassFrame(time, (0, 0.4, 0.5)),
            glassFrame(time + 0.02, (0, 0.4, 0.5), (1, 0.6, 0.5)),
            glassFrame(time + 0.10, (0, 0.4, 0.5), (1, 0.6, 0.5)),
            glassFrame(time + 0.15),
        ], from: Desk.stripHandle)
        harness.tick(after: 1)
    }

    /// Rule D: sleep releases; waking takes again.
    func testSleepReleasesAndWakingTakesAgain() throws {
        let harness = try deskHarness()
        let rest = try dragHalfWay(harness)
        let takesBefore = harness.log.entries.filter { $0.hasSuffix(" taken") }.count

        harness.conditions.sleep()
        XCTAssertEqual(harness.outputs.count(.up), 1, "the touch is cancelled")
        XCTAssertEqual(harness.outputs.record.warps, [])
        for handle in [Desk.ilitekHandle, Desk.stripHandle] {
            XCTAssertEqual(harness.source.state(of: handle), .released, "\(handle) released")
        }
        let up = try XCTUnwrap(harness.log.first("event up"))
        XCTAssertLessThan(up, try XCTUnwrap(harness.log.first("source.setState \(Desk.ilitekHandle) released")))

        // Before the Mac sleeps, something else changes and frames still come: nothing starts.
        let before = harness.outputs.events.count
        harness.conditions.setTouchUpRunning(true)
        harness.displays.set(Desk.displays.map { $0.displayID == Desk.lg.displayID ? with($0) { $0.name = "LG" } : $0 })
        harness.send(retimed(rest, startingAt: harness.clock + 0.01), from: Desk.ilitekHandle)
        harness.send(retimed(try SurveyTakes.strip(take: 9), startingAt: harness.clock + 0.1), from: Desk.stripHandle)
        XCTAssertEqual(harness.outputs.events.count, before)
        XCTAssertEqual(harness.log.entries.filter { $0.hasSuffix(" taken") }.count, takesBefore, "nothing taken")

        harness.conditions.wake()
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .taken, "taken afresh")
        XCTAssertEqual(harness.source.state(of: Desk.stripHandle), .taken)
        XCTAssertEqual(harness.source.refreshes, 0, "taking again does what refresh did")
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .driving)
        harness.send(retimed(try SurveyTakes.ilitek(take: 9), startingAt: harness.clock + 60), from: Desk.ilitekHandle)
        XCTAssertEqual(harness.outputs.count(.down), 2, "a tap after waking clicks")
    }

    func testStateFileFollowsTheSnapshot() throws {
        let harness = try deskHarness(writesStateFile: true)
        func stateFile() throws -> AppSnapshot {
            try JSONDecoder().decode(AppSnapshot.self, from: Data(contentsOf: harness.stateURL))
        }
        XCTAssertEqual(try stateFile(), harness.model.snapshot)

        harness.model.perform(.pair(Desk.ilitekID, displayID: Desk.display.displayID))
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.pairedDisplayID, Desk.display.displayID)
        XCTAssertEqual(try stateFile(), harness.model.snapshot)
        let text = try String(contentsOf: harness.stateURL, encoding: .utf8)
        XCTAssertTrue(text.contains("\n  \"appVersion\""), "pretty-printed with sorted keys")

        harness.model.shutDown()
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.stateURL.path))
    }

    func testASetAsideSettingsFileWarns() throws {
        let damaged = Data("{ \"isOn\": \"no\"".utf8)
        let harness = try makeHarness(fileBytes: damaged)
        // A touchscreen is connected as Tactile starts: its new record is saved at once.
        harness.source.plugIn(Desk.ilitek())
        harness.model.start()

        XCTAssertEqual(harness.model.snapshot.warnings, [.settingsSetAside])
        XCTAssertTrue(harness.model.snapshot.isOn, "the defaults")
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.status, .notSetUp)
        let broken = harness.folder.appendingPathComponent("settings.json.broken")
        XCTAssertEqual(try Data(contentsOf: broken), damaged, "the damaged file is kept, as it was")
        XCTAssertEqual(harness.savedSettings()?.touchscreens[Desk.ilitekID]?.lastSeenName, "ILITEK-TP")
    }

    func testShutDownReleasesEverything() throws {
        let harness = try deskHarness(writesStateFile: true)
        _ = try dragHalfWay(harness)
        harness.model.perform(.rename(Desk.stripID, to: "Strip"))

        harness.model.shutDown()

        let up = try XCTUnwrap(harness.log.first("event up"))
        for handle in [Desk.ilitekHandle, Desk.stripHandle] {
            let released = try XCTUnwrap(harness.log.first("source.setState \(handle) released"))
            XCTAssertLessThan(up, released, "every touch cancelled, then every touchscreen released")
            XCTAssertEqual(harness.source.state(of: handle), .released)
        }
        let stop = try XCTUnwrap(harness.log.first("source.stop"))
        XCTAssertNil(harness.log.entries.dropFirst(stop + 1).first { $0.hasPrefix("source.setState") },
                     "nothing is asked of a source that has stopped")
        XCTAssertEqual(harness.outputs.record.arrowHidden.last, false)
        XCTAssertEqual(harness.savedSettings()?.touchscreens[Desk.stripID]?.customName, "Strip")
        XCTAssertFalse(harness.model.isTicking)

        // Nothing after.
        let before = harness.outputs.events.count
        harness.send(retimed(try SurveyTakes.ilitek(take: 9), startingAt: harness.clock + 1), from: Desk.ilitekHandle)
        harness.model.perform(.setOn(false))
        XCTAssertEqual(harness.outputs.events.count, before)
    }

    // MARK: - Fix round 1

    /// Finding 1, through the model: the reports made during a stall arrive after the cancel.
    func testAStallDoesNotSplitADragThroughTheModel() throws {
        let harness = try deskHarness()
        let frames = try SurveyTakes.ilitek(take: 11)
        let half = frames.count / 2
        harness.send(frames.prefix(half), from: Desk.ilitekHandle)
        let lastTime = frames[half - 1].time
        harness.clock = lastTime + 1.6
        harness.model.tickPipelines()
        XCTAssertEqual(harness.outputs.count(.up), 1)
        let queued = frames.dropFirst(half).enumerated().map { index, frame in
            ContactFrame(time: lastTime + 0.01 * Double(index + 1), contacts: frame.contacts)
        }
        for frame in queued { harness.source.send(frame, from: Desk.ilitekHandle) }
        harness.clock = (queued.last?.time ?? lastTime) + 2
        harness.model.tickPipelines()
        XCTAssertEqual(harness.outputs.count(.down), 1)
        XCTAssertEqual(harness.outputs.count(.up), 1)
    }

    /// Finding 3, through the model: while displays reconfigure, the display source says there are
    /// none.
    func testDisplaysReconfiguringCancelAndHold() throws {
        let harness = try deskHarness()
        let rest = try dragHalfWay(harness)
        let lastDrag = try XCTUnwrap(harness.outputs.events(.drag).last)
        harness.displays.set([])
        XCTAssertEqual(harness.outputs.events.last?.kind, .up)
        XCTAssertEqual(harness.outputs.events.last?.location, lastDrag.location, "released on the mapping it had")
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .held)
        XCTAssertEqual(harness.touchscreen(Desk.stripID)?.mode, .held)

        harness.displays.set(Desk.displays)
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .driving)
        let before = harness.outputs.events.count
        harness.send(rest, from: Desk.ilitekHandle)
        XCTAssertEqual(harness.outputs.events.count, before, "the rest of that touch is ignored")
    }

    /// Finding 4.
    func testTouchscreensWithoutALocationKeepTheirOwnSettings() throws {
        let harness = try makeHarness()
        harness.model.start()
        let a = TouchscreenFacts(vendorID: 0x1111, productID: 0x0001, serial: "A", locationID: 0, name: "Panel A")
        let b = TouchscreenFacts(vendorID: 0x2222, productID: 0x0002, serial: "B", locationID: 0, name: "Panel B")
        harness.source.plugIn(Desk.ilitek(handle: DeviceHandle(rawValue: 10), facts: a))
        harness.source.plugIn(Desk.ilitek(handle: DeviceHandle(rawValue: 11), facts: b))

        let idA = TouchscreenIdentity.baseID(vendorID: 0x1111, productID: 0x0001, serial: "A")
        let idB = TouchscreenIdentity.baseID(vendorID: 0x2222, productID: 0x0002, serial: "B")
        XCTAssertEqual(harness.model.snapshot.touchscreens.map(\.id), [idA, idB])
        XCTAssertEqual(harness.model.snapshot.touchscreens.map(\.name), ["Panel A", "Panel B"])
        XCTAssertEqual(harness.savedSettings()?.touchscreens[idA]?.lastSeenName, "Panel A")
        XCTAssertEqual(harness.savedSettings()?.touchscreens[idB]?.lastSeenName, "Panel B")
        harness.model.perform(.rename(idA, to: "Left"))
        XCTAssertEqual(harness.touchscreen(idA)?.name, "Left")
        XCTAssertEqual(harness.touchscreen(idB)?.name, "Panel B", "a command for one changes only that one")

        // A panel with no location, alone of its kind, has its record. When an identical one joins
        // it, neither can be told apart: neither uses a record, and the record is left as it was.
        let twin = TouchscreenFacts(vendorID: 0x3333, productID: 0x0003, serial: "", locationID: 0, name: "Twin")
        let twinRecord = TouchscreenIdentity.baseID(vendorID: 0x3333, productID: 0x0003, serial: "")
        harness.source.plugIn(Desk.ilitek(handle: DeviceHandle(rawValue: 12), facts: twin))
        XCTAssertEqual(harness.touchscreen(twinRecord)?.isConnected, true)
        harness.source.plugIn(Desk.ilitek(handle: DeviceHandle(rawValue: 13), facts: with(twin) { $0.name = "Twin too" }))
        let snapshot = harness.model.snapshot
        XCTAssertEqual(Set(snapshot.touchscreens.map(\.id)).count, snapshot.touchscreens.count, "no ID twice")
        let twins = snapshot.touchscreens.filter { $0.usbID == "3333:0003" && $0.isConnected }
        XCTAssertEqual(twins.map(\.name), ["Twin", "Twin too"], "each with its own name")
        XCTAssertEqual(twins.map(\.mode), [.held, .held])
        XCTAssertFalse(twins.contains { $0.id == twinRecord })
        XCTAssertEqual(harness.touchscreen(twinRecord)?.isConnected, false, "the record is remembered")
        XCTAssertEqual(harness.savedSettings()?.touchscreens[twinRecord]?.lastSeenName, "Twin",
                       "never the other one's name")
        for twin in twins {
            harness.model.perform(.rename(twin.id, to: "X"))
            XCTAssertEqual(harness.model.snapshot.touchscreens.first { $0.id == twin.id }?.name, twin.name, "nothing changes")
        }
        XCTAssertEqual(harness.source.state(of: DeviceHandle(rawValue: 12)), .taken, "held")
    }

    /// Finding 6.
    func testAChangeForATouchscreenThatHasGoneIsDropped() throws {
        let harness = try deskHarness()
        harness.source.unplug(Desk.stripHandle)
        let requests = harness.source.requests(for: Desk.stripHandle)
        harness.model.touchscreenChanged(Desk.stripScreen(status: Desk.taken(origin: .mouseInterface)))
        XCTAssertEqual(harness.touchscreen(Desk.stripID)?.isConnected, false)
        XCTAssertEqual(harness.source.requests(for: Desk.stripHandle), requests)
    }

    /// Finding 7.
    func testShutDownFromInsideARoundCancelsBeforeItReleases() throws {
        let harness = try deskHarness()
        _ = try dragHalfWay(harness)
        final class ShutsDownOnChange: TouchscreenSourceDelegate {
            weak var model: TactileModel?
            func touchscreenConnected(_ touchscreen: ConnectedTouchscreen) {}
            func touchscreenChanged(_ touchscreen: ConnectedTouchscreen) { model?.shutDown() }
            func touchscreenDisconnected(_ handle: DeviceHandle) { model?.touchscreenDisconnected(handle) }
            func touchscreen(_ handle: DeviceHandle, produced frame: ContactFrame) {}
        }
        harness.model.perform(.setWhenOff(Desk.stripID, .leaveToMacOS))
        let delegate = ShutsDownOnChange()
        delegate.model = harness.model
        harness.source.delegate = delegate
        harness.model.perform(.setTouchscreenOn(Desk.stripID, false))

        let up = try XCTUnwrap(harness.log.first("event up"))
        let stop = try XCTUnwrap(harness.log.first("source.stop"))
        XCTAssertLessThan(up, stop, "the touch is cancelled before anything is let go")
        XCTAssertNil(harness.log.entries.dropFirst(stop + 1).first { $0.hasPrefix("source.setState") })
        XCTAssertEqual(harness.outputs.count(.up), 1)
        XCTAssertEqual(harness.outputs.record.arrowHidden.last, false)
    }

    /// Finding 9.
    func testQuittingAfterANormalEndShowsTheArrow() throws {
        let harness = try deskHarness()
        harness.send(try SurveyTakes.ilitek(take: 9), from: Desk.ilitekHandle)
        harness.tick(after: 0.5)
        XCTAssertEqual(harness.outputs.record.arrowHidden, [true], "after a normal end the arrow waits for the mouse")
        harness.model.shutDown()
        XCTAssertEqual(harness.outputs.record.arrowHidden, [true, false])
        XCTAssertEqual(harness.outputs.record.warps, [Desk.pointerHome])
    }

    func testACancelDuringTheDoubleTapWait() throws {
        let harness = try deskHarness()
        harness.send(try SurveyTakes.ilitek(take: 9), from: Desk.ilitekHandle)
        XCTAssertTrue(harness.model.isTicking, "waiting out the double-tap window")
        harness.source.unplug(Desk.ilitekHandle)
        XCTAssertEqual(harness.outputs.events.map(\.kind), [.move, .down, .up], "nothing more is posted")
        XCTAssertEqual(harness.outputs.record.arrowHidden, [true, false])
        XCTAssertEqual(harness.outputs.record.warps, [])
        XCTAssertNil(harness.outputs.arbiter.owner)
        XCTAssertFalse(harness.model.isTicking)
    }

    func testACancelMidPinch() throws {
        let harness = try deskHarness()
        var pinching = 0
        for frame in try SurveyTakes.ilitek(take: 15) {
            harness.send([frame], from: Desk.ilitekHandle)
            if harness.outputs.events(.gesture).contains(where: { $0.gesturePhase == 1 }) { pinching += 1 }
            if pinching == 5 { break }
        }
        XCTAssertEqual(pinching, 5, "the pinch has begun")
        harness.conditions.setAccessibility(false)
        let pinches = harness.outputs.events(.gesture)
        XCTAssertEqual(pinches.filter { $0.gesturePhase == 1 }.count, 1)
        XCTAssertEqual(pinches.filter { $0.gesturePhase == 4 }.count, 1, "the pinch is ended")
        XCTAssertEqual(harness.outputs.record.arrowHidden.last, false)
    }

    func testAMirroredPairingDrawsOnTheMaster() throws {
        let harness = try makeHarness(settings: Desk.settings)
        let mirror = with(Desk.hdmi) { $0.mirrors = Desk.lg.displayID; $0.frame = Desk.lg.frame }
        harness.displays.set(Desk.displays.map { $0.displayID == Desk.hdmi.displayID ? mirror : $0 })
        harness.source.plugIn(Desk.ilitek())
        harness.model.start()
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .driving)
        harness.send(try SurveyTakes.ilitek(take: 9), from: Desk.ilitekHandle)
        let click = try XCTUnwrap(harness.outputs.events(.down).first)
        XCTAssertTrue(Desk.lg.frame.contains(click.location), "in the master's picture")
        let circleDisplays = Set(harness.outputs.record.circles.compactMap { call -> UInt32? in
            if case .show(let display, _, _, _) = call { return display }
            return nil
        })
        XCTAssertEqual(circleDisplays, [Desk.lg.displayID])
    }

    /// Rule B: the mouse interface goes while its finger is down.
    func testWhenTheMouseInterfaceGoesTheTouchIsCancelled() throws {
        let harness = try deskHarness()
        harness.model.perform(.setOneFinger(Desk.stripID, .automatic))  // a finger that moves at once drags
        harness.send([glassFrame(100.00, (0, 0.3, 0.5)), glassFrame(100.05, (0, 0.4, 0.5))], from: Desk.stripHandle)
        XCTAssertEqual(harness.outputs.count(.down), 1)
        harness.source.change(Desk.stripHandle) { $0.hasMouseInterface = false }
        XCTAssertEqual(harness.outputs.count(.up), 1, "no lift will come: cancelled at once")
        XCTAssertEqual(harness.outputs.record.arrowHidden, [true, false], "the keeper was told cancelled")
        XCTAssertNil(harness.outputs.arbiter.owner)
    }

    /// Rule B: the touches move from the mouse interface to the touch interface mid-touch.
    func testAChangeOfOriginMidTouchCancelsIt() throws {
        // With a mouse interface of its own, and without one: a panel that sends pointer reports
        // on its touchscreen interface, as every panel at location 0 does.
        for hasMouseInterface in [true, false] {
            let label = hasMouseInterface ? "with a mouse interface" : "pointer reports on its touch interface"
            let harness = try makeHarness(settings: Desk.settings)
            harness.source.statusWhenTaken[Desk.stripHandle] = Desk.taken(origin: .mouseInterface, inputMode: .switchedToMultiTouch)
            harness.source.plugIn(with(Desk.stripScreen()) { $0.hasMouseInterface = hasMouseInterface })
            harness.model.start()
            harness.model.perform(.setOneFinger(Desk.stripID, .automatic))  // a finger that moves at once drags
            harness.send([glassFrame(100.00, (0, 0.3, 0.5)), glassFrame(100.05, (0, 0.4, 0.5))], from: Desk.stripHandle)
            XCTAssertEqual(harness.outputs.count(.down), 1, label)
            harness.clock = 100.06
            harness.source.change(Desk.stripHandle) { $0.status.touchOrigin = .touchInterface }
            XCTAssertEqual(harness.outputs.count(.up), 1, "cancelled, \(label)")
            XCTAssertEqual(harness.outputs.record.arrowHidden, [true, false], label)

            // The reader ends the mouse finger with an empty frame, then the finger arrives from the
            // touch interface: the same touch, ignored until it lifts. Never a tap.
            harness.send([glassFrame(100.06), glassFrame(100.06, (3, 0.4, 0.5)), glassFrame(100.07, (3, 0.41, 0.5)),
                          glassFrame(100.15)], from: Desk.stripHandle)
            harness.tick(after: 1)
            XCTAssertEqual(harness.outputs.events.map(\.kind), [.move, .down, .drag, .up], "no second press, \(label)")

            harness.send([glassFrame(102.0, (0, 0.5, 0.5)), glassFrame(102.1)], from: Desk.stripHandle)
            XCTAssertEqual(harness.outputs.count(.down), 2, "the next touch works, \(label)")
        }
    }

    /// Rule B: the mouse interface goes mid-touch, then the touch interface reports the same finger.
    func testTheMouseInterfaceGoesThenTheTouchInterfaceReportsTheSameFinger() throws {
        let harness = try deskHarness()
        harness.model.perform(.setOneFinger(Desk.stripID, .automatic))  // a finger that moves at once drags
        harness.send([glassFrame(100.00, (0, 0.3, 0.5)), glassFrame(100.05, (0, 0.4, 0.5))], from: Desk.stripHandle)
        harness.clock = 100.06
        harness.source.change(Desk.stripHandle) { $0.hasMouseInterface = false }
        XCTAssertEqual(harness.outputs.count(.up), 1)
        harness.clock = 100.30
        harness.source.change(Desk.stripHandle) { $0.status.touchOrigin = .touchInterface }
        harness.send([glassFrame(100.30), glassFrame(100.30, (3, 0.4, 0.5)), glassFrame(100.38)], from: Desk.stripHandle)
        harness.tick(after: 1)
        XCTAssertEqual(harness.outputs.count(.down), 1, "the same touch, not a new one")
        XCTAssertEqual(harness.outputs.count(.up), 1)

        harness.send([glassFrame(102.0, (0, 0.5, 0.5)), glassFrame(102.1)], from: Desk.stripHandle)
        XCTAssertEqual(harness.outputs.count(.down), 2, "the next touch works")
    }

    /// Rule B, the other way: the mouse interface goes and the finger lifts; a touch from the touch
    /// interface well after is a new touch.
    func testAMuchLaterTouchFromTheTouchInterfaceIsANewTouch() throws {
        let harness = try deskHarness()
        harness.model.perform(.setOneFinger(Desk.stripID, .automatic))  // a finger that moves at once drags
        harness.send([glassFrame(100.00, (0, 0.3, 0.5)), glassFrame(100.05, (0, 0.4, 0.5))], from: Desk.stripHandle)
        harness.clock = 100.06
        harness.source.change(Desk.stripHandle) { $0.hasMouseInterface = false }
        harness.clock = 105
        harness.source.change(Desk.stripHandle) { $0.status.touchOrigin = .touchInterface }
        harness.send([glassFrame(105), glassFrame(105, (3, 0.4, 0.5)), glassFrame(105.1)], from: Desk.stripHandle)
        XCTAssertEqual(harness.outputs.count(.down), 2)
    }

    /// Rule C.
    func testAMouseModeTouchscreenMacOSStillSeesPostsNothing() throws {
        let harness = try makeHarness(settings: Desk.settings)
        harness.source.statusWhenTaken[Desk.stripHandle] = Desk.taken(
            origin: .mouseInterface, inputMode: .switchedToMultiTouch, exclusive: .failed)
        harness.source.plugIn(Desk.stripScreen())
        harness.model.start()
        XCTAssertEqual(harness.touchscreen(Desk.stripID)?.mode, .held)
        XCTAssertEqual(harness.touchscreen(Desk.stripID)?.notes, [.oneFingerOnly, .macOSMayAlsoRespond])
        harness.send(try SurveyTakes.strip(take: 9), from: Desk.stripHandle)
        harness.tick(after: 1)
        XCTAssertEqual(harness.outputs.events, [])
    }

    /// Rule C and set-up: a mouse-mode touchscreen macOS still sees stays paired with its connected
    /// display, and no set-up of it begins, whatever the purpose: calibration and test as well as a
    /// full set-up.
    func testAMouseModeTouchscreenMacOSStillSeesIsNeverSetUp() throws {
        let harness = try makeHarness(settings: Desk.settings)
        harness.source.statusWhenTaken[Desk.stripHandle] = Desk.taken(
            origin: .mouseInterface, inputMode: .switchedToMultiTouch, exclusive: .failed)
        harness.source.plugIn(Desk.stripScreen())
        harness.model.start()
        let strip = try XCTUnwrap(harness.touchscreen(Desk.stripID))
        XCTAssertEqual(strip.notes, [.oneFingerOnly, .macOSMayAlsoRespond])
        XCTAssertEqual(strip.pairedDisplayID, Desk.strip.displayID, "paired, its display connected")
        XCTAssertFalse(strip.canBeSetUp)
        for purpose in [SetUpPurpose.calibrate, .test, .full] {
            harness.model.perform(.beginSetUp(Desk.stripID, purpose))
            XCTAssertNil(harness.model.snapshot.setUp, "\(purpose): refused")
            XCTAssertEqual(harness.touchscreen(Desk.stripID)?.mode, .held, "\(purpose)")
        }
        // The interface reads this snapshot and says why on all three buttons.
        let snapshot = harness.model.snapshot
        XCTAssertEqual(SetUpAvailability.full(strip, in: snapshot), .unavailable(.macOSAlsoHandlesIt))
        XCTAssertEqual(SetUpAvailability.onItsDisplay(strip, in: snapshot), .unavailable(.macOSAlsoHandlesIt))
    }

    /// Rule E: the clock runs only while a pipeline needs it.
    func testTheClockRunsOnlyWhileNeeded() throws {
        let harness = try deskHarness()
        XCTAssertEqual(harness.ticker.starts, 0)
        harness.send(try SurveyTakes.ilitek(take: 9), from: Desk.ilitekHandle)
        XCTAssertEqual(harness.ticker.starts, 1)
        XCTAssertTrue(harness.ticker.isRunning)
        harness.tick(after: 0.5)
        XCTAssertEqual(harness.ticker.stops, 1)
        XCTAssertFalse(harness.ticker.isRunning)
    }

    // MARK: - The settings store

    func testNothingIsSavedBeforeTheSettingsAreLoaded() throws {
        let damaged = Data("not json".utf8)
        let harness = try makeHarness(fileBytes: damaged)
        // A device layer that announced a touchscreen before `start`.
        harness.model.touchscreenConnected(Desk.ilitek())
        harness.model.perform(.setOn(false))
        XCTAssertEqual(try Data(contentsOf: harness.settingsURL), damaged, "not written over")
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.settingsURL.path + ".broken"))

        harness.model.start()
        XCTAssertEqual(try Data(contentsOf: harness.settingsURL.appendingPathExtension("broken")), damaged)
        XCTAssertNotNil(harness.savedSettings()?.touchscreens[Desk.ilitekID])
    }

    func testAFileThatCannotBeSetAsideIsNeverWrittenOver() throws {
        let damaged = Data("{ damaged".utf8)
        let harness = try makeHarness(fileBytes: damaged)
        // The folder can't be written: the file can't be renamed.
        XCTAssertEqual(chmod(harness.folder.path, 0o555), 0)

        harness.source.plugIn(Desk.ilitek())
        harness.model.start()
        XCTAssertEqual(harness.model.snapshot.warnings, [.settingsSetAside])
        harness.model.perform(.rename(Desk.ilitekID, to: "Top"))
        harness.model.perform(.setOn(false))
        XCTAssertEqual(try Data(contentsOf: harness.settingsURL), damaged, "never written over")
        XCTAssertEqual(harness.model.loggedSaveFailures, 1, "a failure for the same reason is logged once")
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.name, "Top", "the change still applies")
        XCTAssertFalse(harness.model.snapshot.isOn)

        // The folder can be written again: the damaged file is set aside, then the settings saved.
        XCTAssertEqual(chmod(harness.folder.path, 0o755), 0)
        harness.model.perform(.setOn(true))
        XCTAssertEqual(try Data(contentsOf: harness.settingsURL.appendingPathExtension("broken")), damaged)
        XCTAssertEqual(harness.savedSettings()?.touchscreens[Desk.ilitekID]?.customName, "Top")
        XCTAssertEqual(harness.model.snapshot.warnings, [.settingsSetAside], "the warning stays up")
    }

    // MARK: - More

    func testTheDisplayMovingMidTouchCancelsIt() throws {
        let harness = try deskHarness()
        let rest = try dragHalfWay(harness)
        // "HDMI" is turned upside down in System Settings while the finger is down.
        harness.displays.set(Desk.displays.map { $0.displayID == Desk.hdmi.displayID ? with($0) { $0.rotation = 180 } : $0 })
        XCTAssertEqual(harness.outputs.events.last?.kind, .up, "cancelled")
        XCTAssertEqual(harness.outputs.record.arrowHidden, [true, false])
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .driving)

        let before = harness.outputs.events.count
        harness.send(rest, from: Desk.ilitekHandle)
        XCTAssertEqual(harness.outputs.events.count, before, "the rest of that touch is ignored")
        harness.send(retimed(try SurveyTakes.ilitek(take: 9), startingAt: harness.clock + 1), from: Desk.ilitekHandle)
        XCTAssertEqual(harness.outputs.count(.down), 2)
    }

    func testALostLiftThroughTheModel() throws {
        let harness = try deskHarness()
        _ = try dragHalfWay(harness)
        XCTAssertTrue(harness.model.isTicking)
        harness.tick(after: 1.6)
        XCTAssertEqual(harness.outputs.events.last?.kind, .up, "the silent touch is cancelled")
        XCTAssertEqual(harness.outputs.record.arrowHidden, [true, false])
        XCTAssertFalse(harness.model.isTicking)

        // Its display goes and comes back: the touchscreen drives afresh, and the finger the lost
        // lift left behind is not waited for.
        harness.displays.set(Desk.displays.filter { $0.displayID != Desk.hdmi.displayID })
        harness.displays.set(Desk.displays)
        harness.send(retimed(try SurveyTakes.ilitek(take: 9), startingAt: harness.clock + 1), from: Desk.ilitekHandle)
        XCTAssertEqual(harness.outputs.count(.down), 2, "the next tap clicks")
    }

    func testTicksRunOnlyWhileNeeded() throws {
        let harness = try deskHarness()
        XCTAssertFalse(harness.model.isTicking)
        harness.send(try SurveyTakes.ilitek(take: 9), from: Desk.ilitekHandle)
        XCTAssertTrue(harness.model.isTicking, "waiting out the double-tap window")
        harness.tick(after: 0.5)
        XCTAssertFalse(harness.model.isTicking)
        XCTAssertEqual(harness.outputs.record.warps, [Desk.pointerHome], "the session ended")
    }

    func testATakeOverBetweenTouchscreens() throws {
        // The strip's take rests 1.78 s: with long-press off, a tap. Long-press through the model is
        // covered in M5.
        let harness = try deskHarness(longPress: false)
        harness.send(try SurveyTakes.ilitek(take: 9), from: Desk.ilitekHandle)
        harness.send(retimed(try SurveyTakes.strip(take: 9), startingAt: harness.clock + 0.1), from: Desk.stripHandle)
        XCTAssertEqual(harness.outputs.count(.down), 2)
        harness.tick(after: 0.5)
        XCTAssertEqual(harness.outputs.record.arrowHidden, [true, true])
        XCTAssertEqual(harness.outputs.record.warps, [Desk.pointerHome])
    }

    func testANewNameFollowsTheDevice() throws {
        let harness = try deskHarness()
        harness.source.unplug(Desk.ilitekHandle)
        harness.source.plugIn(Desk.ilitek(handle: DeviceHandle(rawValue: 5),
                                          facts: with(Desk.ilitekFacts) { $0.name = "ILITEK Multi-Touch" }))
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.name, "ILITEK Multi-Touch")
        XCTAssertEqual(harness.savedSettings()?.touchscreens[Desk.ilitekID]?.lastSeenName, "ILITEK Multi-Touch")
    }

    func testAskingForAccessibilityChangesNoSetting() throws {
        let harness = try deskHarness()
        let before = try Data(contentsOf: harness.settingsURL)
        harness.model.perform(.askForAccessibility)
        XCTAssertEqual(harness.conditions.accessibilityRequests, 1)
        XCTAssertEqual(try Data(contentsOf: harness.settingsURL), before)
    }

    func testWarningsFollowTheConditions() throws {
        let harness = try deskHarness()
        harness.conditions.setTouchUpRunning(true)
        XCTAssertEqual(harness.model.snapshot.warnings, [.touchUpRunning])
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .driving)
    }
}

/// The 2b model tests again, with long-press, rotate and the rejection rules off in the desk's
/// settings: what 0.2.0 did is still what these test.
final class TactileModelTestsWithNewOptionsOff: TactileModelTests {
    override class var newOptionsOff: Bool { true }
}

/// The 2b model tests again, with the gesture tester open on the strip: the ILITEK, the other
/// touchscreen in most of them, drives exactly as before, and so does the strip.
final class TactileModelTestsWithATesterOpen: TactileModelTests {
    override class var testerOn: TouchscreenID? { DeskFixture.stripID }
}

/// The 2b model tests again, with the gesture tester open on the ILITEK, which most of them touch:
/// it drives exactly as before.
final class TactileModelTestsWithATesterOpenOnTheILITEK: TactileModelTests {
    override class var testerOn: TouchscreenID? { DeskFixture.ilitekID }
}
