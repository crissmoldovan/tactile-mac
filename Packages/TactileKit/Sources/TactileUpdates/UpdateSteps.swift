// The two things the updater does: ask the site for the newest release, and install one.

import Foundation

/// What a check found.
public enum CheckOutcome: Equatable, Sendable {
    /// A release newer than the running app, which this Mac can run.
    case newer(UpdateOffer)
    /// Nothing newer (or no release yet: the site answers 404).
    case upToDate
    /// A newer release that needs a newer macOS than this Mac's.
    case needsNewerSystem(UpdateOffer)
}

/// Asks the site for the newest release, and compares it with the running app.
public struct UpdateChecker: Sendable {
    public var site: UpdateSite
    public var network: UpdateNetwork
    public var running: RunningApp

    public init(site: UpdateSite, network: UpdateNetwork, running: RunningApp) {
        self.site = site
        self.network = network
        self.running = running
    }

    public func check() async -> Result<CheckOutcome, UpdateFailure> {
        let url = site.answerURL(version: running.version, build: running.build)
        let site = self.site
        let data: Data
        let result: HTTPResult
        do {
            (data, result) = try await network.fetch(url, allowingRedirect: { site.isOnSite($0) })
        } catch {
            return .failure(Self.isCancellation(error) ? .cancelled : .siteUnreachable)
        }
        if Task.isCancelled { return .failure(.cancelled) }
        guard let answeredFrom = result.url, site.isOnSite(answeredFrom), !(300..<400).contains(result.status) else {
            return .failure(.answerNotFromSite)
        }
        if result.status == 404 { return .success(.upToDate) }
        guard result.status == 200 else { return .failure(.siteFailed(status: result.status)) }
        let offer: UpdateOffer
        switch UpdateOffer.read(data) {
        case .success(let read): offer = read
        case .failure(let problem): return .failure(.answerUnreadable(problem))
        }
        guard offer.versionAndBuild > running.versionAndBuild else { return .success(.upToDate) }
        guard running.systemVersion >= offer.minimumSystemVersion else { return .success(.needsNewerSystem(offer)) }
        return .success(.newer(offer))
    }

    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}

/// How far an install has got, for the interface.
public enum InstallProgress: Equatable, Sendable {
    case downloading
    case verifying
}

/// Installs an offered release: checks that Tactile can replace itself, makes the first check,
/// downloads the archive into the update folder (emptied first), makes the other checks, writes the
/// helper script and starts it. Tactile then quits through its normal path, and the helper does the
/// rest. On any failure the update folder is emptied, and the reason returned.
public struct UpdateInstaller: Sendable {
    public var site: UpdateSite
    public var network: UpdateNetwork
    public var verifier: UpdateVerifier
    public var cache: UpdateCache
    public var location: InstallLocation
    public var helper: InstallHelperLaunching
    public var running: RunningApp
    /// Letters and digits that make the helper's hidden names unique.
    public var token: @Sendable () -> String

    public init(site: UpdateSite, network: UpdateNetwork, verifier: UpdateVerifier, cache: UpdateCache,
                location: InstallLocation, helper: InstallHelperLaunching, running: RunningApp,
                token: @escaping @Sendable () -> String) {
        self.site = site
        self.network = network
        self.verifier = verifier
        self.cache = cache
        self.location = location
        self.helper = helper
        self.running = running
        self.token = token
    }

    /// A fresh token: eight hexadecimal digits of a random UUID.
    public static func randomToken() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
    }

    /// Everything up to the helper running; the plan it was given, or why it stopped.
    public func run(_ offer: UpdateOffer, progress: @escaping @MainActor @Sendable (InstallProgress) -> Void) async
        -> Result<InstallPlan, UpdateFailure>
    {
        let result = await prepare(offer, progress: progress)
        if case .failure(let failure) = result {
            UpdatesLog.log.error("install of \(offer.version, privacy: .public) stopped: \(failure.logDescription, privacy: .public)")
            try? cache.clear()
        }
        return result
    }

    private func prepare(_ offer: UpdateOffer, progress: @escaping @MainActor @Sendable (InstallProgress) -> Void) async
        -> Result<InstallPlan, UpdateFailure>
    {
        if let refusal = location.refusal(for: running.bundleURL) { return .failure(refusal) }
        // 1. The archive's address is on the site.
        guard site.isOnSite(offer.archive.url) else { return .failure(.archiveNotOnSite) }
        do {
            try cache.clear()
        } catch {
            return .failure(.couldNotPrepare)
        }
        await progress(.downloading)
        let archive = cache.archive(for: offer.version)
        let site = self.site
        let result: HTTPResult
        do {
            result = try await network.download(offer.archive.url, to: archive, allowingRedirect: { site.allowsDownload(from: $0) })
        } catch {
            return .failure(UpdateChecker.isCancellation(error) ? .cancelled : .downloadFailed)
        }
        if Task.isCancelled { return .failure(.cancelled) }
        guard let downloadedFrom = result.url, site.allowsDownload(from: downloadedFrom),
              !(300..<400).contains(result.status)
        else { return .failure(.downloadNotFromSite) }
        guard result.status == 200 else { return .failure(.downloadFailed) }
        UpdatesLog.log.info("downloaded \(UpdateSite.loggable(offer.archive.url), privacy: .public) from \(UpdateSite.loggable(downloadedFrom), privacy: .public)")
        // 2 to 5.
        await progress(.verifying)
        let verified: VerifiedUpdate
        switch await verifier.verify(archive, offer: offer, running: running.versionAndBuild, unpackingInto: cache.unpacked) {
        case .success(let update): verified = update
        case .failure(let failure): return .failure(failure)
        }
        if Task.isCancelled { return .failure(.cancelled) }
        UpdatesLog.log.info("Tactile \(offer.version, privacy: .public) (\(offer.build, privacy: .public)) passed every check")
        // The helper.
        guard let plan = InstallPlan(
            processID: running.processID, app: running.bundleURL, newApp: verified.app,
            executable: verified.info.executable ?? "Tactile", log: cache.log,
            leftovers: [archive, cache.unpacked], token: token(),
            fromVersion: running.version, toVersion: offer.version.description)
        else { return .failure(.couldNotPrepare) }
        do {
            try Data(InstallScript.text(for: plan).utf8).write(to: cache.script, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cache.script.path)
        } catch {
            return .failure(.couldNotPrepare)
        }
        do {
            try helper.launch(cache.script)
        } catch {
            return .failure(.helperDidNotStart)
        }
        UpdatesLog.log.info("the helper runs \(cache.script.path, privacy: .public); it replaces \(plan.app.path, privacy: .public) once Tactile has quit")
        return .success(plan)
    }
}
