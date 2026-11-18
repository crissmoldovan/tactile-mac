// Finding touchscreens: every USB device that has a Touch Screen (0x0D/0x04) top-level collection
// on any of its HID interfaces, together with all of that device's sibling interfaces (matched by
// USB location ID). Also reads the facts `list` reports about each of them.

import Foundation
import IOKit
import IOKit.hid

func hex(_ code: IOReturn) -> String { String(format: "0x%08x", UInt32(bitPattern: code)) }
func hexByte(_ v: Int) -> String { String(format: "0x%02X", v) }
func hexLocation(_ v: Int) -> String { String(format: "0x%08x", UInt32(truncatingIfNeeded: v)) }
func usbID(_ vendor: Int, _ product: Int) -> String { String(format: "%04x:%04x", vendor, product) }

func hidProperty<T>(_ device: IOHIDDevice, _ key: String) -> T? {
    IOHIDDeviceGetProperty(device, key as CFString) as? T
}

let modeNames = [0: "mouse emulation", 1: "single touch", 2: "multi-touch"]
func describeMode(_ mode: Int) -> String { modeNames[mode] ?? "unknown mode \(mode)" }

enum OpenState: String { case closed, shared, exclusive }

/// One HID interface of a touchscreen's USB device.
final class ProbeInterface {
    let device: IOHIDDevice
    let primaryUsage: Usage
    let usagePairs: [Usage]
    let descriptorBytes: [UInt8]?
    let descriptor: ParsedDescriptor?
    let layouts: [Int: ReportLayout]
    let maxInputReportSize: Int?
    let maxOutputReportSize: Int?
    let maxFeatureReportSize: Int?
    let bufferSize: Int
    let buffer: UnsafeMutablePointer<UInt8>
    var key = ""
    var role = "other"
    var openState = OpenState.closed
    var scheduled = false
    weak var owner: ProbeTouchscreen?

    init(_ device: IOHIDDevice) {
        self.device = device
        let page: Int = hidProperty(device, kIOHIDPrimaryUsagePageKey) ?? 0
        let usage: Int = hidProperty(device, kIOHIDPrimaryUsageKey) ?? 0
        primaryUsage = Usage(page: UInt32(page), id: UInt32(usage))
        let pairs: [[String: Any]] = hidProperty(device, kIOHIDDeviceUsagePairsKey) ?? []
        let list = pairs.compactMap { pair -> Usage? in
            guard let p = pair[kIOHIDDeviceUsagePageKey] as? Int, let u = pair[kIOHIDDeviceUsageKey] as? Int else { return nil }
            return Usage(page: UInt32(p), id: UInt32(u))
        }
        usagePairs = list.isEmpty ? [primaryUsage] : list
        let data: Data? = hidProperty(device, kIOHIDReportDescriptorKey)
        descriptorBytes = data.map { [UInt8]($0) }
        descriptor = descriptorBytes.map { DescriptorParser.parse($0) }
        var layouts: [Int: ReportLayout] = [:]
        if let d = descriptor {
            for id in d.reportIDs(.input) { layouts[id] = ReportLayout.build(d, reportID: id) }
        }
        self.layouts = layouts
        maxInputReportSize = hidProperty(device, kIOHIDMaxInputReportSizeKey)
        maxOutputReportSize = hidProperty(device, kIOHIDMaxOutputReportSizeKey)
        maxFeatureReportSize = hidProperty(device, kIOHIDMaxFeatureReportSizeKey)
        let largestParsed = layouts.values.map(\.byteLength).max() ?? 0
        bufferSize = max(maxInputReportSize ?? 0, largestParsed, 64) + 16
        buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        buffer.initialize(repeating: 0, count: bufferSize)
    }

    var fingerSlotCount: Int { layouts.values.map(\.slots.count).max() ?? 0 }
    var isTouchscreen: Bool { usagePairs.contains(Usages.touchScreen) }
    var isMouse: Bool { usagePairs.contains(Usages.mouse) }

    /// The input report this interface sends fingers in, if any.
    var touchLayout: ReportLayout? {
        layouts.values.filter { $0.kind == .touch }.max { $0.slots.count < $1.slots.count }
    }

    func featureElement(_ usage: Usage) -> IOHIDElement? {
        let matching: [String: Any] = [
            kIOHIDElementUsagePageKey: Int(usage.page),
            kIOHIDElementUsageKey: Int(usage.id),
            kIOHIDElementTypeKey: kIOHIDElementTypeFeature.rawValue,
        ]
        let elements = IOHIDDeviceCopyMatchingElements(device, matching as CFDictionary, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement]
        return elements?.first
    }
}

/// One touchscreen: a USB device with a Touch Screen interface, and all its HID interfaces.
final class ProbeTouchscreen {
    let number: Int
    let locationID: Int
    let interfaces: [ProbeInterface]
    let touch: ProbeInterface?
    let mouse: ProbeInterface?
    let product: String?
    let manufacturer: String?
    let vendorID: Int
    let productID: Int
    let serialNumber: String?
    let versionNumber: Int?
    let transport: String?

    init(number: Int, locationID: Int, devices: [IOHIDDevice]) {
        self.number = number
        self.locationID = locationID
        let all = devices.map(ProbeInterface.init)
        let touch = all.filter(\.isTouchscreen).max { $0.fingerSlotCount < $1.fingerSlotCount }
        let mouse = all.first { $0 !== touch && $0.isMouse }
        // Touchscreen first, then the mouse, then the rest in a stable order.
        let rest = all.filter { $0 !== touch && $0 !== mouse }.sorted { $0.primaryUsage < $1.primaryUsage }
        interfaces = [touch, mouse].compactMap { $0 } + rest
        self.touch = touch
        self.mouse = mouse
        var used: [String: Int] = [:]
        for iface in interfaces {
            let base: String
            if iface === touch { base = "touchscreen"; iface.role = "touchscreen" }
            else if iface === mouse { base = "mouse"; iface.role = "mouse" }
            else if iface.isTouchscreen { base = "touchscreen"; iface.role = "touchscreen" }
            else if iface.isMouse { base = "mouse"; iface.role = "mouse" }
            else if iface.primaryUsage.page >= 0xFF00 { base = String(format: "vendor-%04x", iface.primaryUsage.page) }
            else { base = String(format: "hid-%04x-%04x", iface.primaryUsage.page, iface.primaryUsage.id) }
            let n = (used[base] ?? 0) + 1
            used[base] = n
            iface.key = n == 1 ? base : "\(base)-\(n)"
        }
        let first = touch?.device ?? devices[0]
        product = hidProperty(first, kIOHIDProductKey)
        manufacturer = hidProperty(first, kIOHIDManufacturerKey)
        vendorID = hidProperty(first, kIOHIDVendorIDKey) ?? 0
        productID = hidProperty(first, kIOHIDProductIDKey) ?? 0
        serialNumber = hidProperty(first, kIOHIDSerialNumberKey)
        versionNumber = hidProperty(first, kIOHIDVersionNumberKey)
        transport = hidProperty(first, kIOHIDTransportKey)
        for iface in interfaces { iface.owner = self }
    }

    var name: String { "\(product ?? "Unnamed touchscreen") by \(manufacturer ?? "an unknown maker")" }
    var label: String { "Touchscreen \(number) (\(name), USB \(usbID(vendorID, productID)))" }
    var inputModeElement: IOHIDElement? { touch?.featureElement(Usages.inputMode) }
}

private var discoveryManager: IOHIDManager?

func discoverTouchscreens() -> [ProbeTouchscreen] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, nil)
    discoveryManager = manager
    let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
    var groups: [Int: [IOHIDDevice]] = [:]
    for device in devices {
        var location: Int = hidProperty(device, kIOHIDLocationIDKey) ?? 0
        if location == 0 {
            // No USB location: keep the interface on its own rather than lumping unrelated devices.
            var entryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &entryID)
            location = -Int(truncatingIfNeeded: entryID & 0x7FFF_FFFF_FFFF)
        }
        groups[location, default: []].append(device)
    }
    let touchLocations = groups.filter { _, devices in
        devices.contains { ProbeInterface.quickUsagePairs($0).contains(Usages.touchScreen) }
    }.keys.sorted()
    return touchLocations.enumerated().map { index, location in
        ProbeTouchscreen(number: index + 1, locationID: location, devices: groups[location] ?? [])
    }
}

extension ProbeInterface {
    static func quickUsagePairs(_ device: IOHIDDevice) -> [Usage] {
        let pairs: [[String: Any]] = hidProperty(device, kIOHIDDeviceUsagePairsKey) ?? []
        var list = pairs.compactMap { pair -> Usage? in
            guard let p = pair[kIOHIDDeviceUsagePageKey] as? Int, let u = pair[kIOHIDDeviceUsageKey] as? Int else { return nil }
            return Usage(page: UInt32(p), id: UInt32(u))
        }
        if list.isEmpty, let p: Int = hidProperty(device, kIOHIDPrimaryUsagePageKey), let u: Int = hidProperty(device, kIOHIDPrimaryUsageKey) {
            list = [Usage(page: UInt32(p), id: UInt32(u))]
        }
        return list
    }
}

// MARK: - Feature reports

/// Asks the panel for the current value (a GET_REPORT), rather than trusting a cached one.
func readFeature(_ device: IOHIDDevice, _ element: IOHIDElement) -> (value: Int?, result: IOReturn) {
    let placeholder = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, 0, 0)
    var value = Unmanaged.passUnretained(placeholder)
    let result = IOHIDDeviceGetValueWithOptions(device, element, &value, IOHIDDeviceGetValueOptions.withUpdate.rawValue)
    guard result == kIOReturnSuccess else { return (nil, result) }
    return (IOHIDValueGetIntegerValue(value.takeUnretainedValue()), result)
}

/// Writes one feature value. The HID stack builds the whole feature report, keeping the other
/// fields in it (such as Device Index) at their current values.
func writeFeature(_ device: IOHIDDevice, _ element: IOHIDElement, _ newValue: Int) -> IOReturn {
    let value = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, mach_absolute_time(), newValue)
    return IOHIDDeviceSetValue(device, element, value)
}

func hexString(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

/// Reads a whole feature report (GET_REPORT). The returned bytes start with the report ID when
/// the interface uses report IDs.
func readFeatureReport(_ iface: ProbeInterface, id: Int) -> (bytes: [UInt8]?, result: IOReturn) {
    // Ask for exactly the declared size: some firmware answers with as many bytes as it is asked
    // for, padding the report with unrelated memory.
    let declared = iface.descriptor?.reportBytes(.feature, id) ?? 0
    let size = declared > 0 ? declared : max(iface.maxFeatureReportSize ?? 0, 1)
    var buffer = [UInt8](repeating: 0, count: size)
    var length = CFIndex(size)
    let result = IOHIDDeviceGetReport(iface.device, kIOHIDReportTypeFeature, CFIndex(id), &buffer, &length)
    guard result == kIOReturnSuccess else { return (nil, result) }
    return (Array(buffer.prefix(max(0, min(length, size)))), result)
}

/// Whether a raw feature report looks like a real answer: it must start with its report ID when
/// the interface uses IDs. nil when there is nothing to check against.
func featureReportLooksValid(_ iface: ProbeInterface, id: Int, bytes: [UInt8]?) -> Bool? {
    guard let bytes, iface.descriptor?.usesReportIDs == true, id != 0 else { return nil }
    return bytes.first == UInt8(truncatingIfNeeded: id)
}

/// The raw feature reports of an interface that hold Contact Count Maximum, Input Mode or
/// Device Index, read with GET_REPORT. Only the touchscreen interface has any of these.
func rawFeatureReports(_ iface: ProbeInterface) -> [FeatureReportRaw] {
    guard let d = iface.descriptor else { return [] }
    let interesting: Set<Usage> = [Usages.contactCountMaximum, Usages.inputMode, Usages.deviceIndex]
    var out: [FeatureReportRaw] = []
    for id in d.reportIDs(.feature) {
        let fields = d.fields.filter { $0.type == .feature && $0.reportID == id && !$0.constant }
        guard fields.contains(where: { interesting.contains($0.usage) }) else { continue }
        var names: [String] = []
        for f in fields {
            let name = usageName(f.usage) ?? f.usage.text
            if !names.contains(name) { names.append(name) }
        }
        let read = withOpenInterface(iface) { readFeatureReport(iface, id: id) }
        out.append(FeatureReportRaw(id: id, idHex: hexByte(id), contains: names, ioReturn: hex(read.result),
                                    length: read.bytes?.count, bytes: read.bytes.map(hexString),
                                    startsWithReportID: featureReportLooksValid(iface, id: id, bytes: read.bytes)))
    }
    return out
}

/// Runs `body` with the interface open. Opens it in shared mode (and closes it again) only if it
/// was closed; shared mode reads but never takes the device away from macOS.
func withOpenInterface<T>(_ iface: ProbeInterface, _ body: () -> T) -> T {
    if iface.openState != .closed { return body() }
    let opened = IOHIDDeviceOpen(iface.device, IOOptionBits(kIOHIDOptionsTypeNone))
    defer { if opened == kIOReturnSuccess { IOHIDDeviceClose(iface.device, IOOptionBits(kIOHIDOptionsTypeNone)) } }
    return body()
}

// MARK: - USB chain

private func registryProperty(_ entry: io_registry_entry_t, _ key: String) -> Any? {
    IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
}

private func registryName(_ entry: io_registry_entry_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 128)
    guard IORegistryEntryGetName(entry, &buffer) == KERN_SUCCESS else { return nil }
    return String(cString: buffer)
}

private func registryClass(_ entry: io_registry_entry_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 128)
    guard IOObjectGetClass(entry, &buffer) == KERN_SUCCESS else { return nil }
    return String(cString: buffer)
}

private func registryLocation(_ entry: io_registry_entry_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 128)
    guard IORegistryEntryGetLocationInPlane(entry, kIOServicePlane, &buffer) == KERN_SUCCESS else { return nil }
    return String(cString: buffer)
}

private func speedName(_ code: Int?) -> String? {
    guard let code else { return nil }
    switch code {
    case 0: return "low speed (1.5 Mb/s)"
    case 1: return "full speed (12 Mb/s)"
    case 2: return "high speed (480 Mb/s)"
    case 3: return "SuperSpeed (5 Gb/s)"
    case 4: return "SuperSpeed+ (10 Gb/s)"
    case 5: return "SuperSpeed+ 2x2 (20 Gb/s)"
    default: return "speed code \(code)"
    }
}

private func usbNode(_ entry: io_registry_entry_t) -> USBNode {
    let vendor = registryProperty(entry, "idVendor") as? Int
    let product = registryProperty(entry, "idProduct") as? Int
    let location = registryProperty(entry, "locationID") as? Int
    return USBNode(
        registryName: registryName(entry),
        className: registryClass(entry),
        productName: registryProperty(entry, "USB Product Name") as? String ?? registryProperty(entry, "kUSBProductString") as? String,
        vendorName: registryProperty(entry, "USB Vendor Name") as? String ?? registryProperty(entry, "kUSBVendorString") as? String,
        usbID: vendor.flatMap { v in product.map { usbID(v, $0) } },
        locationID: location.map(hexLocation),
        serialNumber: registryProperty(entry, "USB Serial Number") as? String ?? registryProperty(entry, "kUSBSerialNumberString") as? String,
        deviceClass: registryProperty(entry, "bDeviceClass") as? Int,
        speed: speedName(registryProperty(entry, "Device Speed") as? Int))
}

/// The USB device itself, then each hub it sits behind (nearest first), then the controller.
func usbChain(_ device: IOHIDDevice) -> (device: USBNode?, hubs: [USBNode], controller: String?) {
    let service = IOHIDDeviceGetService(device)
    guard service != MACH_PORT_NULL else { return (nil, [], nil) }
    var nodes: [USBNode] = []
    var controller: String?
    var entry: io_registry_entry_t = service
    IOObjectRetain(entry)
    for _ in 0..<64 {
        var parent: io_registry_entry_t = 0
        let kr = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
        IOObjectRelease(entry)
        guard kr == KERN_SUCCESS else { entry = 0; break }
        entry = parent
        if IOObjectConformsTo(entry, "IOUSBHostDevice") != 0 || IOObjectConformsTo(entry, "IOUSBDevice") != 0 {
            nodes.append(usbNode(entry))
        } else if IOObjectConformsTo(entry, "IOUSBHostController") != 0 || IOObjectConformsTo(entry, "AppleUSBHostController") != 0
                    || (registryClass(entry) ?? "").hasSuffix("XHCI") || (registryClass(entry) ?? "").hasSuffix("EHCI") {
            let name = registryName(entry) ?? registryClass(entry) ?? "USB controller"
            controller = registryLocation(entry).map { "\(name)@\($0)" } ?? name
            break
        }
    }
    if entry != 0 { IOObjectRelease(entry) }
    return (nodes.first, Array(nodes.dropFirst()), controller)
}

// MARK: - Building the `list` facts

private func unitInfo(_ unit: UInt32) -> (name: String, mmPerUnit: Double?) {
    if unit == 0 { return ("none", nil) }
    let system = unit & 0xF
    let length = (unit >> 4) & 0xF
    let others = unit >> 8
    if length == 1, others == 0 {
        if system == 1 { return ("cm", 10) }
        if system == 3 { return ("inch", 25.4) }
    }
    return (String(format: "unit 0x%X", unit), nil)
}

func axisInfo(_ f: HIDField?) -> AxisInfo? {
    guard let f else { return nil }
    let (name, mmPerUnit) = unitInfo(f.unit)
    var size: Double?
    if let mmPerUnit, f.physicalMax != f.physicalMin {
        size = (Double(f.physicalMax - f.physicalMin) * pow(10, Double(f.unitExponent)) * mmPerUnit * 10).rounded() / 10
    }
    return AxisInfo(bits: f.bitSize, logicalMin: f.logicalMin, logicalMax: f.logicalMax,
                    physicalMin: f.physicalMin, physicalMax: f.physicalMax,
                    unit: String(format: "0x%X", f.unit), unitName: name, exponent: f.unitExponent, sizeMM: size)
}

private func presence(_ slots: [FingerSlotLayout], _ path: KeyPath<FingerSlotLayout, HIDField?>) -> FieldPresence {
    let found = slots.compactMap { $0[keyPath: path] }
    guard let f = found.first else { return FieldPresence(present: false, slots: 0, bits: nil, logicalMin: nil, logicalMax: nil) }
    return FieldPresence(present: true, slots: found.count, bits: f.bitSize, logicalMin: f.logicalMin, logicalMax: f.logicalMax)
}

private func presence(_ f: HIDField?) -> FieldPresence {
    guard let f else { return FieldPresence(present: false, slots: nil, bits: nil, logicalMin: nil, logicalMax: nil) }
    return FieldPresence(present: true, slots: nil, bits: f.bitSize, logicalMin: f.logicalMin, logicalMax: f.logicalMax)
}

/// Compares the descriptor parser with IOKit's own element list for the input fields, so a
/// reader of the survey knows the decoded fingers rest on a layout Apple's parser agrees with.
/// IOKit folds a vendor-defined field repeated N times into one long element, so vendor-defined
/// usages are compared by their total size only.
func parserCheck(_ iface: ProbeInterface) -> String {
    guard let d = iface.descriptor else { return "no report descriptor published" }
    struct Key: Hashable { let reportID: Int; let page: UInt32; let usage: UInt32; let bits: Int; let min: Int64; let max: Int64 }
    struct VendorKey: Hashable { let reportID: Int; let page: UInt32; let usage: UInt32 }
    var mine: [Key: Int] = [:]
    var mineVendor: [VendorKey: Int] = [:]
    for f in d.fields where f.type == .input && !f.constant && f.variable && f.usage.page != 0 {
        if f.usage.page >= 0xFF00 {
            mineVendor[VendorKey(reportID: f.reportID, page: f.usage.page, usage: f.usage.id), default: 0] += f.bitSize
        } else {
            mine[Key(reportID: f.reportID, page: f.usage.page, usage: f.usage.id, bits: f.bitSize, min: f.logicalMin, max: f.logicalMax), default: 0] += 1
        }
    }
    var theirs: [Key: Int] = [:]
    var theirsVendor: [VendorKey: Int] = [:]
    let elements = IOHIDDeviceCopyMatchingElements(iface.device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] ?? []
    let inputTypes: Set<UInt32> = [kIOHIDElementTypeInput_Misc.rawValue, kIOHIDElementTypeInput_Button.rawValue,
                                   kIOHIDElementTypeInput_Axis.rawValue]
    for e in elements where inputTypes.contains(IOHIDElementGetType(e).rawValue) {
        guard !IOHIDElementIsVirtual(e), !IOHIDElementIsArray(e), IOHIDElementGetUsagePage(e) != 0 else { continue }
        let size = Int(IOHIDElementGetReportSize(e))
        let count = max(Int(IOHIDElementGetReportCount(e)), 1)
        if IOHIDElementGetUsagePage(e) >= 0xFF00 {
            let key = VendorKey(reportID: Int(IOHIDElementGetReportID(e)), page: IOHIDElementGetUsagePage(e), usage: IOHIDElementGetUsage(e))
            theirsVendor[key, default: 0] += size > 32 ? size : size * count
            continue
        }
        let key = Key(reportID: Int(IOHIDElementGetReportID(e)), page: IOHIDElementGetUsagePage(e), usage: IOHIDElementGetUsage(e),
                      bits: size, min: Int64(IOHIDElementGetLogicalMin(e)), max: Int64(IOHIDElementGetLogicalMax(e)))
        theirs[key, default: 0] += count
    }
    let total = mine.values.reduce(0, +)
    var problems: [String] = []
    for k in Set(mine.keys).union(theirs.keys) where mine[k] != theirs[k] {
        problems.append(String(format: "report 0x%02X usage 0x%02X/0x%02X %d bits %lld…%lld: parser %d, IOKit %d",
                               k.reportID, k.page, k.usage, k.bits, k.min, k.max, mine[k] ?? 0, theirs[k] ?? 0))
    }
    for k in Set(mineVendor.keys).union(theirsVendor.keys) where mineVendor[k] != theirsVendor[k] {
        problems.append(String(format: "report 0x%02X vendor usage 0x%04X/0x%02X: parser %d bits, IOKit %d bits",
                               k.reportID, k.page, k.usage, mineVendor[k] ?? 0, theirsVendor[k] ?? 0))
    }
    if problems.isEmpty {
        let vendor = mineVendor.isEmpty ? "" : " (and on the size of \(mineVendor.count) vendor-defined field group\(mineVendor.count == 1 ? "" : "s"))"
        return "agrees with IOKit on all \(total) input fields\(vendor)"
    }
    return "differs from IOKit on \(problems.count) field kind(s): " + problems.sorted().prefix(4).joined(separator: "; ")
}

func interfaceInfo(_ iface: ProbeInterface) -> InterfaceInfo {
    var reports: [ReportInfo] = []
    if let d = iface.descriptor {
        for type in [ReportType.input, .output, .feature] {
            for id in d.reportIDs(type) {
                let layout = type == .input ? iface.layouts[id] : nil
                reports.append(ReportInfo(type: type, id: id, idHex: hexByte(id), bytes: d.reportBytes(type, id),
                                          decodedAs: layout?.kind.rawValue,
                                          fingerSlots: layout.map { $0.slots.count }.flatMap { $0 > 0 ? $0 : nil }))
            }
        }
    }
    return InterfaceInfo(
        key: iface.key, role: iface.role, primaryUsage: UsageInfo(iface.primaryUsage),
        topLevelUsages: iface.usagePairs.map(UsageInfo.init),
        usesReportIDs: iface.descriptor?.usesReportIDs ?? false, reports: reports,
        maxInputReportSize: iface.maxInputReportSize, maxOutputReportSize: iface.maxOutputReportSize,
        maxFeatureReportSize: iface.maxFeatureReportSize,
        reportDescriptor: iface.descriptorBytes.map(hexString), reportDescriptorLength: iface.descriptorBytes?.count,
        featureReports: rawFeatureReports(iface),
        parserCheck: parserCheck(iface), parserWarnings: iface.descriptor?.warnings ?? [])
}

func touchInterfaceInfo(_ ts: ProbeTouchscreen) -> TouchInterfaceInfo? {
    guard let iface = ts.touch, let d = iface.descriptor else { return nil }
    let layout = iface.touchLayout
    let slots = layout?.slots ?? []
    let firstX = slots.first?.x
    let firstY = slots.first?.y

    let ccmField = d.fields.first { $0.type == .feature && $0.usage == Usages.contactCountMaximum }
    let inputModeField = d.fields.first { $0.type == .feature && $0.usage == Usages.inputMode }
    let deviceIndexPresent = d.fields.contains { $0.type == .feature && $0.usage == Usages.deviceIndex }

    var ccm = FeatureValue(present: false, reportID: nil, value: nil, logicalMax: nil, ioReturn: nil, rawReport: nil, valueTrusted: nil)
    var mode = InputModeInfo(present: false, reportID: nil, value: nil, valueName: nil, ioReturn: nil, deviceIndexPresent: deviceIndexPresent,
                             rawReport: nil, valueTrusted: nil)
    withOpenInterface(iface) {
        if let field = ccmField {
            var value: Int?
            var result: String?
            if let element = iface.featureElement(Usages.contactCountMaximum) {
                let read = readFeature(iface.device, element)
                value = read.value
                result = hex(read.result)
            }
            let raw = readFeatureReport(iface, id: field.reportID).bytes
            ccm = FeatureValue(present: true, reportID: field.reportID, value: value, logicalMax: field.logicalMax, ioReturn: result,
                               rawReport: raw.map(hexString), valueTrusted: featureReportLooksValid(iface, id: field.reportID, bytes: raw))
        }
        if let field = inputModeField {
            var value: Int?
            var result: String?
            if let element = iface.featureElement(Usages.inputMode) {
                let read = readFeature(iface.device, element)
                value = read.value
                result = hex(read.result)
            }
            let raw = readFeatureReport(iface, id: field.reportID).bytes
            mode = InputModeInfo(present: true, reportID: field.reportID, value: value, valueName: value.map(describeMode),
                                 ioReturn: result, deviceIndexPresent: deviceIndexPresent, rawReport: raw.map(hexString),
                                 valueTrusted: featureReportLooksValid(iface, id: field.reportID, bytes: raw))
        }
    }
    let x = axisInfo(firstX)
    let y = axisInfo(firstY)
    var surface: Size?
    if let w = x?.sizeMM, let h = y?.sizeMM { surface = Size(width: w, height: h) }
    return TouchInterfaceInfo(
        interfaceKey: iface.key, inputReportID: layout?.reportID, inputReportBytes: layout?.byteLength,
        fingerCollections: slots.count, contactCountMaximum: ccm,
        hybridModeWouldApply: ccm.value.map { $0 > slots.count },
        inputMode: mode, x: x, y: y, surfaceSizeMM: surface,
        fingerFields: FingerFieldsInfo(
            tipSwitch: presence(slots, \.tip), inRange: presence(slots, \.inRange), confidence: presence(slots, \.confidence),
            contactID: presence(slots, \.contactID), width: presence(slots, \.width), height: presence(slots, \.height),
            azimuth: presence(slots, \.azimuth), pressure: presence(slots, \.pressure)),
        contactCount: presence(layout?.contactCount), scanTime: presence(layout?.scanTime))
}

func touchscreenInfo(_ ts: ProbeTouchscreen) -> TouchscreenInfo {
    let chain = usbChain((ts.touch ?? ts.interfaces[0]).device)
    return TouchscreenInfo(
        number: ts.number, product: ts.product, manufacturer: ts.manufacturer, vendorID: ts.vendorID, productID: ts.productID,
        usbID: usbID(ts.vendorID, ts.productID), serialNumber: ts.serialNumber, versionNumber: ts.versionNumber,
        transport: ts.transport, locationID: hexLocation(ts.locationID), usbDevice: chain.device, usbHubs: chain.hubs,
        usbController: chain.controller, interfaces: ts.interfaces.map(interfaceInfo),
        touchInterface: touchInterfaceInfo(ts), mouseInterfaceKey: ts.mouse?.key)
}
