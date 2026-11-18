import CryptoKit
import Foundation
import ReleaseCore
import XCTest

/// update.json as the contract has it, read back the way the website and the app read it.
final class ManifestTests: XCTestCase {
    private struct Decoded: Decodable {
        struct Archive: Decodable { var name: String; var size: Int; var sha256: String; var signature: String; var keyId: String }
        struct Image: Decodable { var name: String; var size: Int; var sha256: String }
        var schema: Int
        var version: String
        var build: Int
        var minimumSystemVersion: String
        var publishedAt: String
        var notes: String
        var archive: Archive
        var dmg: Image
    }

    private var folder: URL!
    private let key = UpdateKey.newPrivateKey()
    private let zipBytes = Data((0..<70_000).map { UInt8(truncatingIfNeeded: $0 &* 13) })
    private let dmgBytes = Data((0..<90_000).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 1) })

    override func setUpWithError() throws {
        folder = try makeTemporaryFolder(self)
    }

    private func input(version: String = "0.6.0", notes: String = "First line.\nSecond line.",
                       signature: String? = nil, zipName: String? = nil, dmgName: String? = nil) throws -> Manifest.Input {
        let zip = try write(zipBytes, to: folder, zipName ?? "Tactile-\(version).zip")
        let dmg = try write(dmgBytes, to: folder, dmgName ?? "Tactile-\(version).dmg")
        return Manifest.Input(
            version: version, build: 412, minimumSystemVersion: "14.0",
            publishedAt: Date(timeIntervalSince1970: 1_795_000_000.75), notes: notes, zip: zip, dmg: dmg,
            signature: try signature ?? UpdateKey.sign(zipBytes, with: key), keyID: "k1",
            publicKey: UpdateKey.encode(key.publicKey))
    }

    private func hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func testTheManifestHasTheContractsFieldsAndValues() throws {
        let manifestInput = try input()
        let text = try Manifest.json(manifestInput)
        let decoded = try JSONDecoder().decode(Decoded.self, from: Data(text.utf8))
        XCTAssertEqual(decoded.schema, 1)
        XCTAssertEqual(decoded.version, "0.6.0")
        XCTAssertEqual(decoded.build, 412)
        XCTAssertEqual(decoded.minimumSystemVersion, "14.0")
        XCTAssertEqual(decoded.publishedAt, "2026-11-18T11:06:40Z")
        XCTAssertEqual(decoded.notes, "First line.\nSecond line.")
        XCTAssertEqual(decoded.archive.name, "Tactile-0.6.0.zip")
        XCTAssertEqual(decoded.archive.size, zipBytes.count)
        XCTAssertEqual(decoded.archive.sha256, hex(zipBytes))
        XCTAssertEqual(decoded.archive.signature, manifestInput.signature)
        XCTAssertEqual(decoded.archive.keyId, "k1")
        XCTAssertEqual(decoded.dmg.name, "Tactile-0.6.0.dmg")
        XCTAssertEqual(decoded.dmg.size, dmgBytes.count)
        XCTAssertEqual(decoded.dmg.sha256, hex(dmgBytes))
        // The signature in it verifies, as the app will check it.
        let raw = try XCTUnwrap(Data(base64Encoded: decoded.archive.signature))
        XCTAssertTrue(key.publicKey.isValidSignature(raw, for: zipBytes))
    }

    func testTheKeysComeInTheContractsOrder() throws {
        let text = try Manifest.json(try input())
        let order = ["\"schema\"", "\"version\"", "\"build\"", "\"minimumSystemVersion\"", "\"publishedAt\"", "\"notes\"",
                     "\"archive\"", "\"name\"", "\"size\"", "\"sha256\"", "\"signature\"", "\"keyId\"", "\"dmg\""]
        let positions = order.map { text.range(of: $0)?.lowerBound }
        XCTAssertFalse(positions.contains(nil))
        XCTAssertEqual(positions.compactMap { $0 }, positions.compactMap { $0 }.sorted())
        XCTAssertFalse(text.contains("\\/"), "slashes in the signature are left as they are")
    }

    func testNotesAreOneParagraphPerLineAndEscaped() throws {
        let notes = "  Tactile now \"updates\" itself.  \n\n\tA back\\slash, an emoji 👆 and a tab\tinside.\r\n\n"
        let text = try Manifest.json(try input(notes: notes))
        let decoded = try JSONDecoder().decode(Decoded.self, from: Data(text.utf8))
        XCTAssertEqual(decoded.notes, "Tactile now \"updates\" itself.\nA back\\slash, an emoji 👆 and a tab\tinside.")
        XCTAssertEqual(Manifest.normalizedNotes("a\n\n \nb\r\nc"), "a\nb\nc")
    }

    func testEmptyNotesAreRefused() throws {
        XCTAssertThrowsError(try Manifest.json(try input(notes: " \n\n\t\n")))
    }

    func testASignatureThatDoesNotVerifyIsRefused() throws {
        let other = try UpdateKey.sign(zipBytes, with: UpdateKey.newPrivateKey())
        XCTAssertThrowsError(try Manifest.json(try input(signature: other)))
        XCTAssertThrowsError(try Manifest.json(try input(signature: "bm90IGEgc2lnbmF0dXJl")))
    }

    func testAssetsMustCarryTheContractsNames() throws {
        XCTAssertThrowsError(try Manifest.json(try input(zipName: "Tactile.zip")))
        XCTAssertThrowsError(try Manifest.json(try input(dmgName: "Tactile-0.6.1.dmg")))
    }

    func testVersionsBuildsAndKeyIDsAreChecked() throws {
        XCTAssertThrowsError(try Manifest.json(try input(version: "0.6")))
        XCTAssertThrowsError(try Manifest.json(try input(version: "v0.6.0")))
        var bad = try input()
        bad.build = 0
        XCTAssertThrowsError(try Manifest.json(bad))
        bad = try input()
        bad.minimumSystemVersion = "fourteen"
        XCTAssertThrowsError(try Manifest.json(bad))
        bad = try input()
        bad.keyID = "k 1"
        XCTAssertThrowsError(try Manifest.json(bad))
    }

    func testDigestReadsInPiecesAndMatchesCryptoKit() throws {
        let big = Data((0..<(3 << 20) + 17).map { UInt8(truncatingIfNeeded: $0 &* 2_654_435_761 >> 7) })
        let url = try write(big, to: folder, "big")
        XCTAssertEqual(try Manifest.digest(of: url), Manifest.Digest(size: big.count, sha256: hex(big)))
    }

    func testTheManifestCommandWritesWhatTheFunctionWrites() throws {
        let manifestInput = try input()
        let notes = try write(Data(manifestInput.notes.utf8), to: folder, "notes.txt")
        let store = FakeKeyStore(), printed = Printed()
        let status = Tool.run([
            "manifest", "--version", "0.6.0", "--build", "412", "--minimum-system-version", "14.0",
            "--notes-file", notes.path, "--zip", manifestInput.zip.path, "--dmg", manifestInput.dmg.path,
            "--signature", manifestInput.signature, "--key-id", "k1", "--public-key", manifestInput.publicKey,
            "--published-at", "2026-11-18T11:06:40Z",
        ], store: store, console: printed.console)
        XCTAssertEqual(status, 0, printed.err.joined())
        var expected = manifestInput
        expected.publishedAt = Date(timeIntervalSince1970: 1_795_000_000)
        XCTAssertEqual(printed.out, [try Manifest.json(expected)])

        let badBuild = Tool.run(["manifest", "--version", "0.6.0", "--build", "four", "--minimum-system-version", "14.0",
                                 "--notes-file", notes.path, "--zip", manifestInput.zip.path, "--dmg", manifestInput.dmg.path,
                                 "--signature", manifestInput.signature, "--key-id", "k1", "--public-key", manifestInput.publicKey],
                                store: store, console: printed.console)
        XCTAssertEqual(badBuild, 2)
    }
}
