import Foundation
import Observation

/// A model for previews and for rendering the interface without a device: the real desk, or one
/// of its variants, with commands applied the obvious way so a preview can be clicked through.
///
/// Set-up mode and the set-ups begun here are walked through by hand: `simulate(.touch(_:))` stands
/// for a touch on a touchscreen (in the overview an answer, in a flow the next tap),
/// `touchSetUp(_:)` for a tap of the flow running, which `problem` may refuse, and `simulate(_:)`
/// also unplugs or plugs in a display or a touchscreen; `tickSetUp()` ends a set-up, or the mode,
/// after two minutes without input. Tests call them one at a time on a clock they move; a preview can
/// call `playSetUp()`, which touches by itself on a timer.
@MainActor
@Observable
public final class PreviewModel: AppModel {

    /// The desk as surveyed on 2026-11-14, and the states the interface must show well.
    public enum Variant: String, CaseIterable, Sendable {
        /// The ILITEK driving on "HDMI"; the strip on "12.3FHD", one finger only; "Old panel"
        /// remembered and not connected.
        case desk
        /// First run: both touchscreens connected and neither paired. Set-up is offered for the
        /// ILITEK.
        case nothingPaired
        /// The desk without Accessibility access.
        case accessibilityMissing
        /// The desk with Tactile turned off.
        case tactileOff
        /// The desk with "HDMI" unplugged.
        case displayUnplugged
        /// Tactile off while "HDMI" is unplugged: the ILITEK is paired, and its status names no
        /// display.
        case tactileOffDisplayUnplugged
        /// Every warning at once.
        case allWarnings
        /// The desk with a second ILITEK-TP on a hub that reports no USB location: it can't be told
        /// apart from the first, and has no record.
        case identicalTwins
    }

    /// Whoever writes it, `steadySnapshot` follows (`snapshotChanged`).
    public internal(set) var snapshot: AppSnapshot {
        didSet { snapshotChanged() }
    }
    /// `snapshot` without the gesture tester's feed, set with it when that differs (`AppModel`).
    public private(set) var steadySnapshot: AppSnapshot
    /// How many times Copy Diagnostics was pressed; the preview copies nothing.
    public private(set) var diagnosticsCopied = 0
    /// How many times Open Login Items Settings… was pressed; the preview opens nothing.
    public private(set) var loginItemsSettingsOpened = 0

    @ObservationIgnored private var desk: PreviewDesk
    @ObservationIgnored private let clock: @MainActor () -> TimeInterval
    @ObservationIgnored private var player: Task<Void, Never>?

    /// `clock` is the host's uptime clock unless a test gives its own.
    public init(_ variant: Variant = .desk, clock: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        desk = PreviewDesk(variant)
        self.clock = clock
        let first = desk.snapshot()
        snapshot = first
        steadySnapshot = first.withoutTesterFeed
    }

    /// A desk set up by hand, for a state no variant has.
    init(desk: PreviewDesk, clock: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.desk = desk
        self.clock = clock
        let first = desk.snapshot()
        snapshot = first
        steadySnapshot = first.withoutTesterFeed
    }

    public func perform(_ command: AppCommand) {
        if command == .copyDiagnostics {
            diagnosticsCopied += 1
        }
        if command == .openLoginItemsSettings {
            loginItemsSettingsOpened += 1
        }
        desk.apply(command, at: clock())
        publish()
    }

    /// Ends a set-up, or set-up mode, after two minutes without a touch or a button.
    public func tickSetUp() {
        desk.tickSetUp(at: clock())
        publish()
    }

    /// A tap on the touchscreen whose flow runs: in the corners step, the next target, or `problem`
    /// refuses it.
    public func touchSetUp(_ problem: SetUpProblem? = nil) {
        desk.touchSetUp(at: clock(), problem: problem)
        publish()
    }

    /// What a hand or a cable does: a touch, or a display or touchscreen unplugged or plugged in.
    func simulate(_ happening: PreviewDesk.Happening) {
        desk.happen(happening, at: clock())
        publish()
    }

    /// The display being set up was turned in macOS mid-round: the corners start again.
    public func restartSetUpCorners() {
        desk.restartCorners()
        publish()
    }

    /// For previews: touches by itself in set-up mode, or a set-up, begun. Once a display is chosen
    /// it touches the first touchscreen not set up (else the first that can be), taps the four
    /// targets (the second one twice, the first time with a slide), and waits for the buttons
    /// everywhere else. Stopped by `stopPlaying()`.
    public func playSetUp() {
        player?.cancel()
        player = Task { [weak self] in
            var nextTouch: TimeInterval?
            var slid = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                self.tickSetUp()
                let now = self.clock()
                if case .waitingForTouch? = self.snapshot.setUpMode?.stage, self.snapshot.setUp == nil {
                    let lines = self.snapshot.setUpMode?.touchscreens ?? []
                    let answer = lines.first { $0.state == .notSetUp } ?? lines.first { $0.state != .cannotBeSetUp }
                    let at = nextTouch ?? now + 1.5
                    nextTouch = at
                    if now >= at, let answer {
                        self.simulate(.touch(answer.id))
                        nextTouch = nil
                    }
                    continue
                }
                switch self.snapshot.setUp?.step {
                case .corners(_, _, let index, _)?:
                    let at = nextTouch ?? now + 1.5
                    nextTouch = at
                    if now >= at {
                        if index == 1, !slid {
                            slid = true
                            self.touchSetUp(.moved)
                        } else {
                            self.touchSetUp()
                        }
                        nextTouch = nil
                    }
                default:
                    nextTouch = nil
                }
            }
        }
    }

    public func stopPlaying() {
        player?.cancel()
        player = nil
    }

    private func publish() {
        let next = desk.snapshot()
        if next != snapshot {
            snapshot = next
        }
    }

    /// After every write of `snapshot`: `steadySnapshot` follows it, when what it holds differs.
    private func snapshotChanged() {
        let steady = snapshot.withoutTesterFeed
        if steady != steadySnapshot {
            steadySnapshot = steady
        }
    }
}
