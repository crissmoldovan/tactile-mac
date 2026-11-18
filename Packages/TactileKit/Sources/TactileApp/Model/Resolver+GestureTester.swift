// When the gesture tester can be open, and for which touchscreen. Pure.

import Foundation
import TactileScreens

/// Why the gesture tester can't be open for a touchscreen now.
public enum GestureTesterRefusal: Equatable, Sendable {
    /// Not connected, or not known at all.
    case notConnected
    /// It has no record: it can't be told apart from another connected touchscreen.
    case cannotBeToldApart
    /// Not paired with a connected display: there is nowhere for its window, or for its touches.
    case notPaired
    case tactileOff
    case accessibilityMissing
    /// Switched off by its own switch.
    case switchedOff
    /// Every touchscreen is released: the Mac is locked or asleep, or Tactile is quitting.
    case touchscreensReleased
    /// Not driving for a reason of its own: macOS also handles it, its touches can't be read, or the
    /// displays are being reconfigured.
    case notDriving
    /// A set-up runs: set-up mode, or a Calibrate or Test flow.
    case settingUp
}

extension Resolver {

    /// Why the gesture tester can't be open for touchscreen `id`, given what the interface is shown;
    /// nil when it can. It can when no set-up runs and the touchscreen is driving: connected, paired
    /// with a connected display, Tactile on with Accessibility access, the touchscreen switched on,
    /// not held because macOS also handles it or its touches can't be read; otherwise its touches
    /// would reach nothing in the tester's window. The model opens it only then, and closes it as
    /// soon as this says why not; the window's button is enabled by the same rule.
    public static func gestureTesterRefusal(for id: TouchscreenID, in snapshot: AppSnapshot) -> GestureTesterRefusal? {
        guard let touchscreen = snapshot.touchscreens.first(where: { $0.id == id }), touchscreen.isConnected else {
            return .notConnected
        }
        if !snapshot.isOn { return .tactileOff }
        if snapshot.warnings.contains(.accessibilityMissing) { return .accessibilityMissing }
        if snapshot.setUp != nil || snapshot.setUpMode != nil { return .settingUp }
        if touchscreen.notes.contains(.cannotBeToldApart) { return .cannotBeToldApart }
        if !touchscreen.isOn { return .switchedOff }
        if touchscreen.pairedDisplayID == nil { return .notPaired }
        // On, with Tactile on and Accessibility granted, and still released: the session isn't
        // active, the Mac sleeps, or Tactile is quitting (rows 1, 4 and 4a of the mode table).
        if touchscreen.mode == .released { return .touchscreensReleased }
        if touchscreen.mode != .driving { return .notDriving }
        return nil
    }
}
