import Foundation
import XCTest

@testable import TactileUpdates

/// A check asks the site once and compares its answer with the running app; every way the site can
/// fail is a named reason, and an answer from anywhere but the site is refused.
final class CheckerTests: XCTestCase {

    private func check(_ network: FakeNetwork, running: RunningApp = Fixture.running(),
                       site: UpdateSite = Fixture.site) async -> Result<CheckOutcome, UpdateFailure> {
        await UpdateChecker(site: site, network: network, running: running).check()
    }

    func testANewerReleaseIsOffered() async {
        let network = FakeNetwork()
        let result = await check(network)
        XCTAssertEqual(result, .success(.newer(Fixture.offer())))
        XCTAssertEqual(network.fetched.map(\.absoluteString),
                       ["https://tactilemac.com/api/mac/update?version=0.5.0&build=300"])
        XCTAssertEqual(network.downloaded, [], "a check downloads nothing")
    }

    func testTheSameVersionAndBuildIsUpToDate() async {
        let same = await check(FakeNetwork(), running: Fixture.running(version: "0.6.0", build: "412"))
        XCTAssertEqual(same, .success(.upToDate))
        let newerRunning = await check(FakeNetwork(), running: Fixture.running(version: "0.7.0", build: "1"))
        XCTAssertEqual(newerRunning, .success(.upToDate))
    }

    func testAHigherBuildOfTheSameVersionIsNewer() async {
        let result = await check(FakeNetwork(), running: Fixture.running(version: "0.6.0", build: "411"))
        XCTAssertEqual(result, .success(.newer(Fixture.offer())))
    }

    func testARunningVersionThatCantBeReadIsOfferedTheRelease() async {
        let result = await check(FakeNetwork(), running: Fixture.running(version: "", build: ""))
        XCTAssertEqual(result, .success(.newer(Fixture.offer())))
    }

    func testAReleaseForANewerMacOSIsntOffered() async {
        let offer = Fixture.offer(minimumSystem: "15.1")
        let network = FakeNetwork(answer: .success(.init(status: 200, body: Fixture.answer(offer))))
        let result = await check(network, running: Fixture.running(system: SystemVersion(major: 15)))
        XCTAssertEqual(result, .success(.needsNewerSystem(offer)))
        let onNewer = await check(network, running: Fixture.running(system: SystemVersion(major: 15, minor: 1)))
        XCTAssertEqual(onNewer, .success(.newer(offer)))
    }

    func testNoReleaseYetIsUpToDate() async {
        let network = FakeNetwork(answer: .success(.init(status: 404, body: Data(#"{"error":"no release"}"#.utf8))))
        let result = await check(network)
        XCTAssertEqual(result, .success(.upToDate))
    }

    func testTheSitesErrorsAreNamed() async {
        for status in [500, 502, 503, 403, 400] {
            let network = FakeNetwork(answer: .success(.init(status: status, body: Data(#"{"error":"x"}"#.utf8))))
            let result = await check(network)
            XCTAssertEqual(result, .failure(.siteFailed(status: status)), "\(status)")
        }
    }

    func testNoAnswerIsUnreachable() async {
        let network = FakeNetwork(answer: .failure(URLError(.notConnectedToInternet)))
        let result = await check(network)
        XCTAssertEqual(result, .failure(.siteUnreachable))
        let timedOut = await check(FakeNetwork(answer: .failure(URLError(.timedOut))))
        XCTAssertEqual(timedOut, .failure(.siteUnreachable))
    }

    func testACancelledCheckSaysSo() async {
        let result = await check(FakeNetwork(answer: .failure(URLError(.cancelled))))
        XCTAssertEqual(result, .failure(.cancelled))
        let cancelled = await check(FakeNetwork(answer: .failure(CancellationError())))
        XCTAssertEqual(cancelled, .failure(.cancelled))
    }

    func testAnAnswerThatCantBeReadIsNamed() async {
        let network = FakeNetwork(answer: .success(.init(status: 200, body: Data("<html></html>".utf8))))
        let result = await check(network)
        XCTAssertEqual(result, .failure(.answerUnreadable(.notJSON)))
        let missing = FakeNetwork(answer: .success(.init(status: 200, body: Fixture.answer { $0["build"] = nil })))
        let missingResult = await check(missing)
        XCTAssertEqual(missingResult, .failure(.answerUnreadable(.missing("build"))))
    }

    /// The answer may be redirected within the site only. A redirect elsewhere is refused (the request
    /// ends with the redirect's own status), and an answer said to come from elsewhere isn't read.
    func testAnAnswerFromAnywhereButTheSiteIsRefused() async {
        let within = FakeNetwork(answer: .success(.init(
            status: 200, body: Fixture.answer(), redirects: [URL(string: "https://tactilemac.com/api/mac/update/")!])))
        let withinResult = await check(within)
        XCTAssertEqual(withinResult, .success(.newer(Fixture.offer())))
        for elsewhere in ["https://evil.example/api/mac/update", "http://tactilemac.com/api/mac/update",
                          "https://objects.githubusercontent.com/x"] {
            let network = FakeNetwork(answer: .success(.init(
                status: 200, body: Fixture.answer(), redirects: [URL(string: elsewhere)!])))
            let result = await check(network)
            XCTAssertEqual(result, .failure(.answerNotFromSite), elsewhere)
        }
    }

    func testThePreviewSiteIsAskedWhenItIsSet() async {
        let site = UpdateSite(base: "https://preview.example.com")!
        let offer = Fixture.offer(url: URL(string: "https://preview.example.com/api/mac/archive/0.6.0")!)
        let network = FakeNetwork(answer: .success(.init(status: 200, body: Fixture.answer(offer))))
        let result = await check(network, site: site)
        XCTAssertEqual(result, .success(.newer(offer)))
        XCTAssertEqual(network.fetched.first?.host, "preview.example.com")
    }
}

/// The checks after the download, in the contract's order: each failure stops the ones after it.
final class VerifierTests: XCTestCase {

    private var folder: URL!
    private var archive: URL!
    private let running = VersionAndBuild(version: ReleaseVersion("0.5.0")!, build: 300)

    override func setUpWithError() throws {
        folder = try makeTemporaryFolder()
        archive = folder.appendingPathComponent("Tactile-0.6.0.zip")
        try Fixture.archiveBytes.write(to: archive)
    }

    private func verify(_ offer: UpdateOffer = Fixture.offer(), trust: UpdateTrust = Fixture.trust,
                        unpacker: FakeUnpacker = .app(), code: FakeCodeSignature = FakeCodeSignature(),
                        running: VersionAndBuild? = nil) async -> Result<VerifiedUpdate, UpdateFailure> {
        let verifier = UpdateVerifier(trust: trust, unpacker: unpacker, codeSignature: code)
        return await verifier.verify(archive, offer: offer, running: running ?? self.running,
                                     unpackingInto: folder.appendingPathComponent("Unpacked"))
    }

    func testTheContractsOrder() {
        XCTAssertEqual(UpdateCheck.allCases, [.archiveOnSite, .sizeAndDigest, .signature, .codeSignature, .version])
        XCTAssertEqual(UpdateCheck.allCases.map(\.rawValue), [1, 2, 3, 4, 5])
    }

    func testEveryFailureBelongsToItsCheck() {
        let expected: [(UpdateFailure, UpdateCheck?)] = [
            (.archiveNotOnSite, .archiveOnSite),
            (.downloadFailed, .sizeAndDigest), (.downloadNotFromSite, .sizeAndDigest),
            (.sizeMismatch(expected: 1, actual: 2), .sizeAndDigest), (.digestMismatch, .sizeAndDigest),
            (.unknownKey("k9"), .signature), (.badSignature, .signature),
            (.unpackFailed, .codeSignature), (.notOneApp, .codeSignature), (.codeSignatureInvalid, .codeSignature),
            (.versionMismatch, .version), (.notNewer, .version),
            (.siteUnreachable, nil), (.translocated, nil), (.helperDidNotStart, nil), (.cancelled, nil),
        ]
        for (failure, check) in expected {
            XCTAssertEqual(failure.check, check, failure.name)
        }
    }

    func testAnUpdateThatPassesEveryCheck() async throws {
        let code = FakeCodeSignature()
        let update = try await verify(code: code).get()
        XCTAssertEqual(update.app, folder.appendingPathComponent("Unpacked/Tactile.app", isDirectory: true))
        XCTAssertEqual(update.info.version, "0.6.0")
        XCTAssertEqual(update.info.build, "412")
        XCTAssertEqual(update.info.executable, "Tactile")
        XCTAssertEqual(code.checked, [update.app], "the code signature is checked on the unpacked app")
    }

    func testTheWrongSizeStopsBeforeAnythingElse() async {
        let code = FakeCodeSignature()
        let offer = Fixture.offer(size: Fixture.archiveBytes.count + 1)
        let result = await verify(offer, code: code)
        XCTAssertEqual(result, .failure(.sizeMismatch(expected: Fixture.archiveBytes.count + 1, actual: Fixture.archiveBytes.count)))
        XCTAssertEqual(code.checked, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Unpacked").path),
                       "never unpacked")
    }

    func testTheWrongDigestStopsBeforeTheSignature() async {
        let offer = Fixture.offer(sha256: String(repeating: "0", count: 64))
        // An empty trust list would refuse the signature: the digest is checked first.
        let result = await verify(offer, trust: UpdateTrust(keys: [:]))
        XCTAssertEqual(result, .failure(.digestMismatch))
    }

    func testAKeyNotTrustedStopsBeforeUnpacking() async {
        let code = FakeCodeSignature()
        let result = await verify(trust: UpdateTrust(keys: [:]), code: code)
        XCTAssertEqual(result, .failure(.unknownKey("t1")))
        XCTAssertEqual(code.checked, [])
        let production = await verify(trust: .production, code: code)
        XCTAssertEqual(production, .failure(.unknownKey("t1")), "the production list doesn't trust a test's key")
    }

    func testABadSignatureStopsBeforeUnpacking() async {
        var signature = try! Fixture.key.signature(for: Fixture.archiveBytes)
        signature[5] ^= 0xFF
        let code = FakeCodeSignature()
        let result = await verify(Fixture.offer(signature: signature), code: code)
        XCTAssertEqual(result, .failure(.badSignature))
        XCTAssertEqual(code.checked, [])
    }

    func testAnArchiveThatWontUnpack() async {
        let result = await verify(unpacker: FakeUnpacker { _ in false })
        XCTAssertEqual(result, .failure(.unpackFailed))
    }

    func testAnArchiveMustHoldOneTactileAppAndNothingElse() async {
        let extra = FakeUnpacker { folder in
            _ = try FakeUnpacker.app().make(folder)
            try Data().write(to: folder.appendingPathComponent(".hidden"))
            return true
        }
        let extraResult = await verify(unpacker: extra)
        XCTAssertEqual(extraResult, .failure(.notOneApp), "a hidden file counts")
        let renamed = FakeUnpacker { folder in
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("Tactile 2.app"), withIntermediateDirectories: true)
            return true
        }
        let renamedResult = await verify(unpacker: renamed)
        XCTAssertEqual(renamedResult, .failure(.notOneApp))
        let file = FakeUnpacker { folder in
            try Data().write(to: folder.appendingPathComponent("Tactile.app"))
            return true
        }
        let fileResult = await verify(unpacker: file)
        XCTAssertEqual(fileResult, .failure(.notOneApp), "a file, not a folder")
        let link = FakeUnpacker { folder in
            try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("Tactile.app").path,
                                                       withDestinationPath: "/Applications/Tactile.app")
            return true
        }
        let linkResult = await verify(unpacker: link)
        XCTAssertEqual(linkResult, .failure(.notOneApp), "a link, not a folder")
        let empty = FakeUnpacker { _ in true }
        let emptyResult = await verify(unpacker: empty)
        XCTAssertEqual(emptyResult, .failure(.notOneApp))
    }

    func testAnAppNotSignedWithTheDeveloperIDStopsBeforeTheVersion() async {
        let result = await verify(unpacker: .app(version: "0.0.1"), code: FakeCodeSignature(valid: false))
        XCTAssertEqual(result, .failure(.codeSignatureInvalid))
    }

    func testTheAppMustBeTheVersionOffered() async {
        let cases: [(FakeUnpacker, String)] = [
            (.app(version: "0.6.1"), "another version"),
            (.app(build: "413"), "another build"),
            (.app(version: nil), "no version"),
            (.app(build: nil), "no build"),
            (.app(build: "412a"), "a build that isn't a number"),
        ]
        for (unpacker, why) in cases {
            let result = await verify(unpacker: unpacker)
            XCTAssertEqual(result, .failure(.versionMismatch), why)
        }
    }

    func testTheAppMustBeNewerThanTheRunningOne() async {
        let same = await verify(running: VersionAndBuild(version: ReleaseVersion("0.6.0")!, build: 412))
        XCTAssertEqual(same, .failure(.notNewer))
        let older = await verify(running: VersionAndBuild(version: ReleaseVersion("0.7.0")!, build: 1))
        XCTAssertEqual(older, .failure(.notNewer))
        let lowerBuild = await verify(running: VersionAndBuild(version: ReleaseVersion("0.6.0")!, build: 411))
        XCTAssertNoThrow(try lowerBuild.get())
    }

    func testTheDigestIsLowercaseHexadecimal() {
        XCTAssertEqual(UpdateVerifier.sha256(Data("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
