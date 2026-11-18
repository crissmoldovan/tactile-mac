import CryptoKit
import Foundation
import ReleaseCore
import XCTest

/// Signing and checking, with keys made here (never the Keychain).
final class UpdateKeyTests: XCTestCase {
    private let bytes = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })

    func testKeysAreBase64OfTheirThirtyTwoRawBytes() throws {
        let key = UpdateKey.newPrivateKey()
        let privateText = UpdateKey.encode(key)
        let publicText = UpdateKey.encode(key.publicKey)
        XCTAssertEqual(Data(base64Encoded: privateText), key.rawRepresentation)
        XCTAssertEqual(Data(base64Encoded: publicText), key.publicKey.rawRepresentation)
        XCTAssertEqual(privateText.count, 44)
        XCTAssertTrue(publicText.hasSuffix("="), "standard base64 keeps its padding")
        XCTAssertEqual(try UpdateKey.privateKey(base64: privateText).rawRepresentation, key.rawRepresentation)
        XCTAssertEqual(try UpdateKey.publicKey(base64: publicText).rawRepresentation, key.publicKey.rawRepresentation)
    }

    func testSignAndVerifyRoundTrip() throws {
        let key = UpdateKey.newPrivateKey()
        let signature = try UpdateKey.sign(bytes, with: key)
        XCTAssertTrue(try UpdateKey.isValid(signature: signature, of: bytes, publicKey: UpdateKey.encode(key.publicKey)))
    }

    func testTheSignatureIsSixtyFourBytesOverTheExactBytes() throws {
        let key = UpdateKey.newPrivateKey()
        let signature = try UpdateKey.sign(bytes, with: key)
        let raw = try XCTUnwrap(Data(base64Encoded: signature))
        XCTAssertEqual(raw.count, 64)
        // What CryptoKit itself (and so the updater) checks: the signature, over these bytes, under this key.
        XCTAssertTrue(key.publicKey.isValidSignature(raw, for: bytes))
    }

    func testAnEmptyFileSignsAndVerifies() throws {
        let key = UpdateKey.newPrivateKey()
        let signature = try UpdateKey.sign(Data(), with: key)
        XCTAssertTrue(try UpdateKey.isValid(signature: signature, of: Data(), publicKey: UpdateKey.encode(key.publicKey)))
    }

    func testAnotherKeyDoesNotVerify() throws {
        let key = UpdateKey.newPrivateKey(), other = UpdateKey.newPrivateKey()
        let signature = try UpdateKey.sign(bytes, with: key)
        XCTAssertFalse(try UpdateKey.isValid(signature: signature, of: bytes, publicKey: UpdateKey.encode(other.publicKey)))
    }

    func testAnAlteredByteDoesNotVerify() throws {
        let key = UpdateKey.newPrivateKey()
        let publicKey = UpdateKey.encode(key.publicKey)
        let signature = try UpdateKey.sign(bytes, with: key)
        for index in [0, bytes.count / 2, bytes.count - 1] {
            var altered = bytes
            altered[index] ^= 0x01
            XCTAssertFalse(try UpdateKey.isValid(signature: signature, of: altered, publicKey: publicKey), "byte \(index)")
        }
    }

    func testAppendedOrTruncatedBytesDoNotVerify() throws {
        let key = UpdateKey.newPrivateKey()
        let publicKey = UpdateKey.encode(key.publicKey)
        let signature = try UpdateKey.sign(bytes, with: key)
        XCTAssertFalse(try UpdateKey.isValid(signature: signature, of: bytes + Data([0]), publicKey: publicKey))
        XCTAssertFalse(try UpdateKey.isValid(signature: signature, of: bytes.dropLast(), publicKey: publicKey))
    }

    func testAnAlteredSignatureDoesNotVerify() throws {
        let key = UpdateKey.newPrivateKey()
        var raw = try XCTUnwrap(Data(base64Encoded: try UpdateKey.sign(bytes, with: key)))
        raw[10] ^= 0x80
        XCTAssertFalse(try UpdateKey.isValid(signature: raw.base64EncodedString(), of: bytes,
                                             publicKey: UpdateKey.encode(key.publicKey)))
    }

    func testMalformedSignaturesAreErrors() throws {
        let key = UpdateKey.newPrivateKey()
        let publicKey = UpdateKey.encode(key.publicKey)
        let good = try UpdateKey.sign(bytes, with: key)
        let malformed = [
            "", "not base64 at all!", String(good.dropLast(2)),                  // no padding
            Data(count: 63).base64EncodedString(), Data(count: 65).base64EncodedString(),
            String(good.prefix(40)) + " " + String(good.dropFirst(40)),          // a space inside
            good.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_") + "_", // base64url
        ]
        for text in malformed {
            XCTAssertThrowsError(try UpdateKey.isValid(signature: text, of: bytes, publicKey: publicKey), "'\(text)'")
        }
        // A newline at the end (from a pipe) is not malformed.
        XCTAssertTrue(try UpdateKey.isValid(signature: good + "\n", of: bytes, publicKey: publicKey))
    }

    func testMalformedKeysAreErrors() {
        for text in ["", "AAAA", Data(count: 31).base64EncodedString(), Data(count: 33).base64EncodedString(),
                     Data(count: 64).base64EncodedString(), "%%%%"] {
            XCTAssertThrowsError(try UpdateKey.publicKey(base64: text), "'\(text)'")
            XCTAssertThrowsError(try UpdateKey.privateKey(base64: text), "'\(text)'")
        }
    }

    func testKeyIDs() {
        for good in ["k1", "k2", "key-2026.11_a"] { XCTAssertTrue(UpdateKey.isValidKeyID(good), good) }
        for bad in ["", "k 1", "k\"1", "k\\1", "ключ", String(repeating: "k", count: 33), "k1\n"] {
            XCTAssertFalse(UpdateKey.isValidKeyID(bad), bad)
        }
    }
}
