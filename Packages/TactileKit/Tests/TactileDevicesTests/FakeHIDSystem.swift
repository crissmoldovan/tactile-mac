import Foundation
import IOKit
import TactileReading
@testable import TactileDevices

/// A HID system with no devices behind it: it records what it is asked, and the test decides what
/// is connected and what each call returns.
@MainActor
final class FakeHIDSystem: HIDSystem {
    enum Call: Equatable, CustomStringConvertible {
        case startMatching, stopMatching
        case open(HIDInterfaceID, exclusive: Bool)
        case close(HIDInterfaceID, exclusive: Bool)
        case hasInputMode(HIDInterfaceID)
        case readFeatureReport(HIDInterfaceID, reportID: Int, length: Int)
        case writeInputMode(HIDInterfaceID, Int)
        case startReports(HIDInterfaceID, bufferSize: Int)
        case stopReports(HIDInterfaceID)

        var description: String {
            switch self {
            case .startMatching: return "startMatching"
            case .stopMatching: return "stopMatching"
            case .open(let id, let exclusive): return "open(\(id), \(exclusive ? "exclusive" : "shared"))"
            case .close(let id, let exclusive): return "close(\(id), \(exclusive ? "exclusive" : "shared"))"
            case .hasInputMode(let id): return "hasInputMode(\(id))"
            case .readFeatureReport(let id, let reportID, let length):
                return "readFeatureReport(\(id), \(String(format: "0x%02X", reportID)), \(length) bytes)"
            case .writeInputMode(let id, let value): return "writeInputMode(\(id), \(value))"
            case .startReports(let id, let size): return "startReports(\(id), \(size))"
            case .stopReports(let id): return "stopReports(\(id))"
            }
        }

        /// Whether the call opens, writes to, or listens to a device.
        var touchesTheDevice: Bool {
            switch self {
            case .startMatching, .stopMatching, .stopReports, .close: return false
            case .open, .hasInputMode, .readFeatureReport, .writeInputMode, .startReports: return true
            }
        }
    }

    static let refused = IOReturn(bitPattern: 0xE000_02C5)  // kIOReturnExclusiveAccess
    static let notPermitted = IOReturn(bitPattern: 0xE000_02E2)  // kIOReturnNotPermitted

    private(set) var calls: [Call] = []
    /// Interfaces connected now.
    private(set) var connected: [HIDInterfaceDescription] = []
    /// What `open` returns, per interface: exclusive, then shared. Success by default.
    var openResults: [HIDInterfaceID: (exclusive: IOReturn, shared: IOReturn)] = [:]
    /// Interfaces with the Input Mode feature.
    var inputModeInterfaces: Set<HIDInterfaceID> = []
    /// What a write of Input Mode returns. Success by default.
    var writeResult: IOReturn = kIOReturnSuccess
    /// What a feature report read returns. Success by default.
    var readResult: IOReturn = kIOReturnSuccess
    /// How long each feature report read takes, in seconds. None by default.
    var readSeconds: TimeInterval = 0
    /// How many bytes a successful read gives back; `nil` for as many as asked. A failed read gives none.
    var readReturnedLength: Int?
    /// What a successful read of each feature report gives back, by report ID, cut to the length
    /// returned: the report ID byte and then zeros when not given.
    var featureReportBytes: [Int: [UInt8]] = [:]
    /// What each read is answered with instead of `readResult`, by report ID.
    var readResults: [Int: IOReturn] = [:]
    /// Keeps delivering reports after `stopReports`, as a report already on its way would be.
    var keepsDeliveringAfterStop = false

    private var matched: (@MainActor (HIDInterfaceDescription) -> Void)?
    private var removed: (@MainActor (HIDInterfaceID) -> Void)?
    private var handlers: [HIDInterfaceID: @MainActor ([UInt8], TimeInterval) -> Void] = [:]
    private var deferred: [@MainActor () -> Void] = []

    init(connected: [HIDInterfaceDescription] = []) {
        self.connected = connected
    }

    // MARK: The test's side

    /// An interface connects.
    func connect(_ description: HIDInterfaceDescription) {
        connected.append(description)
        matched?(description)
    }

    /// An interface goes.
    func disconnect(_ id: HIDInterfaceID) {
        connected.removeAll { $0.id == id }
        handlers[id] = nil
        removed?(id)
    }

    /// Runs what was put off with `later`, as the run loop would after the current events.
    func runLater() {
        while !deferred.isEmpty {
            let work = deferred
            deferred = []
            for item in work { item() }
        }
    }

    /// A report arrives on an interface. Returns whether anyone was listening.
    @discardableResult
    func send(_ bytes: [UInt8], on id: HIDInterfaceID, at time: TimeInterval) -> Bool {
        guard let handler = handlers[id] else { return false }
        handler(bytes, time)
        return true
    }

    func isListening(to id: HIDInterfaceID) -> Bool { handlers[id] != nil }

    func clearCalls() { calls = [] }

    /// The feature report reads among the calls, in order.
    var featureReads: [Call] {
        calls.filter { if case .readFeatureReport = $0 { return true } else { return false } }
    }

    // MARK: HIDSystem

    func startMatching(matched: @escaping @MainActor (HIDInterfaceDescription) -> Void,
                       removed: @escaping @MainActor (HIDInterfaceID) -> Void) {
        calls.append(.startMatching)
        self.matched = matched
        self.removed = removed
        for description in connected { matched(description) }
    }

    func stopMatching() {
        calls.append(.stopMatching)
        matched = nil
        removed = nil
        handlers = [:]
    }

    func later(_ work: @escaping @MainActor () -> Void) {
        deferred.append(work)
    }

    func open(_ id: HIDInterfaceID, exclusive: Bool) -> IOReturn {
        calls.append(.open(id, exclusive: exclusive))
        guard connected.contains(where: { $0.id == id }) else { return IOResult.noDevice }
        let results = openResults[id] ?? (kIOReturnSuccess, kIOReturnSuccess)
        return exclusive ? results.exclusive : results.shared
    }

    func close(_ id: HIDInterfaceID, exclusive: Bool) -> IOReturn {
        calls.append(.close(id, exclusive: exclusive))
        return kIOReturnSuccess
    }

    func hasInputMode(_ id: HIDInterfaceID) -> Bool {
        calls.append(.hasInputMode(id))
        return inputModeInterfaces.contains(id)
    }

    func readFeatureReport(_ id: HIDInterfaceID, reportID: Int, length: Int) -> FeatureReportRead {
        calls.append(.readFeatureReport(id, reportID: reportID, length: length))
        guard connected.contains(where: { $0.id == id }) else { return FeatureReportRead(result: IOResult.noDevice, length: 0, seconds: 0) }
        let result = readResults[reportID] ?? readResult
        let returned = result == kIOReturnSuccess ? readReturnedLength ?? length : 0
        let given = featureReportBytes[reportID] ?? [UInt8(truncatingIfNeeded: reportID)] + [UInt8](repeating: 0, count: max(length - 1, 0))
        return FeatureReportRead(result: result, length: returned, seconds: readSeconds, bytes: Array(given.prefix(returned)))
    }

    /// Background reads wait for `resumeReads()`, as a panel slow to answer would hold them.
    var suspendsReads = false
    private var pendingReads: [CheckedContinuation<Void, Never>] = []
    var readsWaiting: Int { pendingReads.count }

    func resumeReads() {
        let waiting = pendingReads
        pendingReads = []
        for read in waiting { read.resume() }
    }

    func readFeatureReportInBackground(_ id: HIDInterfaceID, reportID: Int, length: Int) async -> FeatureReportRead {
        if suspendsReads { await withCheckedContinuation { pendingReads.append($0) } }
        return readFeatureReport(id, reportID: reportID, length: length)
    }

    func writeInputMode(_ id: HIDInterfaceID, _ value: Int) -> IOReturn {
        calls.append(.writeInputMode(id, value))
        return writeResult
    }

    func startReports(_ id: HIDInterfaceID, bufferSize: Int, _ handler: @escaping @MainActor ([UInt8], TimeInterval) -> Void) {
        calls.append(.startReports(id, bufferSize: bufferSize))
        handlers[id] = handler
    }

    func stopReports(_ id: HIDInterfaceID) {
        calls.append(.stopReports(id))
        if !keepsDeliveringAfterStop { handlers[id] = nil }
    }
}

/// Everything the source tells its delegate, in order.
@MainActor
final class RecordingDelegate: TouchscreenSourceDelegate {
    enum Event: Equatable {
        case connected(ConnectedTouchscreen)
        case changed(ConnectedTouchscreen)
        case disconnected(DeviceHandle)
        case frame(DeviceHandle, ContactFrame)
    }

    private(set) var events: [Event] = []
    /// Called after each change is recorded, so a test can act as the app would.
    var onChanged: ((ConnectedTouchscreen) -> Void)?
    var onFrame: ((DeviceHandle, ContactFrame) -> Void)?
    var onConnected: ((ConnectedTouchscreen) -> Void)?

    func touchscreenConnected(_ touchscreen: ConnectedTouchscreen) {
        events.append(.connected(touchscreen))
        onConnected?(touchscreen)
    }

    func touchscreenChanged(_ touchscreen: ConnectedTouchscreen) {
        events.append(.changed(touchscreen))
        onChanged?(touchscreen)
    }

    func touchscreenDisconnected(_ handle: DeviceHandle) {
        events.append(.disconnected(handle))
    }

    func touchscreen(_ handle: DeviceHandle, produced frame: ContactFrame) {
        events.append(.frame(handle, frame))
        onFrame?(handle, frame)
    }

    func clear() { events = [] }

    var connected: [ConnectedTouchscreen] {
        events.compactMap { if case .connected(let t) = $0 { return t } else { return nil } }
    }

    var changes: [ConnectedTouchscreen] {
        events.compactMap { if case .changed(let t) = $0 { return t } else { return nil } }
    }

    var frames: [ContactFrame] {
        events.compactMap { if case .frame(_, let f) = $0 { return f } else { return nil } }
    }

    var disconnections: [DeviceHandle] {
        events.compactMap { if case .disconnected(let h) = $0 { return h } else { return nil } }
    }
}
