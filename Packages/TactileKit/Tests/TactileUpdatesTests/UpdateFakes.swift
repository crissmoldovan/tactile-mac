// Fakes and fixtures for the updater's tests. Nothing here touches the network, a Keychain item or
// anything outside the temporary folders the tests make and remove.

import CryptoKit
import Foundation
import XCTest

@testable import TactileUpdates

extension XCTestCase {
    /// A new, empty folder under the temporary directory (its symbolic links resolved), removed when
    /// the test ends, even one the test made read-only.
    func makeTemporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("TactileUpdatesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock {
            if let walker = FileManager.default.enumerator(atPath: folder.path) {
                for case let path as String in walker {
                    chmod(folder.appendingPathComponent(path).path, 0o755)
                }
            }
            chmod(folder.path, 0o755)
            try? FileManager.default.removeItem(at: folder)
        }
        return folder
    }

    /// A stand-in app bundle at `url`: an `Info.plist` with these values, and an executable file.
    @discardableResult
    func makeBundle(at url: URL, identifier: String = "com.crissmoldovan.tactile", version: String?, build: String?,
                    executable: String = "Tactile", marker: String? = nil) throws -> URL {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleExecutable": executable]
        info["CFBundleShortVersionString"] = version
        info["CFBundleVersion"] = build
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: contents.appendingPathComponent("MacOS/\(executable)"))
        if let marker {
            try Data(marker.utf8).write(to: contents.appendingPathComponent("marker"))
        }
        return url
    }

    /// What a stand-in bundle's marker says.
    func marker(of app: URL) -> String? {
        (try? Data(contentsOf: app.appendingPathComponent("Contents/marker"))).flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// Values the tests share: a signing key made here, in memory, and offers signed with it.
enum Fixture {
    static let key = Curve25519.Signing.PrivateKey()
    static let keyID = "t1"
    static let trust = UpdateTrust(keys: [keyID: key.publicKey])
    static let site = UpdateSite.builtIn
    static let archiveBytes = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 3) })
    /// CryptoKit's Ed25519 signatures are randomised: signed once, so offers made for the same bytes
    /// are equal.
    static let archiveSignature = try! key.signature(for: archiveBytes)
    static let published = "2026-11-18T10:00:00Z"

    static func archiveURL(_ version: String = "0.6.0") -> URL {
        URL(string: "https://tactilemac.com/api/mac/archive/\(version)")!
    }

    /// The running app: 0.5.0 (300) on macOS 15.0, at `bundle`.
    static func running(at bundle: URL = URL(fileURLWithPath: "/Applications/Tactile.app"), version: String = "0.5.0",
                        build: String = "300", system: SystemVersion = SystemVersion(major: 15)) -> RunningApp {
        RunningApp(version: version, build: build, bundleURL: bundle, processID: 4242, systemVersion: system)
    }

    /// An offer for `bytes`, signed with the fixture key unless a signature is given.
    static func offer(version: String = "0.6.0", build: Int = 412, minimumSystem: String = "14.0",
                      bytes: Data = archiveBytes, url: URL? = nil, size: Int? = nil, sha256: String? = nil,
                      signature: Data? = nil, keyID: String = keyID, notes: String = "Faster scrolling.\nA fix.") -> UpdateOffer {
        UpdateOffer(
            version: ReleaseVersion(version)!, build: build, minimumSystemVersion: SystemVersion(minimumSystem)!,
            publishedAt: UpdateOffer.date(published)!, notes: notes,
            archive: .init(url: url ?? archiveURL(version), size: size ?? bytes.count,
                           sha256: sha256 ?? UpdateVerifier.sha256(bytes),
                           signature: signature ?? (bytes == archiveBytes ? archiveSignature : try! key.signature(for: bytes)),
                           keyID: keyID))
    }

    /// The answer the site sends for `offer`, as JSON, with `changes` applied to its object first.
    static func answer(_ offer: UpdateOffer = offer(), changes: (inout [String: Any]) -> Void = { _ in }) -> Data {
        var object: [String: Any] = [
            "version": offer.version.description, "build": offer.build,
            "minimumSystemVersion": offer.minimumSystemVersion.description, "publishedAt": published,
            "notes": offer.notes,
            "archive": [
                "url": offer.archive.url.absoluteString, "size": offer.archive.size, "sha256": offer.archive.sha256,
                "signature": offer.archive.signature.base64EncodedString(), "keyId": offer.archive.keyID,
            ] as [String: Any],
        ]
        changes(&object)
        return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

/// The network as the tests have it: canned answers, redirects followed as URLSession follows them
/// (each hop offered to `allowingRedirect`, a refused one ending the request with a 302), and every
/// request recorded.
final class FakeNetwork: UpdateNetwork, @unchecked Sendable {
    struct Response {
        var status: Int
        var body: Data
        /// The addresses redirected through, in order, before the answer.
        var redirects: [URL] = []
    }

    private let lock = NSLock()
    private var _fetchResponse: Result<Response, Error>
    private var _downloadResponse: Result<Response, Error>
    private var _fetched: [URL] = []
    private var _downloaded: [URL] = []
    /// Called as each request starts: the tests' clock reads the time of each check.
    var onRequest: (@Sendable (URL) -> Void)?

    init(answer: Result<Response, Error> = .success(Response(status: 200, body: Fixture.answer())),
         download: Result<Response, Error> = .success(Response(status: 200, body: Fixture.archiveBytes))) {
        _fetchResponse = answer
        _downloadResponse = download
    }

    var fetchResponse: Result<Response, Error> {
        get { lock.withLock { _fetchResponse } }
        set { lock.withLock { _fetchResponse = newValue } }
    }
    var downloadResponse: Result<Response, Error> {
        get { lock.withLock { _downloadResponse } }
        set { lock.withLock { _downloadResponse = newValue } }
    }
    var fetched: [URL] { lock.withLock { _fetched } }
    var downloaded: [URL] { lock.withLock { _downloaded } }

    func fetch(_ url: URL, allowingRedirect: @escaping @Sendable (URL) -> Bool) async throws -> (Data, HTTPResult) {
        lock.withLock { _fetched.append(url) }
        onRequest?(url)
        let response = try fetchResponse.get()
        let (final, refused) = follow(url, response.redirects, allowingRedirect)
        return refused ? (Data(), HTTPResult(status: 302, url: final)) : (response.body, HTTPResult(status: response.status, url: final))
    }

    func download(_ url: URL, to destination: URL, allowingRedirect: @escaping @Sendable (URL) -> Bool) async throws -> HTTPResult {
        lock.withLock { _downloaded.append(url) }
        onRequest?(url)
        let response = try downloadResponse.get()
        let (final, refused) = follow(url, response.redirects, allowingRedirect)
        try (refused ? Data() : response.body).write(to: destination, options: .withoutOverwriting)
        return HTTPResult(status: refused ? 302 : response.status, url: final)
    }

    private func follow(_ url: URL, _ redirects: [URL], _ allow: (URL) -> Bool) -> (URL, refused: Bool) {
        var current = url
        for hop in redirects {
            guard allow(hop) else { return (current, true) }
            current = hop
        }
        return (current, false)
    }
}

/// A clock turned by hand: sleeping moves it on at once, and sleeping past `end` throws, as a
/// cancelled task would, which ends the schedule.
final class FakeClock: UpdateClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private let end: Date
    private var _naps: [TimeInterval] = []

    init(start: Date = Date(timeIntervalSince1970: 1_800_000_000), runFor: TimeInterval = 10 * 24 * 3600) {
        current = start
        end = start.addingTimeInterval(runFor)
    }

    var naps: [TimeInterval] { lock.withLock { _naps } }

    func now() -> Date { lock.withLock { current } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }

    func sleep(seconds: TimeInterval) async throws {
        let past = lock.withLock { () -> Bool in
            guard current.addingTimeInterval(seconds) <= end else { return true }
            current = current.addingTimeInterval(seconds)
            _naps.append(seconds)
            return false
        }
        if past { throw CancellationError() }
        await Task.yield()
    }
}

/// Preferences kept in memory.
final class MemoryPreferences: UpdatePreferences {
    var checksAutomatically: Bool
    var lastChecked: Date?
    var baseURLOverride: String?

    init(checksAutomatically: Bool = true, lastChecked: Date? = nil, baseURLOverride: String? = nil) {
        self.checksAutomatically = checksAutomatically
        self.lastChecked = lastChecked
        self.baseURLOverride = baseURLOverride
    }
}

/// Unzipping as the tests want it: by default, a `Tactile.app` with the offer's version and build.
struct FakeUnpacker: ArchiveUnpacking {
    var make: @Sendable (URL) throws -> Bool

    static func app(version: String? = "0.6.0", build: String? = "412", executable: String = "Tactile") -> FakeUnpacker {
        FakeUnpacker { folder in
            let app = folder.appendingPathComponent("Tactile.app/Contents", isDirectory: true)
            try FileManager.default.createDirectory(at: app.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
            var info: [String: Any] = ["CFBundleIdentifier": "com.crissmoldovan.tactile", "CFBundleExecutable": executable]
            info["CFBundleShortVersionString"] = version
            info["CFBundleVersion"] = build
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: app.appendingPathComponent("Info.plist"))
            return true
        }
    }

    func unpack(_ archive: URL, into folder: URL) async -> Bool {
        (try? make(folder)) ?? false
    }
}

/// A code-signature check that says what it is told, and records what it was asked about.
final class FakeCodeSignature: CodeSignatureChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var _checked: [URL] = []
    let valid: Bool

    init(valid: Bool = true) {
        self.valid = valid
    }

    var checked: [URL] { lock.withLock { _checked } }

    func isValid(_ app: URL) -> Bool {
        lock.withLock { _checked.append(app) }
        return valid
    }
}

/// A helper launcher that starts nothing, records the scripts, and fails when told to.
final class FakeHelper: InstallHelperLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private var _launched: [URL] = []
    var fails = false

    var launched: [URL] { lock.withLock { _launched } }

    func launch(_ script: URL) throws {
        if fails { throw CocoaError(.executableLoad) }
        lock.withLock { _launched.append(script) }
    }
}

extension InstallLocation {
    /// A location where installing is allowed.
    static let allowed = InstallLocation(isTranslocated: { _ in false }, isWritable: { _ in true })
}
