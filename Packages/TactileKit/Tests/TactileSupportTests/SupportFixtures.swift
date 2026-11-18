// What the report's tests are made from: the devices as the device layer describes them (the
// surveyed ILITEK, and a touchscreen that is only a mouse, whose product name carries its serial), a
// finished check's steps, and a Mac. Nothing here opens a device or touches the network.

import CryptoKit
import Foundation
import TactileDevices
import TactileReading
import TactileSupport
import TactileTestSupport
import XCTest

enum Fixture {
    static let ilitekSerial = "V06.00.00.00"
    static let pointerSerial = "POINTER-SERIAL-0042"

    static func ilitek() throws -> SupportDevice {
        let panel = try XCTUnwrap(SurveyFixtures.surveyB.touchscreen(vendorID: 0x222a, productID: 0x0001))
        func descriptor(_ key: String) throws -> [UInt8] {
            try XCTUnwrap(panel.interfaces.first { $0.key == key }).descriptor
        }
        return SupportDevice(
            id: "222a:0001@01141000", kind: .touchscreen, vendorID: 0x222a, productID: 0x0001, product: "ILITEK-TP",
            manufacturer: "ILITEK", serial: ilitekSerial, locationID: 0x0114_1000,
            interfaces: [
                SupportInterface(id: 4_294_970_001, role: .touch, usages: [.init(page: 0x0D, usage: 0x04)],
                                 descriptor: try descriptor("touchscreen"), maxInputReportSize: 64),
                SupportInterface(id: 4_294_970_002, role: .mouse,
                                 usages: [.init(page: 0x01, usage: 0x02), .init(page: 0x01, usage: 0x01), .init(page: 0xFF00, usage: 0x01)],
                                 descriptor: try descriptor("mouse"), maxInputReportSize: 64),
            ])
    }

    static func pointer() -> SupportDevice {
        SupportDevice(
            id: "1234:5678@01200000", kind: .mouseOnly, vendorID: 0x1234, productID: 0x5678, product: "Panel \(pointerSerial)",
            manufacturer: "Example Panels", serial: pointerSerial, locationID: 0x0120_0000,
            interfaces: [
                SupportInterface(id: 4_294_970_031, role: .pointer, usages: [.init(page: 0x01, usage: 0x01)],
                                 descriptor: HandMadeDescriptors.absolutePointer, maxInputReportSize: 6),
            ])
    }

    static let mac = SupportMac(model: "Mac15,6", macOS: "26.1", tactileVersion: "0.7.0", tactileBuild: "512", displays: 2)

    /// The ILITEK's switches: its one feature report read, 258 bytes with Contact Count Maximum 10.
    static func ilitekSwitches() -> SupportSwitches {
        var switches = SupportSwitches()
        switches.opens = [
            .init(interface: 4_294_970_001, role: .touch, exclusiveResult: 0, sharedResult: nil),
            .init(interface: 4_294_970_002, role: .mouse, exclusiveResult: Int32(bitPattern: 0xE000_02C5), sharedResult: 0),
        ]
        switches.reads = [
            .init(reportID: 0x06, contents: ["Contact Count Maximum", "certification blob"], lengthAsked: 258,
                  lengthReturned: 258, result: 0, seconds: 0.0126, bytes: [0x06, 0x0A] + [UInt8](repeating: 0xAB, count: 256)),
        ]
        switches.hasInputMode = false
        return switches
    }

    /// A step with `count` touch reports of the ILITEK's own (report ID 4), one finger seen.
    static func step(_ fingers: SupportFingers, ending: SupportStepEnding, reports count: Int, startedAt: TimeInterval = 100)
        -> SupportTouchStep {
        var step = SupportTouchStep(fingers: fingers, startedAt: startedAt)
        step.ending = ending
        step.seconds = 3.3
        var tally = SupportInterfaceTally(interface: 4_294_970_001, role: .touch)
        tally.reports = count
        tally.touchReports = count
        tally.reportedContactCounts = count > 0 ? [1] : []
        tally.xRange = count > 0 ? 0.25...0.5 : nil
        tally.yRange = count > 0 ? 0.125...0.75 : nil
        tally.firstTime = count > 0 ? startedAt + 0.5 : nil
        tally.lastTime = count > 0 ? startedAt + 0.5 + Double(count - 1) * 0.01 : nil
        step.interfaces = [tally, SupportInterfaceTally(interface: 4_294_970_002, role: .mouse)]
        step.fingersAtOnce = count > 0 ? [1] : []
        step.mostFingersFromTouchInterface = count > 0 ? 1 : 0
        step.origin = count > 0 ? .touchInterface : .undetermined
        step.reportsSeen = count
        step.reports = (0..<min(count, 200)).map { n in
            SupportRawReport(interface: 4_294_970_001, role: .touch, bytes: [0x04, 0x01, UInt8(n % 256), 0x00],
                             time: startedAt + 0.5 + Double(n) * 0.01)
        }
        return step
    }

    static func ilitekInput(logLines: [String] = []) throws -> SupportReportInput {
        let device = try ilitek()
        let steps = [step(.one, ending: .done, reports: 40), step(.two, ending: .skipped, reports: 0),
                     step(.five, ending: .timeUp, reports: 3)]
        let verdict = SupportCheck.verdict(of: steps)
        return SupportReportInput(
            device: device, identity: SupportIdentity(device), switches: ilitekSwitches(), writeBack: nil,
            contactCountMaximum: 10, steps: steps, verdict: verdict.verdict, verdictReason: verdict.reason,
            interruption: nil, logLines: logLines, mac: mac)
    }

    static func pointerInput(logLines: [String] = []) -> SupportReportInput {
        let device = pointer()
        var switches = SupportSwitches()
        switches.opens = [.init(interface: 4_294_970_031, role: .pointer, exclusiveResult: 0, sharedResult: nil)]
        var one = SupportTouchStep(fingers: .one, startedAt: 10)
        one.ending = .done
        one.seconds = 2
        one.mostFingersFromMouseInterface = 1
        one.fingersAtOnce = [1]
        one.origin = .mouseInterface
        one.reportsSeen = 2
        one.reports = [SupportRawReport(interface: 4_294_970_031, role: .pointer, bytes: [0x02, 0x01, 0xFF, 0x3F, 0xFF, 0x3F], time: 10.5)]
        let steps = [one]
        let verdict = SupportCheck.verdict(of: steps)
        return SupportReportInput(
            device: device, identity: SupportIdentity(device), switches: switches, writeBack: nil, contactCountMaximum: nil,
            steps: steps, verdict: verdict.verdict, verdictReason: verdict.reason, interruption: nil, logLines: logLines, mac: mac)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func json(_ file: SupportFile?) throws -> [String: Any] {
        let data = try XCTUnwrap(file?.data, "no such file")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

extension Array where Element == SupportFile {
    subscript(named name: String) -> SupportFile? { first { $0.name == name } }
}
