// One touchscreen check, as its window runs it: the probe and the check, the clock that ends each
// touch step, the model told to let go of a touchscreen it lists and to take it back, the report made
// for the sheet, and sending it or saving it. Its live pieces come in `SupportSessionEnvironment`, so
// the tests run it with a fake HID system, a fake transport and no system log.

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
    /// This process's entries in Tactile's log.
    var readLog: @Sendable () -> [SupportLogEntry]
    var mac: @MainActor () -> SupportMac
    /// The host's clock, the one reports carry.
    var now: @MainActor () -> TimeInterval
    /// Whether a timer ends each step; the tests tick by hand.
    var ticks: Bool
    var temporary: URL
    var home: String

    /// The app's: IOKit, the update decision (only the official build sends, to its update site),
    /// URLSession, `OSLogStore`, this Mac, `systemUptime`.
    @MainActor
    static func live() -> SupportSessionEnvironment {
        SupportSessionEnvironment(
            probe: SupportProbe(),
            sending: SupportSending.decide(
                UpdateAvailability.current(), overrideBaseURL: UserDefaults.standard.string(forKey: UpdateSite.overrideKey)),
            transport: URLSessionSupportTransport(), readLog: { SupportLog.readThisProcess() },
            mac: { SupportMac.current(displays: NSScreen.screens.count) }, now: { ProcessInfo.processInfo.systemUptime },
            ticks: true, temporary: FileManager.default.temporaryDirectory, home: NSHomeDirectory())
    }
}

/// A check under way in the window, from opening to closing. The views read it and call it.
/// Nothing leaves the Mac until Send, and nothing is kept once it closes.
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

    // The sheet.
    var isShowingSheet = false
    var form = SupportSendForm()
    private(set) var archive: SupportArchive?
    private(set) var archiveFailure: SupportArchiveFailure?
    private(set) var sendStage: SupportSendStage
    private(set) var savedAs: String?
    private(set) var saveFailed = false

    /// Closes the window: Done. The window sets it.
    @ObservationIgnored var close: @MainActor () -> Void = {}

    @ObservationIgnored private let environment: SupportSessionEnvironment
    @ObservationIgnored private let perform: PerformCommand
    @ObservationIgnored private var timer: Timer?
    /// The model was asked to let go of `touchscreen`, and hasn't been told to take it back.
    @ObservationIgnored private var holdsTouchscreen = false
    /// The sheet's report and status, and a send, while under way.
    @ObservationIgnored private(set) var preparing: Task<Void, Never>?
    @ObservationIgnored private(set) var sendingTask: Task<Void, Never>?

    /// Starts listing devices, and finds the one that is `touchscreen`, or else `deviceID`'s. Nothing
    /// is opened yet.
    init(deviceID: String?, touchscreen: SupportTarget?, name: String, perform: @escaping PerformCommand,
         environment: SupportSessionEnvironment) {
        self.name = name
        self.touchscreen = touchscreen?.id
        self.perform = perform
        self.environment = environment
        now = environment.now()
        sendStage = environment.sending == .off ? .off : .checking
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

    // MARK: - The steps

    /// Start Check: the model lets go of the touchscreen it lists, then the check takes it.
    func start() {
        guard let check, check.stage == .ready else { return }
        if let touchscreen {
            perform(.beginSupportCheck(touchscreen))
            holdsTouchscreen = true
        }
        now = environment.now()
        check.start(at: now)
        if check.stage != .finished, environment.ticks { startTimer() }
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
    /// device is let go, and Tactile takes its touchscreen back.
    func stop() {
        timer?.invalidate()
        timer = nil
        check?.stop(at: environment.now())
        environment.probe.stop()
        giveBack()
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
        giveBack()
    }

    /// Tactile takes its touchscreen back, once.
    private func giveBack() {
        guard holdsTouchscreen else { return }
        holdsTouchscreen = false
        perform(.endSupportCheck)
    }

    // MARK: - The sheet

    /// Send to Tactile's Developer…: the report is made (with Tactile's log lines about the device and
    /// the Mac's facts), and, for the official build, the site is asked whether it takes reports.
    func showSheet() {
        isShowingSheet = true
        guard preparing == nil, let check, check.stage == .finished else { return }
        let device = check.device
        let environment = environment
        let mac = environment.mac()
        let readLog = environment.readLog
        let home = environment.home
        preparing = Task { @MainActor in
            let lines = await Task.detached(priority: .userInitiated) {
                SupportLog.lines(readLog(), usbID: device.usbID, location: device.location, serials: [device.serial], home: home)
            }.value
            let input = SupportReportInput(check: check, logLines: lines, mac: mac)
            switch await SupportArchiver.make(input, temporary: environment.temporary) {
            case .success(let archive): self.archive = archive
            case .failure(let failure): self.archiveFailure = failure
            }
            if case .on(let site) = environment.sending, sendStage == .checking {
                let available = await SupportUploader(site: site, transport: environment.transport).isAvailable()
                sendStage = available ? .ready : .unavailable
            }
        }
    }

    /// Send: asks the site again whether it takes reports, then uploads.
    func send() {
        guard case .on(let site) = environment.sending, let archive, let check, form.isReady, sendStage != .sending else { return }
        let input = SupportReportInput(check: check, logLines: [], mac: environment.mac())
        guard let request = SupportRequest(bundle: archive.data, input: input, email: form.email, note: form.note) else {
            sendStage = .unavailable
            return
        }
        sendStage = .sending
        let uploader = SupportUploader(site: site, transport: environment.transport)
        sendingTask = Task { @MainActor in
            switch await uploader.send(request) {
            case .sent: sendStage = .sent
            case .refused(_, let reason): sendStage = .refused(reason)
            case .tryLater: sendStage = .tryLater
            case .tooSlow: sendStage = .tooSlow
            case .unavailable: sendStage = .unavailable
            }
            InterfaceLog.log.info("touchscreen check: report sent; \(String(describing: self.sendStage), privacy: .public)")
        }
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
