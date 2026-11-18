// When Tactile checks by itself, and the clock and the preferences it reads.

import Foundation

/// The time, and waiting: the system's in the app, a hand-turned one in the tests.
public protocol UpdateClock: Sendable {
    func now() -> Date
    /// Waits `seconds`; throws when the waiting task is cancelled.
    func sleep(seconds: TimeInterval) async throws
}

/// The system's clock. `Task.sleep` counts on through the Mac's sleep; the schedule compares dates
/// after every nap anyway, so a check that fell due while the Mac slept happens soon after it wakes.
public struct SystemUpdateClock: UpdateClock {
    public init() {}

    public func now() -> Date { Date() }

    public func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}

/// When the automatic checks happen: one a minute after launch, then one every 24 hours, only while
/// Check for updates automatically is on. A check of any kind counts (a manual one too), so the next
/// automatic one is 24 hours after the last. One that failed (offline, the site down) is tried again
/// after an hour rather than a day.
public enum UpdateSchedule {
    public static let afterLaunch: TimeInterval = 60
    public static let interval: TimeInterval = 24 * 60 * 60
    public static let retryAfterFailure: TimeInterval = 60 * 60
    /// The longest the schedule sleeps before it looks at the clock again.
    public static let longestNap: TimeInterval = 15 * 60

    /// When the next automatic check is due, or nil while automatic checks are off.
    public static func nextCheck(automatic: Bool, launchedAt: Date, lastAttempt: Date?, lastAttemptFailed: Bool) -> Date? {
        guard automatic else { return nil }
        guard let lastAttempt else { return launchedAt.addingTimeInterval(afterLaunch) }
        return lastAttempt.addingTimeInterval(lastAttemptFailed ? retryAfterFailure : interval)
    }

    /// How long to sleep before looking again: until the check is due, at most `longestNap`.
    public static func nap(until due: Date?, now: Date) -> TimeInterval {
        guard let due else { return longestNap }
        return min(max(due.timeIntervalSince(now), 0), longestNap)
    }
}

/// What the updater keeps between launches, and the one setting that points it elsewhere.
public protocol UpdatePreferences: AnyObject {
    /// Check for updates automatically; on unless the person turned it off.
    var checksAutomatically: Bool { get set }
    /// When a check last got an answer from the site.
    var lastChecked: Date? { get set }
    /// The user default `TactileUpdateBaseURL`, if set.
    var baseURLOverride: String? { get }
}

/// The preferences in the app's user defaults.
public final class UserDefaultsUpdatePreferences: UpdatePreferences {
    public static let checksAutomaticallyKey = "TactileCheckForUpdatesAutomatically"
    public static let lastCheckedKey = "TactileUpdateLastChecked"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var checksAutomatically: Bool {
        get { defaults.object(forKey: Self.checksAutomaticallyKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.checksAutomaticallyKey) }
    }

    public var lastChecked: Date? {
        get { defaults.object(forKey: Self.lastCheckedKey) as? Date }
        set { defaults.set(newValue, forKey: Self.lastCheckedKey) }
    }

    public var baseURLOverride: String? {
        defaults.string(forKey: UpdateSite.overrideKey)
    }
}
