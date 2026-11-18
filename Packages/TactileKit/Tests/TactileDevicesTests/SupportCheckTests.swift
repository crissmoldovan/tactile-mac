import IOKit
import TactileReading
import TactileTestSupport
import XCTest
@testable import TactileDevices

/// The touchscreen check's steps, run against the fake HID system with the surveyed panels' own
/// descriptors and reports, and with a touchscreen that is only a mouse.
@MainActor
final class SupportCheckTests: XCTestCase {

    private func make(_ connected: [HIDInterfaceDescription], usbID: String,
                      configure: (FakeHIDSystem) -> Void = { _ in }) throws -> (FakeHIDSystem, SupportCheck) {
        let system = FakeHIDSystem(connected: connected)
        system.inputModeInterfaces = [SupportDesk.stripTouchID]
        configure(system)
        let probe = SupportProbe(system: system)
        probe.start()
        let device = try XCTUnwrap(probe.devices.first { $0.usbID == usbID }, "\(usbID) is not offered")
        return (system, SupportCheck(device: device, probe: probe))
    }

    /// Sends a survey take's reports, on the interfaces named, from just after `start`, keeping their
    /// spacing. Returns the time of the last.
    @discardableResult
    private func play(_ take: SurveyFixtures.Take, on ids: [String: HIDInterfaceID], _ system: FakeHIDSystem,
                      from start: TimeInterval) -> TimeInterval {
        guard let first = take.reports.first?.hostTime else { return start }
        var last = start
        for report in take.reports {
            last = start + 0.1 + (report.hostTime - first)
            if let id = ids[report.interfaceKey] { system.send(report.bytes, on: id, at: last) }
        }
        return last
    }

    private let ilitekIDs = ["touchscreen": SupportDesk.ilitekTouchID, "mouse": SupportDesk.ilitekMouseID]
    private let stripIDs = ["touchscreen": SupportDesk.stripTouchID, "mouse": SupportDesk.stripMouseID]

    // MARK: - Step 1: what it is

    func testStepOneReadsWhatItIsAndTouchesNothing() throws {
        let (system, check) = try make(try SupportDesk.all(), usbID: "222a:0001")
        XCTAssertEqual(check.stage, .ready)
        let identity = check.identity
        XCTAssertEqual(identity.interfaces.map(\.role), [.touch, .mouse])
        XCTAssertEqual(identity.fingerCollections, 10)
        XCTAssertFalse(identity.hasInputMode, "the ILITEK has no Input Mode setting")
        XCTAssertTrue(identity.hasCertificationBlob)
        XCTAssertEqual(identity.contactCountMaximumReportID, 0x06)
        XCTAssertEqual(identity.interfaces.first?.summary?.featureReports, [DescriptorSummary.Report(id: 0x06, length: 258)])
        XCTAssertEqual(identity.interfaces.first?.decoded?.surfaceSizeMM?.width ?? 0, 476.1, accuracy: 0.1)
        XCTAssertEqual(system.calls, [.startMatching], "step 1 opens nothing")

        let strip = try make(try SupportDesk.all(), usbID: "27c0:0859").1.identity
        XCTAssertTrue(strip.hasInputMode)
        XCTAssertEqual(strip.interfaces.map(\.role), [.touch, .mouse, .other])
    }

    // MARK: - Steps 2, 3 and 4 on the panels

    func testTheILITEKWorksFully() throws {
        let (system, check) = try make(try SupportDesk.all(), usbID: "222a:0001")
        let panel = try Panels.ilitek()
        check.start(at: 100)
        XCTAssertEqual(check.stage, .touching(.one))
        XCTAssertEqual(check.switches?.reads.map(\.reportID), [0x06])
        XCTAssertEqual(check.switches?.hasInputMode, false)

        var last = play(try Panels.take(panel, 1), on: ilitekIDs, system, from: 100)
        check.tick(at: last + 0.5)
        XCTAssertEqual(check.stage, .touching(.one), "not until the glass has been clear a second")
        check.tick(at: last + 1)
        XCTAssertEqual(check.stage, .touching(.two))
        XCTAssertEqual(check.steps.first?.ending, .done)
        XCTAssertEqual(check.steps.first?.fingersAtOnce, [1])

        last = play(try Panels.take(panel, 2), on: ilitekIDs, system, from: last + 1)
        check.tick(at: last + 1)
        XCTAssertEqual(check.stage, .touching(.five))
        XCTAssertEqual(check.steps[1].mostFingers, 2)

        last = play(try Panels.take(panel, 3), on: ilitekIDs, system, from: last + 1)
        check.tick(at: last + 1)
        XCTAssertEqual(check.steps.map(\.ending), [.done, .done, .done])
        XCTAssertEqual(check.steps[2].mostFingers, 10, "as many fingers as the survey's person could")
        XCTAssertEqual(check.stage, .finished)
        XCTAssertNil(check.interruption)
        XCTAssertEqual(check.verdict, .worksFully)
        XCTAssertEqual(check.verdictReason, .severalFingersFromTouchInterface)
        XCTAssertEqual(check.steps.map(\.origin), [.touchInterface, .touchInterface, .touchInterface])
        XCTAssertTrue(system.calls.contains(.close(SupportDesk.ilitekTouchID, exclusive: true)), "let go at the end")
        XCTAssertNil(check.writeBack, "nothing to write back: it has no Input Mode")
    }

    func testTheStripWorksWithOneFinger() throws {
        let (system, check) = try make(try SupportDesk.all(), usbID: "27c0:0859") {
            $0.featureReportBytes[0x0A] = [0x0A, 0x0A]
        }
        let panel = try Panels.wch()
        check.start(at: 0)
        XCTAssertEqual(check.switches?.inputModeWrite, SupportSwitches.ModeWrite(value: 2, result: kIOReturnSuccess))
        XCTAssertEqual(check.contactCountMaximum, 10)

        let last = play(try Panels.take(panel, 1), on: stripIDs, system, from: 0)
        check.tick(at: last + 1)
        XCTAssertEqual(check.stage, .touching(.two))
        let start = last + 1
        play(try Panels.take(panel, 2), on: stripIDs, system, from: start)
        check.tick(at: start + 14.9)
        XCTAssertEqual(check.stage, .touching(.two), "two fingers never come: it waits its 15 seconds")
        check.tick(at: start + 15)
        XCTAssertEqual(check.stage, .touching(.five))
        check.skip(at: start + 17)
        XCTAssertEqual(check.stage, .finished)

        XCTAssertEqual(check.steps.map(\.ending), [.done, .timeUp, .skipped])
        XCTAssertEqual(check.steps.map(\.origin), [.mouseInterface, .mouseInterface, .mouseInterface])
        XCTAssertEqual(check.verdict, .worksWithOneFinger)
        XCTAssertEqual(check.verdictReason, .oneFingerFromMouseInterface)
        XCTAssertEqual(check.writeBack, SupportSwitches.ModeWrite(value: 0, result: kIOReturnSuccess), "0 written back after its 2")
        XCTAssertEqual(check.steps[2].seconds, 2, accuracy: 1e-9)
    }

    func testAStepsTalliesItsInterfaces() throws {
        let (system, check) = try make(try SupportDesk.all(), usbID: "222a:0001")
        let take = try Panels.take(Panels.ilitek(), 2)
        check.start(at: 0)
        let last = play(take, on: ilitekIDs, system, from: 0)
        check.skip(at: last + 0.2)
        let step = try XCTUnwrap(check.steps.first)
        XCTAssertEqual(step.reportsSeen, take.reports.count)
        let touch = try XCTUnwrap(step.interfaces.first { $0.role == .touch })
        XCTAssertEqual(touch.reports, take.reports.count)
        XCTAssertEqual(touch.touchReports, take.reports.count)
        XCTAssertEqual(touch.pointerReports + touch.otherReports + touch.unreadableReports, 0)
        XCTAssertEqual(touch.reportedContactCounts, Array(Set(take.reports.compactMap(\.contactCount).filter { $0 > 0 })).sorted())
        let rate = try XCTUnwrap(touch.reportsPerSecond)
        XCTAssertEqual(rate, Double(take.reports.count - 1) / (take.reports.last!.hostTime - take.reports.first!.hostTime), accuracy: 1e-6)
        let xs = take.reports.flatMap { $0.fingers ?? [] }.filter { $0.tip == true }.compactMap(\.x)
        XCTAssertEqual(try XCTUnwrap(touch.xRange).lowerBound, xs.min()!, accuracy: 1e-4)
        XCTAssertEqual(try XCTUnwrap(touch.xRange).upperBound, xs.max()!, accuracy: 1e-4)
        XCTAssertEqual(step.interfaces.first { $0.role == .mouse }?.reports, 0, "the mouse interface sent nothing")
    }

    // MARK: - When it doesn't work

    func testNothingComesSoItDoesntWork() throws {
        let (_, check) = try make(try SupportDesk.all(), usbID: "222a:0001")
        check.start(at: 0)
        check.tick(at: 15)
        check.tick(at: 30)
        check.tick(at: 45)
        XCTAssertEqual(check.stage, .finished)
        XCTAssertEqual(check.steps.map(\.ending), [.timeUp, .timeUp, .timeUp])
        XCTAssertEqual(check.verdict, .doesNotWork)
        XCTAssertEqual(check.verdictReason, .noReports)
    }

    func testReportsTactileCantReadDontWork() throws {
        let (system, check) = try make(try SupportDesk.all(), usbID: "222a:0001")
        check.start(at: 0)
        system.send([0x77, 0x01, 0x02], on: SupportDesk.ilitekTouchID, at: 1)
        system.send([0x04], on: SupportDesk.ilitekTouchID, at: 2)
        check.skip(at: 3)
        check.skip(at: 4)
        check.skip(at: 5)
        XCTAssertEqual(check.steps.first?.interfaces.first { $0.role == .touch }?.unreadableReports, 2)
        XCTAssertEqual(check.verdict, .doesNotWork)
        XCTAssertEqual(check.verdictReason, .reportsNotReadable)
    }

    func testAFailedFeatureReadIsRecordedAndTheCheckGoesOn() throws {
        let (_, check) = try make(try SupportDesk.all(), usbID: "222a:0001") {
            $0.readResult = FakeHIDSystem.notPermitted
        }
        check.start(at: 0)
        XCTAssertEqual(check.switches?.reads.map(\.result), [FakeHIDSystem.notPermitted])
        XCTAssertEqual(check.stage, .touching(.one))
        XCTAssertNil(check.contactCountMaximum, "nothing came back")
    }

    func testADeviceThatCantBeTakenEndsTheCheck() throws {
        let (system, check) = try make(try SupportDesk.all(), usbID: "222a:0001")
        system.disconnect(SupportDesk.ilitekTouchID)
        check.start(at: 0)
        XCTAssertEqual(check.stage, .finished)
        XCTAssertEqual(check.interruption, .notConnected)
        XCTAssertNil(check.switches)
        XCTAssertEqual(check.steps, [])
    }

    // MARK: - Skipping, the report cap, stopping and unplugging

    func testSkippingEndsAStepAndKeepsWhatCame() throws {
        let (system, check) = try make(try SupportDesk.all(), usbID: "27c0:0859")
        check.start(at: 10)
        system.send(Panels.wchMouse(buttons: 1, x: 0.25, y: 0.5), on: SupportDesk.stripMouseID, at: 11)
        check.skip(at: 13)
        XCTAssertEqual(check.stage, .touching(.two))
        XCTAssertEqual(check.steps.first?.ending, .skipped)
        XCTAssertEqual(check.steps.first?.seconds ?? 0, 3, accuracy: 1e-9)
        XCTAssertEqual(check.steps.first?.reportsSeen, 1)
        XCTAssertEqual(check.steps.last?.fingers, .two)
        XCTAssertEqual(check.steps.last?.ending, nil, "the step under way")
    }

    func testAtMostTwoHundredReportsAreKeptInAStep() throws {
        let (system, check) = try make(try SupportDesk.all(), usbID: "27c0:0859")
        check.start(at: 0)
        for n in 0..<250 {
            system.send(Panels.wchMouse(buttons: 1, x: Double(n) / 250, y: 0.5), on: SupportDesk.stripMouseID, at: 1 + Double(n) * 0.01)
        }
        check.skip(at: 5)
        let step = try XCTUnwrap(check.steps.first)
        XCTAssertEqual(step.reportsSeen, 250)
        XCTAssertEqual(step.reports.count, SupportCheck.reportsKept)
        XCTAssertEqual(step.reports.first?.bytes, Panels.wchMouse(buttons: 1, x: 0, y: 0.5), "the first ones, in order")
        XCTAssertEqual(step.interfaces.first { $0.role == .mouse }?.reports, 250, "the tallies count every one")
    }

    func testStoppingLetsTheDeviceGo() throws {
        let (system, check) = try make(try SupportDesk.all(), usbID: "27c0:0859")
        check.start(at: 0)
        system.clearCalls()
        check.stop(at: 2)
        XCTAssertEqual(check.stage, .finished)
        XCTAssertEqual(check.interruption, .stopped)
        XCTAssertEqual(check.steps.map(\.ending), [.stopped])
        XCTAssertTrue(system.calls.contains(.writeInputMode(SupportDesk.stripTouchID, 0)))
        check.stop(at: 3)
        XCTAssertEqual(check.steps.count, 1, "stopping twice changes nothing")
    }

    func testUnpluggingEndsTheCheckAndWritesNothing() throws {
        let (system, check) = try make(try SupportDesk.all(), usbID: "27c0:0859")
        var changes = 0
        check.onChange = { changes += 1 }
        check.start(at: 0)
        check.skip(at: 1)
        system.clearCalls()
        system.disconnect(SupportDesk.stripMouseID)
        XCTAssertEqual(check.stage, .finished)
        XCTAssertEqual(check.interruption, .unplugged)
        XCTAssertEqual(check.steps.map(\.ending), [.skipped, .stopped])
        XCTAssertFalse(system.calls.contains { if case .writeInputMode = $0 { return true } else { return false } })
        XCTAssertGreaterThanOrEqual(changes, 3)
    }

    // MARK: - Mouse-only

    func testAMouseOnlyTouchscreenWorksWithOneFinger() throws {
        let (system, check) = try make(try SupportDesk.all(), usbID: "1234:5678")
        XCTAssertEqual(check.device.kind, .mouseOnly)
        XCTAssertEqual(check.identity.interfaces.map(\.role), [.pointer])
        check.start(at: 0)
        XCTAssertEqual(check.switches?.reads, [])
        XCTAssertNil(check.switches?.inputModeWrite)
        func send(_ buttons: UInt8, _ x: Double, at time: TimeInterval) {
            system.send(HandMadeDescriptors.absolutePointerReport(buttons: buttons, x: x, y: 0.5), on: SupportDesk.pointerID, at: time)
        }
        send(1, 0.2, at: 1)
        send(1, 0.3, at: 1.1)
        send(0, 0.3, at: 1.2)
        check.tick(at: 2.2)
        XCTAssertEqual(check.steps.first?.ending, .done)
        XCTAssertEqual(check.steps.first?.interfaces.first?.pointerReports, 3)
        check.skip(at: 3)
        check.skip(at: 4)
        XCTAssertEqual(check.verdict, .worksWithOneFinger)
        XCTAssertEqual(check.verdictReason, .oneFingerFromMouseInterface)
        XCTAssertFalse(system.calls.contains { call in
            switch call {
            case .hasInputMode, .readFeatureReport, .writeInputMode: return true
            default: return false
            }
        }, "nothing is read from it or written to it")
    }

    // MARK: - The verdict

    func testTheVerdictRules() {
        func step(touch: Int = 0, mouse: Int = 0, reports: Int = 0) -> SupportTouchStep {
            var step = SupportTouchStep(fingers: .one, startedAt: 0)
            step.mostFingersFromTouchInterface = touch
            step.mostFingersFromMouseInterface = mouse
            step.reportsSeen = reports
            return step
        }
        func verdict(_ steps: [SupportTouchStep]) -> (SupportVerdict, SupportVerdictReason) {
            SupportCheck.verdict(of: steps)
        }
        XCTAssertTrue(verdict([step(touch: 1), step(touch: 2)]) == (.worksFully, .severalFingersFromTouchInterface))
        XCTAssertTrue(verdict([step(touch: 5, mouse: 1)]) == (.worksFully, .severalFingersFromTouchInterface))
        XCTAssertTrue(verdict([step(touch: 1), step(touch: 1)]) == (.worksWithOneFinger, .oneFingerFromTouchInterface))
        XCTAssertTrue(verdict([step(touch: 1, mouse: 1)]) == (.worksWithOneFinger, .oneFingerFromTouchInterface))
        XCTAssertTrue(verdict([step(mouse: 1), step(mouse: 1)]) == (.worksWithOneFinger, .oneFingerFromMouseInterface))
        XCTAssertTrue(verdict([step(reports: 40)]) == (.doesNotWork, .reportsNotReadable))
        XCTAssertTrue(verdict([step(), step()]) == (.doesNotWork, .noReports))
        XCTAssertTrue(verdict([]) == (.doesNotWork, .noReports))
        XCTAssertEqual(SupportVerdict.allCases.map(\.rawValue), ["works-fully", "works-with-one-finger", "doesnt-work"])
    }
}
