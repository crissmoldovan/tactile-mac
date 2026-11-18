import CoreGraphics
import Foundation
@testable import TactileApp
import TactileDevices
import TactileGestures
import TactileScreens
import XCTest

private typealias Desk = DeskFixture

/// The resolved ILITEK, the strip, and their snapshots, from `inputs`.
private struct Resolved {
    let resolution: Resolution

    init(_ inputs: AppInputs) {
        resolution = Resolver.resolve(inputs)
    }

    var ilitek: ResolvedTouchscreen? { resolution.touchscreens.first { $0.handle == Desk.ilitekHandle } }
    var strip: ResolvedTouchscreen? { resolution.touchscreens.first { $0.handle == Desk.stripHandle } }
    func snapshot(_ id: TouchscreenID) -> TouchscreenSnapshot? { resolution.snapshot.touchscreens.first { $0.id == id } }
    /// The ILITEK's snapshot, under whatever ID it has.
    var ilitekSnapshot: TouchscreenSnapshot? { ilitek.flatMap { snapshot($0.id) } }
}

final class ResolverTests: XCTestCase {

    // MARK: - The mode of each touchscreen

    func testEachRuleOfTheModeTable() throws {
        struct Row {
            let rule: String
            let change: (inout AppInputs) -> Void
            let mode: TouchscreenMode
            let state: DeviceState
            let status: TouchscreenStatus
            /// Rows 1–4a are about Tactile as a whole, and release the strip too.
            let stripDrives: Bool
        }
        func ilitekStatus(_ change: @escaping (inout DeviceStatus) -> Void) -> (inout AppInputs) -> Void {
            { inputs in change(&inputs.connected[0].status) }
        }
        let hdmiLabel = DisplayLabel.label(for: Desk.hdmi, among: Desk.displays, customName: nil, diagonalInches: 23.8)
        let paired = TouchscreenStatus.pairedWith(name: hdmiLabel.name, detail: hdmiLabel.detail)
        let rows: [Row] = [
            Row(rule: "1", change: { $0.isQuitting = true }, mode: .released, state: .released, status: paired,
                stripDrives: false),
            Row(rule: "2", change: { $0.settings.isOn = false }, mode: .released, state: .released, status: .tactileOff,
                stripDrives: false),
            Row(rule: "3", change: { $0.hasAccessibilityAccess = false }, mode: .released, state: .released,
                status: .accessibilityMissing, stripDrives: false),
            Row(rule: "4", change: { $0.isSessionActive = false }, mode: .released, state: .released, status: paired,
                stripDrives: false),
            Row(rule: "4a", change: { $0.isAsleep = true }, mode: .released, state: .released, status: paired,
                stripDrives: false),
            Row(rule: "4b", change: { $0.supportChecks = [UUID(): Desk.ilitekID] }, mode: .released, state: .released, status: paired,
                stripDrives: true),
            Row(rule: "4c", change: { $0.records[Desk.ilitekHandle] = nil }, mode: .held, state: .taken,
                status: .notSetUp, stripDrives: true),
            Row(rule: "5", change: {
                $0.settings.touchscreens[Desk.ilitekID]?.isOn = false
                $0.settings.touchscreens[Desk.ilitekID]?.whenOff = .leaveToMacOS
            }, mode: .released, state: .released, status: .off, stripDrives: true),
            Row(rule: "6", change: {
                $0.settings.touchscreens[Desk.ilitekID]?.isOn = false
                $0.settings.touchscreens[Desk.ilitekID]?.whenOff = .ignoreTouches
            }, mode: .held, state: .taken, status: .off, stripDrives: true),
            Row(rule: "7", change: { $0.settings.touchscreens[Desk.ilitekID]?.unpair() }, mode: .held, state: .taken,
                status: .notSetUp, stripDrives: true),
            Row(rule: "8", change: { $0.displays.removeAll { $0.displayID == Desk.hdmi.displayID } }, mode: .held,
                state: .taken, status: .displayNotConnected(name: "HDMI"), stripDrives: true),
            Row(rule: "8a", change: ilitekStatus { $0.touchOrigin = .unreadable }, mode: .held, state: .taken,
                status: paired, stripDrives: true),
            Row(rule: "8b", change: ilitekStatus { $0.touchOrigin = .mouseInterface; $0.exclusive = .failed },
                mode: .held, state: .taken, status: paired, stripDrives: true),
            Row(rule: "9", change: { _ in }, mode: .driving, state: .taken, status: paired, stripDrives: true),
            Row(rule: "9, touches shared with macOS", change: ilitekStatus { $0.exclusive = .failed }, mode: .driving,
                state: .taken, status: paired, stripDrives: true),
        ]
        for row in rows {
            var inputs = Desk.inputs
            inputs.settings.touchscreens[Desk.ilitekID]?.pairing?.displayName = "HDMI"
            row.change(&inputs)
            let resolved = Resolved(inputs)
            let ilitek = try XCTUnwrap(resolved.ilitek, "rule \(row.rule)")
            XCTAssertEqual(ilitek.mode, row.mode, "rule \(row.rule)")
            XCTAssertEqual(ilitek.deviceState, row.state, "rule \(row.rule)")
            XCTAssertEqual(ilitek.driving != nil, row.mode == .driving, "rule \(row.rule): driving exactly when the mode is")
            XCTAssertEqual(resolved.ilitekSnapshot?.status, row.status, "rule \(row.rule)")
            XCTAssertEqual(resolved.ilitekSnapshot?.mode, row.mode, "rule \(row.rule)")
            XCTAssertEqual(resolved.strip?.mode, row.stripDrives ? .driving : .released, "rule \(row.rule): the strip")
        }
    }

    /// A touchscreen being checked is let go, so the check can take it as Tactile does; it can't run
    /// a set-up meanwhile, and the other touchscreens carry on.
    func testATouchscreenBeingCheckedIsLetGo() throws {
        var inputs = Desk.inputs
        XCTAssertTrue(Resolver.canRunSetUp(Desk.ilitekID, inputs))
        let claim = UUID()
        inputs.supportChecks = [claim: Desk.ilitekID]
        let resolved = Resolved(inputs)
        XCTAssertEqual(resolved.ilitek?.rule, .supportCheck)
        XCTAssertEqual(resolved.ilitek?.deviceState, .released)
        XCTAssertEqual(resolved.strip?.mode, .driving)
        XCTAssertFalse(Resolver.canRunSetUp(Desk.ilitekID, inputs))
        XCTAssertTrue(Resolver.canRunSetUp(Desk.stripID, inputs))
        XCTAssertEqual(Resolver.apply(.beginSupportCheck(Desk.ilitekID, claim: claim), to: inputs), inputs.settings, "no setting changes")
        XCTAssertEqual(Resolver.apply(.endSupportCheck(claim: claim), to: inputs), inputs.settings)

        inputs.setUpMode = SetUpModeSnapshot(stage: .choosing, displays: [], touchscreens: [], justSetUp: nil, notice: nil)
        XCTAssertEqual(Resolved(inputs).ilitek?.deviceState, .released, "set-up mode doesn't take it back")
        XCTAssertEqual(Resolved(inputs).strip?.mode, .settingUp)
    }

    func testFirstRuleWins() {
        var off = Desk.inputs
        off.settings.isOn = false
        off.settings.touchscreens[Desk.ilitekID]?.unpair()
        XCTAssertEqual(Resolved(off).ilitek?.mode, .released)
        XCTAssertEqual(Resolved(off).ilitek?.deviceState, .released)
        XCTAssertEqual(Resolved(off).snapshot(Desk.ilitekID)?.status, .tactileOff)

        var noAccess = Desk.inputs
        noAccess.hasAccessibilityAccess = false
        noAccess.settings.touchscreens[Desk.ilitekID]?.isOn = false
        noAccess.settings.touchscreens[Desk.ilitekID]?.whenOff = .ignoreTouches
        XCTAssertEqual(Resolved(noAccess).ilitek?.mode, .released)
        XCTAssertEqual(Resolved(noAccess).ilitek?.deviceState, .released)
        XCTAssertEqual(Resolved(noAccess).snapshot(Desk.ilitekID)?.status, .accessibilityMissing)
    }

    func testANewTouchscreenIsHeldAndNotSetUp() throws {
        var inputs = Desk.inputs
        inputs.settings.touchscreens[Desk.ilitekID] = nil
        let resolved = Resolved(inputs)
        XCTAssertEqual(resolved.ilitek?.mode, .held)
        XCTAssertEqual(resolved.ilitek?.deviceState, .taken)
        let snapshot = try XCTUnwrap(resolved.snapshot(Desk.ilitekID))
        XCTAssertEqual(snapshot.status, .notSetUp)
        XCTAssertTrue(snapshot.isOn)
        XCTAssertTrue(snapshot.isConnected)
        XCTAssertNil(snapshot.pairedDisplayID)
        XCTAssertNil(snapshot.orientation)
        XCTAssertEqual(snapshot.name, "ILITEK-TP")
        XCTAssertEqual(snapshot.usbID, "222a:0001")
        XCTAssertEqual(snapshot.serial, "V06.00.00.00")
        XCTAssertEqual(snapshot.location, "01141000")
    }

    func testTheDeskDrives() throws {
        let resolved = Resolved(Desk.inputs)
        for (touchscreen, display, diagonal) in [(resolved.ilitek, Desk.hdmi, 23.8), (resolved.strip, Desk.strip, 12.3)] {
            let driving = try XCTUnwrap(touchscreen?.driving, display.name)
            XCTAssertEqual(touchscreen?.mode, .driving)
            let centre = driving.mapping.desktopPoint(forDisplay: driving.mapping.displayPoint(forGlass: CGPoint(x: 0.5, y: 0.5)))
            XCTAssertEqual(centre, CGPoint(x: display.frame.midX, y: display.frame.midY), display.name)
            XCTAssertEqual(driving.displayFrame, display.frame)
            XCTAssertEqual(driving.displayID, display.displayID)
            XCTAssertEqual(SurfaceSize.diagonalInches(of: driving.surfaceSizeMM), diagonal, accuracy: 1e-9, display.name)
            XCTAssertEqual(driving.surfaceSizeMM.width / driving.surfaceSizeMM.height,
                           display.frame.width / display.frame.height, accuracy: 1e-9, "the glass has its display's shape")
        }
        XCTAssertEqual(resolved.snapshot(Desk.ilitekID)?.pairedDisplayID, Desk.hdmi.displayID)
        XCTAssertEqual(resolved.snapshot(Desk.stripID)?.pairedDisplayID, Desk.strip.displayID)
        XCTAssertEqual(resolved.snapshot(Desk.ilitekID)?.reportedDiagonalInches ?? 0,
                       SurfaceSize.diagonalInches(of: Desk.hdmi.sizeMM), accuracy: 1e-9)
        XCTAssertEqual(resolved.snapshot(Desk.ilitekID)?.diagonalInches, 23.8)
        XCTAssertEqual(resolved.resolution.snapshot.warnings, [])
    }

    /// A diagonal the engine ignores (`SurfaceSize.plausibleDiagonals`), such as one written into the
    /// settings file by hand, is never shown either: not in the display's label, not in the status
    /// line, not as the override.
    func testADiagonalTheEngineIgnoresIsNeverShown() throws {
        for inches in [2.9, 200.1, 500, 0, -5] {
            var inputs = Desk.inputs
            inputs.settings.touchscreens[Desk.ilitekID]?.diagonalInches = inches
            let resolved = Resolved(inputs)
            let asReported = DisplayLabel.label(for: Desk.hdmi, among: Desk.displays, customName: nil, diagonalInches: nil)
            let hdmi = try XCTUnwrap(resolved.resolution.snapshot.displays.first { $0.id == Desk.hdmi.displayID })
            XCTAssertEqual(hdmi.detail, asReported.detail, "\(inches)")
            XCTAssertEqual(resolved.snapshot(Desk.ilitekID)?.status,
                           .pairedWith(name: asReported.name, detail: asReported.detail), "\(inches)")
            XCTAssertNil(resolved.snapshot(Desk.ilitekID)?.diagonalInches, "\(inches)")
            let driving = try XCTUnwrap(resolved.ilitek?.driving, "\(inches)")
            XCTAssertEqual(driving.surfaceSizeMM, SurfaceSize.millimetres(display: Desk.hdmi, diagonalInches: nil),
                           "\(inches)")
        }
        // At the range's ends the override is used and shown.
        for inches in [SurfaceSize.plausibleDiagonals.lowerBound, SurfaceSize.plausibleDiagonals.upperBound] {
            var inputs = Desk.inputs
            inputs.settings.touchscreens[Desk.ilitekID]?.diagonalInches = inches
            let resolved = Resolved(inputs)
            let label = DisplayLabel.label(for: Desk.hdmi, among: Desk.displays, customName: nil, diagonalInches: inches)
            XCTAssertEqual(resolved.resolution.snapshot.displays.first { $0.id == Desk.hdmi.displayID }?.detail,
                           label.detail, "\(inches)")
            XCTAssertEqual(resolved.snapshot(Desk.ilitekID)?.diagonalInches, inches)
        }
    }

    func testDisplayUnpluggedThenBack() throws {
        var inputs = Desk.inputs
        inputs.settings.touchscreens[Desk.ilitekID]?.pairing?.displayName = "HDMI"
        inputs.displays.removeAll { $0.displayID == Desk.hdmi.displayID }
        let away = Resolved(inputs)
        XCTAssertEqual(away.ilitek?.mode, .held)
        XCTAssertEqual(away.ilitek?.deviceState, .taken)
        XCTAssertEqual(away.snapshot(Desk.ilitekID)?.status, .displayNotConnected(name: "HDMI"))
        XCTAssertNil(away.snapshot(Desk.ilitekID)?.pairedDisplayID)
        XCTAssertEqual(inputs.settings.touchscreens[Desk.ilitekID]?.pairing?.display, DisplayIdentity(Desk.hdmi),
                       "the pairing is kept")
        XCTAssertEqual(away.strip?.mode, .driving, "the strip is not affected")

        // Back, with a new display ID, as macOS gives one on reconnection.
        inputs.displays.append(with(Desk.hdmi) { $0.displayID = 77 })
        let back = Resolved(inputs)
        XCTAssertEqual(back.ilitek?.mode, .driving)
        XCTAssertEqual(back.ilitek?.driving?.displayID, 77)
        XCTAssertEqual(back.snapshot(Desk.ilitekID)?.pairedDisplayID, 77)

        // In between, no other display was ever its display.
        for display in Desk.displays where display.displayID != Desk.hdmi.displayID {
            XCTAssertNotEqual(away.ilitek?.driving?.displayID, display.displayID)
        }
    }

    func testADisplayNeverSeenIsNamedByItsSize() {
        var inputs = Desk.inputs
        inputs.displays.removeAll { $0.displayID == Desk.hdmi.displayID }
        XCTAssertEqual(Resolved(inputs).snapshot(Desk.ilitekID)?.status, .displayNotConnected(name: "2560 × 1440 display"))

        inputs.settings.displayNames[Desk.hdmi.uuid] = "Top screen"
        XCTAssertEqual(Resolved(inputs).snapshot(Desk.ilitekID)?.status, .displayNotConnected(name: "Top screen"),
                       "a custom name wins")
    }

    func testTwoIdenticalDisplaysAndAStaleUUIDGiveNoMatch() {
        var inputs = Desk.inputs
        // The pairing remembers a UUID no connected display has now, and two connected displays have
        // the pairing's fingerprint.
        inputs.settings.touchscreens[Desk.ilitekID]?.pairing?.display.uuid = "AAAAAAAA-0000-0000-0000-000000000001"
        inputs.displays.removeAll { $0.displayID == Desk.hdmi.displayID }
        inputs.displays.append(with(Desk.hdmi) { $0.displayID = 30; $0.uuid = "BBBBBBBB-0000-0000-0000-000000000030" })
        inputs.displays.append(with(Desk.hdmi) {
            $0.displayID = 31; $0.uuid = "BBBBBBBB-0000-0000-0000-000000000031"; $0.frame.origin.x += 2560
        })
        let resolved = Resolved(inputs)
        XCTAssertEqual(resolved.ilitek?.mode, .held)
        XCTAssertNil(resolved.ilitek?.driving)
        XCTAssertNil(resolved.snapshot(Desk.ilitekID)?.pairedDisplayID)
        guard case .displayNotConnected? = resolved.snapshot(Desk.ilitekID)?.status else {
            return XCTFail("\(String(describing: resolved.snapshot(Desk.ilitekID)?.status))")
        }

        // With only one of them connected, the fingerprint is certain.
        inputs.displays.removeAll { $0.displayID == 31 }
        XCTAssertEqual(Resolved(inputs).ilitek?.driving?.displayID, 30)
    }

    func testARememberedTouchscreenStillClaimsItsDisplay() {
        // Two identical displays: T1 (the ILITEK) is paired with D1, T2 (remembered) with D2.
        let d1 = with(Desk.hdmi) { $0.displayID = 41; $0.uuid = "D1D1D1D1-0000-0000-0000-000000000041" }
        let d2 = with(Desk.hdmi) { $0.displayID = 42; $0.uuid = "D2D2D2D2-0000-0000-0000-000000000042"; $0.frame.origin.x += 2560 }
        let t2 = TouchscreenID(rawValue: "1234:5678:T2")
        var inputs = Desk.inputs
        inputs.displays = Desk.displays.filter { $0.displayID != Desk.hdmi.displayID } + [d1, d2]
        inputs.settings.touchscreens[Desk.ilitekID]?.pairing = Pairing(display: DisplayIdentity(d1))
        inputs.settings.touchscreens[t2] = with(TouchscreenSettings()) { $0.pairing = Pairing(display: DisplayIdentity(d2)) }
        XCTAssertEqual(Resolved(inputs).ilitek?.driving?.displayID, 41)

        // D1 is switched off; T2 is not connected.
        inputs.displays.removeAll { $0.displayID == 41 }
        let resolved = Resolved(inputs)
        XCTAssertEqual(resolved.ilitek?.mode, .held, "never on T2's display")
        XCTAssertNil(resolved.ilitek?.driving)
        XCTAssertNil(resolved.snapshot(Desk.ilitekID)?.pairedDisplayID)
    }

    func testMirroredDisplayMapsIntoTheMasterPicture() throws {
        var inputs = Desk.inputs
        // "HDMI" mirrors the LG: macOS gives it the LG's place in the arrangement.
        let mirror = with(Desk.hdmi) { $0.mirrors = Desk.lg.displayID; $0.frame = Desk.lg.frame }
        inputs.displays = inputs.displays.map { $0.displayID == Desk.hdmi.displayID ? mirror : $0 }
        let driving = try XCTUnwrap(Resolved(inputs).ilitek?.driving)
        XCTAssertEqual(driving.mapping.display, mirror)
        XCTAssertEqual(driving.mapping.content, Desk.lg)
        XCTAssertEqual(driving.surfaceSizeMM, SurfaceSize.millimetres(display: mirror, diagonalInches: 23.8),
                       "the size is the glass's own display's")
        XCTAssertEqual(driving.displayFrame, Desk.lg.frame, "the pointer lands in the master's picture")
        XCTAssertEqual(driving.displayID, Desk.lg.displayID, "circles are drawn where the picture is")
        let centre = driving.mapping.desktopPoint(forDisplay: driving.mapping.displayPoint(forGlass: CGPoint(x: 0.5, y: 0.5)))
        XCTAssertEqual(centre, CGPoint(x: Desk.lg.frame.midX, y: Desk.lg.frame.midY))

        // A display that mirrors one that isn't connected can't be mapped: held, never guessed.
        inputs.displays.removeAll { $0.displayID == Desk.lg.displayID }
        XCTAssertEqual(Resolved(inputs).ilitek?.mode, .held)
    }

    func testMouseOriginForcesOneFinger() throws {
        var inputs = Desk.inputs
        inputs.settings.touchscreens[Desk.stripID]?.gestures = .all
        let resolved = Resolved(inputs)
        XCTAssertEqual(resolved.strip?.driving?.options, Desk.noGestures)
        XCTAssertEqual(resolved.strip?.driving?.options.fingerLimit, 1)
        XCTAssertEqual(resolved.snapshot(Desk.stripID)?.notes, [.oneFingerOnly])

        // The ILITEK, from its touch interface, keeps its gestures. (It has no Input Mode setting:
        // macOS ignores it by itself.)
        XCTAssertEqual(resolved.ilitek?.driving?.options, .all)
        XCTAssertEqual(resolved.snapshot(Desk.ilitekID)?.notes, [.macOSIgnoresIt])
    }

    func testTheNotes() throws {
        var inputs = Desk.inputs
        inputs.connected[0].status.exclusive = .failed
        XCTAssertEqual(Resolved(inputs).snapshot(Desk.ilitekID)?.notes, [.macOSMayAlsoRespond, .macOSIgnoresIt])
        XCTAssertEqual(Resolved(inputs).ilitek?.mode, .driving, "shared with macOS, it still drives")

        inputs.connected[0].status.touchOrigin = .unreadable
        let unreadable = Resolved(inputs)
        XCTAssertEqual(unreadable.snapshot(Desk.ilitekID)?.notes, [.macOSMayAlsoRespond, .touchesCannotBeRead])
        XCTAssertEqual(unreadable.ilitek?.mode, .held)
        XCTAssertEqual(unreadable.ilitek?.deviceState, .taken)

        // A record under a port ID.
        var byPort = Desk.inputs
        let port = TouchscreenIdentity.portID(Desk.ilitekID, locationID: Desk.ilitekFacts.locationID)
        byPort.records[Desk.ilitekHandle] = port
        byPort.settings.touchscreens[port] = byPort.settings.touchscreens[Desk.ilitekID]
        byPort.settings.touchscreens[Desk.ilitekID] = nil
        let snapshot = try XCTUnwrap(Resolver.resolve(byPort).snapshot.touchscreens.first { $0.id == port })
        XCTAssertEqual(snapshot.notes, [.macOSIgnoresIt, .rememberedByPort])
        XCTAssertEqual(snapshot.usbID, "222a:0001")
        XCTAssertEqual(snapshot.serial, "V06.00.00.00")
    }

    func testThePairedDisplaysNameIsAlwaysThere() throws {
        var inputs = Desk.inputs
        inputs.settings.touchscreens[Desk.ilitekID]?.pairing?.displayName = "HDMI"
        XCTAssertEqual(Resolved(inputs).ilitekSnapshot?.pairedDisplayName, "HDMI", "paired and working")

        // The display is away, in every status.
        inputs.displays.removeAll { $0.displayID == Desk.hdmi.displayID }
        let away: [(String, (inout AppInputs) -> Void, TouchscreenStatus)] = [
            ("off", { $0.settings.touchscreens[Desk.ilitekID]?.isOn = false }, .off),
            ("Tactile off", { $0.settings.isOn = false }, .tactileOff),
            ("no Accessibility", { $0.hasAccessibilityAccess = false }, .accessibilityMissing),
            ("display away", { _ in }, .displayNotConnected(name: "HDMI")),
            ("remembered", { $0.connected.removeFirst(); $0.records[Desk.ilitekHandle] = nil }, .notConnected),
        ]
        for (name, change, status) in away {
            let resolved = Resolved(with(inputs, change))
            let snapshot = try XCTUnwrap(resolved.snapshot(Desk.ilitekID), name)
            XCTAssertEqual(snapshot.status, status, name)
            XCTAssertEqual(snapshot.pairedDisplayName, "HDMI", name)
            XCTAssertNil(snapshot.pairedDisplayID, name)
        }

        // A pairing that never remembered its display's name (one from 0.2.0, with the display away
        // since): nothing knows the name but the display's size.
        inputs.settings.touchscreens[Desk.ilitekID]?.pairing?.displayName = ""
        XCTAssertEqual(Resolved(inputs).ilitekSnapshot?.pairedDisplayName, "2560 × 1440 display")
        // A custom name is always known.
        inputs.settings.displayNames[Desk.hdmi.uuid] = "Top screen"
        XCTAssertEqual(Resolved(inputs).ilitekSnapshot?.pairedDisplayName, "Top screen")
        // A remembered touchscreen whose display is connected: the display's name.
        var remembered = Desk.inputs
        remembered.connected.removeFirst()
        remembered.records[Desk.ilitekHandle] = nil
        XCTAssertEqual(Resolved(remembered).snapshot(Desk.ilitekID)?.pairedDisplayName, "HDMI")

        // Unpaired: none.
        inputs.settings.touchscreens[Desk.ilitekID]?.unpair()
        XCTAssertNil(Resolved(inputs).ilitekSnapshot?.pairedDisplayName)
    }

    /// The final review's fix 1: whatever the status line says, a connected, paired touchscreen
    /// whose display is connected names that display, so the Display pop-up never shows a connected
    /// display as "not connected".
    func testThePairedDisplayIsFilledWhateverTheStatus() throws {
        let cases: [(String, (inout AppInputs) -> Void, TouchscreenStatus)] = [
            ("off, ignoring touches", {
                $0.settings.touchscreens[Desk.ilitekID]?.isOn = false
                $0.settings.touchscreens[Desk.ilitekID]?.whenOff = .ignoreTouches
            }, .off),
            ("off, left to macOS", {
                $0.settings.touchscreens[Desk.ilitekID]?.isOn = false
                $0.settings.touchscreens[Desk.ilitekID]?.whenOff = .leaveToMacOS
            }, .off),
            ("Tactile off", { $0.settings.isOn = false }, .tactileOff),
            ("no Accessibility", { $0.hasAccessibilityAccess = false }, .accessibilityMissing),
            ("paired and working", { _ in }, .pairedWith(name: "HDMI", detail: "23.8″ · 2560 × 1440 · above the main display")),
        ]
        for (name, change, status) in cases {
            let snapshot = try XCTUnwrap(Resolved(with(Desk.inputs, change)).ilitekSnapshot, name)
            XCTAssertEqual(snapshot.status, status, "\(name): the status line is unchanged")
            XCTAssertEqual(snapshot.pairedDisplayID, Desk.hdmi.displayID, name)
            XCTAssertEqual(snapshot.pairedDisplayName, "HDMI", name)
            XCTAssertEqual(snapshot.reportedDiagonalInches ?? 0, 27, accuracy: 0.1, name)
            XCTAssertEqual(DisplayPick(snapshot), .display(Desk.hdmi.displayID), name)
        }

        // The display away: not filled, and the pop-up shows it missing.
        var away = Desk.inputs
        away.settings.touchscreens[Desk.ilitekID]?.pairing?.displayName = "HDMI"
        away.displays.removeAll { $0.displayID == Desk.hdmi.displayID }
        for (name, change, _) in cases {
            let snapshot = try XCTUnwrap(Resolved(with(away, change)).ilitekSnapshot, name)
            XCTAssertNil(snapshot.pairedDisplayID, name)
            XCTAssertNil(snapshot.reportedDiagonalInches, name)
            XCTAssertEqual(DisplayPick(snapshot), .missing("HDMI"), name)
        }

        // A remembered touchscreen whose display is connected: not paired with it now.
        var remembered = Desk.inputs
        remembered.connected.removeFirst()
        remembered.records[Desk.ilitekHandle] = nil
        let snapshot = try XCTUnwrap(Resolved(remembered).snapshot(Desk.ilitekID))
        XCTAssertNil(snapshot.pairedDisplayID)
        XCTAssertEqual(snapshot.pairedDisplayName, "HDMI")
    }

    func testAMouseModeTouchscreenMacOSStillSeesIsHeld() {
        var inputs = Desk.inputs
        inputs.connected[1].status.exclusive = .failed
        let resolved = Resolved(inputs)
        XCTAssertEqual(resolved.strip?.mode, .held, "macOS already moves the pointer for it")
        XCTAssertEqual(resolved.strip?.deviceState, .taken)
        XCTAssertNil(resolved.strip?.driving)
        XCTAssertEqual(resolved.snapshot(Desk.stripID)?.notes, [.oneFingerOnly, .macOSMayAlsoRespond])
    }

    func testTouchscreensWithNoRecordAreHeldAndChangeNothing() throws {
        // Two identical panels with no usable USB location: the model gives them no record.
        let twin = with(Desk.ilitekFacts) { $0.locationID = 0 }
        var inputs = Desk.inputs
        inputs.connected = [
            Desk.ilitek(handle: DeviceHandle(rawValue: 20), status: Desk.taken(), facts: twin),
            Desk.ilitek(handle: DeviceHandle(rawValue: 21), status: Desk.taken(), facts: with(twin) { $0.name = "Other" }),
        ]
        inputs.records = [:]
        let resolution = Resolver.resolve(inputs)
        XCTAssertEqual(resolution.touchscreens.map(\.mode), [.held, .held])
        XCTAssertEqual(resolution.touchscreens.map(\.rule), [.noRecord, .noRecord])
        let shown = resolution.snapshot.touchscreens.filter(\.isConnected)
        XCTAssertEqual(shown.map(\.name), ["ILITEK-TP", "Other"], "each with its own name")
        XCTAssertEqual(Set(resolution.snapshot.touchscreens.map(\.id)).count, resolution.snapshot.touchscreens.count,
                       "no ID twice")
        XCTAssertFalse(shown.contains { $0.id == Desk.ilitekID }, "never the stored record's ID")
        XCTAssertEqual(resolution.snapshot.touchscreens.first { $0.id == Desk.ilitekID }?.isConnected, false,
                       "the stored record stays remembered, untouched")

        for snapshot in shown {
            for command in [AppCommand.rename(snapshot.id, to: "X"), .pair(snapshot.id, displayID: Desk.lg.displayID),
                            .setTouchscreenOn(snapshot.id, false), .forget(snapshot.id), .unpair(snapshot.id)] {
                XCTAssertEqual(Resolver.apply(command, to: inputs), inputs.settings, "\(command)")
            }
        }
    }

    func testAStoredKeyThatLooksProvisionalIsNeverARecord() throws {
        // Two identical panels at location 0, and a settings file edited by hand with a key equal to
        // the first one's provisional ID, paired with "HDMI".
        let twin = with(Desk.ilitekFacts) { $0.locationID = 0 }
        var inputs = Desk.inputs
        inputs.connected = [
            Desk.ilitek(handle: DeviceHandle(rawValue: 20), status: Desk.taken(), facts: twin),
            Desk.ilitek(handle: DeviceHandle(rawValue: 21), status: Desk.taken(), facts: twin),
            Desk.stripScreen(status: Desk.taken(origin: .mouseInterface, inputMode: .switchedToMultiTouch)),
        ]
        inputs.records = [Desk.stripHandle: Desk.stripID]
        inputs.settings.touchscreens[Desk.ilitekID] = nil
        let provisional = TouchscreenID(rawValue: "#20:" + Desk.ilitekID.rawValue)
        inputs.settings.touchscreens[provisional] = Desk.paired("Junk", with: Desk.hdmi)
        // And one that names no connected touchscreen.
        let stray = TouchscreenID(rawValue: "#99:1234:5678:Q")
        inputs.settings.touchscreens[stray] = Desk.paired("Stray", with: Desk.lg)

        let snapshot = Resolver.resolve(inputs).snapshot
        XCTAssertFalse(snapshot.touchscreens.contains { $0.id == stray }, "never shown as remembered")
        XCTAssertNil(snapshot.displays.first { $0.id == Desk.lg.displayID }?.pairedTouchscreen)
        XCTAssertEqual(snapshot.touchscreens.filter { $0.id == provisional }.count, 1, "shown once: the connected panel")
        XCTAssertEqual(snapshot.touchscreens.first { $0.id == provisional }?.name, "ILITEK-TP")
        XCTAssertNil(snapshot.displays.first { $0.id == Desk.hdmi.displayID }?.pairedTouchscreen,
                     "the key's pairing claims nothing")

        for command in [AppCommand.pair(provisional, displayID: Desk.strip.displayID), .unpair(provisional),
                        .rename(provisional, to: "X"), .forget(provisional), .setTouchscreenOn(provisional, false),
                        .forget(stray), .unpair(stray)] {
            XCTAssertEqual(Resolver.apply(command, to: inputs), inputs.settings, "\(command)")
        }
        XCTAssertNotNil(inputs.settings.touchscreens[Desk.stripID]?.pairing, "the strip keeps its display")
    }

    func testADiagonalOutsideTheRangeIsIgnored() throws {
        var inputs = Desk.inputs
        inputs.settings.touchscreens[Desk.ilitekID]?.diagonalInches = 500
        let resolved = Resolved(inputs)
        let driving = try XCTUnwrap(resolved.ilitek?.driving)
        XCTAssertEqual(driving.surfaceSizeMM, SurfaceSize.millimetres(display: Desk.hdmi, diagonalInches: nil))
        XCTAssertNil(resolved.snapshot(Desk.ilitekID)?.diagonalInches)
        XCTAssertEqual(resolved.resolution.snapshot.displays.first { $0.id == Desk.hdmi.displayID }?.detail,
                       "27″ · 2560 × 1440 · above the main display", "the label shows what the engine uses")
    }

    func testATouchscreenWithNoNameStillHasOne() throws {
        var inputs = Desk.inputs
        inputs.connected[0].facts.name = ""
        inputs.settings.touchscreens[Desk.ilitekID]?.lastSeenName = ""
        XCTAssertEqual(Resolved(inputs).snapshot(Desk.ilitekID)?.name, "Touchscreen 222a:0001")

        // A remembered one too.
        inputs.connected.removeFirst()
        inputs.records[Desk.ilitekHandle] = nil
        XCTAssertEqual(Resolved(inputs).snapshot(Desk.ilitekID)?.name, "Touchscreen 222a:0001")

        // A custom name of spaces is no name.
        inputs.settings.touchscreens[Desk.ilitekID]?.customName = "   "
        XCTAssertEqual(Resolved(inputs).snapshot(Desk.ilitekID)?.name, "Touchscreen 222a:0001")
    }

    // MARK: - Commands

    func testPairingADisplayInUseMovesIt() throws {
        var inputs = Desk.inputs
        // The ILITEK picks the strip's display: the strip is unpaired in the same change.
        inputs.settings = Resolver.apply(.pair(Desk.ilitekID, displayID: Desk.strip.displayID), to: inputs)
        XCTAssertEqual(inputs.settings.touchscreens[Desk.ilitekID]?.pairing?.display, DisplayIdentity(Desk.strip))
        XCTAssertNil(inputs.settings.touchscreens[Desk.stripID]?.pairing)
        let between = Resolved(inputs)
        XCTAssertEqual(between.ilitek?.driving?.displayID, Desk.strip.displayID)
        XCTAssertEqual(between.strip?.mode, .held)

        // The strip picks the ILITEK's old display: two picks have swapped them.
        inputs.settings = Resolver.apply(.pair(Desk.stripID, displayID: Desk.hdmi.displayID), to: inputs)
        let swapped = Resolved(inputs)
        XCTAssertEqual(swapped.ilitek?.driving?.displayID, Desk.strip.displayID)
        XCTAssertEqual(swapped.strip?.driving?.displayID, Desk.hdmi.displayID)
    }

    func testPairingClearsARememberedTouchscreensClaim() throws {
        // R, remembered and not connected, is paired with "HDMI". The ILITEK is unpaired.
        let remembered = TouchscreenID(rawValue: "1234:5678:R")
        var inputs = Desk.inputs
        inputs.settings.touchscreens[remembered] = Desk.paired("Old panel", with: Desk.hdmi)
        inputs.settings.touchscreens[Desk.ilitekID]?.unpair()
        XCTAssertEqual(Resolved(inputs).snapshot(Desk.ilitekID)?.displayChoices.first { $0.id == Desk.hdmi.displayID }?.inUseBy,
                       "Old panel", "the picker says who has it")

        inputs.settings = Resolver.apply(.pair(Desk.ilitekID, displayID: Desk.hdmi.displayID), to: inputs)
        XCTAssertNil(inputs.settings.touchscreens[remembered]?.pairing, "R is unpaired in the same change")
        XCTAssertNotNil(inputs.settings.touchscreens[remembered], "and still remembered")

        // R connects.
        let facts = TouchscreenFacts(vendorID: 0x1234, productID: 0x5678, serial: "R", locationID: 0x0115_0000, name: "Old panel")
        inputs.connected.append(ConnectedTouchscreen(
            handle: DeviceHandle(rawValue: 9), facts: facts, maxContacts: 5, reportedSizeMM: nil, hasMouseInterface: false,
            reportsPalms: false, status: Desk.taken()))
        inputs.records[DeviceHandle(rawValue: 9)] = remembered
        let resolved = Resolved(inputs)
        XCTAssertEqual(resolved.snapshot(remembered)?.status, .notSetUp)
        XCTAssertEqual(resolved.ilitek?.mode, .driving)
        XCTAssertEqual(resolved.ilitek?.driving?.displayID, Desk.hdmi.displayID)
    }

    func testPairingLeavesAnotherUnitOfTheSameModelAlone() {
        // R is paired with another monitor of HDMI's model: the same fingerprint, another UUID.
        let remembered = TouchscreenID(rawValue: "1234:5678:R")
        var inputs = Desk.inputs
        var twin = DisplayIdentity(Desk.hdmi)
        twin.uuid = "CCCCCCCC-0000-0000-0000-000000000001"
        inputs.settings.touchscreens[remembered] = with(TouchscreenSettings()) { $0.pairing = Pairing(display: twin) }
        inputs.settings.touchscreens[Desk.ilitekID]?.unpair()
        inputs.settings = Resolver.apply(.pair(Desk.ilitekID, displayID: Desk.hdmi.displayID), to: inputs)
        XCTAssertEqual(inputs.settings.touchscreens[remembered]?.pairing?.display, twin)
    }

    func testPairingTheSameDisplayKeepsOrientation() {
        var inputs = Desk.inputs
        let flipped = Orientation(quarterTurns: 2, isFlipped: true)
        inputs.settings.touchscreens[Desk.ilitekID]?.pairing?.orientation = flipped
        let settings = Resolver.apply(.pair(Desk.ilitekID, displayID: Desk.hdmi.displayID), to: inputs)
        XCTAssertEqual(settings.touchscreens[Desk.ilitekID]?.pairing?.orientation, flipped)
        XCTAssertEqual(settings, inputs.settings, "nothing changes")
    }

    func testPairingAnotherStartsAsFitted() {
        var inputs = Desk.inputs
        inputs.settings.touchscreens[Desk.ilitekID]?.pairing?.orientation = Orientation(quarterTurns: 1, isFlipped: true)
        inputs.settings.touchscreens[Desk.ilitekID]?.pairing?.alignment =
            GlassAlignment(pictureRect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8))
        let settings = Resolver.apply(.pair(Desk.ilitekID, displayID: Desk.display.displayID), to: inputs)
        XCTAssertEqual(settings.touchscreens[Desk.ilitekID]?.pairing, Pairing(display: DisplayIdentity(Desk.display)))
    }

    func testRepickingADisplayWhoseUUIDChangedKeepsTheFit() throws {
        var inputs = Desk.inputs
        let flipped = Orientation(quarterTurns: 0, isFlipped: true)
        let fit = GlassAlignment(pictureRect: CGRect(x: 0.02, y: 0.01, width: 0.97, height: 0.98))
        inputs.settings.touchscreens[Desk.ilitekID]?.pairing?.orientation = flipped
        inputs.settings.touchscreens[Desk.ilitekID]?.pairing?.alignment = fit
        // macOS gives "HDMI" a new UUID; the matcher finds it by its fingerprint.
        let renewed = with(Desk.hdmi) { $0.uuid = "DDDDDDDD-0000-0000-0000-000000000003"; $0.displayID = 33 }
        inputs.displays = inputs.displays.map { $0.displayID == Desk.hdmi.displayID ? renewed : $0 }
        XCTAssertEqual(Resolved(inputs).ilitek?.driving?.displayID, 33, "matched by fingerprint")

        let settings = Resolver.apply(.pair(Desk.ilitekID, displayID: 33), to: inputs)
        let pairing = try XCTUnwrap(settings.touchscreens[Desk.ilitekID]?.pairing)
        XCTAssertEqual(pairing.orientation, flipped)
        XCTAssertEqual(pairing.alignment, fit)
        XCTAssertEqual(pairing.display, DisplayIdentity(renewed), "the new UUID is stored")
    }

    func testCommandsThatMustChangeNothing() {
        let inputs = with(Desk.inputs) {
            $0.settings.touchscreens[TouchscreenID(rawValue: "1234:5678:R")] = Desk.paired("Old panel", with: nil)
            $0.settings.touchscreens[Desk.stripID]?.unpair()
        }
        let unknown = TouchscreenID(rawValue: "ffff:ffff:nobody")
        let commands: [(String, AppCommand)] = [
            ("pair with a display that isn't connected", .pair(Desk.ilitekID, displayID: 99)),
            ("pair with the built-in display", .pair(Desk.ilitekID, displayID: Desk.builtIn.displayID)),
            ("forget a connected touchscreen", .forget(Desk.ilitekID)),
            ("orientation of an unpaired touchscreen", .setOrientation(Desk.stripID, Orientation(quarterTurns: 1, isFlipped: false))),
            ("ask for Accessibility", .askForAccessibility),
            ("turn on an unknown touchscreen", .setTouchscreenOn(unknown, false)),
            ("when off, unknown", .setWhenOff(unknown, .leaveToMacOS)),
            ("rename an unknown touchscreen", .rename(unknown, to: "X")),
            ("pair an unknown touchscreen", .pair(unknown, displayID: Desk.hdmi.displayID)),
            ("unpair an unknown touchscreen", .unpair(unknown)),
            ("orientation, unknown", .setOrientation(unknown, .asFitted)),
            ("diagonal, unknown", .setDiagonal(unknown, inches: 20)),
            ("forget an unknown touchscreen", .forget(unknown)),
            ("rename a display with no UUID", .renameDisplay(uuid: "", to: "X")),
            ("rename a display with a blank UUID", .renameDisplay(uuid: "  ", to: "X")),
            ("rename the remembered one to what it is", .rename(TouchscreenID(rawValue: "1234:5678:R"), to: nil)),
        ]
        for (name, command) in commands {
            XCTAssertEqual(Resolver.apply(command, to: inputs), inputs.settings, name)
        }
    }

    func testCommandsThatChangeSettings() {
        let inputs = Desk.inputs
        func apply(_ command: AppCommand) -> TactileSettings { Resolver.apply(command, to: inputs) }
        let ilitek = { (settings: TactileSettings) in settings.touchscreens[Desk.ilitekID] }

        XCTAssertFalse(apply(.setOn(false)).isOn)
        XCTAssertEqual(ilitek(apply(.setTouchscreenOn(Desk.ilitekID, false)))?.isOn, false)
        XCTAssertEqual(ilitek(apply(.setWhenOff(Desk.ilitekID, .leaveToMacOS)))?.whenOff, .leaveToMacOS)
        XCTAssertEqual(ilitek(apply(.rename(Desk.ilitekID, to: "  Top  ")))?.customName, "Top")
        XCTAssertNil(ilitek(apply(.unpair(Desk.ilitekID)))?.pairing)
        XCTAssertEqual(ilitek(apply(.setOrientation(Desk.ilitekID, Orientation(quarterTurns: 3, isFlipped: true))))?
            .pairing?.orientation, Orientation(quarterTurns: 3, isFlipped: true))
        XCTAssertEqual(ilitek(apply(.setDiagonal(Desk.ilitekID, inches: 21.5)))?.diagonalInches, 21.5)
        XCTAssertEqual(apply(.renameDisplay(uuid: Desk.hdmi.uuid, to: " Top ")).displayNames, [Desk.hdmi.uuid: "Top"])
        XCTAssertTrue(apply(.setDebugLogging(true)).debugLogging)

        // Clearing.
        let named = with(inputs) {
            $0.settings.touchscreens[Desk.ilitekID]?.customName = "Top"
            $0.settings.displayNames[Desk.hdmi.uuid] = "Top"
        }
        XCTAssertNil(Resolver.apply(.rename(Desk.ilitekID, to: nil), to: named).touchscreens[Desk.ilitekID]?.customName)
        XCTAssertNil(Resolver.apply(.rename(Desk.ilitekID, to: " "), to: named).touchscreens[Desk.ilitekID]?.customName)
        XCTAssertEqual(Resolver.apply(.renameDisplay(uuid: Desk.hdmi.uuid, to: ""), to: named).displayNames, [:])
        XCTAssertEqual(Resolver.apply(.renameDisplay(uuid: Desk.hdmi.uuid, to: nil), to: named).displayNames, [:])
        for inches in [2.9, 200.1, 0, -5, .nan, .infinity] {
            XCTAssertNil(ilitek(apply(.setDiagonal(Desk.ilitekID, inches: inches)))?.diagonalInches, "\(inches)")
        }
        XCTAssertEqual(ilitek(apply(.setDiagonal(Desk.ilitekID, inches: 3)))?.diagonalInches, 3)
        XCTAssertEqual(ilitek(apply(.setDiagonal(Desk.ilitekID, inches: 200)))?.diagonalInches, 200)
        XCTAssertNil(ilitek(apply(.setDiagonal(Desk.ilitekID, inches: nil)))?.diagonalInches)

        // Forgetting a remembered touchscreen.
        let remembered = TouchscreenID(rawValue: "1234:5678:R")
        let withRemembered = with(inputs) { $0.settings.touchscreens[remembered] = TouchscreenSettings() }
        XCTAssertNil(Resolver.apply(.forget(remembered), to: withRemembered).touchscreens[remembered])
    }

    func testACommandForAConnectedTouchscreenWithoutARecordMakesOne() {
        var inputs = Desk.inputs
        inputs.settings.touchscreens[Desk.ilitekID] = nil
        let settings = Resolver.apply(.rename(Desk.ilitekID, to: "Top"), to: inputs)
        XCTAssertEqual(settings.touchscreens[Desk.ilitekID]?.customName, "Top")
        XCTAssertEqual(settings.touchscreens[Desk.ilitekID]?.lastSeenName, "ILITEK-TP")
    }

    // MARK: - The snapshot

    func testSnapshotOrderAndChoices() throws {
        var inputs = Desk.inputs
        // The strip connected first.
        inputs.connected.reverse()
        // Two remembered touchscreens; Zed is paired with the LG.
        inputs.settings.touchscreens[TouchscreenID(rawValue: "aaaa:0001:z")] = Desk.paired("Zed", with: Desk.lg, diagonal: 31.5)
        inputs.settings.touchscreens[TouchscreenID(rawValue: "aaaa:0001:a")] = Desk.paired("Alpha", with: nil)
        let snapshot = Resolver.resolve(inputs).snapshot
        XCTAssertEqual(snapshot.touchscreens.map(\.name), ["TouchScreen", "ILITEK-TP", "Alpha", "Zed"])
        XCTAssertEqual(snapshot.touchscreens.map(\.isConnected), [true, true, false, false])
        XCTAssertEqual(snapshot.touchscreens[2].mode, nil)
        XCTAssertEqual(snapshot.touchscreens[2].status, .notConnected)
        XCTAssertNil(snapshot.touchscreens[2].location)
        XCTAssertNil(snapshot.touchscreens[2].device)

        // Main first, then by origin: x, then y.
        XCTAssertEqual(snapshot.displays.map(\.name), ["Built-in", "Display", "HDMI", "12.3FHD", "LG HDR 4K"])
        XCTAssertEqual(snapshot.displays.first { $0.id == Desk.hdmi.displayID }?.pairedTouchscreen, "ILITEK-TP")
        XCTAssertEqual(snapshot.displays.first { $0.id == Desk.hdmi.displayID }?.detail,
                       "23.8″ · 2560 × 1440 · above the main display", "the override of the touchscreen on it")
        XCTAssertNil(snapshot.displays.first { $0.id == Desk.display.displayID }?.pairedTouchscreen)
        XCTAssertEqual(snapshot.displays.first { $0.id == Desk.lg.displayID }?.pairedTouchscreen, "Zed",
                       "a remembered touchscreen's pairing claims its display")
        XCTAssertEqual(snapshot.displays.first { $0.id == Desk.lg.displayID }?.detail,
                       "31.5″ · 3008 × 1692 · right of the main display")

        let ilitek = try XCTUnwrap(snapshot.touchscreens.first { $0.id == Desk.ilitekID })
        XCTAssertEqual(ilitek.displayChoices.map(\.name), ["Display", "HDMI", "12.3FHD", "LG HDR 4K"],
                       "never the built-in display")
        XCTAssertEqual(ilitek.displayChoices.first { $0.id == Desk.strip.displayID }?.inUseBy, "TouchScreen")
        XCTAssertNil(ilitek.displayChoices.first { $0.id == Desk.hdmi.displayID }?.inUseBy, "its own display")
        XCTAssertEqual(ilitek.displayChoices.first { $0.id == Desk.lg.displayID }?.inUseBy, "Zed", "remembered, and still in use")
        XCTAssertNil(ilitek.displayChoices.first { $0.id == Desk.display.displayID }?.inUseBy)
        let zed = try XCTUnwrap(snapshot.touchscreens.last)
        XCTAssertNil(zed.displayChoices.first { $0.id == Desk.lg.displayID }?.inUseBy, "its own display")
        XCTAssertEqual(zed.displayChoices.first { $0.id == Desk.hdmi.displayID }?.inUseBy, "ILITEK-TP")
        XCTAssertEqual(zed.status, .notConnected)
        XCTAssertNil(zed.pairedDisplayID, "a remembered touchscreen is paired with no connected display")
        XCTAssertEqual(ilitek.status, .pairedWith(name: "HDMI", detail: "23.8″ · 2560 × 1440 · above the main display"))

        // A custom display name.
        inputs.settings.displayNames[Desk.lg.uuid] = "Big one"
        XCTAssertEqual(Resolver.resolve(inputs).snapshot.displays.last?.name, "Big one")
    }

    func testWarningsInTheirOrder() {
        var inputs = Desk.inputs
        inputs.hasAccessibilityAccess = false
        inputs.isTouchUpRunning = true
        inputs.areMissionControlShortcutsOn = false
        inputs.settingsWereSetAside = true
        XCTAssertEqual(Resolver.resolve(inputs).snapshot.warnings, AppWarning.allCases)
        inputs.hasAccessibilityAccess = true
        inputs.isTouchUpRunning = false
        XCTAssertEqual(Resolver.resolve(inputs).snapshot.warnings, [.missionControlShortcutsOff, .settingsSetAside])
    }

    func testSnapshotSurvivesJSON() throws {
        var inputs = Desk.inputs
        inputs.settings.touchscreens[TouchscreenID(rawValue: "aaaa:0001:z")] = Desk.paired("Zed", with: Desk.lg)
        inputs.displays.removeAll { $0.displayID == Desk.hdmi.displayID }
        let snapshot = Resolver.resolve(inputs).snapshot
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(AppSnapshot.self, from: data), snapshot)
    }

    func testNeverTwoTouchscreensOnOneDisplay() {
        // A second monitor of HDMI's model.
        let twin = with(Desk.hdmi) { $0.displayID = 6; $0.uuid = "EEEEEEEE-0000-0000-0000-000000000006"; $0.frame.origin.x += 2560 }
        let all = Desk.displays + [twin]
        let stale = with(DisplayIdentity(Desk.hdmi)) { $0.uuid = "FFFFFFFF-0000-0000-0000-00000000000F" }
        let pairings: [(String, DisplayIdentity, DisplayIdentity)] = [
            ("both the same", DisplayIdentity(Desk.hdmi), DisplayIdentity(Desk.hdmi)),
            ("one each", DisplayIdentity(Desk.hdmi), DisplayIdentity(twin)),
            ("one stale", stale, DisplayIdentity(twin)),
            ("both stale", stale, stale),
            ("both the twin", DisplayIdentity(twin), DisplayIdentity(twin)),
        ]
        var checked = 0
        for (name, ilitekDisplay, stripDisplay) in pairings {
            for mask in 0..<(1 << all.count) {
                var inputs = Desk.inputs
                inputs.displays = all.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
                inputs.settings.touchscreens[Desk.ilitekID]?.pairing = Pairing(display: ilitekDisplay)
                inputs.settings.touchscreens[Desk.stripID]?.pairing = Pairing(display: stripDisplay)
                let resolution = Resolver.resolve(inputs)
                let driving = resolution.touchscreens.compactMap(\.driving)
                let onDisplays = driving.map(\.mapping.display.displayID)
                XCTAssertEqual(Set(onDisplays).count, onDisplays.count, "\(name), displays \(mask)")
                XCTAssertEqual(Set(driving.map(\.displayID)).count, driving.count, "\(name), displays \(mask)")
                let paired = resolution.snapshot.touchscreens.compactMap(\.pairedDisplayID)
                XCTAssertEqual(Set(paired).count, paired.count, "\(name), displays \(mask)")
                for display in driving.map(\.mapping.display) {
                    XCTAssertFalse(display.isBuiltIn)
                }
                checked += 1
            }
        }
        XCTAssertEqual(checked, pairings.count * 64)
    }
}
