// Finding touchscreens and their sibling interfaces. Nothing here opens a device: it reads the
// I/O Registry only.

import Foundation
import IOKit
import IOKit.hid
import InputModeCore

func property<T>(_ device: IOHIDDevice, _ key: String) -> T? {
    IOHIDDeviceGetProperty(device, key as CFString) as? T
}

func hex(_ code: IOReturn) -> String { String(format: "0x%08x", UInt32(bitPattern: code)) }

func say(_ line: String = "") {
    print(line)
    fflush(stdout)
}

/// One HID interface of a USB device, as IOKit presents it.
final class HIDInterface {
    enum OpenState { case closed, shared, exclusive }

    let device: IOHIDDevice
    let role: InterfaceRole
    let descriptor: HIDDescriptor?
    let descriptorProblem: String?
    let registryID: UInt64
    let locationID: Int
    let interfaceNumber: Int?
    let primary: HIDUsage
    let vendorID: Int
    let productID: Int
    let product: String
    let manufacturer: String
    let serial: String
    let bufferSize: Int
    let buffer: UnsafeMutablePointer<UInt8>
    var openState: OpenState = .closed
    var scheduled = false

    init(_ device: IOHIDDevice) {
        self.device = device
        let page: Int = property(device, kIOHIDPrimaryUsagePageKey) ?? 0
        let usage: Int = property(device, kIOHIDPrimaryUsageKey) ?? 0
        primary = HIDUsage(UInt16(truncatingIfNeeded: page), UInt16(truncatingIfNeeded: usage))
        role = InterfaceRole(primaryUsagePage: page, primaryUsage: usage)
        if let data: Data = property(device, kIOHIDReportDescriptorKey) {
            do {
                descriptor = try HIDDescriptor([UInt8](data))
                descriptorProblem = nil
            } catch {
                descriptor = nil
                descriptorProblem = "\(error)"
            }
        } else {
            descriptor = nil
            descriptorProblem = "no report descriptor in the registry"
        }
        let service = IOHIDDeviceGetService(device)
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(service, &id)
        registryID = id
        let number = IORegistryEntrySearchCFProperty(service, kIOServicePlane, "bInterfaceNumber" as CFString, kCFAllocatorDefault,
                                                     IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
        interfaceNumber = number as? Int
        locationID = property(device, kIOHIDLocationIDKey) ?? 0
        vendorID = property(device, kIOHIDVendorIDKey) ?? 0
        productID = property(device, kIOHIDProductIDKey) ?? 0
        product = property(device, kIOHIDProductKey) ?? "Unnamed"
        manufacturer = property(device, kIOHIDManufacturerKey) ?? "unknown maker"
        serial = property(device, kIOHIDSerialNumberKey) ?? "no serial"
        let size: Int = property(device, kIOHIDMaxInputReportSizeKey) ?? 64
        bufferSize = max(size, 1)
        buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        buffer.initialize(repeating: 0, count: bufferSize)
    }

    deinit { buffer.deallocate() }

    var name: String {
        "interface \(interfaceNumber.map(String.init) ?? "?") (\(role.rawValue), \(primary))"
    }

    var usbID: String { String(format: "%04x:%04x", vendorID, productID) }

    var identity: USBIdentity {
        USBIdentity(vendorID: vendorID, productID: productID, locationID: locationID, serial: serial)
    }

    /// The feature report holding Input Mode, when this is a touchscreen interface that has one.
    var inputModeReport: UInt8? {
        guard role == .touchscreen, let descriptor else { return nil }
        return FeatureWritePlanner.inputModeReport(in: descriptor)
    }
}

/// Every HID interface the registry matches, without opening anything.
func hidDevices(matching: [String: Any]) -> [IOHIDDevice] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
    guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
    return Array(set)
}

/// A touchscreen with an Input Mode setting, and the other interfaces of the same USB device.
final class Strip {
    let touch: HIDInterface
    var siblings: [HIDInterface]

    init(touch: HIDInterface, siblings: [HIDInterface]) {
        self.touch = touch
        self.siblings = siblings
    }

    var all: [HIDInterface] { [touch] + siblings }
    var mouse: HIDInterface? { siblings.first { $0.role == .mouse } }

    var label: String {
        String(format: "%@ by %@ (%@, serial %@, USB location 0x%08x)", touch.product, touch.manufacturer, touch.usbID,
               touch.serial, touch.locationID)
    }

    /// The other interfaces of the same USB device, found again from the registry: the same
    /// non-zero location and the same USB ID. A touchscreen at location 0 gets no siblings, so an
    /// unrelated mouse is never taken for one.
    func findSiblings() {
        guard touch.locationID != 0 else { siblings = []; return }
        siblings = hidDevices(matching: [kIOHIDLocationIDKey: touch.locationID])
            .map(HIDInterface.init)
            .filter { $0.registryID != touch.registryID && $0.identity.isSibling(of: touch.identity) }
            .sorted { ($0.interfaceNumber ?? 99) < ($1.interfaceNumber ?? 99) }
    }
}

/// Touchscreen interfaces that declare an Input Mode feature, each with its siblings.
func findStrips(_ filter: DeviceFilter?) -> [Strip] {
    hidDevices(matching: [kIOHIDDeviceUsagePageKey: 0x0D, kIOHIDDeviceUsageKey: 0x04])
        .map(HIDInterface.init)
        .filter { $0.inputModeReport != nil && (filter?.matches($0.identity) ?? true) }
        .sorted { $0.locationID < $1.locationID }
        .map { touch in
            let strip = Strip(touch: touch, siblings: [])
            strip.findSiblings()
            return strip
        }
}

/// Whether this process may read input devices (Input Monitoring), checked without asking.
func inputMonitoringStatus() -> String {
    switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
    case kIOHIDAccessTypeGranted: return "granted"
    case kIOHIDAccessTypeDenied: return "denied"
    default: return "not determined"
    }
}

/// Running Tactile or Touch Up processes, which would fight this tool for the panel.
func conflictingProcesses() -> [String] {
    let count = proc_listallpids(nil, 0)
    guard count > 0 else { return [] }
    var pids = [pid_t](repeating: 0, count: Int(count) + 64)
    let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
    var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    var found: [String] = []
    for pid in pids.prefix(Int(max(filled, 0))) where pid > 0 {
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { continue }
        let text = String(cString: path)
        if text.contains("Tactile.app/Contents/MacOS") || text.contains("Touch Up") { found.append("\(pid) \(text)") }
    }
    return found
}
