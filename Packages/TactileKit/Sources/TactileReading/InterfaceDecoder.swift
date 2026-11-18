// Decoding the raw input reports of one HID interface from its report descriptor alone: no
// IOKit, so the same code reads a live panel and a recorded one.
//
// The decoding is carried over from `decodeReport` in Tools/tactile-probe/Sources/Recorder.swift,
// which reproduced IOKit's reading of every field of both surveyed panels.

import CoreGraphics
import Foundation

/// What a HID interface is for, from its application collections.
public enum InterfaceKind: Equatable, Sendable {
    /// The interface has a Touch Screen application collection (usage page 0x0D, usage 0x04).
    case touchscreen
    /// It has a Mouse application collection (0x01/0x02) and no Touch Screen one.
    case mouse
    /// Anything else, such as a vendor-defined interface.
    case other
}

/// One input report, decoded.
public enum DecodedReport: Equatable, Sendable {
    /// A report with finger collections.
    case touch(TouchReport)
    /// A report with buttons, or an X or Y outside any finger collection.
    case pointer(PointerReport)
    /// A report the descriptor describes that carries neither.
    case other
}

/// One touch report: every finger collection in it, whether or not a finger is in it.
public struct TouchReport: Equatable, Sendable {
    /// The report's Contact Count, when it has one. A panel that spreads one scan over several
    /// reports gives the count in the first and 0 in the rest.
    public var contactCount: Int?
    /// The report's Scan Time, in the panel's own units, when it has one.
    public var scanTime: Int?
    /// One reading per finger collection, in report order.
    public var slots: [SlotReading]

    public init(contactCount: Int? = nil, scanTime: Int? = nil, slots: [SlotReading]) {
        self.contactCount = contactCount
        self.scanTime = scanTime
        self.slots = slots
    }
}

/// One finger collection of a touch report, as the panel filled it in.
public struct SlotReading: Equatable, Sendable {
    /// The finger collection's index in the report, from 0.
    public var slot: Int
    /// The Contact Identifier, or `nil` when the collection has none.
    public var contactID: Int?
    /// The Tip Switch: a finger is touching. False when the collection has no Tip Switch.
    public var tip: Bool
    /// X and Y, each normalised to 0…1 across its logical range; `nil` when the collection lacks
    /// either or its logical range is empty. A value outside the range is at the range's nearer end,
    /// unless its field has a Null State: then it says there is no value, and `position` is `nil`.
    public var position: CGPoint?
    /// The contact's Width and Height, in the fields' own units; `nil` when the collection has
    /// neither. When it has only one, that value stands for both.
    public var size: CGSize?
    /// The Confidence flag: the panel judges this a finger rather than, say, a palm. `nil` when
    /// the collection has no Confidence field.
    public var isConfident: Bool?

    public init(slot: Int, contactID: Int?, tip: Bool, position: CGPoint?, size: CGSize? = nil, isConfident: Bool? = nil) {
        self.slot = slot
        self.contactID = contactID
        self.tip = tip
        self.position = position
        self.size = size
        self.isConfident = isConfident
    }
}

/// One pointer report: the mouse a panel can pretend to be.
public struct PointerReport: Equatable, Sendable {
    /// The buttons held, as a bit mask: bit 0 is the first button. 0 when the report has no buttons.
    public var buttons: Int
    /// An absolute X and Y, each normalised to 0…1 across its logical range; `nil` for a relative
    /// mouse, or when the report lacks either. A value outside the range is at the range's nearer
    /// end, unless its field has a Null State: then it says there is no value, and `position` is `nil`.
    public var position: CGPoint?
    /// A relative X and Y movement in the fields' own units; `nil` when neither axis is relative.
    public var delta: CGVector?

    public init(buttons: Int, position: CGPoint?, delta: CGVector? = nil) {
        self.buttons = buttons
        self.position = position
        self.delta = delta
    }
}

/// A feature report a host reads when it starts using a touchscreen. Windows and Linux read a
/// touchscreen's Contact Count Maximum and its certification blob (the 256-byte "Windows 8" blob)
/// whenever it enumerates, and some panels wait for that: the ILITEK stays in its power-on mouse
/// emulation until a host has read its report 0x06. Linux's `hid-multitouch` reads the blob "once
/// to enable some devices" (`mt_feature_mapping`).
public struct FeatureReportToRead: Equatable, Sendable {
    /// What the report declares that makes it worth reading.
    public enum Content: Equatable, Sendable, CustomStringConvertible {
        /// Contact Count Maximum (0x0D/0x55).
        case contactCountMaximum
        /// The certification blob (0xFF00/0xC5).
        case certificationBlob

        init?(_ usage: Usage) {
            switch usage {
            case Usages.contactCountMaximum: self = .contactCountMaximum
            case Usages.certificationBlob: self = .certificationBlob
            default: return nil
            }
        }

        public var description: String {
            switch self {
            case .contactCountMaximum: return "Contact Count Maximum"
            case .certificationBlob: return "certification blob"
            }
        }
    }

    /// 0 when the interface does not use report IDs.
    public let reportID: Int
    /// The report's declared length in bytes, with the report ID byte when the interface uses
    /// IDs: exactly what to ask for, since some firmware answers with as many bytes as it is asked.
    public let length: Int
    /// What it declares, each once, in descriptor order.
    public let contents: [Content]

    public init(reportID: Int, length: Int, contents: [Content]) {
        self.reportID = reportID
        self.length = length
        self.contents = contents
    }

    /// "Contact Count Maximum, certification blob", for the log.
    public var describedContents: String { contents.map(\.description).joined(separator: ", ") }

    /// Every feature report of `parsed` with a field declaring Contact Count Maximum or the
    /// certification blob, in descriptor order: the order in which each report first appears among
    /// the feature items, which is the order Linux reads them in. A constant field counts too, as
    /// in Linux: a read too many does no harm, while one too few leaves a panel emulating a mouse.
    static func list(in parsed: ParsedDescriptor) -> [FeatureReportToRead] {
        var order: [Int] = []
        var seen: Set<Int> = []
        var found: [Int: [Content]] = [:]
        for field in parsed.fields where field.type == .feature {
            if seen.insert(field.reportID).inserted { order.append(field.reportID) }
            guard let content = Content(field.usage) else { continue }
            if found[field.reportID]?.contains(content) != true { found[field.reportID, default: []].append(content) }
        }
        return order.compactMap { id in
            guard let contents = found[id], (parsed.reportBits[.feature]?[id] ?? 0) > 0 else { return nil }
            return FeatureReportToRead(reportID: id, length: parsed.reportBytes(.feature, id), contents: contents)
        }
    }
}

/// Reads the input reports of one HID interface. A USB touchscreen can have several interfaces
/// that use the same report IDs (the ILITEK sends report ID 0x04 on both its touch and its mouse
/// interface), so each interface needs a decoder of its own, and reports are routed to it by the
/// interface they arrived on, never by report ID.
public struct InterfaceDecoder: Sendable {
    /// What the interface is for, from its application collections.
    public private(set) var kind: InterfaceKind
    /// How many finger collections one touch report has; 0 unless the interface is a touchscreen.
    public private(set) var contactSlots: Int
    /// The touch surface's width and height in millimetres, from the X and Y fields' physical
    /// ranges, units and exponents; `nil` when they don't give one, when either side isn't finite and
    /// above zero, or when either axis is relative.
    public private(set) var surfaceSizeMM: CGSize?
    /// The finger collections carry a Width or a Height.
    public private(set) var reportsContactSize: Bool
    /// The finger collections carry a Confidence flag.
    public private(set) var reportsConfidence: Bool
    /// The longest input report, in bytes, including the report ID byte when the interface uses IDs.
    public private(set) var maxInputReportLength: Int
    /// The feature reports to read when taking the touchscreen, in descriptor order: those that
    /// declare Contact Count Maximum or the certification blob (see `FeatureReportToRead`).
    public private(set) var featureReportsToRead: [FeatureReportToRead]

    private let usesReportIDs: Bool
    private let layouts: [Int: ReportLayout]

    /// Parses the interface's HID report descriptor. Returns `nil` when the bytes don't describe at
    /// least one input report, or when the descriptor asks for more than a touchscreen ever needs.
    ///
    /// The parser's known limits, enough for both surveyed panels:
    /// - long items are skipped;
    /// - delimiters are ignored, so every usage inside a delimited set is taken as a plain usage;
    /// - an array (non-variable) item is given its first usage only;
    /// - a usage range is cut off at 4,096 usages;
    /// - a descriptor that ends in the middle of an item is read up to that item.
    ///
    /// A descriptor comes from whatever is plugged in, so it is not trusted, and the work it can
    /// ask for is bounded:
    /// - a descriptor longer than 65,535 bytes, more than USB can give, is not one (`nil`);
    /// - a report longer than 65,535 bytes, more than 65,536 fields in all, or collections nested
    ///   more than 64 deep make the descriptor unusable (`nil`);
    /// - a field wider than 32 bits is not read, as if it were padding: its report keeps its length,
    ///   and the report's other fields are read. A report with no other field decodes as `.other`.
    public init?(descriptor: [UInt8]) {
        guard descriptor.count <= DescriptorLimits.maxDescriptorBytes else { return nil }
        let parsed = DescriptorParser.parse(descriptor)
        guard parsed.refusal == nil else { return nil }
        let inputFields = Dictionary(grouping: parsed.fields.filter { $0.type == .input }, by: \.reportID)
        var layouts: [Int: ReportLayout] = [:]
        for id in parsed.reportIDs(.input) where (parsed.reportBits[.input]?[id] ?? 0) > 0 {
            layouts[id] = ReportLayout.build(parsed, reportID: id, fields: inputFields[id] ?? [])
        }
        guard !layouts.isEmpty else { return nil }
        self.layouts = layouts
        usesReportIDs = parsed.usesReportIDs
        maxInputReportLength = layouts.values.map(\.byteLength).max() ?? 0
        featureReportsToRead = FeatureReportToRead.list(in: parsed)

        let applications = parsed.applicationUsages
        if applications.contains(Usages.touchScreen) { kind = .touchscreen }
        else if applications.contains(Usages.mouse) { kind = .mouse }
        else { kind = .other }

        // The touch report is the one with the most finger collections (the lowest report ID on a tie).
        let inOrder = layouts.keys.sorted().compactMap { layouts[$0] }
        let touchLayout = inOrder.filter { $0.kind == .touch }.max { $0.slots.count < $1.slots.count }
        let fingerSlots = kind == .touchscreen ? touchLayout?.slots ?? [] : []
        contactSlots = fingerSlots.count
        reportsContactSize = fingerSlots.contains { $0.width != nil || $0.height != nil }
        reportsConfidence = fingerSlots.contains { $0.confidence != nil }

        // The surface size comes from the fingers' X and Y, or else from a pointer report's.
        var axes: (x: HIDField, y: HIDField)?
        if let slot = touchLayout?.slots.first(where: { $0.x != nil && $0.y != nil }), let x = slot.x, let y = slot.y {
            axes = (x, y)
        } else if let layout = inOrder.first(where: { $0.pointerX != nil && $0.pointerY != nil }),
                  let x = layout.pointerX, let y = layout.pointerY {
            axes = (x, y)
        }
        // A relative axis measures movement, not the surface; a range that runs backwards, or is
        // empty, measures nothing.
        if let axes, !axes.x.relative, !axes.y.relative,
           let width = axes.x.physicalExtentMM, let height = axes.y.physicalExtentMM,
           width.isFinite, height.isFinite, width > 0, height > 0 {
            surfaceSizeMM = CGSize(width: width, height: height)
        } else {
            surfaceSizeMM = nil
        }
    }

    /// Decodes one input report as it arrived on this interface, starting with the report ID byte
    /// when the interface uses IDs. Returns `nil` for bytes the descriptor doesn't describe: an
    /// unknown report ID, or a report shorter than its layout.
    public func decode(_ bytes: [UInt8]) -> DecodedReport? {
        let reportID: Int
        let data: [UInt8]
        if usesReportIDs {
            guard let first = bytes.first else { return nil }
            reportID = Int(first)
            data = Array(bytes.dropFirst())
        } else {
            reportID = 0
            data = bytes
        }
        guard let layout = layouts[reportID], bytes.count >= layout.byteLength else { return nil }
        switch layout.kind {
        case .touch: return .touch(Self.touchReport(layout, data))
        case .pointer: return .pointer(Self.pointerReport(layout, data))
        case .other: return .other
        }
    }

    /// `data` starts after the report ID byte.
    private static func touchReport(_ layout: ReportLayout, _ data: [UInt8]) -> TouchReport {
        func int(_ f: HIDField?) -> Int? { f.flatMap { $0.value(in: data) }.map { Int($0) } }
        let slots = layout.slots.enumerated().map { index, slot -> SlotReading in
            var position: CGPoint?
            if let x = axis(slot.x, in: data), let y = axis(slot.y, in: data) {
                position = CGPoint(x: x, y: y)
            }
            let width = int(slot.width)
            let height = int(slot.height)
            let size = (width ?? height).map { CGSize(width: width ?? $0, height: height ?? $0) }
            return SlotReading(slot: index, contactID: int(slot.contactID), tip: (int(slot.tip) ?? 0) != 0,
                               position: position, size: size, isConfident: int(slot.confidence).map { $0 != 0 })
        }
        return TouchReport(contactCount: int(layout.contactCount), scanTime: int(layout.scanTime), slots: slots)
    }

    /// `data` starts after the report ID byte.
    private static func pointerReport(_ layout: ReportLayout, _ data: [UInt8]) -> PointerReport {
        var buttons = 0
        for f in layout.buttons where (f.value(in: data) ?? 0) != 0 {
            let bit = Int(f.usage.id) - 1
            if bit >= 0, bit < 62 { buttons |= 1 << bit }
        }
        let rawX = layout.pointerX.flatMap { $0.value(in: data) }
        let rawY = layout.pointerY.flatMap { $0.value(in: data) }

        var position: CGPoint?
        if let fx = layout.pointerX, let fy = layout.pointerY, !fx.relative, !fy.relative,
           let x = axis(fx, in: data), let y = axis(fy, in: data) {
            position = CGPoint(x: x, y: y)
        }
        let relativeX = layout.pointerX?.relative ?? false
        let relativeY = layout.pointerY?.relative ?? false
        var delta: CGVector?
        if relativeX || relativeY {
            delta = CGVector(dx: relativeX ? Double(rawX ?? 0) : 0, dy: relativeY ? Double(rawY ?? 0) : 0)
        }
        return PointerReport(buttons: buttons, position: position, delta: delta)
    }

    /// An absolute X or Y on 0…1 across its field's logical range. `nil` when there is no field or
    /// its range is empty, and when the field has a Null State and the value is outside the range:
    /// that is how such a field says it has no value. Any other value outside the range is brought
    /// to the range's nearer end, so a position is always 0…1. `data` starts after the report ID byte.
    private static func axis(_ field: HIDField?, in data: [UInt8]) -> Double? {
        guard let field, let raw = field.value(in: data), let position = field.normalised(raw) else { return nil }
        // Outside 0…1 exactly when the value is outside the range, whichever end is the larger.
        if (0...1).contains(position) { return position }
        return field.nullState ? nil : min(max(position, 0), 1)
    }
}
