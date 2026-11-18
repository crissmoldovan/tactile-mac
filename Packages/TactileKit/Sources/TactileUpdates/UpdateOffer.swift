// The site's answer to `GET /api/mac/update`: the newest release, read and checked.

import Foundation

/// The newest release, as the site describes it (the updates contract, "The website's answers"):
///
///     { "version": "0.6.0", "build": 412, "minimumSystemVersion": "14.0",
///       "publishedAt": "2026-11-18T10:00:00Z", "notes": "...",
///       "archive": { "url": "<same origin>/api/mac/archive/0.6.0", "size": 7340032,
///                    "sha256": "<hex>", "signature": "<base64>", "keyId": "k1" } }
///
/// Every field is required and checked when it is read; fields the contract doesn't name are
/// ignored. Whether the archive's address is on the site is the first check before installing
/// (`UpdateVerifier`), not part of reading.
public struct UpdateOffer: Equatable, Sendable {
    public var version: ReleaseVersion
    public var build: Int
    public var minimumSystemVersion: SystemVersion
    public var publishedAt: Date
    /// Plain text, one paragraph per line.
    public var notes: String
    public var archive: Archive

    public struct Archive: Equatable, Sendable {
        public var url: URL
        public var size: Int
        /// 64 lowercase hexadecimal digits.
        public var sha256: String
        /// The 64-byte Ed25519 signature over the archive's bytes.
        public var signature: Data
        /// Which of the trusted public keys signed it (`UpdateTrust`).
        public var keyID: String

        public init(url: URL, size: Int, sha256: String, signature: Data, keyID: String) {
            self.url = url
            self.size = size
            self.sha256 = sha256
            self.signature = signature
            self.keyID = keyID
        }
    }

    public init(version: ReleaseVersion, build: Int, minimumSystemVersion: SystemVersion, publishedAt: Date,
                notes: String, archive: Archive) {
        self.version = version
        self.build = build
        self.minimumSystemVersion = minimumSystemVersion
        self.publishedAt = publishedAt
        self.notes = notes
        self.archive = archive
    }

    public var versionAndBuild: VersionAndBuild { VersionAndBuild(version: version, build: build) }

    /// The notes as paragraphs: one a line, blank lines and surrounding spaces left out.
    public var paragraphs: [String] {
        notes.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Reading the answer

    /// The longest answer read: the notes are a few paragraphs.
    public static let largestAnswer = 256 * 1024
    /// The longest notes kept.
    public static let longestNotes = 20_000
    /// The largest archive Tactile will download: a few megabytes are expected.
    public static let largestArchive = 1 << 30

    /// The answer in `data`, or the first thing wrong with it, named.
    public static func read(_ data: Data) -> Result<UpdateOffer, AnswerProblem> {
        guard data.count <= largestAnswer else { return .failure(.tooLarge) }
        let wire: Wire
        do {
            wire = try JSONDecoder().decode(Wire.self, from: data)
        } catch let error as DecodingError {
            return .failure(AnswerProblem(error))
        } catch {
            return .failure(.notJSON)
        }
        return wire.offer()
    }

    /// The answer as it is sent. Every field is required.
    private struct Wire: Decodable {
        var version: String
        var build: WholeNumber
        var minimumSystemVersion: String
        var publishedAt: String
        var notes: String
        var archive: ArchiveWire

        struct ArchiveWire: Decodable {
            var url: String
            var size: WholeNumber
            var sha256: String
            var signature: String
            var keyId: String
        }

        func offer() -> Result<UpdateOffer, AnswerProblem> {
            guard let version = ReleaseVersion(version) else { return .failure(.invalid("version")) }
            let build = self.build.value
            guard build > 0 else { return .failure(.invalid("build")) }
            guard let minimum = SystemVersion(minimumSystemVersion) else {
                return .failure(.invalid("minimumSystemVersion"))
            }
            guard let published = UpdateOffer.date(publishedAt) else { return .failure(.invalid("publishedAt")) }
            guard notes.count <= UpdateOffer.longestNotes else { return .failure(.invalid("notes")) }
            guard let url = URL(string: archive.url), let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http", url.host?.isEmpty == false
            else { return .failure(.invalid("archive.url")) }
            let size = archive.size.value
            guard (1...UpdateOffer.largestArchive).contains(size) else {
                return .failure(.invalid("archive.size"))
            }
            guard archive.sha256.count == 64, archive.sha256.allSatisfy({ $0.isHexDigit && !$0.isUppercase && $0.isASCII })
            else { return .failure(.invalid("archive.sha256")) }
            guard let signature = Data(base64Encoded: archive.signature), signature.count == 64 else {
                return .failure(.invalid("archive.signature"))
            }
            guard (1...32).contains(archive.keyId.count),
                  archive.keyId.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) })
            else { return .failure(.invalid("archive.keyId")) }
            return .success(UpdateOffer(
                version: version, build: build, minimumSystemVersion: minimum, publishedAt: published,
                notes: notes,
                archive: Archive(url: url, size: size, sha256: archive.sha256, signature: signature,
                                 keyID: archive.keyId)))
        }
    }

    /// A JSON number that is a whole number: anything else (a fraction, a string, true) is a type
    /// mismatch at its own field, so the problem names the field.
    private struct WholeNumber: Decodable {
        var value: Int

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                throw DecodingError.valueNotFound(Int.self, .init(codingPath: decoder.codingPath, debugDescription: "null"))
            }
            guard let value = try? container.decode(Int.self) else {
                throw DecodingError.typeMismatch(
                    Int.self, .init(codingPath: decoder.codingPath, debugDescription: "not a whole number"))
            }
            self.value = value
        }
    }

    /// An ISO 8601 date and time with a zone, with or without fractions of a second.
    static func date(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}

/// What is wrong with an answer, named for the log; the person reads only that it couldn't be read.
public enum AnswerProblem: Error, Equatable, Sendable, CustomStringConvertible {
    /// Longer than `UpdateOffer.largestAnswer`.
    case tooLarge
    /// Not a JSON object.
    case notJSON
    /// A required field is missing or null: its path, "archive.sha256".
    case missing(String)
    /// A field has the wrong type or a value that isn't allowed: its path.
    case invalid(String)

    init(_ error: DecodingError) {
        func path(_ codingPath: [CodingKey], _ last: CodingKey? = nil) -> String {
            (codingPath + (last.map { [$0] } ?? [])).map(\.stringValue).joined(separator: ".")
        }
        switch error {
        case .keyNotFound(let key, let context): self = .missing(path(context.codingPath, key))
        case .valueNotFound(_, let context): self = .missing(path(context.codingPath))
        case .typeMismatch(_, let context):
            self = context.codingPath.isEmpty ? .notJSON : .invalid(path(context.codingPath))
        case .dataCorrupted(let context):
            self = context.codingPath.isEmpty ? .notJSON : .invalid(path(context.codingPath))
        @unknown default: self = .notJSON
        }
    }

    public var description: String {
        switch self {
        case .tooLarge: return "too large"
        case .notJSON: return "not a JSON object"
        case .missing(let field): return "missing \(field)"
        case .invalid(let field): return "invalid \(field)"
        }
    }
}
