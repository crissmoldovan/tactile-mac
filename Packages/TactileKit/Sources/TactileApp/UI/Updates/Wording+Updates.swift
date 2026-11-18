// The updater's words: the menu's rows, the update window, General's switch, and why a check or an
// install stopped. Capitalisation as in `Wording`: title case for buttons and menu items, sentence
// case for everything else.

import Foundation
import TactileUpdates

extension Wording {

    // MARK: - The menu and the window

    public static let checkForUpdates = "Check for Updates…"
    /// The menu's row while a newer version is known: "Update to 0.6.0…".
    public static func updateTo(_ version: String) -> String { "Update to \(version)…" }
    public static let installAndRelaunch = "Install and Relaunch"
    public static let later = "Later"
    public static let ok = "OK"
    /// The update window's title, for the Window menu and VoiceOver; the window hides it.
    public static let updateWindowTitle = "Tactile Update"

    public static let checkingForUpdates = "Checking for updates…"
    /// Beneath Check for Updates…, and in General, in a build that doesn't update itself: one not
    /// signed as Tactile's releases are, or a fork's.
    public static let updatesOff = "Updates are off in this build of Tactile."
    public static func downloadingUpdate(_ version: String) -> String { "Downloading Tactile \(version)…" }
    public static func verifyingUpdate(_ version: String) -> String { "Verifying Tactile \(version)…" }
    public static func installingUpdate(_ version: String) -> String { "Installing Tactile \(version)…" }
    /// Beneath Installing: what happens next.
    public static let relaunchesInAMoment = "Tactile will quit and open again in a moment."

    /// A manual check that found nothing newer.
    public static func newestVersion(_ version: String) -> String { "Tactile \(version) is the newest version." }
    /// The update window's title for a newer version.
    public static func updateAvailable(_ version: String) -> String { "Tactile \(version) is available" }
    /// Beneath it: the version running.
    public static func youHave(_ version: String) -> String { "You have Tactile \(version)." }
    /// A newer version this Mac's macOS can't run.
    public static func needsNewerMacOS(version: String, minimum: String) -> String {
        "Tactile \(version) needs macOS \(minimum) or later."
    }
    /// The update window's title after a manual check failed.
    public static let couldntCheck = "Tactile couldn’t check for updates"

    // MARK: - Why a check or an install stopped

    /// One line for each reason, naming the site (`tactilemac.com`, or the preview site Tactile is
    /// pointed at). An install that stops changes nothing, so none of them says so.
    public static func updateFailure(_ failure: UpdateFailure, site: String) -> String {
        switch failure {
        case .siteUnreachable:
            return "Tactile couldn’t reach \(site). Check the connection, then try again."
        case .siteFailed(let status):
            return "\(site) couldn’t answer just now (error \(status)). Try again later."
        case .answerNotFromSite:
            return "The answer didn’t come from \(site), so Tactile ignored it."
        case .answerUnreadable:
            return "\(site) sent an answer this version of Tactile can’t read."
        case .translocated:
            return "macOS is running Tactile from a temporary copy. Move Tactile to the Applications folder, open it from there, and try again."
        case .folderNotWritable(let folder):
            let name = FileManager.default.displayName(atPath: folder)
            return "Tactile can’t replace itself in “\(name)”. Download the new version from \(site) instead."
        case .archiveNotOnSite:
            return "The update isn’t on \(site), so Tactile won’t download it."
        case .downloadFailed:
            return "The download didn’t finish. Try again."
        case .downloadNotFromSite:
            return "The download was sent somewhere other than \(site) or GitHub, so Tactile stopped it."
        case .sizeMismatch:
            return "The download isn’t the size it should be."
        case .digestMismatch:
            return "The download doesn’t match its checksum."
        case .unknownKey:
            return "The update is signed with a key this version of Tactile doesn’t know."
        case .badSignature:
            return "The update’s signature doesn’t match it."
        case .unpackFailed:
            return "The update couldn’t be unpacked."
        case .notOneApp:
            return "The update holds something other than Tactile."
        case .codeSignatureInvalid:
            return "The new Tactile isn’t signed by its developer."
        case .versionMismatch:
            return "The new Tactile isn’t the version that was offered."
        case .notNewer:
            return "The new Tactile isn’t newer than this one."
        case .couldNotPrepare:
            return "Tactile couldn’t prepare the update in its Caches folder."
        case .helperDidNotStart:
            return "Tactile couldn’t start replacing itself."
        case .cancelled:
            return "Cancelled."
        }
    }

    // MARK: - General

    public static let updates = "Updates"
    public static let checkAutomatically = "Check for updates automatically"
    /// Beneath Check for updates automatically.
    public static func checkAutomaticallyExplanation(site: String) -> String {
        "Once a day, from \(site). Nothing is installed until you choose to."
    }

    /// When a check last got an answer: "Last checked today at 10:42", "Last checked 12 Nov 2026 at
    /// 09:15", or "Not checked yet".
    public static func lastChecked(_ date: Date?, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        guard let date else { return "Not checked yet" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        formatter.formattingContext = .middleOfSentence
        return "Last checked \(formatter.string(from: date))"
    }
}
