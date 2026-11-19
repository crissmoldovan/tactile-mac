import CoreGraphics
import IOKit
import TactileReading
import TactileScreens
import TactileTestSupport
import XCTest
@testable import TactileDevices

/// The interfaces on the desk, as the HID system describes them.
private enum Desk {
    static let wchTouchID: HIDInterfaceID = 11, wchMouseID: HIDInterfaceID = 12
    static let ilitekTouchID: HIDInterfaceID = 21, ilitekMouseID: HIDInterfaceID = 22
    static let otherMouseID: HIDInterfaceID = 31

    static func wchTouch(id: HIDInterfaceID = wchTouchID) throws -> HIDInterfaceDescription {
        interface(id, at: wchLocation, try Panels.descriptor(Panels.wch(), "touchscreen"), listsTouchScreen: true,
                  vendorID: Panels.wchVendorID, productID: Panels.wchProductID, serial: "TEST-SERIAL-0001",
                  product: "TouchScreen", maxInputReportSize: 54)
    }

    /// The strip's touchscreen interface, with another descriptor.
    static func wchTouch(descriptor: [UInt8]) -> HIDInterfaceDescription {
        interface(wchTouchID, at: wchLocation, descriptor, listsTouchScreen: true,
                  vendorID: Panels.wchVendorID, productID: Panels.wchProductID, serial: "TEST-SERIAL-0001",
                  product: "TouchScreen", maxInputReportSize: 54)
    }

    static func wchMouse(id: HIDInterfaceID = wchMouseID) throws -> HIDInterfaceDescription {
        interface(id, at: wchLocation, try Panels.descriptor(Panels.wch(), "mouse"), usages: Panels.wchMouseUsages,
                  vendorID: Panels.wchVendorID, productID: Panels.wchProductID, serial: "TEST-SERIAL-0001",
                  product: "TouchScreen", maxInputReportSize: 7)
    }

    static func ilitekTouch(id: HIDInterfaceID = ilitekTouchID) throws -> HIDInterfaceDescription {
        interface(id, at: ilitekLocation, try Panels.descriptor(Panels.ilitek(), "touchscreen"), listsTouchScreen: true,
                  vendorID: Panels.ilitekVendorID, productID: Panels.ilitekProductID, serial: "V06.00.00.00",
                  product: "ILITEK-TP", maxInputReportSize: 64)
    }

    static func ilitekMouse(id: HIDInterfaceID = ilitekMouseID, at location: UInt32 = ilitekLocation) throws -> HIDInterfaceDescription {
        interface(id, at: location, try Panels.descriptor(Panels.ilitek(), "mouse"), usages: Panels.ilitekMouseUsages,
                  vendorID: Panels.ilitekVendorID, productID: Panels.ilitekProductID, serial: "V06.00.00.00",
                  product: "ILITEK-TP", maxInputReportSize: 64)
    }

    /// Someone's own absolute mouse, elsewhere on the bus.
    static func otherMouse(id: HIDInterfaceID = otherMouseID, at location: UInt32 = 0x0010_0000) throws -> HIDInterfaceDescription {
        interface(id, at: location, try Panels.descriptor(Panels.wch(), "mouse"), usages: [.mouse], vendorID: 0x05ac, productID: 0x0265,
                  serial: "", product: "Magic Trackpad", maxInputReportSize: 7)
    }

    static func all() throws -> [HIDInterfaceDescription] {
        [try otherMouse(), try wchMouse(), try wchTouch(), try ilitekTouch(), try ilitekMouse()]
    }
}

private extension FakeHIDSystem.Call {
    var interfaceID: HIDInterfaceID? {
        switch self {
        case .startMatching, .stopMatching: return nil
        case .open(let id, _), .close(let id, _), .closeInBackground(let id, _), .hasInputMode(let id),
             .readFeatureReport(let id, _, _), .writeInputMode(let id, _), .startReports(let id, _), .stopReports(let id): return id
        }
    }
}

@MainActor
final class HIDTouchscreenSourceTests: XCTestCase {

    private func make(_ connected: [HIDInterfaceDescription]) -> (FakeHIDSystem, RecordingDelegate, HIDTouchscreenSource) {
        let system = FakeHIDSystem(connected: connected)
        system.inputModeInterfaces = [Desk.wchTouchID]
        let delegate = RecordingDelegate()
        let source = HIDTouchscreenSource(system: system)
        source.delegate = delegate
        return (system, delegate, source)
    }

    private func handle(_ delegate: RecordingDelegate, vendorID: Int) throws -> DeviceHandle {
        try XCTUnwrap(delegate.connected.last { $0.facts.vendorID == vendorID }, "not connected").handle
    }

    private let taken = DeviceStatus(state: .taken, inputMode: .switchedToMultiTouch, touchOrigin: .undetermined, exclusive: .held)

    // MARK: - Finding and announcing

    func testStartAnnouncesTheTouchscreensAlreadyConnected() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()

        XCTAssertEqual(delegate.connected.count, 2)
        let strip = try XCTUnwrap(delegate.connected.first)
        XCTAssertEqual(strip.facts, TouchscreenFacts(vendorID: 0x27c0, productID: 0x0859, serial: "TEST-SERIAL-0001",
                                                     locationID: wchLocation, name: "TouchScreen"))
        XCTAssertEqual(strip.maxContacts, 10)
        XCTAssertEqual(strip.reportedSizeMM?.width ?? 0, 216.9, accuracy: 0.1)
        XCTAssertEqual(strip.reportedSizeMM?.height ?? 0, 90.6, accuracy: 0.1)
        XCTAssertTrue(strip.hasMouseInterface)
        XCTAssertFalse(strip.reportsPalms, "no contact size or confidence in its descriptor")
        XCTAssertEqual(strip.status, DeviceStatus())

        let ilitek = try XCTUnwrap(delegate.connected.last)
        XCTAssertEqual(ilitek.facts, TouchscreenFacts(vendorID: 0x222a, productID: 0x0001, serial: "V06.00.00.00",
                                                      locationID: ilitekLocation, name: "ILITEK-TP"))
        XCTAssertEqual(ilitek.maxContacts, 10)
        XCTAssertEqual(ilitek.reportedSizeMM?.width ?? 0, 476.1, accuracy: 0.1)
        XCTAssertEqual(ilitek.reportedSizeMM?.height ?? 0, 267.8, accuracy: 0.1)
        XCTAssertTrue(ilitek.hasMouseInterface)
        XCTAssertFalse(ilitek.reportsPalms, "no contact size or confidence in its descriptor")
        XCTAssertNotEqual(strip.handle, ilitek.handle)

        XCTAssertEqual(system.calls, [.startMatching], "connected means released: nothing is opened")
        system.runLater()
        XCTAssertEqual(delegate.events.count, 2, "each touchscreen is announced once")
    }

    func testStartingTwiceAnnouncesOnce() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        source.start()
        system.runLater()
        XCTAssertEqual(delegate.connected.count, 2)
        XCTAssertEqual(system.calls, [.startMatching])
    }

    func testATouchscreenWithAnUnreadableDescriptorIsStillAnnounced() throws {
        var touch = try Desk.ilitekTouch()
        touch.descriptor = nil
        let (_, delegate, source) = make([touch])
        source.start()
        let ilitek = try XCTUnwrap(delegate.connected.first)
        XCTAssertEqual(ilitek.maxContacts, 1, "1 when unknown")
        XCTAssertNil(ilitek.reportedSizeMM)
        XCTAssertFalse(ilitek.reportsPalms, "false when unknown")
        XCTAssertFalse(ilitek.hasMouseInterface)
    }

    /// Review Focus 6: a mouse that is not the sibling of a touchscreen is never opened, whatever
    /// happens to the touchscreens.
    func testAStrayMouseIsNeverOpened() throws {
        let locationless = try Desk.otherMouse(id: 32, at: 0)
        let (system, delegate, source) = make(try Desk.all() + [locationless])
        source.start()
        for touchscreen in delegate.connected { source.setState(.taken, for: touchscreen.handle) }
        source.refresh()
        for touchscreen in delegate.connected { source.setState(.released, for: touchscreen.handle) }
        source.stop()
        let stray = system.calls.filter { [Desk.otherMouseID, 32].contains($0.interfaceID) }
        XCTAssertEqual(stray, [], "the other mice were never opened, written to or listened to")
        XCTAssertEqual(delegate.connected.count, 2, "a mouse alone is not a touchscreen")
    }

    // MARK: - Taking

    func testTakingFollowsTheSequenceTheSurveyProved() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        let strip = try handle(delegate, vendorID: Panels.wchVendorID)
        system.clearCalls()
        delegate.clear()

        source.setState(.taken, for: strip)

        XCTAssertEqual(system.calls, [
            .open(Desk.wchTouchID, exclusive: true), .open(Desk.wchMouseID, exclusive: true),
            .readFeatureReport(Desk.wchTouchID, reportID: 0x0A, length: 2),
            .hasInputMode(Desk.wchTouchID), .writeInputMode(Desk.wchTouchID, 2),
            .startReports(Desk.wchTouchID, bufferSize: 80), .startReports(Desk.wchMouseID, bufferSize: 80),
        ])
        XCTAssertEqual(delegate.changes.map(\.status), [taken], "one change: taken, switched, held")
        XCTAssertEqual(delegate.changes.first?.handle, strip)
    }

    func testAPanelWithoutInputModeIsLeftAsItIs() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        let ilitek = try handle(delegate, vendorID: Panels.ilitekVendorID)
        system.clearCalls()

        source.setState(.taken, for: ilitek)
        XCTAssertEqual(system.calls, [
            .open(Desk.ilitekTouchID, exclusive: true), .open(Desk.ilitekMouseID, exclusive: true),
            .readFeatureReport(Desk.ilitekTouchID, reportID: 0x06, length: 258),
            .hasInputMode(Desk.ilitekTouchID),
            .startReports(Desk.ilitekTouchID, bufferSize: 80), .startReports(Desk.ilitekMouseID, bufferSize: 80),
        ])
        XCTAssertEqual(delegate.changes.last?.status.inputMode, .noInputModeSetting)

        system.clearCalls()
        source.setState(.released, for: ilitek)
        XCTAssertEqual(system.calls, [
            .stopReports(Desk.ilitekTouchID), .stopReports(Desk.ilitekMouseID),
            .close(Desk.ilitekTouchID, exclusive: true), .close(Desk.ilitekMouseID, exclusive: true),
        ], "nothing is written to a panel that was never switched")
    }

    /// A panel can apply the write and still answer with an error. A taking that sent 2 writes 0
    /// on release, whatever the answer was.
    func testARefusedSwitchIsSaidAndStillUndone() throws {
        let (system, delegate, source) = make(try Desk.all())
        system.writeResult = FakeHIDSystem.refused
        source.start()
        let strip = try handle(delegate, vendorID: Panels.wchVendorID)
        source.setState(.taken, for: strip)
        XCTAssertEqual(delegate.changes.last?.status.inputMode, .switchRefused)

        system.clearCalls()
        source.setState(.released, for: strip)
        XCTAssertEqual(system.calls.filter { if case .writeInputMode = $0 { return true } else { return false } },
                       [.writeInputMode(Desk.wchTouchID, 0)], "2 was sent, so 0 is written back")
        XCTAssertEqual(system.calls.last, .close(Desk.wchMouseID, exclusive: true), "written before the interfaces are closed")
    }

    func testASeizeThatFailsFallsBackToShared() throws {
        let (system, delegate, source) = make(try Desk.all())
        system.openResults[Desk.wchMouseID] = (exclusive: FakeHIDSystem.refused, shared: kIOReturnSuccess)
        source.start()
        let strip = try handle(delegate, vendorID: Panels.wchVendorID)
        system.clearCalls()

        source.setState(.taken, for: strip)
        XCTAssertEqual(Array(system.calls.prefix(3)), [
            .open(Desk.wchTouchID, exclusive: true), .open(Desk.wchMouseID, exclusive: true), .open(Desk.wchMouseID, exclusive: false),
        ])
        XCTAssertTrue(system.isListening(to: Desk.wchMouseID), "the shared mouse interface is still read")
        XCTAssertEqual(delegate.changes.last?.status,
                       DeviceStatus(state: .taken, inputMode: .switchedToMultiTouch, touchOrigin: .undetermined, exclusive: .failed))

        system.clearCalls()
        source.setState(.released, for: strip)
        XCTAssertTrue(system.calls.contains(.close(Desk.wchMouseID, exclusive: false)))
        XCTAssertTrue(system.calls.contains(.close(Desk.wchTouchID, exclusive: true)))
    }

    func testATouchscreenThatCannotBeOpenedIsUnreadable() throws {
        let (system, delegate, source) = make([try Desk.ilitekTouch()])
        system.openResults[Desk.ilitekTouchID] = (exclusive: FakeHIDSystem.notPermitted, shared: FakeHIDSystem.notPermitted)
        source.start()
        let ilitek = try handle(delegate, vendorID: Panels.ilitekVendorID)
        system.clearCalls()

        source.setState(.taken, for: ilitek)
        XCTAssertEqual(system.calls, [.open(Desk.ilitekTouchID, exclusive: true), .open(Desk.ilitekTouchID, exclusive: false)])
        XCTAssertEqual(delegate.changes.last?.status,
                       DeviceStatus(state: .taken, inputMode: .notSwitched, touchOrigin: .unreadable, exclusive: .failed))

        system.clearCalls()
        source.setState(.released, for: ilitek)
        XCTAssertEqual(system.calls, [], "nothing was opened, so nothing is closed")
        XCTAssertEqual(delegate.changes.last?.status, DeviceStatus())
    }

    func testATouchInterfaceThatCannotBeOpenedLeavesTheMouse() throws {
        let (system, delegate, source) = make([try Desk.wchTouch(), try Desk.wchMouse()])
        system.openResults[Desk.wchTouchID] = (exclusive: FakeHIDSystem.notPermitted, shared: FakeHIDSystem.notPermitted)
        source.start()
        let strip = try handle(delegate, vendorID: Panels.wchVendorID)
        source.setState(.taken, for: strip)
        XCTAssertFalse(system.calls.contains(.hasInputMode(Desk.wchTouchID)), "no switch on an interface that isn't open")
        XCTAssertEqual(delegate.changes.last?.status,
                       DeviceStatus(state: .taken, inputMode: .notSwitched, touchOrigin: .undetermined, exclusive: .failed))
        system.send(Panels.wchMouse(buttons: 1, x: 0.5, y: 0.5), on: Desk.wchMouseID, at: 1.0)
        XCTAssertEqual(delegate.changes.last?.status.touchOrigin, .mouseInterface)
        XCTAssertEqual(delegate.frames.count, 1)
    }

    func testAskingForTheStateItHasDoesNothing() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        let strip = try handle(delegate, vendorID: Panels.wchVendorID)
        system.clearCalls()
        delegate.clear()

        source.setState(.released, for: strip)
        XCTAssertEqual(system.calls, [])
        XCTAssertEqual(delegate.events, [])

        source.setState(.taken, for: strip)
        let afterTake = system.calls
        source.setState(.taken, for: strip)
        XCTAssertEqual(system.calls, afterTake)
        XCTAssertEqual(delegate.changes.count, 1)
    }

    func testAnUnknownHandleIsIgnored() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        system.clearCalls()
        delegate.clear()
        source.setState(.taken, for: DeviceHandle(rawValue: 999))
        XCTAssertEqual(system.calls, [])
        XCTAssertEqual(delegate.events, [])
    }

    func testANewTouchscreenCanBeTakenFromItsAnnouncement() throws {
        let (system, delegate, source) = make(try Desk.all())
        delegate.onConnected = { source.setState(.taken, for: $0.handle) }
        source.start()
        XCTAssertTrue(system.isListening(to: Desk.wchTouchID))
        XCTAssertTrue(system.isListening(to: Desk.ilitekTouchID))
        XCTAssertEqual(delegate.changes.map(\.status.state), [.taken, .taken])
    }

    // MARK: - Reading the feature reports that wake a panel

    /// The ILITEK starts every plug-in and boot emulating a mouse. It becomes a touchscreen once a
    /// host reads its feature report 0x06 (Contact Count Maximum and the 256-byte certification
    /// blob), as Windows and Linux do when it enumerates. Every take reads it once: with the
    /// touchscreen interface open, before anything is listened to.
    func testTakingTheILITEKReadsItsCertificationBlobOnceBeforeListening() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        let ilitek = try handle(delegate, vendorID: Panels.ilitekVendorID)
        system.clearCalls()

        source.setState(.taken, for: ilitek)

        let read = FakeHIDSystem.Call.readFeatureReport(Desk.ilitekTouchID, reportID: 0x06, length: 258)
        XCTAssertEqual(system.featureReads, [read], "once, 258 bytes, from the touchscreen interface")
        let readAt = try XCTUnwrap(system.calls.firstIndex(of: read))
        let openedAt = try XCTUnwrap(system.calls.firstIndex(of: .open(Desk.ilitekTouchID, exclusive: true)))
        let listeningAt = try XCTUnwrap(system.calls.firstIndex { if case .startReports = $0 { return true } else { return false } })
        XCTAssertLessThan(openedAt, readAt, "read with the touchscreen interface open")
        XCTAssertLessThan(readAt, listeningAt, "read before any report is listened to")
    }

    /// Linux's order: GET the feature reports, then SET Input Mode.
    func testTakingTheStripReadsItsContactCountMaximumBeforeTheInputModeWrite() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        let strip = try handle(delegate, vendorID: Panels.wchVendorID)
        system.clearCalls()

        source.setState(.taken, for: strip)

        let read = FakeHIDSystem.Call.readFeatureReport(Desk.wchTouchID, reportID: 0x0A, length: 2)
        XCTAssertEqual(system.featureReads, [read], "0x0A only: 0x21 holds Input Mode, which is written, never read")
        let readAt = try XCTUnwrap(system.calls.firstIndex(of: read))
        let writeAt = try XCTUnwrap(system.calls.firstIndex(of: .writeInputMode(Desk.wchTouchID, 2)))
        let openedAt = try XCTUnwrap(system.calls.firstIndex(of: .open(Desk.wchTouchID, exclusive: true)))
        XCTAssertLessThan(openedAt, readAt, "read with the touchscreen interface open")
        XCTAssertLessThan(readAt, writeAt, "GET, then SET")
    }

    /// A release puts the panel back as if Tactile weren't there; the next take wakes it again.
    func testEveryTakeReadsAgain() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        let ilitek = try handle(delegate, vendorID: Panels.ilitekVendorID)
        let strip = try handle(delegate, vendorID: Panels.wchVendorID)
        system.clearCalls()

        for _ in 0..<2 {
            source.setState(.taken, for: ilitek)
            source.setState(.taken, for: strip)
            source.setState(.released, for: ilitek)
            source.setState(.released, for: strip)
        }
        source.setState(.taken, for: ilitek)

        let ilitekRead = FakeHIDSystem.Call.readFeatureReport(Desk.ilitekTouchID, reportID: 0x06, length: 258)
        let stripRead = FakeHIDSystem.Call.readFeatureReport(Desk.wchTouchID, reportID: 0x0A, length: 2)
        XCTAssertEqual(system.featureReads, [ilitekRead, stripRead, ilitekRead, stripRead, ilitekRead])
        // Each read follows its own take's open.
        var opened: Set<HIDInterfaceID> = []
        for call in system.calls {
            switch call {
            case .open(let id, _): opened.insert(id)
            case .close(let id, _): opened.remove(id)
            case .readFeatureReport(let id, _, _): XCTAssertTrue(opened.contains(id), "read while open: \(system.calls)")
            default: break
            }
        }
    }

    /// Released means as if Tactile weren't there: nothing is read.
    func testNothingIsReadWhileReleased() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        system.runLater()
        let strip = try handle(delegate, vendorID: Panels.wchVendorID)
        XCTAssertEqual(system.featureReads, [], "connected means released")

        source.setState(.taken, for: strip)
        system.clearCalls()
        source.setState(.released, for: strip)
        source.refresh()
        system.disconnect(Desk.wchMouseID)
        system.connect(try Desk.wchMouse())
        system.runLater()
        source.stop()
        XCTAssertEqual(system.featureReads, [], "not on release, refresh, a sibling's arrival or stop: \(system.calls)")
    }

    /// Only the touchscreen interface is read, even when the mouse sibling declares the same report.
    func testOnlyTheTouchscreenInterfaceIsRead() throws {
        let contactCountMaximum: [UInt8] = [
            0x05, 0x01, 0x09, 0x02, 0xA1, 0x01, 0x85, 0x0B,  // a second Mouse collection, report 0x0B
            0x05, 0x0D, 0x09, 0x55, 0x25, 0x0A, 0x75, 0x08, 0x95, 0x01, 0xB1, 0x02, 0xC0,  // Contact Count Maximum
        ]
        let mouse = interface(Desk.wchMouseID, at: wchLocation, try Panels.descriptor(Panels.wch(), "mouse") + contactCountMaximum,
                              usages: Panels.wchMouseUsages, vendorID: Panels.wchVendorID, productID: Panels.wchProductID,
                              serial: "TEST-SERIAL-0001", product: "TouchScreen", maxInputReportSize: 7)
        let (system, delegate, source) = make([try Desk.wchTouch(), mouse])
        source.start()
        let strip = try XCTUnwrap(delegate.connected.first)
        XCTAssertTrue(strip.hasMouseInterface, "it is still the strip's mouse sibling")
        system.clearCalls()

        source.setState(.taken, for: strip.handle)
        XCTAssertTrue(system.calls.contains(.open(Desk.wchMouseID, exclusive: true)))
        XCTAssertEqual(system.featureReads, [.readFeatureReport(Desk.wchTouchID, reportID: 0x0A, length: 2)])
    }

    /// A read the panel refuses is logged, and the take goes on as it would have.
    func testAFailedReadDoesNotStopTheTake() throws {
        let (system, delegate, source) = make(try Desk.all())
        system.readResult = IOReturn(bitPattern: 0xE000_02ED)  // kIOReturnNotResponding
        source.start()
        let ilitek = try handle(delegate, vendorID: Panels.ilitekVendorID)
        let strip = try handle(delegate, vendorID: Panels.wchVendorID)

        source.setState(.taken, for: strip)
        XCTAssertTrue(system.calls.contains(.writeInputMode(Desk.wchTouchID, 2)), "Input Mode is still written")
        XCTAssertEqual(delegate.changes.last?.status, taken)

        source.setState(.taken, for: ilitek)
        XCTAssertEqual(system.featureReads.count, 2, "both were tried")
        XCTAssertEqual(delegate.changes.last?.status,
                       DeviceStatus(state: .taken, inputMode: .noInputModeSetting, touchOrigin: .undetermined, exclusive: .held))
        XCTAssertTrue(system.isListening(to: Desk.ilitekTouchID))
        XCTAssertTrue(system.isListening(to: Desk.ilitekMouseID))
        delegate.clear()
        let take = try Panels.take(Panels.ilitek(), 1)
        for report in take.reports { system.send(report.bytes, on: Desk.ilitekTouchID, at: report.hostTime) }
        XCTAssertEqual(delegate.changes.map(\.status.touchOrigin), [.touchInterface])
        XCTAssertFalse(delegate.frames.isEmpty, "its touches still come through")
    }

    /// A touchscreen that declares neither report is taken, refreshed and released exactly as 0.6.1
    /// did it, whether its descriptor has no such feature or can't be read at all.
    func testATouchscreenWithNoSuchReportMakesTheCallsOf061() throws {
        let (system, delegate, source) = make([Desk.wchTouch(descriptor: Panels.oneFingerTouchscreen), try Desk.wchMouse()])
        source.start()
        let strip = try handle(delegate, vendorID: Panels.wchVendorID)
        system.clearCalls()
        source.setState(.taken, for: strip)
        source.refresh()
        source.setState(.released, for: strip)
        XCTAssertEqual(system.calls, [
            .open(Desk.wchTouchID, exclusive: true), .open(Desk.wchMouseID, exclusive: true),
            .hasInputMode(Desk.wchTouchID), .writeInputMode(Desk.wchTouchID, 2),
            .startReports(Desk.wchTouchID, bufferSize: 80), .startReports(Desk.wchMouseID, bufferSize: 80),
            .writeInputMode(Desk.wchTouchID, 2),
            .stopReports(Desk.wchTouchID), .stopReports(Desk.wchMouseID), .writeInputMode(Desk.wchTouchID, 0),
            .close(Desk.wchTouchID, exclusive: true), .close(Desk.wchMouseID, exclusive: true),
        ], "take, refresh and release, as in 0.6.1")

        var unreadable = try Desk.ilitekTouch()
        unreadable.descriptor = nil
        let (other, otherDelegate, otherSource) = make([unreadable, try Desk.ilitekMouse()])
        otherSource.start()
        let ilitek = try handle(otherDelegate, vendorID: Panels.ilitekVendorID)
        other.clearCalls()
        otherSource.setState(.taken, for: ilitek)
        otherSource.refresh()
        XCTAssertEqual(other.calls, [
            .open(Desk.ilitekTouchID, exclusive: true), .open(Desk.ilitekMouseID, exclusive: true),
            .hasInputMode(Desk.ilitekTouchID),
            .startReports(Desk.ilitekTouchID, bufferSize: 80), .startReports(Desk.ilitekMouseID, bufferSize: 80),
        ], "an unreadable descriptor names no report to read")
    }

    /// Two reports worth reading: both are read, in descriptor order (0x03 before 0x02), after the
    /// opens and before the Input Mode check and write.
    func testATouchscreenWithTwoSuchReportsReadsBothInDescriptorOrder() throws {
        let (system, delegate, source) = make([Desk.wchTouch(descriptor: Panels.twoFeatureReportsTouchscreen), try Desk.wchMouse()])
        source.start()
        system.clearCalls()
        source.setState(.taken, for: try handle(delegate, vendorID: Panels.wchVendorID))
        XCTAssertEqual(system.calls, [
            .open(Desk.wchTouchID, exclusive: true), .open(Desk.wchMouseID, exclusive: true),
            .readFeatureReport(Desk.wchTouchID, reportID: 0x03, length: 2),
            .readFeatureReport(Desk.wchTouchID, reportID: 0x02, length: 257),
            .hasInputMode(Desk.wchTouchID), .writeInputMode(Desk.wchTouchID, 2),
            .startReports(Desk.wchTouchID, bufferSize: 80), .startReports(Desk.wchMouseID, bufferSize: 80),
        ])
    }

    // MARK: - A read that times out

    /// A panel that never answers would hold Tactile for the HID request timeout (5 s) on every
    /// take. Once a read times out, this connection's feature reports aren't read again, on a
    /// later take or a refresh. A new connection (plugged in again, or Tactile started again)
    /// reads again.
    func testAReadThatTimesOutIsNotTriedAgainOnThisConnection() throws {
        let (system, delegate, source) = make(try Desk.all())
        system.readResult = IOResult.timeout
        system.readSeconds = 5
        source.start()
        let ilitek = try handle(delegate, vendorID: Panels.ilitekVendorID)

        source.setState(.taken, for: ilitek)
        XCTAssertEqual(system.featureReads, [.readFeatureReport(Desk.ilitekTouchID, reportID: 0x06, length: 258)])
        XCTAssertEqual(delegate.changes.last?.status,
                       DeviceStatus(state: .taken, inputMode: .noInputModeSetting, touchOrigin: .undetermined, exclusive: .held),
                       "the take goes on")
        XCTAssertTrue(system.isListening(to: Desk.ilitekTouchID))

        source.setState(.released, for: ilitek)
        source.setState(.taken, for: ilitek)
        source.refresh()
        XCTAssertEqual(system.featureReads.count, 1, "not tried again on this connection: \(system.featureReads)")
        XCTAssertEqual(delegate.changes.last?.status.state, .taken)
        XCTAssertTrue(system.isListening(to: Desk.ilitekTouchID))

        // The strip is another connection: it is still read.
        source.setState(.taken, for: try handle(delegate, vendorID: Panels.wchVendorID))
        XCTAssertEqual(system.featureReads.last, .readFeatureReport(Desk.wchTouchID, reportID: 0x0A, length: 2))

        // Plugged in again: a new connection, read again.
        system.disconnect(Desk.ilitekMouseID)
        system.disconnect(Desk.ilitekTouchID)
        system.runLater()
        system.connect(try Desk.ilitekTouch(id: 24))
        system.connect(try Desk.ilitekMouse(id: 25))
        system.runLater()
        system.clearCalls()
        source.setState(.taken, for: try handle(delegate, vendorID: Panels.ilitekVendorID))
        XCTAssertEqual(system.featureReads, [.readFeatureReport(24, reportID: 0x06, length: 258)])

        // Tactile started again: read again.
        source.stop()
        source.start()
        system.clearCalls()
        source.setState(.taken, for: try handle(delegate, vendorID: Panels.ilitekVendorID))
        XCTAssertEqual(system.featureReads, [.readFeatureReport(24, reportID: 0x06, length: 258)])
    }

    /// IOKit's timeout code counts, and so does a read that took 4 s or more, whatever it
    /// returned. A read that fails quickly is tried again on the next take.
    func testWhatCountsAsATimeout() throws {
        let notResponding = IOReturn(bitPattern: 0xE000_02ED)
        let cases: [(name: String, result: IOReturn, seconds: TimeInterval, triedAgain: Bool)] = [
            ("the timeout code, quickly", IOResult.timeout, 0.2, false),
            ("answered after 4 s", kIOReturnSuccess, 4.0, false),
            ("not responding after 4.5 s", notResponding, 4.5, false),
            ("answered after 3.9 s", kIOReturnSuccess, 3.9, true),
            ("not responding, quickly", notResponding, 0.2, true),
        ]
        for c in cases {
            let (system, delegate, source) = make(try Desk.all())
            system.readResult = c.result
            system.readSeconds = c.seconds
            source.start()
            let ilitek = try handle(delegate, vendorID: Panels.ilitekVendorID)
            source.setState(.taken, for: ilitek)
            source.setState(.released, for: ilitek)
            source.setState(.taken, for: ilitek)
            XCTAssertEqual(system.featureReads.count, c.triedAgain ? 2 : 1, c.name)
            XCTAssertEqual(delegate.changes.last?.status.state, .taken, c.name)
            source.stop()
        }
    }

    /// A read that times out ends that take's reads too: the next would most likely wait as long.
    func testATimeoutEndsTheReadsOfThatTake() throws {
        let (system, delegate, source) = make([Desk.wchTouch(descriptor: Panels.twoFeatureReportsTouchscreen), try Desk.wchMouse()])
        system.readResult = IOResult.timeout
        system.readSeconds = 5
        source.start()
        system.clearCalls()
        source.setState(.taken, for: try handle(delegate, vendorID: Panels.wchVendorID))
        XCTAssertEqual(system.featureReads, [.readFeatureReport(Desk.wchTouchID, reportID: 0x03, length: 2)])
        XCTAssertTrue(system.calls.contains(.writeInputMode(Desk.wchTouchID, 2)), "the take goes on")
    }

    // MARK: - The read's log line

    /// The line gives the length asked for and the length that came back. A read that failed
    /// or timed out is an error, which the unified log keeps after a reboot; one that worked is
    /// info. The line says whether a take or a refresh goes on.
    func testTheReadsLogLine() {
        let blob = FeatureReportToRead(reportID: 0x06, length: 258, contents: [.contactCountMaximum, .certificationBlob])
        func line(_ result: IOReturn, _ length: Int, _ seconds: TimeInterval,
                  _ occasion: FeatureReadOccasion = .take) -> (text: String, isError: Bool) {
            HIDTouchscreenSource.featureReadLog(FeatureReportRead(result: result, length: length, seconds: seconds),
                                                of: blob, by: DeviceHandle(rawValue: 2), during: occasion)
        }
        let notResponding = IOReturn(bitPattern: 0xE000_02ED)
        let read = "device-2: read feature report 0x06 (Contact Count Maximum, certification blob): 258 bytes asked"
        let never = "this touchscreen's feature reports won't be read again until it is plugged in again or Tactile restarts"

        let worked = line(kIOReturnSuccess, 258, 0.004)
        XCTAssertEqual(worked.text, read + ", 258 returned in 0.004 s (IOReturn 0x00000000)")
        XCTAssertFalse(worked.isError, "a read that worked is info")
        XCTAssertEqual(line(kIOReturnSuccess, 2, 0.004).text, read + ", 2 returned in 0.004 s (IOReturn 0x00000000)",
                       "the length that came back")

        let failed = line(notResponding, 0, 0.012)
        XCTAssertEqual(failed.text, read + ", none returned in 0.012 s (IOReturn 0xe00002ed); the read failed, and the take goes on")
        XCTAssertTrue(failed.isError, "a failed read is an error")
        XCTAssertEqual(line(notResponding, 0, 0.012, .refresh).text,
                       read + ", none returned in 0.012 s (IOReturn 0xe00002ed); the read failed, and the refresh goes on")

        let timedOut = line(IOResult.timeout, 0, 5.001)
        XCTAssertEqual(timedOut.text, read + ", none returned in 5.001 s (IOReturn 0xe00002d6); it timed out, so " + never
                       + ", and the take goes on")
        XCTAssertTrue(timedOut.isError)
        let slow = line(kIOReturnSuccess, 258, 4.2, .refresh)
        XCTAssertEqual(slow.text, read + ", 258 returned in 4.200 s (IOReturn 0x00000000); it took 4 s or more, so " + never
                       + ", and the refresh goes on")
        XCTAssertTrue(slow.isError)
    }

    // MARK: - Releasing

    func testReleasingWritesMouseEmulationAndCloses() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        let strip = try handle(delegate, vendorID: Panels.wchVendorID)
        source.setState(.taken, for: strip)
        system.clearCalls()
        delegate.clear()

        source.setState(.released, for: strip)
        XCTAssertEqual(system.calls, [
            .stopReports(Desk.wchTouchID), .stopReports(Desk.wchMouseID),
            .writeInputMode(Desk.wchTouchID, 0),
            .close(Desk.wchTouchID, exclusive: true), .close(Desk.wchMouseID, exclusive: true),
        ])
        XCTAssertEqual(delegate.changes.map(\.status), [DeviceStatus()], "released, not held, not switched, undetermined")
    }

    func testNothingIsReadFromAReleasedTouchscreen() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        let strip = try handle(delegate, vendorID: Panels.wchVendorID)
        XCTAssertFalse(system.isListening(to: Desk.wchMouseID), "a touchscreen that has just connected is not read")

        system.keepsDeliveringAfterStop = true
        source.setState(.taken, for: strip)
        source.setState(.released, for: strip)
        delegate.clear()
        system.send(Panels.wchMouse(buttons: 1, x: 0.5, y: 0.5), on: Desk.wchMouseID, at: 1.0)
        XCTAssertEqual(delegate.events, [], "a report already on its way when it was released is dropped")
    }

    func testATakeStartsTheReaderAfresh() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        let strip = try handle(delegate, vendorID: Panels.wchVendorID)
        source.setState(.taken, for: strip)
        system.send(Panels.wchMouse(buttons: 1, x: 0.5, y: 0.5), on: Desk.wchMouseID, at: 1.00)
        system.send(Panels.wchMouse(buttons: 0, x: 0.5, y: 0.5), on: Desk.wchMouseID, at: 1.10)
        source.setState(.released, for: strip)
        source.setState(.taken, for: strip)
        XCTAssertEqual(delegate.changes.last?.status.touchOrigin, .undetermined, "the origin is decided afresh")
        delegate.clear()
        system.send(Panels.wchMouse(buttons: 1, x: 0.7, y: 0.5), on: Desk.wchMouseID, at: 1.11)
        XCTAssertEqual(delegate.frames.count, 1, "the guard of the last taking doesn't refuse the first press of this one")
    }

    // MARK: - Reports

    func testReportsBecomeFramesAndTheOriginIsAnnouncedFirst() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        let strip = try handle(delegate, vendorID: Panels.wchVendorID)
        source.setState(.taken, for: strip)
        delegate.clear()

        let wch = try Panels.wch()
        let take = try Panels.take(wch, 9)  // one-finger tap
        var reader = TouchscreenReader(touch: try Panels.decoder(wch, "touchscreen"), mouse: try Panels.decoder(wch, "mouse"))
        var expected: [ContactFrame] = []
        for report in take.reports {
            system.send(report.bytes, on: Desk.wchMouseID, at: report.hostTime)
            expected += reader.add(report.bytes, from: .mouse, at: report.hostTime)
        }

        XCTAssertFalse(expected.isEmpty)
        XCTAssertEqual(delegate.frames, expected)
        guard case .changed(let change)? = delegate.events.first else { return XCTFail("the first event is not a change") }
        XCTAssertEqual(change.status.touchOrigin, .mouseInterface, "the origin is known before the first frame arrives")
        XCTAssertEqual(delegate.changes.count, 1, "the origin changed once")
        XCTAssertTrue(delegate.events.allSatisfy {
            if case .frame(let h, _) = $0 { return h == strip } else { return true }
        })
    }

    func testTheILITEKsTouchesReachTheDelegate() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        let ilitek = try handle(delegate, vendorID: Panels.ilitekVendorID)
        source.setState(.taken, for: ilitek)
        delegate.clear()
        let take = try Panels.take(Panels.ilitek(), 3)  // as many fingers as you can
        for report in take.reports { system.send(report.bytes, on: Desk.ilitekTouchID, at: report.hostTime) }
        XCTAssertEqual(delegate.changes.map(\.status.touchOrigin), [.touchInterface])
        XCTAssertEqual(delegate.frames.map(\.contacts.count).max(), 10)
        XCTAssertEqual(delegate.frames.last?.contacts, [])
    }

    /// The app may release a touchscreen while it is being told about it. Nothing from that
    /// report reaches it afterwards.
    func testAChangeTheAppAnswersByReleasingEndsTheReport() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        let ilitek = try handle(delegate, vendorID: Panels.ilitekVendorID)
        source.setState(.taken, for: ilitek)
        delegate.clear()
        delegate.onChanged = { change in
            if change.status.touchOrigin == .touchInterface { source.setState(.released, for: change.handle) }
        }
        let first = try XCTUnwrap(Panels.take(Panels.ilitek(), 1).reports.first)
        system.send(first.bytes, on: Desk.ilitekTouchID, at: first.hostTime)
        XCTAssertEqual(delegate.changes.map(\.status.state), [.taken, .released])
        XCTAssertEqual(delegate.frames, [], "the frame of a report whose touchscreen was released meanwhile is dropped")
    }

    func testAFrameTheAppAnswersByReleasingIsTheLast() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        let ilitek = try handle(delegate, vendorID: Panels.ilitekVendorID)
        source.setState(.taken, for: ilitek)
        system.send(Panels.ilitekMouse(buttons: 1, x: 0.5, y: 0.5), on: Desk.ilitekMouseID, at: 1.0)
        XCTAssertEqual(delegate.frames.count, 1)
        delegate.clear()
        delegate.onFrame = { handle, frame in
            if frame.contacts.isEmpty { source.setState(.released, for: handle) }
        }
        let touch = try XCTUnwrap(Panels.take(Panels.ilitek(), 1).reports.first)
        system.send(touch.bytes, on: Desk.ilitekTouchID, at: 1.05)
        XCTAssertEqual(delegate.frames, [ContactFrame(time: 1.05, contacts: [])], "the touch frame after it is not delivered")
        XCTAssertEqual(delegate.changes.last?.status, DeviceStatus())
    }

    // MARK: - Unplugging

    func testUnpluggedMidTouchWritesNothingAndAddsNoFrame() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        let strip = try handle(delegate, vendorID: Panels.wchVendorID)
        let ilitek = try handle(delegate, vendorID: Panels.ilitekVendorID)
        source.setState(.taken, for: strip)
        system.send(Panels.wchMouse(buttons: 1, x: 0.5, y: 0.5), on: Desk.wchMouseID, at: 1.0)
        XCTAssertEqual(delegate.frames.count, 1, "a finger is down")
        system.clearCalls()
        delegate.clear()

        system.disconnect(Desk.wchMouseID)
        system.disconnect(Desk.wchTouchID)
        system.runLater()

        XCTAssertFalse(system.calls.contains { $0.touchesTheDevice }, "nothing is opened or written: \(system.calls)")
        XCTAssertEqual(delegate.frames, [], "the source synthesises no frame; the app cancels the touch")
        XCTAssertEqual(delegate.disconnections, [strip], "announced once")
        XCTAssertEqual(delegate.changes.map(\.hasMouseInterface), [false], "the mouse interface went first")

        // The other touchscreen is still there, and can be taken.
        delegate.clear()
        source.setState(.taken, for: ilitek)
        XCTAssertEqual(delegate.changes.map(\.handle), [ilitek])
        XCTAssertEqual(delegate.changes.first?.status.state, .taken)
    }

    func testUnpluggedTouchInterfaceFirst() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        let strip = try handle(delegate, vendorID: Panels.wchVendorID)
        source.setState(.taken, for: strip)
        system.clearCalls()
        delegate.clear()

        system.disconnect(Desk.wchTouchID)
        system.disconnect(Desk.wchMouseID)
        system.runLater()
        XCTAssertFalse(system.calls.contains { $0.touchesTheDevice }, "nothing is opened or written: \(system.calls)")
        XCTAssertEqual(delegate.events, [.disconnected(strip)])
        source.setState(.released, for: strip)
        XCTAssertFalse(system.calls.contains { $0.touchesTheDevice })
    }

    func testAReconnectedTouchscreenGetsANewHandle() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        let before = try handle(delegate, vendorID: Panels.wchVendorID)
        source.setState(.taken, for: before)
        system.disconnect(Desk.wchTouchID)
        system.disconnect(Desk.wchMouseID)
        system.runLater()
        delegate.clear()

        system.connect(try Desk.wchMouse(id: 14))
        system.connect(try Desk.wchTouch(id: 13))
        system.runLater()
        let after = try XCTUnwrap(delegate.connected.first)
        XCTAssertNotEqual(after.handle, before)
        XCTAssertEqual(after.status, DeviceStatus(), "a touchscreen that has just connected is released")
        XCTAssertTrue(after.hasMouseInterface)
        XCTAssertEqual(delegate.events.count, 1)
    }

    // MARK: - A mouse sibling that comes later

    /// Review Focus 6: a mouse sibling that appears after its touchscreen interface, on a
    /// touchscreen already taken, is taken over too.
    func testAMouseSiblingThatAppearsLaterIsTakenOverToo() throws {
        let (system, delegate, source) = make([try Desk.wchTouch()])
        source.start()
        let strip = try XCTUnwrap(delegate.connected.first)
        XCTAssertFalse(strip.hasMouseInterface)
        source.setState(.taken, for: strip.handle)
        XCTAssertFalse(system.calls.contains { $0.interfaceID == Desk.wchMouseID })
        system.clearCalls()
        delegate.clear()

        system.connect(try Desk.wchMouse())
        system.runLater()

        XCTAssertEqual(system.calls, [.open(Desk.wchMouseID, exclusive: true), .startReports(Desk.wchMouseID, bufferSize: 80)])
        XCTAssertEqual(delegate.changes.count, 1)
        XCTAssertEqual(delegate.changes.first?.hasMouseInterface, true)
        XCTAssertEqual(delegate.changes.first?.status, taken)

        system.send(Panels.wchMouse(buttons: 1, x: 0.5, y: 0.5), on: Desk.wchMouseID, at: 2.0)
        XCTAssertEqual(delegate.frames.count, 1, "the late sibling is read")

        system.clearCalls()
        source.setState(.released, for: strip.handle)
        XCTAssertTrue(system.calls.contains(.close(Desk.wchMouseID, exclusive: true)))
    }

    func testALateMouseSiblingOfAReleasedTouchscreenIsOnlyAnnounced() throws {
        let (system, delegate, source) = make([try Desk.wchTouch()])
        source.start()
        system.clearCalls()
        delegate.clear()
        system.connect(try Desk.wchMouse())
        system.runLater()
        XCTAssertEqual(system.calls, [])
        XCTAssertEqual(delegate.changes.map(\.hasMouseInterface), [true])
        XCTAssertEqual(delegate.changes.first?.status, DeviceStatus())
    }

    func testAMouseThatArrivesFirstWaitsForItsTouchscreen() throws {
        let (system, delegate, source) = make([])
        source.start()
        system.connect(try Desk.wchMouse())
        system.runLater()
        XCTAssertEqual(delegate.events, [])
        system.connect(try Desk.wchTouch())
        system.runLater()
        XCTAssertEqual(delegate.connected.count, 1)
        XCTAssertEqual(delegate.connected.first?.hasMouseInterface, true)
        XCTAssertEqual(system.calls, [.startMatching])
    }

    func testInterfacesArrivingTogetherAreAnnouncedTogether() throws {
        let (system, delegate, source) = make([])
        source.start()
        system.connect(try Desk.wchTouch())
        system.connect(try Desk.wchMouse())
        XCTAssertEqual(delegate.events, [], "announced once the interfaces arriving now have all arrived")
        system.runLater()
        XCTAssertEqual(delegate.events.count, 1)
        XCTAssertEqual(delegate.connected.first?.hasMouseInterface, true)
    }

    func testOtherMiceArrivingLaterAreNotSiblings() throws {
        let (system, delegate, source) = make([try Desk.ilitekTouch(), try Desk.ilitekMouse()])
        source.start()
        let ilitek = try handle(delegate, vendorID: Panels.ilitekVendorID)
        source.setState(.taken, for: ilitek)
        system.clearCalls()
        delegate.clear()

        system.connect(try Desk.otherMouse())
        system.connect(try Desk.ilitekMouse(id: 23))  // a second mouse at its location: it already has its sibling
        system.runLater()
        XCTAssertEqual(system.calls, [])
        XCTAssertEqual(delegate.events, [])
    }

    func testALocationlessTouchscreenHasNoSibling() throws {
        var touch = try Desk.ilitekTouch()
        touch.locationID = 0
        let mouse = try Desk.ilitekMouse(at: 0)
        let (system, delegate, source) = make([touch, mouse])
        source.start()
        let ilitek = try XCTUnwrap(delegate.connected.first)
        XCTAssertFalse(ilitek.hasMouseInterface)
        source.setState(.taken, for: ilitek.handle)
        XCTAssertFalse(system.calls.contains { $0.interfaceID == Desk.ilitekMouseID })
    }

    // MARK: - More than one touchscreen interface

    func testTheTouchscreenInterfaceWithMoreSlotsIsRead() throws {
        let one = interface(41, at: wchLocation, Panels.oneFingerTouchscreen, listsTouchScreen: true,
                            vendorID: Panels.wchVendorID, productID: Panels.wchProductID, product: "TouchScreen")
        let (system, delegate, source) = make([one, try Desk.wchTouch(), try Desk.wchMouse()])
        source.start()
        XCTAssertEqual(delegate.connected.count, 1)
        let strip = try XCTUnwrap(delegate.connected.first)
        XCTAssertEqual(strip.maxContacts, 10)
        source.setState(.taken, for: strip.handle)
        XCTAssertFalse(system.calls.contains { $0.interfaceID == 41 }, "the other touchscreen interface is left alone")

        // Another touchscreen interface arriving later at the same location is left alone too.
        system.clearCalls()
        delegate.clear()
        system.connect(interface(42, at: wchLocation, try Panels.descriptor(Panels.wch(), "touchscreen"), listsTouchScreen: true))
        system.runLater()
        XCTAssertEqual(system.calls, [])
        XCTAssertEqual(delegate.events, [])
    }

    // MARK: - Refresh and stop

    func testRefreshSwitchesEveryTakenTouchscreenAgain() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        let strip = try handle(delegate, vendorID: Panels.wchVendorID)
        let ilitek = try handle(delegate, vendorID: Panels.ilitekVendorID)
        source.setState(.taken, for: strip)
        source.setState(.taken, for: ilitek)
        system.clearCalls()
        delegate.clear()

        source.refresh()
        XCTAssertEqual(system.calls, [
            .readFeatureReport(Desk.wchTouchID, reportID: 0x0A, length: 2), .writeInputMode(Desk.wchTouchID, 2),
            .readFeatureReport(Desk.ilitekTouchID, reportID: 0x06, length: 258),
        ])
        XCTAssertEqual(delegate.events, [], "nothing changed")

        system.writeResult = FakeHIDSystem.refused
        source.refresh()
        XCTAssertEqual(delegate.changes.map(\.status.inputMode), [.switchRefused])

        system.clearCalls()
        source.setState(.released, for: strip)
        XCTAssertTrue(system.calls.contains(.writeInputMode(Desk.wchTouchID, 0)), "it was switched during this taking")

        system.clearCalls()
        source.refresh()
        XCTAssertEqual(system.calls, [.readFeatureReport(Desk.ilitekTouchID, reportID: 0x06, length: 258)],
                       "a released touchscreen is left alone")
    }

    /// A refresh does what a take does to the panel, in the same order: the feature reads, then
    /// the Input Mode write where there is the setting. (The app doesn't call it: it releases
    /// every touchscreen before sleep and takes it again on wake, and that take reads.)
    func testARefreshReadsThenWritesInputMode() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        source.setState(.taken, for: try handle(delegate, vendorID: Panels.ilitekVendorID))
        source.setState(.taken, for: try handle(delegate, vendorID: Panels.wchVendorID))
        system.clearCalls()
        delegate.clear()

        source.refresh()
        source.refresh()

        let wake: [FakeHIDSystem.Call] = [
            .readFeatureReport(Desk.wchTouchID, reportID: 0x0A, length: 2), .writeInputMode(Desk.wchTouchID, 2),
            .readFeatureReport(Desk.ilitekTouchID, reportID: 0x06, length: 258),
        ]
        XCTAssertEqual(system.calls, wake + wake, "every refresh: GET, then SET; the ILITEK, which has no Input Mode, is read too")
        XCTAssertEqual(delegate.events, [], "nothing changed")
    }

    func testARefreshDoesNotReadAReleasedTouchscreen() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        let ilitek = try handle(delegate, vendorID: Panels.ilitekVendorID)
        let strip = try handle(delegate, vendorID: Panels.wchVendorID)
        source.setState(.taken, for: ilitek)
        source.setState(.taken, for: strip)
        source.setState(.released, for: ilitek)
        system.clearCalls()

        source.refresh()
        XCTAssertFalse(system.calls.contains { [Desk.ilitekTouchID, Desk.ilitekMouseID].contains($0.interfaceID) },
                       "released: \(system.calls)")
        XCTAssertEqual(system.featureReads, [.readFeatureReport(Desk.wchTouchID, reportID: 0x0A, length: 2)])

        source.setState(.released, for: strip)
        system.clearCalls()
        source.refresh()
        XCTAssertEqual(system.calls, [], "nothing is taken")
    }

    /// Taken, but its touchscreen interface could not be opened: there is nothing to read from.
    func testARefreshDoesNotReadATouchscreenInterfaceThatIsNotOpen() throws {
        let (system, delegate, source) = make([try Desk.wchTouch(), try Desk.wchMouse()])
        system.openResults[Desk.wchTouchID] = (exclusive: FakeHIDSystem.notPermitted, shared: FakeHIDSystem.notPermitted)
        source.start()
        source.setState(.taken, for: try handle(delegate, vendorID: Panels.wchVendorID))
        system.clearCalls()

        source.refresh()
        XCTAssertEqual(system.calls, [])
    }

    func testAFailedReadOnARefreshGoesOn() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        let ilitek = try handle(delegate, vendorID: Panels.ilitekVendorID)
        source.setState(.taken, for: try handle(delegate, vendorID: Panels.wchVendorID))
        source.setState(.taken, for: ilitek)
        system.readResult = IOReturn(bitPattern: 0xE000_02ED)  // kIOReturnNotResponding
        system.clearCalls()
        delegate.clear()

        source.refresh()
        XCTAssertEqual(system.calls, [
            .readFeatureReport(Desk.wchTouchID, reportID: 0x0A, length: 2), .writeInputMode(Desk.wchTouchID, 2),
            .readFeatureReport(Desk.ilitekTouchID, reportID: 0x06, length: 258),
        ], "the write still follows the failed read, and the next touchscreen is still read")
        XCTAssertEqual(delegate.events, [], "still taken, switched and held")
        XCTAssertTrue(system.isListening(to: Desk.ilitekTouchID))
        let take = try Panels.take(Panels.ilitek(), 1)
        for report in take.reports { system.send(report.bytes, on: Desk.ilitekTouchID, at: report.hostTime) }
        XCTAssertEqual(delegate.changes.map(\.status.touchOrigin), [.touchInterface])
        XCTAssertFalse(delegate.frames.isEmpty, "its touches still come through")
    }

    func testARefreshCanSwitchAPanelThatRefusedAtFirst() throws {
        let (system, delegate, source) = make(try Desk.all())
        system.writeResult = FakeHIDSystem.refused
        source.start()
        let strip = try handle(delegate, vendorID: Panels.wchVendorID)
        source.setState(.taken, for: strip)
        system.writeResult = kIOReturnSuccess
        source.refresh()
        XCTAssertEqual(delegate.changes.last?.status.inputMode, .switchedToMultiTouch)
        system.clearCalls()
        source.setState(.released, for: strip)
        XCTAssertTrue(system.calls.contains(.writeInputMode(Desk.wchTouchID, 0)))
    }

    func testStopReleasesEverythingAndForgetsIt() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        let strip = try handle(delegate, vendorID: Panels.wchVendorID)
        let ilitek = try handle(delegate, vendorID: Panels.ilitekVendorID)
        source.setState(.taken, for: strip)
        source.setState(.taken, for: ilitek)
        system.clearCalls()
        delegate.clear()
        delegate.onChanged = { source.setState(.taken, for: $0.handle) }

        source.stop()

        XCTAssertEqual(system.calls, [
            .stopReports(Desk.wchTouchID), .stopReports(Desk.wchMouseID), .writeInputMode(Desk.wchTouchID, 0),
            .close(Desk.wchTouchID, exclusive: true), .close(Desk.wchMouseID, exclusive: true),
            .stopReports(Desk.ilitekTouchID), .stopReports(Desk.ilitekMouseID),
            .close(Desk.ilitekTouchID, exclusive: true), .close(Desk.ilitekMouseID, exclusive: true),
            .stopMatching,
        ], "everything is released by the time stop returns")
        XCTAssertEqual(delegate.events, [.disconnected(strip), .disconnected(ilitek)])

        system.clearCalls()
        source.setState(.taken, for: strip)
        source.refresh()
        system.runLater()
        XCTAssertEqual(system.calls, [])

        // Started again, each touchscreen is a new connection.
        delegate.clear()
        source.start()
        XCTAssertEqual(delegate.connected.count, 2)
        XCTAssertFalse(delegate.connected.contains { [strip, ilitek].contains($0.handle) })
    }

    // MARK: - A source dropped without stop()

    func testADroppedSourceReleasesEverythingQuietly() throws {
        let system = FakeHIDSystem(connected: try Desk.all())
        system.inputModeInterfaces = [Desk.wchTouchID]
        let delegate = RecordingDelegate()
        weak var watched: HIDTouchscreenSource?
        do {
            let source = HIDTouchscreenSource(system: system)
            source.delegate = delegate
            watched = source
            source.start()
            for touchscreen in delegate.connected { source.setState(.taken, for: touchscreen.handle) }
            delegate.clear()
        }
        XCTAssertNil(watched, "nothing else keeps the source alive")
        assertEveryOpenIsClosed(system.calls)
        XCTAssertTrue(system.calls.contains(.writeInputMode(Desk.wchTouchID, 0)), "the panel it switched is put back")
        XCTAssertEqual(system.calls.last, .stopMatching)
        XCTAssertEqual(delegate.events, [], "a source going away tells nobody")
    }

    /// Dropped off the main thread, the source can't touch its own state there, so it hands the
    /// system to the main thread to stop matching: that closes what is open and unschedules
    /// everything before anything is freed.
    func testASourceDroppedOffTheMainThreadStillStopsMatching() throws {
        let system = FakeHIDSystem(connected: try Desk.all())
        let holder = SourceHolder()
        do {
            let source = HIDTouchscreenSource(system: system)
            source.start()
            holder.source = source
        }
        system.clearCalls()
        let dropped = expectation(description: "dropped off the main thread")
        DispatchQueue.global().async {
            holder.source = nil
            dropped.fulfill()
        }
        wait(for: [dropped], timeout: TestTiming.limit(5))
        let deadline = Date(timeIntervalSinceNow: TestTiming.limit(5))
        while system.calls.isEmpty, Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        XCTAssertEqual(system.calls, [.stopMatching])
    }

    func testADroppedSourceThatWasNeverStartedDoesNothing() {
        let system = FakeHIDSystem()
        do { _ = HIDTouchscreenSource(system: system) }
        XCTAssertEqual(system.calls, [])
    }

    // MARK: - The mouse sibling going on its own

    /// The app cancels the touch when a touchscreen whose touches come from its mouse interface
    /// loses that interface. The source tells it exactly once, with the origin as it was, and makes
    /// up no frame.
    func testTheMouseSiblingLeavingMidPressIsAnnouncedOnce() throws {
        let (system, delegate, source) = make([try Desk.wchTouch(), try Desk.wchMouse()])
        source.start()
        let strip = try handle(delegate, vendorID: Panels.wchVendorID)
        source.setState(.taken, for: strip)
        system.send(Panels.wchMouse(buttons: 1, x: 0.5, y: 0.5), on: Desk.wchMouseID, at: 1.0)
        XCTAssertEqual(delegate.frames.last?.contacts.count, 1, "a finger is down")
        system.clearCalls()
        delegate.clear()

        system.disconnect(Desk.wchMouseID)
        system.runLater()

        XCTAssertEqual(delegate.events.count, 1, "one change, nothing else: \(delegate.events)")
        let change = try XCTUnwrap(delegate.changes.first)
        XCTAssertEqual(change.handle, strip)
        XCTAssertFalse(change.hasMouseInterface)
        XCTAssertEqual(change.status.state, .taken)
        XCTAssertEqual(change.status.touchOrigin, .mouseInterface, "the origin is unchanged")
        XCTAssertEqual(delegate.frames, [], "no frame is made up")
        XCTAssertEqual(system.calls, [.stopReports(Desk.wchMouseID), .close(Desk.wchMouseID, exclusive: true)])
        XCTAssertTrue(system.isListening(to: Desk.wchTouchID), "the touch interface is still open and read")
    }

    // MARK: - What is never a sibling

    /// Review: a touch-enabled pen display's pen interface carries a Mouse collection, as does a
    /// combined keyboard. Neither is ever opened as the touchscreen's mouse sibling.
    func testAPenOrAKeyboardAtTheTouchscreensLocationIsNeverOpened() throws {
        let pen = interface(13, at: wchLocation, try Panels.penAndMouse(), usages: [.pen, .mouse],
                            vendorID: Panels.wchVendorID, productID: Panels.wchProductID, product: "TouchScreen")
        let keyboard = interface(14, at: wchLocation, try Panels.keyboardAndMouse(), usages: [.keyboard, .mouse],
                                 vendorID: Panels.wchVendorID, productID: Panels.wchProductID, product: "TouchScreen")
        let (system, delegate, source) = make([pen, keyboard, try Desk.wchTouch()])
        source.start()
        let strip = try XCTUnwrap(delegate.connected.first)
        XCTAssertFalse(strip.hasMouseInterface)
        source.setState(.taken, for: strip.handle)
        source.refresh()
        source.setState(.released, for: strip.handle)

        system.connect(try Desk.wchMouse())
        system.runLater()
        XCTAssertEqual(delegate.changes.last?.hasMouseInterface, true, "its real mouse interface is its sibling")
        source.setState(.taken, for: strip.handle)
        source.stop()
        XCTAssertFalse(system.calls.contains { [13, 14].contains($0.interfaceID) }, "\(system.calls)")
        XCTAssertTrue(system.calls.contains(.open(Desk.wchMouseID, exclusive: true)))
    }

    /// A pen tablet whose top collection is Digitizer (0x0D/0x01), beside a Mouse one.
    func testADigitizerInterfaceAtTheTouchscreensLocationIsNeverOpened() throws {
        let digitizer = interface(15, at: wchLocation, try Panels.penAndMouse(), usages: [HIDUsage(page: 0x0D, usage: 0x01), .mouse],
                                  vendorID: Panels.wchVendorID, productID: Panels.wchProductID, product: "TouchScreen")
        let (system, delegate, source) = make([digitizer, try Desk.wchTouch()])
        source.start()
        let strip = try XCTUnwrap(delegate.connected.first)
        XCTAssertFalse(strip.hasMouseInterface)
        source.setState(.taken, for: strip.handle)
        source.stop()
        XCTAssertFalse(system.calls.contains { $0.interfaceID == 15 }, "\(system.calls)")
    }

    func testAMouseWithAnotherUSBIDAtTheSameLocationIsNeverOpened() throws {
        let stranger = try Desk.otherMouse(id: 33, at: wchLocation)
        let (system, delegate, source) = make([stranger, try Desk.wchTouch()])
        source.start()
        let strip = try XCTUnwrap(delegate.connected.first)
        XCTAssertFalse(strip.hasMouseInterface)
        source.setState(.taken, for: strip.handle)
        source.stop()
        XCTAssertFalse(system.calls.contains { $0.interfaceID == 33 })
    }

    // MARK: - stop() from inside the delegate

    func testStopFromInsideAFrame() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        let ilitek = try handle(delegate, vendorID: Panels.ilitekVendorID)
        source.setState(.taken, for: ilitek)
        system.send(Panels.ilitekMouse(buttons: 1, x: 0.5, y: 0.5), on: Desk.ilitekMouseID, at: 1.0)
        delegate.clear()
        delegate.onFrame = { _, frame in
            if frame.contacts.isEmpty { source.stop() }
        }
        // A touch report: the empty frame that ends the mouse finger, then the touch frame.
        let touch = try XCTUnwrap(Panels.take(Panels.ilitek(), 1).reports.first)
        system.send(touch.bytes, on: Desk.ilitekTouchID, at: 1.05)

        XCTAssertEqual(delegate.frames, [ContactFrame(time: 1.05, contacts: [])], "nothing after the frame that stopped it")
        XCTAssertEqual(delegate.disconnections.count, 2)
        assertEveryOpenIsClosed(system.calls)
        XCTAssertEqual(system.calls.last, .stopMatching)
        XCTAssertFalse(system.send(touch.bytes, on: Desk.ilitekTouchID, at: 1.10), "nothing is listened to")
    }

    func testStopFromInsideAnOriginChange() throws {
        let (system, delegate, source) = make(try Desk.all())
        source.start()
        let ilitek = try handle(delegate, vendorID: Panels.ilitekVendorID)
        source.setState(.taken, for: ilitek)
        delegate.clear()
        delegate.onChanged = { change in
            if change.status.touchOrigin == .touchInterface { source.stop() }
        }
        let touch = try XCTUnwrap(Panels.take(Panels.ilitek(), 1).reports.first)
        system.send(touch.bytes, on: Desk.ilitekTouchID, at: 1.0)

        XCTAssertEqual(delegate.changes.map(\.status.touchOrigin), [.touchInterface])
        XCTAssertEqual(delegate.frames, [], "the frame of the report that stopped it is not delivered")
        XCTAssertEqual(delegate.disconnections.count, 2)
        assertEveryOpenIsClosed(system.calls)
        XCTAssertEqual(system.calls.last, .stopMatching)
    }

    func testStopFromInsideAnAnnouncementDuringStart() throws {
        let (system, delegate, source) = make(try Desk.all())
        delegate.onConnected = { _ in source.stop() }
        source.start()
        let first = try XCTUnwrap(delegate.connected.first)
        XCTAssertEqual(delegate.events, [.connected(first), .disconnected(first.handle)], "the second touchscreen is not announced")
        XCTAssertEqual(system.calls, [.startMatching, .stopMatching])
        source.setState(.taken, for: first.handle)
        system.runLater()
        XCTAssertEqual(system.calls, [.startMatching, .stopMatching])
    }

    /// Holds a source so the last reference can be dropped on another thread.
    private final class SourceHolder: @unchecked Sendable {
        var source: HIDTouchscreenSource?
    }

    private func assertEveryOpenIsClosed(_ calls: [FakeHIDSystem.Call], file: StaticString = #filePath, line: UInt = #line) {
        var open: [HIDInterfaceID: Int] = [:]
        for call in calls {
            switch call {
            case .open(let id, _): open[id, default: 0] += 1
            case .close(let id, _): open[id, default: 0] -= 1
            default: break
            }
        }
        XCTAssertEqual(open.filter { $0.value != 0 }, [:], "an open without its close: \(calls)", file: file, line: line)
    }

    func testTheDelegateIsNotKeptAlive() {
        let source = HIDTouchscreenSource(system: FakeHIDSystem())
        weak var watched: RecordingDelegate?
        do {
            let delegate = RecordingDelegate()
            source.delegate = delegate
            watched = delegate
        }
        XCTAssertNil(watched)
        XCTAssertNil(source.delegate)
    }
}
