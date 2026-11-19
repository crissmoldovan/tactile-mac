// The touchscreen check's interface rules, kept pure so they are tested: where the check is offered,
// which devices Touchscreen Not Listed? shows, each step's mark, and what the "what will be sent"
// sheet offers at each stage.

import Foundation
import TactileDevices
import TactileSupport

/// Where Tactile's issue form for touchscreens is.
enum SupportLinks {
    static let touchscreenReport = URL(string: "https://github.com/crissmoldovan/tactile-mac/issues/new?template=touchscreen_report.yml")!
}

/// What the person is told when the check's window closes while a report goes.
enum SupportClosingNotice {
    /// An alert's title and text when the report may already have reached the site; nil when nothing
    /// was sent, and always while Tactile quits: quitting never waits on a click (the window logs it).
    static func alert(closedWhileSending: SupportSendStage?, isQuitting: Bool) -> (title: String, detail: String)? {
        guard closedWhileSending == .mayHaveBeenSent, !isQuitting else { return nil }
        return (Wording.sendingMayHaveBeenSentTitle, Wording.sendingMayHaveBeenSentDetail)
    }
}

/// Whether Help Me Support This Touchscreen… can start now, for a touchscreen Tactile lists.
enum SupportCheckAvailability: Equatable, Sendable {
    case available
    case notConnected
    /// A set-up has the touchscreens: the model won't let go of one.
    case setUpRunning
    /// An earlier check of it was closed during a read, and hasn't let go yet: a new one couldn't
    /// open it. It clears by itself once that check has let go (`SupportChecksFinishing`).
    case lastCheckFinishing
    /// An earlier check found it had stopped answering: taking it again could wait for it for good.
    /// It clears when it is plugged in again (`TouchscreenStatus.stoppedAnswering`, and
    /// `SupportChecksFinishing` for a device Tactile doesn't list).
    case stoppedAnswering

    /// Any connected touchscreen, whatever Tactile makes of it (one it can't use, or can only share
    /// with macOS, is just the kind to check), unless it has stopped answering, a set-up runs or,
    /// `finishing`, an earlier check of it is still letting go.
    static func of(_ touchscreen: TouchscreenSnapshot, in snapshot: AppSnapshot, finishing: Bool = false) -> SupportCheckAvailability {
        guard touchscreen.isConnected else { return .notConnected }
        if touchscreen.status == .stoppedAnswering { return .stoppedAnswering }
        if snapshot.setUp != nil || snapshot.setUpMode != nil { return .setUpRunning }
        return available.whileFinishing(finishing)
    }

    /// This, or `lastCheckFinishing` when it would be available and an earlier check is still
    /// letting go.
    func whileFinishing(_ finishing: Bool) -> SupportCheckAvailability {
        finishing && self == .available ? .lastCheckFinishing : self
    }
}

/// Matching the check's devices with the touchscreens Tactile lists.
enum SupportDeviceMatching {
    /// The device that is this connected touchscreen: the same USB ID at the same location, or, with
    /// no location, the same USB ID and serial number.
    static func device(for touchscreen: TouchscreenSnapshot, among devices: [SupportDevice]) -> SupportDevice? {
        device(for: SupportTarget(touchscreen), among: devices)
    }

    static func device(for target: SupportTarget, among devices: [SupportDevice]) -> SupportDevice? {
        let candidates = devices.filter { $0.usbID == target.usbID.lowercased() }
        if let location = target.location?.lowercased() {
            return candidates.first { $0.location == location }
        }
        return candidates.first { $0.location == nil && $0.serial == target.serial }
            ?? candidates.first { $0.location == nil }
    }

    /// Touchscreen Not Listed?'s devices: every device the check can check that isn't a connected
    /// touchscreen Tactile lists.
    static func unlisted(_ devices: [SupportDevice], in snapshot: AppSnapshot) -> [SupportDevice] {
        let listed = Set(snapshot.touchscreens.filter(\.isConnected).compactMap { device(for: $0, among: devices)?.id })
        return devices.filter { !listed.contains($0.id) }
    }
}

/// The mark beside each of the four steps.
enum SupportStepMark: Equatable, Sendable {
    case pending, current, done, skipped
}

/// The four steps' marks: what it is, switches, touches, verdict.
struct SupportStepMarks: Equatable {
    var marks: [SupportStepMark]

    init(stage: SupportCheck.Stage, steps: [SupportTouchStep], interrupted: Bool = false) {
        switch stage {
        case .ready:
            marks = [.current, .pending, .pending, .pending]
        case .taking:
            marks = [.done, .current, .pending, .pending]
        case .touching:
            marks = [.done, .done, .current, .pending]
        case .finished where interrupted:
            // No verdict for a check that didn't run its course.
            marks = [.done, steps.isEmpty ? .skipped : .done, .skipped, .skipped]
        case .finished:
            marks = [.done, .done, .done, .done]
        }
    }
}

/// The sheet's email and note, as typed.
struct SupportSendForm: Equatable {
    var email = ""
    var note = ""

    /// Nil while the field is empty or the address looks right.
    var emailProblem: String? {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.isEmpty || SupportForm.isEmail(email) ? nil : Wording.emailInvalid
    }

    var noteProblem: String? {
        SupportForm.noteProblem(note) == nil ? nil : Wording.noteTooLong
    }

    var isReady: Bool {
        SupportForm.isEmail(email.trimmingCharacters(in: .whitespacesAndNewlines)) && noteProblem == nil
    }

    var noteCount: String { Wording.noteCount(SupportForm.cleanNote(note).count) }
}

/// Where sending stands.
enum SupportSendStage: Equatable, Sendable {
    /// Not the official build: it only saves the report.
    case off
    /// The official build: the email and note, and Send.
    case ready
    /// Asking the site whether it takes reports, then uploading.
    case sending
    /// Sending was stopped before the upload began: nothing was sent.
    case notSent
    /// Sending was stopped during the upload: the report may already have reached the site.
    case mayHaveBeenSent
    case sent
    /// The site refused it, with this reason. The person can fix the email and send again.
    case refused(String)
    case tryLater
    /// The upload took too long: Save Report…, or Send again.
    case tooSlow
    /// The site doesn't take reports now: only Save Report….
    case unavailable
}

/// What the sheet shows at a stage.
struct SupportSendSheetContent: Equatable {
    var showsForm: Bool
    var formIsEnabled: Bool
    var showsSend: Bool
    var sendEnabled: Bool
    var showsSaveReport: Bool
    /// A line about where sending stands, when there is one.
    var message: String?
    var showsGitHub: Bool
    /// Its cancel button stops the sending under way (Stop Sending), rather than closing the sheet.
    var stopsSending = false

    init(stage: SupportSendStage, form: SupportSendForm, saved: Bool) {
        switch stage {
        case .off:
            self.init(form: false, send: false, message: Wording.sendingOff, gitHub: true)
        case .ready:
            self.init(form: true, send: true, message: nil, gitHub: saved)
        case .sending:
            self.init(form: true, send: true, message: Wording.sending, gitHub: saved)
            formIsEnabled = false
            sendEnabled = false
            stopsSending = true
        case .notSent:
            self.init(form: true, send: true, message: Wording.sendingNotSent, gitHub: saved)
        case .mayHaveBeenSent:
            self.init(form: false, send: false, message: Wording.sendingMayHaveBeenSent, gitHub: saved)
        case .sent:
            self.init(form: false, send: false, message: Wording.reportSent, gitHub: false)
            showsSaveReport = false
        case .refused(let reason):
            self.init(form: true, send: true, message: reason, gitHub: saved)
        case .tryLater:
            self.init(form: true, send: true, message: Wording.tryLater, gitHub: saved)
        case .tooSlow:
            self.init(form: true, send: true, message: Wording.sendingTooSlow, gitHub: saved)
        case .unavailable:
            self.init(form: false, send: false, message: Wording.sendingUnavailable, gitHub: true)
        }
        if showsSend, formIsEnabled { sendEnabled = form.isReady }
    }

    private init(form: Bool, send: Bool, message: String?, gitHub: Bool) {
        showsForm = form
        formIsEnabled = form
        showsSend = send
        sendEnabled = send
        showsSaveReport = true
        self.message = message
        showsGitHub = gitHub
    }
}
