// Opening the Settings window, and keeping it from opening when nobody asked.
//
// Tactile has no Dock icon and is never the active app when its menu is used or when it launches.
// Since macOS 14 activation is cooperative, so asking SwiftUI to open the window is not enough to
// bring it in front of the app the person is using. These pieces do what is documented to work
// and log what happened, so the first run can say whether it did.

import AppKit
import SwiftUI
import os

/// The interface's log: subsystem `com.crissmoldovan.tactile`, category `interface`.
enum InterfaceLog {
    static let log = Logger(subsystem: "com.crissmoldovan.tactile", category: "interface")
}

/// The Settings window's scene, and how it is brought forward with focus.
@MainActor
enum SettingsWindow {
    static let id = "settings"

    enum Reason: String, Sendable {
        /// Settings… in the menu-bar panel or menu.
        case menu
        /// The launch check (see `LaunchCheck`).
        case launch
        /// Tactile opened again, from Finder or Spotlight, while it runs (see `SettingsRequests`).
        case reopen
    }

    /// Whether anything has asked for the window since launch.
    private(set) static var wasRequested = false
    /// The Settings window while it is open; reported by `SettingsWindowReader`, cleared on close.
    private(set) static weak var window: NSWindow?
    private static var closeObserver: NSObjectProtocol?

    /// Opens Settings, or brings it to the front, and gives it focus.
    ///
    /// SwiftUI creates the window during this turn of the main loop or soon after. Once the window
    /// is visible, Tactile tries the steps of `ActivationStep` in turn until the app is active and
    /// the window key: asking macOS to activate it; if that is refused, becoming a regular app (with
    /// a Dock icon) while Settings is open; if it is still not active, forcing the activation. Each
    /// step and its result are logged.
    ///
    /// With `pane`, Settings shows that pane, whether it opens now or was open already (Settings for
    /// <name>… in a touchscreen's details in the menu).
    static func open(_ openWindow: OpenWindowAction, reason: Reason, pane: SidebarItem? = nil) {
        wasRequested = true
        if let pane {
            SettingsPaneRequests.shared.post(pane)
        }
        openWindow(id: id)
        Task { @MainActor in
            await bringForward(reason: reason)
        }
    }

    private static func bringForward(reason: Reason) async {
        // A window that is visible: never a closed one still referenced, nor one not yet shown.
        var waited = 0
        while window?.isVisible != true, waited < 20 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(50))
            waited += 1
        }
        guard let window, window.isVisible else {
            InterfaceLog.log.error("Settings (\(reason.rawValue, privacy: .public)): no window appeared to bring forward")
            return
        }
        var step = ActivationStep.cooperative
        while true {
            perform(step, on: window)
            // The answer to an activation arrives on a later turn of the main loop.
            try? await Task.sleep(for: .milliseconds(300))
            guard window.isVisible else { return }
            let isActive = NSApplication.shared.isActive, isKey = window.isKeyWindow
            switch step {
            case .cooperative:
                InterfaceLog.log.info(
                    """
                    Settings opened (\(reason.rawValue, privacy: .public)): app active \(isActive), \
                    window key \(isKey), visible \(window.isVisible)
                    """)
            case .becomeRegular:
                InterfaceLog.log.info(
                    "Settings after becoming a regular app: app active \(isActive), window key \(isKey)")
            case .force:
                break
            }
            guard let next = ActivationStep.next(after: step, isActive: isActive, isKey: isKey) else {
                if step != .cooperative {
                    InterfaceLog.log.info("Settings final: app active \(isActive), window key \(isKey)")
                }
                return
            }
            step = next
        }
    }

    private static func perform(_ step: ActivationStep, on window: NSWindow) {
        let app = NSApplication.shared
        switch step {
        case .cooperative:
            app.activate()
        case .becomeRegular:
            InterfaceLog.log.info("Settings: activation refused; becoming a regular app while Settings is open")
            RegularAppHold.hold(.settings)
            app.activate()
        case .force:
            InterfaceLog.log.info("Settings: forcing activation")
            (app as ForcedActivation).activateIgnoringOtherApps()
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// Asks for Settings from outside the scenes, which alone can reach SwiftUI's `openWindow`: the
    /// request is recorded at once, so the window that opens is never taken for one nobody asked
    /// for, and the scenes open it through `open` (see `SettingsRequests`). If they haven't within 2
    /// seconds, that is logged.
    static func requestFromOutside(reason: Reason) {
        wasRequested = true
        let requests = SettingsRequests.shared
        requests.post(reason)
        let count = requests.count
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if requests.count == count, requests.unanswered != nil {
                InterfaceLog.log.error("Settings (\(reason.rawValue, privacy: .public)): the request was not taken up; no window opened")
            }
        }
    }

    /// The window closed (by the person, or by the guard below): drop it, and stop being a regular
    /// app if Tactile became one for it. Quitting with Settings open needs nothing: the policy
    /// belongs to the running process.
    private static func forget() {
        window = nil
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        if RegularAppHold.release(.settings) {
            InterfaceLog.log.info("Settings closed; back to a menu-bar app")
        }
    }

    /// Called by `SettingsWindowReader` when the Settings view is put in a window.
    static func adopt(_ window: NSWindow) {
        guard window !== self.window else { return }
        self.window = window
        RegularAppHold.opened(.settings)
        window.isRestorable = false
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak window] _ in
            MainActor.assumeIsolated {
                if let window, SettingsWindow.window === window {
                    SettingsWindow.forget()
                }
            }
        }
        let sinceLaunch = NSRunningApplication.current.launchDate.map { Date().timeIntervalSince($0) }
        if SettingsWindowGuard.shouldClose(wasRequested: wasRequested, secondsSinceLaunch: sinceLaunch) {
            InterfaceLog.log.info("closed a Settings window that opened by itself at launch")
            Task { @MainActor in window.close() }
        }
    }
}

/// The steps of bringing Settings to the front, in order.
enum ActivationStep: Equatable, Sendable {
    /// Ask macOS to activate Tactile. Since macOS 14 it may refuse, for an app that isn't in front.
    case cooperative
    /// Become a regular app, with a Dock icon, while Settings is open, and ask again.
    case becomeRegular
    /// Activate whatever the other apps are doing.
    case force

    /// The step after `step`, given whether the app is now active and the window key; nil when
    /// Settings is in front with focus, or when nothing more can help. After asking, anything short
    /// of both counts as refused. After becoming regular, only an inactive app is forced: forcing
    /// can't make an active app's window key.
    static func next(after step: ActivationStep, isActive: Bool, isKey: Bool) -> ActivationStep? {
        switch step {
        case .cooperative: return isActive && isKey ? nil : .becomeRegular
        case .becomeRegular: return isActive ? nil : .force
        case .force: return nil
        }
    }
}

/// `NSApplication.activate(ignoringOtherApps:)` is deprecated since macOS 14 in favour of the
/// cooperative `activate()`, which macOS may refuse for an app that isn't in front: exactly a
/// menu-bar app opening Settings. It is the last resort of `ActivationStep.force`, used only when
/// the person has chosen Settings… or Gesture Tester…, or at the first-run launch check, and only
/// after `activate()` was refused twice. The package builds with warnings as errors, so it is reached through this
/// protocol, whose requirement isn't deprecated.
@MainActor
protocol ForcedActivation {
    func activateIgnoringOtherApps()
}

extension NSApplication: ForcedActivation {
    @available(macOS, deprecated: 14.0, message: "Only for the last resort of Settings and the gesture tester; see ForcedActivation.")
    func activateIgnoringOtherApps() {
        activate(ignoringOtherApps: true)
    }
}

/// When a Settings window nobody asked for is closed: one that appears in the first seconds after
/// launch without a request is SwiftUI opening or restoring it by itself.
enum SettingsWindowGuard {
    /// How long after launch an unrequested window counts as SwiftUI's own doing.
    static let launchPeriod: TimeInterval = 5

    static func shouldClose(wasRequested: Bool, secondsSinceLaunch: TimeInterval?) -> Bool {
        guard !wasRequested, let secondsSinceLaunch else { return false }
        return secondsSinceLaunch < launchPeriod
    }
}

/// Reports the window the Settings view is in to `SettingsWindow`. Invisible.
struct SettingsWindowReader: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ReportingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ReportingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                SettingsWindow.adopt(window)
            }
        }
    }
}

/// Opens Settings once, shortly after launch, when Accessibility access is missing (see
/// `shouldOpenSettingsAtLaunch`): long enough after launch for the model to have heard from the
/// touchscreens already connected. A touchscreen that isn't set up is the first-run window's.
@MainActor
final class LaunchCheck {
    static let shared = LaunchCheck()
    static let delay = Duration.seconds(1)

    private var hasDecided = false

    /// Waits, then decides once whether Settings opens, and opens it if so. Returns the decision,
    /// or nil when it decided nothing: the wait was cancelled (a later run may still decide), or it
    /// has decided already.
    @discardableResult
    func run(wait: () async throws -> Void, snapshot: () -> AppSnapshot, open: () -> Void) async -> Bool? {
        guard !hasDecided else { return nil }
        do {
            try await wait()
        } catch {
            InterfaceLog.log.info("launch check: the wait was cancelled; nothing decided yet")
            return nil
        }
        guard !hasDecided else { return nil }
        hasDecided = true
        let current = snapshot()
        let opens = shouldOpenSettingsAtLaunch(current)
        let notSetUp = current.touchscreens.filter { $0.isConnected && $0.status == .notSetUp }.count
        let offered = current.offerSetUpTo.isEmpty ? "none" : current.offerSetUpTo.map { "\($0)" }.joined(separator: ", ")
        InterfaceLog.log.info(
            """
            launch check: Accessibility missing \(current.warnings.contains(.accessibilityMissing)), \
            touchscreens not set up \(notSetUp), set-up offered to \(offered, privacy: .public): \
            \(opens ? "opening Settings" : "nothing to ask", privacy: .public)
            """)
        if opens {
            open()
        }
        return opens
    }
}

/// Requests to open Settings that come from outside the scenes, which can't reach SwiftUI's
/// `openWindow`: opening Tactile again from Finder or Spotlight while it runs, which on a Mac whose
/// menu-bar icon is hidden is the only way to Settings. The menu-bar label, the one view that exists
/// from launch, observes `count` and, when it changes, opens Settings through `SettingsWindow.open`,
/// exactly as the menu does. A signal, not a second window: there is still one Settings window.
@MainActor
@Observable
final class SettingsRequests {
    static let shared = SettingsRequests()

    /// Increases with every request.
    private(set) var count = 0
    /// The reason of the last request, until the scenes answer it.
    private(set) var unanswered: SettingsWindow.Reason?

    func post(_ reason: SettingsWindow.Reason) {
        unanswered = reason
        count += 1
    }

    /// The scenes have opened Settings for the last request.
    func answered() {
        unanswered = nil
    }

    /// The request waiting to be answered, if any, now answered: the scenes open Settings for it.
    /// Each request is taken once, however often this is asked.
    func takeUnanswered() -> SettingsWindow.Reason? {
        defer { unanswered = nil }
        return unanswered
    }
}

/// The pane Settings is asked to show: Settings for <name>… in a touchscreen's details in the menu.
/// The Settings view observes `count`, and takes the pane once, as it opens or while it is open; the
/// pane then counts as the person's choice, so Settings stays on it.
@MainActor
@Observable
final class SettingsPaneRequests {
    static let shared = SettingsPaneRequests()

    /// Increases with every request.
    private(set) var count = 0
    /// The pane last asked for, until the Settings view takes it.
    private(set) var pane: SidebarItem?

    func post(_ pane: SidebarItem) {
        self.pane = pane
        count += 1
    }

    /// The pane waiting, if any, now taken. Each is taken once.
    func take() -> SidebarItem? {
        defer { pane = nil }
        return pane
    }
}
