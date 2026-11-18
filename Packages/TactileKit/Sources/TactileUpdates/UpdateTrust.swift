// The update keys Tactile trusts, and checking an archive's signature with them.

import CryptoKit
import Foundation

/// The public halves of the update keys Tactile trusts, by key ID (the updates contract, "The update
/// key"): Ed25519 keys as CryptoKit's `Curve25519.Signing`. A release's archive is signed with one of
/// them; an archive signed with a key not listed here is refused, whoever serves it.
///
/// A list, not one key, so a release signed with an old key can ship a new one, and losing a key
/// doesn't strand the copies already installed.
public struct UpdateTrust: Sendable {
    /// The production keys: key ID → standard base64 of the 32-byte raw public key. The official
    /// build trusts the keys its Info.plist names (the build setting `TACTILE_UPDATE_KEYS`, which
    /// the project sets to these, and a test checks it does); these stand when it names none. The
    /// release script checks the built app carries the key it signs with.
    ///
    /// `k1` is the first update key, made by the release tool; its private half never leaves the
    /// release Mac's login keychain. A new key goes beside it, never in its place, so copies that
    /// know only `k1` can still update to the release that brings the new one: here and in
    /// `TACTILE_UPDATE_KEYS`.
    public static let productionKeys: [String: String] = [
        "k1": "IpKoBBLRNGZ8WqpbNod6gXQdjESJc0xYOjHdBUwbxYI=",
    ]

    /// The production keys, as a trust.
    public static var production: UpdateTrust { UpdateTrust(base64Keys: productionKeys) }

    public let keys: [String: Curve25519.Signing.PublicKey]

    public init(keys: [String: Curve25519.Signing.PublicKey]) {
        self.keys = keys
    }

    /// Keys as the contract writes them: standard base64 of the raw representation. A key that
    /// doesn't decode to 32 bytes is left out (a test checks the production list loses none).
    public init(base64Keys: [String: String]) {
        var keys: [String: Curve25519.Signing.PublicKey] = [:]
        for (id, text) in base64Keys {
            guard let raw = Data(base64Encoded: text), raw.count == 32,
                  let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
            else { continue }
            keys[id] = key
        }
        self.init(keys: keys)
    }

    public enum Verdict: Equatable, Sendable {
        case valid
        /// No trusted key has this ID.
        case unknownKey
        /// The key exists, and the signature isn't its signature of these bytes.
        case invalidSignature
    }

    /// Whether `signature` is the key `keyID`'s signature of exactly `data`.
    public func verify(signature: Data, over data: Data, keyID: String) -> Verdict {
        guard let key = keys[keyID] else { return .unknownKey }
        return key.isValidSignature(signature, for: data) ? .valid : .invalidSignature
    }
}
