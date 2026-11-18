// What a report descriptor says about its interface, read only. The support check reports it, and
// tells from it which devices it can check: a digitiser, or a touchscreen that is only a mouse.

import Foundation

/// A summary of one HID interface's report descriptor, as `DescriptorParser` reads it: its
/// application collections, its reports and their lengths, the feature reports a touchscreen is
/// switched with, and whether it has an absolute pointer. Nothing here reads or writes a device.
public struct DescriptorSummary: Equatable, Sendable {
    /// One application collection's usage.
    public struct Collection: Hashable, Sendable {
        public var page: Int
        public var usage: Int

        public init(page: Int, usage: Int) {
            self.page = page
            self.usage = usage
        }
    }

    /// One report: its ID (0 when the interface uses none), and its length in bytes as it travels,
    /// with the report ID byte when the interface uses IDs.
    public struct Report: Hashable, Sendable {
        public var id: Int
        public var length: Int

        public init(id: Int, length: Int) {
            self.id = id
            self.length = length
        }
    }

    /// The application collections, in descriptor order.
    public private(set) var applicationCollections: [Collection] = []
    public private(set) var usesReportIDs = false
    /// Each kind of report, by ID.
    public private(set) var inputReports: [Report] = []
    public private(set) var outputReports: [Report] = []
    public private(set) var featureReports: [Report] = []
    /// The feature report that holds Input Mode (0x0D/0x52), the switch between mouse emulation and
    /// multi-touch; nil when there is none.
    public private(set) var inputModeReportID: Int?
    /// The feature report that holds the certification blob (0xFF00/0xC5).
    public private(set) var certificationBlobReportID: Int?
    /// The feature report that holds Contact Count Maximum (0x0D/0x55).
    public private(set) var contactCountMaximumReportID: Int?
    /// An absolute X and Y (Generic Desktop 0x30 and 0x31, without the relative flag) inside a
    /// Pointer (0x01/0x01) or Mouse (0x01/0x02) collection: a panel that acts as a mouse.
    public private(set) var hasAbsolutePointer = false
    /// An application collection on the Digitizer page (0x0D): a touchscreen, a pen, a digitiser.
    public private(set) var isDigitizer = false
    /// What stopped the parser, then what it found odd, in its own words. Empty for a sound descriptor.
    public private(set) var problems: [String] = []

    /// Where Contact Count Maximum sits in its report, after the report ID byte.
    private var contactCountMaximumField: FieldPlace?

    private struct FieldPlace: Equatable, Sendable {
        var reportID: Int
        var bitOffset: Int
        var bitSize: Int
        var isSigned: Bool
    }

    /// The summary of `descriptor`. A descriptor longer than USB can give is not read, and says so.
    public init(descriptor: [UInt8]) {
        guard descriptor.count <= DescriptorLimits.maxDescriptorBytes else {
            problems = ["the descriptor is longer than \(DescriptorLimits.maxDescriptorBytes) bytes"]
            return
        }
        let parsed = DescriptorParser.parse(descriptor)
        problems = (parsed.refusal.map { [$0] } ?? []) + parsed.warnings
        usesReportIDs = parsed.usesReportIDs
        applicationCollections = parsed.applicationUsages.map { Collection(page: Int($0.page), usage: Int($0.id)) }
        isDigitizer = parsed.applicationUsages.contains { $0.page == UInt32(0x0D) }
        func reports(_ type: ReportType) -> [Report] {
            parsed.reportIDs(type).filter { (parsed.reportBits[type]?[$0] ?? 0) > 0 }
                .map { Report(id: $0, length: parsed.reportBytes(type, $0)) }
        }
        inputReports = reports(.input)
        outputReports = reports(.output)
        featureReports = reports(.feature)

        for field in parsed.fields where field.type == .feature {
            switch field.usage {
            case Usages.inputMode where inputModeReportID == nil:
                inputModeReportID = field.reportID
            case Usages.certificationBlob where certificationBlobReportID == nil:
                certificationBlobReportID = field.reportID
            case Usages.contactCountMaximum where contactCountMaximumReportID == nil:
                contactCountMaximumReportID = field.reportID
                contactCountMaximumField = FieldPlace(reportID: field.reportID, bitOffset: field.bitOffset,
                                                      bitSize: field.bitSize, isSigned: field.signed)
            default:
                break
            }
        }

        let pointerAxes = parsed.fields.filter { field in
            field.type == .input && !field.constant && !field.relative
                && (field.usage == Usages.x || field.usage == Usages.y)
                && Self.isInPointerOrMouse(field.collection, parsed)
        }
        hasAbsolutePointer = pointerAxes.contains { $0.usage == Usages.x } && pointerAxes.contains { $0.usage == Usages.y }
    }

    /// Contact Count Maximum, from the bytes a read of its feature report returned (with the report
    /// ID byte first when the interface uses IDs); nil when the descriptor declares none, or the
    /// bytes are another report's or too short.
    public func contactCountMaximum(fromFeatureReport bytes: [UInt8]) -> Int? {
        guard let place = contactCountMaximumField, place.bitSize > 0, place.bitSize <= 32 else { return nil }
        let data: [UInt8]
        if usesReportIDs {
            guard let first = bytes.first, Int(first) == place.reportID else { return nil }
            data = Array(bytes.dropFirst())
        } else {
            data = bytes
        }
        guard (place.bitOffset + place.bitSize + 7) / 8 <= data.count else { return nil }
        var value: UInt64 = 0
        for bit in 0..<place.bitSize {
            let position = place.bitOffset + bit
            if data[position >> 3] & (1 << UInt8(position & 7)) != 0 { value |= 1 << UInt64(bit) }
        }
        if place.isSigned, value & (1 << UInt64(place.bitSize - 1)) != 0 {
            return Int(Int64(bitPattern: value | ~UInt64(0) << UInt64(place.bitSize)))
        }
        return Int(value)
    }

    /// Whether `collection`, or a collection around it, is a Pointer or a Mouse.
    private static func isInPointerOrMouse(_ collection: Int?, _ parsed: ParsedDescriptor) -> Bool {
        var current = collection
        while let index = current, parsed.collections.indices.contains(index) {
            let usage = parsed.collections[index].usage
            if usage == Usages.pointer || usage == Usages.mouse { return true }
            current = parsed.collections[index].parent
        }
        return false
    }
}
