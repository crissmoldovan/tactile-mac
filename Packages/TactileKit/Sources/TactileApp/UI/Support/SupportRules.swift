// The touchscreen check's interface rules, kept pure so they are tested: where the check is offered,
// which devices Touchscreen Check lists as not listed, each step's mark, what the "what will be
// sent" sheet offers at each stage, and the sizes of the check's window, its sheet and the file
// viewer.

import Foundation
import TactileDevices
import TactileScreens
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

/// Whether a check can start now: Check This Touchscreen… and Check…, for a touchscreen Tactile lists
/// or a device it doesn't.
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
        let leaving = leavingSetUp(touchscreen, finishing: finishing)
        guard leaving != .notConnected, leaving != .stoppedAnswering else { return leaving }
        return snapshot.setUp != nil || snapshot.setUpMode != nil ? .setUpRunning : leaving
    }

    /// As `of`, once set-up has let go: for set-up mode's session card, whose Check leaves set-up
    /// mode first.
    static func leavingSetUp(_ touchscreen: TouchscreenSnapshot, finishing: Bool = false) -> SupportCheckAvailability {
        guard touchscreen.isConnected else { return .notConnected }
        if touchscreen.status == .stoppedAnswering { return .stoppedAnswering }
        return available.whileFinishing(finishing)
    }

    /// For a device Tactile doesn't list, by the same rule: not once a check found it had stopped
    /// answering (`stoppedAnswering`), nor while a set-up runs, nor while an earlier check of it is
    /// still letting go (`finishing`).
    static func of(device: SupportDevice, in snapshot: AppSnapshot, finishing: Bool = false, stoppedAnswering: Bool = false)
        -> SupportCheckAvailability
    {
        if stoppedAnswering { return .stoppedAnswering }
        return snapshot.setUp != nil || snapshot.setUpMode != nil ? .setUpRunning : available.whileFinishing(finishing)
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

    /// The devices Tactile doesn't list, in Touchscreen Check: every device the check can check that
    /// isn't a connected touchscreen Tactile lists.
    static func unlisted(_ devices: [SupportDevice], in snapshot: AppSnapshot) -> [SupportDevice] {
        let listed = Set(snapshot.touchscreens.filter(\.isConnected).compactMap { device(for: $0, among: devices)?.id })
        return devices.filter { !listed.contains($0.id) }
    }
}

/// What Touchscreen Check, the sidebar's pane, lists: every connected touchscreen Tactile lists, in
/// the sidebar's order, then the touch devices it doesn't list. Each has Check…, enabled or disabled
/// by `SupportCheckAvailability`, with the reason when it can't be used.
struct TouchscreenCheckList: Equatable {
    /// A connected touchscreen Tactile lists.
    struct Listed: Equatable, Identifiable {
        var id: TouchscreenID
        var name: String
        /// Its device's own name, beneath, when the touchscreen has a name of its own; nil otherwise.
        var deviceName: String?
        var availability: SupportCheckAvailability
        var target: SupportTarget

        var reason: String? { availability == .available ? nil : Wording.supportUnavailable(availability) }
    }

    /// A touch device Tactile doesn't list.
    struct Unlisted: Equatable, Identifiable {
        var device: SupportDevice
        /// Its own name, or its USB ID.
        var name: String
        /// What kind it is, and its USB ID.
        var detail: String
        var availability: SupportCheckAvailability

        var id: String { device.id }
        var reason: String? { availability == .available ? nil : Wording.supportUnavailable(availability) }
    }

    var listed: [Listed]
    var unlisted: [Unlisted]

    /// `devices` are the check's devices as its probe finds them; `finishing`, the checks still
    /// letting go and the devices found to have stopped answering.
    @MainActor
    init(_ snapshot: AppSnapshot, devices: [SupportDevice], finishing: SupportChecksFinishing) {
        listed = snapshot.touchscreens.filter(\.isConnected).map { touchscreen in
            Listed(
                id: touchscreen.id, name: touchscreen.name,
                deviceName: touchscreen.deviceName.isEmpty || touchscreen.deviceName == touchscreen.name
                    ? nil : touchscreen.deviceName,
                availability: SupportCheckAvailability.of(
                    touchscreen, in: snapshot, finishing: finishing.isFinishing(touchscreen.id)),
                target: SupportTarget(touchscreen))
        }
        unlisted = SupportDeviceMatching.unlisted(devices, in: snapshot).map { device in
            Unlisted(
                device: device, name: Wording.supportDeviceName(device), detail: Wording.notListedDetail(device),
                availability: SupportCheckAvailability.of(
                    device: device, in: snapshot, finishing: finishing.isFinishing(device: device.id),
                    stoppedAnswering: finishing.hasStoppedAnswering(device)))
        }
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

/// The check window's frame on the screen that shows it: `content` and the title bar, in the middle
/// of the screen's visible frame, but never larger than that frame less `margin` all round. The
/// window opens on the touchscreen's own display, which can be a short bar.
///
/// It is taller than the check itself needs, so that on an ordinary display the sheet shows every
/// file of the report and the form without scrolling. It isn't resizable: on a short display it
/// takes what there is, and the sheet fits that (`SupportSheetFit`).
enum SupportCheckWindowFrame {
    /// The window's content where there is room.
    static let content = CGSize(width: 780, height: 700)
    /// Kept clear between the window and the edges of the visible frame, when it has to shrink.
    static let margin: CGFloat = 8

    /// The frame on a screen whose visible frame is `visible`, for a window whose title bar is
    /// `titleBar` points tall.
    static func frame(in visible: CGRect, titleBar: CGFloat) -> CGRect {
        let width = max(0, min(content.width, visible.width - 2 * margin)).rounded(.down)
        let height = max(0, min(content.height + titleBar, visible.height - 2 * margin)).rounded(.down)
        return CGRect(x: (visible.midX - width / 2).rounded(), y: (visible.midY - height / 2).rounded(),
                      width: width, height: height)
    }
}

/// How the "what will be sent" sheet, and the file viewer on it, fit what shows them. On macOS 26 a
/// sheet is drawn inside its window and cut to it; on earlier macOS it hangs from the title bar, and
/// runs past the bottom of a window shorter than it. So each is no larger than what shows it, less
/// `margin` all round: the sheet within the check window's content, the viewer within the sheet.
/// Inside, the title stays at the top and the buttons at the bottom; what lies between scrolls, and
/// the file list gives up height first, down to about four rows.
enum SupportSheetFit {
    /// The sheet's size where there is room.
    static let idealSheet = CGSize(width: 580, height: 720)
    /// The file viewer's size where there is room. No sheet is that wide, so it is always as wide as
    /// the sheet less the margins.
    static let idealViewer = CGSize(width: 640, height: 520)
    /// Kept clear between a sheet and the edges of what shows it.
    static let margin: CGFloat = 12
    /// The file list's height where there is room: every file of a report.
    static let fileListHeight: CGFloat = 285
    /// The least the file list shrinks to: four rows and a little of the next, so it shows there is more.
    static let fileListMinimum: CGFloat = 136

    /// The sheet's size in a window whose content is `room`.
    static func sheet(in room: CGSize) -> CGSize {
        fit(idealSheet, in: room)
    }

    /// The file viewer's size on a sheet of `sheet`.
    static func viewer(on sheet: CGSize) -> CGSize {
        fit(idealViewer, in: sheet)
    }

    private static func fit(_ ideal: CGSize, in room: CGSize) -> CGSize {
        CGSize(width: max(0, min(ideal.width, room.width - 2 * margin)).rounded(.down),
               height: max(0, min(ideal.height, room.height - 2 * margin)).rounded(.down))
    }
}
