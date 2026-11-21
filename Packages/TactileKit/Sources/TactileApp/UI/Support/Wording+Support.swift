// Every word of the touchscreen check: the entries that start it (Touchscreen Check in the sidebar,
// Check This Touchscreen… in a touchscreen's header, in its details beside the menu and on set-up
// mode's session card), its window, its steps, its verdict and the "what will be sent" sheet. Short
// sentences, British spelling, typographic apostrophes.

import Foundation
import TactileDevices
import TactileSupport

extension Wording {

    // MARK: - Where it starts

    /// A touchscreen's header, its details beside the menu, and set-up mode's session card with one
    /// touchscreen.
    static let checkThisTouchscreen = "Check This Touchscreen…"
    /// The sidebar's item, its pane's title, and the check window's title.
    static let touchscreenCheck = "Touchscreen Check"
    /// What the pane is for, in a line.
    static let checkIntro =
        "Check what a touchscreen sends. You can then send the results to Tactile’s developer, to help it work fully."
    /// Set-up mode's session card: one touchscreen, with Check This Touchscreen… beside it.
    static let setUpModeCheckLine = "Touch not working right?"
    /// Set-up mode's session card: several touchscreens, each line with Check….
    static let setUpModeCheckEachLine = "Touch not working right? Click Check… beside the touchscreen."

    static func supportUnavailable(_ reason: SupportCheckAvailability) -> String {
        switch reason {
        case .available: return ""
        case .notConnected: return "Connect it first."
        case .setUpRunning: return "Not while a set-up runs."
        case .lastCheckFinishing: return "The last check is still finishing. Try again in a moment."
        case .stoppedAnswering: return itStoppedAnswering
        }
    }

    /// Step 1, for a touchscreen Tactile can only share with macOS (or once the check has opened it
    /// shared).
    static let supportShared =
        "Tactile can only share this touchscreen with macOS, so macOS may also act on your touches during the check."
    static let supportLetGoRefused = "Tactile couldn’t let go of the touchscreen just now. Try again in a moment."
    static let readingTouchscreen = "Reading the touchscreen…"
    static let interruptedTitle = "Interrupted"
    static let tryAgain = "Close this window, then start the check again."
    static let stopSending = "Stop Sending"

    static let notListedTitle = "Touchscreen Not Listed?"
    static let notListedExplanation =
        "Touch devices Tactile doesn’t list show here: digitisers, and touchscreens that only act as a mouse. "
        + "Check one, so Tactile can learn to support it."
    static let notListedNone = "No other touch devices are connected."
    static let checkButton = "Check…"

    /// The device's own name, or its USB ID.
    static func supportDeviceName(_ device: SupportDevice) -> String {
        let name = device.product.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "USB device \(device.usbID)" : name
    }

    /// "Acts only as a mouse · 1234:5678".
    static func notListedDetail(_ device: SupportDevice) -> String {
        let kind: String
        switch device.kind {
        case .touchscreen: kind = "A touchscreen"
        case .digitizer: kind = "A digitiser"
        case .mouseOnly: kind = "Acts only as a mouse"
        }
        return "\(kind) · \(device.usbID)"
    }

    // MARK: - The window

    static func supportWindowTitle(name: String) -> String { "\(touchscreenCheck): \(name)" }

    static let supportIntro =
        "This takes a minute. Tactile reads what the touchscreen says about itself, takes it as it always does, and asks you "
        + "to touch it with one, two and five fingers. Nothing leaves this Mac unless you send it."
    static let supportLetGo =
        "During the check, touches don’t click anything. Use your mouse or trackpad for the buttons."
    static let supportCantFind = "Tactile can’t find this touchscreen’s details. Unplug it, plug it in again, and try again."
    static let startCheck = "Start Check"
    static let skip = "Skip"

    static let supportStepTitles = ["What it is", "Switches", "Touches", "Verdict"]

    /// The plain sentence under step `index` (0 to 3).
    static func supportStepSentence(_ index: Int, kind: SupportDeviceKind, hasTouchInterface: Bool = true) -> String {
        switch index {
        case 0: return "What it says about itself. Nothing is written to it."
        case 1:
            if kind == .mouseOnly { return "It only acts as a mouse, so there is nothing to switch." }
            return hasTouchInterface
                ? "Tactile takes it as it always does: it reads its settings, then switches it to multi-touch where it can."
                : "Tactile drives only touchscreens, so it switches nothing here. It only listens."
        case 2: return "Touch it when asked. Each step lasts up to 15 seconds."
        default: return "What Tactile made of it."
        }
    }

    /// Step 1's facts, a line each.
    static func identityLines(_ device: SupportDevice, _ identity: SupportIdentity) -> [String] {
        var lines = ["USB ID \(device.usbID)" + (device.manufacturer.isEmpty ? "." : ", made by \(device.manufacturer).")]
        lines.append(interfacesLine(identity.interfaces.map(\.role)))
        if identity.fingerCollections > 0 {
            lines.append("Up to \(identity.fingerCollections) \(identity.fingerCollections == 1 ? "finger" : "fingers") in one report.")
        }
        if device.kind != .mouseOnly {
            lines.append(identity.hasInputMode ? "It can be switched to multi-touch." : "It has no multi-touch switch.")
        }
        return lines
    }

    /// "2 interfaces: touch and mouse.", "3 interfaces: touch, mouse and 1 other."
    static func interfacesLine(_ roles: [SupportInterface.Role]) -> String {
        let named = roles.filter { $0 != .other }.map(\.rawValue)
        let others = roles.count - named.count
        let parts = named + (others > 0 ? ["\(others) other"] : [])
        let list = parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + parts.last! : parts.first ?? ""
        return "\(roles.count) \(roles.count == 1 ? "interface" : "interfaces"): \(list)."
    }

    /// Step 2, in a line.
    static func switchesLine(_ switches: SupportSwitches?, kind: SupportDeviceKind) -> String? {
        guard let switches else { return nil }
        if switches.opens.allSatisfy({ $0.held == .notOpened }) { return "It couldn’t be opened." }
        if kind != .touchscreen, switches.hasInputMode == nil { return "Opened. Nothing to switch." }
        if switches.hasInputMode == true {
            return switches.inputModeWrite?.result == 0 ? "Switched to multi-touch." : "It refused the switch to multi-touch."
        }
        return "Read. It has no multi-touch switch."
    }

    static func touchPrompt(_ fingers: SupportFingers) -> String {
        switch fingers {
        case .one: return "Touch the screen with one finger. Hold it still for a moment, then move it."
        case .two: return "Now touch it with two fingers, and move them."
        case .five: return "Now touch it with five fingers, and move them."
        }
    }

    static func touchStepOf(_ fingers: SupportFingers) -> String {
        let index = (SupportFingers.allCases.firstIndex(of: fingers) ?? 0) + 1
        return "Step \(index) of \(SupportFingers.allCases.count)"
    }

    /// The seconds left, rounded up: "13 s".
    static func secondsLeft(_ seconds: TimeInterval) -> String {
        "\(Int(max(0, seconds).rounded(.up))) s"
    }

    static func fingersSeen(_ most: Int) -> String {
        switch most {
        case 0: return "Nothing yet."
        case 1: return "Seen: 1 finger."
        default: return "Seen: up to \(most) fingers at once."
        }
    }

    // MARK: - The verdict

    static func verdictTitle(_ verdict: SupportVerdict) -> String {
        switch verdict {
        case .worksFully: return "Works fully"
        case .worksWithOneFinger: return "Works with one finger"
        case .doesNotWork: return "Doesn’t work"
        }
    }

    static func verdictSentence(_ reason: SupportVerdictReason) -> String {
        switch reason {
        case .severalFingersFromTouchInterface: return "Tactile saw several fingers at once through its touch interface."
        case .oneFingerFromTouchInterface: return "Tactile only saw one finger at a time."
        case .oneFingerFromMouseInterface: return "It only sends one finger, as a mouse."
        case .reportsNotReadable: return "Its reports came, but Tactile couldn’t read a touch from them."
        case .noReports: return "Nothing came from it."
        }
    }

    static func supportInterruption(_ interruption: SupportCheck.Interruption) -> String {
        switch interruption {
        case .notConnected: return "It wasn’t connected when the check began."
        case .couldNotOpen: return "Tactile couldn’t open it. Another program may be using it."
        case .unplugged: return "It was unplugged, so the check stopped."
        case .stopped: return "The check stopped when the Mac went to sleep."
        }
    }

    static let supportDone = "Done"
    static let sendToDeveloper = "Send to Tactile’s Developer…"
    static let sendAnyway = "Send the Results Anyway…"
    static let worksFullyThanks = "Thank you. Sending the results still helps: others will know it works."

    // MARK: - What will be sent

    static let sendSheetTitle = "What will be sent"
    static let sendSheetIntro = "These files, and nothing else. Open any of them to see exactly what it holds."
    static let openFile = "Open"
    static let close = "Close"
    static let emailLabel = "Your email"
    static let emailPrompt = "So we can reply"
    static let noteLabel = "Anything else we should know?"
    static let notePrompt = "Optional"
    static let supportPrivacy = "We use this only to help with your touchscreen, and delete it on request."
    static let send = "Send"
    static let sending = "Sending…"
    static let saveReport = "Save Report…"
    static let emailInvalid = "That email address doesn’t look right."
    static let noteTooLong = "The note is longer than 1,000 characters."
    static let sendingNotSent = "Sending stopped. Nothing was sent."
    static let sendingMayHaveBeenSentTitle = "Your report may already have been sent."
    static let sendingMayHaveBeenSentDetail =
        "Check your email: nothing is filed until you confirm it. If you’d rather it wasn’t filed, ignore that email."
    static let sendingMayHaveBeenSent = sendingMayHaveBeenSentTitle + " " + sendingMayHaveBeenSentDetail
    static let reportSent = "Check your email to confirm. Nothing is filed until you do."
    static let tryLater = "Too many reports from here just now. Try again later, or save the report."
    static let sendingTooSlow = "Sending took too long. You can save the report instead."
    static let sendingUnavailable =
        "Sending isn’t available yet. Save the report, then attach it to a touchscreen report on GitHub."
    static let sendingOff =
        "This build of Tactile doesn’t send reports. Save the report, then attach it to a touchscreen report on GitHub."
    static let githubIsPublic = "GitHub issues are public. The report holds no personal data: only the files listed above."
    static let openGitHubReport = "Open a Touchscreen Report on GitHub"
    static let makingReport = "Making the report…"
    static let saveFailed = "The report couldn’t be saved."

    static func reportSaved(_ name: String) -> String { "Saved as \(name)." }

    static func reportFailed(_ failure: SupportArchiveFailure) -> String {
        switch failure {
        case .couldNotWrite, .couldNotZip: return "The report couldn’t be made."
        case .tooLarge: return "The report is too large to send, even cut down."
        }
    }

    /// "1,001 / 1,000".
    static func noteCount(_ count: Int) -> String {
        "\(count.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_GB")))) / 1,000"
    }

    /// "812 bytes", "15 KB", "1.5 MB".
    static func fileSize(_ bytes: Int) -> String {
        if bytes < 1024 { return bytes == 1 ? "1 byte" : "\(bytes) bytes" }
        if bytes < 1024 * 1024 { return "\(Int((Double(bytes) / 1024).rounded())) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }

    /// The name Save Report… offers.
    static func reportFileName(usbID: String) -> String {
        "tactile-report-\(usbID.replacingOccurrences(of: ":", with: "-")).zip"
    }
}
