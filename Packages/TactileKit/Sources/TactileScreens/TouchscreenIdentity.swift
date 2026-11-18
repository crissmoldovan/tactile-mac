// A touchscreen's ID, and which stored record each connected touchscreen uses.

import Foundation

/// The key a touchscreen's record is stored under: what makes it "this touchscreen" wherever its
/// cable goes.
///
/// Either a base ID, `vendor:product:serial`, or a port ID, `@location:` in front of the base ID:
/// see `TouchscreenIdentity`. It codes as a plain string, and a dictionary keyed by it codes as a
/// JSON object keyed by that string, as the settings file needs.
public struct TouchscreenID: Hashable, Codable, CodingKeyRepresentable, Sendable, CustomStringConvertible {
    /// The ID as text: `"27c0:0859:TEST-SERIAL-0001"`, or `"@01141000:222a:0001:V06.00.00.00"` by port.
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var codingKey: CodingKey { Key(stringValue: rawValue) }

    public init?<T: CodingKey>(codingKey: T) {
        self.init(rawValue: codingKey.stringValue)
    }

    /// A dictionary key: the ID's text.
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }
}

/// What the USB descriptors of one connected touchscreen say about it.
public struct TouchscreenFacts: Equatable, Sendable {
    /// The USB vendor ID.
    public var vendorID: Int
    /// The USB product ID.
    public var productID: Int
    /// The serial number string as the device reports it. May be empty; may be a firmware version
    /// that every unit of the model shares, as the ILITEK's is.
    public var serial: String
    /// The USB location ID: the port, through whichever hubs. No two connected devices share one, and
    /// it changes when the cable moves.
    public var locationID: UInt32
    /// The product name the device reports. Not part of its ID: two may both be "TouchScreen".
    public var name: String

    public init(vendorID: Int, productID: Int, serial: String, locationID: UInt32, name: String) {
        self.vendorID = vendorID
        self.productID = productID
        self.serial = serial
        self.locationID = locationID
        self.name = name
    }
}

/// Recognising a touchscreen: its ID, and which stored record it uses.
///
/// A touchscreen's **base ID** is its vendor, product and serial as reported. Tactile doesn't judge
/// whether a serial is unique: the ILITEK's is a firmware version, and that is still enough to
/// recognise it wherever its cable goes. Two connected touchscreens with the same base ID (identical
/// models) can only be told apart by USB port, and each then gets a record under its **port ID**.
///
/// `assign` is pure, and the app calls it every time a touchscreen connects or disconnects, passing
/// what it answered last time. Whatever it is given, no record is used by two connected
/// touchscreens; and given its own last answer, a touchscreen that stays connected keeps its record.
public enum TouchscreenIdentity {

    /// `vendor:product:serial`: four lower-case hex digits each for vendor and product, then the
    /// serial exactly as reported, `"27c0:0859:TEST-SERIAL-0001"`. An empty serial gives
    /// `"222a:0001:"`.
    ///
    /// USB vendor and product IDs are 16 bits, so they always take four digits. A value outside
    /// that range, which no USB device can report, is written in full (a negative one as its 64-bit
    /// pattern) rather than cut down to four digits, so that it is never taken for another's.
    public static func baseID(vendorID: Int, productID: Int, serial: String) -> TouchscreenID {
        TouchscreenID(rawValue: "\(hex(vendorID, digits: 4)):\(hex(productID, digits: 4)):\(serial)")
    }

    /// `@`, the location ID in eight lower-case hex digits, a colon, then the base ID:
    /// `"@01141000:222a:0001:V06.00.00.00"`.
    ///
    /// The port goes in front because a serial may hold any characters: a base ID always starts with
    /// a hex digit and a port ID always with `@`, so neither can be taken for the other, and no two
    /// pairs of base and location give the same port ID, whatever the serials hold.
    public static func portID(_ base: TouchscreenID, locationID: UInt32) -> TouchscreenID {
        TouchscreenID(rawValue: "@\(hex(locationID, digits: 8)):\(base.rawValue)")
    }

    /// Whether `id` is a port ID: it starts with `@`, eight lower-case hex digits and a colon. No base
    /// ID does, whatever its serial.
    public static func isByPort(_ id: TouchscreenID) -> Bool {
        let prefix = id.rawValue.utf8.prefix(10)
        guard prefix.count == 10, prefix.first == UInt8(ascii: "@"), prefix.last == UInt8(ascii: ":") else {
            return false
        }
        return prefix.dropFirst().dropLast().allSatisfy(isLowerCaseHexDigit)
    }

    /// Which record each connected touchscreen uses, keyed by location ID.
    ///
    /// - Parameters:
    ///   - connected: every touchscreen connected now.
    ///   - current: what `assign` answered last time. A touchscreen still connected keeps its record.
    ///   - stored: every record in the settings file.
    ///
    /// A touchscreen in `current` keeps its record if the touchscreen at that location now is one the
    /// record can belong to: the record is its base ID, or its port ID there. Anything else there is
    /// a different touchscreen, which the caller didn't pass on, and it counts as just connected.
    ///
    /// Each touchscreen that has just connected gets, in order:
    /// 1. the record under its port ID, if `stored` has one and no other connected touchscreen is
    ///    using it;
    /// 2. the record under its base ID, if `stored` has one and no other connected touchscreen is
    ///    using it;
    /// 3. a new record: under its base ID if no other connected touchscreen has the same base ID,
    ///    otherwise under its port ID.
    ///
    /// Touchscreens that connect in the same call are taken in ascending location ID order, after
    /// every touchscreen that stays has kept its record. Every connected touchscreen gets a record,
    /// one for each location.
    ///
    /// Malformed input doesn't trap. A record that appears twice in `current` is kept at the lower
    /// location only. If `connected` lists more than one touchscreen at one location, which USB
    /// doesn't allow, that location gets one record, for one of them: the one its record in `current`
    /// belongs to, if any, else the first in order of vendor, product, serial and name; the others
    /// there are left out. The answer never depends on the order of `connected`.
    public static func assign(
        connected: [TouchscreenFacts], current: [UInt32: TouchscreenID], stored: Set<TouchscreenID>
    ) -> [UInt32: TouchscreenID] {
        let screens = onePerLocation(connected, current: current)
        var answer: [UInt32: TouchscreenID] = [:]
        var inUse: Set<TouchscreenID> = []

        // Touchscreens that stay keep their records.
        for screen in screens {
            guard let record = current[screen.locationID], belongs(record, to: screen), !inUse.contains(record)
            else { continue }
            answer[screen.locationID] = record
            inUse.insert(record)
        }

        // Touchscreens that have just connected.
        var sharingBase: [TouchscreenID: Int] = [:]
        for screen in screens {
            sharingBase[baseID(of: screen), default: 0] += 1
        }
        for screen in screens where answer[screen.locationID] == nil {
            let base = baseID(of: screen)
            let port = portID(base, locationID: screen.locationID)
            let record: TouchscreenID
            if stored.contains(port), !inUse.contains(port) {
                record = port
            } else if stored.contains(base), !inUse.contains(base) {
                record = base
            } else {
                // A new record, and no one else can be using it. A connected touchscreen only ever
                // uses its own base ID or its own port ID, and no base ID is a port ID: so a base ID
                // no one else has is free, and so is the port ID of a location no one else is at.
                record = sharingBase[base] == 1 ? base : port
            }
            answer[screen.locationID] = record
            inUse.insert(record)
        }
        return answer
    }

    // MARK: - Private

    private static func baseID(of screen: TouchscreenFacts) -> TouchscreenID {
        baseID(vendorID: screen.vendorID, productID: screen.productID, serial: screen.serial)
    }

    /// Whether `record` can be `screen`'s: its base ID, or its port ID where it is.
    private static func belongs(_ record: TouchscreenID, to screen: TouchscreenFacts) -> Bool {
        let base = baseID(of: screen)
        return record == base || record == portID(base, locationID: screen.locationID)
    }

    /// `connected` with one touchscreen per location, in ascending location order.
    private static func onePerLocation(
        _ connected: [TouchscreenFacts], current: [UInt32: TouchscreenID]
    ) -> [TouchscreenFacts] {
        var byLocation: [UInt32: TouchscreenFacts] = [:]
        for screen in connected {
            let location = screen.locationID
            if let other = byLocation[location], !isPreferred(screen, over: other, record: current[location]) {
                continue
            }
            byLocation[location] = screen
        }
        return byLocation.keys.sorted().compactMap { byLocation[$0] }
    }

    /// Of two touchscreens listed at one location: the one `record` belongs to, if just one; else the
    /// first in order of vendor, product, serial and name, the strings compared byte by byte.
    private static func isPreferred(
        _ screen: TouchscreenFacts, over other: TouchscreenFacts, record: TouchscreenID?
    ) -> Bool {
        if let record {
            let owns = belongs(record, to: screen), otherOwns = belongs(record, to: other)
            if owns != otherOwns { return owns }
        }
        if screen.vendorID != other.vendorID { return screen.vendorID < other.vendorID }
        if screen.productID != other.productID { return screen.productID < other.productID }
        if !screen.serial.utf8.elementsEqual(other.serial.utf8) {
            return screen.serial.utf8.lexicographicallyPrecedes(other.serial.utf8)
        }
        return screen.name.utf8.lexicographicallyPrecedes(other.name.utf8)
    }

    private static func isLowerCaseHexDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
    }

    /// `value` in lower-case hex, zero-padded to at least `digits` digits; a negative value as its
    /// 64-bit pattern.
    private static func hex<Value: BinaryInteger>(_ value: Value, digits: Int) -> String {
        let text = String(UInt64(truncatingIfNeeded: value), radix: 16)
        return String(repeating: "0", count: max(0, digits - text.count)) + text
    }
}
