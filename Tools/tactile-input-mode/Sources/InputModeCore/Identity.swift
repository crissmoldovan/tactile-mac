// Which interfaces belong together, and which touchscreen a run is about.

import Foundation

/// What IOKit says about one HID interface's USB device.
public struct USBIdentity: Equatable, Sendable {
    public let vendorID: Int
    public let productID: Int
    public let locationID: Int
    public let serial: String

    public init(vendorID: Int, productID: Int, locationID: Int, serial: String) {
        self.vendorID = vendorID
        self.productID = productID
        self.locationID = locationID
        self.serial = serial
    }

    /// Another interface of the same USB device: the same non-zero location and the same USB ID.
    /// Location 0 never matches: unrelated devices without a location would all look alike.
    public func isSibling(of other: USBIdentity) -> Bool {
        locationID != 0 && locationID == other.locationID && vendorID == other.vendorID && productID == other.productID
    }
}

/// `--touchscreen <vendor:product>` or `<vendor:product:serial>`, in hexadecimal.
public struct DeviceFilter: Equatable, Sendable {
    public let vendorID: Int
    public let productID: Int
    /// When set, the serial must match too.
    public let serial: String?

    public init?(_ text: String) {
        let parts = text.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              let vendor = Int(parts[0], radix: 16), let product = Int(parts[1], radix: 16) else { return nil }
        if parts.count == 3, parts[2].isEmpty { return nil }
        vendorID = vendor
        productID = product
        serial = parts.count == 3 ? String(parts[2]) : nil
    }

    /// The filter that matches exactly this device: its USB ID and its serial.
    public init(identity: USBIdentity) {
        vendorID = identity.vendorID
        productID = identity.productID
        serial = identity.serial
    }

    public func matches(_ identity: USBIdentity) -> Bool {
        identity.vendorID == vendorID && identity.productID == productID && (serial.map { $0 == identity.serial } ?? true)
    }

    public var text: String {
        String(format: "%04x:%04x", vendorID, productID) + (serial.map { ":\($0)" } ?? "")
    }
}
