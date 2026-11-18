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
/// ILITEK's interfaces, a fake transport and log entries made here: the model is told to let go and
/// to take back, the report is made, the site is asked, and the answer shown. No device, no window,
/// no network, and the temporary folder is removed.
@MainActor
final class SupportCheckSessionTests: XCTestCase {

    /// A HID system with the ILITEK behind it, answering every call with success.
    private final class StandInHIDSystem: HIDSystem {
        var connected: [HIDInterfaceDescription]
        private(set) var calls: [String] = []
        private var handlers: [HIDInterfaceID: @MainActor ([UInt8], TimeInterval) -> Void] = [:]

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

    /// Answers the status and the upload as told.
    private final class FakeTransport: SupportTransport, @unchecked Sendable {
        var available = true
        var uploadStatus = 202
        private(set) var methods: [String] = []

        func perform(_ request: URLRequest) async throws -> (Data, HTTPResult) {
            methods.append(request.httpMethod ?? "GET")
            if request.url?.path == SupportUploader.statusPath {
                return (Data(#"{"available":\#(available)}"#.utf8), HTTPResult(status: 200, url: request.url))
            }
            return (Data(#"{"status":"check-email"}"#.utf8), HTTPResult(status: uploadStatus, url: request.url))
        }
    }

    private static let touchID: HIDInterfaceID = 21, mouseID: HIDInterfaceID = 22

    private var clock: TimeInterval = 1000
    private var commands: [AppCommand] = []

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

    private func session(sending: SupportSending, transport: FakeTransport = FakeTransport(), target: Bool = true)
        throws -> (StandInHIDSystem, SupportCheckSession, URL) {
        let system = StandInHIDSystem(try ilitek())
        let temporary = try folder()
        let environment = SupportSessionEnvironment(
            probe: SupportProbe(system: system), sending: sending, transport: transport,
            readLog: {
                [SupportLogEntry(date: Date(timeIntervalSince1970: 0), category: "devices",
                                 message: #"Connected device-3: 222a:0001 "ILITEK-TP" serial "V06.00.00.00" at 0x01141000"#)]
            },
            mac: { SupportMac(model: "Mac15,6", macOS: "26.1", tactileVersion: "0.7.0", tactileBuild: "512", displays: 2) },
            now: { [unowned self] in self.clock }, ticks: false, temporary: temporary, home: "/Users/someone")
        let ilitek = try XCTUnwrap(PreviewModel(.desk).snapshot.touchscreens.first { $0.usbID == "222a:0001" })
        let session = SupportCheckSession(
            deviceID: target ? nil : "222a:0001@01141000", touchscreen: target ? SupportTarget(ilitek) : nil, name: ilitek.name,
            perform: { [unowned self] in self.commands.append($0) }, environment: environment)
        return (system, session, temporary)
    }

    /// Runs the check through: the ILITEK's one-finger take, then the other two steps skipped.
    private func runThrough(_ session: SupportCheckSession, _ system: StandInHIDSystem) throws {
        session.start()
        let take = try XCTUnwrap(SurveyFixtures.surveyB.touchscreen(vendorID: 0x222a, productID: 0x0001)?.takes.first { $0.number == 3 })
        let first = take.reports.first?.hostTime ?? 0
        for report in take.reports { system.send(report.bytes, on: Self.touchID, at: clock + 0.1 + report.hostTime - first) }
        clock += 3
        session.skip()
        session.skip()
        session.skip()
    }

    private func settle(_ session: SupportCheckSession) async {
        await session.preparing?.value
        await session.sendingTask?.value
    }

    // MARK: - Letting go and taking back

    func testTheModelLetsGoForTheCheckAndTakesItBackAtTheEnd() throws {
        let (system, session, _) = try session(sending: .off)
        let check = try XCTUnwrap(session.check)
        XCTAssertEqual(check.device.usbID, "222a:0001")
        XCTAssertEqual(commands, [], "nothing until Start Check")
        XCTAssertFalse(system.calls.contains { $0.hasPrefix("open") }, "nothing opened before Start Check")

        session.start()
        XCTAssertEqual(commands, [.beginSupportCheck(UIFixtures.ilitek)])
        XCTAssertTrue(system.calls.contains("open 21"))
        XCTAssertEqual(check.stage, .touching(.one))

        try runThroughRest(session)
        XCTAssertEqual(check.stage, .finished)
        XCTAssertEqual(commands, [.beginSupportCheck(UIFixtures.ilitek), .endSupportCheck], "taken back once the steps are over")
        session.stop()
        XCTAssertEqual(commands.filter { $0 == .endSupportCheck }.count, 1, "and only once")
    }

    private func runThroughRest(_ session: SupportCheckSession) throws {
        session.skip()
        session.skip()
        session.skip()
    }

    func testClosingMidCheckLetsTheDeviceGoAndGivesItBack() throws {
        let (system, session, _) = try session(sending: .off)
        session.start()
        session.stop()
        XCTAssertEqual(session.check?.stage, .finished)
        XCTAssertEqual(session.check?.interruption, .stopped)
        XCTAssertEqual(commands, [.beginSupportCheck(UIFixtures.ilitek), .endSupportCheck])
        XCTAssertTrue(system.calls.contains("close 21"))
        XCTAssertEqual(system.calls.last, "stopMatching")
    }

    func testADeviceTactileDoesntListIsCheckedWithoutTheModel() throws {
        let (_, session, _) = try session(sending: .off, target: false)
        session.start()
        try runThroughRest(session)
        XCTAssertEqual(session.check?.stage, .finished)
        XCTAssertEqual(commands, [], "the model has nothing to let go of")
    }

    func testADeviceThatIsntThereShowsWhy() throws {
        let system = StandInHIDSystem([])
        let environment = SupportSessionEnvironment(
            probe: SupportProbe(system: system), sending: .off, transport: FakeTransport(), readLog: { [] },
            mac: { SupportMac(model: "M", macOS: "26.1", tactileVersion: "0.7.0", tactileBuild: "1", displays: 1) },
            now: { 0 }, ticks: false, temporary: try folder(), home: "/")
        let session = SupportCheckSession(deviceID: "1234:5678@01200000", touchscreen: nil, name: "Gone", perform: { _ in },
                                          environment: environment)
        XCTAssertNil(session.check)
        session.start()
        session.stop()
    }

    // MARK: - The sheet

    func testABuildThatDoesntSendOnlySaves() async throws {
        let transport = FakeTransport()
        let (system, session, temporary) = try session(sending: .off, transport: transport)
        try runThrough(session, system)
        session.showSheet()
        await settle(session)
        XCTAssertTrue(session.isShowingSheet)
        let archive = try XCTUnwrap(session.archive)
        XCTAssertEqual(archive.files.last?.name, "manifest.json")
        XCTAssertTrue(String(decoding: try XCTUnwrap(archive.files.first { $0.name == "tactile-log.txt" }).data, as: UTF8.self)
            .contains(#"serial "[serial removed]""#), "the log's line, without its serial")
        XCTAssertEqual(session.sendStage, .off)
        XCTAssertEqual(transport.methods, [], "nothing asked of any site")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporary.path), [], "the zip's folder is removed")

        session.form.email = "someone@example.com"
        session.send()
        XCTAssertEqual(transport.methods, [], "a build that doesn't send never sends")

        let saved = temporary.appendingPathComponent("saved.zip")
        session.save(to: saved)
        XCTAssertEqual(session.savedAs, "saved.zip")
        XCTAssertEqual(try Data(contentsOf: saved), archive.data, "the same zip the list showed")
    }

    func testTheOfficialBuildAsksTheSiteThenSends() async throws {
        let transport = FakeTransport()
        let (system, session, _) = try session(sending: .on(.builtIn), transport: transport)
        try runThrough(session, system)
        session.showSheet()
        XCTAssertEqual(session.sendStage, .checking)
        await settle(session)
        XCTAssertEqual(session.sendStage, .ready)
        XCTAssertEqual(transport.methods, ["GET"])

        session.send()
        XCTAssertEqual(session.sendStage, .ready, "no email yet: nothing sent")
        session.form.email = "someone@example.com"
        session.send()
        XCTAssertEqual(session.sendStage, .sending)
        await settle(session)
        XCTAssertEqual(session.sendStage, .sent)
        XCTAssertEqual(transport.methods, ["GET", "GET", "POST"], "asked again just before the upload")
    }

    func testWhenTheSiteDoesntTakeReportsTheSheetOffersSaving() async throws {
        let transport = FakeTransport()
        transport.available = false
        let (system, session, _) = try session(sending: .on(.builtIn), transport: transport)
        try runThrough(session, system)
        session.showSheet()
        await settle(session)
        XCTAssertEqual(session.sendStage, .unavailable)
        XCTAssertFalse(SupportSendSheetContent(stage: session.sendStage, form: session.form, saved: false).showsForm)
        XCTAssertEqual(transport.methods, ["GET"], "nothing uploaded")
    }

    func testAnUploadRefusedAfterAYesIsUnavailable() async throws {
        let transport = FakeTransport()
        transport.uploadStatus = 503
        let (system, session, _) = try session(sending: .on(.builtIn), transport: transport)
        try runThrough(session, system)
        session.showSheet()
        await settle(session)
        session.form.email = "someone@example.com"
        session.send()
        await settle(session)
        XCTAssertEqual(session.sendStage, .unavailable)
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

        let (system, session, temporary) = try session(sending: .on(.builtIn))
        try render(SupportCheckView(session: session), size: SupportCheckWindow.size, to: out, name: "support-1-ready")
        session.start()
        clock += 4
        session.tick()
        system.send([0x04] + [UInt8](repeating: 0, count: 62), on: Self.touchID, at: clock)
        try render(SupportCheckView(session: session), size: SupportCheckWindow.size, to: out, name: "support-2-touching")
        try runThrough(session, system)
        try render(SupportCheckView(session: session), size: SupportCheckWindow.size, to: out, name: "support-3-verdict")
        session.showSheet()
        await settle(session)
        session.form.email = "someone@example"
        try render(SupportSendSheet(session: session), size: SupportSendSheet.size, to: out, name: "support-4-sheet")
        session.save(to: temporary.appendingPathComponent("r.zip"))
        session.form.email = "someone@example.com"
        let unavailable = FakeTransport()
        unavailable.available = false
        let (system2, offline, _) = try self.session(sending: .on(.builtIn), transport: unavailable)
        try runThrough(offline, system2)
        offline.showSheet()
        await settle(offline)
        offline.save(to: temporary.appendingPathComponent("r2.zip"))
        try render(SupportSendSheet(session: offline), size: SupportSendSheet.size, to: out, name: "support-5-unavailable")
        try render(SupportFileViewer(file: try XCTUnwrap(session.archive?.files.first)), size: CGSize(width: 640, height: 520),
                   to: out, name: "support-6-viewer")
        try render(Form { NotListedSection(snapshot: PreviewModel(.desk).snapshot, perform: { _ in }, list: nil) }.formStyle(.grouped),
                   size: CGSize(width: 560, height: 220), to: out, name: "support-7-not-listed")
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
