// What Touchscreen Check shows on the preview desk beyond its touchscreens: two touch devices Tactile
// doesn't list, as the check's probe would find them. Nothing is opened or watched.

import TactileDevices

extension PreviewDesk {
    /// A pen digitiser, and a touchscreen that only acts as a mouse.
    static let notListedDevices: [SupportDevice] = [
        SupportDevice(
            id: "256c:006d@01200000", kind: .digitizer, vendorID: 0x256c, productID: 0x006d, product: "Pen Display",
            manufacturer: "", serial: "", locationID: 0x0120_0000,
            interfaces: [SupportInterface(id: 31, role: .digitizer, usages: [], descriptor: nil, maxInputReportSize: nil)]),
        SupportDevice(
            id: "0eef:0005@01300000", kind: .mouseOnly, vendorID: 0x0eef, productID: 0x0005, product: "USB Touch Panel",
            manufacturer: "", serial: "", locationID: 0x0130_0000,
            interfaces: [SupportInterface(id: 32, role: .pointer, usages: [], descriptor: nil, maxInputReportSize: nil)]),
    ]
}
