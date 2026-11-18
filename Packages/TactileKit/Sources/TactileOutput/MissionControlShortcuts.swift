import Foundation

/// The Mission Control keyboard shortcuts that swipes post.
public enum MissionControlShortcuts {

    /// Their IDs in `com.apple.symbolichotkeys`: Mission Control (32), App Exposé (33), and the
    /// desktop to the left (79) and to the right (81).
    static let ids = ["32", "33", "79", "81"]

    /// True unless one of them is turned off. A missing entry is the system default, which is on.
    public static func allEnabled(in hotkeys: [String: Any]?) -> Bool {
        ids.allSatisfy { id in
            guard let entry = hotkeys?[id] as? [String: Any], let enabled = entry["enabled"] as? Bool else { return true }
            return enabled
        }
    }

    public static func areEnabled() -> Bool {
        allEnabled(in: UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys"))
    }
}
