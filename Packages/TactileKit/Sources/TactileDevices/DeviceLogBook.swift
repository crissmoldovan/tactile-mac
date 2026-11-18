// Tactile's own record of what it did with each device this session, for the touchscreen check's
// report: kept in memory, bounded, written plain and already redacted, and found by the interface
// each line is about. The report reads this, never the system log, so it holds only what was
// written for it.

import Foundation

/// One line of the record.
public struct DeviceLogEntry: Equatable, Sendable {
    public var date: Date
    /// The interface the line is about: a touchscreen's touch interface (its IORegistry entry ID,
    /// the same for every IOKit client while it is connected), or the interface the check keys a
    /// device by. Two identical units never share one.
    public var interface: UInt64
    /// "devices" for the touchscreen source's lines, "support" for the check's.
    public var category: String
    public var text: String

    public init(date: Date, interface: UInt64, category: String, text: String) {
        self.date = date
        self.interface = interface
        self.category = category
        self.text = text
    }
}

/// The record: the newest `capacity` lines, each redacted as it is written (`redact`). Its writers
/// write no serial number and no name, only what they did; the redaction is the second guard.
@MainActor
public final class DeviceLogBook {
    /// The app's: the touchscreen source and the check write here.
    public static let shared = DeviceLogBook()
    nonisolated public static let capacity = 2000
    nonisolated public static let maxLineLength = 300

    private let capacity: Int
    private let now: () -> Date
    private var lines: [DeviceLogEntry] = []
    /// Where the oldest line is, once the record is full.
    private var oldest = 0

    public init(capacity: Int = DeviceLogBook.capacity, now: @escaping () -> Date = Date.init) {
        self.capacity = max(1, capacity)
        self.now = now
    }

    /// Writes a line about `interface`.
    public func note(_ interface: UInt64, category: String, _ text: String) {
        let entry = DeviceLogEntry(date: now(), interface: interface, category: category, text: Self.redact(text))
        if lines.count < capacity {
            lines.append(entry)
        } else {
            lines[oldest] = entry
            oldest = (oldest + 1) % capacity
        }
    }

    /// The lines about any of `interfaces`, oldest first.
    public func entries(about interfaces: Set<UInt64>) -> [DeviceLogEntry] {
        (lines[oldest...] + lines[..<oldest]).filter { interfaces.contains($0.interface) }
    }

    /// `text` with anything in double quotes (a product, a display, a serial number) replaced by
    /// `"[removed]"`, control characters as spaces, bidi and other format characters taken out,
    /// spaces closed up, and at most `maxLineLength` characters.
    nonisolated public static func redact(_ text: String) -> String {
        var unquoted = text.replacingOccurrences(of: #""[^"]*""#, with: #""[removed]""#, options: .regularExpression)
        // A quote left unpaired is the last one: what follows it goes too.
        if unquoted.filter({ $0 == "\"" }).count % 2 == 1, let last = unquoted.lastIndex(of: "\"") {
            unquoted = String(unquoted[..<last]) + #""[removed]"#
        }
        var scalars = String.UnicodeScalarView()
        for scalar in unquoted.unicodeScalars {
            if scalar.value <= 31 || (127...159).contains(scalar.value) {
                scalars.append(" ")
            } else if scalar.properties.generalCategory != .format {
                scalars.append(scalar)
            }
        }
        let spaced = String(scalars).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return String(spaced.prefix(maxLineLength))
    }
}
