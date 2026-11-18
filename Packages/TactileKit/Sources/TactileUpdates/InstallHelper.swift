// Starting the helper script so that it outlives Tactile.

import Foundation

/// Starting the helper script, detached from Tactile.
public protocol InstallHelperLaunching: Sendable {
    /// Starts `/bin/sh <script>` so that it keeps running after Tactile quits; throws when it
    /// couldn't be started.
    func launch(_ script: URL) throws
}

/// Starts the helper through `/bin/sh` with `Process`: a first shell turns job control on
/// (`set -m`), which puts the helper, started in the background, in a process group of its own,
/// and ends at once. So nothing that ends Tactile's process group ends the helper, and its parent
/// is gone before Tactile quits. The helper reads nothing and writes only to its own log.
public struct DetachedShellLauncher: InstallHelperLaunching {
    /// The first shell's command; `$0` is the script.
    public static let command = #"set -m; /bin/sh "$0" </dev/null >/dev/null 2>&1 &"#

    public init() {}

    public func launch(_ script: URL) throws {
        // The script fails in the background, where nothing would see it: make sure it is there.
        guard FileManager.default.isReadableFile(atPath: script.path) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", Self.command, script.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw CocoaError(.executableLoad)
        }
    }
}
