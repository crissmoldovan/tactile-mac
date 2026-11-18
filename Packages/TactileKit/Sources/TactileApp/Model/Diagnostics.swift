// What Copy Diagnostics puts on the pasteboard. Pure, so it is tested.

import CoreGraphics
import Foundation
import TactileGestures
import TactileScreens

/// Tactile's own state as plain text, for a person to paste into a message: the app's version and
/// macOS's, the switches, every warning, a set-up in progress, the gesture tester, each touchscreen
/// with its USB facts (serial included), device status, mode, pairing and behaviour (the one-finger
/// mode in force, the choice, and whether it last gave one finger), and each display with its label
/// and frame. Nothing outside Tactile's own state: no other app, no user, no file path.
public enum Diagnostics {

    /// - Parameters:
    ///   - snapshot: what the interface shows now.
    ///   - settings: what is stored, for what the snapshot doesn't carry (a pairing's display
    ///     identity and alignment, whether set-up was offered).
    ///   - systemVersion: macOS's version, as `ProcessInfo.operatingSystemVersionString` gives it.
    public static func text(snapshot: AppSnapshot, settings: TactileSettings, systemVersion: String) -> String {
        var lines: [String] = []
        lines.append("Tactile \(snapshot.appVersion)")
        lines.append("macOS \(systemVersion)")
        lines.append("Tactile \(snapshot.isOn ? "on" : "off") · debug logging \(onOff(snapshot.debugLogging)) · "
                     + "recording frames \(onOff(snapshot.recordsFrames))")
        lines.append("Swipes follow the fingers \(onOff(snapshot.swipesFollowFingers)) (this Mac "
                     + "\(snapshot.canFollowSwipes ? "can" : "can't") follow them) · launch at login \(snapshot.launchAtLogin.rawValue)")
        lines.append("Warnings: " + (snapshot.warnings.isEmpty ? "none" : snapshot.warnings.map(\.rawValue).joined(separator: ", ")))
        if let setUp = snapshot.setUp {
            lines.append("Set-up running: \(setUp.touchscreenName) [\(setUp.touchscreen.rawValue)], "
                         + "\(setUp.purpose.rawValue), \(describe(setUp.step))")
        }
        if let mode = snapshot.setUpMode {
            lines.append("Set-up mode: \(describe(mode))")
        }
        if !snapshot.offerSetUpTo.isEmpty {
            lines.append("Set-up offered for: " + snapshot.offerSetUpTo.map(\.rawValue).joined(separator: ", "))
        }
        lines.append("Gesture tester: " + (snapshot.gestureTester.map(describe) ?? "closed"))

        lines.append("")
        lines.append("Touchscreens")
        if snapshot.touchscreens.isEmpty { lines.append("  none") }
        for touchscreen in snapshot.touchscreens {
            lines.append(contentsOf: describe(touchscreen, stored: settings.touchscreens[touchscreen.id]))
        }

        lines.append("")
        lines.append("Displays")
        if snapshot.displays.isEmpty { lines.append("  none") }
        for display in snapshot.displays {
            lines.append(contentsOf: describe(display, customName: settings.displayNames[display.uuid]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Private

    private static func describe(_ touchscreen: TouchscreenSnapshot, stored: TouchscreenSettings?) -> [String] {
        var lines = ["- \(touchscreen.name) [\(touchscreen.id.rawValue)]"]
        var usb = "  USB \(touchscreen.usbID) · serial \"\(touchscreen.serial)\""
        if let location = touchscreen.location { usb += " · location \(location)" }
        if touchscreen.deviceName != touchscreen.name { usb += " · device name \"\(touchscreen.deviceName)\"" }
        lines.append(usb)
        let mode = touchscreen.mode.map { "mode \($0.rawValue)" } ?? "not connected"
        lines.append("  \(touchscreen.isConnected ? "connected" : "remembered") · \(mode) · status \(describe(touchscreen.status))")
        if let device = touchscreen.device { lines.append("  device: \(device)") }
        if !touchscreen.notes.isEmpty { lines.append("  notes: " + touchscreen.notes.map(\.rawValue).joined(separator: ", ")) }
        lines.append("  \(touchscreen.isOn ? "on" : "off") · when off: \(touchscreen.whenOff.rawValue)"
                     + (stored.map { " · offered set-up: \($0.wasOfferedSetUp ? "yes" : "no")" } ?? ""))

        if let pairing = stored?.pairing {
            var paired = "  paired with \(touchscreen.pairedDisplayName ?? "?")"
            paired += touchscreen.pairedDisplayID.map { " (display \($0))" } ?? " (not connected)"
            lines.append(paired)
            let identity = pairing.display
            lines.append("    display uuid \(identity.uuid.isEmpty ? "none" : identity.uuid) · vendor \(hex(identity.vendor)) · "
                         + "model \(hex(identity.model)) · serial \(identity.serial) · native \(identity.nativeWidth) × \(identity.nativeHeight)"
                         + (pairing.displayName.isEmpty ? "" : " · remembered as \"\(pairing.displayName)\""))
            lines.append("    orientation \(pairing.orientation.quarterTurns * 90)°\(pairing.orientation.isFlipped ? " flipped" : "") · "
                         + "alignment \(describe(pairing.alignment))")
        } else {
            lines.append("  not paired")
        }
        let diagonal = touchscreen.diagonalInches.map { "\(number($0))″ (set)" } ?? "as reported"
        let reported = touchscreen.reportedDiagonalInches.map { " · its display reports \(number($0))″" } ?? ""
        lines.append("  diagonal \(diagonal)\(reported)")

        let behaviour = touchscreen.behaviour
        let gaveOneFinger = stored?.lastGaveOneFinger.map { $0 ? "yes" : "no" } ?? "not known"
        lines.append("  one finger \(behaviour.oneFinger.rawValue) in force · "
                     + "choice \(behaviour.oneFingerChoice?.rawValue ?? "none (the default)") · "
                     + "last gave one finger: \(gaveOneFinger)")
        lines.append("  after a touch \(behaviour.pointerReturn.rawValue) · circles \(onOff(behaviour.showsCircles))")
        lines.append("  gestures: \(describe(behaviour.gestures))"
                     + (behaviour.multiFingerAvailable ? "" : " (one finger only: the multi-finger ones not in force)"))
        lines.append("  palm rejection \(onOff(behaviour.rejection.palm)) · edge margin \(number(behaviour.rejection.edgeMarginMM)) mm · "
                     + "reports contact size or confidence: \(behaviour.reportsPalms ? "yes" : "no")")
        if touchscreen.isConnected {
            lines.append("  calibrated: \(touchscreen.isCalibrated ? "yes" : "no") · can be set up: \(touchscreen.canBeSetUp ? "yes" : "no")")
        }
        return lines
    }

    private static func describe(_ display: DisplaySnapshot, customName: String?) -> [String] {
        let frame = display.frame
        var line = "- \(display.name) — \(display.detail)"
        line += ": display \(display.id) · uuid \(display.uuid.isEmpty ? "none" : display.uuid)"
        line += " · frame \(number(frame.origin.x)), \(number(frame.origin.y)), \(number(frame.width)) × \(number(frame.height))"
        if display.isMain { line += " · main" }
        if display.isBuiltIn { line += " · built-in" }
        if customName != nil { line += " · named by the person" }
        if let paired = display.pairedTouchscreen { line += " · paired with \(paired)" }
        return [line]
    }

    private static func describe(_ status: TouchscreenStatus) -> String {
        switch status {
        case .notConnected: return "not connected"
        case .tactileOff: return "Tactile off"
        case .accessibilityMissing: return "Accessibility missing"
        case .off: return "off"
        case .notSetUp: return "not set up"
        case .displayNotConnected(let name): return "display not connected (\(name))"
        case .pairedWith(let name, let detail): return "paired with \(name) — \(detail)"
        }
    }

    private static func describe(_ step: SetUpStep) -> String {
        switch step {
        case .corners(let display, _, let index, let problem):
            return "corners on display \(display), target \(index + 1) of 4" + (problem.map { ", \($0.rawValue)" } ?? "")
        case .size(let display, let displayReports, let touchscreenReports, let current):
            let options = [displayReports.map { "display reports \(number($0))″" },
                           touchscreenReports.map { "touchscreen reports \(number($0))″" },
                           current.map { "set \(number($0))″" }].compactMap { $0 }
            return "size on display \(display)" + (options.isEmpty ? "" : ": " + options.joined(separator: ", "))
        case .check(let display):
            return "check on display \(display)"
        }
    }

    private static func describe(_ tester: GestureTesterSnapshot) -> String {
        "open for \(tester.touchscreenName) [\(tester.touchscreen.rawValue)] on display \(tester.displayID) · "
            + "swipes \(tester.performsSwipes ? "let through" : "held")"
    }

    private static func describe(_ mode: SetUpModeSnapshot) -> String {
        let stage: String
        switch mode.stage {
        case .choosing: stage = "choosing"
        case .waitingForTouch(let display): stage = "waiting for a touch on display \(display)"
        case .touchedFirst(let touchscreen, _): stage = "\(touchscreen.rawValue) touched first"
        case .running: stage = "running"
        }
        let displays = mode.displays.map { "\($0.id)" }.joined(separator: ", ")
        return stage + " · candidates " + (displays.isEmpty ? "none" : displays)
            + (mode.justSetUp.map { " · just set up \($0.rawValue)" } ?? "")
    }

    private static func describe(_ gestures: GestureOptions) -> String {
        let all: [(String, Bool)] = [("scroll", gestures.twoFingerScroll), ("pinch", gestures.pinch),
                                     ("two-finger tap", gestures.twoFingerTap), ("swipes", gestures.swipes),
                                     ("rotate", gestures.rotate), ("long-press", gestures.longPress)]
        return all.map { "\($0.0) \(onOff($0.1))" }.joined(separator: ", ")
    }

    private static func describe(_ alignment: GlassAlignment) -> String {
        guard alignment != .wholeGlass else { return "whole glass" }
        let rect = alignment.pictureRect
        return "\(number(rect.origin.x, places: 4)), \(number(rect.origin.y, places: 4)), "
            + "\(number(rect.width, places: 4)) × \(number(rect.height, places: 4))"
    }

    private static func onOff(_ value: Bool) -> String { value ? "on" : "off" }

    private static func hex(_ value: Int) -> String { "0x" + String(UInt64(truncatingIfNeeded: value), radix: 16) }

    /// `value` with up to `places` decimals, trailing zeros dropped: "23.8", "27", "-252".
    private static func number<Value: BinaryFloatingPoint>(_ value: Value, places: Int = 1) -> String {
        let double = Double(value)
        guard double.isFinite else { return "\(double)" }
        var text = String(format: "%.\(places)f", double)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text == "-0" ? "0" : text
    }
}
