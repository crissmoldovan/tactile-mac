// The folder an update is downloaded to, unpacked in, and installed from.

import Foundation

/// `~/Library/Caches/com.crissmoldovan.tactile/Updates/`: the download, the unpacked app, the
/// helper script and its log. Cleared before each download and after a failure; the helper removes
/// the download and the unpacked copy once it has finished, and leaves its script and log until the
/// next download, for reading what happened.
public struct UpdateCache: Equatable, Sendable {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// The app's own: `~/Library/Caches/com.crissmoldovan.tactile/Updates/`.
    public static var live: UpdateCache {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
        return UpdateCache(folder: caches.appendingPathComponent("com.crissmoldovan.tactile/Updates", isDirectory: true))
    }

    /// `Tactile-<version>.zip`, as the release names it.
    public func archive(for version: ReleaseVersion) -> URL {
        folder.appendingPathComponent("Tactile-\(version).zip")
    }

    /// Where the archive is unzipped.
    public var unpacked: URL { folder.appendingPathComponent("Unpacked", isDirectory: true) }
    /// The helper script.
    public var script: URL { folder.appendingPathComponent("install.sh") }
    /// What the helper did, line by line.
    public var log: URL { folder.appendingPathComponent("install.log") }

    /// Empties the folder: everything in it is removed, and it is made again, readable only by this
    /// account.
    public func clear() throws {
        let files = FileManager.default
        if files.fileExists(atPath: folder.path) {
            try files.removeItem(at: folder)
        }
        try files.createDirectory(at: folder, withIntermediateDirectories: true,
                                  attributes: [.posixPermissions: 0o700])
    }
}
