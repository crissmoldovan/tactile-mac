import TactileScreens

/// The connected displays, live.
@MainActor
public protocol DisplaySource: AnyObject {
    var displays: [DisplayFacts] { get }
    var onChange: (@MainActor () -> Void)? { get set }
}

/// Permissions, the session, power, and other apps.
@MainActor
public protocol SystemConditions: AnyObject {
    var hasAccessibilityAccess: Bool { get }
    /// False while the screen is locked or the user is switched out.
    var isSessionActive: Bool { get }
    var isTouchUpRunning: Bool { get }
    var areMissionControlShortcutsOn: Bool { get }
    /// Any of the four above changed.
    var onChange: (@MainActor () -> Void)? { get set }
    var onWillSleep: (@MainActor () -> Void)? { get set }
    var onDidWake: (@MainActor () -> Void)? { get set }
    /// Shows the system's request for Accessibility access. Only ever called from a button.
    func askForAccessibility()
    var launchAtLogin: LaunchAtLogin { get }
    func setLaunchAtLogin(_ on: Bool)
    func openLoginItemsSettings()
}
