// The tests' wall-clock limits. On a run of one's own they are as written. On a CI runner, a shared
// machine whose speed varies from one minute to the next, they have headroom, so a test fails for
// what it measures and not for a busy neighbour (CUE-1297).

import Foundation

public enum TestTiming {
    /// How much longer a wait or a duration may take in CI.
    public static let ciFactor = 5.0
    /// In CI, a cost that mustn't grow may be at least this many times its first value…
    public static let ciRatio = 2.5
    /// …and this many milliseconds more, so a median of a fraction of a millisecond can't fail on noise.
    public static let ciMarginMS = 0.25

    /// Whether the tests run on a CI runner: `GITHUB_ACTIONS` or `CI` set to anything but empty,
    /// "false" or "0".
    public static func isCI(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        ["GITHUB_ACTIONS", "CI"].contains { name in
            guard let value = environment[name]?.lowercased(), !value.isEmpty else { return false }
            return value != "false" && value != "0"
        }
    }

    /// A wall-clock limit for a wait or a duration: `seconds` on a run of one's own, `ciFactor` times
    /// that in CI.
    public static func limit(_ seconds: TimeInterval,
                             _ environment: [String: String] = ProcessInfo.processInfo.environment) -> TimeInterval {
        isCI(environment) ? seconds * ciFactor : seconds
    }

    /// The most a cost may come to, from `early`, when it mustn't grow: `ratio × early + margin` on a
    /// run of one's own; in CI at least `ciRatio × early + ciMarginMS`. A cost that grows with what is
    /// measured, several times as much, still exceeds it.
    public static func costBound(early: Double, ratio: Double, margin: Double,
                                 _ environment: [String: String] = ProcessInfo.processInfo.environment) -> Double {
        guard isCI(environment) else { return ratio * early + margin }
        return max(ratio, ciRatio) * early + max(margin, ciMarginMS)
    }
}
