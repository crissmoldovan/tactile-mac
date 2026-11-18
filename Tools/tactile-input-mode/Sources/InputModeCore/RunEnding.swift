// How a run that opened the strip ends: what is printed last, and the exit code.

import Foundation

public struct RunEnding: Equatable, Sendable {
    /// The last line of a run whose closing write of mouse emulation failed while the strip was attached.
    public static let notPutBack = "NOT put back: unplug the strip's touch cable and plug it back in."
    /// Exit codes: 0 ran; 1 a write was refused or not accepted, or a wait timed out; 2 no strip;
    /// 3 Tactile or Touch Up running; 4 not put back; 64 usage.
    public static let notPutBackExitCode: Int32 = 4

    /// Whether the closing write put the strip back: either write accepted, or the strip has gone
    /// (plugged in again, it starts in mouse emulation). `fallbackAccepted` is nil when the
    /// whole-report write was accepted and no fallback was tried.
    public static func putBack(wholeReportAccepted: Bool, fallbackAccepted: Bool?, attachedAfter: Bool) -> Bool {
        wholeReportAccepted || fallbackAccepted == true || !attachedAfter
    }

    /// Printed after everything else.
    public let lines: [String]
    public let exitCode: Int32

    public init(restored: Bool, writesAccepted: Bool) {
        if !restored {
            lines = [Self.notPutBack]
            exitCode = Self.notPutBackExitCode
        } else {
            lines = []
            exitCode = writesAccepted ? 0 : 1
        }
    }
}
