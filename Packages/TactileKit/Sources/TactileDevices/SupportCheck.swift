// The touchscreen check's steps: what the device is (read only), the switches a take makes, the
// touches with one, two and five fingers, and the verdict. It runs on `SupportProbe`, so every step
// runs in the tests against the fake HID system with the surveyed panels' own descriptors and reports.

import CoreGraphics
import Foundation
import TactileReading

/// How many fingers a touch step asks for.
public enum SupportFingers: Int, CaseIterable, Codable, Sendable {
    case one = 1, two = 2, five = 5
}

/// How a touch step ended.
public enum SupportStepEnding: String, Codable, Sendable {
    /// The fingers asked for came, then every finger lifted, and the glass stayed clear a moment.
    case done
    /// Its 15 seconds ran out.
    case timeUp = "time up"
    /// The person pressed Skip. What had come by then is kept.
    case skipped
    /// The check stopped during it: the window closed, or the device went.
    case stopped
}

/// The check's verdict.
public enum SupportVerdict: String, Codable, Sendable, CaseIterable {
    /// Several fingers at once, through its touch interface.
    case worksFully = "works-fully"
    /// One finger at a time: from its touch interface, or as a mouse.
    case worksWithOneFinger = "works-with-one-finger"
    /// Nothing came, or nothing Tactile could read a touch from.
    case doesNotWork = "doesnt-work"
}

/// Why the verdict is what it is, for its one sentence.
public enum SupportVerdictReason: String, Codable, Sendable {
    case severalFingersFromTouchInterface
    case oneFingerFromTouchInterface
    case oneFingerFromMouseInterface
    case reportsNotReadable
    case noReports
}

/// What one interface sent during a touch step.
public struct SupportInterfaceTally: Equatable, Sendable {
    public var interface: UInt64
    public var role: SupportInterface.Role
    /// Every report that arrived on it.
    public var reports = 0
    /// Reports its descriptor reads as touches (finger collections), as a pointer's, as something
    /// else, and reports its descriptor doesn't describe at all.
    public var touchReports = 0
    public var pointerReports = 0
    public var otherReports = 0
    public var unreadableReports = 0
    /// The Contact Count values its touch reports carried, above zero, ascending.
    public var reportedContactCounts: [Int] = []
    /// Where fingers touched (a finger with its tip on) or the pointer pointed, each axis 0…1 across
    /// its logical range.
    public var xRange: ClosedRange<Double>?
    public var yRange: ClosedRange<Double>?
    /// When its first and last reports arrived, on the host's clock.
    public var firstTime: TimeInterval?
    public var lastTime: TimeInterval?

    public init(interface: UInt64, role: SupportInterface.Role) {
        self.interface = interface
        self.role = role
    }

    /// Reports a second, from its first to its last; nil for fewer than two, or none apart.
    public var reportsPerSecond: Double? {
        guard reports > 1, let firstTime, let lastTime, lastTime > firstTime else { return nil }
        return Double(reports - 1) / (lastTime - firstTime)
    }
}

/// One touch step: what it asked for, how it ended, what came, and what Tactile read from it.
public struct SupportTouchStep: Equatable, Sendable {
    public var fingers: SupportFingers
    /// Nil while it is under way.
    public var ending: SupportStepEnding?
    public var startedAt: TimeInterval
    /// How long it ran, in seconds.
    public var seconds: TimeInterval = 0
    /// Each interface listened to, in the device's order.
    public var interfaces: [SupportInterfaceTally] = []
    /// How many fingers Tactile read at once, as it reads a touchscreen (`TouchscreenReader`): each
    /// number seen, ascending.
    public var fingersAtOnce: [Int] = []
    /// The most fingers read at once from the touch interface, and from the mouse interface (or a
    /// mouse-only device's pointer).
    public var mostFingersFromTouchInterface = 0
    public var mostFingersFromMouseInterface = 0
    /// Where Tactile read touches from at its end.
    public var origin: TouchOrigin = .undetermined
    /// Every report that arrived, and the first `SupportCheck.reportsKept` of them, as they came.
    public var reportsSeen = 0
    public var reports: [SupportRawReport] = []

    public init(fingers: SupportFingers, startedAt: TimeInterval) {
        self.fingers = fingers
        self.startedAt = startedAt
    }

    public var mostFingers: Int { max(mostFingersFromTouchInterface, mostFingersFromMouseInterface) }
}

/// Step 1: what the device says about itself, read only.
public struct SupportIdentity: Equatable, Sendable {
    /// What `InterfaceDecoder` makes of an interface's descriptor.
    public struct Decoded: Equatable, Sendable {
        public var kind: InterfaceKind
        public var fingerCollections: Int
        public var surfaceSizeMM: CGSize?
        public var reportsContactSize: Bool
        public var reportsConfidence: Bool
        public var maxInputReportLength: Int
        public var featureReportsToRead: [FeatureReportToRead]
    }

    public struct Interface: Equatable, Sendable {
        public var id: UInt64
        public var role: SupportInterface.Role
        /// As IOKit lists them.
        public var usages: [DescriptorSummary.Collection]
        public var descriptor: [UInt8]?
        public var maxInputReportSize: Int?
        /// Nil when it publishes no descriptor.
        public var summary: DescriptorSummary?
        /// Nil when it publishes no descriptor, or one Tactile can't read.
        public var decoded: Decoded?
    }

    public var interfaces: [Interface]

    /// The touch interface's: its finger collections (the most fingers one report can carry), and
    /// whether it has Input Mode and the certification blob, and where Contact Count Maximum is.
    public var fingerCollections: Int { touch?.decoded?.fingerCollections ?? 0 }
    public var hasInputMode: Bool { touch?.summary?.inputModeReportID != nil }
    public var hasCertificationBlob: Bool { touch?.summary?.certificationBlobReportID != nil }
    public var contactCountMaximumReportID: Int? { touch?.summary?.contactCountMaximumReportID }

    public var touch: Interface? { interfaces.first { $0.role == .touch } }

    init(_ device: SupportDevice) {
        interfaces = device.interfaces.map { interface in
            let decoder = interface.descriptor.flatMap(InterfaceDecoder.init(descriptor:))
            return Interface(
                id: interface.id, role: interface.role, usages: interface.usages, descriptor: interface.descriptor,
                maxInputReportSize: interface.maxInputReportSize,
                summary: interface.descriptor.map(DescriptorSummary.init(descriptor:)),
                decoded: decoder.map {
                    Decoded(kind: $0.kind, fingerCollections: $0.contactSlots, surfaceSizeMM: $0.surfaceSizeMM,
                            reportsContactSize: $0.reportsContactSize, reportsConfidence: $0.reportsConfidence,
                            maxInputReportLength: $0.maxInputReportLength, featureReportsToRead: $0.featureReportsToRead)
                })
        }
    }
}

/// The check of one device, step by step.
///
/// 1. **What it is**, made at once from what the system described: nothing is opened.
/// 2. **Switches**, on `start`: the device is taken as Tactile takes a touchscreen (`SupportProbe`),
///    and what each call returned is kept. A mouse-only device is only opened.
/// 3. **Touches**: one finger, then two, then five. Each step ends when its fingers have come and
///    the glass has been clear for `quietAfterLift`, when its `stepSeconds` run out, or on Skip; what
///    came by then is kept. Every report is counted and read as Tactile reads a touchscreen
///    (`TouchscreenReader`, one for the touch interface and its mouse, one for each pointer of a
///    mouse-only device); the first `reportsKept` of each step are kept as they came.
/// 4. **The verdict**, once the steps are over and the device has been let go (`verdict(of:)`).
///
/// The time is the host's clock, the one reports carry: `tick(at:)` is called by the window's
/// timer, a few times a second. The check stops if the device is unplugged or can't be taken, and
/// on `stop`.
@MainActor
public final class SupportCheck {
    public enum Stage: Equatable, Sendable {
        /// Step 1 is known; nothing is taken yet.
        case ready
        /// Step 3, with this many fingers.
        case touching(SupportFingers)
        /// The steps are over, and the device has been let go.
        case finished
    }

    /// Why a check finished before its steps were over.
    public enum Interruption: Equatable, Sendable {
        /// It wasn't connected any more when the check began.
        case notConnected
        /// It was unplugged during the check.
        case unplugged
        /// The check was stopped.
        case stopped
    }

    public static let stepSeconds: TimeInterval = 15
    public static let reportsKept = 200
    /// How long the glass stays clear after the fingers asked for before a step is done.
    public static let quietAfterLift: TimeInterval = 1

    public let device: SupportDevice
    public let identity: SupportIdentity
    public private(set) var stage: Stage = .ready
    /// Step 2: nil until the device is taken.
    public private(set) var switches: SupportSwitches?
    /// The write of Input Mode 0 when the device was let go, after a take that wrote 2.
    public private(set) var writeBack: SupportSwitches.ModeWrite?
    /// Step 3: the steps that ended, and the one under way, last.
    public private(set) var steps: [SupportTouchStep] = []
    public private(set) var interruption: Interruption?
    /// Called after each change.
    public var onChange: (@MainActor () -> Void)?

    private let probe: SupportProbe
    private var decoders: [UInt64: InterfaceDecoder] = [:]
    /// The readers, and which reader, as what, reads each interface.
    private var readers: [Int: TouchscreenReader] = [:]
    private var readerOf: [UInt64: (key: Int, as: TouchscreenReader.Interface)] = [:]
    private var fingersDown: [Int: Int] = [:]
    /// When the glass last became clear, while it is clear.
    private var clearSince: TimeInterval?

    public init(device: SupportDevice, probe: SupportProbe) {
        self.device = device
        self.probe = probe
        identity = SupportIdentity(device)
        for interface in device.interfaces {
            decoders[interface.id] = interface.descriptor.flatMap(InterfaceDecoder.init(descriptor:))
        }
    }

    /// The verdict from the steps so far.
    public var verdict: SupportVerdict { Self.verdict(of: steps).verdict }
    public var verdictReason: SupportVerdictReason { Self.verdict(of: steps).reason }

    /// Contact Count Maximum, from what its read returned in step 2.
    public var contactCountMaximum: Int? {
        guard let summary = identity.touch?.summary, let id = summary.contactCountMaximumReportID else { return nil }
        return switches?.reads.first { $0.reportID == id && $0.lengthReturned > 0 }
            .flatMap { summary.contactCountMaximum(fromFeatureReport: $0.bytes) }
    }

    // MARK: - The steps

    /// Step 2, then the first touch step from `time`.
    public func start(at time: TimeInterval) {
        guard stage == .ready else { return }
        guard let switches = probe.take(device, onReport: { [weak self] in self?.received($0) },
                                        onGone: { [weak self] in self?.gone() }) else {
            interruption = .notConnected
            stage = .finished
            onChange?()
            return
        }
        self.switches = switches
        makeReaders(opened: Set(switches.opens.filter { $0.held != .notOpened }.map(\.interface)))
        begin(.one, at: time)
    }

    /// Ends the step under way, keeping what came, and goes on to the next.
    public func skip(at time: TimeInterval) {
        guard case .touching = stage else { return }
        end(.skipped, at: time)
    }

    /// Ends the step under way when its time is up, or once it is done.
    public func tick(at time: TimeInterval) {
        guard case .touching(let fingers) = stage, let step = steps.last else { return }
        if time - step.startedAt >= Self.stepSeconds {
            end(.timeUp, at: time)
        } else if step.mostFingers >= fingers.rawValue, let clearSince, time - clearSince >= Self.quietAfterLift {
            end(.done, at: time)
        }
    }

    /// Stops the check: the step under way ends, and the device is let go.
    public func stop(at time: TimeInterval) {
        guard stage != .finished else { return }
        if case .touching = stage { close(.stopped, at: time) }
        interruption = .stopped
        finish(releasing: true)
    }

    // MARK: - Reports

    private func makeReaders(opened: Set<UInt64>) {
        let decoder = { (role: SupportInterface.Role) -> (UInt64, InterfaceDecoder?)? in
            self.device.interfaces.first { $0.role == role && opened.contains($0.id) }.map { ($0.id, self.decoders[$0.id]) }
        }
        if device.kind == .mouseOnly {
            for (index, pointer) in device.interfaces.enumerated() where pointer.role == .pointer && opened.contains(pointer.id) {
                readers[index] = TouchscreenReader(touch: nil, mouse: decoders[pointer.id])
                readerOf[pointer.id] = (index, .mouse)
            }
        } else {
            let touch = decoder(.touch), mouse = decoder(.mouse)
            readers[0] = TouchscreenReader(touch: touch?.1 ?? nil, mouse: mouse?.1 ?? nil)
            if let touch { readerOf[touch.0] = (0, .touch) }
            if let mouse { readerOf[mouse.0] = (0, .mouse) }
        }
    }

    private func received(_ report: SupportRawReport) {
        guard case .touching = stage, var step = steps.last else { return }
        step.reportsSeen += 1
        if step.reports.count < Self.reportsKept { step.reports.append(report) }
        if let index = step.interfaces.firstIndex(where: { $0.interface == report.interface }) {
            tally(report, into: &step.interfaces[index])
        }
        if let (key, role) = readerOf[report.interface], var reader = readers[key] {
            let frames = reader.add(report.bytes, from: role, at: report.time)
            readers[key] = reader
            for frame in frames {
                let count = frame.contacts.count
                if count > 0 {
                    if reader.origin == .touchInterface {
                        step.mostFingersFromTouchInterface = max(step.mostFingersFromTouchInterface, count)
                    } else {
                        step.mostFingersFromMouseInterface = max(step.mostFingersFromMouseInterface, count)
                    }
                    if !step.fingersAtOnce.contains(count) { step.fingersAtOnce = (step.fingersAtOnce + [count]).sorted() }
                }
                let wasDown = fingersDown.values.reduce(0, +) > 0
                fingersDown[key] = count
                let isDown = fingersDown.values.reduce(0, +) > 0
                if isDown {
                    clearSince = nil
                } else if wasDown {
                    clearSince = frame.time
                }
            }
        }
        steps[steps.count - 1] = step
        onChange?()
    }

    private func tally(_ report: SupportRawReport, into tally: inout SupportInterfaceTally) {
        tally.reports += 1
        tally.firstTime = tally.firstTime ?? report.time
        tally.lastTime = report.time
        func note(_ point: CGPoint) {
            let x = Double(point.x), y = Double(point.y)
            tally.xRange = tally.xRange.map { min($0.lowerBound, x)...max($0.upperBound, x) } ?? x...x
            tally.yRange = tally.yRange.map { min($0.lowerBound, y)...max($0.upperBound, y) } ?? y...y
        }
        switch decoders[report.interface]?.decode(report.bytes) {
        case .touch(let touch)?:
            tally.touchReports += 1
            if let count = touch.contactCount, count > 0, !tally.reportedContactCounts.contains(count) {
                tally.reportedContactCounts = (tally.reportedContactCounts + [count]).sorted()
            }
            for slot in touch.slots where slot.tip {
                if let position = slot.position { note(position) }
            }
        case .pointer(let pointer)?:
            tally.pointerReports += 1
            if let position = pointer.position { note(position) }
        case .other?:
            tally.otherReports += 1
        case nil:
            tally.unreadableReports += 1
        }
    }

    // MARK: - Moving on

    private func begin(_ fingers: SupportFingers, at time: TimeInterval) {
        var step = SupportTouchStep(fingers: fingers, startedAt: time)
        let listened = Set(readerOf.keys)
        step.interfaces = device.interfaces.filter { listened.contains($0.id) }
            .map { SupportInterfaceTally(interface: $0.id, role: $0.role) }
        step.origin = readers[0]?.origin ?? readers.values.first?.origin ?? .unreadable
        steps.append(step)
        stage = .touching(fingers)
        clearSince = fingersDown.values.reduce(0, +) > 0 ? nil : time
        onChange?()
    }

    /// Ends the step under way with `ending`, and begins the next, or finishes.
    private func end(_ ending: SupportStepEnding, at time: TimeInterval) {
        guard case .touching(let fingers) = stage else { return }
        close(ending, at: time)
        if let next = SupportFingers.allCases.first(where: { $0.rawValue > fingers.rawValue }) {
            begin(next, at: time)
        } else {
            finish(releasing: true)
        }
    }

    private func close(_ ending: SupportStepEnding, at time: TimeInterval) {
        guard var step = steps.last, step.ending == nil else { return }
        step.ending = ending
        step.seconds = max(0, time - step.startedAt)
        if let reader = readers[0] {
            step.origin = reader.origin
        } else if let decided = readers.values.map(\.origin).first(where: { $0 != .undetermined }) {
            step.origin = decided
        } else {
            step.origin = readers.values.first?.origin ?? .unreadable
        }
        steps[steps.count - 1] = step
    }

    private func finish(releasing: Bool) {
        if releasing, switches != nil { writeBack = probe.release() }
        stage = .finished
        onChange?()
    }

    /// The device was unplugged: the probe has let it go, writing nothing.
    private func gone() {
        guard stage != .finished else { return }
        if case .touching = stage, let step = steps.last {
            close(.stopped, at: max(step.startedAt, step.reports.last?.time ?? step.startedAt))
        }
        interruption = .unplugged
        finish(releasing: false)
    }

    // MARK: - The verdict

    /// The verdict from the touch steps:
    /// - **works fully**: some step read two or more fingers at once from the touch interface;
    /// - **works with one finger**: else, some step read a finger, from the touch interface or from a
    ///   mouse interface (a mouse-only device's pointer included);
    /// - **doesn't work**: else; reports came that gave no finger, or none came at all.
    public static func verdict(of steps: [SupportTouchStep]) -> (verdict: SupportVerdict, reason: SupportVerdictReason) {
        if steps.contains(where: { $0.mostFingersFromTouchInterface >= 2 }) { return (.worksFully, .severalFingersFromTouchInterface) }
        if steps.contains(where: { $0.mostFingersFromTouchInterface >= 1 }) { return (.worksWithOneFinger, .oneFingerFromTouchInterface) }
        if steps.contains(where: { $0.mostFingersFromMouseInterface >= 1 }) { return (.worksWithOneFinger, .oneFingerFromMouseInterface) }
        if steps.contains(where: { $0.reportsSeen > 0 }) { return (.doesNotWork, .reportsNotReadable) }
        return (.doesNotWork, .noReports)
    }
}
