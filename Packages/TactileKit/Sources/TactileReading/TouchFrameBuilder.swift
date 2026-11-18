// Touch reports → frames: every finger down on the glass, once per complete scan of the panel.

import CoreGraphics
import Foundation

/// Builds frames from one touch interface's reports.
///
/// The rules:
/// - A contact is down while a slot reports it with the tip on. A slot with the tip off ends that
///   contact, and a contact that was down and is absent from a complete scan has lifted, so a frame
///   is exactly the contacts its scan reports with the tip on.
/// - A report with a Contact Count other than 0 starts a scan, which reads that many slots in
///   report order. Only the first `contactCount` slots of a report are read; what a panel leaves
///   in the slots after them is not. When the report carries fewer slots than its count, the scan
///   continues over the following reports, whose count is 0, until its own count has been read,
///   however many slots the interface's largest report has. The frame is timed at the scan's
///   first report.
/// - A new scan sets aside one that never completed. A count of 0 continues the scan in progress;
///   with no scan in progress, it is a complete scan with nobody down. A negative count is taken
///   as 0.
/// - A panel with no Contact Count: every report is a complete scan, and all its slots are read,
///   up to 256 (see below).
/// - A slot with no contact ID, or with a position missing, is ignored.
/// - One contact ID in several slots of a scan is one contact: down if any of them has the tip on,
///   at the position of the first that does.
/// - Every complete scan gives a frame, including the empty one when the last finger lifts. That
///   empty frame is what separates two touches that reuse one contact ID.
///
/// Fingers are tracked by contact ID, never by slot, and times are the host's clock as the caller
/// passes them, never the panel's Scan Time.
///
/// A report comes from whatever is plugged in, so it is not trusted: a scan reads at most 256
/// slots (`mostSlotsInAScan`), whatever its count or its number of slots, and the builder holds
/// at most one scan.
public struct TouchFrameBuilder: Sendable {
    /// The most slots one scan reads. No touchscreen reports this many fingers; the bound keeps the
    /// builder's memory fixed when a Contact Count is garbage.
    static let mostSlotsInAScan = 256

    /// A split scan still arriving, or `nil`.
    private var arriving: Scan?

    /// One scan as it is read: when its first report came, the contacts down so far by ID, and how
    /// many slots are still to read.
    private struct Scan: Sendable {
        let time: TimeInterval
        var slotsToRead: Int
        var contacts: [Int: Contact] = [:]

        init(time: TimeInterval, slotsToRead: Int) {
            self.time = time
            self.slotsToRead = min(max(0, slotsToRead), TouchFrameBuilder.mostSlotsInAScan)
        }

        /// Reads the report's slots, in report order, up to the number still to read.
        mutating func read(_ slots: [SlotReading]) {
            let count = min(slotsToRead, slots.count)
            for slot in slots.prefix(count) where slot.tip {
                guard let id = slot.contactID, let position = slot.position, contacts[id] == nil else { continue }
                contacts[id] = Contact(id: id, position: position, size: slot.size, isConfident: slot.isConfident)
            }
            slotsToRead -= count
        }

        var frame: ContactFrame {
            ContactFrame(time: time, contacts: contacts.values.sorted { $0.id < $1.id })
        }
    }

    /// A builder with no scan in progress.
    public init() {}

    /// Adds one touch report, which arrived at `time` on the host's clock, in seconds. Returns the
    /// frame when the report completes a scan, and `nil` while a split scan is still arriving.
    public mutating func add(_ report: TouchReport, at time: TimeInterval) -> ContactFrame? {
        let count = report.contactCount.map { max(0, $0) }

        if count == 0, var scan = arriving {
            arriving = nil  // so the scan's contacts are read in place, not copied
            scan.read(report.slots)
            guard scan.slotsToRead == 0 else {
                arriving = scan
                return nil
            }
            return scan.frame
        }

        arriving = nil
        var scan = Scan(time: time, slotsToRead: count ?? report.slots.count)
        scan.read(report.slots)
        // With no Contact Count the scan has read every slot, or the first 256 of a report with more,
        // so such a scan never continues.
        if scan.slotsToRead > 0 {
            arriving = scan
            return nil
        }
        return scan.frame
    }
}
