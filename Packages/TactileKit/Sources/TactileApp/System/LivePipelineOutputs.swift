// The real outputs every touch pipeline shares: events, the pointer, and circles on the displays.

import AppKit
import CoreGraphics
import Foundation
import TactileGestures
import TactileOutput
import TactileScreens

/// The real event sender, pointer keeper, arbiter and element resolver, the Dock-swipe sender, and
/// one circle overlay per display, made when circles are first shown there and closed when its
/// display goes. Thin: every decision is the pipeline's.
///
/// The Dock-swipe sender posts at its own tap (`DockSwipeSender.tap`, the session tap) and reads
/// the Mac through `LiveDockSwipeSurroundings`. It writes one line per swipe to the log; the model
/// turns its per-event lines on while debug logging is on. Only the app makes these outputs: no
/// test does, so no test can post a Dock swipe.
///
/// Lives as long as the app; it never stops observing.
@MainActor
public final class LivePipelineOutputs: PipelineOutputs {
    public let sender: EventSender
    public let keeper: PointerKeeper
    public let arbiter = PointerArbiter<TouchscreenID>()
    public let dockSwipes: DockSwipeSender
    private let dockSwipeWaits: DockSwipeWaits
    private let resolver = ElementResolver()
    private var overlays: [UInt32: TouchCircleOverlay] = [:]
    private var observer: NSObjectProtocol?

    public init() {
        sender = EventSender()
        keeper = PointerKeeper()
        let waits = DockSwipeWaits()
        dockSwipeWaits = waits
        dockSwipes = DockSwipeSender(deliver: { $0.post(tap: DockSwipeSender.tap) },
                                     surroundings: LiveDockSwipeSurroundings(),
                                     clock: { ProcessInfo.processInfo.systemUptime },
                                     schedule: { delay, work in waits.schedule(after: delay, work) })
        dockSwipes.logging = DockSwipeLogging(swipes: true, events: false)
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeOverlaysOfDisplaysGone() }
        }
    }

    public func sendDockSwipeWaitsNow() {
        dockSwipeWaits.runNow()
    }

    public func app(atDesktopPoint point: CGPoint) -> AppUnderPoint? {
        AppUnderPoint.find(at: point)
    }

    public func intent(atDesktopPoint point: CGPoint, inApp pid: pid_t) -> OneFingerIntent {
        resolver.intent(at: point, inApp: pid)
    }

    public func showCircles(_ fingers: [Int: CGPoint], hollow: Set<Int>, ringed: Set<Int>, onDisplay displayID: UInt32) {
        guard let screen = Self.screen(for: displayID) else {
            overlays.removeValue(forKey: displayID)?.close()
            return
        }
        let overlay = overlays[displayID] ?? TouchCircleOverlay()
        overlays[displayID] = overlay
        overlay.show(fingers: fingers, hollow: hollow, ringed: ringed, on: screen)
    }

    public func hideCircles(onDisplay displayID: UInt32) {
        overlays[displayID]?.clear()
    }

    /// Takes down every overlay, for quitting.
    public func closeEveryOverlay() {
        for overlay in overlays.values { overlay.close() }
        overlays = [:]
    }

    private func closeOverlaysOfDisplaysGone() {
        for displayID in overlays.keys where Self.screen(for: displayID) == nil {
            overlays.removeValue(forKey: displayID)?.close()
        }
    }

    private static func screen(for displayID: UInt32) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
    }
}
