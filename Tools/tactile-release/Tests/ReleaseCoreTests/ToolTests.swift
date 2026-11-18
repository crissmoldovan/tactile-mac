import CryptoKit
import Foundation
import ReleaseCore
import XCTest

/// The commands, run as the executable runs them, against a key store in memory.
final class ToolTests: XCTestCase {
    private var store = FakeKeyStore()
    private var printed = Printed()

    private func run(_ arguments: String...) -> Int32 {
        Tool.run(arguments, store: store, console: printed.console)
    }

    // MARK: keygen

    func testKeygenStoresAKeyAndPrintsOnlyItsPublicHalf() throws {
        XCTAssertEqual(run("keygen", "--key-id", "k1"), 0)
        let stored = try XCTUnwrap(store.items["k1"])
        let key = try UpdateKey.privateKey(base64: stored)
        let publicKey = UpdateKey.encode(key.publicKey)
        XCTAssertTrue(printed.all.contains("Public key:  \(publicKey)"))
        XCTAssertTrue(printed.all.contains("keyId:       k1"))
        XCTAssertFalse(printed.all.contains(stored), "the private key must never be printed")
        // The backup line the person releasing runs: the key goes to the clipboard, never to the screen.
        XCTAssertTrue(printed.all.contains("security find-generic-password -s 'Tactile update signing key' -a 'k1' -w | pbcopy"))
        XCTAssertTrue(printed.all.contains("can no longer update themselves"))
    }

    func testKeygenRefusesWhenTheItemExistsAndLeavesItAsItIs() {
        store.items["k1"] = "existing"
        XCTAssertEqual(run("keygen", "--key-id", "k1"), 1)
        XCTAssertEqual(store.items["k1"], "existing")
        XCTAssertTrue(store.adds.isEmpty)
        XCTAssertTrue(printed.err.joined().contains("already an update key k1"))
    }

    func testKeygenSaysSoWhenTheKeyIsNotThereAfterWritingIt() {
        store.dropsWrites = true
        XCTAssertEqual(run("keygen", "--key-id", "k1"), 1)
        XCTAssertTrue(printed.err.joined().contains("could not be stored"))
        XCTAssertFalse(printed.all.contains("Public key:"))
    }

    func testKeygenRefusesABadKeyID() {
        XCTAssertEqual(run("keygen", "--key-id", "k 1"), 2)
        XCTAssertEqual(run("keygen", "--key-id", "k\"1"), 2)
        XCTAssertTrue(store.adds.isEmpty)
    }

    // MARK: import

    func testImportStoresAPipedKeyAndPrintsItsPublicHalf() throws {
        let key = UpdateKey.newPrivateKey()
        printed.input = Data((UpdateKey.encode(key) + "\n").utf8)
        XCTAssertEqual(run("import", "--key-id", "k1"), 0)
        XCTAssertEqual(store.items["k1"], UpdateKey.encode(key))
        XCTAssertTrue(printed.all.contains(UpdateKey.encode(key.publicKey)))
        XCTAssertFalse(printed.all.contains(UpdateKey.encode(key)))
    }

    func testImportRefusesATerminalSomethingElseAndAnExistingItem() throws {
        printed.inputIsTerminal = true
        XCTAssertEqual(run("import", "--key-id", "k1"), 2)

        printed.inputIsTerminal = false
        printed.input = Data("hunter2".utf8)
        XCTAssertEqual(run("import", "--key-id", "k1"), 1)
        XCTAssertFalse(printed.all.contains("hunter2"), "what was piped in is never repeated")

        store.items["k1"] = "existing"
        printed.input = Data(UpdateKey.encode(UpdateKey.newPrivateKey()).utf8)
        XCTAssertEqual(run("import", "--key-id", "k1"), 1)
        XCTAssertEqual(store.items["k1"], "existing")
        XCTAssertTrue(store.adds.isEmpty)
    }

    // MARK: public-key, sign, verify

    func testPublicKeyIsDerivedFromTheStoredKey() throws {
        let key = UpdateKey.newPrivateKey()
        store.items["k1"] = UpdateKey.encode(key)
        XCTAssertEqual(run("public-key", "--key-id", "k1"), 0)
        XCTAssertEqual(printed.out, [UpdateKey.encode(key.publicKey)])
    }

    func testCommandsNeedingTheKeySayWhenThereIsNone() throws {
        let folder = try makeTemporaryFolder(self)
        let file = try write(Data("x".utf8), to: folder, "file")
        XCTAssertEqual(run("public-key", "--key-id", "k1"), 1)
        XCTAssertEqual(run("sign", "--key-id", "k1", file.path), 1)
        XCTAssertTrue(printed.err.joined().contains("no update key k1"))
        store.items["k2"] = "not a key"
        XCTAssertEqual(run("public-key", "--key-id", "k2"), 1)
        XCTAssertFalse(printed.all.contains("not a key"))
    }

    func testSignThenVerify() throws {
        let folder = try makeTemporaryFolder(self)
        let file = try write(Data((0..<100_000).map { UInt8(truncatingIfNeeded: $0) }), to: folder, "Tactile-0.6.0.zip")
        let key = UpdateKey.newPrivateKey()
        store.items["k1"] = UpdateKey.encode(key)
        XCTAssertEqual(run("sign", "--key-id", "k1", file.path), 0)
        let signature = try XCTUnwrap(printed.out.last)
        XCTAssertTrue(key.publicKey.isValidSignature(try XCTUnwrap(Data(base64Encoded: signature)), for: try Data(contentsOf: file)))
        XCTAssertEqual(run("verify", "--public-key", UpdateKey.encode(key.publicKey), "--signature", signature, file.path), 0)
    }

    func testVerifyRefusesAnotherKeyAnAlteredFileAndMalformedInput() throws {
        let folder = try makeTemporaryFolder(self)
        let original = Data((0..<1000).map { UInt8(truncatingIfNeeded: $0) })
        let file = try write(original, to: folder, "file")
        let key = UpdateKey.newPrivateKey()
        let signature = try UpdateKey.sign(original, with: key)
        let publicKey = UpdateKey.encode(key.publicKey)

        XCTAssertEqual(run("verify", "--public-key", UpdateKey.encode(UpdateKey.newPrivateKey().publicKey),
                           "--signature", signature, file.path), 1)
        var altered = original
        altered[500] ^= 0xFF
        let alteredFile = try write(altered, to: folder, "altered")
        XCTAssertEqual(run("verify", "--public-key", publicKey, "--signature", signature, alteredFile.path), 1)
        XCTAssertEqual(run("verify", "--public-key", publicKey, "--signature", "bm90IGEgc2lnbmF0dXJl", file.path), 1)
        XCTAssertEqual(run("verify", "--public-key", "short", "--signature", signature, file.path), 1)
        XCTAssertEqual(run("verify", "--public-key", publicKey, "--signature", signature, folder.appendingPathComponent("missing").path), 1)
        XCTAssertEqual(run("verify", "--public-key", publicKey, "--signature", signature, folder.path), 1, "a folder is not a file")
        XCTAssertEqual(run("verify", "--public-key", publicKey, "--signature", signature, file.path), 0)
    }

    // MARK: Usage

    func testUsageErrors() {
        XCTAssertEqual(run(), 2)
        XCTAssertEqual(run("sing", "--key-id", "k1"), 2)
        XCTAssertEqual(run("keygen"), 2)
        XCTAssertEqual(run("keygen", "--key-id"), 2)
        XCTAssertEqual(run("keygen", "--key-id", "k1", "--key-id", "k2"), 2)
        XCTAssertEqual(run("keygen", "--key-id", "k1", "extra"), 2)
        XCTAssertEqual(run("keygen", "--key-id", "k1", "--force", "yes"), 2)
        XCTAssertEqual(run("sign", "--key-id", "k1"), 2)
        XCTAssertEqual(run("verify", "--public-key", "x", "file"), 2)
        XCTAssertTrue(store.adds.isEmpty)
        XCTAssertEqual(run("--help"), 0)
        XCTAssertTrue(printed.out.joined().contains("usage: tactile-release"))
    }
}
