// The connected displays, from CoreGraphics and AppKit, kept current.

import AppKit
import CoreGraphics
import Foundation
import TactileScreens
import os

/// Every online display as `DisplayFacts`. Thin: what the raw values become is decided, and
/// tested, in `DisplayReading`, and what is published while displays reconfigure in
/// `PublishedDisplays`.
///
/// - When CoreGraphics says a reconfiguration has begun, there are no displays until it ends, so
///   no touch is mapped through a frame that is changing.
/// - The displays are read again when the reconfiguration ends, and whenever AppKit says the
///   screens changed (which it says only after the change). If neither comes within 5 seconds of a
///   reconfiguration beginning, they are read again anyway.
///
/// Lives as long as the app: the reconfiguration callback keeps it, and it never stops observing.
@MainActor
public final class LiveDisplaySource: DisplaySource {
    public var displays: [DisplayFacts] { published.displays }
    public var onChange: (@MainActor () -> Void)?

    private static let log = Logger(subsystem: "com.crissmoldovan.tactile", category: "displays")
    private var published: PublishedDisplays
    private var observer: NSObjectProtocol?

    public init() {
        published = PublishedDisplays(Self.read())
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.settle() }
        }
        CGDisplayRegisterReconfigurationCallback(Self.reconfigured, Unmanaged.passRetained(self).toOpaque())
    }

    /// CoreGraphics calls this for each display before a reconfiguration, with the begin flag, and
    /// again after it, without.
    private static let reconfigured: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
        guard let userInfo else { return }
        let source = Unmanaged<LiveDisplaySource>.fromOpaque(userInfo).takeUnretainedValue()
        let began = flags.contains(.beginConfigurationFlag)
        let deliver: @Sendable () -> Void = {
            MainActor.assumeIsolated {
                if began { source.reconfigurationBegan() } else { source.settle() }
            }
        }
        if Thread.isMainThread { deliver() } else { DispatchQueue.main.async(execute: deliver) }
    }

    private func reconfigurationBegan() {
        let (changed, fallback) = published.reconfigurationBegan()
        if let fallback {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.published.needsFallback(fallback) else { return }
                    Self.log.error("No end of the reconfiguration after 5 s; reading the displays again")
                    self.settle()
                }
            }
        }
        guard changed else { return }
        Self.log.info("Displays reconfiguring: none until they settle")
        onChange?()
    }

    private func settle() {
        guard published.settled(Self.read()) else { return }
        Self.log.info("Displays: \(self.displays.map { "\($0.displayID) \"\($0.name)\" \(String(describing: $0.frame))" }.joined(separator: "; "), privacy: .public)")
        onChange?()
    }

    private static func read() -> [DisplayFacts] {
        onlineDisplayIDs().compactMap { id in
            let raw = rawDisplay(id)
            guard let facts = DisplayReading.facts(from: raw) else {
                log.error("Display \(id) left out: its frame \(String(describing: raw.bounds), privacy: .public) isn't finite")
                return nil
            }
            return facts
        }
    }

    private static func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count))).sorted()
    }

    private static func rawDisplay(_ id: CGDirectDisplayID) -> RawDisplay {
        let uuid = CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String? }
        return RawDisplay(
            displayID: id,
            uuid: uuid ?? nil,
            vendor: CGDisplayVendorNumber(id),
            model: CGDisplayModelNumber(id),
            serial: CGDisplaySerialNumber(id),
            modes: modes(id),
            screenSizeMM: CGDisplayScreenSize(id),
            screenName: screen(for: id)?.localizedName,
            bounds: CGDisplayBounds(id),
            rotation: CGDisplayRotation(id),
            isBuiltIn: CGDisplayIsBuiltin(id) != 0,
            isMain: CGDisplayIsMain(id) != 0,
            mirrors: CGDisplayMirrorsDisplay(id))
    }

    /// Every mode the display advertises, HiDPI ones included; the current one when it lists none.
    private static func modes(_ id: CGDirectDisplayID) -> [RawMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        var modes = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? []
        if modes.isEmpty, let current = CGDisplayCopyDisplayMode(id) { modes = [current] }
        return modes.map {
            RawMode(pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight, width: $0.width, height: $0.height,
                    ioFlags: $0.ioFlags)
        }
    }

    private static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }
}
