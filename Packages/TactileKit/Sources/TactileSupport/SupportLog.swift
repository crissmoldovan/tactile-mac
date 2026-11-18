// The log book's lines about one touchscreen, for the report, and taking serial numbers and the
// home folder out of text.

import Foundation
import TactileDevices

/// Takes what could say who someone is out of text that goes in a report.
public enum SupportRedaction {
    public static let serialRemoved = "[serial removed]"

    /// `text` with:
    /// - each of `serials` wherever it appears, longest first, when it is four characters or longer
    ///   (a shorter one is too common a string to take out without spoiling the text);
    /// - whatever follows the word "serial" in quotes (`serial "…"`, `Serial: "…"`), whichever device's
    ///   it is;
    /// - the home folder `home` as `~`, and any other `/Users/<name>` as `/Users/[user]`.
    public static func redact(_ text: String, serials: [String], home: String?) -> String {
        var text = text
        // Every serial known first, longest first, so a quote inside one can't stop the pattern short.
        for serial in Set(serials).filter({ $0.count >= 4 }).sorted(by: { $0.count > $1.count }) {
            text = text.replacingOccurrences(of: serial, with: serialRemoved)
        }
        text = text.replacingOccurrences(
            of: #"([Ss]erial:?[ ]*")[^"]*(")"#, with: "$1\(serialRemoved)$2", options: .regularExpression)
        if let home, home.count > 1 {
            text = text.replacingOccurrences(of: home, with: "~")
        }
        text = text.replacingOccurrences(of: #"/Users/[^/\s"']+"#, with: "/Users/[user]", options: .regularExpression)
        return text
    }
}

/// The log book's lines about one device, as the report holds them.
public enum SupportLog {
    /// `entries` (the log book's lines about the device, found by its interfaces), oldest first, each
    /// as `<UTC time> [<category>] <text>`, redacted once more (`SupportRedaction`) with every serial
    /// number Tactile knows, though the log book holds none.
    public static func lines(_ entries: [DeviceLogEntry], serials: [String], home: String?) -> [String] {
        entries.map { "\(time($0.date)) [\($0.category)] \(SupportRedaction.redact($0.text, serials: serials, home: home))" }
    }

    static func time(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
