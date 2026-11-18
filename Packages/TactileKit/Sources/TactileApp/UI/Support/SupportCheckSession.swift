// One touchscreen check, as its window runs it: the probe and the check, the clock that ends each
// touch step, the model told to let go of a touchscreen it lists and to take it back, the report made
// for the sheet, and sending it or saving it. Its live pieces come in `SupportSessionEnvironment`, so
// the tests run it with a fake HID system, a fake transport and a log book of their own.

import AppKit
import Observation
import UniformTypeIdentifiers
import TactileDevices
import TactileScreens
import TactileSupport
import TactileUpdates

/// Everything live a check's session uses.
struct SupportSessionEnvironment {
    /// Lists the devices and takes the one checked. The session starts it, and stops it when it ends.
    var probe: SupportProbe
    /// Whether this build sends, and where.
    var sending: SupportSending
    var transport: SupportTransport
    /// What Tactile did with each device this session: the report's log.
    var logBook: DeviceLogBook
    var mac: @MainActor () -> SupportMac
    /// The host's clock, the one reports carry.
    var now: @MainActor () -> TimeInterval
    /// Whether a timer ends each step; the tests tick by hand.
    var ticks: Bool
    var temporary: URL
    var home: String

    /// The app's: IOKit, the update decision (only the official build sends, to its update site),
    /// URLSession, the app's log book, this Mac, `systemUptime`.
    @MainActor
    static func live() -> SupportSessionEnvironment {
        SupportSessionEnvironment(
            probe: SupportProbe(),
            sending: SupportSending.decide(
                UpdateAvailability.current(), overrideBaseURL: UserDefaults.standard.string(forKey: UpdateSite.overrideKey)),
            transport: URLSessionSupportTransport(), logBook: .shared,
            mac: { SupportMac.current(displays: NSScreen.screens.count) }, now: { ProcessInfo.processInfo.systemUptime },
            ticks: true, temporary: FileManager.default.temporaryDirectory, home: NSHomeDirectory())
    }
}

/// A check under way in the window, from opening to closing. The views read it and call it.
/// Nothing leaves the Mac until Send, and nothing is kept once it closes.
///
/// - **Start Check** goes ahead only while Tactile can let go of the touchscreen it lists
///   (`startAvailability`, from the model's snapshot now), and only once the model has let go of it:
///   otherwise it says why, and opens nothing.
/// - **Tactile takes the touchscreen back** once the check has let the device go, on every way out,
///   and never while the check still holds it (a read can be under way off the main thread).
/// - **An interrupted check** (sleep, unplugging, a device that couldn't be opened) has no verdict
///   and no report: the person tries again.
/// - **Sending** asks the site whether it takes reports only when the person presses Send. Stop
///   Sending, Esc, or closing the window while it goes cancels it, and says whether the report may
///   already have reached the site.
@MainActor
@Observable
final class SupportCheckSession {
    /// What the window is for: its name, and the touchscreen Tactile lists it as, if it does.
    let name: String
    let touchscreen: TouchscreenID?
    /// The check, once the device was found; nil when it wasn't (`Wording.supportCantFind`).
    @ObservationIgnored private(set) var check: SupportCheck?
    /// Bumped on every change of the check, so the views follow it.
    private(set) var revision = 0
    /// The host's clock, as of the last tick: for the countdown.
    private(set) var now: TimeInterval
    /// Why Start Check didn't go ahead, the last time it was pressed.
    private(set) var startRefusal: String?

    // The sheet.
    var isShowingSheet = false
    var form = SupportSendForm()
    private(set) var archive: SupportArchive?
    private(set) var archiveFailure: SupportArchiveFailure?
    private(set) var sendStage: SupportSendStage
    private(set) var savedAs: String?
    private(set) var saveFailed = false
    /// How sending ended when the window closed while it went: `.mayHaveBeenSent` or `.notSent`.
    private(set) var closedWhileSending: SupportSendStage?

    /// Closes the window: Done. The window sets it.
    @ObservationIgnored var close: @MainActor () -> Void = {}

    @ObservationIgnored private let environment: SupportSessionEnvironment
    @ObservationIgnored private let perform: PerformCommand
    @ObservationIgnored private let snapshot: @MainActor () -> AppSnapshot?
    @ObservationIgnored private var timer: Timer?
    /// The model was asked to let go of `touchscreen`, and hasn't been told to take it back.
    @ObservationIgnored private var holdsTouchscreen = false
    /// The take is under way: Tactile mustn't take the touchscreen back until it is over.
    @ObservationIgnored private var isTaking = false
    /// The start, the report and a send, while under way.
    @ObservationIgnored private(set) var starting: Task<Void, Never>?
    @ObservationIgnored private(set) var preparing: Task<Void, Never>?
    @ObservationIgnored private(set) var sendingTask: Task<Void, Never>?
    /// The upload itself began: the report may have reached the site.
    @ObservationIgnored private var uploadBegan = false

    /// Starts listing devices, and finds the one that is `touchscreen`, or else `deviceID`'s. Nothing
    /// is opened yet. `snapshot` is the model's now, for a touchscreen it lists.
    init(deviceID: String?, touchscreen: SupportTarget?, name: String, perform: @escaping PerformCommand,
         snapshot: @escaping @MainActor () -> AppSnapshot?, environment: SupportSessionEnvironment) {
        self.name = DeviceText.clean(name)
        self.touchscreen = touchscreen?.id
        self.perform = perform
        self.snapshot = snapshot
        self.environment = environment
        now = environment.now()
        sendStage = environment.sending == .off ? .off : .ready
        let probe = environment.probe
        probe.start()
        let device = touchscreen.flatMap { SupportDeviceMatching.device(for: $0, among: probe.devices) }
            ?? probe.devices.first { $0.id == deviceID }
        if let device {
            let check = SupportCheck(device: device, probe: probe)
            check.onChange = { [weak self] in self?.checkChanged() }
            self.check = check
        }
        InterfaceLog.log.info("touchscreen check opened for \(device?.usbID ?? "a device that wasn't found", privacy: .public)")
    }

    var device: SupportDevice? { check?.device }

    /// Whether Start Check can go ahead now: for a touchscreen Tactile lists, as the model's snapshot
    /// says (no set-up running, not held shared); always for a device it doesn't.
    var startAvailability: SupportCheckAvailability {
        guard let touchscreen else { return .available }
        guard let snapshot = snapshot(), let listed = snapshot.touchscreens.first(where: { $0.id == touchscreen }) else {
            return .notConnected
        }
        return SupportCheckAvailability.of(listed, in: snapshot)
    }

    // MARK: - The steps

    /// Start Check: the model lets go of the touchscreen it lists, then the check takes it, its reads
    /// off the main thread.
    func start() {
        guard let check, check.stage == .ready, starting == nil else { return }
        if let touchscreen {
            let availability = startAvailability
            guard availability == .available else {
                startRefusal = Wording.supportUnavailable(availability)
                return
            }
            perform(.beginSupportCheck(touchscreen))
            guard snapshot()?.touchscreens.first(where: { $0.id == touchscreen })?.mode == .released else {
                // The model didn't let go: nothing is opened, and nothing it holds is touched.
                perform(.endSupportCheck)
                startRefusal = Wording.supportLetGoRefused
                return
            }
            holdsTouchscreen = true
        }
        startRefusal = nil
        isTaking = true
        let environment = environment
        starting = Task { @MainActor in
            // A turn first, so the window says it is reading before the reads begin.
            await Task.yield()
            await check.start(at: environment.now())
            isTaking = false
            now = environment.now()
            if check.stage == .finished {
                giveBack()
            } else if environment.ticks {
                startTimer()
            }
        }
    }

    func skip() {
        check?.skip(at: environment.now())
    }

    /// The window's timer: the countdown, and the step's end.
    func tick() {
        now = environment.now()
        check?.tick(at: now)
    }

    /// The window closed, the Mac is going to sleep, or Tactile is quitting: the check stops, the
    /// device is let go, sending stops, and Tactile takes its touchscreen back once the device is free.
    func stop() {
        timer?.invalidate()
        timer = nil
        preparing?.cancel()
        if sendStage == .sending {
            cancelSending()
            closedWhileSending = sendStage
        }
        check?.stop(at: environment.now())
        environment.probe.stop()
        if !isTaking { giveBack() }
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func checkChanged() {
        revision &+= 1
        guard check?.stage == .finished else { return }
        timer?.invalidate()
        timer = nil
        if !isTaking { giveBack() }
    }

    /// Tactile takes its touchscreen back, once.
    private func giveBack() {
        guard holdsTouchscreen else { return }
        holdsTouchscreen = false
        perform(.endSupportCheck)
    }

    // MARK: - The sheet

    /// Send to Tactile's Developer…: the report is made, with the log book's lines about the device
    /// and the Mac's facts. Nothing is asked of any site. An interrupted check has no report.
    func showSheet() {
        guard let check, check.stage == .finished, !check.wasInterrupted else { return }
        isShowingSheet = true
        guard preparing == nil else { return }
        let device = check.device
        let environment = environment
        let serials = Array(Set(environment.probe.devices.map(\.serial) + [device.serial]
                                + (snapshot()?.touchscreens.map(\.serial) ?? [])))
        let lines = SupportLog.lines(environment.logBook.entries(about: Set(device.interfaces.map(\.id))),
                                     serials: serials, home: environment.home)
        let input = SupportReportInput(check: check, logLines: lines, mac: environment.mac())
        preparing = Task { @MainActor in
            let made = await SupportArchiver.make(input, temporary: environment.temporary)
            guard !Task.isCancelled else { return }
            switch made {
            case .success(let archive): self.archive = archive
            case .failure(let failure): self.archiveFailure = failure
            }
        }
    }

    /// Send: asks the site whether it takes reports, then uploads.
    func send() {
        guard case .on(let site) = environment.sending, let archive, let check, !check.wasInterrupted, form.isReady,
              sendStage != .sending, sendStage != .sent, sendStage != .mayHaveBeenSent else { return }
        let input = SupportReportInput(check: check, logLines: [], mac: environment.mac())
        guard let request = SupportRequest(bundle: archive.data, input: input, email: form.email, note: form.note) else {
            sendStage = .unavailable
            return
        }
        sendStage = .sending
        uploadBegan = false
        let uploader = SupportUploader(site: site, transport: environment.transport)
        sendingTask = Task { @MainActor in
            let available = await uploader.isAvailable()
            guard !Task.isCancelled else { return }
            guard available else {
                sendStage = .unavailable
                return
            }
            uploadBegan = true
            let answer = await uploader.upload(request)
            guard !Task.isCancelled else { return }
            switch answer {
            case .sent: sendStage = .sent
            case .refused(_, let reason): sendStage = .refused(reason)
            case .tryLater: sendStage = .tryLater
            case .tooSlow: sendStage = .tooSlow
            case .unavailable: sendStage = .unavailable
            }
            InterfaceLog.log.info("touchscreen check: the site answered \(String(describing: self.sendStage), privacy: .public)")
        }
    }

    /// Stop Sending, or Esc, while it goes: the request is cancelled. Before the upload began nothing
    /// was sent; after, the report may already have reached the site, and the person is told so.
    func cancelSending() {
        guard sendStage == .sending else { return }
        sendingTask?.cancel()
        sendStage = uploadBegan ? .mayHaveBeenSent : .notSent
        InterfaceLog.log.info("touchscreen check: sending stopped (\(String(describing: self.sendStage), privacy: .public))")
    }

    /// Save Report…: the same zip, wherever the person chooses.
    func save() {
        guard archive != nil, let device else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Wording.reportFileName(usbID: device.usbID)
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        save(to: url)
    }

    /// Writes the zip to `url`.
    func save(to url: URL) {
        guard let archive else { return }
        do {
            try archive.data.write(to: url, options: .atomic)
            savedAs = url.lastPathComponent
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }

    func openGitHub() {
        NSWorkspace.shared.open(SupportLinks.touchscreenReport)
    }
}
