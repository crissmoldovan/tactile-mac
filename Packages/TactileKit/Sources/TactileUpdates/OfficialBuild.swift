// Whether this copy of Tactile updates itself: only the official build does, and its Info.plist says
// where it asks and which keys it trusts.

import CryptoKit
import Foundation
import Security

/// The official build of Tactile: its bundle identifier, and the code requirement its own signature
/// must satisfy, the one every update is checked against (a Developer ID of Tactile's team). Only
/// that build updates itself, so a fork, or a copy anyone builds from the source, is never replaced
/// by an official release.
///
/// A fork that wants updates of its own gives itself its own bundle identifier, team, site and keys:
/// the identifier and team here and in `SecurityCodeSignatureCheck.developerIDRequirement`, the site
/// and keys in the build settings `TACTILE_UPDATE_BASE_URL` and `TACTILE_UPDATE_KEYS`
/// (`Config/Updates.xcconfig`, or its own `Signing.local.xcconfig`).
public enum OfficialBuild {
    public static let bundleIdentifier = "com.crissmoldovan.tactile"
    /// The requirement updates are checked against (`SecurityCodeSignatureCheck`), which names the
    /// bundle identifier and the team.
    public static let requirement = SecurityCodeSignatureCheck.developerIDRequirement
}

/// Checks the running app's own code signature against a requirement.
public protocol SelfSignatureChecking: Sendable {
    func satisfies(_ requirement: String) -> Bool
}

/// The Security framework's check of this process: `SecCodeCopySelf`, then `SecCodeCheckValidity`
/// against the requirement.
public struct SecuritySelfSignatureCheck: SelfSignatureChecking {
    public init() {}

    public func satisfies(_ requirement: String) -> Bool {
        status(requirement) == errSecSuccess
    }

    /// `errSecSuccess` when this process's signature is valid and satisfies `requirement`.
    public func status(_ requirement: String) -> OSStatus {
        var code: SecCode?
        var status = SecCodeCopySelf([], &code)
        guard status == errSecSuccess, let code else { return status }
        var compiled: SecRequirement?
        status = SecRequirementCreateWithString(requirement as CFString, [], &compiled)
        guard status == errSecSuccess, let compiled else { return status }
        return SecCodeCheckValidity(code, [], compiled)
    }
}

/// Where a build asks for updates and which update keys it trusts, from its Info.plist. The build
/// settings `TACTILE_UPDATE_BASE_URL` and `TACTILE_UPDATE_KEYS` fill in the keys
/// `TactileUpdateBaseURL` and `TactileUpdateKeys` (see `Tactile/Info.plist`);
/// `Config/Updates.xcconfig` sets them to today's values, which are also `builtIn`.
public struct UpdateSettings: Equatable, Sendable {
    public static let baseURLKey = "TactileUpdateBaseURL"
    public static let keysKey = "TactileUpdateKeys"

    /// tactilemac.com and the production keys: what a build whose Info.plist names none uses.
    public static let builtIn = UpdateSettings(site: .builtIn, keys: UpdateTrust.productionKeys)

    public var site: UpdateSite
    /// Key ID → standard base64 of the raw Ed25519 public key, as `UpdateTrust(base64Keys:)` takes them.
    public var keys: [String: String]

    public init(site: UpdateSite, keys: [String: String]) {
        self.site = site
        self.keys = keys
    }

    /// The settings in an Info.plist. A value that is missing or empty (an unset build setting
    /// expands to nothing) leaves the built-in one. A value that is there but can't be used fails,
    /// and the build then doesn't update at all, rather than fall back to the built-in site and keys:
    /// the site must be an https origin (on this Mac too), and every key entry must be usable.
    public static func read(info: [String: Any]?) -> Result<UpdateSettings, UnusableUpdateSetting> {
        var settings = builtIn
        if let value = info?[baseURLKey] {
            let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if text != "" {
                guard let text, let site = UpdateSite(base: text, allowingHTTPOnThisMac: false) else {
                    return .failure(unusable(baseURLKey, value, "isn’t an https origin"))
                }
                settings.site = site
            }
        }
        if let value = info?[keysKey] {
            let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if text != "" {
                guard let text, let keys = parseKeys(text) else {
                    return .failure(unusable(keysKey, value, "isn’t a list of <id>:<base64 public key>, each ID once"))
                }
                settings.keys = keys
            }
        }
        return .success(settings)
    }

    private static func unusable(_ key: String, _ value: Any, _ why: String) -> UnusableUpdateSetting {
        UpdatesLog.log.error("Info.plist \(key, privacy: .public) “\(String(describing: value), privacy: .public)” \(why, privacy: .public): updates are off in this build")
        return UnusableUpdateSetting(key: key)
    }

    /// Keys written as `<id>:<base64>`, separated by spaces, commas or new lines:
    /// `k1:IpKo…= k2:…`. An ID is 1 to 32 letters, digits, `.`, `_` or `-` (as the release script
    /// takes it); a key must decode to 32 bytes. All or nothing: nil when any entry isn't so, when an
    /// ID is given twice, or when there is no entry.
    public static func parseKeys(_ text: String) -> [String: String]? {
        var keys: [String: String] = [:]
        for entry in text.split(whereSeparator: { $0 == "," || $0.isWhitespace }) {
            guard let colon = entry.firstIndex(of: ":") else { return nil }
            let id = String(entry[..<colon])
            let key = String(entry[entry.index(after: colon)...])
            guard isKeyID(id), keys[id] == nil, let raw = Data(base64Encoded: key), raw.count == 32,
                  (try? Curve25519.Signing.PublicKey(rawRepresentation: raw)) != nil
            else { return nil }
            keys[id] = key
        }
        return keys.isEmpty ? nil : keys
    }

    private static func isKeyID(_ id: String) -> Bool {
        (1...32).contains(id.unicodeScalars.count) && id.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || "._-".unicodeScalars.contains($0)
        }
    }
}

/// Whether this copy of Tactile updates itself, and from where.
public enum UpdateAvailability: Equatable, Sendable {
    /// The official build: it asks `settings.site` and trusts `settings.keys`.
    case on(UpdateSettings)
    /// Any other build: nothing asks any site, and Check for Updates… and General say that updates
    /// are off in this build.
    case off(UpdatesOffReason)

    public var isOn: Bool {
        if case .on = self { return true }
        return false
    }

    /// The decision, from the running app's bundle identifier, its Info.plist and its own signature.
    public static func decide(bundleIdentifier: String?, info: [String: Any]?,
                              signature: SelfSignatureChecking) -> UpdateAvailability {
        guard bundleIdentifier == OfficialBuild.bundleIdentifier else { return .off(.otherBundleIdentifier) }
        guard signature.satisfies(OfficialBuild.requirement) else { return .off(.notSignedByTheDeveloper) }
        switch UpdateSettings.read(info: info) {
        case .success(let settings): return .on(settings)
        case .failure(let unusable): return .off(.unusableSetting(unusable.key))
        }
    }

    /// The decision for this process: `Bundle.main`, and its signature as the Security framework
    /// checks it. Turn the updater's log on first, for what it finds wrong to be logged.
    public static func current() -> UpdateAvailability {
        decide(bundleIdentifier: Bundle.main.bundleIdentifier, info: Bundle.main.infoDictionary,
               signature: SecuritySelfSignatureCheck())
    }
}

/// Why a build doesn't update itself, for the log.
public enum UpdatesOffReason: Equatable, Sendable {
    /// Its bundle identifier isn't Tactile's.
    case otherBundleIdentifier
    /// Its signature doesn't satisfy the requirement: signed ad hoc, by another team, with Apple
    /// Development, or not at all.
    case notSignedByTheDeveloper
    /// The official build, but this Info.plist key is there and can't be used: the site isn't an
    /// https origin, or the keys aren't all usable.
    case unusableSetting(String)

    public var logDescription: String {
        switch self {
        case .otherBundleIdentifier: return "its bundle identifier isn’t \(OfficialBuild.bundleIdentifier)"
        case .notSignedByTheDeveloper: return "it isn’t signed with the Developer ID that signs Tactile’s releases"
        case .unusableSetting(let key): return "its Info.plist’s \(key) can’t be used"
        }
    }
}

/// An Info.plist key whose value is there but can't be used.
public struct UnusableUpdateSetting: Error, Equatable, Sendable {
    public let key: String

    public init(key: String) {
        self.key = key
    }
}
