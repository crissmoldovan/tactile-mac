// What the touchscreen source asks of the HID system. `IOKitHIDSystem` answers with IOKit; the
// tests answer with a fake, so every rule of the source is tested without a device.

import Foundation
import IOKit

/// The HID system, as the touchscreen source uses it. Everything runs on the main thread.
@MainActor
protocol HIDSystem: AnyObject {
    /// Starts watching for the interfaces it was made to watch (`HIDMatching`): for the touchscreen
    /// source, touchscreen interfaces (a Touch Screen collection, 0x0D/0x04) and mouse interfaces (a
    /// Mouse collection, 0x01/0x02). Calls `matched` before returning for each one connected now,
    /// then once for each that connects later, and `removed` once for each that goes. Opens nothing.
    func startMatching(matched: @escaping @MainActor (HIDInterfaceDescription) -> Void,
                       removed: @escaping @MainActor (HIDInterfaceID) -> Void)
    /// Stops watching, and forgets every interface.
    func stopMatching()
    /// Runs `work` on the main thread once the events being delivered now have been handled.
    func later(_ work: @escaping @MainActor () -> Void)

    /// Opens an interface, exclusively (seized from macOS) or shared.
    func open(_ id: HIDInterfaceID, exclusive: Bool) -> IOReturn
    /// Closes an interface opened with `open`, with the same `exclusive`.
    @discardableResult
    func close(_ id: HIDInterfaceID, exclusive: Bool) -> IOReturn
    /// Whether the interface has the Input Mode feature (0x0D/0x52). Asked while it is open.
    func hasInputMode(_ id: HIDInterfaceID) -> Bool
    /// Reads one whole feature report (GET_REPORT), asking for exactly `length` bytes (the report
    /// ID byte included when the interface uses IDs), and gives back what came back. The touchscreen
    /// source drops it: for the panels that need it, the read itself is what matters. The support
    /// check records it. Asked while the interface is open.
    func readFeatureReport(_ id: HIDInterfaceID, reportID: Int, length: Int) -> FeatureReportRead
    /// The same read as `readFeatureReport`, made off the main thread, so a panel slow to answer
    /// doesn't hold up the interface. The touchscreen check reads this way; the source doesn't.
    func readFeatureReportInBackground(_ id: HIDInterfaceID, reportID: Int, length: Int) async -> FeatureReportRead
    /// Writes the Input Mode feature: 0 mouse emulation, 2 multi-touch. Never reads it.
    func writeInputMode(_ id: HIDInterfaceID, _ value: Int) -> IOReturn
    /// Delivers each raw input report of an open interface, with its time on the host's clock in
    /// seconds, until `stopReports`. `bufferSize` is the most bytes one report can have.
    func startReports(_ id: HIDInterfaceID, bufferSize: Int,
                      _ handler: @escaping @MainActor (_ bytes: [UInt8], _ time: TimeInterval) -> Void)
    func stopReports(_ id: HIDInterfaceID)
}

extension HIDSystem {
    /// By default, the read on the main thread, as `readFeatureReport` makes it: the tests' system.
    func readFeatureReportInBackground(_ id: HIDInterfaceID, reportID: Int, length: Int) async -> FeatureReportRead {
        readFeatureReport(id, reportID: reportID, length: length)
    }
}

/// What one feature report read gave.
struct FeatureReportRead: Equatable, Sendable {
    var result: IOReturn
    /// How many bytes came back: none when the read failed.
    var length: Int
    /// How long the read took, in seconds.
    var seconds: TimeInterval
    /// The bytes that came back, the report ID byte first when the interface uses IDs: `length` of
    /// them, none when the read failed.
    var bytes: [UInt8] = []
}

/// IOKit result codes the device layer names. Swift can't import IOKit's macros for these.
enum IOResult {
    static let noDevice = IOReturn(bitPattern: 0xE000_02C0)
    static let badArgument = IOReturn(bitPattern: 0xE000_02C2)
    static let timeout = IOReturn(bitPattern: 0xE000_02D6)
    static let notFound = IOReturn(bitPattern: 0xE000_02F0)

    /// "0x00000000", as IOKit's headers write codes.
    static func text(_ code: IOReturn) -> String { String(format: "0x%08x", UInt32(bitPattern: code)) }
}
