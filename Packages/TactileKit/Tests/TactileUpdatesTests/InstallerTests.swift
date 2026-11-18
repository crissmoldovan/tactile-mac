import Foundation
import XCTest

@testable import TactileUpdates

/// Installing: where Tactile runs is checked first, then the archive's address (check 1); the update
/// folder is emptied before the download, which follows redirects only to the site and GitHub's
/// download hosts; after the other checks the helper script is written into the update folder and
/// started. Any failure empties the update folder and starts nothing.
final class InstallerTests: XCTestCase {

    private var root: URL!
    private var cache: UpdateCache!
    private var app: URL!

    override func setUpWithError() throws {
        root = try makeTemporaryFolder()
        cache = UpdateCache(folder: root.appendingPathComponent("Caches/Updates", isDirectory: true))
        app = try makeBundle(at: root.appendingPathComponent("Applications/Tactile.app"), version: "0.5.0", build: "300")
    }

    private func installer(network: FakeNetwork = FakeNetwork(), unpacker: FakeUnpacker = .app(),
                           code: FakeCodeSignature = FakeCodeSignature(), helper: FakeHelper = FakeHelper(),
                           location: InstallLocation = .allowed, trust: UpdateTrust = Fixture.trust) -> UpdateInstaller {
        UpdateInstaller(
            site: Fixture.site, network: network,
            verifier: UpdateVerifier(trust: trust, unpacker: unpacker, codeSignature: code),
            cache: cache, location: location, helper: helper, running: Fixture.running(at: app),
            token: { "abc123" })
    }

    private func run(_ installer: UpdateInstaller, _ offer: UpdateOffer = Fixture.offer()) async
        -> (Result<InstallPlan, UpdateFailure>, [InstallProgress])
    {
        let seen = ProgressLog()
        let result = await installer.run(offer, progress: { seen.add($0) })
        return (result, await seen.all)
    }

    /// What was left in the update folder.
    private var cacheContents: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: cache.folder.path).sorted()) ?? []
    }

    func testAnUpdateThatPassesStartsTheHelperWithItsScript() async throws {
        let network = FakeNetwork()
        let helper = FakeHelper()
        let (result, progress) = await run(installer(network: network, helper: helper))
        let plan = try result.get()
        XCTAssertEqual(progress, [.downloading, .verifying])
        XCTAssertEqual(network.downloaded.map(\.absoluteString), ["https://tactilemac.com/api/mac/archive/0.6.0"])
        XCTAssertEqual(helper.launched, [cache.script])
        XCTAssertEqual(plan.app, app)
        XCTAssertEqual(plan.newApp, cache.unpacked.appendingPathComponent("Tactile.app", isDirectory: true))
        XCTAssertEqual(plan.processID, 4242)
        XCTAssertEqual(plan.executable, "Tactile")
        XCTAssertEqual(plan.leftovers, [cache.archive(for: ReleaseVersion("0.6.0")!), cache.unpacked])
        XCTAssertEqual(plan.staged.lastPathComponent, ".Tactile.app.new-abc123")
        XCTAssertEqual(plan.aside.lastPathComponent, ".Tactile.app.replaced-abc123")
        let script = try String(contentsOf: cache.script, encoding: .utf8)
        XCTAssertEqual(script, InstallScript.text(for: plan))
        let permissions = try FileManager.default.attributesOfItem(atPath: cache.script.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o700)
        XCTAssertEqual(cacheContents, ["Tactile-0.6.0.zip", "Unpacked", "install.sh"])
        XCTAssertEqual(marker(of: app), nil, "the running app is untouched: the helper replaces it after Tactile quits")
    }

    func testTheUpdateFolderIsEmptiedBeforeTheDownload() async throws {
        try cache.clear()
        let stale = cache.folder.appendingPathComponent("Tactile-0.6.0.zip")
        try Data("stale".utf8).write(to: stale)
        try Data("old log".utf8).write(to: cache.log)
        let (result, _) = await run(installer())
        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(try Data(contentsOf: stale), Fixture.archiveBytes)
        XCTAssertFalse(cacheContents.contains("install.log"))
    }

    func testATranslocatedAppDownloadsNothing() async {
        let network = FakeNetwork()
        let location = InstallLocation(isTranslocated: { _ in true }, isWritable: { _ in true })
        let (result, progress) = await run(installer(network: network, location: location))
        XCTAssertEqual(result, .failure(.translocated))
        XCTAssertEqual(network.downloaded, [])
        XCTAssertEqual(progress, [])
    }

    func testAFolderThatCantBeWrittenDownloadsNothing() async {
        let network = FakeNetwork()
        let location = InstallLocation(isTranslocated: { _ in false }, isWritable: { _ in false })
        let (result, _) = await run(installer(network: network, location: location))
        XCTAssertEqual(result, .failure(.folderNotWritable(folder: app.deletingLastPathComponent().path)))
        XCTAssertEqual(network.downloaded, [])
    }

    /// Check 1, before anything is downloaded.
    func testAnArchiveNotOnTheSiteIsNeverDownloaded() async {
        for elsewhere in ["https://objects.githubusercontent.com/x/Tactile-0.6.0.zip", "https://evil.example/Tactile.zip",
                          "http://tactilemac.com/api/mac/archive/0.6.0"] {
            let network = FakeNetwork()
            let helper = FakeHelper()
            let (result, _) = await run(installer(network: network, helper: helper),
                                        Fixture.offer(url: URL(string: elsewhere)!))
            XCTAssertEqual(result, .failure(.archiveNotOnSite), elsewhere)
            XCTAssertEqual(network.downloaded, [], elsewhere)
            XCTAssertEqual(helper.launched, [])
        }
    }

    func testTheDownloadMayBeRedirectedToGitHubsDownloadHost() async throws {
        let network = FakeNetwork(download: .success(.init(
            status: 200, body: Fixture.archiveBytes,
            redirects: [URL(string: "https://release-assets.githubusercontent.com/github-production-release-asset/1?sig=x")!])))
        let (result, _) = await run(installer(network: network))
        XCTAssertNoThrow(try result.get())
    }

    func testADownloadRedirectedElsewhereIsRefused() async {
        for elsewhere in ["https://evil.example/Tactile.zip", "http://objects.githubusercontent.com/x",
                          "https://github.com/crissmoldovan/tactile-mac/releases/download/mac-v0.6.0/Tactile-0.6.0.zip"] {
            let network = FakeNetwork(download: .success(.init(
                status: 200, body: Fixture.archiveBytes, redirects: [URL(string: elsewhere)!])))
            let helper = FakeHelper()
            let (result, _) = await run(installer(network: network, helper: helper))
            XCTAssertEqual(result, .failure(.downloadNotFromSite), elsewhere)
            XCTAssertEqual(helper.launched, [])
            XCTAssertEqual(cacheContents, [], "the update folder is emptied after a failure")
        }
    }

    func testADownloadThatFailsIsNamed() async {
        let errorStatus = FakeNetwork(download: .success(.init(status: 404, body: Data(#"{"error":"x"}"#.utf8))))
        let (statusResult, _) = await run(installer(network: errorStatus))
        XCTAssertEqual(statusResult, .failure(.downloadFailed))
        XCTAssertEqual(cacheContents, [])
        let dropped = FakeNetwork(download: .failure(URLError(.networkConnectionLost)))
        let (droppedResult, _) = await run(installer(network: dropped))
        XCTAssertEqual(droppedResult, .failure(.downloadFailed))
        let cancelled = FakeNetwork(download: .failure(URLError(.cancelled)))
        let (cancelledResult, _) = await run(installer(network: cancelled))
        XCTAssertEqual(cancelledResult, .failure(.cancelled))
        XCTAssertEqual(cacheContents, [])
    }

    /// Each check that fails empties the update folder and starts nothing.
    func testEveryCheckThatFailsLeavesNothing() async {
        let truncated = Fixture.archiveBytes.prefix(100)
        let cases: [(UpdateInstaller, UpdateFailure)] = [
            (installer(network: FakeNetwork(download: .success(.init(status: 200, body: Data(truncated))))),
             .sizeMismatch(expected: Fixture.archiveBytes.count, actual: 100)),
            (installer(trust: UpdateTrust(keys: [:])), .unknownKey("t1")),
            (installer(unpacker: FakeUnpacker { _ in false }), .unpackFailed),
            (installer(code: FakeCodeSignature(valid: false)), .codeSignatureInvalid),
            (installer(unpacker: .app(version: "0.6.1")), .versionMismatch),
        ]
        for (installer, failure) in cases {
            let (result, _) = await run(installer)
            XCTAssertEqual(result, .failure(failure), failure.name)
            XCTAssertEqual(cacheContents, [], failure.name)
            XCTAssertNil(marker(of: app))
        }
    }

    func testAHelperThatWontStartIsNamed() async {
        let helper = FakeHelper()
        helper.fails = true
        let (result, _) = await run(installer(helper: helper))
        XCTAssertEqual(result, .failure(.helperDidNotStart))
        XCTAssertEqual(cacheContents, [])
    }

    func testTheNewAppsExecutableNameIsTheOneWatchedFor() async throws {
        let (result, _) = await run(installer(unpacker: .app(executable: "Tactile Touch")))
        XCTAssertEqual(try result.get().executable, "Tactile Touch")
    }
}

/// Progress reports, gathered on the main actor.
@MainActor
final class ProgressLog: Sendable {
    private var seen: [InstallProgress] = []

    nonisolated init() {}

    func add(_ progress: InstallProgress) {
        seen.append(progress)
    }

    var all: [InstallProgress] { seen }
}
