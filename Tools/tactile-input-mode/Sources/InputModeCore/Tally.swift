// Counting what each interface sends while listening, and saying what that means.

import Foundation

public struct InterfaceTally: Equatable, Sendable {
    public let role: InterfaceRole
    public let descriptor: HIDDescriptor?
    public private(set) var reports = 0
    /// Reports per report ID; empty when the descriptor is unknown or uses no IDs.
    public private(set) var byReportID: [UInt8: Int] = [:]
    public private(set) var firstReport: [UInt8]?
    /// Touchscreen: the most tip switches set in one report.
    public private(set) var mostContactsDown = 0
    /// Mouse: reports with button 1 held (the finger on the glass, in mouse emulation).
    public private(set) var reportsWithButtonDown = 0

    public init(role: InterfaceRole, descriptor: HIDDescriptor?) {
        self.role = role
        self.descriptor = descriptor
    }

    public mutating func add(_ report: [UInt8]) {
        reports += 1
        if firstReport == nil { firstReport = report }
        guard let descriptor else { return }
        let id: UInt8 = descriptor.usesReportIDs ? (report.first ?? 0) : 0
        if descriptor.usesReportIDs { byReportID[id, default: 0] += 1 }
        let tips = descriptor.elements(.input, id, usage: Usages.tipSwitch)
            .filter { (descriptor.value(of: $0.field, element: $0.element, in: report) ?? 0) != 0 }.count
        mostContactsDown = max(mostContactsDown, tips)
        if let button = descriptor.elements(.input, id, usage: Usages.button1).first,
           (descriptor.value(of: button.field, element: button.element, in: report) ?? 0) != 0 {
            reportsWithButtonDown += 1
        }
    }
}

public enum ListenOutcome: Equatable, Sendable {
    /// The touchscreen interface sent a report with at least one finger down: the only success.
    case touchesArrived
    /// The touchscreen interface sent reports, but none with a finger down (an empty release frame
    /// after a mode write, or reports whose fingers can't be read). Not shown to work.
    case touchReportsWithoutFingers
    /// Nothing from the touchscreen interface, but the mouse interface sent: a finger was there.
    case stayedInMouseMode
    /// Nothing at all from the touchscreen or mouse interface.
    case nothingArrived
}

public struct ListenSummary: Equatable, Sendable {
    public var tallies: [InterfaceTally]
    public var seconds: Double

    public init(tallies: [InterfaceTally], seconds: Double) {
        self.tallies = tallies
        self.seconds = seconds
    }

    private func total(_ role: InterfaceRole) -> Int { tallies.filter { $0.role == role }.reduce(0) { $0 + $1.reports } }

    public var touchReports: Int { total(.touchscreen) }
    public var mouseReports: Int { total(.mouse) }
    public var vendorReports: Int { total(.vendor) }

    /// The most fingers down in one touchscreen report.
    public var mostFingers: Int { tallies.filter { $0.role == .touchscreen }.map(\.mostContactsDown).max() ?? 0 }

    public var outcome: ListenOutcome {
        if touchReports > 0 { return mostFingers >= 1 ? .touchesArrived : .touchReportsWithoutFingers }
        if mouseReports > 0 { return .stayedInMouseMode }
        return .nothingArrived
    }

    /// The result, first line first. The first line always starts "touch reports: N".
    public func lines() -> [String] {
        var out: [String] = []
        switch outcome {
        case .touchesArrived: out.append("touch reports: \(touchReports) (most fingers in one report: \(mostFingers))")
        case .touchReportsWithoutFingers: out.append("touch reports: \(touchReports), none with a finger down")
        case .stayedInMouseMode, .nothingArrived: out.append("touch reports: 0")
        }
        let pressed = tallies.filter { $0.role == .mouse }.reduce(0) { $0 + $1.reportsWithButtonDown }
        out.append("mouse reports: \(mouseReports)" + (mouseReports > 0 ? " (\(pressed) with the button held)" : ""))
        if tallies.contains(where: { $0.role == .vendor }) || vendorReports > 0 {
            var line = "vendor reports: \(vendorReports)"
            if let first = tallies.first(where: { $0.role == .vendor && $0.firstReport != nil })?.firstReport {
                line += " (first: \(hexBytes(Array(first.prefix(16))))\(first.count > 16 ? " …" : ""))"
            }
            out.append(line)
        }
        switch outcome {
        case .touchesArrived:
            out.append("The touchscreen interface sent touch reports with a finger down: this method WORKED.")
        case .touchReportsWithoutFingers:
            out.append("The touchscreen interface sent reports, but none with a finger down: not shown to work. Note this, and run the step again.")
        case .stayedInMouseMode:
            out.append("A finger was on the glass (the mouse interface sent), and the touchscreen interface sent nothing: this method did not work.")
        case .nothingArrived:
            out.append(String(format: "Nothing arrived in %.0f s, so nothing was touching the glass: this run shows only whether the write was accepted, not whether the method works.", seconds))
        }
        return out
    }
}
