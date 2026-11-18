import Foundation
import ReleaseCore
import XCTest

/// Finding an update key's public half in a built app (here, folders laid out like one).
final class KeySearchTests: XCTestCase {
    private let publicKey = UpdateKey.encode(UpdateKey.newPrivateKey().publicKey)

    private func binary(around inner: Data) -> Data {
        Data((0..<5000).map { UInt8(truncatingIfNeeded: $0 &* 17) }) + inner + Data([0, 0xFF, 0x10, 0x0A, 0])
    }

    func testFindsTheBase64KeyInTheAppsBinary() throws {
        let app = try makeTemporaryFolder(self).appendingPathComponent("Tactile.app")
        try write(binary(around: Data("k1\0".utf8) + Data(publicKey.utf8) + Data([0])), to: app, "Contents/MacOS/Tactile")
        try write(Data("<plist/>".utf8), to: app, "Contents/Info.plist")
        let matches = try KeySearch.find(publicKey: publicKey, in: app)
        XCTAssertEqual(matches, [KeySearch.Match(path: "Contents/MacOS/Tactile", form: "base64")])

        let printed = Printed()
        XCTAssertEqual(Tool.run(["find-key", "--public-key", publicKey, app.path], store: FakeKeyStore(), console: printed.console), 0)
        XCTAssertEqual(printed.out, ["Contents/MacOS/Tactile (base64)"])
    }

    func testFindsTheKeysRawBytes() throws {
        let app = try makeTemporaryFolder(self).appendingPathComponent("Tactile.app")
        try write(binary(around: try XCTUnwrap(Data(base64Encoded: publicKey))), to: app, "Contents/Frameworks/Updates.framework/Updates")
        XCTAssertEqual(try KeySearch.find(publicKey: publicKey, in: app),
                       [KeySearch.Match(path: "Contents/Frameworks/Updates.framework/Updates", form: "raw bytes")])
    }

    func testAnAppWithoutTheKeyOrWithAnotherKeyHasNoMatch() throws {
        let app = try makeTemporaryFolder(self).appendingPathComponent("Tactile.app")
        let other = UpdateKey.encode(UpdateKey.newPrivateKey().publicKey)
        try write(binary(around: Data(other.utf8)), to: app, "Contents/MacOS/Tactile")
        // Most of the key is not the key.
        try write(Data(publicKey.dropLast(2).utf8), to: app, "Contents/Resources/partial")
        XCTAssertEqual(try KeySearch.find(publicKey: publicKey, in: app), [])

        let printed = Printed()
        XCTAssertEqual(Tool.run(["find-key", "--public-key", publicKey, app.path], store: FakeKeyStore(), console: printed.console), 1)
    }

    func testSymbolicLinksOutOfTheAppAreNotFollowed() throws {
        let folder = try makeTemporaryFolder(self)
        let outside = try write(Data(publicKey.utf8), to: folder, "outside/keys")
        let app = folder.appendingPathComponent("Tactile.app")
        try write(Data("binary".utf8), to: app, "Contents/MacOS/Tactile")
        try FileManager.default.createSymbolicLink(at: app.appendingPathComponent("Contents/Resources-link"),
                                                   withDestinationURL: outside.deletingLastPathComponent())
        try FileManager.default.createSymbolicLink(at: app.appendingPathComponent("Contents/keys-link"), withDestinationURL: outside)
        XCTAssertEqual(try KeySearch.find(publicKey: publicKey, in: app), [])
    }

    func testAMalformedKeyOrAMissingAppIsAnError() throws {
        let folder = try makeTemporaryFolder(self)
        XCTAssertThrowsError(try KeySearch.find(publicKey: "abc", in: folder))
        XCTAssertThrowsError(try KeySearch.find(publicKey: publicKey, in: folder.appendingPathComponent("missing.app")))
        let printed = Printed()
        XCTAssertEqual(Tool.run(["find-key", "--public-key", "abc", folder.path], store: FakeKeyStore(), console: printed.console), 1)
    }
}
