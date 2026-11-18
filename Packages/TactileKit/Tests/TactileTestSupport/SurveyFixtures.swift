// The two panel surveys recorded with Tools/tactile-probe, for tests. The files are read where
// they are in the repository (Fixtures/surveys), found from this file's own path, so these
// tests only run inside the repository. The panel's serial and the displays' serial numbers and
// UUIDs in them are placeholders, not the surveyed devices'. Only the fields tests need are decoded; the schema is in
// Tools/tactile-probe/README.md.

import Foundation

public enum SurveyFixtures {
    /// Survey A: the wch.cn "TouchScreen" (27c0:0859) in takes 1–20. It only ever sent mouse-interface reports.
    public static let surveyA = Survey.load(fileName: "tactile-survey-20261114-070943.json")
    /// Survey B: the ILITEK "ILITEK-TP" (222a:0001) in takes 1–15. It sent touch-interface reports.
    public static let surveyB = Survey.load(fileName: "tactile-survey-20261114-071756.json")

    /// One survey file.
    public struct Survey: Sendable {
        let touchscreens: [Touchscreen]

        /// The section of the survey about the touchscreen with this USB vendor and product ID:
        /// its interfaces as the tool listed them, and the takes recorded on it.
        public func touchscreen(vendorID: Int, productID: Int) -> Touchscreen? {
            touchscreens.first { $0.vendorID == vendorID && $0.productID == productID }
        }
    }

    public struct Touchscreen: Sendable {
        public let vendorID: Int
        public let productID: Int
        public let interfaces: [Interface]
        public let takes: [Take]
    }

    /// One HID interface of a touchscreen's USB device.
    public struct Interface: Sendable {
        /// "touchscreen", "mouse", "vendor-ff0a" and so on: the key reports name their interface by.
        public let key: String
        /// The interface's HID report descriptor.
        public let descriptor: [UInt8]
    }

    /// One prompted action, from its first report until every contact lifted.
    public struct Take: Sendable {
        public let number: Int
        public let title: String
        /// Every input report from the surveyed touchscreen, in arrival order.
        public let reports: [Report]
    }

    /// One input report as it arrived, with what the survey tool decoded from it.
    public struct Report: Sendable {
        public let interfaceKey: String
        /// Host time in seconds, on the same clock as HID report timestamps.
        public let hostTime: TimeInterval
        /// The raw report, starting with the report ID byte when the interface uses IDs.
        public let bytes: [UInt8]
        /// The tool's decoded Contact Count and Scan Time, when the report has them.
        public let contactCount: Int?
        public let scanTime: Int?
        /// The tool's decoded fingers: the slots that carried data. `nil` for a report that isn't a touch report.
        public let fingers: [Finger]?
        /// The tool's decoded pointer. `nil` for a report that isn't a pointer report.
        public let pointer: Pointer?
    }

    /// One finger slot as the survey tool decoded it. Positions are 0…1 across the logical range,
    /// written rounded to five decimal places.
    public struct Finger: Sendable {
        public let slot: Int
        public let id: Int?
        public let tip: Bool?
        public let x: Double?
        public let y: Double?
    }

    /// A pointer report as the survey tool decoded it. Positions are 0…1 across the logical range,
    /// written rounded to five decimal places; `buttons` is a bit mask, bit 0 the first button.
    public struct Pointer: Sendable {
        public let buttons: Int?
        public let x: Double?
        public let y: Double?
    }
}

// MARK: - Loading

extension SurveyFixtures.Survey {
    static func load(fileName: String) -> Self {
        let url = SurveyFixtures.surveysDirectory(from: #filePath).appendingPathComponent(fileName)
        do {
            let raw = try JSONDecoder().decode(RawSurvey.self, from: Data(contentsOf: url))
            return try Self(raw: raw)
        } catch {
            fatalError("Could not load the survey \(url.path): \(error)")
        }
    }

    private init(raw: RawSurvey) throws {
        var touchscreens: [SurveyFixtures.Touchscreen] = []
        for listed in raw.list.touchscreens {
            let section = raw.touchscreens.first { $0.locationID == listed.locationID }
            let interfaces = try listed.interfaces.map {
                SurveyFixtures.Interface(key: $0.key, descriptor: try bytes(fromHex: $0.reportDescriptor ?? ""))
            }
            let takes = try (section?.takes ?? []).map { take in
                SurveyFixtures.Take(number: take.number, title: take.title, reports: try (take.reports ?? []).map { r in
                    SurveyFixtures.Report(
                        interfaceKey: r.interface, hostTime: TimeInterval(r.hostTimeNs) / 1_000_000_000,
                        bytes: try bytes(fromHex: r.bytes), contactCount: r.contactCount, scanTime: r.scanTime,
                        fingers: r.fingers?.map { SurveyFixtures.Finger(slot: $0.slot, id: $0.id, tip: $0.tip, x: $0.x, y: $0.y) },
                        pointer: r.pointer.map { SurveyFixtures.Pointer(buttons: $0.buttons, x: $0.x, y: $0.y) })
                })
            }
            touchscreens.append(SurveyFixtures.Touchscreen(
                vendorID: listed.vendorID, productID: listed.productID, interfaces: interfaces, takes: takes))
        }
        self.init(touchscreens: touchscreens)
    }
}

extension SurveyFixtures {
    /// Fixtures/surveys, found by walking up from this source file (here, or through the link
    /// in Tools/tactile-probe) to the repository's root.
    static func surveysDirectory(from sourceFile: String) -> URL {
        var directory = URL(fileURLWithPath: sourceFile).deletingLastPathComponent()
        while directory.pathComponents.count > 1 {
            let candidate = directory.appendingPathComponent("Fixtures/surveys")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            directory.deleteLastPathComponent()
        }
        fatalError("No Fixtures/surveys above \(sourceFile): these tests only run inside the repository")
    }
}

private struct HexError: Error, CustomStringConvertible {
    let text: String
    var description: String { "not a hex string: \(text.prefix(40))" }
}

private func bytes(fromHex text: String) throws -> [UInt8] {
    let digits = Array(text.utf8)
    guard digits.count % 2 == 0 else { throw HexError(text: text) }
    func nibble(_ c: UInt8) throws -> UInt8 {
        switch c {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return c - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return c - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return c - UInt8(ascii: "A") + 10
        default: throw HexError(text: text)
        }
    }
    var result: [UInt8] = []
    result.reserveCapacity(digits.count / 2)
    var i = 0
    while i < digits.count {
        result.append(try nibble(digits[i]) << 4 | nibble(digits[i + 1]))
        i += 2
    }
    return result
}

// MARK: - The subset of the survey file's schema that is decoded

private struct RawSurvey: Decodable {
    struct List: Decodable { let touchscreens: [ListedTouchscreen] }
    struct ListedTouchscreen: Decodable {
        let vendorID: Int
        let productID: Int
        let locationID: String
        let interfaces: [RawInterface]
    }
    struct RawInterface: Decodable {
        let key: String
        let reportDescriptor: String?
    }
    struct Section: Decodable {
        let locationID: String
        let takes: [RawTake]
    }
    struct RawTake: Decodable {
        let number: Int
        let title: String
        let reports: [RawReport]?
    }
    struct RawReport: Decodable {
        let interface: String
        let hostTimeNs: UInt64
        let bytes: String
        let contactCount: Int?
        let scanTime: Int?
        let fingers: [RawFinger]?
        let pointer: RawPointer?
    }
    struct RawFinger: Decodable {
        let slot: Int
        let id: Int?
        let tip: Bool?
        let x: Double?
        let y: Double?
    }
    struct RawPointer: Decodable {
        let buttons: Int?
        let x: Double?
        let y: Double?
    }

    let list: List
    let touchscreens: [Section]
}
