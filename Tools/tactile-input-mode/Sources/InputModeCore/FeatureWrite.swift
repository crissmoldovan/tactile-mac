// What this tool may write, and nothing else.
//
// The rule: a write goes only to a touchscreen interface (Digitizer / Touch Screen, 0x0D/0x04), only
// as a feature report that interface's own descriptor declares, and only when every field in that
// report is one of the standard digitizer settings below, with a value inside its declared range
// that also fits the field's bits. Nothing is ever written to a mouse or vendor-defined interface,
// and no output report is ever sent.
//
// A PlannedFeatureWrite can only be made here, so the IOKit side cannot send bytes that were not
// checked against the descriptor.

import Foundation

/// The standard digitizer features a host writes to switch a panel (Windows and Linux's
/// hid-multitouch write these). Latency Mode is deliberately not here: no method needs it.
public enum DigitizerSetting: UInt16, CaseIterable, Sendable, CustomStringConvertible {
    case inputMode = 0x52
    case deviceIndex = 0x53
    case surfaceSwitch = 0x57
    case buttonSwitch = 0x58

    public var usage: HIDUsage { HIDUsage(0x0D, rawValue) }

    public var description: String {
        switch self {
        case .inputMode: return "Input Mode"
        case .deviceIndex: return "Device Index"
        case .surfaceSwitch: return "Surface Switch"
        case .buttonSwitch: return "Button Switch"
        }
    }

    /// The value used when the caller gives none. Device Index 0 means "all collections"
    /// (Microsoft); the switches on are what Linux writes at probe.
    var defaultValue: Int? {
        switch self {
        case .inputMode: return nil
        case .deviceIndex: return 0
        case .surfaceSwitch, .buttonSwitch: return 1
        }
    }

    init?(usage: HIDUsage) {
        guard usage.page == 0x0D, let setting = DigitizerSetting(rawValue: usage.id) else { return nil }
        self = setting
    }
}

public enum InterfaceRole: String, Sendable {
    case touchscreen, mouse, vendor, other

    public init(primaryUsagePage: Int, primaryUsage: Int) {
        switch (primaryUsagePage, primaryUsage) {
        case (0x0D, 0x04): self = .touchscreen
        case (0x01, 0x01), (0x01, 0x02): self = .mouse
        case (0xFF00...0xFFFF, _): self = .vendor
        default: self = .other
        }
    }
}

public enum WriteRefusal: Error, Equatable, CustomStringConvertible {
    case notATouchscreenInterface(InterfaceRole)
    case noTouchScreenCollection
    case reportNotDeclared(UInt8)
    case fieldNotAllowed(HIDUsage)
    case arrayField(UInt8)
    case noValue(DigitizerSetting)
    case valueOutOfRange(DigitizerSetting, value: Int, min: Int, max: Int)
    case valueTooWide(DigitizerSetting, value: Int, bits: Int)
    case notInReport(DigitizerSetting, UInt8)

    public var description: String {
        switch self {
        case .notATouchscreenInterface(let role):
            return "refused: only a touchscreen interface is ever written, and this is a \(role.rawValue) interface"
        case .noTouchScreenCollection:
            return "refused: the descriptor has no Touch Screen (0x0D/0x04) collection"
        case .reportNotDeclared(let id):
            return String(format: "refused: the descriptor declares no feature report 0x%02X", id)
        case .fieldNotAllowed(let usage):
            return "refused: the report also holds \(usage), which is not a standard digitizer setting this tool writes"
        case .arrayField(let id):
            return String(format: "refused: feature report 0x%02X holds an array field", id)
        case .noValue(let setting):
            return "refused: no value given for \(setting)"
        case .valueOutOfRange(let setting, let value, let min, let max):
            return "refused: \(setting) \(value) is outside the declared range \(min)...\(max)"
        case .valueTooWide(let setting, let value, let bits):
            return "refused: \(setting) \(value) does not fit its \(bits)-bit field"
        case .notInReport(let setting, let id):
            return String(format: "refused: feature report 0x%02X holds no \(setting)", id)
        }
    }
}

public struct PlannedFeatureWrite: Equatable, Sendable {
    public struct Setting: Equatable, Sendable {
        public let setting: DigitizerSetting
        public let value: Int
    }
    public let reportID: UInt8
    /// The whole report as sent with SET_REPORT, starting with the report ID when IDs are used.
    public let bytes: [UInt8]
    public let settings: [Setting]

    public var summary: String {
        let list = settings.map { "\($0.setting) \($0.value)" }.joined(separator: ", ")
        return String(format: "feature report 0x%02X = ", reportID) + hexBytes(bytes) + " (\(list))"
    }
}

public func hexBytes(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined(separator: " ") }

public enum FeatureWritePlanner {
    public static func plan(role: InterfaceRole, descriptor: HIDDescriptor, reportID: UInt8,
                            values: [DigitizerSetting: Int]) throws -> PlannedFeatureWrite {
        guard role == .touchscreen else { throw WriteRefusal.notATouchscreenInterface(role) }
        guard descriptor.applications.contains(Usages.touchScreen) else { throw WriteRefusal.noTouchScreenCollection }
        let fields = descriptor.fields(.feature, reportID)
        guard !fields.isEmpty, descriptor.usesReportIDs || reportID == 0 else { throw WriteRefusal.reportNotDeclared(reportID) }

        let length = descriptor.reportLength(.feature, reportID)
        var report = [UInt8](repeating: 0, count: length)
        let dataStart = descriptor.usesReportIDs ? 1 : 0
        if descriptor.usesReportIDs { report[0] = reportID }
        var settings: [PlannedFeatureWrite.Setting] = []

        for field in fields where !field.isConstant {
            guard field.isVariable else { throw WriteRefusal.arrayField(reportID) }
            for element in 0..<field.count {
                guard let usage = field.usage(at: element), let setting = DigitizerSetting(usage: usage) else {
                    throw WriteRefusal.fieldNotAllowed(field.usage(at: element) ?? HIDUsage(0, 0))
                }
                guard let value = values[setting] ?? setting.defaultValue else { throw WriteRefusal.noValue(setting) }
                guard value >= field.logicalMin, value <= field.logicalMax else {
                    throw WriteRefusal.valueOutOfRange(setting, value: value, min: field.logicalMin, max: field.logicalMax)
                }
                guard fits(value, bits: field.bitSize, signed: field.logicalMin < 0) else {
                    throw WriteRefusal.valueTooWide(setting, value: value, bits: field.bitSize)
                }
                let start = dataStart * 8 + field.bitOffset + element * field.bitSize
                let raw = UInt64(bitPattern: Int64(value))
                for bit in 0..<field.bitSize where raw & (1 << UInt64(bit)) != 0 {
                    report[(start + bit) / 8] |= 1 << UInt8((start + bit) % 8)
                }
                settings.append(.init(setting: setting, value: value))
            }
        }
        for setting in values.keys where !settings.contains(where: { $0.setting == setting }) {
            throw WriteRefusal.notInReport(setting, reportID)
        }
        return PlannedFeatureWrite(reportID: reportID, bytes: report, settings: settings)
    }

    /// Whether a value can be sent in a field of this many bits without losing any of them.
    static func fits(_ value: Int, bits: Int, signed: Bool) -> Bool {
        guard bits > 0 else { return false }
        if bits >= 63 { return true }
        if signed {
            let half = 1 << (bits - 1)
            return value >= -half && value < half
        }
        return value >= 0 && value < (1 << bits)
    }

    /// The feature report holding Input Mode. Linux writes the first one it finds; so does this.
    public static func inputModeReport(in descriptor: HIDDescriptor) -> UInt8? {
        descriptor.reports(.feature, containing: Usages.inputMode).first
    }

    /// The feature reports holding a Surface Switch or a Button Switch.
    public static func switchReports(in descriptor: HIDDescriptor) -> [UInt8] {
        Array(Set(descriptor.reports(.feature, containing: Usages.surfaceSwitch)
            + descriptor.reports(.feature, containing: Usages.buttonSwitch))).sorted()
    }
}
