import CryptoKit
import Foundation

/// The update key, in the formats the updates contract pins: Ed25519 as CryptoKit's `Curve25519.Signing`;
/// the private and public keys carried as standard base64 (with padding) of their `rawRepresentation`
/// (32 bytes each); a signature as standard base64 of its 64 bytes, made over the exact bytes of a file.
public enum UpdateKey {
    /// The Keychain item's service. Its account is the keyId.
    public static let keychainService = "Tactile update signing key"

    public static let keyLength = 32
    public static let signatureLength = 64

    /// A keyId: short, plain, and safe to quote on a `security` command line ("k1", "k2", ...).
    public static func isValidKeyID(_ keyID: String) -> Bool {
        !keyID.isEmpty && keyID.count <= 32
            && keyID.unicodeScalars.allSatisfy { scalar in
                (scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar))) || "._-".unicodeScalars.contains(scalar)
            }
    }

    public static func newPrivateKey() -> Curve25519.Signing.PrivateKey {
        Curve25519.Signing.PrivateKey()
    }

    public static func encode(_ key: Curve25519.Signing.PrivateKey) -> String {
        key.rawRepresentation.base64EncodedString()
    }

    public static func encode(_ key: Curve25519.Signing.PublicKey) -> String {
        key.rawRepresentation.base64EncodedString()
    }

    public static func privateKey(base64: String) throws -> Curve25519.Signing.PrivateKey {
        let raw = try decode(base64, length: keyLength, what: "private key")
        do {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
        } catch {
            throw UpdateKeyError("The private key is not a valid Ed25519 key.")
        }
    }

    public static func publicKey(base64: String) throws -> Curve25519.Signing.PublicKey {
        let raw = try decode(base64, length: keyLength, what: "public key")
        do {
            return try Curve25519.Signing.PublicKey(rawRepresentation: raw)
        } catch {
            throw UpdateKeyError("The public key is not a valid Ed25519 key.")
        }
    }

    /// The signature of these bytes, as base64.
    public static func sign(_ data: Data, with key: Curve25519.Signing.PrivateKey) throws -> String {
        try key.signature(for: data).base64EncodedString()
    }

    /// Whether `signature` (base64) is the signature of these bytes under `publicKey` (base64).
    /// A signature or key that is not well formed is an error, not merely "not valid".
    public static func isValid(signature: String, of data: Data, publicKey: String) throws -> Bool {
        let key = try self.publicKey(base64: publicKey)
        let raw = try decode(signature, length: signatureLength, what: "signature")
        return key.isValidSignature(raw, for: data)
    }

    /// Strict standard base64: padded, no whitespace inside, canonical (it encodes back to the same
    /// text), and exactly `length` bytes. Whitespace at either end (a newline from a pipe) is ignored.
    static func decode(_ text: String, length: Int, what: String) throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed), data.base64EncodedString() == trimmed else {
            throw UpdateKeyError("The \(what) is not standard base64.")
        }
        guard data.count == length else {
            throw UpdateKeyError("The \(what) is \(data.count) bytes; it must be \(length).")
        }
        return data
    }
}

public struct UpdateKeyError: Error, Equatable, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}
