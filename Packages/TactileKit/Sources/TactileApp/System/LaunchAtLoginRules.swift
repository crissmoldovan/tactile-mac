// Whether Tactile opens at login, decided from where it runs and what the system says. Pure, so it is
// tested; `LiveSystemConditions` asks the system.

import Foundation

/// What the system says about Tactile as a login item: `SMAppService.Status`, kept apart from
/// ServiceManagement so the decision can be tested without it.
enum LoginItemStatus: Equatable, Sendable {
    case notRegistered, enabled, requiresApproval, notFound
}

/// Tactile's login item as `LaunchAtLoginRules.request` asks it: `SMAppService.mainApp` in the app
/// (see `LiveSystemConditions`), a fake in the tests.
@MainActor
protocol LoginItemRegistrar {
    var status: LoginItemStatus? { get }
    func register() throws
    func unregister() throws
}

/// What became of a request to switch launch at login on or off.
enum LaunchAtLoginRequest: Equatable, Sendable {
    /// Switching on from a copy that isn't the installed one: refused before macOS was asked.
    case notTheInstalledCopy
    /// macOS was asked. `error`: what its call threw, described, if it threw; `statusAfter`: what it
    /// says afterwards; `refused`: `LaunchAtLoginRules.wasRefused`'s answer.
    case asked(error: String?, statusAfter: LoginItemStatus?, refused: Bool)
}

enum LaunchAtLoginRules {

    /// Whether the app at `bundlePath` is the installed copy: once its symbolic links are resolved
    /// (`resolvingSymlinks`, the file system's answer in the app), inside `/Applications` or
    /// `~/Applications` (`home` + `/Applications`), at any depth. So a link in `/Applications` to a
    /// build folder is not; nor is a build folder, a disk image, a path that only has
    /// "Applications" somewhere in it, or where macOS runs an app downloaded and opened in place
    /// ("App Translocation"). Nothing is registered to open at login from anywhere but the
    /// installed copy. Compared without regard to case, as the startup disk does by default; `.`
    /// and `..` are taken out first.
    static func isTheInstalledCopy(bundlePath: String, home: String, resolvingSymlinks: (String) -> String) -> Bool {
        let path = standardised(resolvingSymlinks(bundlePath))
        let folders = ["/Applications", home + "/Applications"].map { standardised($0) + "/" }
        return folders.contains { path.hasPrefix($0) && path.count > $0.count }
    }

    /// What the switch shows, by the first that applies:
    /// - registered and enabled: `on`, wherever Tactile runs, so that a registered item can always be
    ///   switched off;
    /// - registered and waiting for the person in System Settings › Login Items: `needsApproval`,
    ///   wherever Tactile runs;
    /// - not the installed copy: `notInstalled`;
    /// - a request made in this run was refused (`refused`, see `wasRefused`): `unavailable`;
    /// - otherwise `off`: not registered, `notFound` (what macOS says of an installed app never
    ///   registered, and after `unregister()`), or a status this Tactile doesn't know.
    static func state(isInstalled: Bool, status: LoginItemStatus?, refused: Bool) -> LaunchAtLogin {
        switch status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        case .notRegistered, .notFound, nil:
            guard isInstalled else { return .notInstalled }
            return refused ? .unavailable : .off
        }
    }

    /// Switches launch at login `on` or off through `registrar`. Switching on from a copy that
    /// isn't the installed one is refused before `registrar` is reached: nothing is ever registered
    /// from a build folder. Switching off always reaches it, so a login item registered from
    /// anywhere can be removed from there.
    @MainActor
    static func request(_ on: Bool, isInstalled: Bool, registrar: LoginItemRegistrar) -> LaunchAtLoginRequest {
        if on, !isInstalled { return .notTheInstalledCopy }
        var error: String?
        do {
            if on { try registrar.register() } else { try registrar.unregister() }
        } catch let thrown {
            error = String(describing: thrown)
        }
        let after = registrar.status
        return .asked(error: error, statusAfter: after, refused: wasRefused(on: on, threw: error != nil, statusAfter: after))
    }

    /// Whether a request to switch launch at login `on` or off was refused: its call threw, or,
    /// asked to switch on, the system says afterwards that it is neither on nor waiting for the
    /// person's approval.
    static func wasRefused(on: Bool, threw: Bool, statusAfter: LoginItemStatus?) -> Bool {
        if threw { return true }
        guard on else { return false }
        return statusAfter != .enabled && statusAfter != .requiresApproval
    }

    private static func standardised(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path.lowercased()
    }
}
