import IOKit
import TactileReading
import TactileTestSupport
import XCTest
@testable import TactileDevices

/// The check's hands on a device: it lists what is connected without opening anything, takes a
/// device exactly as the touchscreen source takes a touchscreen, records what each call returned,
/// hands over the raw reports, and lets the device go as the source does.
@MainActor
final class SupportProbeTests: XCTestCase {

    private func make(_ connected: [HIDInterfaceDescription]) -> (FakeHIDSystem, SupportProbe) {
        let system = FakeHIDSystem(connected: connected)
        system.inputModeInterfaces = [SupportDesk.stripTouchID]
        let probe = SupportProbe(system: system)
        return (system, probe)
    }

    private func device(_ probe: SupportProbe, _ usbID: String) throws -> SupportDevice {
        try XCTUnwrap(probe.devices.first { $0.usbID == usbID }, "\(usbID) is not offered")
    }

    // MARK: - Listing

    func testListingOpensNothing() async throws {
        let (system, probe) = make(try SupportDesk.all())
        var changes = 0
        probe.onDevicesChanged = { changes += 1 }
        probe.start()
        XCTAssertEqual(probe.devices.map(\.usbID), ["27c0:0859", "222a:0001", "1234:5678", "256c:006d"])
        XCTAssertEqual(system.calls, [.startMatching], "listing reads what the system described, and opens nothing")

        var another = SupportDesk.pointer()
        another.id = 99
        another.locationID = 0x0199_0000
        system.connect(another)
        XCTAssertEqual(probe.devices.count, 5)
        system.disconnect(99)
        XCTAssertEqual(probe.devices.count, 4)
        XCTAssertEqual(changes, 2, "each change is told")

        probe.stop()
        XCTAssertEqual(probe.devices, [])
        XCTAssertEqual(system.calls, [.startMatching, .stopMatching])
    }

    // MARK: - Taking, exactly as the source takes

    /// The calls the touchscreen source makes to take and then release the touchscreen with this USB
    /// vendor ID, on a desk of its own.
    private func sourceCalls(_ connected: [HIDInterfaceDescription], vendorID: Int, configure: (FakeHIDSystem) -> Void)
        -> (take: [FakeHIDSystem.Call], release: [FakeHIDSystem.Call]) {
        let system = FakeHIDSystem(connected: connected)
        system.inputModeInterfaces = [SupportDesk.stripTouchID]
        configure(system)
        let delegate = RecordingDelegate()
        let source = HIDTouchscreenSource(system: system)
        source.delegate = delegate
        source.start()
        system.runLater()
        guard let handle = delegate.connected.first(where: { $0.facts.vendorID == vendorID })?.handle else {
            XCTFail("the source didn't announce \(vendorID)")
            return ([], [])
        }
        system.clearCalls()
        source.setState(.taken, for: handle)
        let take = system.calls
        system.clearCalls()
        source.setState(.released, for: handle)
        return (take, system.calls)
    }

    private func probeCalls(_ connected: [HIDInterfaceDescription], usbID: String, configure: (FakeHIDSystem) -> Void) async throws
        -> (take: [FakeHIDSystem.Call], release: [FakeHIDSystem.Call]) {
        let (system, probe) = make(connected)
        configure(system)
        probe.start()
        system.clearCalls()
        let taken = await probe.take(try device(probe, usbID), onReport: { _ in }, onGone: { _ in })
        XCTAssertNotNil(taken)
        let take = system.calls
        system.clearCalls()
        probe.release()
        return (take, system.calls)
    }

    func testTheStripIsTakenAndReleasedAsTheSourceDoes() async throws {
        let desk = try SupportDesk.strip()
        let source = sourceCalls(desk, vendorID: Panels.wchVendorID) { _ in }
        let probe = try await probeCalls(desk, usbID: "27c0:0859") { _ in }
        XCTAssertEqual(probe.take, source.take)
        XCTAssertEqual(probe.release, source.release)
        XCTAssertTrue(probe.take.contains(.writeInputMode(SupportDesk.stripTouchID, 2)))
        XCTAssertTrue(probe.release.contains(.writeInputMode(SupportDesk.stripTouchID, 0)))
    }

    func testTheILITEKIsTakenAndReleasedAsTheSourceDoes() async throws {
        let desk = try SupportDesk.ilitek()
        let source = sourceCalls(desk, vendorID: Panels.ilitekVendorID) { _ in }
        let probe = try await probeCalls(desk, usbID: "222a:0001") { _ in }
        XCTAssertEqual(probe.take, source.take)
        XCTAssertEqual(probe.release, source.release)
        XCTAssertTrue(probe.take.contains(.readFeatureReport(SupportDesk.ilitekTouchID, reportID: 0x06, length: 258)))
        XCTAssertFalse(probe.take.contains { if case .writeInputMode = $0 { return true } else { return false } },
                       "the ILITEK has no Input Mode")
    }

    func testOpeningSharedAFailedReadAndARefusedWriteGoAsTheSourcesDo() async throws {
        let desk = try SupportDesk.strip()
        let configure: (FakeHIDSystem) -> Void = { system in
            system.openResults[SupportDesk.stripTouchID] = (FakeHIDSystem.refused, kIOReturnSuccess)
            system.openResults[SupportDesk.stripMouseID] = (FakeHIDSystem.refused, FakeHIDSystem.refused)
            system.readResult = FakeHIDSystem.notPermitted
            system.writeResult = FakeHIDSystem.notPermitted
        }
        let source = sourceCalls(desk, vendorID: Panels.wchVendorID, configure: configure)
        let probe = try await probeCalls(desk, usbID: "27c0:0859", configure: configure)
        XCTAssertEqual(probe.take, source.take)
        XCTAssertEqual(probe.release, source.release)
    }

    func testAReadThatTimesOutEndsTheReadsAsTheSourcesDo() async throws {
        var touch = try SupportDesk.strip()[0]
        touch.descriptor = Panels.twoFeatureReportsTouchscreen
        let configure: (FakeHIDSystem) -> Void = { $0.readSeconds = 5 }
        let source = sourceCalls([touch], vendorID: Panels.wchVendorID, configure: configure)
        let probe = try await probeCalls([touch], usbID: "27c0:0859", configure: configure)
        XCTAssertEqual(probe.take, source.take)
        XCTAssertEqual(probe.take.filter { if case .readFeatureReport = $0 { return true } else { return false } },
                       [.readFeatureReport(SupportDesk.stripTouchID, reportID: 0x03, length: 2)])
    }

    // MARK: - What it records

    func testTheSwitchesAreRecordedWithTheBytesThatCameBack() async throws {
        let (system, probe) = make(try SupportDesk.all())
        system.featureReportBytes[0x0A] = [0x0A, 0x0A]
        probe.start()
        let taken = await probe.take(try device(probe, "27c0:0859"), onReport: { _ in }, onGone: { _ in })
        let switches = try XCTUnwrap(taken)
        XCTAssertEqual(switches.opens, [
            SupportSwitches.Open(interface: SupportDesk.stripTouchID, role: .touch, exclusiveResult: 0, sharedResult: nil),
            SupportSwitches.Open(interface: SupportDesk.stripMouseID, role: .mouse, exclusiveResult: 0, sharedResult: nil),
        ])
        XCTAssertEqual(switches.opens.map(\.held), [.exclusively, .exclusively])
        XCTAssertEqual(switches.reads, [
            SupportSwitches.FeatureRead(reportID: 0x0A, contents: ["Contact Count Maximum"], lengthAsked: 2, lengthReturned: 2,
                                        result: 0, seconds: 0, bytes: [0x0A, 0x0A]),
        ])
        XCTAssertEqual(switches.hasInputMode, true)
        XCTAssertEqual(switches.inputModeWrite, SupportSwitches.ModeWrite(value: 2, result: 0))
        XCTAssertFalse(switches.readsStoppedAfterTimeout)

        XCTAssertEqual(probe.release(), SupportSwitches.ModeWrite(value: 0, result: 0), "0 is written back after a 2")
        XCTAssertNil(probe.release(), "nothing more to let go of")
    }

    func testAFailedReadIsRecordedAndTheTakeGoesOn() async throws {
        let (system, probe) = make(try SupportDesk.all())
        system.readResults[0x0A] = FakeHIDSystem.notPermitted
        system.openResults[SupportDesk.stripMouseID] = (FakeHIDSystem.refused, kIOReturnSuccess)
        probe.start()
        let taken = await probe.take(try device(probe, "27c0:0859"), onReport: { _ in }, onGone: { _ in })
        let switches = try XCTUnwrap(taken)
        XCTAssertEqual(switches.reads.map(\.result), [FakeHIDSystem.notPermitted])
        XCTAssertEqual(switches.reads.map(\.lengthReturned), [0])
        XCTAssertEqual(switches.reads.map(\.bytes), [[]])
        XCTAssertEqual(switches.inputModeWrite?.value, 2, "the take goes on")
        XCTAssertEqual(switches.opens[1].held, .shared)
        XCTAssertEqual(switches.opens[1].sharedResult, 0)
        XCTAssertEqual(SupportSwitches.ioReturnText(FakeHIDSystem.notPermitted), "0xe00002e2")
    }

    func testAnInterfaceThatCantBeOpenedIsNeitherReadNorSwitched() async throws {
        let (system, probe) = make(try SupportDesk.all())
        system.openResults[SupportDesk.stripTouchID] = (FakeHIDSystem.refused, FakeHIDSystem.notPermitted)
        probe.start()
        let taken = await probe.take(try device(probe, "27c0:0859"), onReport: { _ in }, onGone: { _ in })
        let switches = try XCTUnwrap(taken)
        XCTAssertEqual(switches.opens[0].held, .notOpened)
        XCTAssertEqual(switches.reads, [])
        XCTAssertNil(switches.hasInputMode, "not asked: it isn't open")
        XCTAssertNil(switches.inputModeWrite)
        XCTAssertNil(probe.release())
    }

    func testAVendorInterfaceIsNeverOpened() async throws {
        let (system, probe) = make(try SupportDesk.all())
        probe.start()
        _ = await probe.take(try device(probe, "27c0:0859"), onReport: { _ in }, onGone: { _ in })
        probe.release()
        probe.stop()
        XCTAssertFalse(system.calls.contains { call in
            switch call {
            case .open(let id, _), .close(let id, _), .hasInputMode(let id), .readFeatureReport(let id, _, _),
                 .writeInputMode(let id, _), .startReports(let id, _), .stopReports(let id):
                return id == SupportDesk.stripVendorID
            case .startMatching, .stopMatching:
                return false
            }
        })
    }

    // MARK: - Mouse-only

    func testAMouseOnlyDeviceIsOpenedAndListenedToAndNothingElse() async throws {
        let (system, probe) = make(try SupportDesk.all())
        probe.start()
        system.clearCalls()
        let taken = await probe.take(try device(probe, "1234:5678"), onReport: { _ in }, onGone: { _ in })
        let switches = try XCTUnwrap(taken)
        XCTAssertEqual(system.calls, [
            .open(SupportDesk.pointerID, exclusive: true),
            .startReports(SupportDesk.pointerID, bufferSize: 80),
        ])
        XCTAssertEqual(switches.reads, [])
        XCTAssertNil(switches.hasInputMode)
        XCTAssertNil(switches.inputModeWrite)
        system.clearCalls()
        XCTAssertNil(probe.release())
        XCTAssertEqual(system.calls, [.stopReports(SupportDesk.pointerID), .close(SupportDesk.pointerID, exclusive: true)])
    }

    // MARK: - Reports and unplugging

    func testReportsArriveWithTheirInterfaceUntilTheDeviceIsLetGo() async throws {
        let (system, probe) = make(try SupportDesk.all())
        system.keepsDeliveringAfterStop = true
        probe.start()
        var reports: [SupportRawReport] = []
        _ = await probe.take(try device(probe, "27c0:0859"), onReport: { reports.append($0) }, onGone: { _ in })
        system.send(Panels.wchMouse(buttons: 1, x: 0.5, y: 0.5), on: SupportDesk.stripMouseID, at: 10)
        system.send(Panels.wchTouch(id: 1, x: 0.5, y: 0.5), on: SupportDesk.stripTouchID, at: 11)
        probe.release()
        system.send(Panels.wchMouse(buttons: 0, x: 0.5, y: 0.5), on: SupportDesk.stripMouseID, at: 12)
        XCTAssertEqual(reports.map(\.role), [.mouse, .touch])
        XCTAssertEqual(reports.map(\.interface), [SupportDesk.stripMouseID, SupportDesk.stripTouchID])
        XCTAssertEqual(reports.map(\.time), [10, 11])
        XCTAssertEqual(reports.first?.bytes, Panels.wchMouse(buttons: 1, x: 0.5, y: 0.5))
    }

    func testUnpluggingWritesNothingAndSaysSo() async throws {
        let (system, probe) = make(try SupportDesk.all())
        probe.start()
        var gone = 0
        _ = await probe.take(try device(probe, "27c0:0859"), onReport: { _ in }, onGone: { _ in gone += 1 })
        system.clearCalls()
        system.disconnect(SupportDesk.stripTouchID)
        XCTAssertEqual(gone, 1)
        XCTAssertFalse(system.calls.contains { if case .writeInputMode = $0 { return true } else { return false } },
                       "nothing is written to a device that has gone")
        XCTAssertTrue(system.calls.contains(.close(SupportDesk.stripMouseID, exclusive: true)), "what is left is closed")
        XCTAssertNil(probe.release(), "it is already let go")
        XCTAssertFalse(probe.devices.contains { $0.usbID == "27c0:0859" && $0.touchInterface != nil })
    }

    func testADeviceThatHasGoneCantBeTaken() async throws {
        let (system, probe) = make(try SupportDesk.all())
        probe.start()
        let pointer = try device(probe, "1234:5678")
        system.disconnect(SupportDesk.pointerID)
        let taken = await probe.take(pointer, onReport: { _ in }, onGone: { _ in })
        XCTAssertNil(taken)
    }

    func testStoppingLetsTheDeviceGo() async throws {
        let (system, probe) = make(try SupportDesk.all())
        probe.start()
        _ = await probe.take(try device(probe, "27c0:0859"), onReport: { _ in }, onGone: { _ in })
        system.clearCalls()
        probe.stop()
        XCTAssertEqual(system.calls.first, .stopReports(SupportDesk.stripTouchID))
        XCTAssertTrue(system.calls.contains(.writeInputMode(SupportDesk.stripTouchID, 0)))
        XCTAssertEqual(system.calls.last, .stopMatching)
    }

    // MARK: - One interface going (M-2), and reads off the main thread (M-7)

    /// The mouse interface goes while the touch interface stays: the take ends as a release does,
    /// 0 written back to the touch interface, best effort.
    func testWhenOneInterfaceGoesTheOtherIsSwitchedBack() async throws {
        let (system, probe) = make(try SupportDesk.all())
        probe.start()
        var writeBacks: [SupportSwitches.ModeWrite?] = []
        _ = await probe.take(try device(probe, "27c0:0859"), onReport: { _ in }, onGone: { writeBacks.append($0) })
        system.clearCalls()
        system.disconnect(SupportDesk.stripMouseID)
        XCTAssertEqual(writeBacks, [SupportSwitches.ModeWrite(value: 0, result: 0)])
        XCTAssertTrue(system.calls.contains(.writeInputMode(SupportDesk.stripTouchID, 0)), "the touch interface is switched back")
        XCTAssertTrue(system.calls.contains(.close(SupportDesk.stripTouchID, exclusive: true)))
        XCTAssertNil(probe.release(), "already let go")
    }

    /// The reads run off the main thread: while one is under way, a release waits for it, then
    /// closes everything, and nothing is written.
    func testAReleaseDuringAReadWaitsForItAndWritesNothing() async throws {
        let (system, probe) = make(try SupportDesk.all())
        system.suspendsReads = true
        probe.start()
        let device = try device(probe, "27c0:0859")
        let taking = Task { @MainActor in await probe.take(device, onReport: { _ in }, onGone: { _ in }) }
        while system.readsWaiting == 0 { await Task.yield() }
        XCTAssertNil(probe.release(), "deferred until the read returns")
        XCTAssertFalse(system.calls.contains { if case .close = $0 { return true } else { return false } })
        system.resumeReads()
        let switches = await taking.value
        XCTAssertNil(switches, "the take didn't finish")
        XCTAssertFalse(system.calls.contains { if case .writeInputMode = $0 { return true } else { return false } })
        XCTAssertTrue(system.calls.contains(.close(SupportDesk.stripTouchID, exclusive: true)))
        XCTAssertTrue(system.calls.contains(.close(SupportDesk.stripMouseID, exclusive: true)))
    }

    /// Unplugged during a read: everything is closed at once, nothing written, and the take ends.
    func testUnpluggedDuringAReadTheTakeEnds() async throws {
        let (system, probe) = make(try SupportDesk.all())
        system.suspendsReads = true
        probe.start()
        var gone = 0
        let device = try device(probe, "27c0:0859")
        let taking = Task { @MainActor in await probe.take(device, onReport: { _ in }, onGone: { _ in gone += 1 }) }
        while system.readsWaiting == 0 { await Task.yield() }
        system.disconnect(SupportDesk.stripTouchID)
        XCTAssertEqual(gone, 1)
        system.resumeReads()
        let switches = await taking.value
        XCTAssertNil(switches)
        XCTAssertFalse(system.calls.contains { if case .writeInputMode = $0 { return true } else { return false } })
    }

    /// Every line of a take goes into the log book, keyed by the device's touch interface.
    func testTheTakeIsWrittenInTheLogBook() async throws {
        let system = FakeHIDSystem(connected: try SupportDesk.all())
        system.inputModeInterfaces = [SupportDesk.stripTouchID]
        let book = DeviceLogBook()
        let probe = SupportProbe(system: system, logBook: book)
        probe.start()
        _ = await probe.take(try device(probe, "27c0:0859"), onReport: { _ in }, onGone: { _ in })
        probe.release()
        let lines = book.entries(about: [SupportDesk.stripTouchID]).map(\.text)
        XCTAssertEqual(lines.first, "Support check: taking it (touchscreen) as Tactile takes a touchscreen")
        XCTAssertTrue(lines.contains("Support check: read feature report 0x0A: 2 bytes asked, 2 returned in 0.000 s (IOReturn 0x00000000)"))
        XCTAssertTrue(lines.contains("Support check: Input Mode 0 (mouse emulation) written back (IOReturn 0x00000000)"))
        XCTAssertEqual(lines.last, "Support check: let go")
        XCTAssertFalse(lines.joined().contains(SupportDesk.stripSerial))
    }
}
