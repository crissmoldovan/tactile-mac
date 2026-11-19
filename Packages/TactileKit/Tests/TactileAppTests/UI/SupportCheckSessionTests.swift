import AppKit
import Foundation
import IOKit
import SwiftUI
@testable import TactileApp
@testable import TactileDevices
import TactileScreens
import TactileSupport
import TactileTestSupport
import TactileUpdates
import XCTest

/// The check's session, as its window runs it, with a stand-in HID system holding the surveyed
/// ILITEK's interfaces, a fake model, a fake transport and a log book of its own: Start Check waits
/// while Tactile can't let go; the model is told to let go and to take back, only once the device is
/// free; an interrupted check has no report; the site is asked only at Send; and sending can be
/// stopped. No device, no window, no network, and the temporary folder is removed.
@MainActor
final class SupportCheckSessionTests: XCTestCase {

    /// A HID system with the ILITEK behind it, answering every call with success. Its reads can be
    /// held, as a panel slow to answer would hold them.
    private final class StandInHIDSystem: HIDSystem {
        var connected: [HIDInterfaceDescription]
        private(set) var calls: [String] = []
        private var handlers: [HIDInterfaceID: @MainActor ([UInt8], TimeInterval) -> Void] = [:]
        var holdsReads = false
        private var heldReads: [CheckedContinuation<Void, Never>] = []

        init(_ connected: [HIDInterfaceDescription]) {
            self.connected = connected
        }

        func startMatching(matched: @escaping @MainActor (HIDInterfaceDescription) -> Void,
                           removed: @escaping @MainActor (HIDInterfaceID) -> Void) {
            for description in connected { matched(description) }
        }

        func stopMatching() { calls.append("stopMatching") }
        func later(_ work: @escaping @MainActor () -> Void) { work() }

        /// How many holders each interface has: it opens for one at a time, as a seized device does.
        private var holders: [HIDInterfaceID: Int] = [:]

        func open(_ id: HIDInterfaceID, exclusive: Bool) -> IOReturn {
            guard holders[id, default: 0] == 0 else {
                calls.append("refused \(id)")
                return IOReturn(bitPattern: 0xE000_02C5)  // kIOReturnExclusiveAccess
            }
            holders[id, default: 0] += 1
            calls.append("open \(id)")
            return kIOReturnSuccess
        }

        func close(_ id: HIDInterfaceID, exclusive: Bool) -> IOReturn {
            holders[id] = max(0, holders[id, default: 0] - 1)
            calls.append("close \(id)")
            return kIOReturnSuccess
        }

        var isHeld: Bool { holders.values.contains { $0 > 0 } }

        func hasInputMode(_ id: HIDInterfaceID) -> Bool { false }

        func readFeatureReport(_ id: HIDInterfaceID, reportID: Int, length: Int) -> FeatureReportRead {
            calls.append("read \(reportID)")
            return FeatureReportRead(result: kIOReturnSuccess, length: length, seconds: 0.01,
                                     bytes: [UInt8(reportID), 10] + [UInt8](repeating: 0, count: max(0, length - 2)))
        }

        func readFeatureReportInBackground(_ id: HIDInterfaceID, reportID: Int, length: Int) async -> FeatureReportRead {
            if holdsReads { await withCheckedContinuation { heldReads.append($0) } }
            return readFeatureReport(id, reportID: reportID, length: length)
        }

        var readsHeld: Int { heldReads.count }

        func letReadsGo() {
            let held = heldReads
            heldReads = []
            for read in held { read.resume() }
        }

        func writeInputMode(_ id: HIDInterfaceID, _ value: Int) -> IOReturn {
            calls.append("write \(value)")
            return kIOReturnSuccess
        }

        func startReports(_ id: HIDInterfaceID, bufferSize: Int, _ handler: @escaping @MainActor ([UInt8], TimeInterval) -> Void) {
            handlers[id] = handler
        }

        func stopReports(_ id: HIDInterfaceID) { handlers[id] = nil }

        func send(_ bytes: [UInt8], on id: HIDInterfaceID, at time: TimeInterval) { handlers[id]?(bytes, time) }
    }

    /// The model as the check sees it: the preview desk's snapshot. As the real one, it lets go of
    /// a touchscreen while any check's claim on it is held (unless told not to let go), and takes it
    /// back when the last claim goes.
    @MainActor
    private final class FakeModel {
        var snapshot = PreviewModel(.desk).snapshot
        var letsGo = true
        private(set) var commands: [AppCommand] = []
        private(set) var claims: [UUID: TouchscreenID] = [:]
        /// Whether the device was free (no check holding it open) each time the model took it back.
        private(set) var deviceWasFreeAtEnd: [Bool] = []
        var isDeviceFree: () -> Bool = { true }

        func perform(_ command: AppCommand) {
            commands.append(command)
            switch command {
            case .beginSupportCheck(let id, let claim) where letsGo:
                claims[claim] = id
                set(id, mode: .released)
            case .endSupportCheck(let claim):
                guard let id = claims.removeValue(forKey: claim), !claims.values.contains(id) else { return }
                deviceWasFreeAtEnd.append(isDeviceFree())
                set(id, mode: .driving)
            default:
                break
            }
        }

        /// The commands, with each claim named by the order it first appeared: "begin 1", "end 1".
        var named: [String] {
            var order: [UUID] = []
            func number(_ claim: UUID) -> Int {
                if let index = order.firstIndex(of: claim) { return index + 1 }
                order.append(claim)
                return order.count
            }
            return commands.compactMap { command in
                switch command {
                case .beginSupportCheck(_, let claim): return "begin \(number(claim))"
                case .endSupportCheck(let claim): return "end \(number(claim))"
                default: return nil
                }
            }
        }

        private func set(_ id: TouchscreenID, mode: TouchscreenMode) {
            guard let index = snapshot.touchscreens.firstIndex(where: { $0.id == id }) else { return }
            snapshot.touchscreens[index].mode = mode
        }
    }

    /// Answers the status and the upload as told, and can hold either until it is cancelled.
    private final class FakeTransport: SupportTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var _methods: [String] = []
        private var _cancelled: [String] = []
        var available = true
        var uploadStatus = 202
        var holdsStatus = false
        var holdsUpload = false

        var methods: [String] { lock.withLock { _methods } }
        var cancelled: [String] { lock.withLock { _cancelled } }

        func perform(_ request: URLRequest) async throws -> (Data, HTTPResult) {
            let method = request.httpMethod ?? "GET"
            lock.withLock { _methods.append(method) }
            let isStatus = request.url?.path == SupportUploader.statusPath
            if isStatus ? holdsStatus : holdsUpload {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    lock.withLock { _cancelled.append(method) }
                    throw error
                }
            }
            if isStatus {
                return (Data(#"{"available":\#(available)}"#.utf8), HTTPResult(status: 200, url: request.url))
            }
            return (Data(#"{"status":"check-email"}"#.utf8), HTTPResult(status: uploadStatus, url: request.url))
        }
    }

    private static let touchID: HIDInterfaceID = 21, mouseID: HIDInterfaceID = 22

    private var clock: TimeInterval = 1000

    private func ilitek() throws -> [HIDInterfaceDescription] {
        let panel = try XCTUnwrap(SurveyFixtures.surveyB.touchscreen(vendorID: 0x222a, productID: 0x0001))
        func descriptor(_ key: String) throws -> [UInt8] { try XCTUnwrap(panel.interfaces.first { $0.key == key }).descriptor }
        return [
            HIDInterfaceDescription(id: Self.touchID, locationID: 0x0114_1000, vendorID: 0x222a, productID: 0x0001,
                                    serial: "V06.00.00.00", product: "ILITEK-TP", usages: [.touchScreen],
                                    descriptor: try descriptor("touchscreen"), maxInputReportSize: 64, manufacturer: "ILITEK"),
            HIDInterfaceDescription(id: Self.mouseID, locationID: 0x0114_1000, vendorID: 0x222a, productID: 0x0001,
                                    serial: "V06.00.00.00", product: "ILITEK-TP", usages: [.mouse, .pointer],
                                    descriptor: try descriptor("mouse"), maxInputReportSize: 64, manufacturer: "ILITEK"),
        ]
    }

    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("SupportCheckSessionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    private struct Desk {
        let system: StandInHIDSystem
        let model: FakeModel
        let transport: FakeTransport
        let book: DeviceLogBook
        let session: SupportCheckSession
        let temporary: URL
    }

    private func desk(sending: SupportSending, target: Bool = true, model given: FakeModel? = nil,
                      transport: FakeTransport = FakeTransport(), system givenSystem: StandInHIDSystem? = nil,
                      finishing givenFinishing: SupportChecksFinishing? = nil) throws -> Desk {
        let model = given ?? FakeModel()
        let system = try givenSystem ?? StandInHIDSystem(try ilitek())
        let finishing = givenFinishing ?? SupportChecksFinishing()
        let temporary = try folder()
        let book = DeviceLogBook()
        let environment = SupportSessionEnvironment(
            probe: SupportProbe(system: system, logBook: book), sending: sending, transport: transport, logBook: book,
            mac: { SupportMac(model: "Mac15,6", macOS: "26.1", tactileVersion: "0.7.0", tactileBuild: "512", displays: 2) },
            now: { [unowned self] in self.clock }, ticks: false, temporary: temporary, home: "/Users/someone",
            finishing: finishing)
        model.isDeviceFree = { [unowned system] in !system.isHeld }
        let ilitek = try XCTUnwrap(model.snapshot.touchscreens.first { $0.id == UIFixtures.ilitek })
        let session = SupportCheckSession(
            deviceID: target ? nil : "222a:0001@01141000", touchscreen: target ? SupportTarget(ilitek) : nil, name: ilitek.name,
            perform: { model.perform($0) }, snapshot: { target ? model.snapshot : nil }, environment: environment)
        return Desk(system: system, model: model, transport: transport, book: book, session: session, temporary: temporary)
    }

    /// Starts the check and waits for its take.
    private func start(_ session: SupportCheckSession) async {
        session.start()
        await session.starting?.value
    }

    /// Runs the check through: the ILITEK's ten-finger take, then every step skipped.
    private func runThrough(_ desk: Desk) async throws {
        await start(desk.session)
        let take = try XCTUnwrap(SurveyFixtures.surveyB.touchscreen(vendorID: 0x222a, productID: 0x0001)?.takes.first { $0.number == 3 })
        let first = take.reports.first?.hostTime ?? 0
        for report in take.reports { desk.system.send(report.bytes, on: Self.touchID, at: clock + 0.1 + report.hostTime - first) }
        clock += 3
        for _ in 0..<3 { desk.session.skip() }
    }

    private func settle(_ session: SupportCheckSession) async {
        await session.preparing?.value
        await session.sendingTask?.value
    }

    /// Waits, a turn at a time, until `condition` holds, for at most a second (more in CI).
    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(TestTiming.limit(1))
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
    }

    // MARK: - Letting go and taking back

    func testTheModelLetsGoForTheCheckAndTakesItBackOnceTheDeviceIsFree() async throws {
        let desk = try desk(sending: .off)
        let check = try XCTUnwrap(desk.session.check)
        XCTAssertEqual(desk.model.commands, [], "nothing until Start Check")
        XCTAssertFalse(desk.system.calls.contains { $0.hasPrefix("open") }, "nothing opened before Start Check")

        await start(desk.session)
        XCTAssertEqual(desk.model.named, ["begin 1"])
        XCTAssertTrue(desk.system.calls.contains("open 21"))
        XCTAssertEqual(check.stage, .touching(.one))

        for _ in 0..<3 { desk.session.skip() }
        XCTAssertEqual(check.stage, .finished)
        XCTAssertEqual(desk.model.named, ["begin 1", "end 1"])
        XCTAssertEqual(desk.model.deviceWasFreeAtEnd, [true], "taken back only once the check had closed it")
        desk.session.stop()
        XCTAssertEqual(desk.model.named.filter { $0.hasPrefix("end") }.count, 1, "and only once")
    }

    func testStartCheckWaitsWhileTactileCantLetGo() async throws {
        let setUp = FakeModel()
        setUp.snapshot.setUpMode = SetUpModeSnapshot(stage: .choosing, displays: [], touchscreens: [], justSetUp: nil, notice: nil)
        let duringSetUp = try desk(sending: .off, model: setUp)
        XCTAssertEqual(duringSetUp.session.startAvailability, .setUpRunning)
        await start(duringSetUp.session)
        XCTAssertEqual(duringSetUp.session.startRefusal, "Not while a set-up runs.")
        XCTAssertEqual(setUp.commands, [], "the model isn't asked")
        XCTAssertFalse(duringSetUp.system.calls.contains { $0.hasPrefix("open") }, "nothing opened")
        XCTAssertEqual(duringSetUp.session.check?.stage, .ready)

        let shared = FakeModel()
        if let index = shared.snapshot.touchscreens.firstIndex(where: { $0.id == UIFixtures.ilitek }) {
            shared.snapshot.touchscreens[index].notes.append(.macOSMayAlsoRespond)
        }

        let refusing = FakeModel()
        refusing.letsGo = false
        let refused = try desk(sending: .off, model: refusing)
        await start(refused.session)
        XCTAssertEqual(refused.session.startRefusal, "Tactile couldn’t let go of the touchscreen just now. Try again in a moment.")
        XCTAssertEqual(refusing.named, ["begin 1", "end 1"])
        XCTAssertFalse(refused.system.calls.contains { $0.hasPrefix("open") }, "nothing it holds is touched")
        XCTAssertEqual(refused.session.check?.stage, .ready)
    }

    // MARK: - Overlapping checks (R-1)

    /// The review's sequence: check A is closed while a slow read holds the device, and the person
    /// opens the check again. Check B can't start until A has let go, and says why; once A's read
    /// returns, A lets go and hands back, the model takes the touchscreen again, and B can start.
    func testANewCheckWaitsUntilTheLastOneHasLetGo() async throws {
        let system = StandInHIDSystem(try ilitek())
        let model = FakeModel()
        let finishing = SupportChecksFinishing()
        let a = try desk(sending: .off, model: model, system: system, finishing: finishing)
        system.holdsReads = true
        a.session.start()
        await waitUntil { system.readsHeld == 1 }
        a.session.stop()
        XCTAssertTrue(finishing.isFinishing(UIFixtures.ilitek))

        let b = try desk(sending: .off, model: model, system: system, finishing: finishing)
        XCTAssertEqual(b.session.startAvailability, .lastCheckFinishing)
        XCTAssertEqual(Wording.supportUnavailable(.lastCheckFinishing), "The last check is still finishing. Try again in a moment.")
        b.session.start()
        XCTAssertEqual(b.session.startRefusal, "The last check is still finishing. Try again in a moment.")
        XCTAssertEqual(model.named, ["begin 1"], "B asks nothing of the model")
        XCTAssertFalse(system.calls.contains("refused 21"), "B never tries the device A holds")

        system.letReadsGo()
        await a.session.starting?.value
        XCTAssertEqual(model.named, ["begin 1", "end 1"])
        XCTAssertEqual(model.deviceWasFreeAtEnd, [true], "taken back once A had closed it")
        XCTAssertEqual(model.snapshot.touchscreens.first { $0.id == UIFixtures.ilitek }?.mode, .driving)
        XCTAssertFalse(finishing.isFinishing(UIFixtures.ilitek), "clears by itself")
        XCTAssertEqual(b.session.startAvailability, .available)

        system.holdsReads = false
        await start(b.session)
        for _ in 0..<3 { b.session.skip() }
        XCTAssertNil(b.session.check?.interruption, "B ran its course")
        XCTAssertEqual(model.named, ["begin 1", "end 1", "begin 2", "end 2"])
        XCTAssertEqual(model.deviceWasFreeAtEnd, [true, true])
        XCTAssertEqual(model.snapshot.touchscreens.first { $0.id == UIFixtures.ilitek }?.mode, .driving)
    }

    /// The same sequence with nothing to stop B starting (as before the guard): B can't open what A
    /// holds and hands back, but its hand-back clears only its own claim. When A's read returns and A
    /// hands back, the model takes the touchscreen again: it is never left undriven.
    func testAHandBackClearsOnlyItsOwnClaim() async throws {
        let system = StandInHIDSystem(try ilitek())
        let model = FakeModel()
        let a = try desk(sending: .off, model: model, system: system)
        system.holdsReads = true
        a.session.start()
        await waitUntil { system.readsHeld == 1 }
        a.session.stop()

        let b = try desk(sending: .off, model: model, system: system)  // a registry of its own: nothing stops it
        await start(b.session)
        XCTAssertEqual(b.session.check?.interruption, .couldNotOpen, "A still holds the device")
        XCTAssertEqual(model.named, ["begin 1", "begin 2", "end 2"])
        XCTAssertEqual(model.snapshot.touchscreens.first { $0.id == UIFixtures.ilitek }?.mode, .released, "A still holds it")

        system.letReadsGo()
        await a.session.starting?.value
        XCTAssertEqual(model.named, ["begin 1", "begin 2", "end 2", "end 1"])
        XCTAssertEqual(model.deviceWasFreeAtEnd, [true], "taken back once, when the device was free")
        XCTAssertEqual(model.snapshot.touchscreens.first { $0.id == UIFixtures.ilitek }?.mode, .driving, "never left undriven")
    }

    /// The pane's and the menu's Help Me Support say the same while a check is still letting go.
    func testTheEntriesWaitWhileALastCheckIsFinishing() throws {
        let snapshot = PreviewModel(.desk).snapshot
        let ilitek = try XCTUnwrap(snapshot.touchscreens.first { $0.id == UIFixtures.ilitek })
        XCTAssertEqual(SupportCheckAvailability.of(ilitek, in: snapshot, finishing: true), .lastCheckFinishing)
        XCTAssertEqual(SupportCheckAvailability.available.whileFinishing(true), .lastCheckFinishing)
        XCTAssertEqual(SupportCheckAvailability.setUpRunning.whileFinishing(true), .setUpRunning)
        XCTAssertEqual(SupportCheckAvailability.available.whileFinishing(false), .available)
    }

    /// A touchscreen Tactile holds shared is checked like any other, once the model has let go, and
    /// the window says macOS may act on its touches too.
    func testATouchscreenHeldSharedIsCheckedAndSaysSo() async throws {
        let shared = FakeModel()
        if let index = shared.snapshot.touchscreens.firstIndex(where: { $0.id == UIFixtures.ilitek }) {
            shared.snapshot.touchscreens[index].notes.append(.macOSMayAlsoRespond)
        }
        let desk = try desk(sending: .off, model: shared)
        XCTAssertEqual(desk.session.startAvailability, .available)
        XCTAssertTrue(desk.session.macOSMayActToo, "step 1 says so")
        await start(desk.session)
        XCTAssertNil(desk.session.startRefusal)
        XCTAssertEqual(shared.named, ["begin 1"], "the model lets go first")
        XCTAssertTrue(desk.system.calls.contains("open 21"))

        let plain = try self.desk(sending: .off)
        XCTAssertFalse(plain.session.macOSMayActToo)
    }

    /// Closed while a read is under way off the main thread: Tactile takes the touchscreen back only
    /// once the read has returned and the check has closed the device.
    func testClosingDuringTheTakeGivesItBackOnlyOnceTheDeviceIsFree() async throws {
        let desk = try desk(sending: .off)
        desk.system.holdsReads = true
        desk.session.start()
        await waitUntil { desk.system.readsHeld == 1 }
        XCTAssertEqual(desk.session.check?.stage, .taking)
        desk.session.stop()
        XCTAssertEqual(desk.model.named, ["begin 1"], "not yet: the read holds the device")
        XCTAssertFalse(desk.system.calls.contains { $0.hasPrefix("close") || $0 == "stopMatching" },
                       "nothing closed under the read in flight")
        desk.system.letReadsGo()
        await desk.session.starting?.value
        XCTAssertEqual(desk.system.calls.last, "stopMatching", "closed, then unmatched, once the read returned")
        XCTAssertEqual(desk.model.named, ["begin 1", "end 1"])
        XCTAssertEqual(desk.model.deviceWasFreeAtEnd, [true])
        XCTAssertFalse(desk.system.calls.contains { $0.hasPrefix("write") }, "nothing written after a read that was cut short")
        XCTAssertEqual(desk.session.check?.interruption, .stopped)
    }

    func testADeviceTactileDoesntListIsCheckedWithoutTheModel() async throws {
        let model = FakeModel()
        let desk = try desk(sending: .off, target: false, model: model)
        XCTAssertEqual(desk.session.startAvailability, .available)
        await start(desk.session)
        for _ in 0..<3 { desk.session.skip() }
        XCTAssertEqual(desk.session.check?.stage, .finished)
        XCTAssertEqual(model.commands, [], "the model has nothing to let go of")
    }

    func testADeviceThatIsntThereShowsWhy() throws {
        let book = DeviceLogBook()
        let environment = SupportSessionEnvironment(
            probe: SupportProbe(system: StandInHIDSystem([]), logBook: book), sending: .off, transport: FakeTransport(),
            logBook: book, mac: { SupportMac(model: "M", macOS: "26.1", tactileVersion: "0.7.0", tactileBuild: "1", displays: 1) },
            now: { 0 }, ticks: false, temporary: try folder(), home: "/", finishing: SupportChecksFinishing())
        let session = SupportCheckSession(deviceID: "1234:5678@01200000", touchscreen: nil, name: "Gone\u{202E}", perform: { _ in },
                                          snapshot: { nil }, environment: environment)
        XCTAssertNil(session.check)
        XCTAssertEqual(session.name, "Gone", "the name is plain text")
        session.start()
        session.stop()
    }

    // MARK: - Interrupted checks

    func testAnInterruptedCheckHasNoReportToSend() async throws {
        let asleep = try desk(sending: .on(.builtIn))
        asleep.session.stop()  // the Mac went to sleep at step 1
        XCTAssertEqual(asleep.session.check?.stage, .finished)
        XCTAssertEqual(asleep.session.check?.interruption, .stopped)
        asleep.session.showSheet()
        XCTAssertFalse(asleep.session.isShowingSheet)
        XCTAssertNil(asleep.session.archive)

        let midway = try desk(sending: .on(.builtIn))
        await start(midway.session)
        midway.session.skip()
        midway.session.stop()
        XCTAssertEqual(midway.session.check?.wasInterrupted, true)
        midway.session.showSheet()
        midway.session.form.email = "someone@example.com"
        midway.session.send()
        XCTAssertEqual(midway.transport.methods, [], "never sent")
    }

    // MARK: - The report

    /// Two identical units: the report's log holds the checked one's lines only.
    func testTheLogHoldsOnlyTheCheckedUnitsLines() async throws {
        let desk = try desk(sending: .off)
        desk.book.note(Self.touchID, category: "devices", "Connected device-1: 222a:0001 at 0x01141000; 10 contacts")
        desk.book.note(41, category: "devices", "Connected device-2: 222a:0001 at 0x01151000; 10 contacts")
        desk.book.note(41, category: "devices", "UNIT-B-0002 of the other unit")
        try await runThrough(desk)
        desk.session.showSheet()
        await settle(desk.session)
        let log = String(decoding: try XCTUnwrap(desk.session.archive?.files.first { $0.name == "tactile-log.txt" }).data,
                         as: UTF8.self)
        XCTAssertTrue(log.contains("Connected device-1"), log)
        XCTAssertTrue(log.contains("[support] Support check: taking it"), log)
        XCTAssertFalse(log.contains("device-2") || log.contains("UNIT-B"), log)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: desk.temporary.path), [], "the zip's folder is removed")
    }

    func testABuildThatDoesntSendOnlySaves() async throws {
        let desk = try desk(sending: .off)
        try await runThrough(desk)
        desk.session.showSheet()
        await settle(desk.session)
        XCTAssertTrue(desk.session.isShowingSheet)
        let archive = try XCTUnwrap(desk.session.archive)
        XCTAssertEqual(desk.session.sendStage, .off)
        desk.session.form.email = "someone@example.com"
        desk.session.send()
        XCTAssertEqual(desk.transport.methods, [], "a build that doesn't send never asks any site")

        let saved = desk.temporary.appendingPathComponent("saved.zip")
        desk.session.save(to: saved)
        XCTAssertEqual(desk.session.savedAs, "saved.zip")
        XCTAssertEqual(try Data(contentsOf: saved), archive.data, "the same zip the list showed")
    }

    /// Sleep while the report is being made: making it sends nothing, so it goes on, and the sheet
    /// shows it after wake.
    func testSleepDoesntStopTheReportBeingMade() async throws {
        let desk = try desk(sending: .off)
        try await runThrough(desk)
        desk.session.showSheet()
        desk.session.sleep()
        await desk.session.preparing?.value
        XCTAssertNotNil(desk.session.archive, "made all the same")
        XCTAssertNil(desk.session.check?.interruption, "a finished check stays finished")
    }

    /// A report whose making was cancelled (the window closing) is made again when the sheet opens
    /// again, never left on "Making the report…".
    func testACancelledReportIsMadeAgain() async throws {
        let desk = try desk(sending: .off)
        try await runThrough(desk)
        desk.session.showSheet()
        desk.session.stop()
        XCTAssertNil(desk.session.preparing, "cancelled, and forgotten")
        desk.session.showSheet()
        XCTAssertNotNil(desk.session.preparing, "made again")
        await desk.session.preparing?.value
        XCTAssertNotNil(desk.session.archive)
    }

    // MARK: - Sending

    func testTheSiteIsAskedOnlyAtSend() async throws {
        let desk = try desk(sending: .on(.builtIn))
        try await runThrough(desk)
        desk.session.showSheet()
        await settle(desk.session)
        XCTAssertEqual(desk.session.sendStage, .ready, "the form, at once")
        XCTAssertEqual(desk.transport.methods, [], "nothing asked of the site before Send")

        desk.session.send()
        XCTAssertEqual(desk.transport.methods, [], "no email yet: nothing sent")
        desk.session.form.email = "someone@example.com"
        desk.session.send()
        XCTAssertEqual(desk.session.sendStage, .sending)
        await settle(desk.session)
        XCTAssertEqual(desk.session.sendStage, .sent)
        XCTAssertEqual(desk.transport.methods, ["GET", "POST"])
    }

    func testWhenTheSiteDoesntTakeReportsNothingIsUploaded() async throws {
        let transport = FakeTransport()
        transport.available = false
        let desk = try desk(sending: .on(.builtIn), transport: transport)
        try await runThrough(desk)
        desk.session.showSheet()
        await settle(desk.session)
        desk.session.form.email = "someone@example.com"
        desk.session.send()
        await settle(desk.session)
        XCTAssertEqual(desk.session.sendStage, .unavailable)
        XCTAssertFalse(SupportSendSheetContent(stage: desk.session.sendStage, form: desk.session.form, saved: false).showsForm)
        XCTAssertEqual(transport.methods, ["GET"], "nothing uploaded")
    }

    func testStoppingBeforeTheUploadSendsNothing() async throws {
        let transport = FakeTransport()
        transport.holdsStatus = true
        let desk = try desk(sending: .on(.builtIn), transport: transport)
        try await runThrough(desk)
        desk.session.showSheet()
        await settle(desk.session)
        desk.session.form.email = "someone@example.com"
        desk.session.send()
        await waitUntil { transport.methods == ["GET"] }
        desk.session.cancelSending()
        XCTAssertEqual(desk.session.sendStage, .notSent)
        await desk.session.sendingTask?.value
        XCTAssertEqual(desk.session.sendStage, .notSent, "a cancelled send never goes on")
        XCTAssertEqual(transport.methods, ["GET"])
        XCTAssertEqual(transport.cancelled, ["GET"])
    }

    func testStoppingDuringTheUploadSaysItMayHaveGone() async throws {
        let transport = FakeTransport()
        transport.holdsUpload = true
        let desk = try desk(sending: .on(.builtIn), transport: transport)
        try await runThrough(desk)
        desk.session.showSheet()
        await settle(desk.session)
        desk.session.form.email = "someone@example.com"
        desk.session.send()
        await waitUntil { transport.methods == ["GET", "POST"] }
        desk.session.cancelSending()
        XCTAssertEqual(desk.session.sendStage, .mayHaveBeenSent)
        await desk.session.sendingTask?.value
        XCTAssertEqual(desk.session.sendStage, .mayHaveBeenSent)
        XCTAssertEqual(transport.cancelled, ["POST"], "the upload was cancelled")
        desk.session.send()
        XCTAssertEqual(transport.methods, ["GET", "POST"], "never sent twice")
    }

    func testClosingTheWindowWhileSendingCancelsIt() async throws {
        let transport = FakeTransport()
        transport.holdsUpload = true
        let desk = try desk(sending: .on(.builtIn), transport: transport)
        try await runThrough(desk)
        desk.session.showSheet()
        await settle(desk.session)
        desk.session.form.email = "someone@example.com"
        desk.session.send()
        await waitUntil { transport.methods == ["GET", "POST"] }
        desk.session.stop()
        XCTAssertEqual(desk.session.closedWhileSending, .mayHaveBeenSent, "the window tells the person")
        await desk.session.sendingTask?.value
        XCTAssertEqual(transport.cancelled, ["POST"])
    }

    func testAnUploadRefusedAfterAYesIsUnavailable() async throws {
        let transport = FakeTransport()
        transport.uploadStatus = 503
        let desk = try desk(sending: .on(.builtIn), transport: transport)
        try await runThrough(desk)
        desk.session.showSheet()
        await settle(desk.session)
        desk.session.form.email = "someone@example.com"
        desk.session.send()
        await settle(desk.session)
        XCTAssertEqual(desk.session.sendStage, .unavailable)
    }

    // MARK: - Pictures, for a person to look at

    /// Renders the window at each stage, and the sheet, to PNG files. Skipped unless `TACTILE_RENDER_UI`
    /// names a folder, as `UIRenderTests`. No window is opened: an `NSHostingView` that is never put in
    /// one draws each.
    func testRenderTheCheck() async throws {
        guard let path = ProcessInfo.processInfo.environment["TACTILE_RENDER_UI"], !path.isEmpty else {
            throw XCTSkip("Set TACTILE_RENDER_UI to a folder to render the interface.")
        }
        let out = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)

        let desk = try desk(sending: .on(.builtIn))
        let session = desk.session
        try render(SupportCheckView(session: session), size: SupportCheckWindow.size, to: out, name: "support-1-ready")
        await start(session)
        clock += 4
        session.tick()
        desk.system.send([0x04] + [UInt8](repeating: 0, count: 62), on: Self.touchID, at: clock)
        try render(SupportCheckView(session: session), size: SupportCheckWindow.size, to: out, name: "support-2-touching")
        let take = try XCTUnwrap(SurveyFixtures.surveyB.touchscreen(vendorID: 0x222a, productID: 0x0001)?.takes.first { $0.number == 3 })
        let first = take.reports.first?.hostTime ?? 0
        for report in take.reports { desk.system.send(report.bytes, on: Self.touchID, at: clock + 0.1 + report.hostTime - first) }
        for _ in 0..<3 { session.skip() }
        try render(SupportCheckView(session: session), size: SupportCheckWindow.size, to: out, name: "support-3-verdict")
        session.showSheet()
        await settle(session)
        session.form.email = "someone@example"
        try render(SupportSendSheet(session: session), size: SupportSendSheet.size, to: out, name: "support-4-sheet")

        let unavailable = FakeTransport()
        unavailable.available = false
        let offline = try self.desk(sending: .on(.builtIn), transport: unavailable)
        try await runThrough(offline)
        offline.session.showSheet()
        await settle(offline.session)
        offline.session.form.email = "someone@example.com"
        offline.session.send()
        await settle(offline.session)
        offline.session.save(to: offline.temporary.appendingPathComponent("r2.zip"))
        try render(SupportSendSheet(session: offline.session), size: SupportSendSheet.size, to: out, name: "support-5-unavailable")
        try render(SupportFileViewer(file: try XCTUnwrap(session.archive?.files.first)), size: CGSize(width: 640, height: 520),
                   to: out, name: "support-6-viewer")
        try render(Form { NotListedSection(snapshot: PreviewModel(.desk).snapshot, perform: { _ in }, list: nil) }.formStyle(.grouped),
                   size: CGSize(width: 560, height: 220), to: out, name: "support-7-not-listed")

        let refusing = FakeModel()
        refusing.snapshot.setUpMode = SetUpModeSnapshot(stage: .choosing, displays: [], touchscreens: [], justSetUp: nil, notice: nil)
        let waiting = try self.desk(sending: .off, model: refusing)
        try render(SupportCheckView(session: waiting.session), size: SupportCheckWindow.size, to: out, name: "support-8-start-waits")
        let interrupted = try self.desk(sending: .off)
        await start(interrupted.session)
        interrupted.session.stop()
        try render(SupportCheckView(session: interrupted.session), size: SupportCheckWindow.size, to: out, name: "support-9-interrupted")
    }

    private func render<V: View>(_ view: V, size: CGSize, to folder: URL, name: String) throws {
        for dark in [false, true] {
            let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = NSRect(origin: .zero, size: size)
            for _ in 0..<4 {
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try png.write(to: folder.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        }
    }
}
