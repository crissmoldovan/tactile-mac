// A small HID report descriptor parser: enough to know which reports an interface declares, which
// fields each holds, where they sit, and what values they allow. It is the basis of the rule that
// nothing is written that the panel's own descriptor does not declare.

import Foundation

public struct HIDUsage: Hashable, Sendable, CustomStringConvertible {
    public let page: UInt16
    public let id: UInt16
    public init(_ page: UInt16, _ id: UInt16) { self.page = page; self.id = id }
    public var isVendorDefined: Bool { page >= 0xFF00 }
    public var description: String {
        if let name = Usages.names[self] { return name }
        return String(format: "0x%02X/0x%02X", page, id)
    }
}

/// Usages this tool cares about.
public enum Usages {
    public static let pointer = HIDUsage(0x01, 0x01)
    public static let mouse = HIDUsage(0x01, 0x02)
    public static let button1 = HIDUsage(0x09, 0x01)
    public static let touchScreen = HIDUsage(0x0D, 0x04)
    public static let deviceConfiguration = HIDUsage(0x0D, 0x0E)
    public static let finger = HIDUsage(0x0D, 0x22)
    public static let deviceSettings = HIDUsage(0x0D, 0x23)
    public static let tipSwitch = HIDUsage(0x0D, 0x42)
    public static let contactID = HIDUsage(0x0D, 0x51)
    public static let inputMode = HIDUsage(0x0D, 0x52)
    public static let deviceIndex = HIDUsage(0x0D, 0x53)
    public static let contactCount = HIDUsage(0x0D, 0x54)
    public static let contactCountMaximum = HIDUsage(0x0D, 0x55)
    public static let surfaceSwitch = HIDUsage(0x0D, 0x57)
    public static let buttonSwitch = HIDUsage(0x0D, 0x58)
    public static let latencyMode = HIDUsage(0x0D, 0x60)
    /// The 256-byte "Windows 8 certified" blob some panels declare (Linux reads it once at probe).
    public static let certificationBlob = HIDUsage(0xFF00, 0xC5)

    static let names: [HIDUsage: String] = [
        pointer: "Pointer (0x01/0x01)", mouse: "Mouse (0x01/0x02)", touchScreen: "Touch Screen (0x0D/0x04)",
        deviceConfiguration: "Device Configuration (0x0D/0x0E)", finger: "Finger (0x0D/0x22)",
        deviceSettings: "Device Settings (0x0D/0x23)", tipSwitch: "Tip Switch (0x0D/0x42)",
        contactID: "Contact ID (0x0D/0x51)", inputMode: "Input Mode (0x0D/0x52)", deviceIndex: "Device Index (0x0D/0x53)",
        contactCount: "Contact Count (0x0D/0x54)", contactCountMaximum: "Contact Count Maximum (0x0D/0x55)",
        surfaceSwitch: "Surface Switch (0x0D/0x57)", buttonSwitch: "Button Switch (0x0D/0x58)",
        latencyMode: "Latency Mode (0x0D/0x60)", certificationBlob: "certification blob (0xFF00/0xC5)",
        HIDUsage(0x01, 0x30): "X (0x01/0x30)", HIDUsage(0x01, 0x31): "Y (0x01/0x31)", HIDUsage(0x01, 0x38): "Wheel (0x01/0x38)",
        HIDUsage(0x0D, 0x56): "Scan Time (0x0D/0x56)", button1: "Button 1 (0x09/0x01)",
        HIDUsage(0x09, 0x02): "Button 2 (0x09/0x02)", HIDUsage(0x09, 0x03): "Button 3 (0x09/0x03)",
    ]
}

public enum HIDReportKind: String, Sendable, CaseIterable { case input, output, feature }

/// One Input, Output or Feature main item: `count` elements of `bitSize` bits each.
public struct HIDField: Equatable, Sendable {
    public var kind: HIDReportKind
    /// 0 when the descriptor uses no report IDs.
    public var reportID: UInt8
    /// Bits from the start of the report's data, after the report ID byte.
    public var bitOffset: Int
    public var bitSize: Int
    public var count: Int
    public var usages: [HIDUsage]
    public var isConstant: Bool
    public var isVariable: Bool
    public var logicalMin: Int
    public var logicalMax: Int
    /// The top-level application collection the field belongs to.
    public var application: HIDUsage?

    /// The usage of one element. When there are fewer usages than elements, the last one repeats.
    public func usage(at element: Int) -> HIDUsage? {
        guard !usages.isEmpty, element >= 0 else { return nil }
        return usages[min(element, usages.count - 1)]
    }
}

public struct HIDDescriptorError: Error, Equatable, CustomStringConvertible {
    public let offset: Int
    public let reason: String
    public var description: String { "report descriptor byte \(offset): \(reason)" }
}

public struct HIDDescriptor: Equatable, Sendable {
    /// Limits as Linux's HID parser sets them: a malformed descriptor is an error, never a crash.
    static let maxReportSize: UInt32 = 256
    static let maxReportCount: UInt32 = 12_288
    static let maxReportBits = 16_384 * 8

    public let fields: [HIDField]
    public let usesReportIDs: Bool
    /// Top-level application collections, in order.
    public let applications: [HIDUsage]

    public init(_ bytes: [UInt8]) throws {
        struct Globals {
            var usagePage: UInt16 = 0
            var logicalMin = 0, logicalMax = 0, logicalMaxRaw = 0
            var reportSize = 0, reportCount = 0
            var reportID: UInt8 = 0
        }
        var globals = Globals()
        var stack: [Globals] = []
        // Local usages are kept raw and given their Usage Page at the main item, as the HID spec
        // says: the page in effect then, unless the usage carried its own (a four-byte usage).
        enum LocalUsage { case one(UInt32, Int), range(UInt32, Int, UInt32, Int) }
        var locals: [LocalUsage] = []
        var usageMin: (value: UInt32, size: Int)?
        var collections: [HIDUsage?] = []
        var application: HIDUsage?
        var applications: [HIDUsage] = []
        var usesIDs = false
        var offsets: [String: Int] = [:]
        var fields: [HIDField] = []

        func fullUsage(_ value: UInt32, size: Int, page: UInt16) -> HIDUsage {
            size == 4 ? HIDUsage(UInt16(value >> 16), UInt16(value & 0xFFFF)) : HIDUsage(page, UInt16(value & 0xFFFF))
        }

        func resolvedUsages(page: UInt16) -> [HIDUsage] {
            var out: [HIDUsage] = []
            for local in locals {
                switch local {
                case let .one(value, size):
                    out.append(fullUsage(value, size: size, page: page))
                case let .range(low, lowSize, high, highSize):
                    let first = fullUsage(low, size: lowSize, page: page)
                    let last = fullUsage(high, size: highSize, page: page)
                    if first.page == last.page, first.id <= last.id, Int(last.id) - Int(first.id) < 1024 {
                        for id in first.id...last.id { out.append(HIDUsage(last.page, id)) }
                    }
                }
            }
            if out.isEmpty, let low = usageMin { out = [fullUsage(low.value, size: low.size, page: page)] }
            return out
        }

        var i = 0
        while i < bytes.count {
            let prefix = bytes[i]
            if prefix == 0xFE {   // long item: skipped
                guard i + 2 < bytes.count else { throw HIDDescriptorError(offset: i, reason: "truncated long item") }
                i += 3 + Int(bytes[i + 1])
                continue
            }
            let size = [0, 1, 2, 4][Int(prefix & 0x03)]
            let type = (prefix >> 2) & 0x03
            let tag = prefix >> 4
            guard i + 1 + size <= bytes.count else { throw HIDDescriptorError(offset: i, reason: "truncated item") }
            var unsigned: UInt32 = 0
            for k in 0..<size { unsigned |= UInt32(bytes[i + 1 + k]) << (8 * k) }
            let signed: Int = {
                switch size {
                case 1: return Int(Int8(truncatingIfNeeded: unsigned))
                case 2: return Int(Int16(truncatingIfNeeded: unsigned))
                case 4: return Int(Int32(truncatingIfNeeded: unsigned))
                default: return 0
                }
            }()
            let at = i
            i += 1 + size

            switch type {
            case 0:   // main
                switch tag {
                case 0x8, 0x9, 0xB:
                    let kind: HIDReportKind = tag == 0x8 ? .input : (tag == 0x9 ? .output : .feature)
                    let key = "\(kind.rawValue)-\(globals.reportID)"
                    let offset = offsets[key] ?? 0
                    // Both are capped where they are set, so this cannot overflow.
                    let end = offset + globals.reportSize * globals.reportCount
                    guard end <= HIDDescriptor.maxReportBits else {
                        throw HIDDescriptorError(offset: at, reason: "a report longer than \(HIDDescriptor.maxReportBits / 8) bytes")
                    }
                    // Logical Maximum is unsigned unless the minimum is negative (as Linux reads it).
                    let max = globals.logicalMin < 0 ? globals.logicalMax : globals.logicalMaxRaw
                    fields.append(HIDField(kind: kind, reportID: globals.reportID, bitOffset: offset,
                                           bitSize: globals.reportSize, count: globals.reportCount,
                                           usages: resolvedUsages(page: globals.usagePage),
                                           isConstant: unsigned & 0x01 != 0, isVariable: unsigned & 0x02 != 0,
                                           logicalMin: globals.logicalMin, logicalMax: max, application: application))
                    offsets[key] = end
                    locals = []; usageMin = nil
                case 0xA:   // Collection
                    let usage = resolvedUsages(page: globals.usagePage).first
                    collections.append(usage)
                    if collections.count == 1, unsigned == 1, let usage {
                        application = usage
                        applications.append(usage)
                    }
                    locals = []; usageMin = nil
                case 0xC:   // End Collection
                    guard !collections.isEmpty else { throw HIDDescriptorError(offset: at, reason: "End Collection without a Collection") }
                    collections.removeLast()
                    if collections.isEmpty { application = nil }
                    locals = []; usageMin = nil
                default:
                    break
                }
            case 1:   // global
                switch tag {
                case 0x0: globals.usagePage = UInt16(truncatingIfNeeded: unsigned)
                case 0x1: globals.logicalMin = signed
                case 0x2: globals.logicalMax = signed; globals.logicalMaxRaw = Int(unsigned)
                case 0x7:
                    guard unsigned <= HIDDescriptor.maxReportSize else { throw HIDDescriptorError(offset: at, reason: "report size \(unsigned)") }
                    globals.reportSize = Int(unsigned)
                case 0x8:
                    guard unsigned > 0, unsigned <= 0xFF else { throw HIDDescriptorError(offset: at, reason: "report ID \(unsigned)") }
                    globals.reportID = UInt8(unsigned); usesIDs = true
                case 0x9:
                    guard unsigned <= HIDDescriptor.maxReportCount else { throw HIDDescriptorError(offset: at, reason: "report count \(unsigned)") }
                    globals.reportCount = Int(unsigned)
                case 0xA: stack.append(globals)
                case 0xB:
                    guard let top = stack.popLast() else { throw HIDDescriptorError(offset: at, reason: "Pop without Push") }
                    globals = top
                default: break   // physical range, units: not needed here
                }
            case 2:   // local
                switch tag {
                case 0x0: locals.append(.one(unsigned, size))
                case 0x1: usageMin = (unsigned, size)
                case 0x2:
                    if let low = usageMin {
                        locals.append(.range(low.value, low.size, unsigned, size))
                        usageMin = nil
                    }
                default: break
                }
            default:
                throw HIDDescriptorError(offset: at, reason: "reserved item type")
            }
        }
        guard collections.isEmpty else { throw HIDDescriptorError(offset: bytes.count, reason: "a Collection is never ended") }
        self.fields = fields
        self.usesReportIDs = usesIDs
        self.applications = applications
    }

    public func reportIDs(_ kind: HIDReportKind) -> [UInt8] {
        Array(Set(fields.filter { $0.kind == kind }.map(\.reportID))).sorted()
    }

    public func fields(_ kind: HIDReportKind, _ id: UInt8) -> [HIDField] {
        fields.filter { $0.kind == kind && $0.reportID == id }
    }

    /// The report's length in bytes, including the report ID byte when the descriptor uses IDs.
    public func reportLength(_ kind: HIDReportKind, _ id: UInt8) -> Int {
        let bits = fields(kind, id).reduce(0) { $0 + $1.bitSize * $1.count }
        return (bits + 7) / 8 + (usesReportIDs ? 1 : 0)
    }

    /// The IDs of the reports of this kind that hold a non-constant field with this usage.
    public func reports(_ kind: HIDReportKind, containing usage: HIDUsage) -> [UInt8] {
        let holding = fields.filter { field in
            field.kind == kind && !field.isConstant && (0..<max(field.count, 1)).contains { field.usage(at: $0) == usage }
        }
        return Array(Set(holding.map(\.reportID))).sorted()
    }

    /// Every element with this usage in one report.
    public func elements(_ kind: HIDReportKind, _ id: UInt8, usage: HIDUsage) -> [(field: HIDField, element: Int)] {
        fields(kind, id).filter { !$0.isConstant }.flatMap { field in
            (0..<field.count).filter { field.usage(at: $0) == usage }.map { (field, $0) }
        }
    }

    /// One element's value in a raw report (which starts with its report ID when IDs are used).
    /// Signed when the field's logical minimum is negative. nil when the report is too short.
    public func value(of field: HIDField, element: Int, in report: [UInt8]) -> Int? {
        let start = (usesReportIDs ? 8 : 0) + field.bitOffset + element * field.bitSize
        guard field.bitSize > 0, field.bitSize <= 32, start + field.bitSize <= report.count * 8 else { return nil }
        var raw: UInt64 = 0
        for bit in 0..<field.bitSize {
            let position = start + bit
            if report[position / 8] & (1 << UInt8(position % 8)) != 0 { raw |= 1 << UInt64(bit) }
        }
        if field.logicalMin < 0, raw & (1 << UInt64(field.bitSize - 1)) != 0 {
            return Int(Int64(bitPattern: raw | ~((1 << UInt64(field.bitSize)) - 1)))
        }
        return Int(raw)
    }
}
