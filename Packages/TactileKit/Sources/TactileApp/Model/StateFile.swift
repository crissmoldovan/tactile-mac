// The state file: what the interface shows, on disk, for scripts and for diagnostics.

import Foundation

/// `~/Library/Application Support/Tactile/state.json` in the app: the current snapshot as JSON,
/// pretty-printed with sorted keys, written atomically whenever it changes and removed when Tactile
/// quits. Nothing reads it back.
struct StateFile {
    let url: URL

    func write(_ snapshot: AppSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func remove() throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            // Already gone.
        }
    }
}
