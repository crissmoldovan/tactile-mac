import Foundation
import XCTest

@testable import TactileUpdates

/// The updater as the interface sees it: a manual check says what it found; an automatic one says
/// nothing unless it finds a newer version; an install shows its progress, and quits through the
/// path it is given once the helper runs; a failure leaves a reason, and nothing else.
@MainActor
final class ControllerTests: XCTestCase {

    private var root: URL!
    private var network: FakeNetwork!
    private var helper: FakeHelper!
    private var preferences: MemoryPreferences!
    private var clock: FakeClock!
    private var quits = 0

    override func setUpWithError() throws {
        root = try makeTemporaryFolder()
        network = FakeNetwork()
        helper = FakeHelper()
        preferences = MemoryPreferences()
        clock = FakeClock()
        quits = 0
    }

    private func controller(code: FakeCodeSignature = FakeCodeSignature()) throws -> UpdateController {
        let app = try makeBundle(at: root.appendingPathComponent("Applications/Tactile.app"), version: "0.5.0", build: "300")
        let environment = UpdateEnvironment(
            site: Fixture.site, network: network,
            verifier: UpdateVerifier(trust: Fixture.trust, unpacker: FakeUnpacker.app(), codeSignature: code),
            cache: UpdateCache(folder: root.appendingPathComponent("Updates")), location: .allowed, helper: helper,
            preferences: preferences, clock: clock, running: Fixture.running(at: app), token: { "abc123" },
            quit: { [weak self] in self?.quits += 1 })
        return UpdateController(environment: environment)
    }

    func testItStartsFromThePreferences() throws {
        preferences = MemoryPreferences(checksAutomatically: false, lastChecked: Date(timeIntervalSince1970: 5))
        let updates = try controller()
        XCTAssertEqual(updates.state, UpdateState(
            phase: .idle, lastChecked: Date(timeIntervalSince1970: 5), checksAutomatically: false,
            runningVersion: "0.5.0", siteHost: "tactilemac.com"))
    }

    func testAManualCheckThatFindsANewerVersionOffersIt() async throws {
        let updates = try controller()
        let task = updates.checkForUpdates()
        XCTAssertEqual(updates.state.phase, .checking(manual: true), "checking at once")
        await task?.value
        XCTAssertEqual(updates.state.phase, .idle)
        XCTAssertEqual(updates.state.available, Fixture.offer())
        XCTAssertNil(updates.state.notice)
        XCTAssertEqual(updates.state.lastChecked, clock.now())
        XCTAssertEqual(preferences.lastChecked, clock.now(), "kept for the next launch")
    }

    func testAManualCheckThatFindsNothingNewerSaysSo() async throws {
        network.fetchResponse = .success(.init(status: 200, body: Fixture.answer(Fixture.offer(version: "0.5.0", build: 300))))
        let updates = try controller()
        await updates.checkForUpdates()?.value
        XCTAssertEqual(updates.state.notice, .upToDate)
        XCTAssertNil(updates.state.available)
        updates.dismissNotice()
        XCTAssertNil(updates.state.notice)
    }

    func testAManualCheckThatFailsSaysWhy() async throws {
        network.fetchResponse = .failure(URLError(.notConnectedToInternet))
        let updates = try controller()
        await updates.checkForUpdates()?.value
        XCTAssertEqual(updates.state.notice, .checkFailed(.siteUnreachable))
        XCTAssertNil(updates.state.lastChecked, "no answer: not a check")
    }

    func testAManualCheckForAReleaseThisMacCantRunSaysSo() async throws {
        let offer = Fixture.offer(minimumSystem: "27.0")
        network.fetchResponse = .success(.init(status: 200, body: Fixture.answer(offer)))
        let updates = try controller()
        await updates.checkForUpdates()?.value
        XCTAssertEqual(updates.state.notice, .needsNewerSystem(offer))
        XCTAssertNil(updates.state.available)
    }

    func testACancelledCheckSaysNothing() async throws {
        network.fetchResponse = .failure(URLError(.cancelled))
        let updates = try controller()
        await updates.checkForUpdates()?.value
        XCTAssertNil(updates.state.notice)
        XCTAssertEqual(updates.state.phase, .idle)
    }

    func testANewCheckClearsTheLastNotice() async throws {
        network.fetchResponse = .failure(URLError(.timedOut))
        let updates = try controller()
        await updates.checkForUpdates()?.value
        XCTAssertNotNil(updates.state.notice)
        network.fetchResponse = .success(.init(status: 200, body: Fixture.answer()))
        let task = updates.checkForUpdates()
        XCTAssertNil(updates.state.notice, "cleared as the new check starts")
        await task?.value
        XCTAssertNil(updates.state.notice)
        XCTAssertNotNil(updates.state.available)
    }

    func testANewerVersionThatIsGoneIsNoLongerOffered() async throws {
        let updates = try controller()
        await updates.checkForUpdates()?.value
        XCTAssertNotNil(updates.state.available)
        network.fetchResponse = .success(.init(status: 404, body: Data()))
        await updates.checkForUpdates()?.value
        XCTAssertNil(updates.state.available)
        XCTAssertEqual(updates.state.notice, .upToDate)
    }

    func testInstallingShowsItsProgressThenQuits() async throws {
        let updates = try controller()
        await updates.checkForUpdates()?.value
        let task = updates.install()
        XCTAssertEqual(updates.state.phase, .downloading(Fixture.offer()), "downloading at once")
        await task?.value
        XCTAssertEqual(updates.state.phase, .installing(Fixture.offer()))
        XCTAssertEqual(helper.launched.count, 1, "the helper runs before Tactile quits")
        XCTAssertEqual(quits, 1, "Tactile quits through the path it was given")
        XCTAssertNil(updates.checkForUpdates(), "nothing more while installing")
        XCTAssertNil(updates.install())
    }

    func testAnInstallThatFailsSaysWhyAndDoesntQuit() async throws {
        let updates = try controller(code: FakeCodeSignature(valid: false))
        await updates.checkForUpdates()?.value
        await updates.install()?.value
        XCTAssertEqual(updates.state.phase, .idle)
        XCTAssertEqual(updates.state.notice, .installFailed(.codeSignatureInvalid))
        XCTAssertEqual(updates.state.available, Fixture.offer(), "still offered: it can be tried again")
        XCTAssertEqual(helper.launched, [])
        XCTAssertEqual(quits, 0)
    }

    func testNothingIsInstalledWithoutANewerVersion() throws {
        let updates = try controller()
        XCTAssertNil(updates.install())
        XCTAssertEqual(updates.state.phase, .idle)
        XCTAssertEqual(network.downloaded, [])
    }

    func testTheSettingIsKept() throws {
        let updates = try controller()
        updates.setChecksAutomatically(false)
        XCTAssertFalse(updates.state.checksAutomatically)
        XCTAssertFalse(preferences.checksAutomatically)
        updates.setChecksAutomatically(true)
        XCTAssertTrue(preferences.checksAutomatically)
        updates.stop()
    }
}

/// The schedule: one check a minute after launch, then every 24 hours, only while the setting is on;
/// a failed one again after an hour; a manual check counts.
@MainActor
final class ScheduleTests: XCTestCase {

    func testTheFirstCheckIsAMinuteAfterLaunchThenEveryDay() {
        let launch = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(UpdateSchedule.nextCheck(automatic: true, launchedAt: launch, lastAttempt: nil, lastAttemptFailed: false),
                       launch.addingTimeInterval(60))
        let last = launch.addingTimeInterval(500)
        XCTAssertEqual(UpdateSchedule.nextCheck(automatic: true, launchedAt: launch, lastAttempt: last, lastAttemptFailed: false),
                       last.addingTimeInterval(24 * 3600))
        XCTAssertEqual(UpdateSchedule.nextCheck(automatic: true, launchedAt: launch, lastAttempt: last, lastAttemptFailed: true),
                       last.addingTimeInterval(3600))
    }

    func testNoAutomaticCheckWhileTheSettingIsOff() {
        XCTAssertNil(UpdateSchedule.nextCheck(automatic: false, launchedAt: Date(), lastAttempt: nil, lastAttemptFailed: false))
        XCTAssertNil(UpdateSchedule.nextCheck(automatic: false, launchedAt: Date(), lastAttempt: Date(), lastAttemptFailed: true))
    }

    func testTheScheduleNapsUntilTheCheckIsDueAtMostAQuarterOfAnHour() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertEqual(UpdateSchedule.nap(until: now.addingTimeInterval(60), now: now), 60)
        XCTAssertEqual(UpdateSchedule.nap(until: now.addingTimeInterval(86_400), now: now), 15 * 60)
        XCTAssertEqual(UpdateSchedule.nap(until: now.addingTimeInterval(-5), now: now), 0)
        XCTAssertEqual(UpdateSchedule.nap(until: nil, now: now), 15 * 60)
    }

    // MARK: - The schedule running, on a hand-turned clock

    private func runSchedule(days: Double, automatic: Bool = true, answer: Result<FakeNetwork.Response, Error>? = nil,
                             before: (UpdateController, FakeClock) async -> Void = { _, _ in }) async throws
        -> (checks: [TimeInterval], updates: UpdateController)
    {
        let root = try makeTemporaryFolder()
        let clock = FakeClock(runFor: days * 24 * 3600)
        let start = clock.now()
        let network = answer.map { FakeNetwork(answer: $0) } ?? FakeNetwork()
        let times = CheckTimes()
        network.onRequest = { _ in times.add(clock.now().timeIntervalSince(start)) }
        let environment = UpdateEnvironment(
            site: Fixture.site, network: network,
            verifier: UpdateVerifier(trust: Fixture.trust, unpacker: FakeUnpacker.app(), codeSignature: FakeCodeSignature()),
            cache: UpdateCache(folder: root.appendingPathComponent("Updates")), location: .allowed, helper: FakeHelper(),
            preferences: MemoryPreferences(checksAutomatically: automatic), clock: clock,
            running: Fixture.running(), quit: {})
        let updates = UpdateController(environment: environment)
        await before(updates, clock)
        await updates.runSchedule()
        return (times.all, updates)
    }

    func testChecksAMinuteAfterLaunchThenEveryDay() async throws {
        let (checks, updates) = try await runSchedule(days: 3)
        let day: TimeInterval = 86_400
        XCTAssertEqual(checks, [60, 60 + day, 60 + 2 * day])
        XCTAssertNotNil(updates.state.available, "an automatic check that finds a newer version offers it")
        XCTAssertNil(updates.state.notice)
    }

    func testAnAutomaticCheckThatFindsNothingOrFailsSaysNothing() async throws {
        let (_, upToDate) = try await runSchedule(days: 0.5, answer: .success(.init(status: 404, body: Data())))
        XCTAssertNil(upToDate.state.notice)
        let (checks, failing) = try await runSchedule(days: 0.2, answer: .failure(URLError(.notConnectedToInternet)))
        XCTAssertNil(failing.state.notice, "a failed automatic check says nothing")
        let hour: TimeInterval = 3600
        XCTAssertEqual(checks, [60, 60 + hour, 60 + 2 * hour, 60 + 3 * hour, 60 + 4 * hour],
                       "and is tried again every hour (the clock runs for 4.8 hours)")
    }

    func testNoCheckWhileTheSettingIsOff() async throws {
        let (checks, _) = try await runSchedule(days: 3, automatic: false)
        XCTAssertEqual(checks, [])
    }

    func testAManualCheckPutsOffTheNextAutomaticOne() async throws {
        let (checks, _) = try await runSchedule(days: 1.5) { updates, clock in
            clock.advance(30)
            await updates.checkForUpdates()?.value
        }
        let day: TimeInterval = 86_400
        XCTAssertEqual(checks, [30, 30 + day], "the manual check at 30 seconds counts as the day's")
    }
}

/// Times gathered from the network's callback.
final class CheckTimes: @unchecked Sendable {
    private let lock = NSLock()
    private var times: [TimeInterval] = []

    func add(_ time: TimeInterval) { lock.withLock { times.append(time) } }
    var all: [TimeInterval] { lock.withLock { times } }
}
