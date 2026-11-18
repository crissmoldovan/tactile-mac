// A small HID report descriptor parser. It turns the descriptor bytes every HID interface
// publishes into a flat list of fields with their exact bit positions, so that a raw report can
// be decoded without relying on IOKit's element cache (which only reports values that changed).

import Foundation

struct Usage: Hashable, Comparable {
    let page: UInt32
    let id: UInt32

    static func < (a: Usage, b: Usage) -> Bool { (a.page, a.id) < (b.page, b.id) }
    var text: String { String(format: "0x%02X/0x%02X", page, id) }
}

enum Usages {
    static let touchScreen = Usage(page: 0x0D, id: 0x04)
    static let deviceConfiguration = Usage(page: 0x0D, id: 0x0E)
    static let finger = Usage(page: 0x0D, id: 0x22)
    static let tipPressure = Usage(page: 0x0D, id: 0x30)
    static let inRange = Usage(page: 0x0D, id: 0x32)
    static let azimuth = Usage(page: 0x0D, id: 0x3F)
    static let tipSwitch = Usage(page: 0x0D, id: 0x42)
    static let confidence = Usage(page: 0x0D, id: 0x47)
    static let width = Usage(page: 0x0D, id: 0x48)
    static let height = Usage(page: 0x0D, id: 0x49)
    static let contactID = Usage(page: 0x0D, id: 0x51)
    static let inputMode = Usage(page: 0x0D, id: 0x52)
    static let deviceIndex = Usage(page: 0x0D, id: 0x53)
    static let contactCount = Usage(page: 0x0D, id: 0x54)
    static let contactCountMaximum = Usage(page: 0x0D, id: 0x55)
    static let scanTime = Usage(page: 0x0D, id: 0x56)
    static let mouse = Usage(page: 0x01, id: 0x02)
    static let pointer = Usage(page: 0x01, id: 0x01)
    static let x = Usage(page: 0x01, id: 0x30)
    static let y = Usage(page: 0x01, id: 0x31)
    static let wheel = Usage(page: 0x01, id: 0x38)
    static let buttonPage: UInt32 = 0x09
}

/// A plain-words name for the usages this tool cares about.
func usageName(_ u: Usage) -> String? {
    switch (u.page, u.id) {
    case (0x01, 0x01): return "Pointer"
    case (0x01, 0x02): return "Mouse"
    case (0x01, 0x06): return "Keyboard"
    case (0x01, 0x30): return "X"
    case (0x01, 0x31): return "Y"
    case (0x01, 0x38): return "Wheel"
    case (0x0C, 0x01): return "Consumer Control"
    case (0x0D, 0x01): return "Digitizer"
    case (0x0D, 0x02): return "Pen"
    case (0x0D, 0x04): return "Touch Screen"
    case (0x0D, 0x05): return "Touch Pad"
    case (0x0D, 0x0E): return "Device Configuration"
    case (0x0D, 0x20): return "Stylus"
    case (0x0D, 0x22): return "Finger"
    case (0x0D, 0x30): return "Tip Pressure"
    case (0x0D, 0x32): return "In Range"
    case (0x0D, 0x3F): return "Azimuth"
    case (0x0D, 0x42): return "Tip Switch"
    case (0x0D, 0x47): return "Confidence"
    case (0x0D, 0x48): return "Width"
    case (0x0D, 0x49): return "Height"
    case (0x0D, 0x51): return "Contact Identifier"
    case (0x0D, 0x52): return "Input Mode"
    case (0x0D, 0x53): return "Device Index"
    case (0x0D, 0x54): return "Contact Count"
    case (0x0D, 0x55): return "Contact Count Maximum"
    case (0x0D, 0x56): return "Scan Time"
    case (0x09, _): return "Button \(u.id)"
    default:
        if u.page >= 0xFF00 { return "Vendor-defined" }
        return nil
    }
}

enum ReportType: String, Codable { case input, output, feature }

struct HIDCollectionInfo {
    let index: Int
    /// 0 physical, 1 application, 2 logical, 3 report, 4 named array, 5 usage switch, 6 usage modifier.
    let type: UInt32
    let usage: Usage
    let parent: Int?
}

struct HIDField {
    let type: ReportType
    /// 0 when the interface does not use report IDs.
    let reportID: Int
    /// Bit position inside the report, counted after the report ID byte.
    let bitOffset: Int
    let bitSize: Int
    let usage: Usage
    let constant: Bool
    let variable: Bool
    let relative: Bool
    let nullState: Bool
    let logicalMin: Int64
    let logicalMax: Int64
    let physicalMin: Int64
    let physicalMax: Int64
    let unit: UInt32
    let unitExponent: Int
    /// Innermost collection that contains the field.
    let collection: Int?

    var signed: Bool { logicalMin < 0 }

    /// Reads this field from report data that starts after the report ID byte.
    func value(in data: [UInt8]) -> Int64? {
        guard bitSize > 0, bitSize <= 64, (bitOffset + bitSize + 7) / 8 <= data.count else { return nil }
        var v: UInt64 = 0
        for b in 0..<bitSize {
            let bit = bitOffset + b
            if data[bit >> 3] & (1 << UInt8(bit & 7)) != 0 { v |= (1 << UInt64(b)) }
        }
        if signed, bitSize < 64, v & (1 << UInt64(bitSize - 1)) != 0 { v |= ~UInt64(0) << UInt64(bitSize) }
        return Int64(bitPattern: v)
    }

    /// The value placed on 0…1 across the logical range.
    func normalised(_ raw: Int64) -> Double? {
        guard logicalMax != logicalMin else { return nil }
        return Double(raw - logicalMin) / Double(logicalMax - logicalMin)
    }
}

final class ParsedDescriptor {
    var collections: [HIDCollectionInfo] = []
    var fields: [HIDField] = []
    var usesReportIDs = false
    /// Bits used by each report, keyed by type then report ID (report ID byte not included).
    var reportBits: [ReportType: [Int: Int]] = [:]
    var warnings: [String] = []

    func reportIDs(_ type: ReportType) -> [Int] { (reportBits[type] ?? [:]).keys.sorted() }

    /// Size in bytes as it travels over USB, including the report ID byte when IDs are used.
    func reportBytes(_ type: ReportType, _ id: Int) -> Int {
        let bits = reportBits[type]?[id] ?? 0
        return (bits + 7) / 8 + (usesReportIDs ? 1 : 0)
    }

    /// Top-level (application) collections, in descriptor order.
    var applicationUsages: [Usage] {
        collections.filter { $0.parent == nil && $0.type == 1 }.map(\.usage)
    }

    /// The collection directly below the outermost application collection that contains
    /// `collection`, which is how a finger's fields are grouped together.
    func slotCollection(of collection: Int?) -> Int? {
        guard var current = collection else { return nil }
        var chain = [current]
        while let parent = collections[current].parent {
            chain.append(parent)
            current = parent
        }
        guard let appPosition = chain.lastIndex(where: { collections[$0].type == 1 }) else { return chain.last }
        return appPosition > 0 ? chain[appPosition - 1] : nil
    }

    /// The application collection that contains `collection`.
    func applicationCollection(of collection: Int?) -> Int? {
        guard var current = collection else { return nil }
        var outermostApplication: Int? = collections[current].type == 1 ? current : nil
        while let parent = collections[current].parent {
            current = parent
            if collections[current].type == 1 { outermostApplication = current }
        }
        return outermostApplication
    }
}

enum DescriptorParser {
    private struct Globals {
        var usagePage: UInt32 = 0
        var logicalMin: (UInt32, Int) = (0, 0)
        var logicalMax: (UInt32, Int) = (0, 0)
        var physicalMin: (UInt32, Int) = (0, 0)
        var physicalMax: (UInt32, Int) = (0, 0)
        var unitExponent: Int = 0
        var unit: UInt32 = 0
        var reportSize: Int = 0
        var reportID: Int = 0
        var reportCount: Int = 0
    }

    private static func signedValue(_ raw: (UInt32, Int)) -> Int64 {
        switch raw.1 {
        case 1: return Int64(Int8(truncatingIfNeeded: raw.0))
        case 2: return Int64(Int16(truncatingIfNeeded: raw.0))
        case 4: return Int64(Int32(bitPattern: raw.0))
        default: return 0
        }
    }

    /// A minimum below zero makes the range signed; otherwise both ends are read unsigned, which
    /// keeps a maximum such as 0xFFFF from turning into -1.
    private static func range(_ minRaw: (UInt32, Int), _ maxRaw: (UInt32, Int)) -> (Int64, Int64) {
        let signedMin = signedValue(minRaw)
        if signedMin < 0 { return (signedMin, signedValue(maxRaw)) }
        return (Int64(minRaw.0), Int64(maxRaw.0))
    }

    static func parse(_ bytes: [UInt8]) -> ParsedDescriptor {
        let result = ParsedDescriptor()
        var globals = Globals()
        var globalStack: [Globals] = []
        var usages: [Usage] = []
        var usageMin: Usage?
        var usageMax: Usage?
        var collectionStack: [Int] = []
        var offsets: [ReportType: [Int: Int]] = [:]

        func clearLocals() { usages = []; usageMin = nil; usageMax = nil }

        var i = 0
        while i < bytes.count {
            let prefix = bytes[i]
            if prefix == 0xFE { // long item: skip it
                guard i + 1 < bytes.count else { break }
                i += 3 + Int(bytes[i + 1])
                continue
            }
            let sizeCode = Int(prefix & 0x03)
            let size = sizeCode == 3 ? 4 : sizeCode
            let type = (prefix >> 2) & 0x03
            let tag = (prefix >> 4) & 0x0F
            guard i + 1 + size <= bytes.count else {
                result.warnings.append("descriptor ends in the middle of an item at byte \(i)")
                break
            }
            var raw: UInt32 = 0
            for k in 0..<size { raw |= UInt32(bytes[i + 1 + k]) << UInt32(8 * k) }
            i += 1 + size

            switch type {
            case 0: // main
                switch tag {
                case 0x8, 0x9, 0xB:
                    let reportType: ReportType = tag == 0x8 ? .input : (tag == 0x9 ? .output : .feature)
                    var list = usages
                    if let low = usageMin, let high = usageMax, high.id >= low.id {
                        let top = min(high.id, low.id + 4095)
                        list += (low.id...top).map { Usage(page: low.page, id: $0) }
                    }
                    let (lmin, lmax) = range(globals.logicalMin, globals.logicalMax)
                    let (pmin, pmax) = range(globals.physicalMin, globals.physicalMax)
                    let variable = raw & 0x02 != 0
                    var offset = offsets[reportType]?[globals.reportID] ?? 0
                    for n in 0..<max(globals.reportCount, 0) {
                        let usage: Usage
                        if list.isEmpty { usage = Usage(page: 0, id: 0) }
                        else if variable { usage = list[min(n, list.count - 1)] }
                        else { usage = list[0] }
                        result.fields.append(HIDField(
                            type: reportType, reportID: globals.reportID, bitOffset: offset, bitSize: globals.reportSize,
                            usage: usage, constant: raw & 0x01 != 0, variable: variable, relative: raw & 0x04 != 0,
                            nullState: raw & 0x40 != 0, logicalMin: lmin, logicalMax: lmax, physicalMin: pmin,
                            physicalMax: pmax, unit: globals.unit, unitExponent: globals.unitExponent,
                            collection: collectionStack.last))
                        offset += globals.reportSize
                    }
                    offsets[reportType, default: [:]][globals.reportID] = offset
                    clearLocals()
                case 0xA:
                    let usage = usages.first ?? Usage(page: 0, id: 0)
                    result.collections.append(HIDCollectionInfo(index: result.collections.count, type: raw, usage: usage, parent: collectionStack.last))
                    collectionStack.append(result.collections.count - 1)
                    clearLocals()
                case 0xC:
                    if collectionStack.popLast() == nil { result.warnings.append("an End Collection has no matching Collection") }
                    clearLocals()
                default:
                    clearLocals()
                }
            case 1: // global
                switch tag {
                case 0x0: globals.usagePage = raw
                case 0x1: globals.logicalMin = (raw, size)
                case 0x2: globals.logicalMax = (raw, size)
                case 0x3: globals.physicalMin = (raw, size)
                case 0x4: globals.physicalMax = (raw, size)
                case 0x5:
                    // Unit Exponent is a 4-bit signed value in practice (0x0E = -2); larger values are read as signed.
                    if raw <= 0x0F { globals.unitExponent = raw >= 8 ? Int(raw) - 16 : Int(raw) }
                    else { globals.unitExponent = Int(signedValue((raw, size))) }
                case 0x6: globals.unit = raw
                case 0x7: globals.reportSize = Int(raw)
                case 0x8: globals.reportID = Int(raw); result.usesReportIDs = true
                case 0x9: globals.reportCount = Int(raw)
                case 0xA: globalStack.append(globals)
                case 0xB: if let top = globalStack.popLast() { globals = top }
                default: break
                }
            case 2: // local
                let usage = size == 4 ? Usage(page: raw >> 16, id: raw & 0xFFFF) : Usage(page: globals.usagePage, id: raw)
                switch tag {
                case 0x0: usages.append(usage)
                case 0x1: usageMin = usage
                case 0x2: usageMax = usage
                default: break
                }
            default:
                break
            }
        }
        if !collectionStack.isEmpty { result.warnings.append("\(collectionStack.count) collection(s) are never closed") }
        result.reportBits = offsets
        return result
    }
}

// MARK: - Report layouts: where the fingers, the pointer and the counters sit in each input report

struct FingerSlotLayout {
    var tip: HIDField?
    var inRange: HIDField?
    var confidence: HIDField?
    var contactID: HIDField?
    var x: HIDField?
    var y: HIDField?
    var width: HIDField?
    var height: HIDField?
    var azimuth: HIDField?
    var pressure: HIDField?
}

struct ReportLayout {
    enum Kind: String { case touch, pointer, other }

    let reportID: Int
    let byteLength: Int
    var slots: [FingerSlotLayout] = []
    var contactCount: HIDField?
    var scanTime: HIDField?
    var buttons: [HIDField] = []
    var pointerX: HIDField?
    var pointerY: HIDField?
    var wheel: HIDField?
    var tip: HIDField?
    var inRange: HIDField?

    var kind: Kind {
        if !slots.isEmpty { return .touch }
        if pointerX != nil || pointerY != nil || !buttons.isEmpty { return .pointer }
        return .other
    }

    static func build(_ d: ParsedDescriptor, reportID: Int) -> ReportLayout {
        var layout = ReportLayout(reportID: reportID, byteLength: d.reportBytes(.input, reportID))
        let fields = d.fields.filter { $0.type == .input && $0.reportID == reportID && !$0.constant }

        // Group the fields by the collection right below the application collection.
        var groups: [Int: [HIDField]] = [:]
        var topLevel: [HIDField] = []
        for f in fields {
            if let slot = d.slotCollection(of: f.collection) { groups[slot, default: []].append(f) }
            else { topLevel.append(f) }
        }
        var fingerGroups: [(Int, [HIDField])] = []
        for (collection, members) in groups {
            let isFinger = members.contains { $0.usage == Usages.contactID } || d.collections[collection].usage == Usages.finger
            if isFinger { fingerGroups.append((collection, members)) } else { topLevel += members }
        }
        fingerGroups.sort { ($0.1.map(\.bitOffset).min() ?? 0) < ($1.1.map(\.bitOffset).min() ?? 0) }
        for (_, members) in fingerGroups {
            var slot = FingerSlotLayout()
            for f in members {
                switch f.usage {
                case Usages.tipSwitch: if slot.tip == nil { slot.tip = f }
                case Usages.inRange: if slot.inRange == nil { slot.inRange = f }
                case Usages.confidence: if slot.confidence == nil { slot.confidence = f }
                case Usages.contactID: if slot.contactID == nil { slot.contactID = f }
                case Usages.x: if slot.x == nil { slot.x = f }
                case Usages.y: if slot.y == nil { slot.y = f }
                case Usages.width: if slot.width == nil { slot.width = f }
                case Usages.height: if slot.height == nil { slot.height = f }
                case Usages.azimuth: if slot.azimuth == nil { slot.azimuth = f }
                case Usages.tipPressure: if slot.pressure == nil { slot.pressure = f }
                default: break
                }
            }
            layout.slots.append(slot)
        }
        topLevel.sort { $0.bitOffset < $1.bitOffset }
        for f in topLevel {
            switch f.usage {
            case Usages.contactCount: if layout.contactCount == nil { layout.contactCount = f }
            case Usages.scanTime: if layout.scanTime == nil { layout.scanTime = f }
            case Usages.x: if layout.pointerX == nil { layout.pointerX = f }
            case Usages.y: if layout.pointerY == nil { layout.pointerY = f }
            case Usages.wheel: if layout.wheel == nil { layout.wheel = f }
            case Usages.tipSwitch: if layout.tip == nil { layout.tip = f }
            case Usages.inRange: if layout.inRange == nil { layout.inRange = f }
            default:
                if f.usage.page == Usages.buttonPage, f.variable { layout.buttons.append(f) }
            }
        }
        return layout
    }
}
