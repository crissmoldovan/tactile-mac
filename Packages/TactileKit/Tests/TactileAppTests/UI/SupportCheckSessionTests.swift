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

        func open(_ id: HIDInterfaceID, exclusive: Bool) -> IOReturn {
            calls.append("open \(id)")
            return kIOReturnSuccess
        }

        func close(_ id: HIDInterfaceID, exclusive: Bool) -> IOReturn {
            calls.append("close \(id)")
            return kIOReturnSuccess
        }

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

    /// The model as the check sees it: the preview desk's snapshot, which lets go of a touchscreen
    /// on `beginSupportCheck` (unless told not to) and takes it back on `endSupportCheck`.
    @MainActor
    private final class FakeModel {
        var snapshot = PreviewModel(.desk).snapshot
        var letsGo = true
        private(set) var commands: [AppCommand] = []
        /// Whether the device was closed when Tactile was told to take it back, each time.
        private(set) var deviceWasFreeAtEnd: [Bool] = []
        var isDeviceFree: () -> Bool = { true }

        func perform(_ command: AppCommand) {
            commands.append(command)
            switch command {
            case .beginSupportCheck(let id) where letsGo:
                set(id, mode: .released)
            case .endSupportCheck:
                deviceWasFreeAtEnd.append(isDeviceFree())
                set(UIFixtures.ilitek, mode: .driving)
            default:
                break
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
                      transport: FakeTransport = FakeTransport()) throws -> Desk {
        let model = given ?? FakeModel()
        let system = StandInHIDSystem(try ilitek())
        let temporary = try folder()
        let book = DeviceLogBook()
        let environment = SupportSessionEnvironment(
            probe: SupportProbe(system: system, logBook: book), sending: sending, transport: transport, logBook: book,
            mac: { SupportMac(model: "Mac15,6", macOS: "26.1", tactileVersion: "0.7.0", tactileBuild: "512", displays: 2) },
            now: { [unowned self] in self.clock }, ticks: false, temporary: temporary, home: "/Users/someone")
        model.isDeviceFree = { [unowned system] in
            system.calls.filter { $0 == "open \(Self.touchID)" }.count == system.calls.filter { $0 == "close \(Self.touchID)" }.count
        }
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

    /// Waits, a turn at a time, until `condition` holds, for at most a second.
    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(1)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
    }

    // MARK: - Letting go and taking back

    func testTheModelLetsGoForTheCheckAndTakesItBackOnceTheDeviceIsFree() async throws {
        let desk = try desk(sending: .off)
        let check = try XCTUnwrap(desk.session.check)
        XCTAssertEqual(desk.model.commands, [], "nothing until Start Check")
        XCTAssertFalse(desk.system.calls.contains { $0.hasPrefix("open") }, "nothing opened before Start Check")

        await start(desk.session)
        XCTAssertEqual(desk.model.commands, [.beginSupportCheck(UIFixtures.ilitek)])
        XCTAssertTrue(desk.system.calls.contains("open 21"))
        XCTAssertEqual(check.stage, .touching(.one))

        for _ in 0..<3 { desk.session.skip() }
        XCTAssertEqual(check.stage, .finished)
        XCTAssertEqual(desk.model.commands, [.beginSupportCheck(UIFixtures.ilitek), .endSupportCheck])
        XCTAssertEqual(desk.model.deviceWasFreeAtEnd, [true], "taken back only once the check had closed it")
        desk.session.stop()
        XCTAssertEqual(desk.model.commands.filter { $0 == .endSupportCheck }.count, 1, "and only once")
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
        let heldShared = try desk(sending: .off, model: shared)
        await start(heldShared.session)
        XCTAssertEqual(heldShared.session.startRefusal, "Another program holds this touchscreen. Quit it, then try again.")
        XCTAssertEqual(shared.commands, [])

        let refusing = FakeModel()
        refusing.letsGo = false
        let refused = try desk(sending: .off, model: refusing)
        await start(refused.session)
        XCTAssertEqual(refused.session.startRefusal, "Tactile couldn’t let go of the touchscreen just now. Try again in a moment.")
        XCTAssertEqual(refusing.commands, [.beginSupportCheck(UIFixtures.ilitek), .endSupportCheck])
        XCTAssertFalse(refused.system.calls.contains { $0.hasPrefix("open") }, "nothing it holds is touched")
        XCTAssertEqual(refused.session.check?.stage, .ready)
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
        XCTAssertEqual(desk.model.commands, [.beginSupportCheck(UIFixtures.ilitek)], "not yet: the read holds the device")
        desk.system.letReadsGo()
        await desk.session.starting?.value
        XCTAssertEqual(desk.model.commands, [.beginSupportCheck(UIFixtures.ilitek), .endSupportCheck])
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
            now: { 0 }, ticks: false, temporary: try folder(), home: "/")
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
