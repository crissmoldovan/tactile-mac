import Foundation
import TactileUpdates

/// Whether a built app's Info.plist gives the official build the update settings a release needs:
/// it trusts the key the release is signed with, under its keyId, and asks the official site. The
/// plist is read by the app's own code (`UpdateSettings.read`), so what passes here is exactly what
/// the app will trust. Both values must be in the plist itself: without them the app would fall
/// back to what is compiled into it, which nothing here checks.
public enum UpdateSettingsCheck {
    public struct Failure: Error, Equatable {
        public let message: String
    }

    /// The site `text` names, if it is an https origin.
    public static func site(_ text: String) -> UpdateSite? {
        UpdateSite(base: text, allowingHTTPOnThisMac: false)
    }

    /// One line saying what the app trusts and asks, or a failure saying why it won't do.
    public static func check(app: URL, keyID: String, publicKey: String, site: UpdateSite) throws -> String {
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw Failure(message: "could not read \(plistURL.path).") }

        for key in [UpdateSettings.baseURLKey, UpdateSettings.keysKey] {
            let value = info[key]
            if value == nil || (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
                throw Failure(message: "the app’s Info.plist names no \(key) (its build setting is unset), so it would use what is compiled in instead.")
            }
        }

        let settings: UpdateSettings
        switch UpdateSettings.read(info: info) {
        case .success(let read): settings = read
        case .failure(let unusable):
            throw Failure(message: "the app’s Info.plist \(unusable.key) can’t be used, so updates would be off in this build: “\(info[unusable.key] ?? "")”.")
        }

        let trusted = settings.keys.keys.sorted()
        guard let trustedKey = settings.keys[keyID] else {
            throw Failure(message: "the app doesn’t trust \(keyID): its Info.plist trusts only \(trusted.joined(separator: ", ")). Add \(keyID) to TACTILE_UPDATE_KEYS (Config/Updates.xcconfig).")
        }
        guard trustedKey == publicKey.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw Failure(message: "the app’s Info.plist doesn’t trust \(keyID) with that public key: it has \(trustedKey) under \(keyID).")
        }
        guard settings.site == site else {
            throw Failure(message: "the app’s Info.plist asks \(settings.site.base.absoluteString) for updates, not \(site.base.absoluteString).")
        }
        return "Info.plist: trusts \(keyID) (\(trustedKey)) among \(trusted.joined(separator: ", ")), and asks \(settings.site.base.absoluteString)."
    }
}
