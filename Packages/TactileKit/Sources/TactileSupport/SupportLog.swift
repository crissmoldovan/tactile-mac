// Tactile's own log lines about one touchscreen, for the report, and taking serial numbers and the
// home folder out of text.

import Foundation
import OSLog

/// One entry of Tactile's log.
public struct SupportLogEntry: Equatable, Sendable {
    public var date: Date
    public var category: String
    public var message: String

    public init(date: Date, category: String, message: String) {
        self.date = date
        self.category = category
        self.message = message
    }
}

/// Takes what could say who someone is out of text that goes in a report.
public enum SupportRedaction {
    public static let serialRemoved = "[serial removed]"

    /// `text` with:
    /// - whatever follows the word "serial" in quotes (`serial "…"`, `Serial: "…"`), whichever device's
    ///   it is, as the device layer logs a serial;
    /// - each of `serials` wherever it appears, when it is four characters or longer (a shorter one
    ///   is too common a string to take out without spoiling the text);
    /// - the home folder `home` as `~`, and any other `/Users/<name>` as `/Users/[user]`.
    public static func redact(_ text: String, serials: [String], home: String?) -> String {
        var text = text
        text = text.replacingOccurrences(
            of: #"([Ss]erial:?[ ]*")[^"]*(")"#, with: "$1\(serialRemoved)$2", options: .regularExpression)
        for serial in serials where serial.count >= 4 {
            text = text.replacingOccurrences(of: serial, with: serialRemoved)
        }
        if let home, home.count > 1 {
            text = text.replacingOccurrences(of: home, with: "~")
        }
        text = text.replacingOccurrences(of: #"/Users/[^/\s"']+"#, with: "/Users/[user]", options: .regularExpression)
        return text
    }
}

/// Tactile's log lines about one touchscreen in this session.
public enum SupportLog {
    /// The lines of `entries` about the device with `usbID` (at `location`, as Tactile writes it:
    /// "01141000"), oldest first, each as `<UTC time> [<category>] <message>`, redacted
    /// (`SupportRedaction`):
    /// - the touchscreen source's line announcing it (its USB ID, and its location when known) gives
    ///   the handle Tactile knew it by ("device-3"); every line naming that handle is kept;
    /// - a line naming its USB ID is kept too (the check's own lines), unless it names a handle that
    ///   isn't its own: another touchscreen of the same model.
    public static func lines(_ entries: [SupportLogEntry], usbID: String, location: String?, serials: [String],
                             home: String?) -> [String] {
        let usb = usbID.lowercased()
        var handles: Set<String> = []
        for entry in entries {
            let message = entry.message.lowercased()
            guard message.contains(usb), location.map({ message.contains("0x" + $0.lowercased()) }) ?? true else { continue }
            if message.contains("connected device-") { handles.formUnion(Self.handles(in: entry.message)) }
        }
        return entries.filter { entry in
            let named = Self.handles(in: entry.message)
            if !named.isDisjoint(with: handles) { return true }
            return entry.message.lowercased().contains(usb) && named.isEmpty
        }
        .map { "\(Self.time($0.date)) [\($0.category)] \(SupportRedaction.redact($0.message, serials: serials, home: home))" }
    }

    /// Every "device-N" in a message.
    static func handles(in message: String) -> Set<String> {
        guard let expression = try? NSRegularExpression(pattern: #"device-[0-9]+"#) else { return [] }
        let range = NSRange(message.startIndex..., in: message)
        return Set(expression.matches(in: message, range: range).compactMap { Range($0.range, in: message).map { String(message[$0]) } })
    }

    static func time(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    /// This process's entries in Tactile's subsystem (`com.crissmoldovan.tactile`), from the unified
    /// log, oldest first: what `OSLogStore` gives for the current process. Empty when it can't be read.
    /// The app calls it; tests never do.
    public static func readThisProcess() -> [SupportLogEntry] {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let predicate = NSPredicate(format: "subsystem == %@", "com.crissmoldovan.tactile")
            return try store.getEntries(at: nil, matching: predicate).compactMap { entry in
                guard let entry = entry as? OSLogEntryLog else { return nil }
                return SupportLogEntry(date: entry.date, category: entry.category, message: entry.composedMessage)
            }
        } catch {
            return []
        }
    }
}
