// The devices the touchscreen check can check: touchscreens, digitisers Tactile doesn't list, and
// touchscreens that are only a mouse. Pure: it reads what the HID system described, and nothing else.

import Foundation
import TactileReading

/// What kind of device a check is for.
public enum SupportDeviceKind: String, Codable, Sendable, CaseIterable {
    /// It has a Touch Screen collection (0x0D/0x04): Tactile lists it.
    case touchscreen
    /// It has a collection on the Digitizer page (0x0D) but no Touch Screen one: a pen, a digitiser,
    /// a touchscreen that calls itself something else. Tactile doesn't list it.
    case digitizer
    /// It is only a mouse, with an absolute X and Y in a Pointer or Mouse collection: a touchscreen
    /// that never shows its touches. Tactile doesn't list it.
    case mouseOnly = "mouse-only"
}

/// One interface of a device to check, as the HID system described it.
public struct SupportInterface: Equatable, Sendable {
    /// What the check does with it.
    public enum Role: String, Codable, Sendable {
        /// The interface touches are read from, as Tactile reads them: a touchscreen's touchscreen
        /// interface, or a digitiser's. A take opens it, reads its feature reports and switches it.
        case touch
        /// The touch interface's mouse sibling, which a take opens and listens to as well.
        case mouse
        /// A mouse-only device's absolute pointer: opened and listened to, never read or written.
        case pointer
        /// A digitiser's interface (a touch pad, a pen, a digitiser): Tactile drives only touchscreens,
        /// so it is opened and listened to, never read or written. Nothing is switched on a guess: a
        /// touch pad's Input Mode, for one, isn't a touchscreen's.
        case digitizer
        /// Anything else of the device (a vendor interface, say): described in the report, never opened.
        case other
    }

    /// The interface while it is connected (its IORegistry entry ID).
    public let id: UInt64
    public let role: Role
    /// Its application collections, as IOKit lists them.
    public let usages: [DescriptorSummary.Collection]
    /// Its report descriptor, when it publishes one.
    public let descriptor: [UInt8]?
    /// IOKit's largest input report size, when it gives one.
    public let maxInputReportSize: Int?

    public init(id: UInt64, role: Role, usages: [DescriptorSummary.Collection], descriptor: [UInt8]?, maxInputReportSize: Int?) {
        self.id = id
        self.role = role
        self.usages = usages
        self.descriptor = descriptor
        self.maxInputReportSize = maxInputReportSize
    }
}

/// One device the check can check: the interfaces of one USB device, in the order they arrived.
public struct SupportDevice: Equatable, Sendable, Identifiable {
    /// `<usb id>@<location>`, or `<usb id>#<interface>` for a device with no USB location.
    public let id: String
    public let kind: SupportDeviceKind
    public let vendorID: Int
    public let productID: Int
    /// As reported; empty when there is none.
    public let product: String
    public let manufacturer: String
    /// As reported, so that the report can take it out wherever it appears. Never written in it.
    public let serial: String
    /// 0 when it has no USB location.
    public let locationID: UInt32
    public let interfaces: [SupportInterface]

    public init(id: String, kind: SupportDeviceKind, vendorID: Int, productID: Int, product: String, manufacturer: String,
                serial: String, locationID: UInt32, interfaces: [SupportInterface]) {
        self.id = id
        self.kind = kind
        self.vendorID = vendorID
        self.productID = productID
        self.product = product
        self.manufacturer = manufacturer
        self.serial = serial
        self.locationID = locationID
        self.interfaces = interfaces
    }

    /// "222a:0001".
    public var usbID: String { String(format: "%04x:%04x", vendorID, productID) }
    /// "01141000", as Tactile writes a location; nil when it has none.
    public var location: String? { locationID == 0 ? nil : String(format: "%08x", locationID) }

    /// The interface touches are read from, if it has one.
    public var touchInterface: SupportInterface? { interfaces.first { $0.role == .touch } }

    /// The interface the log book keys this device's lines by: its touch interface (the touchscreen
    /// source keys a touchscreen's lines by the same), else its first listened interface, else its first.
    public var logKey: UInt64? { (touchInterface ?? listenedOnly.first ?? interfaces.first)?.id }

    /// The interfaces only listened to: a mouse-only device's pointers, or a digitiser's interfaces
    /// when none is known to take touches.
    public var listenedOnly: [SupportInterface] { interfaces.filter { $0.role == .pointer || $0.role == .digitizer } }
}

/// A device's own strings, as plain text: they come from whatever is plugged in.
public enum DeviceText {
    public static let maxLength = 64

    /// `text` with control characters (C0, C1, DEL) as spaces, format characters (bidi controls,
    /// zero-width characters) taken out, spaces closed up, trimmed, and at most `maxLength`
    /// characters. Empty when nothing is left.
    public static func clean(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar.value <= 31 || (127...159).contains(scalar.value) {
                scalars.append(" ")
            } else if scalar.properties.generalCategory != .format {
                scalars.append(scalar)
            }
        }
        let spaced = String(scalars).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return String(spaced.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
    }
}

/// Groups the interfaces the HID system described into devices to check.
///
/// - **A device** is the interfaces at one USB location with one vendor and product ID. Location 0
///   means no USB location: such an interface is a device by itself.
/// - **Its kind**, by the first that applies: a **touchscreen** when an interface is one as the
///   touchscreen source sees it (IOKit lists a Touch Screen collection, or its descriptor has one); a
///   **digitiser** when an interface lists, or its descriptor has, a collection on the Digitizer
///   page; **mouse-only** when an interface's descriptor has an absolute X and Y in a Pointer or Mouse
///   collection. Anything else, an ordinary mouse among them, is not offered.
/// - **Never offered:** Apple's own devices (USB vendor 0x05AC, Bluetooth vendor 0x004C) and any
///   device with an interface built into the Mac, such as the trackpad. Nor a mouse-only device with
///   the USB ID of a touchscreen or digitiser that is offered: without a location to tell, it is
///   taken for that device's mouse interface.
/// - **Its interfaces' roles:** a touchscreen's touch interface is the one the source would read
///   (`InterfaceChoice.touchInterface`), and its mouse is the sibling the source would open
///   (`InterfaceChoice.mouseSibling`). A digitiser has no touch interface: Tactile drives only
///   touchscreens, so its digitiser interfaces (a touch pad's included; never a vendor-defined or
///   Device Configuration one) are `digitizer`, only listened to. A mouse-only device's absolute
///   pointers are its pointers. Every other interface is `other`, and is never opened.
/// - **Its strings** are plain text (`DeviceText`).
enum SupportDevices {
    static let appleVendorIDs: Set<Int> = [0x05AC, 0x004C]

    static func group(_ interfaces: [KnownInterface]) -> [SupportDevice] {
        let ordered = interfaces.sorted { $0.arrival < $1.arrival }
        var groups: [[KnownInterface]] = []
        for interface in ordered {
            if interface.locationID != 0, let index = groups.firstIndex(where: { sameDevice($0[0], interface) }) {
                groups[index].append(interface)
            } else {
                groups.append([interface])
            }
        }
        let devices = groups.compactMap(device(of:))
        let shown = Set(devices.filter { $0.kind != .mouseOnly }.map(\.usbID))
        return devices.filter { $0.kind != .mouseOnly || !shown.contains($0.usbID) }
    }

    private static func sameDevice(_ a: KnownInterface, _ b: KnownInterface) -> Bool {
        a.locationID != 0 && a.locationID == b.locationID && a.description.vendorID == b.description.vendorID
            && a.description.productID == b.description.productID
    }

    private static func device(of group: [KnownInterface]) -> SupportDevice? {
        let first = group[0].description
        guard !appleVendorIDs.contains(first.vendorID), !group.contains(where: \.description.isBuiltIn) else { return nil }
        let summaries = Dictionary(uniqueKeysWithValues: group.map { ($0.id, $0.description.descriptor.map(DescriptorSummary.init)) })

        let kind: SupportDeviceKind
        var roles: [HIDInterfaceID: SupportInterface.Role] = [:]
        if let touch = InterfaceChoice.touchInterface(among: group) {
            kind = .touchscreen
            roles[touch.id] = .touch
            if let mouse = InterfaceChoice.mouseSibling(of: touch, among: group) { roles[mouse.id] = .mouse }
        } else if group.contains(where: { isDigitizer($0, summaries[$0.id] ?? nil) }) {
            kind = .digitizer
            for interface in group where isListenedDigitizer(interface, summaries[interface.id] ?? nil) {
                roles[interface.id] = .digitizer
            }
        } else {
            let pointers = group.filter { summaries[$0.id]??.hasAbsolutePointer == true }
            guard !pointers.isEmpty else { return nil }
            kind = .mouseOnly
            for pointer in pointers { roles[pointer.id] = .pointer }
        }

        let id = first.locationID == 0
            ? String(format: "%04x:%04x#%llu", first.vendorID, first.productID, first.id)
            : String(format: "%04x:%04x@%08x", first.vendorID, first.productID, first.locationID)
        return SupportDevice(
            id: id, kind: kind, vendorID: first.vendorID, productID: first.productID,
            product: DeviceText.clean(group.lazy.map(\.description.product).first { !$0.isEmpty } ?? ""),
            manufacturer: DeviceText.clean(group.lazy.map(\.description.manufacturer).first { !$0.isEmpty } ?? ""),
            serial: group.lazy.map(\.description.serial).first { !$0.isEmpty } ?? "",
            locationID: first.locationID,
            interfaces: group.map { interface in
                SupportInterface(
                    id: interface.id, role: roles[interface.id] ?? .other,
                    usages: interface.description.usages.map { DescriptorSummary.Collection(page: $0.page, usage: $0.usage) },
                    descriptor: interface.description.descriptor, maxInputReportSize: interface.description.maxInputReportSize)
            })
    }

    /// IOKit lists a collection on the Digitizer page, or the descriptor has one.
    private static func isDigitizer(_ interface: KnownInterface, _ summary: DescriptorSummary?) -> Bool {
        interface.description.usages.contains { $0.page == HIDUsage.digitizerPage } || summary?.isDigitizer == true
    }

    /// Its collections: as IOKit lists them, else as its descriptor has them.
    private static func collections(_ interface: KnownInterface, _ summary: DescriptorSummary?) -> [HIDUsage] {
        let listed = interface.description.usages
        return listed.isEmpty ? (summary?.applicationCollections ?? []).map { HIDUsage(page: $0.page, usage: $0.usage) } : listed
    }

    /// Its first collection is vendor-defined (page 0xFF00 and above).
    private static func isVendorFirst(_ interface: KnownInterface, _ summary: DescriptorSummary?) -> Bool {
        (collections(interface, summary).first?.page ?? 0) >= 0xFF00
    }

    /// A Digitizer-page collection other than Device Configuration (0x0D/0x0E), on an interface whose
    /// first collection isn't vendor-defined.
    private static func isListenedDigitizer(_ interface: KnownInterface, _ summary: DescriptorSummary?) -> Bool {
        !isVendorFirst(interface, summary)
            && collections(interface, summary).contains { $0.page == HIDUsage.digitizerPage && $0.usage != 0x0E }
    }
}
