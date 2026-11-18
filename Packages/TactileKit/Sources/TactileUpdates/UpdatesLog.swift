// Where the updater writes to the unified log.

import os

/// The updater's log: subsystem `com.crissmoldovan.tactile`, category `updates`. Versions, addresses
/// and the reasons a check or an install stopped are written as public, so the log can be read
/// without a profile. Nothing secret passes through the updater: the site needs no token.
///
/// It writes nothing until it is turned on, which the app does when it starts the updater: an
/// updater made in a test logs nothing, as `ModelLog` doesn't for a model made in a test.
public enum UpdatesLog {
    public private(set) static var log = Logger(.disabled)
    /// Whether it writes: only once the app has turned it on.
    public private(set) static var isOn = false

    /// On for the app; off, the default, for tests.
    public static func set(on: Bool) {
        isOn = on
        log = on ? Logger(subsystem: "com.crissmoldovan.tactile", category: "updates") : Logger(.disabled)
    }
}
