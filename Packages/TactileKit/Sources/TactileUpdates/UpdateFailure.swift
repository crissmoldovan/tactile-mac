// Why a check or an install stopped: each reason named, for the log and for the person's words
// (`Wording.updateFailure` in the app).

import Foundation

/// The checks before installing, in the updates contract's order. Any failure stops the update,
/// deletes the download and says so.
public enum UpdateCheck: Int, CaseIterable, Sendable, CustomStringConvertible {
    /// 1. The answer's `archive.url` is on the site's origin.
    case archiveOnSite = 1
    /// 2. The download's size is `archive.size`, and its SHA-256 is `archive.sha256`.
    case sizeAndDigest
    /// 3. `archive.signature` verifies over the bytes with the trusted key named by `archive.keyId`.
    case signature
    /// 4. Unzipped with `ditto -x -k`, the single `Tactile.app` satisfies the Developer ID requirement.
    case codeSignature
    /// 5. Its `CFBundleShortVersionString` and `CFBundleVersion` are the answer's, and newer than the
    ///    running app's.
    case version

    public var description: String {
        switch self {
        case .archiveOnSite: return "1 archive on the site"
        case .sizeAndDigest: return "2 size and SHA-256"
        case .signature: return "3 update signature"
        case .codeSignature: return "4 code signature"
        case .version: return "5 version"
        }
    }
}

/// Why a check for updates or an install stopped.
public enum UpdateFailure: Error, Equatable, Sendable {
    // MARK: Asking the site

    /// No answer: offline, the name didn't resolve, the connection failed or timed out.
    case siteUnreachable
    /// The site answered with an error status (404 means no release yet, and isn't a failure).
    case siteFailed(status: Int)
    /// The answer, or a redirect on the way to it, came from somewhere other than the site.
    case answerNotFromSite
    /// The answer couldn't be read; what was wrong is for the log.
    case answerUnreadable(AnswerProblem)

    // MARK: Before downloading: where Tactile runs from

    /// macOS runs Tactile from a randomised, read-only place (App Translocation), so it can't
    /// replace itself where it really is.
    case translocated
    /// The folder Tactile is in can't be written by this account, so Tactile can't replace itself.
    case folderNotWritable(folder: String)

    // MARK: The checks before installing, in order

    /// 1. The archive's address isn't on the site.
    case archiveNotOnSite
    /// The download didn't finish, or the site answered it with an error.
    case downloadFailed
    /// The download was redirected somewhere Tactile doesn't download from.
    case downloadNotFromSite
    /// 2. The download isn't `archive.size` bytes long.
    case sizeMismatch(expected: Int, actual: Int)
    /// 2. The download's SHA-256 isn't `archive.sha256`.
    case digestMismatch
    /// 3. No trusted key has the archive's key ID.
    case unknownKey(String)
    /// 3. The signature isn't the key's signature of the download.
    case badSignature
    /// 4. `ditto` couldn't unzip the download.
    case unpackFailed
    /// 4. The download doesn't hold one `Tactile.app` and nothing else.
    case notOneApp
    /// 4. The app's code signature isn't valid, or isn't the official Developer ID for Tactile.
    case codeSignatureInvalid
    /// 5. The app's version or build isn't the one offered.
    case versionMismatch
    /// 5. The app isn't newer than the one running.
    case notNewer

    // MARK: Installing

    /// The update folder or the helper script couldn't be written.
    case couldNotPrepare
    /// The helper that replaces the app couldn't be started.
    case helperDidNotStart

    /// The person cancelled; nothing is said.
    case cancelled

    /// The check before installing this failure belongs to, if any.
    public var check: UpdateCheck? {
        switch self {
        case .archiveNotOnSite: return .archiveOnSite
        case .downloadFailed, .downloadNotFromSite, .sizeMismatch, .digestMismatch: return .sizeAndDigest
        case .unknownKey, .badSignature: return .signature
        case .unpackFailed, .notOneApp, .codeSignatureInvalid: return .codeSignature
        case .versionMismatch, .notNewer: return .version
        case .siteUnreachable, .siteFailed, .answerNotFromSite, .answerUnreadable, .translocated,
             .folderNotWritable, .couldNotPrepare, .helperDidNotStart, .cancelled:
            return nil
        }
    }

    /// A stable name for the log: "sizeMismatch".
    public var name: String {
        switch self {
        case .siteUnreachable: return "siteUnreachable"
        case .siteFailed: return "siteFailed"
        case .answerNotFromSite: return "answerNotFromSite"
        case .answerUnreadable: return "answerUnreadable"
        case .translocated: return "translocated"
        case .folderNotWritable: return "folderNotWritable"
        case .archiveNotOnSite: return "archiveNotOnSite"
        case .downloadFailed: return "downloadFailed"
        case .downloadNotFromSite: return "downloadNotFromSite"
        case .sizeMismatch: return "sizeMismatch"
        case .digestMismatch: return "digestMismatch"
        case .unknownKey: return "unknownKey"
        case .badSignature: return "badSignature"
        case .unpackFailed: return "unpackFailed"
        case .notOneApp: return "notOneApp"
        case .codeSignatureInvalid: return "codeSignatureInvalid"
        case .versionMismatch: return "versionMismatch"
        case .notNewer: return "notNewer"
        case .couldNotPrepare: return "couldNotPrepare"
        case .helperDidNotStart: return "helperDidNotStart"
        case .cancelled: return "cancelled"
        }
    }

    /// The name with what goes with it, for the log: "sizeMismatch (expected 7340032, got 12)".
    public var logDescription: String {
        switch self {
        case .siteFailed(let status): return "\(name) (status \(status))"
        case .answerUnreadable(let problem): return "\(name) (\(problem))"
        case .folderNotWritable(let folder): return "\(name) (\(folder))"
        case .sizeMismatch(let expected, let actual): return "\(name) (expected \(expected), got \(actual))"
        case .unknownKey(let id): return "\(name) (\(id))"
        default: return name
        }
    }
}
