// The report's zip: its files written to a temporary folder, zipped there with `ditto`, read back,
// and the folder removed; trimmed until it is within what tactilemac.com takes.

import Foundation

/// Zips a folder's contents, at the zip's root.
public protocol SupportZipping: Sendable {
    /// Zips the contents of `folder` into the file `zip`, which must not exist yet. True when it worked.
    func zip(folder: URL, to zip: URL) async -> Bool
}

/// `/usr/bin/ditto -c -k --norsrc --noextattr --noacl <folder> <zip>`: the folder's contents at the
/// zip's root (no `--keepParent`), with no resource forks, extended attributes or ACLs, so no `._`
/// entries, which tactilemac.com refuses.
public struct DittoZipper: SupportZipping {
    public init() {}

    public static func arguments(folder: URL, zip: URL) -> [String] {
        ["-c", "-k", "--norsrc", "--noextattr", "--noacl", folder.path, zip.path]
    }

    public func zip(folder: URL, to zip: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = Self.arguments(folder: folder, zip: zip)
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus == 0) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: false)
            }
        }
    }
}

/// A report's zip, and the files it holds, as the sheet lists them.
public struct SupportArchive: Equatable, Sendable {
    public var data: Data
    public var files: [SupportFile]
    /// The raw reports kept of each step, and the log's lines when it was trimmed.
    public var reportsPerStep: Int
    public var logLines: Int?

    public init(data: Data, files: [SupportFile], reportsPerStep: Int, logLines: Int?) {
        self.data = data
        self.files = files
        self.reportsPerStep = reportsPerStep
        self.logLines = logLines
    }
}

public enum SupportArchiveFailure: Error, Equatable, Sendable {
    /// The temporary folder or a file in it couldn't be written, or the zip read back.
    case couldNotWrite
    case couldNotZip
    /// Even with every raw report and every log line left out, it is larger than tactilemac.com takes.
    case tooLarge
}

/// Makes a report's zip.
public enum SupportArchiver {
    /// The largest zip tactilemac.com takes: 2 MiB.
    public static let maxZipBytes = 2 * 1024 * 1024
    /// What the zip may unpack to, at most: 8 MiB.
    public static let maxUnpackedBytes = 8 * 1024 * 1024

    /// How much of the raw reports and the log is kept.
    public struct Trim: Equatable, Sendable {
        public var reportsPerStep: Int
        /// Nil for every line.
        public var logLines: Int?
    }

    /// Tried in order until one fits: every raw report kept, then fewer, then none; then the log cut.
    public static let trims: [Trim] = [
        Trim(reportsPerStep: SupportReport.reportsPerStep, logLines: nil),
        Trim(reportsPerStep: 100, logLines: nil),
        Trim(reportsPerStep: 50, logLines: nil),
        Trim(reportsPerStep: 20, logLines: nil),
        Trim(reportsPerStep: 0, logLines: nil),
        Trim(reportsPerStep: 0, logLines: 1000),
        Trim(reportsPerStep: 0, logLines: 200),
        Trim(reportsPerStep: 0, logLines: 0),
    ]

    /// The report's files (`SupportReport.files`) zipped, at the first of `trims` whose files unpack to
    /// at most `maxUnpackedBytes` and whose zip is at most `maxZipBytes`. Each try is made in a new
    /// folder in `temporary`, removed before this returns, whatever happened.
    public static func make(_ input: SupportReportInput, zipper: SupportZipping = DittoZipper(),
                            temporary: URL = FileManager.default.temporaryDirectory) async -> Result<SupportArchive, SupportArchiveFailure> {
        for trim in trims {
            let files = SupportReport.files(input, reportsPerStep: trim.reportsPerStep, logLines: trim.logLines)
            guard files.reduce(0, { $0 + $1.size }) <= maxUnpackedBytes else { continue }
            switch await zip(files, zipper: zipper, temporary: temporary) {
            case .success(let data) where data.count <= maxZipBytes:
                return .success(SupportArchive(data: data, files: files, reportsPerStep: trim.reportsPerStep, logLines: trim.logLines))
            case .success:
                continue
            case .failure(let failure):
                return .failure(failure)
            }
        }
        return .failure(.tooLarge)
    }

    /// Writes `files` into a new folder, zips its contents, reads the zip, and removes the folder.
    private static func zip(_ files: [SupportFile], zipper: SupportZipping, temporary: URL) async -> Result<Data, SupportArchiveFailure> {
        let manager = FileManager.default
        let work = temporary.appendingPathComponent("TactileReport-\(UUID().uuidString)", isDirectory: true)
        let folder = work.appendingPathComponent("report", isDirectory: true)
        let zip = work.appendingPathComponent("report.zip")
        defer { try? manager.removeItem(at: work) }
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            for file in files {
                let url = folder.appendingPathComponent(file.name)
                try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try file.data.write(to: url)
            }
        } catch {
            return .failure(.couldNotWrite)
        }
        guard await zipper.zip(folder: folder, to: zip) else { return .failure(.couldNotZip) }
        guard let data = try? Data(contentsOf: zip) else { return .failure(.couldNotWrite) }
        return .success(data)
    }
}
