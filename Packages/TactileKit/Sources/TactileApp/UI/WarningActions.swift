// What a warning's button does. Two of them act directly, through `NSWorkspace`, and are not
// commands: they change nothing in Tactile.

import AppKit
import Foundation

@MainActor
enum WarningActions {
    /// Carries out `kind`: a command goes to the model; the others act through `NSWorkspace`.
    static func run(_ kind: WarningAction.Kind, perform: PerformCommand) {
        switch kind {
        case .command(let command):
            perform(command)
        case .openKeyboardSettings:
            openKeyboardSettings()
        case .quitTouchUp:
            quitTouchUp()
        }
    }

    /// System Settings at Keyboard, where Keyboard Shortcuts… holds Mission Control's. The first
    /// address is System Settings' (macOS 13 and later); the second is the older System
    /// Preferences' address, which later versions also take.
    static let keyboardSettingsAddresses = [
        "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
        "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts",
    ]

    private static func openKeyboardSettings() {
        for address in keyboardSettingsAddresses {
            if let url = URL(string: address), NSWorkspace.shared.open(url) {
                InterfaceLog.log.info("opened Keyboard settings (\(address, privacy: .public))")
                return
            }
        }
        InterfaceLog.log.error("could not open Keyboard settings")
    }

    /// Whether an app is Touch Up, as the Touch Up warning itself decides
    /// (`LiveSystemConditions.isTouchUp`): the button quits exactly what the warning saw.
    static func isTouchUp(bundleIdentifier: String?, bundleURL: URL?) -> Bool {
        LiveSystemConditions.isTouchUp(bundleIdentifier: bundleIdentifier, bundleURL: bundleURL)
    }

    /// Asks every running Touch Up to quit, as Quit in its own menu would.
    private static func quitTouchUp() {
        let running = NSWorkspace.shared.runningApplications.filter {
            isTouchUp(bundleIdentifier: $0.bundleIdentifier, bundleURL: $0.bundleURL)
        }
        for app in running {
            let asked = app.terminate()
            InterfaceLog.log.info("asked Touch Up (pid \(app.processIdentifier, privacy: .public)) to quit: \(asked ? "accepted" : "refused", privacy: .public)")
        }
        if running.isEmpty {
            InterfaceLog.log.info("Quit Touch Up: it is not running")
        }
    }
}
