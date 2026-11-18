// The HID interfaces the device layer is shown, and which of them make up one touchscreen.
// Nothing here calls IOKit.

import Foundation
import TactileReading

/// One HID interface while it is connected: its IORegistry entry ID.
typealias HIDInterfaceID = UInt64

/// One application collection's usage, as IOKit lists an interface's usages.
struct HIDUsage: Hashable, Sendable {
    var page: Int
    var usage: Int

    /// The Digitizer usage page: touchscreens, pens, digitizer tablets.
    static let digitizerPage = 0x0D
    static let touchScreen = HIDUsage(page: 0x0D, usage: 0x04)
    static let pen = HIDUsage(page: 0x0D, usage: 0x02)
    static let pointer = HIDUsage(page: 0x01, usage: 0x01)
    static let mouse = HIDUsage(page: 0x01, usage: 0x02)
    static let keyboard = HIDUsage(page: 0x01, usage: 0x06)
}

/// What the system says about one HID interface it matched, before anything is opened.
struct HIDInterfaceDescription: Equatable, Sendable {
    var id: HIDInterfaceID
    /// The USB location ID. Every interface of one USB device shares it; 0 when there is none.
    var locationID: UInt32
    var vendorID: Int
    var productID: Int
    /// As reported; empty when there is none.
    var serial: String
    /// The product name as reported; empty when there is none.
    var product: String
    /// The usages of its application collections, as IOKit lists them (its usage pairs, or else
    /// its primary usage).
    var usages: [HIDUsage]
    /// The HID report descriptor, when the interface publishes one.
    var descriptor: [UInt8]?
    /// IOKit's largest input report size, when it gives one.
    var maxInputReportSize: Int?
}

/// One HID interface the device layer knows of, with its decoder.
struct KnownInterface: Sendable {
    let description: HIDInterfaceDescription
    /// `nil` when the interface publishes no descriptor or one that can't be read.
    let decoder: InterfaceDecoder?
    /// When it arrived, relative to the others: lower is earlier.
    let arrival: Int

    init(_ description: HIDInterfaceDescription, arrival: Int) {
        self.description = description
        self.arrival = arrival
        decoder = description.descriptor.flatMap { InterfaceDecoder(descriptor: $0) }
    }

    var id: HIDInterfaceID { description.id }
    var locationID: UInt32 { description.locationID }
    /// A touchscreen interface: IOKit lists a Touch Screen collection, or its descriptor has one.
    var isTouchscreen: Bool { description.usages.contains(.touchScreen) || decoder?.kind == .touchscreen }
    /// A mouse interface: its descriptor has a Mouse collection and no Touch Screen one.
    var isMouse: Bool { !isTouchscreen && decoder?.kind == .mouse }
    /// A mouse interface that may be a touchscreen's sibling: IOKit lists it as a Mouse (an empty
    /// list is refused), and it lists nothing on the Digitizer page (a pen display's pen interface
    /// carries a Mouse collection beside a Pen or a Digitizer one) and no Keyboard.
    var canBeMouseSibling: Bool {
        let usages = description.usages
        return isMouse && usages.contains(.mouse) && !usages.contains { $0.page == HIDUsage.digitizerPage }
            && !usages.contains(.keyboard)
    }
    /// Finger collections per touch report; 0 when unknown.
    var contactSlots: Int { decoder?.contactSlots ?? 0 }
    /// The buffer IOKit fills with each input report.
    var reportBufferSize: Int { InterfaceChoice.reportBufferSize(decoder: decoder, maxInputReportSize: description.maxInputReportSize) }
}

/// One touchscreen's interfaces: the touchscreen interface it is read from, and its mouse sibling.
struct InterfaceGroup: Equatable, Sendable {
    var touch: HIDInterfaceID
    var mouse: HIDInterfaceID?
}

/// Which interfaces make up a touchscreen.
///
/// - A touchscreen is a USB device with a touchscreen interface. Its other interfaces are those at
///   the same USB location ID.
/// - When it has more than one touchscreen interface, the one with the most finger collections is
///   used; on a tie, the first to arrive.
/// - Its mouse sibling is the first interface to arrive at the same location, with the same USB
///   vendor and product ID, whose descriptor is a mouse's, which IOKit lists as a Mouse, and which
///   IOKit lists with no Digitizer usage and no Keyboard. Nothing else is ever a sibling: not a
///   mouse elsewhere or of another device, not a pen display's pen interface, not a digitizer
///   tablet, not a combined keyboard, not a vendor interface.
/// - Location 0 means no USB location: such an interface is never grouped with another.
enum InterfaceChoice {
    /// The touchscreen interface to use among `candidates`, which share one location.
    static func touchInterface(among candidates: [KnownInterface]) -> KnownInterface? {
        candidates.filter(\.isTouchscreen).min { a, b in
            a.contactSlots != b.contactSlots ? a.contactSlots > b.contactSlots : a.arrival < b.arrival
        }
    }

    /// The mouse sibling of the touchscreen read from `touch`, among `candidates`.
    static func mouseSibling(of touch: KnownInterface, among candidates: [KnownInterface]) -> KnownInterface? {
        guard touch.locationID != 0 else { return nil }
        return candidates.filter {
            $0.locationID == touch.locationID && $0.description.vendorID == touch.description.vendorID
                && $0.description.productID == touch.description.productID && $0.canBeMouseSibling
        }.min { $0.arrival < $1.arrival }
    }

    /// Every touchscreen among `interfaces`, in the order their touchscreen interfaces arrived.
    static func groups(_ interfaces: [KnownInterface]) -> [InterfaceGroup] {
        let touchscreens = interfaces.filter(\.isTouchscreen)
        var found: [(arrival: Int, group: InterfaceGroup)] = []
        for touch in touchscreens where touch.locationID == 0 {
            found.append((touch.arrival, InterfaceGroup(touch: touch.id, mouse: nil)))
        }
        for location in Set(touchscreens.map(\.locationID)).subtracting([0]) {
            guard let touch = touchInterface(among: touchscreens.filter { $0.locationID == location }) else { continue }
            let mouse = mouseSibling(of: touch, among: interfaces)
            found.append((touch.arrival, InterfaceGroup(touch: touch.id, mouse: mouse?.id)))
        }
        return found.sorted { $0.arrival < $1.arrival }.map(\.group)
    }

    /// The size of the buffer for one interface's input reports: the longest report its descriptor
    /// or IOKit gives, at least 64 bytes, plus the 16-byte margin the survey tool used.
    static func reportBufferSize(decoder: InterfaceDecoder?, maxInputReportSize: Int?) -> Int {
        max(decoder?.maxInputReportLength ?? 0, maxInputReportSize ?? 0, 64) + 16
    }
}

/// The host's clock: one clock for reports and for the app's ticks.
///
/// A HID report's timestamp is `mach_absolute_time` ticks. `ProcessInfo.processInfo.systemUptime`,
/// which the app's ticks use, counts the same ticks in seconds, so a report's time in seconds is
/// its ticks × `numer` / `denom` (from `mach_timebase_info`) / 10⁹.
///
/// How this was checked, on 2026-11-14 on the Mac with the panels (a timebase of 125/3): read one
/// after the other, `systemUptime` gave 274791.37540270836 s and `mach_absolute_time` converted
/// this way gave 274791.37540270836 s, the same to the last digit. `mach_continuous_time`, the
/// other candidate, gave 301405.27 s: it also counts time asleep, so it is not this clock. The test
/// `testHostClock` checks the agreement again on every run, to within half a second.
enum HostClock {
    static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// A `mach_absolute_time` value in seconds.
    static func seconds(fromMachTime time: UInt64, timebase: mach_timebase_info_data_t = timebase) -> TimeInterval {
        guard timebase.denom != 0 else { return 0 }
        return Double(time) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }

    /// A report's time in seconds: its timestamp, or `now` when it has none or the timestamp is
    /// more than a second ahead of `now` (so it is not on the host's clock after all).
    static func reportTime(timestamp: UInt64, now: TimeInterval, timebase: mach_timebase_info_data_t = timebase) -> TimeInterval {
        guard timestamp != 0 else { return now }
        let time = seconds(fromMachTime: timestamp, timebase: timebase)
        return time > now + 1 ? now : time
    }
}
