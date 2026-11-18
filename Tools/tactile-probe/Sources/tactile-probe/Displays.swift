// Displays and the environment the probe runs in.

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import IOKit.hid

func onlineDisplayIDs() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
    return Array(ids.prefix(Int(count))).sorted()
}

func screen(for id: CGDirectDisplayID) -> NSScreen? {
    NSScreen.screens.first {
        ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
    }
}

func displayName(_ id: CGDirectDisplayID) -> String? {
    screen(for: id)?.localizedName
}

func displayInfo(_ id: CGDirectDisplayID) -> DisplayInfo {
    let s = screen(for: id)
    let uuid = CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
    let mode = CGDisplayCopyDisplayMode(id)
    let bounds = CGDisplayBounds(id)
    let physical = CGDisplayScreenSize(id)
    let mirrors = CGDisplayMirrorsDisplay(id)
    let refresh = mode.map { $0.refreshRate }.flatMap { $0 > 0 ? $0 : nil }
    return DisplayInfo(
        displayID: id, name: s?.localizedName,
        vendorNumber: CGDisplayVendorNumber(id), modelNumber: CGDisplayModelNumber(id), serialNumber: CGDisplaySerialNumber(id),
        uuid: uuid,
        physicalSizeMM: Size(width: (Double(physical.width) * 10).rounded() / 10, height: (Double(physical.height) * 10).rounded() / 10),
        pixelSize: mode.map { IntSize(width: $0.pixelWidth, height: $0.pixelHeight) },
        pointSize: Size(width: Double(bounds.width), height: Double(bounds.height)),
        rotationDegrees: CGDisplayRotation(id),
        origin: Point(x: Double(bounds.origin.x), y: Double(bounds.origin.y)),
        builtIn: CGDisplayIsBuiltin(id) != 0, main: CGDisplayIsMain(id) != 0,
        active: CGDisplayIsActive(id) != 0, asleep: CGDisplayIsAsleep(id) != 0,
        refreshRateHz: refresh, backingScaleFactor: s.map { Double($0.backingScaleFactor) },
        mirroring: MirroringInfo(
            inMirrorSet: CGDisplayIsInMirrorSet(id) != 0,
            mirrorsDisplayID: mirrors == kCGNullDirectDisplay ? nil : mirrors,
            alwaysInMirrorSet: CGDisplayIsAlwaysInMirrorSet(id) != 0,
            primaryDisplayID: CGDisplayPrimaryDisplay(id)))
}

func allDisplays() -> [DisplayInfo] { onlineDisplayIDs().map(displayInfo) }

/// The display a global point (pointer coordinates) falls on.
func displayContaining(_ p: CGPoint) -> CGDirectDisplayID? {
    var id: CGDirectDisplayID = 0
    var count: UInt32 = 0
    guard CGGetDisplaysWithPoint(p, 1, &id, &count) == .success, count > 0 else { return nil }
    return id
}

private func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
    return String(cString: buffer)
}

func environmentInfo() -> EnvironmentInfo {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    let version = v.patchVersion == 0 ? "\(v.majorVersion).\(v.minorVersion)" : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    let access: String
    switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
    case kIOHIDAccessTypeGranted: access = "granted"
    case kIOHIDAccessTypeDenied: access = "denied"
    default: access = "unknown"
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone.current
    return EnvironmentInfo(
        tool: toolName, toolVersion: toolVersion, macOSVersion: version, macOSBuild: sysctlString("kern.osversion"),
        hardwareModel: sysctlString("hw.model"), date: formatter.string(from: Date()),
        inputMonitoring: access, accessibility: AXIsProcessTrusted(),
        terminal: ProcessInfo.processInfo.environment["TERM_PROGRAM"])
}
