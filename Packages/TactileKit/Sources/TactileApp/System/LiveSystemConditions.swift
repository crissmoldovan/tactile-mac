// Permissions, the session, power and other apps, from the system, kept current.

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ServiceManagement
import TactileOutput
import os

/// What the model needs to know about the system, from macOS. Thin: every decision about what
/// these mean is the resolver's.
///
/// - Accessibility: `AXIsProcessTrusted()`, checked every 2 seconds, so a change either way is
///   noticed within 3. It never asks; `askForAccessibility` does, and only a button calls it.
/// - The session: active unless the user is switched out (`NSWorkspace`'s session notifications)
///   or the screen is locked (the `com.apple.screenIsLocked` / `…Unlocked` distributed
///   notifications, delivered at once although Tactile is almost never the active app: AppKit holds
///   back distributed notifications from an inactive app unless asked not to). Also read from
///   `CGSessionCopyCurrentDictionary` at the start, every 2 seconds and on waking, so a
///   notification that never comes is made up for; that read can't undo a lock notification
///   unless it has itself shown the lock since (see `ScreenLock`).
/// - Sleep and wake: `NSWorkspace`'s notifications.
/// - Touch Up: whether an app with one of `touchUpBundleIdentifiers` is running.
/// - The Mission Control shortcuts: `MissionControlShortcuts.areEnabled()`, every 2 seconds.
/// - The trackpad's "Swipe between full-screen applications": `LiveDockSwipeSurroundings`' read of
///   the person's trackpad settings (defaults only: never the window server, never a private
///   function), every 2 seconds and when Tactile becomes the active app. It isn't carried here: the
///   model is told when it changed, and reads it through the Dock-swipe sender at that round
///   (`canFollowSwipes`), so the interface follows it as the pipelines do.
/// - Launch at login: `SMAppService.mainApp`, reached nowhere else. Its status is read when asked,
///   and the model is told when it changed by the time Tactile becomes the active app (the person
///   comes back from System Settings). What it means is `LaunchAtLoginRules`'. Nothing is
///   registered unless the person presses the switch, and never from outside the Applications
///   folder; a refusal is logged and shown as `unavailable`.
///
/// Lives as long as the app; it never stops observing.
@MainActor
public final class LiveSystemConditions: SystemConditions {
    public private(set) var hasAccessibilityAccess: Bool
    public var isSessionActive: Bool { isOnConsole && !screenLock.isLocked }
    public private(set) var isTouchUpRunning: Bool
    public private(set) var areMissionControlShortcutsOn: Bool
    public var onChange: (@MainActor () -> Void)?
    public var onWillSleep: (@MainActor () -> Void)?
    public var onDidWake: (@MainActor () -> Void)?

    /// Touch Up's bundle identifiers: the one in `/Applications/Touch Up.app` when it is installed
    /// (the notarized download's is `de.schafe.Touch-Up-notarized`), and that one regardless.
    public static let touchUpBundleIdentifiers: Set<String> = {
        var identifiers: Set<String> = ["de.schafe.Touch-Up-notarized"]
        if let installed = Bundle(url: URL(fileURLWithPath: "/Applications/Touch Up.app"))?.bundleIdentifier {
            identifiers.insert(installed)
        }
        return identifiers
    }()

    private static let log = Logger(subsystem: "com.crissmoldovan.tactile", category: "system")
    private var isOnConsole: Bool
    /// The trackpad's "Swipe between full-screen applications" when last read: kept only to tell
    /// when it changed.
    private var isSpaceSwipeOn: Bool
    /// The lock notifications and the session dictionary together: see `ScreenLock`.
    private var screenLock: ScreenLock
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var lockObserver: LockObserver?
    private var timer: Timer?
    /// Whether the system refused the last request to register or unregister.
    private var launchAtLoginRefused = false
    /// What launch at login was when last reported.
    private var lastLaunchAtLogin = LaunchAtLogin.unavailable

    public init() {
        hasAccessibilityAccess = AXIsProcessTrusted()
        let session = Self.readSession()
        isOnConsole = session.onConsole
        screenLock = ScreenLock(dictionaryShowsLock: session.locked)
        isTouchUpRunning = Self.touchUpIsRunning()
        areMissionControlShortcutsOn = MissionControlShortcuts.areEnabled()
        isSpaceSwipeOn = Self.spaceSwipeIsOn()

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.isOnConsole = true; $0.changed() }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.isOnConsole = false; $0.changed() }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.onWillSleep?() }
        observe(workspace, NSWorkspace.didWakeNotification) { conditions in
            // The lock and the rest are read again first, so that waking never takes a touchscreen
            // on a locked screen.
            conditions.poll()
            conditions.onDidWake?()
        }
        observe(NotificationCenter.default, NSApplication.didBecomeActiveNotification) { $0.becameActive() }
        observe(workspace, NSWorkspace.didLaunchApplicationNotification) { $0.poll() }
        observe(workspace, NSWorkspace.didTerminateApplicationNotification) { $0.poll() }
        let lockObserver = LockObserver { [weak self] locked in
            guard let self else { return }
            let outcome = self.screenLock.notified(locked: locked)
            self.report(outcome)
            if outcome.changed { self.changed() }
        }
        let distributed = DistributedNotificationCenter.default()
        for name in [LockObserver.locked, LockObserver.unlocked] {
            distributed.addObserver(lockObserver, selector: #selector(LockObserver.received(_:)), name: name,
                                    object: nil, suspensionBehavior: .deliverImmediately)
        }
        self.lockObserver = lockObserver

        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Self.log.info("Accessibility \(self.hasAccessibilityAccess ? "granted" : "missing", privacy: .public); session \(self.isSessionActive ? "active" : "not active", privacy: .public); Touch Up \(self.isTouchUpRunning ? "running" : "not running", privacy: .public)")
        if let line = screenLock.reportAtLaunch { Self.log.info("\(line, privacy: .public)") }
        lastLaunchAtLogin = launchAtLogin
        Self.log.info("Launch at login: \(self.lastLaunchAtLogin.rawValue, privacy: .public) (\(Self.bundlePath, privacy: .public))")
    }

    public func askForAccessibility() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        poll()
    }

    public var launchAtLogin: LaunchAtLogin {
        LaunchAtLoginRules.state(isInstalled: Self.isTheInstalledCopy,
                                 status: Self.status(SMAppService.mainApp.status), refused: launchAtLoginRefused)
    }

    /// Registers or unregisters Tactile as a login item. Only a button calls it. Never registers a
    /// Tactile that isn't the installed copy; unregisters from anywhere, so that a login item
    /// registered earlier can be switched off wherever Tactile runs (`LaunchAtLoginRules.request`).
    /// A request the system refuses (the call throws, or asked to switch on, it is neither on nor
    /// waiting for approval afterwards) is logged, and shown as `unavailable` until a later
    /// request goes through.
    public func setLaunchAtLogin(_ on: Bool) {
        switch LaunchAtLoginRules.request(on, isInstalled: Self.isTheInstalledCopy, registrar: MainAppLoginItem()) {
        case .notTheInstalledCopy:
            Self.log.error("Launch at login not registered: Tactile isn't running from the Applications folder (\(Self.bundlePath, privacy: .public))")
            return
        case .asked(let error, let after, let refused):
            if let error {
                Self.log.error("Launch at login: macOS refused to \(on ? "register" : "unregister", privacy: .public) Tactile: \(error, privacy: .public)")
            }
            launchAtLoginRefused = refused
            if refused, error == nil {
                Self.log.error("Launch at login: asked to switch on, macOS says \(String(describing: after), privacy: .public)")
            }
        }
        lastLaunchAtLogin = launchAtLogin
        Self.log.info("Launch at login: \(self.lastLaunchAtLogin.rawValue, privacy: .public)")
    }

    public func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - Private

    /// The running app's bundle, as it was opened.
    private static var bundlePath: String { Bundle.main.bundleURL.path }

    /// Whether this is the installed copy, its symbolic links resolved by the file system.
    private static var isTheInstalledCopy: Bool {
        LaunchAtLoginRules.isTheInstalledCopy(bundlePath: bundlePath, home: home) {
            URL(fileURLWithPath: $0).resolvingSymlinksInPath().path
        }
    }

    private static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    fileprivate static func status(_ status: SMAppService.Status) -> LoginItemStatus? {
        switch status {
        case .notRegistered: return .notRegistered
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return nil
        }
    }

    /// Tactile became the active app, perhaps back from System Settings: the model is told, once, if
    /// launch at login or the trackpad's "Swipe between full-screen applications" changed meanwhile.
    private func becameActive() {
        let now = launchAtLogin
        let launchAtLoginChanged = now != lastLaunchAtLogin
        if launchAtLoginChanged {
            lastLaunchAtLogin = now
            Self.log.info("Launch at login: \(now.rawValue, privacy: .public)")
        }
        let spaceSwipe = Self.spaceSwipeIsOn()
        if spaceSwipe != isSpaceSwipeOn {
            isSpaceSwipeOn = spaceSwipe
            changed()
        } else if launchAtLoginChanged {
            onChange?()
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ handle: @escaping @MainActor (LiveSystemConditions) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handle(self)
            }
        }
        observers.append((center, token))
    }

    /// Reads again what isn't announced, or may not have been, and says so if anything changed.
    private func poll() {
        let access = AXIsProcessTrusted()
        let touchUp = Self.touchUpIsRunning()
        let shortcuts = MissionControlShortcuts.areEnabled()
        let spaceSwipe = Self.spaceSwipeIsOn()
        let session = Self.readSession()
        let lock = screenLock.polled(dictionaryShowsLock: session.locked)
        report(lock)
        guard access != hasAccessibilityAccess || touchUp != isTouchUpRunning || shortcuts != areMissionControlShortcutsOn
                || spaceSwipe != isSpaceSwipeOn || session.onConsole != isOnConsole || lock.changed
        else { return }
        hasAccessibilityAccess = access
        isTouchUpRunning = touchUp
        areMissionControlShortcutsOn = shortcuts
        isSpaceSwipeOn = spaceSwipe
        isOnConsole = session.onConsole
        changed()
    }

    /// The lines `ScreenLock` says are due: a lock starting, and what saw it; the dictionary first
    /// confirming a notified lock; a lock ending, and what saw it. So a test by hand learns which source
    /// works, and a lock that never ends shows in the log as one that started.
    private func report(_ outcome: ScreenLock.Outcome) {
        if let line = outcome.report { Self.log.info("\(line, privacy: .public)") }
    }

    private func changed() {
        Self.log.info("Accessibility \(self.hasAccessibilityAccess ? "granted" : "missing", privacy: .public); session \(self.isSessionActive ? "active" : "not active", privacy: .public); Touch Up \(self.isTouchUpRunning ? "running" : "not running", privacy: .public); Mission Control shortcuts \(self.areMissionControlShortcutsOn ? "on" : "off", privacy: .public); swipe between full-screen applications \(self.isSpaceSwipeOn ? "on" : "not on", privacy: .public)")
        onChange?()
    }

    /// The trackpad's "Swipe between full-screen applications", as the Dock-swipe sender reads it:
    /// the person's trackpad settings, decided by `SpaceSwipeSetting`. Logged by the sender once a
    /// launch, at the first read; never here at each poll.
    private static func spaceSwipeIsOn() -> Bool {
        LiveDockSwipeSurroundings().isSpaceSwipeEnabled
    }

    /// Whether an app is Touch Up: one of `touchUpBundleIdentifiers`, any other build of it
    /// (`de.schafe.Touch-Up…`), or a bundle called `Touch Up.app`. The one definition, used for the
    /// warning and by the warning's Quit Touch Up button.
    public static func isTouchUp(bundleIdentifier: String?, bundleURL: URL?) -> Bool {
        if let bundleIdentifier,
           touchUpBundleIdentifiers.contains(bundleIdentifier) || bundleIdentifier.hasPrefix("de.schafe.Touch-Up") {
            return true
        }
        return bundleURL?.lastPathComponent == "Touch Up.app"
    }

    private static func touchUpIsRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            isTouchUp(bundleIdentifier: app.bundleIdentifier, bundleURL: app.bundleURL)
        }
    }

    /// Whether this user's session is the one on the console, and whether its screen is locked.
    private static func readSession() -> (onConsole: Bool, locked: Bool) {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return (true, false) }
        let onConsole = session[kCGSessionOnConsoleKey as String] as? Bool ?? true
        let locked = session["CGSSessionScreenIsLocked"] as? Bool ?? false
        return (onConsole, locked)
    }
}

/// Receives the screen-lock distributed notifications, which need a selector to be delivered at
/// once to an app that isn't active.
private final class LockObserver: NSObject, @unchecked Sendable {
    static let locked = Notification.Name("com.apple.screenIsLocked")
    static let unlocked = Notification.Name("com.apple.screenIsUnlocked")

    private let handle: @MainActor @Sendable (_ locked: Bool) -> Void

    init(_ handle: @escaping @MainActor @Sendable (_ locked: Bool) -> Void) {
        self.handle = handle
    }

    @objc nonisolated func received(_ notification: Notification) {
        let locked = notification.name == Self.locked
        let handle = handle
        if Thread.isMainThread {
            MainActor.assumeIsolated { handle(locked) }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { handle(locked) } }
        }
    }
}

/// `SMAppService.mainApp`, as `LaunchAtLoginRules.request` asks it.
@MainActor
private struct MainAppLoginItem: LoginItemRegistrar {
    var status: LoginItemStatus? { LiveSystemConditions.status(SMAppService.mainApp.status) }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}
