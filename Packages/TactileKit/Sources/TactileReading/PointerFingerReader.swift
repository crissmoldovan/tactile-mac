// Mouse reports → frames: a touchscreen that stays in mouse mode, read as one finger.

import CoreGraphics
import Foundation

/// Reads one mouse interface's pointer reports as one finger on the glass.
///
/// Some touchscreens never send touches: like the wch.cn strip, they accept the switch to
/// multi-touch and carry on as a mouse, reporting one absolute point and a button. Their mouse
/// interface is read as one finger: the point is where it is, the first button is it touching.
///
/// The rules:
/// - While the first button is down and the report has an absolute position, there is one contact,
///   with ID 0, at that position. Other buttons are not read.
/// - When the first button goes up after a press that gave a contact, one empty frame.
/// - Every other report gives `nil`. A report with the button up while it was already up gives
///   `nil`, so an untouched mouse-mode panel that keeps sending its point gives no stream of empty
///   frames. A report with the button down and no position gives `nil`, so a relative mouse
///   (`position` nil) never gives a contact, and its release no empty frame.
/// - **The guard:** a press that begins less than `guardInterval` after the last release is not a
///   new touch. Nothing is returned for it until the button has been released; that release gives
///   no frame either, and does not restart the interval.
///
/// A press begins at the report where the first button goes down, whether or not that report has
/// a position. The interval runs from the last release that gave an empty frame: the end of the
/// last touch. Times are the host's clock as the caller passes them. A press stamped earlier than
/// that release can't be shown to have come soon after it, so it is a new touch, and a clock that
/// steps back never leaves the reader refusing every press until the clock catches up.
///
/// Such a panel reports one point however many fingers touch it. Measured on the wch.cn strip, the
/// point never jumps while pressed, but four fingers lifting can end in a phantom press 16 ms after
/// the release and far from it: that is what the guard is for. A two-finger tap arrives as two
/// presses 0.133 s apart, and is indistinguishable from a quick double-tap.
///
/// The reader holds three values whatever it is fed, and no report or time can trap it.
public struct PointerFingerReader: Sendable {
    /// How soon after a touch ends a press is refused, in seconds. 0 refuses nothing.
    private let guardInterval: TimeInterval
    /// The first button as the last report left it.
    private var press: Press = .up
    /// When the last touch ended: the time of the last empty frame, or `nil` before the first.
    private var lastRelease: TimeInterval?

    private enum Press: Sendable {
        /// The first button is up.
        case up
        /// It is down for a touch; `touching` once a report of this press has given a contact.
        case down(touching: Bool)
        /// It is down for a press the guard refused.
        case refused
    }

    /// A reader with the glass clear. `guardInterval` is how soon after a touch ends a new press is
    /// refused, in seconds.
    public init(guardInterval: TimeInterval = 0.05) {
        self.guardInterval = guardInterval
    }

    /// Adds one pointer report, which arrived at `time` on the host's clock, in seconds. Returns a
    /// frame with contact 0 while a touch is down, an empty frame when it ends, and `nil` otherwise.
    public mutating func add(_ report: PointerReport, at time: TimeInterval) -> ContactFrame? {
        let buttonDown = report.buttons & 1 != 0
        switch (press, buttonDown) {
        case (.up, false), (.refused, true):
            return nil

        case (.refused, false):
            press = .up
            return nil

        case (.up, true):
            if beginsTooSoon(time) {
                press = .refused
                return nil
            }
            press = .down(touching: false)
            return touch(report, at: time)

        case (.down, true):
            return touch(report, at: time)

        case (.down(let touching), false):
            press = .up
            guard touching else { return nil }
            lastRelease = time
            return ContactFrame(time: time, contacts: [])
        }
    }

    /// Whether a press at `time` begins less than `guardInterval` after the last touch ended. Plain
    /// comparisons, so a NaN or a negative interval refuses nothing rather than trapping.
    private func beginsTooSoon(_ time: TimeInterval) -> Bool {
        guard let lastRelease else { return false }
        let since = time - lastRelease
        return since >= 0 && since < guardInterval
    }

    /// The frame of a report with the button down for a touch: contact 0 at its position, or `nil`
    /// when it has none.
    private mutating func touch(_ report: PointerReport, at time: TimeInterval) -> ContactFrame? {
        guard let position = report.position else { return nil }
        press = .down(touching: true)
        return ContactFrame(time: time, contacts: [Contact(id: 0, position: position)])
    }
}
