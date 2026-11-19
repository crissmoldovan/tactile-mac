// The tests' wall-clock limits. On a run of one's own they are as written. On a CI runner, a shared
// machine whose speed varies from one minute to the next, they have headroom, so a test fails for
// what it measures and not for a busy neighbour (CUE-1297). A measurement that passes only with
// that headroom leaves a warning on the run, so it still shows on the PR.

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

    // MARK: - What passes only with CI's headroom

    /// In CI, the GitHub Actions warning for a measurement that passes only thanks to the headroom:
    /// over the bound a run of one's own holds it to (`strict`), and within CI's (`ci`). It names
    /// the test and the three numbers, so what only a run of one's own would catch still shows on
    /// the PR. Nil on a run of one's own, within `strict`, and over `ci`, where the test fails anyway.
    public static func headroomWarning(_ test: String, measured: Double, strict: Double, ci: Double, unit: String,
                                       _ environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        guard isCI(environment), measured > strict, measured <= ci else { return nil }
        func amount(_ value: Double) -> String { String(format: "%.3f", value) + " " + unit }
        let message = "\(test): \(amount(measured)), over the strict bound of \(amount(strict)), within CI's \(amount(ci)). "
            + "A run of one's own would fail it."
        return "::warning title=Timing headroom::" + escaped(message)
    }

    /// `headroomWarning` for a cost bounded by `costBound(early:ratio:margin:)`, in milliseconds.
    public static func costWarning(_ test: String, cost: Double, early: Double, ratio: Double, margin: Double,
                                   _ environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        headroomWarning(test, measured: cost, strict: costBound(early: early, ratio: ratio, margin: margin, [:]),
                        ci: costBound(early: early, ratio: ratio, margin: margin, environment), unit: "ms", environment)
    }

    /// `headroomWarning` for a wait or a duration bounded by `limit(seconds)`.
    public static func waitWarning(_ test: String, seconds measured: TimeInterval, limit seconds: TimeInterval,
                                   _ environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        headroomWarning(test, measured: measured, strict: seconds, ci: limit(seconds, environment), unit: "s", environment)
    }

    /// Writes the warning, if there is one, to the log, where GitHub Actions makes it an annotation.
    /// It never fails the test.
    public static func warn(_ warning: String?) {
        guard let warning else { return }
        print(warning)
    }

    /// Waits, 5 ms at a time, until `condition` holds or `limit(seconds)` has passed, and warns when
    /// it held only after `seconds` (`waitWarning`). Returns whether it held: the test asserts what
    /// it waited for.
    @MainActor
    @discardableResult
    public static func waitUntil(_ test: String, seconds: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let start = Date()
        let deadline = start.addingTimeInterval(limit(seconds))
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        guard condition() else { return false }
        warn(waitWarning(test, seconds: Date().timeIntervalSince(start), limit: seconds))
        return true
    }

    /// A workflow command's message: `%`, carriage returns and newlines escaped.
    private static func escaped(_ message: String) -> String {
        message.replacingOccurrences(of: "%", with: "%25").replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
    }
}
