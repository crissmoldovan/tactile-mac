// The checks after the download, in the updates contract's order (2 to 5; the first is made
// before downloading, by `UpdateInstaller`).

import CryptoKit
import Foundation

/// Unzipping the archive.
public protocol ArchiveUnpacking: Sendable {
    /// Unzips `archive` into `folder`, which exists and is empty. True when it succeeded.
    func unpack(_ archive: URL, into folder: URL) async -> Bool
}

/// Checking an app's code signature.
public protocol CodeSignatureChecking: Sendable {
    /// Whether the app at `app` is validly signed and satisfies the requirement.
    func isValid(_ app: URL) -> Bool
}

/// What an app's `Info.plist` says, as far as the updater needs it.
public struct BundleInfo: Equatable, Sendable {
    public var identifier: String?
    public var version: String?
    public var build: String?
    public var executable: String?

    public init(identifier: String?, version: String?, build: String?, executable: String?) {
        self.identifier = identifier
        self.version = version
        self.build = build
        self.executable = executable
    }

    /// The `Contents/Info.plist` of the app at `app`, read directly (not through `Bundle`, which
    /// caches), or nil when it can't be read.
    public static func read(app: URL) -> BundleInfo? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return BundleInfo(
            identifier: dictionary["CFBundleIdentifier"] as? String,
            version: dictionary["CFBundleShortVersionString"] as? String,
            build: dictionary["CFBundleVersion"] as? String,
            executable: dictionary["CFBundleExecutable"] as? String)
    }
}

/// An update that passed every check: the unpacked app, and what its `Info.plist` says.
public struct VerifiedUpdate: Equatable, Sendable {
    public var app: URL
    public var info: BundleInfo
}

/// Checks 2 to 5 of the updates contract on a downloaded archive, in order, stopping at the first
/// that fails.
public struct UpdateVerifier: Sendable {
    /// The one thing the archive holds.
    public static let appName = "Tactile.app"

    public var trust: UpdateTrust
    public var unpacker: ArchiveUnpacking
    public var codeSignature: CodeSignatureChecking

    public init(trust: UpdateTrust, unpacker: ArchiveUnpacking, codeSignature: CodeSignatureChecking) {
        self.trust = trust
        self.unpacker = unpacker
        self.codeSignature = codeSignature
    }

    /// The checks on the archive at `archive`, for `offer`, with the app running now at `running`;
    /// the archive is unpacked into `folder`, made here.
    public func verify(_ archive: URL, offer: UpdateOffer, running: VersionAndBuild, unpackingInto folder: URL)
        async -> Result<VerifiedUpdate, UpdateFailure>
    {
        // 2. The size, before reading a byte; then the SHA-256.
        let size = (try? FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? Int) ?? -1
        if let failure = Self.checkSize(size, offer: offer) { return .failure(failure) }
        guard let data = try? Data(contentsOf: archive, options: .mappedIfSafe) else { return .failure(.downloadFailed) }
        if let failure = Self.checkSizeAndDigest(data, offer: offer) { return .failure(failure) }
        // 3. The update signature.
        if let failure = checkSignature(data, offer: offer) { return .failure(failure) }
        // 4. Unzipped, one Tactile.app, signed with the Developer ID.
        let app: URL
        switch await unpack(archive, into: folder) {
        case .success(let unpacked): app = unpacked
        case .failure(let failure): return .failure(failure)
        }
        guard codeSignature.isValid(app) else { return .failure(.codeSignatureInvalid) }
        // 5. The version offered, and newer than this one.
        let info = BundleInfo.read(app: app)
        if let failure = Self.checkVersion(info, offer: offer, running: running) { return .failure(failure) }
        guard let info else { return .failure(.versionMismatch) }
        return .success(VerifiedUpdate(app: app, info: info))
    }

    // MARK: - The checks, one by one

    static func checkSize(_ size: Int, offer: UpdateOffer) -> UpdateFailure? {
        size == offer.archive.size ? nil : .sizeMismatch(expected: offer.archive.size, actual: size)
    }

    /// Check 2: the length of `data`, then its SHA-256 in lowercase hexadecimal.
    public static func checkSizeAndDigest(_ data: Data, offer: UpdateOffer) -> UpdateFailure? {
        if let failure = checkSize(data.count, offer: offer) { return failure }
        return sha256(data) == offer.archive.sha256 ? nil : .digestMismatch
    }

    /// Check 3: the signature, with the trusted key the answer names.
    public func checkSignature(_ data: Data, offer: UpdateOffer) -> UpdateFailure? {
        switch trust.verify(signature: offer.archive.signature, over: data, keyID: offer.archive.keyID) {
        case .valid: return nil
        case .unknownKey: return .unknownKey(offer.archive.keyID)
        case .invalidSignature: return .badSignature
        }
    }

    /// The first part of check 4: unzipped into `folder`, the archive holds `Tactile.app` and nothing
    /// else, a real folder rather than a link.
    func unpack(_ archive: URL, into folder: URL) async -> Result<URL, UpdateFailure> {
        let files = FileManager.default
        do {
            if files.fileExists(atPath: folder.path) {
                try files.removeItem(at: folder)
            }
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return .failure(.couldNotPrepare)
        }
        guard await unpacker.unpack(archive, into: folder) else { return .failure(.unpackFailed) }
        guard let app = Self.singleApp(in: folder) else { return .failure(.notOneApp) }
        return .success(app)
    }

    /// `Tactile.app` in `folder` when it is the only thing there (hidden files count) and a folder
    /// itself, not a link to one.
    public static func singleApp(in folder: URL) -> URL? {
        let files = FileManager.default
        guard let names = try? files.contentsOfDirectory(atPath: folder.path), names == [appName] else { return nil }
        let app = folder.appendingPathComponent(appName, isDirectory: true)
        guard let type = try? files.attributesOfItem(atPath: app.path)[.type] as? FileAttributeType,
              type == .typeDirectory
        else { return nil }
        return app
    }

    /// Check 5: the app's version and build are the ones offered, and newer than the running app's.
    public static func checkVersion(_ info: BundleInfo?, offer: UpdateOffer, running: VersionAndBuild) -> UpdateFailure? {
        guard let info, let versionText = info.version, let buildText = info.build,
              let version = ReleaseVersion(versionText), let build = VersionAndBuild.build(buildText),
              version == offer.version, build == offer.build
        else { return .versionMismatch }
        return VersionAndBuild(version: version, build: build) > running ? nil : .notNewer
    }

    /// The SHA-256 of `data`, in lowercase hexadecimal.
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
