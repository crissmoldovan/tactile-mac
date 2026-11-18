// Everything tactile-probe writes as JSON. The README documents these types field by field;
// keep the two in step. A key that is absent means "not applicable" or "the panel has no such field".

import Foundation

let toolName = "tactile-probe"
let toolVersion = "1.1.0"

struct Point: Codable, Equatable { let x: Double; let y: Double }
struct Size: Codable, Equatable { let width: Double; let height: Double }
struct IntSize: Codable, Equatable { let width: Int; let height: Int }

// MARK: - Environment

struct EnvironmentInfo: Codable {
    let tool: String
    let toolVersion: String
    let macOSVersion: String
    let macOSBuild: String?
    let hardwareModel: String?
    let date: String
    /// IOHIDCheckAccess(listen) for this process, which macOS attributes to the terminal app:
    /// "granted", "denied" or "unknown" (never asked).
    let inputMonitoring: String
    /// AXIsProcessTrusted() for this process (the terminal app).
    let accessibility: Bool
    let terminal: String?
}

// MARK: - list

struct ListData: Codable {
    let environment: EnvironmentInfo
    let displays: [DisplayInfo]
    let touchscreens: [TouchscreenInfo]
}

struct MirroringInfo: Codable, Equatable {
    let inMirrorSet: Bool
    let mirrorsDisplayID: UInt32?
    let alwaysInMirrorSet: Bool
    let primaryDisplayID: UInt32
}

struct DisplayInfo: Codable, Equatable {
    let displayID: UInt32
    let name: String?
    let vendorNumber: UInt32
    let modelNumber: UInt32
    let serialNumber: UInt32
    let uuid: String?
    let physicalSizeMM: Size
    let pixelSize: IntSize?
    let pointSize: Size
    let rotationDegrees: Double
    let origin: Point
    let builtIn: Bool
    let main: Bool
    let active: Bool
    let asleep: Bool
    let refreshRateHz: Double?
    let backingScaleFactor: Double?
    let mirroring: MirroringInfo
}

struct UsageInfo: Codable {
    let page: Int
    let usage: Int
    let text: String
    let name: String?

    init(_ u: Usage) {
        page = Int(u.page)
        usage = Int(u.id)
        text = u.text
        name = usageName(u)
    }
}

struct USBNode: Codable {
    let registryName: String?
    let className: String?
    let productName: String?
    let vendorName: String?
    let usbID: String?
    let locationID: String?
    let serialNumber: String?
    let deviceClass: Int?
    let speed: String?
}

struct ReportInfo: Codable {
    let type: ReportType
    let id: Int
    let idHex: String
    /// Bytes on the wire, including the report ID byte when the interface uses IDs.
    let bytes: Int
    /// Input reports only: "touch", "pointer" or "other" (see the README).
    let decodedAs: String?
    let fingerSlots: Int?
}

struct FeatureReportRaw: Codable {
    let id: Int
    let idHex: String
    /// What the descriptor puts in this report, e.g. ["Contact Count Maximum"].
    let contains: [String]
    let ioReturn: String
    let length: Int?
    /// The bytes GET_REPORT returned, as hex. The first byte is the report ID when the interface uses IDs.
    let bytes: String?
    /// False when the interface uses report IDs but the answer does not start with this one: the
    /// panel's answer is malformed, and IOKit's value for the report is a cached default, not a reading.
    let startsWithReportID: Bool?
}

struct InterfaceInfo: Codable {
    let key: String
    let role: String
    let primaryUsage: UsageInfo
    let topLevelUsages: [UsageInfo]
    let usesReportIDs: Bool
    let reports: [ReportInfo]
    let maxInputReportSize: Int?
    let maxOutputReportSize: Int?
    let maxFeatureReportSize: Int?
    let reportDescriptor: String?
    let reportDescriptorLength: Int?
    let featureReports: [FeatureReportRaw]
    let parserCheck: String
    let parserWarnings: [String]
}

struct FieldPresence: Codable {
    let present: Bool
    /// For per-finger fields: how many finger collections carry it.
    let slots: Int?
    let bits: Int?
    let logicalMin: Int64?
    let logicalMax: Int64?
}

struct FingerFieldsInfo: Codable {
    let tipSwitch: FieldPresence
    let inRange: FieldPresence
    let confidence: FieldPresence
    let contactID: FieldPresence
    let width: FieldPresence
    let height: FieldPresence
    let azimuth: FieldPresence
    let pressure: FieldPresence
}

struct AxisInfo: Codable {
    let bits: Int
    let logicalMin: Int64
    let logicalMax: Int64
    let physicalMin: Int64
    let physicalMax: Int64
    let unit: String
    let unitName: String
    let exponent: Int
    let sizeMM: Double?
}

struct FeatureValue: Codable {
    let present: Bool
    let reportID: Int?
    let value: Int?
    let logicalMax: Int64?
    let ioReturn: String?
    let rawReport: String?
    /// Whether `value` really came from the panel (see FeatureReportRaw.startsWithReportID).
    let valueTrusted: Bool?
}

struct InputModeInfo: Codable {
    let present: Bool
    let reportID: Int?
    let value: Int?
    let valueName: String?
    let ioReturn: String?
    let deviceIndexPresent: Bool
    let rawReport: String?
    let valueTrusted: Bool?
}

struct TouchInterfaceInfo: Codable {
    let interfaceKey: String
    let inputReportID: Int?
    let inputReportBytes: Int?
    let fingerCollections: Int
    let contactCountMaximum: FeatureValue
    let hybridModeWouldApply: Bool?
    let inputMode: InputModeInfo
    let x: AxisInfo?
    let y: AxisInfo?
    let surfaceSizeMM: Size?
    let fingerFields: FingerFieldsInfo
    let contactCount: FieldPresence
    let scanTime: FieldPresence
}

struct TouchscreenInfo: Codable {
    let number: Int
    let product: String?
    let manufacturer: String?
    let vendorID: Int
    let productID: Int
    let usbID: String
    let serialNumber: String?
    let versionNumber: Int?
    let transport: String?
    let locationID: String
    let usbDevice: USBNode?
    let usbHubs: [USBNode]
    let usbController: String?
    let interfaces: [InterfaceInfo]
    let touchInterface: TouchInterfaceInfo?
    let mouseInterfaceKey: String?
}

// MARK: - survey

struct SurveySettings: Codable {
    let stepTimeoutSeconds: Double
    let takeLimitSeconds: Double
    let liftQuietSeconds: Double
    let quietWithContactsDownSeconds: Double
    /// Since 1.1.0: the arguments after `survey`, as typed.
    var arguments: [String]? = nil
    /// Since 1.1.0: the take numbers this run was asked for (`--from`, `--only`, or all).
    var takesSelected: [Int]? = nil
}

struct SurveyFile: Codable {
    let format: String
    let formatVersion: Int
    let environment: EnvironmentInfo
    let settings: SurveySettings
    let list: ListData
    var conflictingApps: [String]
    var touchscreens: [TouchscreenSurvey]
    var restore: [ActionRecord]
    var completed: Bool
    var interrupted: Bool
    var endedBecause: String
}

struct DisplayChoice: Codable {
    let number: Int
    let displayID: UInt32
    let name: String?
}

struct DisplayAnswer: Codable {
    /// What the person typed, at the survey's question or as `--display`; "" means not sure, or
    /// (with `source` "state file") nothing typed.
    let answer: String
    let displayID: UInt32?
    let name: String?
    /// The numbered list the question offered; empty when no question was asked.
    let choices: [DisplayChoice]
    /// Since 1.1.0: where the display came from. Absent in older files, where it is always the question.
    var source: DisplaySource? = nil
}

struct ActionRecord: Codable {
    /// "input mode write", "input mode restore", "exclusive open", "exclusive close", "shared reopen".
    let kind: String
    let touchscreen: String
    let interface: String
    /// The take this action came right before (or after, for closes and restores).
    let take: String?
    let ioReturn: String
    let ok: Bool
    let value: Int?
    let readBack: Int?
    /// The whole feature report read back after the action, as hex, when there was one to read.
    let featureReport: String?
    /// Whether `readBack` really came from the panel; false when its raw answer is malformed.
    let readBackTrusted: Bool?
    let note: String?
}

/// The survey file as written: pretty-printed, keys sorted, no escaped slashes.
func encodeSurvey(_ file: SurveyFile) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(file)
}

struct TouchscreenSurvey: Codable {
    let number: Int
    let locationID: String
    let name: String
    var identifiedBy: String
    var status: String
    var display: DisplayAnswer?
    var inputModeFound: Int?
    var inputModeFoundName: String?
    var inputModeFoundTrusted: Bool?
    var inputModeFoundRaw: String?
    var actions: [ActionRecord]
    var takes: [Take]
}

struct PointerRecord: Codable {
    let from: Point?
    let to: Point?
    let moved: Bool
    let maxDistance: Double
    let endDisplayID: UInt32?
    let endDisplayName: String?
    /// [seconds since the prompt, x, y], one entry each time the position changed.
    let samples: [[Double]]
}

struct NormPoint: Codable { let x: Double; let y: Double }

struct TapMedian: Codable {
    let touch: NormPoint?
    let touchSamples: Int
    let mouse: NormPoint?
    let mouseSamples: Int
}

struct TakeFacts: Codable {
    let interfacesReporting: [String]
    let reportRateHz: [String: Double]
    let contactIDsSeen: [Int]
    let maxContactsDown: Int
    let maxContactCountField: Int?
    let fingersChangeSlots: Bool?
    let slotChanges: Int
    let liftedWithTipUpReport: Int
    let liftedWithoutTipUpReport: Int
    let stillDownAtEnd: Int
    /// "every contact", "none", "some", or absent when no touch report was seen.
    let finalTipUp: String?
    let lastTouchReportHadNoContacts: Bool?
    let hybridObserved: Bool
    let touchFramesSplitAcrossReports: Int
    let mouseButtonsSeen: Int?
    let mouseButtonReleased: Bool?
}

struct FingerRecord: Codable {
    let slot: Int
    let id: Int?
    let tip: Bool?
    let x: Double?
    let y: Double?
    let rawX: Int?
    let rawY: Int?
    let inRange: Bool?
    let confidence: Int?
    let width: Int?
    let height: Int?
    let pressure: Int?
    let azimuth: Int?
}

struct PointerReport: Codable {
    let buttons: Int?
    let x: Double?
    let y: Double?
    let rawX: Int?
    let rawY: Int?
    let dx: Int?
    let dy: Int?
    let wheel: Int?
    let tip: Bool?
    let inRange: Bool?
}

struct RecordedReport: Codable {
    let t: Double
    let hostTimeNs: UInt64
    let interface: String
    let reportID: Int
    let length: Int
    let bytes: String
    let contactCount: Int?
    let scanTime: Int?
    let fingers: [FingerRecord]?
    let pointer: PointerReport?
}

struct Take: Codable {
    let id: String
    let number: Int
    let title: String
    let prompt: String
    let mode: String
    let inputMode: Int?
    let exclusiveInterfaces: [String]
    let attempt: Int
    var result: String
    var endReason: String?
    var summary: String
    var promptedAtNs: UInt64
    var startedAtNs: UInt64?
    var endedAtNs: UInt64?
    var waitedSeconds: Double?
    var durationSeconds: Double?
    var reportSpanSeconds: Double?
    var reportCounts: [String: Int]
    var otherTouchscreenReports: Int
    var staleReportsDiscarded: Int
    var pointer: PointerRecord?
    var facts: TakeFacts?
    var tap: TapMedian?
    var reports: [RecordedReport]
}
