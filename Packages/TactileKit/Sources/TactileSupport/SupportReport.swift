// The touchscreen check's report: the files it is made of, exactly as the "what will be sent" sheet
// lists them and the zip holds them. Pure: everything comes from the finished check, Tactile's log
// lines and the Mac's facts, given.

import CryptoKit
import Foundation
import TactileDevices
import TactileReading

/// One file of a report: its name in the zip, and its bytes.
public struct SupportFile: Equatable, Sendable {
    public var name: String
    public var data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }

    public var size: Int { data.count }
    /// Every file of a report is text.
    public var text: String { String(decoding: data, as: UTF8.self) }
}

/// Everything a report is made from.
public struct SupportReportInput: Sendable {
    public var device: SupportDevice
    public var identity: SupportIdentity
    public var switches: SupportSwitches?
    public var writeBack: SupportSwitches.ModeWrite?
    public var contactCountMaximum: Int?
    public var steps: [SupportTouchStep]
    public var verdict: SupportVerdict
    public var verdictReason: SupportVerdictReason
    public var interruption: SupportCheck.Interruption?
    /// Tactile's log lines about the device (`SupportLog.lines`).
    public var logLines: [String]
    public var mac: SupportMac

    public init(device: SupportDevice, identity: SupportIdentity, switches: SupportSwitches?,
                writeBack: SupportSwitches.ModeWrite?, contactCountMaximum: Int?, steps: [SupportTouchStep],
                verdict: SupportVerdict, verdictReason: SupportVerdictReason, interruption: SupportCheck.Interruption?,
                logLines: [String], mac: SupportMac) {
        self.device = device
        self.identity = identity
        self.switches = switches
        self.writeBack = writeBack
        self.contactCountMaximum = contactCountMaximum
        self.steps = steps
        self.verdict = verdict
        self.verdictReason = verdictReason
        self.interruption = interruption
        self.logLines = logLines
        self.mac = mac
    }

    /// A finished check's.
    @MainActor
    public init(check: SupportCheck, logLines: [String], mac: SupportMac) {
        self.init(device: check.device, identity: check.identity, switches: check.switches, writeBack: check.writeBack,
                  contactCountMaximum: check.contactCountMaximum, steps: check.steps, verdict: check.verdict,
                  verdictReason: check.verdictReason, interruption: check.interruption, logLines: logLines, mac: mac)
    }
}

/// The report's files, in the order the sheet lists them:
///
/// | File | What it holds |
/// |---|---|
/// | `summary.txt` | The verdict and each step's results, in plain words. |
/// | `device.json` | The USB IDs, product and manufacturer, each interface's usages and its descriptor read (`DescriptorSummary`, `InterfaceDecoder`). No serial number, and not where it is plugged in. |
/// | `descriptors/interface-<n>.hex` | Each interface's report descriptor, 16 bytes a line. |
/// | `switches.json` | Each open, feature report read (with the bytes that came back) and Input Mode write, with its IOReturn. |
/// | `touches.json` | Each touch step: how it ended, each interface's tallies, and its first raw reports. |
/// | `tactile-log.txt` | Tactile's log lines about the device in this session. |
/// | `mac.json` | The Mac's model identifier, macOS's version, Tactile's version and build, and the number of displays. |
/// | `manifest.json` | The schema version, and the SHA-256 of every other file. |
///
/// Interfaces are numbered from 1 in the device's order, never by their IORegistry IDs. Every
/// string that came from the device or the log goes through `SupportRedaction`, so no serial number
/// is in any file.
public enum SupportReport {
    public static let schemaVersion = 1
    /// The raw reports kept of each step, at most: the check's own limit.
    public static let reportsPerStep = 200
    public static let manifestName = "manifest.json"
    /// The descriptors a report holds, at most: tactilemac.com takes 32 entries in a zip, which are
    /// the seven other files, the `descriptors/` folder and these.
    public static let maxDescriptorFiles = 24

    /// The files, in order, the manifest last. `reportsPerStep` and `logLines` trim the raw reports
    /// of each step and the log, to keep the zip within its limit (`SupportArchive`).
    public static func files(_ input: SupportReportInput, reportsPerStep: Int = reportsPerStep, logLines: Int? = nil) -> [SupportFile] {
        let numbers = Dictionary(uniqueKeysWithValues: input.device.interfaces.enumerated().map { ($0.element.id, $0.offset + 1) })
        var files: [SupportFile] = [
            SupportFile(name: "summary.txt", data: Data(summary(input, numbers: numbers).utf8)),
            SupportFile(name: "device.json", data: json(deviceFile(input, numbers: numbers))),
        ]
        for (index, interface) in input.device.interfaces.enumerated() where hasDescriptorFile(index, input) {
            guard let descriptor = interface.descriptor else { continue }
            files.append(SupportFile(name: descriptorName(index + 1), data: Data(hexLines(descriptor).utf8)))
        }
        files.append(SupportFile(name: "switches.json", data: json(switchesFile(input, numbers: numbers))))
        files.append(SupportFile(name: "touches.json", data: json(touchesFile(input, numbers: numbers, kept: max(0, reportsPerStep)))))
        files.append(SupportFile(name: "tactile-log.txt", data: Data(logText(input, limit: logLines).utf8)))
        files.append(SupportFile(name: "mac.json", data: json(MacFile(input.mac))))
        let hashes = Dictionary(uniqueKeysWithValues: files.map { ($0.name, sha256($0.data)) })
        files.append(SupportFile(name: manifestName, data: json(ManifestFile(schema: schemaVersion, files: hashes))))
        return files
    }

    /// Whether `name` is one a report holds: what the site accepts in a zip.
    public static func isExpectedName(_ name: String) -> Bool {
        if ["summary.txt", "device.json", "switches.json", "touches.json", "tactile-log.txt", "mac.json", manifestName].contains(name) {
            return true
        }
        return name.range(of: #"^descriptors/interface-[1-9][0-9]*\.hex$"#, options: .regularExpression) != nil
    }

    static func descriptorName(_ number: Int) -> String { "descriptors/interface-\(number).hex" }

    /// Whether the interface at `index` has its descriptor in a file: it has one, and it is among the
    /// first `maxDescriptorFiles` that do.
    private static func hasDescriptorFile(_ index: Int, _ input: SupportReportInput) -> Bool {
        let interfaces = input.device.interfaces
        guard interfaces.indices.contains(index), interfaces[index].descriptor != nil else { return false }
        return interfaces[..<index].filter { $0.descriptor != nil }.count < maxDescriptorFiles
    }

    // MARK: - Hex

    private static let hexDigits = Array("0123456789abcdef".utf8)

    /// "05 0d 09 04 …", 16 bytes a line, each line ended.
    static func hexLines(_ bytes: [UInt8]) -> String {
        var text: [UInt8] = []
        text.reserveCapacity(bytes.count * 3)
        for (index, byte) in bytes.enumerated() {
            text.append(hexDigits[Int(byte >> 4)])
            text.append(hexDigits[Int(byte & 0x0F)])
            text.append(index % 16 == 15 || index == bytes.count - 1 ? UInt8(ascii: "\n") : UInt8(ascii: " "))
        }
        return String(decoding: text, as: UTF8.self)
    }

    /// "060aabab…".
    static func hex(_ bytes: [UInt8]) -> String {
        var text: [UInt8] = []
        text.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            text.append(hexDigits[Int(byte >> 4)])
            text.append(hexDigits[Int(byte & 0x0F)])
        }
        return String(decoding: text, as: UTF8.self)
    }

    /// The bytes of hex text, spaced or not; nil when it isn't hex.
    public static func bytes(fromHex text: String) -> [UInt8]? {
        let digits = text.filter { !$0.isWhitespace }
        guard digits.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            guard let byte = UInt8(digits[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func json(_ value: some Encodable) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = (try? encoder.encode(value)) ?? Data("{}".utf8)
        return data + Data("\n".utf8)
    }

    private static func rounded(_ value: Double, _ places: Double) -> Double {
        let scale = pow(10, places)
        return (value * scale).rounded() / scale
    }

    private static func usageText(_ usage: DescriptorSummary.Collection) -> String {
        String(format: "0x%04x/0x%04x", usage.page, usage.usage)
    }

    /// The device's strings, with any serial number taken out.
    private static func clean(_ text: String, _ input: SupportReportInput) -> String {
        SupportRedaction.redact(text, serials: [input.device.serial], home: nil)
    }

    // MARK: - device.json

    private struct DeviceFile: Encodable {
        var usbId: String
        var vendorId: Int
        var productId: Int
        var product: String
        var manufacturer: String
        var kind: String
        var fingerCollections: Int
        var hasInputMode: Bool
        var hasCertificationBlob: Bool
        var contactCountMaximumReport: Int?
        var contactCountMaximum: Int?
        var interfaces: [Interface]
        /// Descriptors not in a file of their own, past `maxDescriptorFiles`.
        var descriptorsLeftOut: Int?

        struct Interface: Encodable {
            var number: Int
            var role: String
            var usages: [String]
            var maxInputReportSize: Int?
            var descriptorFile: String?
            var descriptorLength: Int?
            var descriptor: Summary?
            var decoded: Decoded?
        }

        struct Summary: Encodable {
            var applicationCollections: [String]
            var usesReportIds: Bool
            var inputReports: [Report]
            var outputReports: [Report]
            var featureReports: [Report]
            var inputModeReport: Int?
            var certificationBlobReport: Int?
            var contactCountMaximumReport: Int?
            var absolutePointer: Bool
            var digitizer: Bool
            var problems: [String]
        }

        struct Report: Encodable {
            var id: Int
            var length: Int
        }

        struct Decoded: Encodable {
            var kind: String
            var fingerCollections: Int
            var surfaceMm: [Double]?
            var reportsContactSize: Bool
            var reportsConfidence: Bool
            var maxInputReportLength: Int
            var featureReportsToRead: [Int]
        }
    }

    private static func deviceFile(_ input: SupportReportInput, numbers: [UInt64: Int]) -> DeviceFile {
        let identity = input.identity
        let withDescriptors = input.device.interfaces.filter { $0.descriptor != nil }.count
        let leftOut = max(0, withDescriptors - maxDescriptorFiles)
        let filed = Set(input.device.interfaces.indices.filter { hasDescriptorFile($0, input) }.map { input.device.interfaces[$0].id })
        return DeviceFile(
            usbId: input.device.usbID, vendorId: input.device.vendorID, productId: input.device.productID,
            product: clean(input.device.product, input), manufacturer: clean(input.device.manufacturer, input),
            kind: input.device.kind.rawValue, fingerCollections: identity.fingerCollections,
            hasInputMode: identity.hasInputMode, hasCertificationBlob: identity.hasCertificationBlob,
            contactCountMaximumReport: identity.contactCountMaximumReportID, contactCountMaximum: input.contactCountMaximum,
            interfaces: identity.interfaces.map { interface in
                let number = numbers[interface.id] ?? 0
                return DeviceFile.Interface(
                    number: number, role: interface.role.rawValue, usages: interface.usages.map(usageText),
                    maxInputReportSize: interface.maxInputReportSize,
                    descriptorFile: filed.contains(interface.id) ? descriptorName(number) : nil,
                    descriptorLength: interface.descriptor?.count,
                    descriptor: interface.summary.map { summary in
                        DeviceFile.Summary(
                            applicationCollections: summary.applicationCollections.map(usageText),
                            usesReportIds: summary.usesReportIDs,
                            inputReports: summary.inputReports.map { DeviceFile.Report(id: $0.id, length: $0.length) },
                            outputReports: summary.outputReports.map { DeviceFile.Report(id: $0.id, length: $0.length) },
                            featureReports: summary.featureReports.map { DeviceFile.Report(id: $0.id, length: $0.length) },
                            inputModeReport: summary.inputModeReportID, certificationBlobReport: summary.certificationBlobReportID,
                            contactCountMaximumReport: summary.contactCountMaximumReportID,
                            absolutePointer: summary.hasAbsolutePointer, digitizer: summary.isDigitizer, problems: summary.problems)
                    },
                    decoded: interface.decoded.map { decoded in
                        DeviceFile.Decoded(
                            kind: kindText(decoded.kind), fingerCollections: decoded.fingerCollections,
                            surfaceMm: decoded.surfaceSizeMM.map { [rounded($0.width, 1), rounded($0.height, 1)] },
                            reportsContactSize: decoded.reportsContactSize, reportsConfidence: decoded.reportsConfidence,
                            maxInputReportLength: decoded.maxInputReportLength,
                            featureReportsToRead: decoded.featureReportsToRead.map(\.reportID))
                    })
            },
            descriptorsLeftOut: leftOut > 0 ? leftOut : nil)
    }

    private static func kindText(_ kind: InterfaceKind) -> String {
        switch kind {
        case .touchscreen: return "touchscreen"
        case .mouse: return "mouse"
        case .other: return "other"
        }
    }

    // MARK: - switches.json

    private struct SwitchesFile: Encodable {
        var skipped: Bool
        var why: String?
        var opens: [Open]
        var featureReads: [Read]
        var readsStoppedAfterTimeout: Bool
        var hasInputMode: Bool?
        var inputModeWrite: Write?
        var inputModeWriteBack: Write?

        struct Open: Encodable {
            var interface: Int
            var role: String
            var held: String
            var exclusiveIoReturn: String
            var sharedIoReturn: String?
        }

        struct Read: Encodable {
            var reportId: Int
            var contents: [String]
            var lengthAsked: Int
            var lengthReturned: Int
            var ioReturn: String
            var seconds: Double
            var timedOut: Bool
            var bytes: String
        }

        struct Write: Encodable {
            var value: Int
            var ioReturn: String
        }
    }

    private static func switchesFile(_ input: SupportReportInput, numbers: [UInt64: Int]) -> SwitchesFile {
        let switches = input.switches ?? SupportSwitches()
        let why: String?
        if input.switches == nil {
            why = "the device wasn't connected when the check began"
        } else if input.device.kind == .mouseOnly {
            why = "mouse-only: it has no touch interface to read or switch"
        } else if input.device.touchInterface == nil {
            why = "digitiser: no Touch Screen or Touch Pad interface, so Tactile read and switched nothing; its digitiser interfaces were only listened to"
        } else {
            why = nil
        }
        func write(_ write: SupportSwitches.ModeWrite?) -> SwitchesFile.Write? {
            write.map { SwitchesFile.Write(value: $0.value, ioReturn: SupportSwitches.ioReturnText($0.result)) }
        }
        return SwitchesFile(
            skipped: why != nil, why: why,
            opens: switches.opens.map { open in
                SwitchesFile.Open(
                    interface: numbers[open.interface] ?? 0, role: open.role.rawValue, held: open.held.rawValue,
                    exclusiveIoReturn: SupportSwitches.ioReturnText(open.exclusiveResult),
                    sharedIoReturn: open.sharedResult.map(SupportSwitches.ioReturnText))
            },
            featureReads: switches.reads.map { read in
                SwitchesFile.Read(
                    reportId: read.reportID, contents: read.contents, lengthAsked: read.lengthAsked,
                    lengthReturned: read.lengthReturned, ioReturn: SupportSwitches.ioReturnText(read.result),
                    seconds: rounded(read.seconds, 4), timedOut: read.timedOut, bytes: hex(read.bytes))
            },
            readsStoppedAfterTimeout: switches.readsStoppedAfterTimeout, hasInputMode: switches.hasInputMode,
            inputModeWrite: write(switches.inputModeWrite), inputModeWriteBack: write(input.writeBack))
    }

    // MARK: - touches.json

    private struct TouchesFile: Encodable {
        var steps: [Step]
        var stopped: String?

        struct Step: Encodable {
            var fingers: Int
            var ending: String?
            var seconds: Double
            var origin: String
            var fingersAtOnce: [Int]
            var mostFingersFromTouchInterface: Int
            var mostFingersFromMouseInterface: Int
            var reportsSeen: Int
            var reportsKept: Int
            var interfaces: [Tally]
            var reports: [RawReport]
        }

        struct Tally: Encodable {
            var interface: Int
            var role: String
            var reports: Int
            var touchReports: Int
            var pointerReports: Int
            var otherReports: Int
            var unreadableReports: Int
            var reportedContactCounts: [Int]
            var xRange: [Double]?
            var yRange: [Double]?
            var reportsPerSecond: Double?
        }

        struct RawReport: Encodable {
            var interface: Int
            var role: String
            /// Since the step began, in milliseconds.
            var ms: Double
            var bytes: String
        }
    }

    private static func touchesFile(_ input: SupportReportInput, numbers: [UInt64: Int], kept: Int) -> TouchesFile {
        TouchesFile(
            steps: input.steps.map { step in
                let reports = step.reports.prefix(kept)
                return TouchesFile.Step(
                    fingers: step.fingers.rawValue, ending: step.ending?.rawValue, seconds: rounded(step.seconds, 3),
                    origin: step.origin.rawValue, fingersAtOnce: step.fingersAtOnce,
                    mostFingersFromTouchInterface: step.mostFingersFromTouchInterface,
                    mostFingersFromMouseInterface: step.mostFingersFromMouseInterface, reportsSeen: step.reportsSeen,
                    reportsKept: reports.count,
                    interfaces: step.interfaces.map { tally in
                        TouchesFile.Tally(
                            interface: numbers[tally.interface] ?? 0, role: tally.role.rawValue, reports: tally.reports,
                            touchReports: tally.touchReports, pointerReports: tally.pointerReports,
                            otherReports: tally.otherReports, unreadableReports: tally.unreadableReports,
                            reportedContactCounts: tally.reportedContactCounts,
                            xRange: tally.xRange.map { [rounded($0.lowerBound, 5), rounded($0.upperBound, 5)] },
                            yRange: tally.yRange.map { [rounded($0.lowerBound, 5), rounded($0.upperBound, 5)] },
                            reportsPerSecond: tally.reportsPerSecond.map { rounded($0, 1) })
                    },
                    reports: reports.map { report in
                        TouchesFile.RawReport(
                            interface: numbers[report.interface] ?? 0, role: report.role.rawValue,
                            ms: rounded((report.time - step.startedAt) * 1000, 1), bytes: hex(report.bytes))
                    })
            },
            stopped: input.interruption.map(interruptionText))
    }

    private static func interruptionText(_ interruption: SupportCheck.Interruption) -> String {
        switch interruption {
        case .notConnected: return "not connected"
        case .unplugged: return "unplugged"
        case .stopped: return "stopped"
        }
    }

    // MARK: - tactile-log.txt, mac.json, manifest.json

    private static func logText(_ input: SupportReportInput, limit: Int?) -> String {
        var lines = input.logLines.map { clean($0, input) }
        guard !lines.isEmpty else { return "No lines of Tactile’s log about this touchscreen in this session.\n" }
        var head = ""
        if let limit, lines.count > max(0, limit) {
            let left = lines.count - max(0, limit)
            lines = Array(lines.suffix(max(0, limit)))
            head = "(\(left) earlier \(left == 1 ? "line" : "lines") left out)\n"
        }
        return head + lines.map { $0 + "\n" }.joined()
    }

    private struct MacFile: Encodable {
        var model: String
        var macos: String
        var tactileVersion: String
        var tactileBuild: String
        var displays: Int

        init(_ mac: SupportMac) {
            model = mac.model
            macos = mac.macOS
            tactileVersion = mac.tactileVersion
            tactileBuild = mac.tactileBuild
            displays = mac.displays
        }
    }

    private struct ManifestFile: Encodable {
        var schema: Int
        var files: [String: String]
    }

    // MARK: - summary.txt

    private static func summary(_ input: SupportReportInput, numbers: [UInt64: Int]) -> String {
        let device = input.device
        let product = clean(device.product, input).isEmpty ? "A USB device" : clean(device.product, input)
        let maker = clean(device.manufacturer, input)
        var lines = ["Tactile’s touchscreen check", ""]
        let kind: String
        switch device.kind {
        case .touchscreen: kind = "a touchscreen"
        case .digitizer: kind = "a digitiser Tactile doesn’t list"
        case .mouseOnly: kind = "a touchscreen that is only a mouse"
        }
        lines.append("\(product) (\(device.usbID))\(maker.isEmpty ? "" : ", made by \(maker)"): \(kind).")
        lines.append("Verdict: \(verdictText(input.verdict)). \(reasonText(input.verdictReason))")
        switch input.interruption {
        case .notConnected?: lines.append("The check stopped: it wasn’t connected when the check began.")
        case .unplugged?: lines.append("The check stopped: it was unplugged.")
        case .stopped?: lines.append("The check was stopped before its end.")
        case nil: break
        }

        lines += ["", "1. What it is"]
        for interface in input.identity.interfaces {
            let number = numbers[interface.id] ?? 0
            var parts: [String] = []
            let usages = interface.usages.isEmpty ? interface.summary?.applicationCollections ?? [] : interface.usages
            parts.append(usages.isEmpty ? "no usages listed" : usages.map(usageName).joined(separator: ", "))
            if let fingers = interface.decoded?.fingerCollections, fingers > 0 {
                parts.append("\(fingers) finger \(fingers == 1 ? "collection" : "collections")")
            }
            if let descriptor = interface.descriptor {
                parts.append("\(descriptor.count)-byte descriptor")
                if interface.decoded == nil { parts.append("Tactile can’t read it") }
            } else {
                parts.append("no descriptor")
            }
            lines.append("Interface \(number) (\(interface.role.rawValue)): \(parts.joined(separator: "; ")).")
        }
        if let touch = input.identity.touch?.summary {
            if !touch.featureReports.isEmpty {
                let reports = touch.featureReports.map { String(format: "0x%02X", $0.id) + " (\($0.length) bytes)" }
                lines.append("Its touch interface’s feature reports: \(reports.joined(separator: ", ")).")
            }
            lines.append(touch.inputModeReportID.map { "Input Mode: in feature report " + String(format: "0x%02X", $0) + "." }
                ?? "No Input Mode setting.")
        }

        lines += ["", "2. Switches"]
        if let switches = input.switches {
            if device.kind == .mouseOnly {
                lines.append("Skipped: it is only a mouse, so there is nothing to read or switch.")
            } else if device.touchInterface == nil {
                lines.append("Skipped: Tactile can’t tell which interface takes touches, so it read and switched nothing.")
            }
            for open in switches.opens {
                let number = numbers[open.interface] ?? 0
                let held: String
                switch open.held {
                case .exclusively:
                    held = "held exclusively"
                case .shared:
                    held = "held shared (exclusive: IOReturn \(SupportSwitches.ioReturnText(open.exclusiveResult)))"
                case .notOpened:
                    held = "not opened (exclusive: IOReturn \(SupportSwitches.ioReturnText(open.exclusiveResult)); "
                        + "shared: IOReturn \(SupportSwitches.ioReturnText(open.sharedResult ?? 0)))"
                }
                lines.append("Interface \(number) (\(open.role.rawValue)): \(held).")
            }
            for read in switches.reads {
                var line = "Read feature report " + String(format: "0x%02X", read.reportID)
                    + " (\(read.contents.joined(separator: ", "))): \(read.lengthAsked) bytes asked, \(read.lengthReturned) returned in "
                    + String(format: "%.3f", read.seconds) + " s, IOReturn \(SupportSwitches.ioReturnText(read.result))."
                if read.timedOut { line += " It timed out, so no more were read." }
                lines.append(line)
            }
            if let maximum = input.contactCountMaximum { lines.append("Contact Count Maximum: \(maximum).") }
            if device.touchInterface != nil {
                switch switches.hasInputMode {
                case true?:
                    if let write = switches.inputModeWrite {
                        lines.append("Wrote Input Mode 2 (multi-touch): IOReturn \(SupportSwitches.ioReturnText(write.result)).")
                    }
                    if let back = input.writeBack {
                        lines.append("Wrote Input Mode 0 (mouse emulation) back at the end: IOReturn \(SupportSwitches.ioReturnText(back.result)).")
                    }
                case false?:
                    lines.append("No Input Mode setting: nothing written.")
                case nil:
                    lines.append("Input Mode wasn’t asked: the touch interface couldn’t be opened.")
                }
            }
        } else {
            lines.append("Not made: it wasn’t connected when the check began.")
        }

        lines += ["", "3. Touches"]
        if input.steps.isEmpty { lines.append("None.") }
        for step in input.steps {
            let name: String
            switch step.fingers {
            case .one: name = "One finger"
            case .two: name = "Two fingers"
            case .five: name = "Five fingers"
            }
            let ending: String
            switch step.ending {
            case .done?: ending = "done"
            case .timeUp?: ending = "time up"
            case .skipped?: ending = "skipped"
            case .stopped?: ending = "stopped"
            case nil: ending = "under way"
            }
            var line = "\(name): \(ending) after " + String(format: "%.1f", step.seconds) + " s. "
            if step.reportsSeen == 0 {
                line += "No reports."
            } else {
                line += "\(step.reportsSeen) \(step.reportsSeen == 1 ? "report" : "reports"); "
                switch step.mostFingers {
                case 0: line += "no finger read."
                case 1: line += "1 finger at once; "
                default: line += "up to \(step.mostFingers) fingers at once; "
                }
                if step.mostFingers > 0 {
                    line += step.mostFingersFromTouchInterface > 0 ? "read from the touch interface." : "read from the mouse interface."
                }
            }
            lines.append(line)
        }

        lines += ["", "4. Verdict: \(verdictText(input.verdict)).", ""]
        let mac = input.mac
        lines.append("Tactile \(mac.tactileVersion) (\(mac.tactileBuild)) on macOS \(mac.macOS), \(mac.model), "
                     + "\(mac.displays) \(mac.displays == 1 ? "display" : "displays").")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func verdictText(_ verdict: SupportVerdict) -> String {
        switch verdict {
        case .worksFully: return "works fully"
        case .worksWithOneFinger: return "works with one finger"
        case .doesNotWork: return "doesn’t work"
        }
    }

    private static func reasonText(_ reason: SupportVerdictReason) -> String {
        switch reason {
        case .severalFingersFromTouchInterface: return "Several fingers at once came through its touch interface."
        case .oneFingerFromTouchInterface: return "One finger at a time came through its touch interface."
        case .oneFingerFromMouseInterface: return "It sends one finger, as a mouse."
        case .reportsNotReadable: return "Its reports came, but Tactile couldn’t read a touch from them."
        case .noReports: return "Nothing came from it."
        }
    }

    private static func usageName(_ usage: DescriptorSummary.Collection) -> String {
        switch (usage.page, usage.usage) {
        case (0x0D, 0x01): return "Digitizer"
        case (0x0D, 0x02): return "Pen"
        case (0x0D, 0x04): return "Touch Screen"
        case (0x0D, 0x05): return "Touch Pad"
        case (0x0D, 0x0E): return "Device Configuration"
        case (0x01, 0x01): return "Pointer"
        case (0x01, 0x02): return "Mouse"
        case (0x01, 0x06): return "Keyboard"
        case (0xFF00...0xFFFF, _): return "vendor-defined"
        default: return usageText(usage)
        }
    }
}
