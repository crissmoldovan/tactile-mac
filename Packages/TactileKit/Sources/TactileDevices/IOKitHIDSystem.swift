// The HID system through IOKit: matching, opening, the feature report reads, the Input Mode write
// and raw input reports. It decides nothing; `HIDTouchscreenSource` does. The open, seize, close,
// feature-read and mode-write calls are those `Tools/tactile-probe` proved on both panels during
// the survey.

import CoreFoundation
import Foundation
import IOKit
import IOKit.hid

/// Which HID interfaces a system watches.
enum HIDMatching: Sendable {
    /// Touchscreen interfaces (a Touch Screen collection, 0x0D/0x04) and mouse interfaces (a Mouse
    /// collection, 0x01/0x02): the touchscreen source's.
    case touchscreensAndMice
    /// Every interface on the Digitizer page (0x0D), and pointer and mouse interfaces (0x01/0x01,
    /// 0x01/0x02): the support check's, which lists digitisers Tactile doesn't drive and touchscreens
    /// that are only a mouse. Watching opens nothing.
    case supportCheck

    /// IOHIDManager's matching dictionaries.
    var criteria: [[String: Int]] {
        switch self {
        case .touchscreensAndMice:
            return [
                [kIOHIDDeviceUsagePageKey: 0x0D, kIOHIDDeviceUsageKey: 0x04],  // Touch Screen
                [kIOHIDDeviceUsagePageKey: 0x01, kIOHIDDeviceUsageKey: 0x02],  // Mouse
            ]
        case .supportCheck:
            return [
                [kIOHIDDeviceUsagePageKey: 0x0D],                              // any digitiser
                [kIOHIDDeviceUsagePageKey: 0x01, kIOHIDDeviceUsageKey: 0x01],  // Pointer
                [kIOHIDDeviceUsagePageKey: 0x01, kIOHIDDeviceUsageKey: 0x02],  // Mouse
            ]
        }
    }
}

@MainActor
final class IOKitHIDSystem: HIDSystem {
    private let matching: HIDMatching
    private var manager: IOHIDManager?
    /// What the manager's callbacks find the system through. It lives as long as the system.
    private let context = ManagerContext()
    private var devices: [HIDInterfaceID: IOHIDDevice] = [:]
    private var inputModeElements: [HIDInterfaceID: IOHIDElement] = [:]
    /// The interfaces open now, and whether each was opened exclusively.
    private var openInterfaces: [HIDInterfaceID: Bool] = [:]
    private var links: [HIDInterfaceID: ReportLink] = [:]
    /// Links of interfaces that went. IOKit may still hold their context pointer, so they are kept
    /// until matching stops.
    private var retiredLinks: [ReportLink] = []
    private var matched: (@MainActor (HIDInterfaceDescription) -> Void)?
    private var removed: (@MainActor (HIDInterfaceID) -> Void)?

    init(matching: HIDMatching = .touchscreensAndMice) {
        self.matching = matching
        context.system = self
    }

    /// The source stops matching before it goes, through its own `stop()` or `deinit`. This is the
    /// safety net if the system goes first: nothing IOKit holds may point into freed memory.
    deinit {
        guard Thread.isMainThread else { return }
        MainActor.assumeIsolated { stopMatching() }
    }

    // MARK: Matching

    func startMatching(matched: @escaping @MainActor (HIDInterfaceDescription) -> Void,
                       removed: @escaping @MainActor (HIDInterfaceID) -> Void) {
        guard manager == nil else { return }
        self.matched = matched
        self.removed = removed
        // The manager is never opened: IOHIDManagerOpen would open every matched interface, every
        // mouse on the Mac included. Each interface is opened by itself, and only when taken.
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching.criteria as CFArray)
        let pointer = Unmanaged.passUnretained(context).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatchedCallback, pointer)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemovedCallback, pointer)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        self.manager = manager
        // Those connected now are delivered at once; the manager's own first callbacks for them,
        // which come on the run loop, are then duplicates and ignored.
        let present = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        for device in present.sorted(by: { Self.entryID($0) < Self.entryID($1) }) { add(device) }
    }

    /// Unschedules the manager and every device from the run loop, so no callback can come with a
    /// context or a report buffer that is about to be freed, and closes any interface still open.
    /// Callbacks are not unregistered with NULL: the survey never tried that, and unscheduling
    /// stops their delivery.
    func stopMatching() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        for link in links.values { link.handler = nil }
        for (id, exclusive) in openInterfaces { close(id, exclusive: exclusive) }
        for device in devices.values {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        }
        self.manager = nil
        openInterfaces = [:]
        matched = nil
        removed = nil
        devices = [:]
        inputModeElements = [:]
        links = [:]
        retiredLinks = []
    }

    func later(_ work: @escaping @MainActor () -> Void) {
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
            MainActor.assumeIsolated { work() }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    fileprivate func add(_ device: IOHIDDevice) {
        guard manager != nil else { return }
        let id = Self.entryID(device)
        guard id != 0, devices[id] == nil else { return }
        devices[id] = device
        matched?(Self.describe(device, id: id))
    }

    fileprivate func remove(_ device: IOHIDDevice) {
        guard manager != nil else { return }
        let id = devices.first { $0.value === device }?.key ?? Self.entryID(device)
        guard devices[id] != nil else { return }
        removed?(id)
        devices[id] = nil
        inputModeElements[id] = nil
        openInterfaces[id] = nil
        if let link = links.removeValue(forKey: id) {
            link.handler = nil
            retiredLinks.append(link)
        }
    }

    // MARK: One interface

    func open(_ id: HIDInterfaceID, exclusive: Bool) -> IOReturn {
        guard let device = devices[id] else { return IOResult.noDevice }
        let result = IOHIDDeviceOpen(device, IOOptionBits(exclusive ? kIOHIDOptionsTypeSeizeDevice : kIOHIDOptionsTypeNone))
        if result == kIOReturnSuccess { openInterfaces[id] = exclusive }
        return result
    }

    @discardableResult
    func close(_ id: HIDInterfaceID, exclusive: Bool) -> IOReturn {
        guard let device = devices[id] else { return IOResult.noDevice }
        openInterfaces[id] = nil
        return IOHIDDeviceClose(device, IOOptionBits(exclusive ? kIOHIDOptionsTypeSeizeDevice : kIOHIDOptionsTypeNone))
    }

    func hasInputMode(_ id: HIDInterfaceID) -> Bool {
        inputModeElement(id) != nil
    }

    /// The call `Tools/tactile-probe` made on both panels in the survey (`readFeatureReport` in its
    /// Devices.swift), asking for exactly the declared size: some firmware answers with as many
    /// bytes as it is asked for. It waits for the panel's answer, up to the HID request timeout
    /// (5 s on this desk's panels), and says how long it waited and how many bytes came back.
    func readFeatureReport(_ id: HIDInterfaceID, reportID: Int, length: Int) -> FeatureReportRead {
        guard let device = devices[id] else { return FeatureReportRead(result: IOResult.noDevice, length: 0, seconds: 0) }
        guard length > 0 else { return FeatureReportRead(result: IOResult.badArgument, length: 0, seconds: 0) }
        var buffer = [UInt8](repeating: 0, count: length)
        var reportLength = CFIndex(length)
        let start = ProcessInfo.processInfo.systemUptime
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(reportID), &buffer, &reportLength)
        let seconds = ProcessInfo.processInfo.systemUptime - start
        let returned = result == kIOReturnSuccess ? min(max(Int(reportLength), 0), length) : 0
        return FeatureReportRead(result: result, length: returned, seconds: seconds, bytes: Array(buffer.prefix(returned)))
    }

    /// The HID stack builds the whole feature report, keeping its other fields (such as Device
    /// Index) at their current values.
    func writeInputMode(_ id: HIDInterfaceID, _ value: Int) -> IOReturn {
        guard let device = devices[id] else { return IOResult.noDevice }
        guard let element = inputModeElement(id) else { return IOResult.notFound }
        let hidValue = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, mach_absolute_time(), value)
        return IOHIDDeviceSetValue(device, element, hidValue)
    }

    func startReports(_ id: HIDInterfaceID, bufferSize: Int,
                      _ handler: @escaping @MainActor ([UInt8], TimeInterval) -> Void) {
        guard let device = devices[id] else { return }
        let link: ReportLink
        if let existing = links[id], existing.bufferSize >= bufferSize {
            link = existing
        } else {
            if let old = links[id] { retiredLinks.append(old) }
            link = ReportLink(bufferSize: bufferSize)
            links[id] = link
        }
        link.handler = handler
        // Registered again on every open, as the survey tool did. Scheduled in common modes, so
        // reports keep coming while a menu is open.
        IOHIDDeviceRegisterInputReportWithTimeStampCallback(device, link.buffer, link.bufferSize, inputReportCallback,
                                                            Unmanaged.passUnretained(link).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }

    /// Reports stop reaching the handler at once; the interface stops sending when it is closed.
    func stopReports(_ id: HIDInterfaceID) {
        links[id]?.handler = nil
    }

    // MARK: Reading an interface

    private func inputModeElement(_ id: HIDInterfaceID) -> IOHIDElement? {
        if let element = inputModeElements[id] { return element }
        guard let device = devices[id] else { return nil }
        let matching: [String: Int] = [
            kIOHIDElementUsagePageKey: 0x0D,
            kIOHIDElementUsageKey: 0x52,  // Input Mode
            kIOHIDElementTypeKey: Int(kIOHIDElementTypeFeature.rawValue),
        ]
        let elements = IOHIDDeviceCopyMatchingElements(device, matching as CFDictionary, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement]
        let element = elements?.first
        inputModeElements[id] = element
        return element
    }

    private static func entryID(_ device: IOHIDDevice) -> HIDInterfaceID {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
        return id
    }

    private static func describe(_ device: IOHIDDevice, id: HIDInterfaceID) -> HIDInterfaceDescription {
        func property<T>(_ key: String) -> T? {
            IOHIDDeviceGetProperty(device, key as CFString) as? T
        }
        let location: Int = property(kIOHIDLocationIDKey) ?? 0
        let pairs: [[String: Any]] = property(kIOHIDDeviceUsagePairsKey) ?? []
        var usages = pairs.compactMap { pair -> HIDUsage? in
            guard let page = pair[kIOHIDDeviceUsagePageKey] as? Int, let usage = pair[kIOHIDDeviceUsageKey] as? Int else { return nil }
            return HIDUsage(page: page, usage: usage)
        }
        if usages.isEmpty, let page: Int = property(kIOHIDPrimaryUsagePageKey), let usage: Int = property(kIOHIDPrimaryUsageKey) {
            usages = [HIDUsage(page: page, usage: usage)]
        }
        let descriptor: Data? = property(kIOHIDReportDescriptorKey)
        return HIDInterfaceDescription(
            id: id, locationID: UInt32(truncatingIfNeeded: location),
            vendorID: property(kIOHIDVendorIDKey) ?? 0, productID: property(kIOHIDProductIDKey) ?? 0,
            serial: property(kIOHIDSerialNumberKey) ?? "", product: property(kIOHIDProductKey) ?? "",
            usages: usages,
            descriptor: descriptor.map { [UInt8]($0) },
            maxInputReportSize: property(kIOHIDMaxInputReportSizeKey),
            manufacturer: property(kIOHIDManufacturerKey) ?? "",
            isBuiltIn: property(kIOHIDBuiltInKey) ?? false)
    }
}

/// What the manager's callbacks are given: a way back to the system that does not keep it alive.
private final class ManagerContext {
    weak var system: IOKitHIDSystem?
}

/// One interface's report buffer and where its reports go.
private final class ReportLink {
    let bufferSize: Int
    let buffer: UnsafeMutablePointer<UInt8>
    var handler: (@MainActor ([UInt8], TimeInterval) -> Void)?

    init(bufferSize: Int) {
        self.bufferSize = bufferSize
        buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        buffer.initialize(repeating: 0, count: bufferSize)
    }

    deinit {
        buffer.deallocate()
    }
}

// MARK: - The C callbacks. The manager and the devices are scheduled on the main run loop, so
// each runs on the main thread.

private let deviceMatchedCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    let box = Unmanaged<ManagerContext>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { box.system?.add(device) }
}

private let deviceRemovedCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    let box = Unmanaged<ManagerContext>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { box.system?.remove(device) }
}

private let inputReportCallback: IOHIDReportWithTimeStampCallback = { context, result, _, _, _, report, length, timestamp in
    guard let context, result == kIOReturnSuccess, length > 0 else { return }
    let link = Unmanaged<ReportLink>.fromOpaque(context).takeUnretainedValue()
    let bytes = Array(UnsafeBufferPointer(start: report, count: min(Int(length), link.bufferSize)))
    MainActor.assumeIsolated {
        // The timestamp is mach absolute time; in seconds it is on `systemUptime`'s clock (see `HostClock`).
        let time = HostClock.reportTime(timestamp: timestamp, now: ProcessInfo.processInfo.systemUptime)
        link.handler?(bytes, time)
    }
}
