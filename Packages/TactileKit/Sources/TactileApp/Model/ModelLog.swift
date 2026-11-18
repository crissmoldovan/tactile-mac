// Where the model and the pipelines write to the unified log.

import os

/// The model's log: subsystem `com.crissmoldovan.tactile`, category `model`. Names of touchscreens
/// and displays are written as public, so the log can be read without a profile.
///
/// It writes nothing until it is turned on, which the app's model does when it is made (see
/// `TactileModel`'s `logs`): a model or a pipeline made in a test logs nothing, so a test run
/// doesn't bury the app's own lines under the subsystem.
enum ModelLog {
    private(set) static var model = Logger(.disabled)

    /// On for the app; off, the default, for tests.
    static func set(on: Bool) {
        model = on ? Logger(subsystem: "com.crissmoldovan.tactile", category: "model") : Logger(.disabled)
    }
}
