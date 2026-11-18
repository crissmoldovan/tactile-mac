import ColorSync
import CoreGraphics
import Darwin
import Foundation
import os
import TactileGestures

/// Posts the Dock's own swipe events, so the Desktops slide under the fingers as they do under a
/// trackpad's: one `began`, `changed` events as the fingers move, and exactly one end, completed or
/// cancelled.
///
/// The events are undocumented. What they hold was learned from other projects that post them,
/// which NOTICE.md credits; only facts were taken. They are built for macOS 12 to 26, where the
/// Dock reads plain `CGEvent` fields. From macOS 27 it reads a private payload that this sender
/// does not build, so there it is unavailable and the person gets the keyboard shortcuts.
///
/// The rule that binds it: after a `began` it posted, exactly one end goes out, on every path. A
/// swipe left open leaves the screen stuck between two Desktops. Every event leaves through
/// `deliver`, which the app gives; tests read the events there and nothing else posts. Main
/// thread only.
///
/// For the code that wires it in:
/// - `deliver` must post at `DockSwipeSender.tap`, the session tap.
/// - `displayWidth` is in points.
/// - Keep one sender for the app's life: the open swipe and its repeated end live in it.
/// - `isOpen` turns false as the end is posted, before the end is repeated `endRepeatDelay` later.
///   Keep the pointer on that display for `endRepeatDelay` after the end, so the repeat reaches
///   the same Spaces.
/// - `isAvailable(_:onDisplay:)` asks the window server for the display's Spaces: it is for a
///   swipe's beginning, not for every session's start. `isAvailable(_:)` reads the person's settings.
/// - Call `closeIfOpen()` on every way a touch can stop. The engine's later actions for a swipe
///   closed that way are then handled with nothing posted, and return true.
/// - It logs nothing until `logging` says so: set `swipes` in the app, and `events` only while the
///   person has asked for a detailed log. Tests leave both off.
@MainActor
public final class DockSwipeSender {

    /// Where the app's `deliver` should post: every known tool posts Dock swipes at the session
    /// tap, not at the HID tap where Tactile posts everything else.
    public nonisolated static let tap: CGEventTapLocation = .cgSessionEventTap

    /// The end is delivered once more this long after it, unless a new swipe has begun by then: the
    /// Dock sometimes misses an end when the system is busy, and Mac Mouse Fix has resent it at
    /// 0.2 s since 2021. One repeat, at its first delay, so it goes
    /// while the pointer is still on the touchscreen's display (the keeper sends it home 0.4 s after
    /// the lift at the soonest).
    public nonisolated static let endRepeatDelay: TimeInterval = 0.2

    /// The macOS versions whose Dock reads these events' fields. From 27 it reads a private payload.
    nonisolated static let macOSVersions: ClosedRange<Int> = 12...26
    /// At most one `changed` event in this time; faster makes the Dock fall behind.
    nonisolated static let changedInterval: TimeInterval = 0.008
    /// The gap between Spaces, in points: one display width plus this is one Space. Mac Mouse Fix's
    /// measurement, which the others copy: no second measurement is known.
    nonisolated static let spaceGap: Double = 63
    /// The largest speed sent with an end, in progress per second: much larger skips the animation
    /// (the units are inferred, and still to be tuned by hand).
    nonisolated static let velocityLimit: Double = 50

    /// Runs `work` on the main thread after `delay` seconds.
    public typealias Schedule = (_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> Void

    private let deliver: (CGEvent) -> Void
    private let surroundings: DockSwipeSurroundings
    private let clock: () -> TimeInterval
    private let schedule: Schedule
    /// Makes each event before its fields are set. Tests make it fail.
    var makeEvent: () -> CGEvent? = { CGEvent(source: nil) }

    /// What it writes to the log. Nothing, unless the app asks.
    public var logging = DockSwipeLogging.quiet

    private static let log = Logger(subsystem: "com.crissmoldovan.tactile", category: "dockswipe")

    /// A swipe whose `began` was posted and whose end hasn't been.
    private struct OpenSwipe {
        let axis: SwipeAxis
        /// Progress per unit of the engine's offset: negative, as fingers moving left show the
        /// Space on the right.
        let scale: Double
        /// One Space in the Dock's units: the most progress either way.
        let perSpace: Double
        /// A cancelled end, built before the `began` was posted, for when the real end can't be built.
        let fallbackEnd: [CGEvent]
        /// The progress last said by the engine, and the progress last posted.
        var latest: Double
        var posted: Double
        var lastPostTime: TimeInterval
        var flushScheduled = false
    }

    private var open: OpenSwipe?
    /// The axis of a swipe closed before its own end came: its remaining actions are handled with
    /// nothing. Forgotten at its end, or at the next `began`.
    private var closedEarly: SwipeAxis?
    /// Counts the swipes begun, so a repeat or a flush scheduled for an earlier one does nothing.
    private var swipeNumber = 0

    /// A sender with the system's clock, and the main queue to wait on.
    public convenience init(deliver: @escaping (CGEvent) -> Void, surroundings: DockSwipeSurroundings) {
        self.init(deliver: deliver, surroundings: surroundings,
                  clock: { ProcessInfo.processInfo.systemUptime },
                  schedule: { delay, work in
                      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { work() } }
                  })
    }

    /// A sender whose time is `clock`, in seconds, and whose waits go through `schedule`.
    public init(deliver: @escaping (CGEvent) -> Void, surroundings: DockSwipeSurroundings,
                clock: @escaping () -> TimeInterval, schedule: @escaping Schedule) {
        self.deliver = deliver
        self.surroundings = surroundings
        self.clock = clock
        self.schedule = schedule
    }

    /// Whether a swipe along this axis can be followed now. False means: use the shortcut.
    /// Horizontal only, on macOS 12 to 26, with the person's gesture switched on. A swipe also
    /// needs the number of Spaces on its display, which `isAvailable(_:onDisplay:)` checks too.
    public func isAvailable(_ axis: SwipeAxis) -> Bool {
        axis == .horizontal && Self.macOSVersions.contains(surroundings.macOSMajorVersion)
            && surroundings.isSpaceSwipeEnabled
    }

    /// `isAvailable(_:)`, and the number of Spaces on that display can be found out. This asks the
    /// window server: for a swipe's beginning, not for every session's start.
    public func isAvailable(_ axis: SwipeAxis, onDisplay displayID: UInt32) -> Bool {
        isAvailable(axis) && spaceCount(onDisplay: displayID) != nil
    }

    public var isOpen: Bool { open != nil }

    /// One `swipeTracking` action. Returns true when it was handled: posted, held back for a moment,
    /// or part of a swipe closed early, for which nothing more is to be done. Returns false when
    /// nothing was posted for it and the caller's shortcut should stand in.
    ///
    /// Whether a swipe can be followed is decided at its `began`, from `displayID` (whose Spaces
    /// it moves) and `displayWidth` (in points); later phases use what was decided then, so a
    /// swipe begun is never cut off half way.
    /// - A `changed` or an end for a swipe it never began posts nothing and returns false.
    /// - A second `began` while one is open first closes that one as cancelled. So does any other
    ///   call for the other axis, which then goes on as for a swipe never begun.
    /// - A swipe closed before its own end came is closed early: by `closeIfOpen()` (the displays
    ///   changed, the Mac is going to sleep, the fingers still down), by a call for the other axis,
    ///   or by a new `began`, unless that `began` was accepted on the same axis (then what follows
    ///   is the new swipe's). Its later `changed` and its end post nothing and return true:
    ///   handled, with no shortcut to follow, since the Dock has already slid back. This lasts
    ///   until its end, or the next `began`.
    /// - A `changed` held back by the rate limit returns true: its position goes out within 8 ms,
    ///   or with the end.
    /// - A `completed` returns false if only the cancelled end built before the `began` could be
    ///   posted for it, so the caller's shortcut still moves the Desktop.
    @discardableResult
    public func handle(axis: SwipeAxis, offset: Double, phase: SwipeTrackingPhase,
                       displayID: UInt32, displayWidth: Double) -> Bool {
        if phase != .began, let swipe = open, swipe.axis != axis {
            // The open swipe's own end may never come: close it now, whoever keeps the books.
            closeIfOpen()
        }
        switch phase {
        case .began:
            let closing = open?.axis
            closeIfOpen()
            // The swipe this closes is closed early; with none open, an older early close is forgotten.
            closedEarly = closing
            let accepted = begin(axis: axis, offset: offset, displayID: displayID, displayWidth: displayWidth)
            // What follows on the same axis is the new swipe's.
            if accepted, closing == axis { closedEarly = nil }
            return accepted
        case .changed:
            if closedEarly == axis { return true }
            guard var swipe = open, swipe.axis == axis else { return false }
            swipe.latest = clamped(offset, swipe)
            open = swipe
            return postLatest()
        case .completed(let velocity):
            if closedEarly == axis {
                closedEarly = nil
                return true
            }
            guard let swipe = open, swipe.axis == axis else { return false }
            let progress = clamped(offset, swipe)
            // Nowhere to go on to: the Dock would go left, as it does after a real trackpad's.
            guard progress != 0 else { return finish(.cancelled, progress: 0, velocity: 0) }
            // Velocity in progress per second, scaled as the offset. Never against the way it
            // goes, and clamped.
            let speed = velocity * swipe.scale
            let onwards = speed * progress > 0 ? speed : 0
            return finish(.ended, progress: progress,
                          velocity: min(max(onwards, -Self.velocityLimit), Self.velocityLimit))
        case .cancelled:
            if closedEarly == axis {
                closedEarly = nil
                return true
            }
            guard let swipe = open, swipe.axis == axis else { return false }
            return finish(.cancelled, progress: clamped(offset, swipe), velocity: 0)
        }
    }

    /// Posts a cancelled end if a swipe is open, at its latest progress. Safe to call at any time,
    /// any number of times. The engine's later actions for that swipe are handled with nothing.
    public func closeIfOpen() {
        guard let swipe = open else { return }
        finish(.cancelled, progress: swipe.latest, velocity: 0, early: true)
        closedEarly = swipe.axis
    }

    // MARK: - The swipe

    private func begin(axis: SwipeAxis, offset: Double, displayID: UInt32, displayWidth: Double) -> Bool {
        guard isAvailable(axis), displayWidth > 0, let spaces = spaceCount(onDisplay: displayID) else {
            if logging.swipes {
                Self.log.info("not followed: \(axis == .horizontal ? "horizontal" : "vertical", privacy: .public), macOS \(self.surroundings.macOSMajorVersion), gesture \(self.surroundings.isSpaceSwipeEnabled), width \(displayWidth)")
            }
            return false
        }
        // One display width plus the gap is one Space, which the Dock counts as n/(n−1); with one
        // Space, 2: the Dock's `progress` counts Spaces that way.
        let perSpace = spaces <= 1 ? 2 : Double(spaces) / Double(spaces - 1)
        let scale = -displayWidth / (displayWidth + Self.spaceGap) * perSpace
        let progress = min(max(offset * scale, -perSpace), perSpace)
        // The end is built before the beginning, so a failure later can't leave the Dock open
        // (Space Rabbit does the same).
        guard let fallbackEnd = events(.cancelled, progress: progress, velocity: 0),
              let began = events(.began, progress: progress, velocity: nil) else {
            if logging.swipes { Self.log.error("not followed: the events couldn't be made") }
            return false
        }
        swipeNumber += 1
        open = OpenSwipe(axis: axis, scale: scale, perSpace: perSpace, fallbackEnd: fallbackEnd,
                         latest: progress, posted: progress, lastPostTime: clock())
        post(began)
        if logging.swipes { Self.log.info("began: progress \(progress), \(spaces) Spaces, \(perSpace) a Space") }
        return true
    }

    /// Posts the latest progress as a `changed` now or, within 8 ms of the last post, once those
    /// 8 ms are up.
    private func postLatest() -> Bool {
        guard var swipe = open else { return false }
        guard swipe.latest != swipe.posted else { return true }
        let wait = Self.changedInterval - (clock() - swipe.lastPostTime)
        guard wait > 0 else { return postChanged() }
        if !swipe.flushScheduled {
            swipe.flushScheduled = true
            open = swipe
            let number = swipeNumber
            schedule(wait) { [weak self] in self?.flush(number) }
        }
        return true
    }

    /// The 8 ms are up: posts the latest progress without measuring them again. A clock read at
    /// the deadline can fall a hair short of it, and measuring again would wait for ever.
    private func flush(_ number: Int) {
        guard number == swipeNumber, var swipe = open else { return }
        swipe.flushScheduled = false
        open = swipe
        _ = postChanged()
    }

    /// Posts the latest progress as a `changed`, unless it is the one last posted.
    private func postChanged() -> Bool {
        guard var swipe = open else { return false }
        guard swipe.latest != swipe.posted else { return true }
        let progress = swipe.latest
        guard let changed = events(.changed, progress: progress, velocity: nil) else { return false }
        swipe.posted = progress
        swipe.lastPostTime = clock()
        open = swipe
        post(changed)
        if logging.events { Self.log.debug("changed: progress \(progress)") }
        return true
    }

    /// Posts the one end and closes the swipe; schedules its repeat. Returns whether the end posted
    /// is the one asked for. `early`: closed by `closeIfOpen()`, before the swipe's own end came.
    @discardableResult
    private func finish(_ phase: Phase, progress: Double, velocity: Double, early: Bool = false) -> Bool {
        guard let swipe = open else { return false }
        open = nil
        let built = events(phase, progress: progress, velocity: velocity)
        // Never drop an end: if it can't be built, the cancel built before the began goes instead
        // (Space Rabbit does the same).
        let end = built ?? swipe.fallbackEnd
        post(end)
        if logging.swipes {
            Self.log.info("\(built == nil ? "fallback cancelled" : phase == .ended ? "ended" : "cancelled", privacy: .public)\(early ? ", closed early" : "", privacy: .public): progress \(progress), velocity \(velocity)")
        }
        let number = swipeNumber
        schedule(Self.endRepeatDelay) { [weak self] in
            guard let self, self.swipeNumber == number else { return }
            self.post(end)
            if self.logging.events { Self.log.debug("end repeated") }
        }
        return built != nil || phase == .cancelled
    }

    private func clamped(_ offset: Double, _ swipe: OpenSwipe) -> Double {
        min(max(offset * swipe.scale, -swipe.perSpace), swipe.perSpace)
    }

    private func spaceCount(onDisplay displayID: UInt32) -> Int? {
        guard let count = surroundings.spaceCount(forDisplay: displayID), count >= 1 else { return nil }
        return count
    }

    // MARK: - The events

    /// The phases, as field 132 takes them: IOHID's phase values.
    enum Phase: Int64 {
        case began = 1
        case changed = 2
        case ended = 4
        case cancelled = 8
    }

    /// The fields of a Dock swipe, by number, with Apple's names from WebKit's
    /// `CoreGraphicsTestSPI.h`. Every value is what the Dock reads on macOS 12 to 26, where it
    /// reads plain `CGEvent` fields. Deliberately not set: 125 and 126 (positions, not needed up to 26), 135 (overlaps 124), 136 (left 0), 41, 119,
    /// 139 and 165 (constants that did nothing), and 4205 (macOS 27's payload, not built).
    enum Field {
        /// `kCGSEventTypeField`: 30, `kCGSEventDockControl`, as the event's type. Every tool.
        static let eventType: UInt32 = 55
        /// `kCGEventGestureHIDType`: 23, `kIOHIDEventTypeDockSwipe`. Every tool.
        static let hidType: UInt32 = 110
        /// `kCGEventGestureSwipeMotion`: 1, horizontal, which moves Spaces. Every tool.
        static let motion: UInt32 = 123
        /// `kCGEventGestureSwipeProgress`: the travel since the gesture began, signed, in the Dock's
        /// units. Every tool.
        static let progress: UInt32 = 124
        /// `kCGEventGestureSwipeVelocityX` and `Y`: the speed at lift, only on an end; a trackpad
        /// puts the same value in both. Mac Mouse Fix, InstantSpaceSwitcher, tbodt, yabai.
        static let velocityX: UInt32 = 129
        static let velocityY: UInt32 = 130
        /// `kCGEventGesturePhase`: `Phase`. Every tool.
        static let phase: UInt32 = 132
        /// `kCGEventGestureSwipeMask`: the phase again. InstantSpaceSwitcher sets it because a real
        /// trackpad's swipe carries it; Mac Mouse Fix sets it without knowing whether the Dock needs
        /// it. Purpose unclear; harmless.
        static let swipeMask: UInt32 = 134
        /// `kCGEventGestureFlavor`: 3, `kIOHIDGestureFlavorDockPrimary`. Optional up to 26; set on
        /// each event, as a real trackpad's swipe carries it.
        static let flavor: UInt32 = 138
    }

    /// A Dock swipe event (type 30) and the empty gesture event (type 29) that follows it, or nil if
    /// either can't be made. Mac Mouse Fix posts the companion; the sources disagree on whether it
    /// is needed, and it costs nothing.
    private func events(_ phase: Phase, progress: Double, velocity: Double?) -> [CGEvent]? {
        guard let swipe = makeEvent(), let companion = makeEvent(),
              let dockControl = CGEventType(rawValue: 30), let gesture = CGEventType(rawValue: 29) else { return nil }
        swipe.type = dockControl
        let integers: [(UInt32, Int64)] = [
            (Field.eventType, 30), (Field.hidType, 23), (Field.motion, 1),
            (Field.phase, phase.rawValue), (Field.swipeMask, phase.rawValue), (Field.flavor, 3),
        ]
        for (field, value) in integers {
            if let key = CGEventField(rawValue: field) { swipe.setIntegerValueField(key, value: value) }
        }
        var doubles: [(UInt32, Double)] = [(Field.progress, progress)]
        if let velocity { doubles += [(Field.velocityX, velocity), (Field.velocityY, velocity)] }
        for (field, value) in doubles {
            if let key = CGEventField(rawValue: field) { swipe.setDoubleValueField(key, value: value) }
        }
        companion.type = gesture
        return [swipe, companion]
    }

    /// Tags each event as Tactile's, last, counts it in `EventSender.lastPostTime` so the pointer
    /// keeper knows it for Tactile's own, and hands it to `deliver`.
    private func post(_ events: [CGEvent]) {
        for event in events {
            event.setIntegerValueField(.eventSourceUserData, value: EventSender.tag)
            EventSender.lastPostTime = ProcessInfo.processInfo.systemUptime
            deliver(event)
        }
    }
}

// MARK: - The log

/// What a `DockSwipeSender` writes to the log, under Tactile's subsystem, category `dockswipe`.
/// Both are off unless the app turns them on: a sender built in a test logs nothing.
public struct DockSwipeLogging: Equatable, Sendable {
    /// One line per swipe, at info level: its beginning (or why it couldn't be followed), and its
    /// end with the phase. The app turns this on.
    public var swipes: Bool
    /// One line per event after the beginning (each `changed`, the repeated end), at debug level.
    /// The app turns this on only while the person has asked for a detailed log.
    public var events: Bool

    public init(swipes: Bool, events: Bool) {
        self.swipes = swipes
        self.events = events
    }

    /// Nothing at all: the default.
    public static let quiet = DockSwipeLogging(swipes: false, events: false)
}

// MARK: - The surroundings

/// What the sender needs to know about the Mac, behind a seam so tests can set it.
public protocol DockSwipeSurroundings {
    var macOSMajorVersion: Int { get }
    /// The number of Spaces on that display, or nil when it can't be found out.
    func spaceCount(forDisplay displayID: UInt32) -> Int?
    /// Whether the person has "swipe between full-screen applications" on in System Settings.
    var isSpaceSwipeEnabled: Bool { get }
}

/// The Mac's own answers. It only reads: the system's version, the window server's list of Spaces,
/// and the person's trackpad settings. No test calls it.
public struct LiveDockSwipeSurroundings: DockSwipeSurroundings {

    public init() {}

    public var macOSMajorVersion: Int {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }

    /// From `SLSCopyManagedDisplaySpaces`, the window server's Spaces for each display: a private
    /// function, reached through `dlsym`, so nil when it is missing. Each entry names its display by UUID;
    /// "Main" stands for the main display, and for every display when "Displays have separate
    /// Spaces" is off and it is the only entry. Full-screen apps' Spaces count: a swipe goes
    /// through them.
    public func spaceCount(forDisplay displayID: UInt32) -> Int? {
        typealias MainConnectionID = @convention(c) () -> Int32
        typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
        let everyImage = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
        guard let connectionSymbol = dlsym(everyImage, "SLSMainConnectionID"),
              let copySymbol = dlsym(everyImage, "SLSCopyManagedDisplaySpaces") else { return nil }
        let connection = unsafeBitCast(connectionSymbol, to: MainConnectionID.self)()
        guard let copied = unsafeBitCast(copySymbol, to: CopyManagedDisplaySpaces.self)(connection),
              let entries = copied.takeRetainedValue() as? [[String: Any]] else { return nil }
        let uuid = CGDisplayCreateUUIDFromDisplayID(displayID).map {
            CFUUIDCreateString(nil, $0.takeRetainedValue()) as String
        }
        func names(_ entry: [String: Any]) -> Bool {
            guard let identifier = entry["Display Identifier"] as? String else { return false }
            if let uuid, identifier.caseInsensitiveCompare(uuid) == .orderedSame { return true }
            return identifier == "Main" && (entries.count == 1 || displayID == CGMainDisplayID())
        }
        return (entries.first(where: names)?["Spaces"] as? [Any])?.count
    }

    /// The person's trackpad settings, decided by `SpaceSwipeSetting.isOn(foundIn:)`: a key missing
    /// everywhere is not on. What was found, and what was decided, is logged once a launch.
    public var isSpaceSwipeEnabled: Bool {
        let found = SpaceSwipeSetting.domains.map { domain -> [String: Any] in
            guard let defaults = UserDefaults(suiteName: domain) else { return [:] }
            return SpaceSwipeSetting.keys.reduce(into: [:]) { values, key in values[key] = defaults.object(forKey: key) }
        }
        let isOn = SpaceSwipeSetting.isOn(foundIn: found)
        if !Self.hasLoggedSpaceSwipe {
            Self.hasLoggedSpaceSwipe = true
            Self.log.info("swipe between full-screen applications: \(isOn ? "on" : "not on, so swipes use the shortcuts", privacy: .public); found \(SpaceSwipeSetting.summary(of: found), privacy: .public)")
        }
        return isOn
    }

    nonisolated(unsafe) private static var hasLoggedSpaceSwipe = false
    private static let log = Logger(subsystem: "com.crissmoldovan.tactile", category: "dockswipe")
}

/// Whether "swipe between full-screen applications" is on, from the person's trackpad settings:
/// while it is off, the Dock can ignore a posted swipe, so the shortcut is used instead. Pure, so it can be tested; `LiveDockSwipeSurroundings` reads
/// the settings.
enum SpaceSwipeSetting {
    /// 2 in either means on: with three fingers, or with four.
    static let keys = ["TrackpadThreeFingerHorizSwipeGesture", "TrackpadFourFingerHorizSwipeGesture"]
    /// Where System Settings keeps them: the trackpad's domain, then the Bluetooth trackpad's.
    static let domains = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]

    /// `found`: for each of `domains`, the keys set there. On when a key is 2 in every domain that
    /// has it. Not on in every other case, which means the shortcut, which always works:
    /// - a key missing from every domain. A Mac that has never had a trackpad may have none, and if
    ///   the Dock then counts the gesture as off, it would ignore the swipe while the sender thought
    ///   it had posted one: neither the slide nor the shortcut;
    /// - the domains disagreeing on a key, on in one and off in another: which one the Dock reads
    ///   isn't known;
    /// - a value, anywhere, that isn't a number.
    static func isOn(foundIn found: [[String: Any]]) -> Bool {
        var on = false
        for key in keys {
            let values = found.compactMap { $0[key] }
            let numbers = values.compactMap { $0 as? Int }
            guard numbers.count == values.count else { return false }
            let says = Set(numbers.map { $0 == 2 })
            guard says.count <= 1 else { return false }
            if says.contains(true) { on = true }
        }
        return on
    }

    /// What was found, for the log: each domain's keys, with their values or "missing".
    static func summary(of found: [[String: Any]]) -> String {
        zip(domains, found).map { domain, values in
            "\(domain): " + keys.map { key in "\(key) \(values[key].map { "\($0)" } ?? "missing")" }
                .joined(separator: ", ")
        }.joined(separator: "; ")
    }
}
