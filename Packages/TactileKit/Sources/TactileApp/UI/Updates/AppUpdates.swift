// The updater as the app has it: made once at launch, reached by the menu, the update window and
// General.

import AppKit
import Observation
import TactileUpdates

/// Holds the app's updater. The delegate starts it once the model has started; until then (and in
/// tests and previews, where it never starts) the menu and General show nothing of updates.
///
/// Only the official build has an updater (`UpdateAvailability`). Any other build, a fork's or one
/// signed ad hoc, makes none, so nothing asks any site; the menu and General say that updates are
/// off in this build.
@MainActor
@Observable
final class AppUpdates {
    static let shared = AppUpdates()

    private(set) var controller: UpdateController?
    /// Started, and this build doesn't update itself.
    private(set) var isOff = false

    init() {}

    /// Turns the updater's log on, then decides whether this build updates itself (so what the
    /// decision finds wrong in the Info.plist is logged) and, if it does, makes the live updater and
    /// starts its schedule.
    func start() {
        guard controller == nil, !isOff else { return }
        UpdatesLog.set(on: true)
        start(availability: UpdateAvailability.current())
    }

    /// Makes the live updater for the official build and starts its schedule; for any other build,
    /// none. Installing quits Tactile through `NSApplication.terminate`, its normal quit path, which
    /// lets every touchscreen go. Leaves the updater's log as it is: tests call this, and only the
    /// app's `start()` turns it on.
    func start(availability: UpdateAvailability) {
        guard controller == nil, !isOff else { return }
        switch availability {
        case .off(let reason):
            isOff = true
            UpdatesLog.log.info("updates are off in this build: \(reason.logDescription, privacy: .public)")
        case .on(let settings):
            let controller = UpdateController(environment: .live(settings: settings, quit: {
                NSApplication.shared.terminate(nil)
            }))
            self.controller = controller
            controller.start()
        }
    }

    /// The menu's rows: the updater's, or that updates are off in this build; nil while there is
    /// neither.
    var menuContent: UpdateMenuContent? {
        if let controller { return UpdateMenuContent(controller.state) }
        return isOff ? .off : nil
    }

    /// Check for Updates…: checks now, and shows the window, which says what the check found.
    func check() {
        guard let controller else { return }
        controller.checkForUpdates()
        UpdateWindow.shared.show(controller)
    }

    /// Update to <version>…: shows the window with the newer version's notes.
    func showUpdate() {
        guard let controller else { return }
        UpdateWindow.shared.show(controller)
    }
}
