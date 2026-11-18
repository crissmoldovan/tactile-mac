// Reading and writing the settings file.

import Foundation

/// Keeps `TactileSettings` in one JSON file, given by its URL. The app gives it
/// `~/Library/Application Support/Tactile/settings.json` and saves on every change.
///
/// A file Tactile can't use is never written over and never lost. It is set aside under a new name
/// beside it, defaults are used, and the caller is told, so that it can tell the person.
///
/// The store keeps nothing of the settings: `load` reads the file each time and `save` replaces it
/// whole. Two stores on one file don't coordinate; whichever saves last wins, and neither file is
/// ever half of each. Use a store from one thread at a time.
public final class SettingsStore {

    /// What `load` found.
    public enum LoadOutcome: Equatable {
        /// The file held settings this version can read, and they are the answer.
        case loaded
        /// Nothing is at the file's path, or a folder on the way to it is missing (or isn't a
        /// folder). The answer is the defaults, and nothing is written until `save`.
        case noFile
        /// What was at the path couldn't be used, and was renamed to this URL, beside it. The answer
        /// is the defaults.
        case setAside(URL)
        /// What was at the path couldn't be used, and couldn't be renamed either (its folder can't
        /// be written, say). It is left exactly as it is, and the answer is the defaults. `save`
        /// won't write over it: see `save`.
        case couldNotSetAside
    }

    /// The settings file.
    public let fileURL: URL

    /// The largest file `load` reads, in bytes: 1 MiB. Tactile writes a few kilobytes, even for
    /// many touchscreens; a file larger than this is set aside without being read.
    static let mostBytes = 1 << 20

    /// Whether the last `load` left a file it couldn't use where it was, so `save` must move it
    /// before writing.
    private var unusableFileInPlace = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The settings in the file, or the defaults, and what was found. Never throws or traps,
    /// whatever is at the path.
    ///
    /// - Settings this version can read: those, `.loaded`. A field that is missing or `null` takes
    ///   its default, and a field this version doesn't know is ignored (see `TactileSettings`).
    /// - Nothing there: the defaults, `.noFile`.
    /// - Anything else is set aside: a file that is empty, isn't JSON, is cut off, or is JSON of
    ///   another shape (a top level that isn't an object; `touchscreens` that isn't an object, or a
    ///   touchscreen in it that isn't one, `null` included); a value of the wrong type anywhere, or
    ///   a choice this version doesn't have (`"version": "1"`, `"isOn": "no"`); a `version` above
    ///   `currentVersion`; a file that can't be opened or read; a file larger than 1 MiB
    ///   (`mostBytes`), which is not read at all, whatever it holds; and a folder, pipe or anything
    ///   else that isn't a file. It is renamed beside itself to `<name>.broken`, or the first of
    ///   `<name>.broken-2`, `-3`… that nothing has, and the answer is the defaults,
    ///   `.setAside(new URL)`. The rename never moves anything already there, and nothing is copied
    ///   or deleted.
    /// - If that rename fails: the defaults, `.couldNotSetAside`, with the file left as it is. If
    ///   the file has gone by the time it is renamed: the defaults, `.noFile`.
    ///
    /// A `version` below `currentVersion`, even 0 or a negative one, isn't a reason to set a file
    /// aside: its settings load. A key given twice in one object is no reason either; one of the two
    /// is used.
    public func load() -> (settings: TactileSettings, outcome: LoadOutcome) {
        unusableFileInPlace = false
        switch read() {
        case .nothing:
            return (TactileSettings(), .noFile)
        case .contents(let data):
            if let settings = try? JSONDecoder().decode(TactileSettings.self, from: data) {
                return (settings, .loaded)
            }
        case .unusable:
            break
        }
        do {
            guard let url = try setAside() else { return (TactileSettings(), .noFile) }
            return (TactileSettings(), .setAside(url))
        } catch {
            unusableFileInPlace = true
            return (TactileSettings(), .couldNotSetAside)
        }
    }

    /// Writes `settings` to the file, replacing it whole, and creating its folder if it is missing.
    ///
    /// The file is written atomically: whatever happens, it is either the old file or the new one,
    /// never part of each. It is JSON, pretty-printed with sorted keys, so it reads easily and a
    /// change shows as a small diff. Keys are written as they are named: no key strategy, which would
    /// also rewrite the touchscreen IDs used as keys. The version written is always
    /// `TactileSettings.currentVersion`.
    ///
    /// If the last `load` couldn't set aside a file it couldn't use (`.couldNotSetAside`), this first
    /// sets aside whatever is at the path now, as `load` would have; if that still fails, it throws
    /// why, and writes nothing. So a file `load` couldn't use is never written over. (A store that
    /// hasn't loaded doesn't look before it saves.)
    ///
    /// Throws only when the file system refuses: the folder can't be created or written, say. Never
    /// because of what the settings hold.
    public func save(_ settings: TactileSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(settings)
        if unusableFileInPlace {
            _ = try setAside()
            unusableFileInPlace = false
        }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Private

    /// What is at the file's path.
    private enum Found {
        /// Nothing, or a folder on the way is missing or isn't a folder.
        case nothing
        /// A file, and what it holds.
        case contents(Data)
        /// Something that can't be read as a file.
        case unusable
    }

    /// Reads what is at the file's path, following a symbolic link. Only a regular file is read: a
    /// device such as `/dev/zero` would never end. It is opened without waiting, so a pipe left there
    /// can't stall the open, and its type is checked on what was opened.
    ///
    /// Only a file of at most `mostBytes` is read, so a large file (even a sparse one, which takes
    /// no room on the disk) can't take as much memory: one whose size is larger is not read at all,
    /// and one that grows past it while it is read is not read further. Either is `.unusable`.
    private func read() -> Found {
        var error: Int32 = 0
        let descriptor = fileURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                error = EINVAL
                return -1
            }
            let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
            if descriptor < 0 { error = errno }
            return descriptor
        }
        guard descriptor >= 0 else { return error == ENOENT || error == ENOTDIR ? .nothing : .unusable }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG,
            status.st_size <= off_t(Self.mostBytes)
        else { return .unusable }
        do {
            // One byte more than the most, to tell a file that has grown since `fstat`.
            var data = Data()
            while data.count <= Self.mostBytes,
                let chunk = try file.read(upToCount: Self.mostBytes + 1 - data.count), !chunk.isEmpty {
                data.append(chunk)
            }
            return data.count <= Self.mostBytes ? .contents(data) : .unusable
        } catch {
            return .unusable
        }
    }

    /// Renames whatever is at the file's path to the first of `<name>.broken`, `<name>.broken-2`,
    /// `<name>.broken-3`… that nothing has, and returns its new URL; `nil` if nothing was there.
    /// Throws why it couldn't be renamed.
    private func setAside() throws -> URL? {
        let folder = fileURL.deletingLastPathComponent()
        let name = fileURL.lastPathComponent
        for number in 1..<Int.max {
            let candidate = folder.appendingPathComponent(
                number == 1 ? "\(name).broken" : "\(name).broken-\(number)", isDirectory: false)
            let error = Self.move(fileURL, to: candidate)
            switch error {
            case 0: return candidate
            case EEXIST: continue
            case ENOENT, ENOTDIR: return nil
            default: throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO)
            }
        }
        throw POSIXError(.EEXIST)
    }

    /// Renames `source` to `destination` if nothing is at `destination`: 0, or the error number.
    /// `EEXIST` when something is there, even a symbolic link to nothing; it is never replaced.
    ///
    /// The check and the rename are one call where the file system can do both (APFS and HFS+ can).
    /// Elsewhere, the destination is looked at first and then the rename is made.
    private static func move(_ source: URL, to destination: URL) -> Int32 {
        source.withUnsafeFileSystemRepresentation { from in
            destination.withUnsafeFileSystemRepresentation { to in
                guard let from, let to else { return EINVAL }
                if renamex_np(from, to, UInt32(RENAME_EXCL)) == 0 { return 0 }
                let error = errno
                guard error == ENOTSUP || error == EINVAL else { return error }
                var status = stat()
                if lstat(to, &status) == 0 { return EEXIST }
                guard errno == ENOENT else { return errno }
                return rename(from, to) == 0 ? 0 : errno
            }
        }
    }
}
