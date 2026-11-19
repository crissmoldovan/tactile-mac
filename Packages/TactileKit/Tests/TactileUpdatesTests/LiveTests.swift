import CryptoKit
import Foundation
import Security
import XCTest

@testable import TactileUpdates
import TactileTestSupport

/// The live pieces, on stand-in files in temporary folders: `ditto`, the Security framework's code
/// signature check, the place Tactile runs from, the update folder, and starting the helper.
final class LiveTests: XCTestCase {

    // MARK: - Unzipping with ditto

    private func zip(_ source: URL, to archive: URL, keepParent: Bool = true) async throws {
        let status = await DittoUnpacker.run("/usr/bin/ditto", ["-c", "-k"] + (keepParent ? ["--keepParent"] : [])
                                             + [source.path, archive.path])
        XCTAssertEqual(status, 0)
    }

    func testAnArchiveMadeAsTheReleaseMakesItUnpacksToOneApp() async throws {
        let root = try makeTemporaryFolder()
        let app = try makeBundle(at: root.appendingPathComponent("Built/Tactile.app"), version: "0.6.0", build: "412")
        let archive = root.appendingPathComponent("Tactile-0.6.0.zip")
        try await zip(app, to: archive)
        let out = root.appendingPathComponent("Unpacked")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let unpacked = await DittoUnpacker().unpack(archive, into: out)
        XCTAssertTrue(unpacked)
        let found = try XCTUnwrap(UpdateVerifier.singleApp(in: out))
        XCTAssertEqual(BundleInfo.read(app: found),
                       BundleInfo(identifier: "com.crissmoldovan.tactile", version: "0.6.0", build: "412", executable: "Tactile"))
    }

    func testAnArchiveThatIsntAZipDoesntUnpack() async throws {
        let root = try makeTemporaryFolder()
        let archive = root.appendingPathComponent("Tactile-0.6.0.zip")
        try Fixture.archiveBytes.write(to: archive)
        let out = root.appendingPathComponent("Unpacked")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let unpacked = await DittoUnpacker().unpack(archive, into: out)
        XCTAssertFalse(unpacked)
    }

    /// Checks 2 to 5 on a real zip, signed with the test's key, unzipped by ditto; only the code
    /// signature is a stand-in.
    func testTheChecksPassARealArchive() async throws {
        let root = try makeTemporaryFolder()
        let app = try makeBundle(at: root.appendingPathComponent("Built/Tactile.app"), version: "0.6.0", build: "412")
        let archive = root.appendingPathComponent("Tactile-0.6.0.zip")
        try await zip(app, to: archive)
        let bytes = try Data(contentsOf: archive)
        let offer = Fixture.offer(bytes: bytes)
        let verifier = UpdateVerifier(trust: Fixture.trust, unpacker: DittoUnpacker(), codeSignature: FakeCodeSignature())
        let running = VersionAndBuild(version: ReleaseVersion("0.5.0")!, build: 300)
        let result = await verifier.verify(archive, offer: offer, running: running,
                                           unpackingInto: root.appendingPathComponent("Unpacked"))
        XCTAssertEqual(try result.get().info.version, "0.6.0")
    }

    func testAnArchiveHoldingMoreThanTheAppIsRefused() async throws {
        let root = try makeTemporaryFolder()
        let built = root.appendingPathComponent("Built", isDirectory: true)
        try makeBundle(at: built.appendingPathComponent("Tactile.app"), version: "0.6.0", build: "412")
        try Data("extra".utf8).write(to: built.appendingPathComponent("README.txt"))
        let archive = root.appendingPathComponent("Tactile-0.6.0.zip")
        try await zip(built, to: archive, keepParent: false)
        let offer = Fixture.offer(bytes: try Data(contentsOf: archive))
        let verifier = UpdateVerifier(trust: Fixture.trust, unpacker: DittoUnpacker(), codeSignature: FakeCodeSignature())
        let result = await verifier.verify(archive, offer: offer, running: VersionAndBuild(version: ReleaseVersion("0.5.0")!, build: 1),
                                           unpackingInto: root.appendingPathComponent("Unpacked"))
        XCTAssertEqual(result, .failure(.notOneApp))
    }

    // MARK: - The code signature

    func testTheRequirementIsTheContracts() throws {
        XCTAssertEqual(SecurityCodeSignatureCheck.developerIDRequirement,
                       "anchor apple generic and identifier \"com.crissmoldovan.tactile\" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"75K3LTUM8A\"")
        var requirement: SecRequirement?
        XCTAssertEqual(SecRequirementCreateWithString(SecurityCodeSignatureCheck.developerIDRequirement as CFString, [],
                                                      &requirement), errSecSuccess, "it compiles")
        XCTAssertEqual(SecurityCodeSignatureCheck.flags.rawValue,
                       kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        XCTAssertEqual(SecurityCodeSignatureCheck().requirement, SecurityCodeSignatureCheck.developerIDRequirement)
    }

    func testAnUnsignedAppIsRefused() throws {
        let root = try makeTemporaryFolder()
        let app = try makeBundle(at: root.appendingPathComponent("Tactile.app"), version: "0.6.0", build: "412")
        XCTAssertFalse(SecurityCodeSignatureCheck().isValid(app))
        XCTAssertFalse(SecurityCodeSignatureCheck().isValid(root.appendingPathComponent("Missing.app")))
    }

    /// The check itself works: Apple's own `true` is validly signed by Apple, and isn't Tactile.
    func testTheCheckTellsAValidSignatureFromTheWrongOne() {
        let tool = URL(fileURLWithPath: "/usr/bin/true")
        XCTAssertEqual(SecurityCodeSignatureCheck(requirement: "anchor apple").check(tool), errSecSuccess)
        XCTAssertEqual(SecurityCodeSignatureCheck().check(tool), errSecCSReqFailed)
        XCTAssertFalse(SecurityCodeSignatureCheck().isValid(tool))
    }

    // MARK: - Where Tactile runs from

    func testATranslocatedPathIsRefusedFirst() {
        let translocated = URL(fileURLWithPath: "/private/var/folders/ab/xyz/T/AppTranslocation/1234-ABCD/d/Tactile.app")
        XCTAssertTrue(InstallLocation.pathLooksTranslocated(translocated))
        XCTAssertFalse(InstallLocation.pathLooksTranslocated(URL(fileURLWithPath: "/Applications/Tactile.app")))
        let neither = InstallLocation(isTranslocated: { _ in true }, isWritable: { _ in false })
        XCTAssertEqual(neither.refusal(for: translocated), .translocated)
    }

    func testAFolderThatCantBeWrittenIsRefused() throws {
        let root = try makeTemporaryFolder()
        let folder = root.appendingPathComponent("Applications", isDirectory: true)
        let app = try makeBundle(at: folder.appendingPathComponent("Tactile.app"), version: "0.5.0", build: "300")
        XCTAssertNil(InstallLocation.live.refusal(for: app))
        chmod(folder.path, 0o555)
        XCTAssertEqual(InstallLocation.live.refusal(for: app), .folderNotWritable(folder: folder.path))
    }

    func testAnAppInAnOrdinaryFolderIsntTranslocated() throws {
        let root = try makeTemporaryFolder()
        let app = try makeBundle(at: root.appendingPathComponent("Tactile.app"), version: "0.5.0", build: "300")
        XCTAssertFalse(InstallLocation.securityReportsTranslocated(app))
        XCTAssertFalse(InstallLocation.live.isTranslocated(app))
    }

    // MARK: - The update folder

    func testTheUpdateFolderIsInTactilesCaches() {
        XCTAssertTrue(UpdateCache.live.folder.path.hasSuffix("/Library/Caches/com.crissmoldovan.tactile/Updates"),
                      UpdateCache.live.folder.path)
    }

    func testClearingEmptiesTheFolderAndKeepsItPrivate() throws {
        let root = try makeTemporaryFolder()
        let cache = UpdateCache(folder: root.appendingPathComponent("Caches/Updates", isDirectory: true))
        XCTAssertEqual(cache.archive(for: ReleaseVersion("0.6.0")!).lastPathComponent, "Tactile-0.6.0.zip")
        XCTAssertEqual(cache.unpacked.lastPathComponent, "Unpacked")
        XCTAssertEqual(cache.script.lastPathComponent, "install.sh")
        XCTAssertEqual(cache.log.lastPathComponent, "install.log")
        try cache.clear()
        try FileManager.default.createDirectory(at: cache.unpacked.appendingPathComponent("Tactile.app"),
                                                withIntermediateDirectories: true)
        try Data("x".utf8).write(to: cache.log)
        try cache.clear()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cache.folder.path), [])
        let permissions = try FileManager.default.attributesOfItem(atPath: cache.folder.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o700)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Caches").path),
                      "only the update folder is cleared")
    }

    // MARK: - Starting the helper

    /// The helper runs in a process group of its own, whose parent has already gone, so nothing that
    /// ends Tactile's group ends it.
    func testTheHelperRunsInAProcessGroupOfItsOwn() throws {
        let root = try makeTemporaryFolder()
        let report = root.appendingPathComponent("report")
        let script = root.appendingPathComponent("helper.sh")
        let text = """
        #!/bin/sh
        /bin/sleep 0.3
        printf '%s %s\\n' "$$" "$(/bin/ps -o pgid= -p $$ | tr -d ' ')" > \(InstallScript.quoted(report.path + ".part"))
        /bin/mv \(InstallScript.quoted(report.path + ".part")) \(InstallScript.quoted(report.path))

        """
        try Data(text.utf8).write(to: script)
        try DetachedShellLauncher().launch(script)
        let deadline = Date().addingTimeInterval(TestTiming.limit(10))
        while !FileManager.default.fileExists(atPath: report.path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        let line = try String(contentsOf: report, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = line.split(separator: " ").compactMap { Int32($0) }
        XCTAssertEqual(parts.count, 2, line)
        XCTAssertEqual(parts.first, parts.last, "the helper leads its own process group")
        XCTAssertNotEqual(parts.last, getpgrp(), "not the test's (Tactile's) group")
    }

    func testAMissingScriptIsntStarted() {
        XCTAssertThrowsError(try DetachedShellLauncher().launch(URL(fileURLWithPath: "/nonexistent/install.sh")))
        XCTAssertEqual(DetachedShellLauncher.command, #"set -m; /bin/sh "$0" </dev/null >/dev/null 2>&1 &"#)
    }
}
