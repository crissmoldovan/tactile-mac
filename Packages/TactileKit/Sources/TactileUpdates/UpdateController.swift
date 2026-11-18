// The updater as the interface sees it: its state, and what the person can ask of it.

import Foundation
import Observation

/// What the updater is doing.
public enum UpdatePhase: Equatable, Sendable {
    case idle
    /// Asking the site. A manual check (Check for Updates…) says what it found; an automatic one says
    /// nothing unless it finds a newer version.
    case checking(manual: Bool)
    case downloading(UpdateOffer)
    case verifying(UpdateOffer)
    /// The helper runs and Tactile is quitting.
    case installing(UpdateOffer)

    public var isIdle: Bool { self == .idle }
}

/// What the last manual check or install left to say, until the person dismisses it or does
/// something else.
public enum UpdateNotice: Equatable, Sendable {
    /// A manual check found nothing newer.
    case upToDate
    /// A manual check found a newer version this Mac's macOS can't run.
    case needsNewerSystem(UpdateOffer)
    /// A manual check failed.
    case checkFailed(UpdateFailure)
    /// An install stopped, nothing changed.
    case installFailed(UpdateFailure)
}

/// Everything the interface shows about updates.
public struct UpdateState: Equatable, Sendable {
    public var phase: UpdatePhase
    /// The newer version the last check found, until a check finds otherwise.
    public var available: UpdateOffer?
    public var notice: UpdateNotice?
    /// When a check last got an answer from the site.
    public var lastChecked: Date?
    public var checksAutomatically: Bool
    /// The running app's version, as its bundle says it.
    public var runningVersion: String
    /// The site's host, for the person's words: "tactilemac.com".
    public var siteHost: String

    public init(phase: UpdatePhase = .idle, available: UpdateOffer? = nil, notice: UpdateNotice? = nil,
                lastChecked: Date? = nil, checksAutomatically: Bool = true, runningVersion: String,
                siteHost: String = UpdateSite.builtIn.host) {
        self.phase = phase
        self.available = available
        self.notice = notice
        self.lastChecked = lastChecked
        self.checksAutomatically = checksAutomatically
        self.runningVersion = runningVersion
        self.siteHost = siteHost
    }
}

/// Every live piece the updater uses, given in one place: the app makes them with `live(quit:)`,
/// tests with fakes.
public struct UpdateEnvironment {
    public var site: UpdateSite
    public var network: UpdateNetwork
    public var verifier: UpdateVerifier
    public var cache: UpdateCache
    public var location: InstallLocation
    public var helper: InstallHelperLaunching
    public var preferences: UpdatePreferences
    public var clock: UpdateClock
    public var running: RunningApp
    public var token: @Sendable () -> String
    /// Quits Tactile through its normal path, once the helper runs.
    public var quit: @MainActor () -> Void

    public init(site: UpdateSite, network: UpdateNetwork, verifier: UpdateVerifier, cache: UpdateCache,
                location: InstallLocation, helper: InstallHelperLaunching, preferences: UpdatePreferences,
                clock: UpdateClock, running: RunningApp,
                token: @escaping @Sendable () -> String = { UpdateInstaller.randomToken() },
                quit: @escaping @MainActor () -> Void) {
        self.site = site
        self.network = network
        self.verifier = verifier
        self.cache = cache
        self.location = location
        self.helper = helper
        self.preferences = preferences
        self.clock = clock
        self.running = running
        self.token = token
        self.quit = quit
    }

    /// The official build's: the site and keys its Info.plist names (`settings`; the user
    /// default's site instead, when it names one), URLSession, `ditto`, the Security framework, the
    /// update folder in Caches, the user defaults, the system clock and this process. Only for a
    /// build `UpdateAvailability` says is on: nothing else may ask a site.
    public static func live(settings: UpdateSettings,
                            preferences: UpdatePreferences = UserDefaultsUpdatePreferences(),
                            quit: @escaping @MainActor () -> Void) -> UpdateEnvironment {
        UpdateEnvironment(
            site: UpdateSite.resolve(override: preferences.baseURLOverride, fallback: settings.site),
            network: URLSessionUpdateNetwork(),
            verifier: UpdateVerifier(trust: UpdateTrust(base64Keys: settings.keys), unpacker: DittoUnpacker(),
                                     codeSignature: SecurityCodeSignatureCheck()),
            cache: .live, location: .live, helper: DetachedShellLauncher(), preferences: preferences,
            clock: SystemUpdateClock(), running: .current, quit: quit)
    }
}

/// The updater: checks on its schedule and when asked, and installs when asked. The interface reads
/// `state` and calls the methods; nothing else.
@MainActor
@Observable
public final class UpdateController {
    public private(set) var state: UpdateState

    @ObservationIgnored private let checker: UpdateChecker
    @ObservationIgnored private let installer: UpdateInstaller
    @ObservationIgnored private let preferences: UpdatePreferences
    @ObservationIgnored private let clock: UpdateClock
    @ObservationIgnored private let quit: @MainActor () -> Void
    @ObservationIgnored private let launchedAt: Date
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var lastAttemptFailed = false
    /// The check or install under way.
    @ObservationIgnored private(set) var work: Task<Void, Never>?
    @ObservationIgnored private var schedule: Task<Void, Never>?

    public init(environment: UpdateEnvironment) {
        checker = UpdateChecker(site: environment.site, network: environment.network, running: environment.running)
        installer = UpdateInstaller(
            site: environment.site, network: environment.network, verifier: environment.verifier,
            cache: environment.cache, location: environment.location, helper: environment.helper,
            running: environment.running, token: environment.token)
        preferences = environment.preferences
        clock = environment.clock
        quit = environment.quit
        launchedAt = environment.clock.now()
        state = UpdateState(
            lastChecked: environment.preferences.lastChecked,
            checksAutomatically: environment.preferences.checksAutomatically,
            runningVersion: environment.running.version, siteHost: environment.site.host)
    }

    // MARK: - What the person can ask

    /// Starts the automatic checks: the first a minute from now, if they are on.
    public func start() {
        UpdatesLog.log.info("updater started: Tactile \(self.state.runningVersion, privacy: .public), asking \(self.state.siteHost, privacy: .public), automatic checks \(self.state.checksAutomatically ? "on" : "off", privacy: .public)")
        restartSchedule()
    }

    public func stop() {
        schedule?.cancel()
        schedule = nil
        work?.cancel()
    }

    /// Check for Updates…: asks the site now, and says what it found. During an automatic check, that
    /// check becomes this one. Does nothing while an update downloads or installs.
    @discardableResult
    public func checkForUpdates() -> Task<Void, Never>? {
        switch state.phase {
        case .idle:
            state.notice = nil
            return beginCheck(manual: true)
        case .checking:
            state.notice = nil
            state.phase = .checking(manual: true)
            return work
        case .downloading, .verifying, .installing:
            return nil
        }
    }

    /// Install and Relaunch: downloads, checks and installs the newer version found, then quits for
    /// the helper to replace the app and open the new one.
    @discardableResult
    public func install() -> Task<Void, Never>? {
        guard state.phase.isIdle, let offer = state.available else { return nil }
        state.notice = nil
        state.phase = .downloading(offer)
        UpdatesLog.log.info("installing Tactile \(offer.version, privacy: .public) (\(offer.build, privacy: .public))")
        let task = Task { await self.performInstall(offer) }
        work = task
        return task
    }

    /// Stops a check or a download under way. An install whose helper runs can't be stopped.
    public func cancel() {
        switch state.phase {
        case .checking, .downloading, .verifying: work?.cancel()
        case .idle, .installing: break
        }
    }

    /// The person has read the notice.
    public func dismissNotice() {
        state.notice = nil
    }

    /// Check for updates automatically, on or off; kept for the next launch.
    public func setChecksAutomatically(_ on: Bool) {
        guard on != state.checksAutomatically else { return }
        preferences.checksAutomatically = on
        state.checksAutomatically = on
        UpdatesLog.log.info("automatic checks \(on ? "on" : "off", privacy: .public)")
        restartSchedule()
    }

    // MARK: - Checking

    private func beginCheck(manual: Bool) -> Task<Void, Never> {
        state.phase = .checking(manual: manual)
        let task = Task { await self.performCheck() }
        work = task
        return task
    }

    private func performCheck() async {
        lastAttempt = clock.now()
        let result = await checker.check()
        let isManual = state.phase == .checking(manual: true)
        state.phase = .idle
        let kind = isManual ? "manual" : "automatic"
        switch result {
        case .success(let outcome):
            lastAttemptFailed = false
            let now = clock.now()
            preferences.lastChecked = now
            state.lastChecked = now
            switch outcome {
            case .newer(let offer):
                state.available = offer
                UpdatesLog.log.info("\(kind, privacy: .public) check: Tactile \(offer.version, privacy: .public) (\(offer.build, privacy: .public)) is available")
            case .upToDate:
                state.available = nil
                if isManual { state.notice = .upToDate }
                UpdatesLog.log.info("\(kind, privacy: .public) check: \(self.state.runningVersion, privacy: .public) is the newest")
            case .needsNewerSystem(let offer):
                state.available = nil
                if isManual { state.notice = .needsNewerSystem(offer) }
                UpdatesLog.log.info("\(kind, privacy: .public) check: Tactile \(offer.version, privacy: .public) needs macOS \(offer.minimumSystemVersion.description, privacy: .public)")
            }
        case .failure(let failure):
            lastAttemptFailed = failure != .cancelled
            if isManual, failure != .cancelled {
                state.notice = .checkFailed(failure)
            }
            UpdatesLog.log.error("\(kind, privacy: .public) check failed: \(failure.logDescription, privacy: .public)")
        }
    }

    // MARK: - Installing

    private func performInstall(_ offer: UpdateOffer) async {
        let result = await installer.run(offer, progress: { [weak self] progress in
            guard let self, !self.state.phase.isIdle else { return }
            switch progress {
            case .downloading: self.state.phase = .downloading(offer)
            case .verifying: self.state.phase = .verifying(offer)
            }
        })
        switch result {
        case .success:
            state.phase = .installing(offer)
            UpdatesLog.log.info("quitting for the helper to install Tactile \(offer.version, privacy: .public)")
            quit()
        case .failure(let failure):
            state.phase = .idle
            if failure != .cancelled {
                state.notice = .installFailed(failure)
            }
        }
    }

    // MARK: - The schedule

    private func restartSchedule() {
        schedule?.cancel()
        schedule = Task { await self.runSchedule() }
    }

    /// Checks when `UpdateSchedule` says one is due, looking at the clock at least every
    /// `UpdateSchedule.longestNap`; ends when cancelled.
    func runSchedule() async {
        while !Task.isCancelled {
            let now = clock.now()
            let due = UpdateSchedule.nextCheck(
                automatic: state.checksAutomatically, launchedAt: launchedAt, lastAttempt: lastAttempt,
                lastAttemptFailed: lastAttemptFailed)
            var nap = UpdateSchedule.nap(until: due, now: now)
            if let due, now >= due {
                if state.phase.isIdle {
                    await beginCheck(manual: false).value
                    continue
                }
                // Busy downloading or installing: look again in a minute.
                nap = UpdateSchedule.afterLaunch
            }
            do {
                try await clock.sleep(seconds: nap)
            } catch {
                return
            }
        }
    }
}
