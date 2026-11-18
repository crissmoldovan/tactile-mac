// The model's clock: 60 ticks a second while a touch needs them, 10 while only a set-up does, kept
// from being slowed by App Nap.

import Foundation

/// Calls `tick` every `interval` seconds between `start` and `stop`. The model uses it while any
/// pipeline needs ticks (momentum, the double-tap wait, the silence watchdog), at `touchInterval`,
/// and while a set-up runs, at `setUpInterval` when nothing else needs it.
@MainActor
protocol ModelTicker: AnyObject {
    var isRunning: Bool { get }
    /// How often it ticks while running; nil while stopped.
    var interval: TimeInterval? { get }
    /// Starts calling `tick` every `interval` seconds. While already running at that interval, it
    /// does nothing; at another, it ticks at the new one from now.
    func start(every interval: TimeInterval, _ tick: @escaping @MainActor @Sendable () -> Void)
    /// Stops; does nothing while stopped.
    func stop()
}

enum TickRate {
    /// About 60 times a second: for a touch.
    static let touchInterval: TimeInterval = 1.0 / 60
    /// 10 times a second: for a set-up or set-up mode, whose time limits need the clock to move.
    static let setUpInterval: TimeInterval = 0.1
}

extension ModelTicker {
    /// Starts at the touch rate.
    func start(_ tick: @escaping @MainActor @Sendable () -> Void) {
        start(every: TickRate.touchInterval, tick)
    }
}

/// A timer on the main run loop in common modes (so ticks go on while a menu is open), and, while
/// it runs, an activity that keeps App Nap from slowing it: with no window open, App Nap may slow a
/// background app's timers.
@MainActor
final class LiveTicker: ModelTicker {
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private let beginActivity: () -> NSObjectProtocol
    private let endActivity: (NSObjectProtocol) -> Void

    /// `beginActivity` and `endActivity` are the system's, unless a test gives its own.
    init(
        beginActivity: @escaping () -> NSObjectProtocol = {
            ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical], reason: "Following a touch")
        },
        endActivity: @escaping (NSObjectProtocol) -> Void = { ProcessInfo.processInfo.endActivity($0) }
    ) {
        self.beginActivity = beginActivity
        self.endActivity = endActivity
    }

    var isRunning: Bool { timer != nil }
    var interval: TimeInterval? { timer?.timeInterval }

    func start(every interval: TimeInterval, _ tick: @escaping @MainActor @Sendable () -> Void) {
        if let timer {
            guard timer.timeInterval != interval else { return }
            timer.invalidate()
        } else {
            activity = beginActivity()
        }
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let activity { endActivity(activity) }
        activity = nil
    }
}
