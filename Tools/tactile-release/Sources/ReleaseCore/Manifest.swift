import CryptoKit
import Foundation

/// update.json, exactly as the updates contract shows it (the same keys, in the same order):
/// `schema`, `version`, `build`, `minimumSystemVersion`, `publishedAt`, `notes`, `archive` (`name`, `size`,
/// `sha256`, `signature`, `keyId`) and `dmg` (`name`, `size`, `sha256`).
public enum Manifest {
    public static let schema = 1

    public struct Input {
        public var version: String
        public var build: Int
        public var minimumSystemVersion: String
        public var publishedAt: Date
        /// The notes as written: plain text, one paragraph per line (blank lines are dropped).
        public var notes: String
        public var zip: URL
        public var dmg: URL
        /// The update key's signature of the zip (base64), and the key it was made with.
        public var signature: String
        public var keyID: String
        /// The public half of that key (base64): the signature is checked against it before anything
        /// is written, so update.json never carries a signature that does not verify.
        public var publicKey: String

        public init(version: String, build: Int, minimumSystemVersion: String, publishedAt: Date, notes: String,
                    zip: URL, dmg: URL, signature: String, keyID: String, publicKey: String) {
            self.version = version
            self.build = build
            self.minimumSystemVersion = minimumSystemVersion
            self.publishedAt = publishedAt
            self.notes = notes
            self.zip = zip
            self.dmg = dmg
            self.signature = signature
            self.keyID = keyID
            self.publicKey = publicKey
        }
    }

    public static func json(_ input: Input) throws -> String {
        guard isVersion(input.version) else { throw ManifestError("The version '\(input.version)' is not <major>.<minor>.<patch>.") }
        guard input.build > 0 else { throw ManifestError("The build must be a positive whole number, not \(input.build).") }
        guard isSystemVersion(input.minimumSystemVersion) else {
            throw ManifestError("The minimum macOS version '\(input.minimumSystemVersion)' is not a version like 14.0.")
        }
        guard UpdateKey.isValidKeyID(input.keyID) else { throw ManifestError("'\(input.keyID)' is not a keyId.") }
        let notes = normalizedNotes(input.notes)
        guard !notes.isEmpty else { throw ManifestError("The release notes are empty.") }

        let zipName = "Tactile-\(input.version).zip", dmgName = "Tactile-\(input.version).dmg"
        guard input.zip.lastPathComponent == zipName else {
            throw ManifestError("The update must be named \(zipName), not \(input.zip.lastPathComponent).")
        }
        guard input.dmg.lastPathComponent == dmgName else {
            throw ManifestError("The disk image must be named \(dmgName), not \(input.dmg.lastPathComponent).")
        }
        let zipData: Data
        do {
            zipData = try Data(contentsOf: input.zip, options: .mappedIfSafe)
        } catch {
            throw ManifestError("Could not read \(input.zip.path).")
        }
        let valid: Bool
        do {
            valid = try UpdateKey.isValid(signature: input.signature, of: zipData, publicKey: input.publicKey)
        } catch {
            throw ManifestError("\(error)")
        }
        guard valid else { throw ManifestError("The signature does not verify over \(zipName) with the public key of \(input.keyID).") }
        let zip = Digest(size: zipData.count, sha256: hex(SHA256.hash(data: zipData)))
        let dmg = try digest(of: input.dmg)

        let q = try [
            "version": input.version, "minimumSystemVersion": input.minimumSystemVersion,
            "publishedAt": timestamp(input.publishedAt), "notes": notes,
            "zipName": zipName, "zipSHA": zip.sha256, "keyId": input.keyID,
            "signature": input.signature.trimmingCharacters(in: .whitespacesAndNewlines),
            "dmgName": dmgName, "dmgSHA": dmg.sha256,
        ].mapValues(quoted)
        return """
        {
          "schema": \(schema),
          "version": \(q["version"]!),
          "build": \(input.build),
          "minimumSystemVersion": \(q["minimumSystemVersion"]!),
          "publishedAt": \(q["publishedAt"]!),
          "notes": \(q["notes"]!),
          "archive": {
            "name": \(q["zipName"]!),
            "size": \(zip.size),
            "sha256": \(q["zipSHA"]!),
            "signature": \(q["signature"]!),
            "keyId": \(q["keyId"]!)
          },
          "dmg": {
            "name": \(q["dmgName"]!),
            "size": \(dmg.size),
            "sha256": \(q["dmgSHA"]!)
          }
        }
        """
    }

    /// One paragraph per line: each line trimmed, blank lines dropped, joined with "\n".
    public static func normalizedNotes(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// "2026-11-18T10:00:00Z": UTC, whole seconds.
    public static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    public struct Digest: Equatable {
        public var size: Int
        public var sha256: String

        public init(size: Int, sha256: String) {
            self.size = size
            self.sha256 = sha256
        }
    }

    /// The size and SHA-256 (64 lowercase hex digits) of a file, read in pieces.
    public static func digest(of url: URL) throws -> Digest {
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw ManifestError("Could not read \(url.path).") }
        defer { try? handle.close() }
        var hasher = SHA256()
        var size = 0
        while true {
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            } catch {
                throw ManifestError("Could not read \(url.path).")
            }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            size += chunk.count
        }
        return Digest(size: size, sha256: hex(hasher.finalize()))
    }

    static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    static func isVersion(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isASCIIDigitCharacter) }
    }

    static func isSystemVersion(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return (1...3).contains(parts.count) && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isASCIIDigitCharacter) }
    }

    /// A JSON string, with JSON's own escaping ('/' left as it is).
    static func quoted(_ text: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return String(decoding: try encoder.encode(text), as: UTF8.self)
    }
}

public struct ManifestError: Error, Equatable, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

extension Character {
    var isASCIIDigitCharacter: Bool { isASCII && isNumber }
}
