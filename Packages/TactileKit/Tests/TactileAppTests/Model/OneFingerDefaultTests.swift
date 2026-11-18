// Delivery 5, Part S (the amendment): the one-finger default depends on the touchscreen. Always
// scroll where only one finger comes through (the strip, in mouse mode), Automatic elsewhere; a
// choice wins on both. Through the model with its fakes: no device, event, window or pointer.

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
final class OneFingerDefaultTests: XCTestCase {
    private let ilitek = Desk.ilitekID
    private let strip = Desk.stripID

    private func behaviour(_ id: TouchscreenID, _ harness: ModelHarness) throws -> BehaviourSnapshot {
        try XCTUnwrap(harness.touchscreen(id)).behaviour
    }

    /// One finger of `handle`'s at glass point `start`, resting `rest` seconds in frames 10 ms apart,
    /// then moving `distance` of the glass to the right over 0.2 s, and lifting.
    private func slide(_ handle: DeviceHandle, _ harness: ModelHarness, from start: CGPoint = CGPoint(x: 0.3, y: 0.5),
                       rest: Double, distance: CGFloat = 0.2) {
        let t = harness.clock + 0.5
        var frames: [ContactFrame] = []
        var k = 0
        while Double(k) * 0.01 < rest {
            frames.append(glassFrame(t + Double(k) * 0.01, (1, start.x, start.y)))
            k += 1
        }
        let moving = t + Double(k) * 0.01
        for i in 1...20 {
            frames.append(glassFrame(moving + Double(i) * 0.01, (1, start.x + distance * CGFloat(i) / 20, start.y)))
        }
        frames.append(glassFrame(moving + 0.25))
        harness.send(frames, from: handle)
        harness.tick(after: 1)
    }

    func testTheDefaultForEachKind() throws {
        let harness = try deskHarness(self)
        // The ILITEK gives every finger: Automatic. The strip gives one, from its mouse interface:
        // Always scroll. Neither has a choice stored.
        XCTAssertEqual(try behaviour(ilitek, harness).oneFinger, .automatic)
        XCTAssertNil(try behaviour(ilitek, harness).oneFingerChoice)
        XCTAssertEqual(try behaviour(strip, harness).oneFinger, .alwaysScroll)
        XCTAssertNil(try behaviour(strip, harness).oneFingerChoice)
        XCTAssertEqual(harness.touchscreen(strip)?.notes.contains(.oneFingerOnly), true)

        let resolved = Resolver.resolve(Desk.inputs)
        XCTAssertEqual(resolved.touchscreens.first { $0.id == ilitek }?.driving?.oneFinger, .automatic)
        XCTAssertEqual(resolved.touchscreens.first { $0.id == strip }?.driving?.oneFinger, .alwaysScroll)

        // Released (off, left to macOS), the strip is still known for what it is: as last seen taken.
        harness.model.perform(.setTouchscreenOn(strip, false))
        harness.model.perform(.setWhenOff(strip, .leaveToMacOS))
        XCTAssertEqual(harness.touchscreen(strip)?.mode, .released)
        XCTAssertEqual(try behaviour(strip, harness).oneFinger, .alwaysScroll)

        // Not connected: what it last gave is remembered.
        harness.source.unplug(Desk.stripHandle)
        XCTAssertEqual(try behaviour(strip, harness).oneFinger, .alwaysScroll)
        XCTAssertNil(try behaviour(strip, harness).oneFingerChoice)
    }

    func testAChoiceWinsOnBoth() throws {
        let harness = try deskHarness(self)
        harness.model.perform(.setOneFinger(strip, .automatic))
        harness.model.perform(.setOneFinger(ilitek, .alwaysScroll))
        XCTAssertEqual(try behaviour(strip, harness).oneFinger, .automatic)
        XCTAssertEqual(try behaviour(strip, harness).oneFingerChoice, .automatic)
        XCTAssertEqual(try behaviour(ilitek, harness).oneFinger, .alwaysScroll)
        XCTAssertEqual(try behaviour(ilitek, harness).oneFingerChoice, .alwaysScroll)
        XCTAssertEqual(harness.savedSettings()?.touchscreens[strip]?.oneFinger, .automatic,
                       "a choice of Automatic is kept as a choice")

        // Through the pipelines: the strip's finger moving at once drags (the fakes' Automatic answers
        // drag); the ILITEK's scrolls.
        slide(Desk.stripHandle, harness, rest: 0)
        XCTAssertEqual(harness.outputs.count(.down), 1)
        XCTAssertEqual(harness.outputs.count(.scroll), 0)
        slide(Desk.ilitekHandle, harness, rest: 0)
        XCTAssertGreaterThan(harness.outputs.count(.scroll), 0)
        XCTAssertEqual(harness.outputs.count(.down), 1)

        // Back to the default: each its own.
        harness.model.perform(.setOneFinger(strip, nil))
        harness.model.perform(.setOneFinger(ilitek, nil))
        XCTAssertEqual(try behaviour(strip, harness).oneFinger, .alwaysScroll)
        XCTAssertEqual(try behaviour(ilitek, harness).oneFinger, .automatic)
        XCTAssertNil(harness.savedSettings()?.touchscreens[strip]?.oneFinger)

        // Relaunched, the choice and the default are read back as they were.
        harness.model.perform(.setOneFinger(strip, .automatic))
        harness.model.shutDown()
        let again = try deskHarness(self, settings: try XCTUnwrap(harness.savedSettings()))
        XCTAssertEqual(try behaviour(strip, again).oneFingerChoice, .automatic)
        XCTAssertEqual(try behaviour(strip, again).oneFinger, .automatic)
        XCTAssertNil(try behaviour(ilitek, again).oneFingerChoice)
    }

    func testA040FilesAutomaticIsTheDefault() throws {
        // The desk as 0.4.0 left it: "automatic" stored for both, as every earlier version wrote it.
        let file = """
            {
              "touchscreens" : {
                "222a:0001:V06.00.00.00" : { "lastSeenName" : "ILITEK-TP", "oneFinger" : "automatic",
                  "pairing" : { "display" : { "model" : 3600, "nativeHeight" : 1440, "nativeWidth" : 2560, "serial" : 1,
                    "uuid" : "4C2D0E10-0000-0000-0A20-0104B53C2278", "vendor" : 19501 } } },
                "27c0:0859:TEST-SERIAL-0001" : { "lastSeenName" : "TouchScreen", "oneFinger" : "automatic",
                  "pairing" : { "display" : { "model" : 291, "nativeHeight" : 720, "nativeWidth" : 1920, "serial" : 0,
                    "uuid" : "2D1E0123-0000-0000-1A21-0103802D1A78", "vendor" : 11550 } } }
              },
              "version" : 1
            }
            """
        let harness = try ModelHarness(fileBytes: Data(file.utf8))
        addTeardownBlock { @MainActor in harness.cleanUp() }
        harness.source.statusWhenTaken[Desk.stripHandle] = Desk.taken(origin: .mouseInterface, inputMode: .switchedToMultiTouch)
        harness.source.plugIn(Desk.ilitek())
        harness.source.plugIn(Desk.stripScreen())
        harness.model.start()
        XCTAssertEqual(harness.model.snapshot.warnings, [], "nothing set aside")
        XCTAssertNil(try behaviour(strip, harness).oneFingerChoice)
        XCTAssertEqual(try behaviour(strip, harness).oneFinger, .alwaysScroll, "the strip scrolls now")
        XCTAssertEqual(try behaviour(ilitek, harness).oneFinger, .automatic)
    }

    /// The amendment's safety: with Always scroll on a one-finger touchscreen, a finger that rests
    /// (the ring) and then moves drags, press, drag and release; one that moves at once scrolls.
    func testOnAOneFingerTouchscreenRestingThenMovingDragsAndMovingAtOnceScrolls() throws {
        let harness = try deskHarness(self)
        XCTAssertEqual(try behaviour(strip, harness).oneFinger, .alwaysScroll)

        slide(Desk.stripHandle, harness, rest: 0)
        XCTAssertGreaterThan(harness.outputs.count(.scroll), 0, "moving at once scrolls")
        XCTAssertEqual(harness.outputs.count(.down), 0)
        XCTAssertEqual(harness.outputs.count(.drag), 0)

        let scrolls = harness.outputs.count(.scroll)
        slide(Desk.stripHandle, harness, rest: 0.7)
        XCTAssertEqual(harness.outputs.count(.down), 1, "resting 0.7 s, then moving: a press")
        XCTAssertGreaterThan(harness.outputs.count(.drag), 5, "a drag")
        XCTAssertEqual(harness.outputs.count(.up), 1, "a release")
        XCTAssertEqual(harness.outputs.count(.scroll), scrolls, "and no scroll")
        let kinds = harness.outputs.events.map(\.kind).filter { [.down, .drag, .up].contains($0) }
        XCTAssertEqual(kinds.first, .down)
        XCTAssertEqual(kinds.last, .up)
        XCTAssertTrue(harness.outputs.record.circles.contains {
            if case .show(_, _, _, let ringed) = $0 { return !ringed.isEmpty }
            return false
        }, "the ring showed before it moved")
    }

    func testCopyAndResetCarryTheChoiceOrTheDefault() throws {
        let harness = try deskHarness(self)
        harness.model.perform(.setOneFinger(strip, .alwaysDrag))
        // From the ILITEK, which has no choice: the strip takes the default, its own.
        harness.model.perform(.copyBehaviour(from: ilitek, to: strip))
        XCTAssertNil(try behaviour(strip, harness).oneFingerChoice)
        XCTAssertEqual(try behaviour(strip, harness).oneFinger, .alwaysScroll)
        // A choice is carried.
        harness.model.perform(.setOneFinger(ilitek, .alwaysDrag))
        harness.model.perform(.copyBehaviour(from: ilitek, to: strip))
        XCTAssertEqual(try behaviour(strip, harness).oneFinger, .alwaysDrag)
        harness.model.perform(.resetBehaviour(strip))
        XCTAssertNil(try behaviour(strip, harness).oneFingerChoice)
        XCTAssertEqual(try behaviour(strip, harness).oneFinger, .alwaysScroll)
    }

    // MARK: - Fix round 1, item 6: what a touchscreen gives, remembered

    /// Whether a touchscreen last gave one finger is stored in its settings when it changes, so that
    /// after a launch the strip scrolls from its first touch, before anything says where its touches
    /// come from; and its first touch, if it says otherwise, changes the default and is stored.
    func testWhatATouchscreenGivesIsRememberedAcrossALaunch() throws {
        let harness = try deskHarness(self)
        XCTAssertEqual(harness.savedSettings()?.touchscreens[strip]?.lastGaveOneFinger, true, "seen giving one finger")
        XCTAssertEqual(harness.savedSettings()?.touchscreens[ilitek]?.lastGaveOneFinger, false)
        let saves = harness.model.saves
        harness.displays.set(Desk.displays)  // a round that sees nothing new
        XCTAssertEqual(harness.model.saves, saves, "written only when it changes")
        harness.model.shutDown()

        // Relaunched: taken, nothing arrived yet from either.
        let again = try ModelHarness(settings: try XCTUnwrap(harness.savedSettings()))
        addTeardownBlock { @MainActor in again.cleanUp() }
        again.source.statusWhenTaken[Desk.stripHandle] = Desk.taken(origin: .undetermined, inputMode: .switchedToMultiTouch)
        again.source.statusWhenTaken[Desk.ilitekHandle] = Desk.taken(origin: .undetermined)
        again.source.plugIn(Desk.ilitek())
        again.source.plugIn(Desk.stripScreen())
        again.model.start()
        XCTAssertEqual(again.touchscreen(strip)?.mode, .driving)
        XCTAssertEqual(try behaviour(strip, again).oneFinger, .alwaysScroll, "remembered, before any touch")
        XCTAssertEqual(try behaviour(ilitek, again).oneFinger, .automatic)
        slide(Desk.stripHandle, again, rest: 0)
        XCTAssertGreaterThan(again.outputs.count(.scroll), 0, "its first stroke scrolls")
        XCTAssertEqual(again.outputs.count(.down), 0)

        // Its first touch comes from its touch interface: it gives more than one finger after all.
        again.source.change(Desk.stripHandle) { $0.status.touchOrigin = .touchInterface }
        XCTAssertEqual(try behaviour(strip, again).oneFinger, .automatic)
        XCTAssertEqual(again.savedSettings()?.touchscreens[strip]?.lastGaveOneFinger, false, "stored")

        // Without anything remembered, a touchscreen nothing has arrived from yet is Automatic.
        let fresh = try ModelHarness(settings: with(Desk.settings) {
            $0.touchscreens[Desk.stripID]?.lastGaveOneFinger = nil
        })
        addTeardownBlock { @MainActor in fresh.cleanUp() }
        fresh.source.statusWhenTaken[Desk.stripHandle] = Desk.taken(origin: .undetermined, inputMode: .switchedToMultiTouch)
        fresh.source.plugIn(Desk.stripScreen())
        fresh.model.start()
        XCTAssertEqual(try behaviour(strip, fresh).oneFinger, .automatic)
        XCTAssertNil(fresh.savedSettings()?.touchscreens[strip]?.lastGaveOneFinger, "nothing known, nothing written")
    }

    /// The `oneFingerOnly` note, and with it `multiFingerAvailable`, go by the same remembered value
    /// as the default until the touchscreen says where its touches come from, so the pane never
    /// shows the strip's gesture switches as available while its default reads Always scroll.
    func testTheOneFingerNoteUsesTheRememberedValueUntilTheTouchscreenSays() throws {
        let harness = try ModelHarness(settings: with(Desk.settings) { $0.touchscreens[Desk.stripID]?.lastGaveOneFinger = true })
        addTeardownBlock { @MainActor in harness.cleanUp() }
        harness.source.statusWhenTaken[Desk.stripHandle] = Desk.taken(origin: .undetermined, inputMode: .switchedToMultiTouch)
        harness.source.plugIn(Desk.stripScreen())
        harness.model.start()
        // Relaunched, before any touch.
        var snapshot = try XCTUnwrap(harness.touchscreen(strip))
        XCTAssertTrue(snapshot.notes.contains(.oneFingerOnly), "remembered as one finger")
        XCTAssertFalse(snapshot.behaviour.multiFingerAvailable)
        XCTAssertEqual(snapshot.behaviour.oneFinger, .alwaysScroll)

        // Its first touch comes from its touch interface: both cleared, with the default.
        harness.source.change(Desk.stripHandle) { $0.status.touchOrigin = .touchInterface }
        snapshot = try XCTUnwrap(harness.touchscreen(strip))
        XCTAssertFalse(snapshot.notes.contains(.oneFingerOnly))
        XCTAssertTrue(snapshot.behaviour.multiFingerAvailable)
        XCTAssertEqual(snapshot.behaviour.oneFinger, .automatic)

        // Unplugged, the pane goes by what is remembered, as the default does.
        harness.source.change(Desk.stripHandle) { $0.status.touchOrigin = .mouseInterface }
        harness.source.unplug(Desk.stripHandle)
        snapshot = try XCTUnwrap(harness.touchscreen(strip))
        XCTAssertTrue(snapshot.notes.contains(.oneFingerOnly))
        XCTAssertFalse(snapshot.behaviour.multiFingerAvailable)
        XCTAssertEqual(snapshot.behaviour.oneFinger, .alwaysScroll)

        // Nothing remembered and nothing said: neither.
        let fresh = Resolver.resolve(with(Desk.inputs) {
            $0.settings.touchscreens[Desk.stripID]?.lastGaveOneFinger = nil
            $0.connected[1].status.touchOrigin = .undetermined
        }).snapshot.touchscreens.first { $0.id == strip }
        XCTAssertEqual(fresh?.notes.contains(.oneFingerOnly), false)
        XCTAssertEqual(fresh?.behaviour.multiFingerAvailable, true)
    }

    func testWhatATouchscreenGivesIsRememberedOnlyFromWhatItSaid() {
        // Remembered from its status while taken, or from what it said last while taken.
        var inputs = Desk.inputs
        var remembered = Resolver.rememberingWhatTouchscreensGive(inputs)
        XCTAssertEqual(remembered.touchscreens[strip]?.lastGaveOneFinger, true)
        XCTAssertEqual(remembered.touchscreens[ilitek]?.lastGaveOneFinger, false)
        inputs.settings = remembered
        XCTAssertEqual(Resolver.rememberingWhatTouchscreensGive(inputs), inputs.settings, "unchanged once remembered")

        // Released, its status says nothing: what it said last while taken still counts.
        var released = inputs
        released.connected[1].status = DeviceStatus()
        released.settings.touchscreens[strip]?.lastGaveOneFinger = nil
        XCTAssertEqual(Resolver.rememberingWhatTouchscreensGive(released).touchscreens[strip]?.lastGaveOneFinger, nil)
        released.lastTakenStatus[Desk.stripHandle] = Desk.taken(origin: .mouseInterface)
        XCTAssertEqual(Resolver.rememberingWhatTouchscreensGive(released).touchscreens[strip]?.lastGaveOneFinger, true)

        // Undetermined or unreadable says nothing: the remembered value stays.
        for origin in [TouchOrigin.undetermined, .unreadable] {
            var silent = inputs
            silent.connected[1].status.touchOrigin = origin
            remembered = Resolver.rememberingWhatTouchscreensGive(silent)
            XCTAssertEqual(remembered.touchscreens[strip]?.lastGaveOneFinger, true, "\(origin)")
        }

        // A touchscreen with no record: nothing stored.
        var unrecorded = Desk.inputs
        unrecorded.records[Desk.stripHandle] = nil
        XCTAssertNil(Resolver.rememberingWhatTouchscreensGive(unrecorded).touchscreens[strip]?.lastGaveOneFinger)
    }
}
