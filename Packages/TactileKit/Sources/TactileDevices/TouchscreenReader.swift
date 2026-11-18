// One touchscreen's raw reports → frames: which of its interfaces feeds, and what it says.

import Foundation
import TactileReading

/// Reads one touchscreen: the raw reports of its touchscreen interface and of its mouse interface,
/// each as it arrived, into frames of contacts.
///
/// A touchscreen sends touches from its touchscreen interface, or, when it stays in mouse mode,
/// one finger from its pointer reports. Which one is decided afresh each time it is taken (see
/// `reset()`), from what it sends:
///
/// - `origin` starts `undetermined`, or `unreadable` when there is neither a touch decoder nor a
///   mouse decoder.
/// - The first touch report from the touch interface that **carries a contact** (a finger slot
///   with its tip on, a contact ID and a position, among the slots its Contact Count says to read)
///   makes the origin `touchInterface`. A touch report with every tip off is not a finger and
///   decides nothing: a panel in mouse mode may send one.
/// - The first pointer report with an absolute position, while the origin is `undetermined`,
///   makes it `mouseInterface`, **whichever interface it arrives on**: some panels put their Mouse
///   collection on the touchscreen interface itself. Pointer reports from both interfaces are one
///   finger.
/// - **A touch report always wins.** When the origin is `mouseInterface` and the touch interface
///   sends a touch report that carries a contact, the origin becomes `touchInterface` until the
///   next reset. If the mouse finger was down, an empty frame at the touch report's time ends it
///   first, so one touch is never two fingers. From then on pointer reports are ignored.
/// - A report that is `.other`, undecodable, short or empty gives nothing and changes nothing. A
///   touch report from the mouse interface is ignored. A relative pointer (no absolute position) is
///   never a finger and decides nothing.
///
/// The frames themselves come from `TouchFrameBuilder` (touch reports) and `PointerFingerReader`
/// with its 50 ms guard (pointer reports), unchanged.
public struct TouchscreenReader: Sendable {
    /// The interface a report arrived on.
    public enum Interface: Sendable { case touch, mouse }

    /// The guard of the mouse finger, in seconds: a press that begins less than this after the last
    /// release is not a new touch. Measured on the wch.cn strip (see the design).
    public static let mouseGuardInterval: TimeInterval = 0.05

    /// Where this touchscreen's touches are coming from.
    public private(set) var origin: TouchOrigin

    private let touch: InterfaceDecoder?
    private var mouse: InterfaceDecoder?
    private var builder = TouchFrameBuilder()
    private var pointer = PointerFingerReader(guardInterval: TouchscreenReader.mouseGuardInterval)
    /// The mouse finger is down: the last frame of the pointer reports had a contact.
    private var mouseFingerDown = false

    /// `touch` is the touchscreen interface's decoder and `mouse` its mouse interface's, each `nil`
    /// when there is none, its descriptor can't be read, or it could not be opened.
    public init(touch: InterfaceDecoder?, mouse: InterfaceDecoder?) {
        self.touch = touch
        self.mouse = mouse
        origin = .undetermined
        origin = canGiveContacts ? .undetermined : .unreadable
    }

    /// One raw report, starting with the report ID byte when the interface uses IDs, which arrived
    /// on `interface` at `time` on the host's clock, in seconds. Returns the frames it completes:
    /// none, one, or (on a change of origin) an empty frame that ends the mouse finger followed by
    /// the first touch frame.
    public mutating func add(_ bytes: [UInt8], from interface: Interface, at time: TimeInterval) -> [ContactFrame] {
        switch interface {
        case .touch:
            switch touch?.decode(bytes) {
            case .touch(let report)?: return addTouch(report, at: time)
            case .pointer(let report)?: return addPointer(report, at: time)
            case .other?, nil: return []
            }
        case .mouse:
            guard case .pointer(let report)? = mouse?.decode(bytes) else { return [] }
            return addPointer(report, at: time)
        }
    }

    /// The touchscreen was released or taken again: forget every finger and every scan, and decide
    /// the origin afresh. `TouchFrameBuilder` and `PointerFingerReader` have no reset of their own,
    /// so both are made anew; the mouse finger's guard starts clean.
    public mutating func reset() {
        builder = TouchFrameBuilder()
        pointer = PointerFingerReader(guardInterval: Self.mouseGuardInterval)
        mouseFingerDown = false
        origin = canGiveContacts ? .undetermined : .unreadable
    }

    /// The mouse interface came, or went, after the reader was made. A decided origin stays as it
    /// is; an undecided one becomes `unreadable` or `undetermined` as the interfaces now allow.
    /// Nothing is ended here: a finger down on a mouse interface that goes away stays down until
    /// a touch report ends it or the reader is reset.
    public mutating func setMouse(_ decoder: InterfaceDecoder?) {
        mouse = decoder
        if origin == .undetermined || origin == .unreadable {
            origin = canGiveContacts ? .undetermined : .unreadable
        }
    }

    private var canGiveContacts: Bool { touch != nil || mouse != nil }

    private mutating func addTouch(_ report: TouchReport, at time: TimeInterval) -> [ContactFrame] {
        var frames: [ContactFrame] = []
        if origin != .touchInterface {
            guard Self.carriesContact(report) else { return [] }
            origin = .touchInterface
            if mouseFingerDown {
                frames.append(ContactFrame(time: time, contacts: []))
                mouseFingerDown = false
            }
        }
        if let frame = builder.add(report, at: time) { frames.append(frame) }
        return frames
    }

    private mutating func addPointer(_ report: PointerReport, at time: TimeInterval) -> [ContactFrame] {
        if origin == .undetermined {
            guard report.position != nil else { return [] }
            origin = .mouseInterface
        }
        guard origin == .mouseInterface, let frame = pointer.add(report, at: time) else { return [] }
        mouseFingerDown = !frame.contacts.isEmpty
        return [frame]
    }

    /// Whether a touch report has a finger down: a slot with its tip on, a contact ID and a
    /// position, among the slots `TouchFrameBuilder` reads from a report that starts a scan.
    private static func carriesContact(_ report: TouchReport) -> Bool {
        let read = report.contactCount.map { report.slots.prefix(max(0, $0)) } ?? report.slots[...]
        return read.contains { $0.tip && $0.contactID != nil && $0.position != nil }
    }
}
