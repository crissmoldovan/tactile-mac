// Delivery 3, M4: the frame recorder and Copy Diagnostics. Every file goes to the harness's
// temporary folder, which is removed when the test ends.

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
final class DiagnosticsTests: XCTestCase {

    /// The recorded files, by name.
    private func recordings(_ harness: ModelHarness) throws -> [String] {
        guard FileManager.default.fileExists(atPath: harness.framesURL.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: harness.framesURL.path).sorted()
    }

    private func frames(in name: String, _ harness: ModelHarness) throws -> [TouchFrame] {
        try TouchFrame.decodeLines(Data(contentsOf: harness.framesURL.appendingPathComponent(name)))
    }

    /// `frames` moved in time so that the first is at `start`.
    private func retimed(_ frames: [ContactFrame], startingAt start: TimeInterval) -> [ContactFrame] {
        guard let first = frames.first?.time else { return frames }
        return frames.map { ContactFrame(time: $0.time - first + start, contacts: $0.contacts) }
    }

    // MARK: - The frame recorder

    func testTheRecorderWritesDecodableFramesAndStopsWhenSwitchedOff() throws {
        let harness = try deskHarness(self)
        XCTAssertEqual(try recordings(harness), [], "nothing while it is off")

        harness.model.perform(.setRecordsFrames(true))
        XCTAssertTrue(harness.model.snapshot.recordsFrames)
        XCTAssertEqual(harness.savedSettings()?.recordsFrames, true)
        let files = try recordings(harness)
        XCTAssertEqual(files.count, 2, "one for each driving touchscreen: \(files)")
        let ilitekFile = try XCTUnwrap(files.first { $0.hasPrefix("ILITEK-TP-frames-") && $0.hasSuffix(".jsonl") })
        XCTAssertNotNil(files.first { $0.hasPrefix("TouchScreen-frames-") })

        let take = try SurveyTakes.ilitek(take: 9)
        harness.send(take, from: Desk.ilitekHandle)
        harness.tick(after: 1)
        let recorded = try frames(in: ilitekFile, harness)
        XCTAssertEqual(recorded.count, take.count, "every frame the engine was given")
        XCTAssertEqual(recorded.map(\.time), take.map(\.time))
        XCTAssertEqual(recorded.map(\.fingers.count), take.map(\.contacts.count))
        let surface = SurfaceSize.millimetres(display: Desk.hdmi, diagonalInches: 23.8)
        XCTAssertTrue(recorded.allSatisfy { $0.surfaceSize == surface })
        let glass = try XCTUnwrap(take.first?.contacts.first?.position)
        XCTAssertEqual(recorded.first?.fingers.first?.location, Desk.mapping(on: Desk.hdmi).displayPoint(forGlass: glass),
                       "as the engine sees them: points of the display")

        // Switched off: the file stops growing.
        harness.model.perform(.setRecordsFrames(false))
        harness.send(retimed(take, startingAt: harness.clock + 1), from: Desk.ilitekHandle)
        harness.tick(after: 1)
        XCTAssertEqual(try frames(in: ilitekFile, harness).count, take.count)
        XCTAssertEqual(try recordings(harness).count, 2)

        // On again: a new file, and the old one stays as it was.
        harness.model.perform(.setRecordsFrames(true))
        let again = try recordings(harness).filter { !files.contains($0) }
        XCTAssertEqual(again.count, 2, "\(again)")
        let newILITEK = try XCTUnwrap(again.first { $0.hasPrefix("ILITEK-TP-frames-") })
        harness.send(retimed(take, startingAt: harness.clock + 1), from: Desk.ilitekHandle)
        XCTAssertEqual(try frames(in: newILITEK, harness).count, take.count)
        XCTAssertEqual(try frames(in: ilitekFile, harness).count, take.count)

        // Starting to drive again starts a new file.
        harness.source.unplug(Desk.ilitekHandle)
        harness.source.plugIn(Desk.ilitek(handle: DeviceHandle(rawValue: 9)))
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .driving)
        XCTAssertEqual(try recordings(harness).filter { $0.hasPrefix("ILITEK-TP-frames-") }.count, 3)
    }

    func testFramesAreNotRecordedForAHeldTouchscreen() throws {
        let harness = try deskHarness(self)
        harness.model.perform(.unpair(Desk.ilitekID))
        harness.model.perform(.setRecordsFrames(true))
        XCTAssertEqual(try recordings(harness).map { $0.hasPrefix("TouchScreen-") }, [true], "only the strip drives")
    }

    // MARK: - Copy diagnostics

    func testCopyDiagnosticsDescribesTheDesk() throws {
        let harness = try deskHarness(self)
        let before = try Data(contentsOf: harness.settingsURL)
        harness.model.perform(.copyDiagnostics)
        XCTAssertEqual(harness.pasteboard.count, 1)
        let text = try XCTUnwrap(harness.pasteboard.first)

        XCTAssertTrue(text.hasPrefix("Tactile 0.2.0\nmacOS Version 26.1 (Build 25B78)\n"), text)
        XCTAssertTrue(text.contains("Warnings: none"))
        XCTAssertTrue(text.contains("Swipes follow the fingers off (this Mac can follow them) · launch at login off"), text)
        for (usb, serial, location) in [("222a:0001", "V06.00.00.00", "01141000"), ("27c0:0859", "TEST-SERIAL-0001", "01130000")] {
            XCTAssertTrue(text.contains("USB \(usb) · serial \"\(serial)\" · location \(location)"), "\(usb)\n\(text)")
        }
        for touchscreen in harness.model.snapshot.touchscreens {
            XCTAssertTrue(text.contains("- \(touchscreen.name) [\(touchscreen.id.rawValue)]"), touchscreen.name)
            XCTAssertTrue(text.contains("mode driving"))
        }
        XCTAssertTrue(text.contains("device: taken · input mode noInputModeSetting · touches from touchInterface · exclusive held"))
        XCTAssertTrue(text.contains("touches from mouseInterface"))
        for display in harness.model.snapshot.displays {
            XCTAssertTrue(text.contains("- \(display.name) — \(display.detail): display \(display.id)"), "\(display.name)\n\(text)")
        }
        XCTAssertTrue(text.contains("frame -252, -1440, 2560 × 1440"), "HDMI's frame")
        XCTAssertTrue(text.contains("paired with HDMI (display 3)"))
        XCTAssertTrue(text.contains("display uuid \(Desk.hdmi.uuid)"))

        // Nothing outside Tactile's own state, and nothing changed.
        XCTAssertFalse(text.contains(harness.folder.path))
        XCTAssertFalse(text.contains(NSUserName()))
        XCTAssertEqual(try Data(contentsOf: harness.settingsURL), before)
    }

    func testDiagnosticsSayWhatIsWrong() throws {
        var inputs = Desk.inputs
        inputs.hasAccessibilityAccess = false
        inputs.areMissionControlShortcutsOn = false
        inputs.displays.removeAll { $0.displayID == Desk.hdmi.displayID }
        inputs.settings.touchscreens[Desk.ilitekID]?.pairing?.displayName = "HDMI"
        inputs.settings.touchscreens[Desk.stripID]?.pairing?.alignment = GlassAlignment(
            pictureRect: CGRect(x: 0.01, y: 0.03, width: 0.98, height: 0.96))
        var snapshot = Resolver.resolve(inputs).snapshot
        snapshot.setUp = SetUpSnapshot(touchscreen: Desk.ilitekID, touchscreenName: "ILITEK-TP", purpose: .calibrate,
                                       step: .corners(display: 4, target: CGPoint(x: 0.12, y: 0.12), index: 1,
                                                      problem: .moved))
        let text = Diagnostics.text(snapshot: snapshot, settings: inputs.settings, systemVersion: "15.1")
        XCTAssertTrue(text.contains("Warnings: accessibilityMissing, missionControlShortcutsOff"), text)
        XCTAssertTrue(text.contains("Set-up running: ILITEK-TP [\(Desk.ilitekID.rawValue)], calibrate, corners on display 4, target 2 of 4, moved"))
        XCTAssertTrue(text.contains("paired with HDMI (not connected)"))
        XCTAssertTrue(text.contains("remembered as \"HDMI\""))
        XCTAssertTrue(text.contains("alignment 0.01, 0.03, 0.98 × 0.96"))
        XCTAssertTrue(text.contains("status Accessibility missing"))
        XCTAssertTrue(text.contains("gestures: scroll on, pinch on, two-finger tap on, swipes on, rotate on, long-press on "
                                    + "(one finger only: the multi-finger ones not in force)"), "the strip's gestures")
    }

    /// Delivery 5: set-up mode, the touchscreens offered set-up, and whether the one-finger mode in
    /// force is the default.
    func testDiagnosticsSaySetUpModeAndTheOffers() throws {
        var inputs = Desk.inputs
        inputs.settings.touchscreens[Desk.ilitekID]?.unpair()
        inputs.settings.touchscreens[Desk.stripID]?.oneFinger = .alwaysDrag
        var snapshot = Resolver.resolve(inputs).snapshot
        XCTAssertEqual(snapshot.offerSetUpTo, [Desk.ilitekID])
        var text = Diagnostics.text(snapshot: snapshot, settings: inputs.settings, systemVersion: "15.1")
        XCTAssertTrue(text.contains("Set-up offered for: \(Desk.ilitekID.rawValue)"), text)
        XCTAssertFalse(text.contains("Set-up mode:"))
        XCTAssertTrue(text.contains("  one finger automatic in force · choice none (the default) · "), text)
        XCTAssertTrue(text.contains("  one finger alwaysDrag in force · choice alwaysDrag · "), text)

        snapshot.setUpMode = SetUpModeSnapshot(
            stage: .waitingForTouch(display: Desk.hdmi.displayID), displays: Resolver.setUpScene(inputs).scene.cards,
            touchscreens: [], justSetUp: Desk.stripID, notice: nil)
        text = Diagnostics.text(snapshot: snapshot, settings: inputs.settings, systemVersion: "15.1")
        XCTAssertTrue(text.contains("Set-up mode: waiting for a touch on display 3 · candidates 5, 3, 4, 2 · just set up "
                                    + Desk.stripID.rawValue), text)
    }

    /// The final review's item 8: a line for the gesture tester (open or not; for which
    /// touchscreen; swipes held or let through), and for each touchscreen whether it last gave one
    /// finger, its one-finger choice and the mode in force.
    func testDiagnosticsSayTheTesterAndEachTouchscreensOneFinger() throws {
        let harness = try deskHarness(self)
        func copied() throws -> String {
            harness.model.perform(.copyDiagnostics)
            return try XCTUnwrap(harness.pasteboard.last)
        }
        var text = try copied()
        XCTAssertTrue(text.contains("\nGesture tester: closed\n"), text)
        // On the desk the ILITEK gives every finger and has no choice; the strip, one finger.
        XCTAssertTrue(text.contains("  one finger automatic in force · choice none (the default) · last gave one finger: no\n"), text)
        XCTAssertTrue(text.contains("  one finger alwaysScroll in force · choice none (the default) · last gave one finger: yes\n"), text)
        XCTAssertTrue(text.contains("  after a touch backWhereItWas · circles on\n"), text)

        harness.model.perform(.openGestureTester(Desk.ilitekID))
        text = try copied()
        XCTAssertTrue(text.contains("\nGesture tester: open for ILITEK-TP [\(Desk.ilitekID.rawValue)] on display 3 · swipes held\n"), text)
        harness.model.perform(.setGestureTesterPerformsSwipes(true))
        text = try copied()
        XCTAssertTrue(text.contains("\nGesture tester: open for ILITEK-TP [\(Desk.ilitekID.rawValue)] on display 3 · swipes let through\n"),
                      text)
        harness.model.perform(.openGestureTester(Desk.stripID))
        harness.model.perform(.setOneFinger(Desk.stripID, .alwaysDrag))
        text = try copied()
        XCTAssertTrue(text.contains("\nGesture tester: open for TouchScreen [\(Desk.stripID.rawValue)] on display 4 · swipes held\n"), text)
        XCTAssertTrue(text.contains("  one finger alwaysDrag in force · choice alwaysDrag · last gave one finger: yes\n"), text)
        harness.model.perform(.closeGestureTester)
        XCTAssertTrue(try copied().contains("\nGesture tester: closed\n"))

        // A touchscreen never seen giving anything: not known.
        var inputs = Desk.inputs
        inputs.connected = []
        let snapshot = Resolver.resolve(inputs).snapshot
        text = Diagnostics.text(snapshot: snapshot, settings: inputs.settings, systemVersion: "15.1")
        XCTAssertTrue(text.contains("  one finger automatic in force · choice none (the default) · last gave one finger: not known\n"), text)
    }
}
