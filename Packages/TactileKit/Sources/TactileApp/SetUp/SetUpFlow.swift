// Setting a touchscreen up by touching it: which way round its glass is fitted on the display
// chosen for it, and how big it is. A pure state machine, fed that touchscreen's frames and the time.

import CoreGraphics
import Foundation
import TactileReading
import TactileScreens

/// One run of the set-up flow for one touchscreen, from its first screen to Done or its end.
///
/// It has no window, no device and no clock of its own. The model feeds it the touchscreen's
/// frames (and no other touchscreen's), ticks it, passes on the person's choices and tells it when
/// the displays change; it answers each with an `Event`, and its `snapshot` is what the interface
/// draws. Every time is on the host's uptime clock, the clock frames are timed on. Nothing is
/// stored until the outcome of `done()`, and only the caller stores it: set-up never stores a guess
/// and never half-applies.
///
/// **The steps.** `.full` is corners, size and check, on its one candidate: the display set-up mode
/// chose for it (`SetUpSession`: which display comes from a click, which touchscreen from a touch;
/// no timer decides either). `.calibrate` is corners and check, on the display the touchscreen is
/// paired with; `.test` is the check alone, with the mapping it has.
///
/// 1. **Corners.** `Calibration.targets`, in order, one at a time. A *landing* is a frame with a
///    contact after a frame with none. A *tap* is one contact that
///    lands and lifts having moved at most `tapTravelMM` on the glass from where it landed; its
///    glass point is the mean of its positions. Two contacts at once (or another contact ID taking
///    over) refuses the tap with `tooManyFingers`, a slide with `moved`, and the same target is
///    shown again. After the fourth tap, each target is taken from the picture as the person sees
///    it to the display's own unrotated picture (`TouchMapping.nativePoint(forDisplay:)` on an
///    as-fitted, whole-glass mapping, through the display it mirrors when it mirrors one), and
///    `Calibration.fit` fits the glass to them. A fit it refuses (`tapsDidNotFit`, `ambiguous`), or
///    one that leaves a tap more than `tapReachMM` from where its target falls under it, or the taps'
///    root-mean-square distance from there above `fitSpreadMM` (`tapsDidNotFit`), starts the
///    corners again. So one wild tap is never averaged in.
/// 2. **Size** (`.full` only). Offers the display's reported diagonal and the touchscreen's, each
///    only when `SurfaceSize`'s density rule finds it plausible on that display, and the
///    touchscreen's only when its glass has the picture's shape, within `shapeTolerance`; and takes
///    a number of inches within `SurfaceSize.plausibleDiagonals` or "as reported" (`nil`).
/// 3. **Check.** `checkMapping` is the mapping touches are shown with: the fitted one, or for
///    `.test` the stored one. The flow only waits. `redo()` goes back to the corners (not for
///    `.test`); `done()` finishes with the outcome (`nil` for `.test`: nothing changed). Neither
///    does anything until the check has been on show for `reactionTime`: a second press of Return
///    on the size card lands on the check, and the check is the only guard against a wrong display
///    or a symmetric tap order being stored.
///
/// **What each round measured.** After each round of the corners, accepted or refused,
/// `lastCornersReport` says what it measured, for tuning `tapReachMM`, `fitSpreadMM` and
/// `tapTravelMM` from real taps: see `CornersReport`, and its `logLine`, which the model logs.
///
/// `cancel()`, `idleTimeout` without input in any step, and the display in use going away all
/// finish with `nil`: store nothing. *Input* is a landing, a tap, a
/// command that changes the step (`confirmSize` taken, `redo`), and in the check step a contact
/// that moves further than a tap may (a hand resting on the glass is not input). So a forgotten
/// flow doesn't keep a touchscreen out of use, as long as it is ticked.
///
/// **The millimetres of the glass.** The corners' limits are distances on the glass. Its size is
/// what the touchscreen reports, in its own axes, when that is plausible on the display by
/// `SurfaceSize`'s density rule; a report that isn't (a wrong unit exponent in a descriptor makes
/// one ten times too large) would refuse every honest tap, and is passed over. Then it is the
/// display's picture laid along the glass by the fit: the confirmed diagonal (for `.calibrate`) or
/// the display's own plausible report, turned back from the macOS rotation, divided by the
/// alignment's extent, and turned back from the fit's quarter turns. When neither is known, a tap's
/// travel is `tapTravel` of the glass, and the fit is held to `Calibration`'s own limits alone.
///
/// A tap's travel is judged before there is a fit, so which way round the glass lies isn't known:
/// the touchscreen's report counts when it is plausible either way round, and the display's
/// picture is taken either way round, the reading that makes the travel shorter.
///
/// **Too soon after a change.** A person can't react in under `reactionTime`, so a landing that
/// soon after what the flow shows changed was meant for what it showed before, and is ignored
/// with every finger of it, until the glass clears. A change is: the flow starting; the next
/// target, or the first again. (A refused tap is not one: the target stays where it was.) A landing
/// timed before the latest change, or not timed at all, is ignored the same way, so a frame that
/// arrives late is never taken for what was shown after it.
///
/// **The start.** Every landing in the first `startQuiet` after the flow starts is ignored, so a
/// finger already resting on the glass is not a touch, even on a panel that says nothing while a
/// finger rests. If the model knows fingers are down when it starts a flow, it should also hand the
/// flow their latest frame straight away: timed before the start, it is ignored as a landing, and
/// so are those fingers until they lift.
///
/// **A lift that never comes.** The glass is clear only after a frame with no contacts. If a
/// panel's lift report is lost, the next touch is taken for the same fingers and ignored, and the
/// one after it counts: one touch lost, never a touch made up.
///
/// **A change with no time.** `confirmSize`, `redo` and `done` are given no time. A step they
/// change is taken to have changed at the next frame or tick the flow is given (timed no earlier
/// than the latest), and every landing until then, and within `reactionTime` after, is ignored. The
/// model should tick the flow about ten times a second in every step: every step's `idleTimeout`
/// is seen by the ticks.
///
/// **Hostile input.** Times are taken as they come, but the flow's clock never goes back: a frame
/// or tick earlier than the latest is not a later moment. Positions outside 0…1 are taken at the
/// glass's edge, as the reader clamps them; a position that isn't a number spoils the touch it is
/// part of, silently. Once the flow has finished, every call returns the same `.finished` and
/// changes nothing. Nothing traps, and every number in the snapshot and the outcome is finite.
///
/// A value, cheap to copy: the model holds it.
public struct SetUpFlow: Equatable, Sendable {

    /// What a flow starts from. The model fills it.
    public struct Start: Equatable, Sendable {
        public var touchscreen: TouchscreenID
        public var touchscreenName: String
        public var purpose: SetUpPurpose
        /// For `.full`: the display set-up mode chose, alone. For the others: its own display, alone.
        public var candidates: [DisplayFacts]
        /// Every connected display: where a candidate that mirrors another finds it.
        public var allDisplays: [DisplayFacts]
        /// The size of its glass as the touchscreen itself reports it, in millimetres, in the
        /// glass's own axes; `nil` when it reports none.
        public var reportedSizeMM: CGSize?
        /// Its pairing now. `.calibrate` and `.test` need it: their display is this pairing's.
        public var current: Pairing?
        /// Its diagonal override now, in inches; `nil` for as reported.
        public var currentDiagonal: Double?

        public init(
            touchscreen: TouchscreenID, touchscreenName: String, purpose: SetUpPurpose, candidates: [DisplayFacts],
            allDisplays: [DisplayFacts], reportedSizeMM: CGSize?, current: Pairing?, currentDiagonal: Double?
        ) {
            self.touchscreen = touchscreen
            self.touchscreenName = touchscreenName
            self.purpose = purpose
            self.candidates = candidates
            self.allDisplays = allDisplays
            self.reportedSizeMM = reportedSizeMM
            self.current = current
            self.currentDiagonal = currentDiagonal
        }
    }

    /// What Done gives, for the caller to store in one change.
    public struct Outcome: Equatable, Sendable {
        /// The display: for `.full` the one chosen for it, or for `.calibrate` the current
        /// pairing's, as it was stored.
        public var display: DisplayIdentity
        public var orientation: Orientation
        public var alignment: GlassAlignment
        /// The diagonal override, in inches: as confirmed in the size step, or for `.calibrate` the
        /// current one, unchanged. `nil` for as reported.
        public var diagonalInches: Double?

        public init(
            display: DisplayIdentity, orientation: Orientation, alignment: GlassAlignment, diagonalInches: Double?
        ) {
            self.display = display
            self.orientation = orientation
            self.alignment = alignment
            self.diagonalInches = diagonalInches
        }
    }

    public enum Event: Equatable, Sendable {
        case stillRunning
        /// `nil`: cancelled, timed out, the display gone, or a test: store nothing.
        case finished(Outcome?)
    }

    /// What one round of the corners measured, accepted or refused: kept after it in
    /// `lastCornersReport`, and logged by the model as `logLine`, so that the corners' limits
    /// (`tapReachMM`, `fitSpreadMM`, `tapTravelMM`) can be tuned from real taps.
    public struct CornersReport: Equatable, Sendable {
        /// Where a size came from.
        public enum Source: String, Equatable, Sendable {
            /// What the touchscreen reports, when it is plausible on the display.
            case reported
            /// The display's picture: its confirmed diagonal (for `.calibrate`) or its own report.
            /// Before a fit, a tap's travel is its shorter reading.
            case display
            /// No size: shares of the glass.
            case shares
        }

        public enum Verdict: Equatable, Sendable {
            case accepted
            /// The corners start again, showing this problem.
            case refused(SetUpProblem)
        }

        public var touchscreen: TouchscreenID
        public var touchscreenName: String
        /// Which round of this flow it was: 1 for the first.
        public var round: Int
        public var verdict: Verdict
        /// The orientation `Calibration` fitted; `nil` when it refused the taps itself.
        public var orientation: Orientation?
        /// The size of the glass the distances from the fit are measured on, in millimetres, in the
        /// glass's own axes; `nil` for shares of the glass, and when there was no fit.
        public var glassMM: CGSize?
        /// Where `glassMM` came from, `.shares` when nothing gave a size; `nil` when there was no fit.
        public var glassSource: Source?
        /// Each tap's distance from where its target falls under the fit, in the order the targets
        /// were shown: millimetres, or shares of the glass with `.shares`; `nil` when there was no fit.
        public var fromFit: [Double]?
        /// Their root mean square, in the same units; `nil` when there was no fit.
        public var spread: Double?
        /// Each tap's travel, the farthest it moved from where it landed, as the limit judged it:
        /// millimetres, or shares of the glass with `.shares`.
        public var travel: [Double]
        /// Where the size `travel` is measured on came from.
        public var travelSource: Source
        /// For each tap refused as moved during the round, the travel it was refused at: it moved at
        /// least that far. In `travel`'s units.
        public var moved: [Double]

        public init(
            touchscreen: TouchscreenID, touchscreenName: String, round: Int, verdict: Verdict,
            orientation: Orientation?, glassMM: CGSize?, glassSource: Source?, fromFit: [Double]?, spread: Double?,
            travel: [Double], travelSource: Source, moved: [Double]
        ) {
            self.touchscreen = touchscreen
            self.touchscreenName = touchscreenName
            self.round = round
            self.verdict = verdict
            self.orientation = orientation
            self.glassMM = glassMM
            self.glassSource = glassSource
            self.fromFit = fromFit
            self.spread = spread
            self.travel = travel
            self.travelSource = travelSource
            self.moved = moved
        }

        /// The report as one line, for the log and the tuning that reads it:
        ///
        ///     Set-up corners: <name> [<touchscreen ID>] round <n>: <verdict>; orientation <orientation>;
        ///     glass <glass>; taps <distances> from fit; spread <spread>; travel <travels> (<source>);
        ///     moved <moved>
        ///
        /// on one line, the fields always in this order, separated by `; `:
        /// - `<verdict>`: `accepted`, or `refused (<problem>)` with the `SetUpProblem`'s raw value.
        /// - `<orientation>`: `0°`, `90°`, `180°` or `270°`, then ` flipped` when it is; `none` when
        ///   `Calibration` refused the taps itself.
        /// - `<glass>`: `<width> × <height> mm (reported)` or `(display)`; `unknown (shares of the
        ///   glass)`; or `none` when there was no fit.
        /// - `<distances>`, `<travels>`, `<moved>`: numbers separated by `, `, then their unit, `mm` or
        ///   `of the glass`; or `none`. `<spread>`: one number and its unit, or `none`.
        /// - `<source>`: `reported`, `display` or `shares`, for the travel.
        ///
        /// Millimetres to 0.1, shares of the glass to 0.0001. The name may hold anything: the
        /// touchscreen's ID follows it in `[ ]`, then ` round `.
        public var logLine: String {
            let fitInShares = glassSource == .shares
            let travelInShares = travelSource == .shares
            func number(_ value: Double, inShares: Bool) -> String {
                String(format: inShares ? "%.4f" : "%.1f", value)
            }
            func list(_ values: [Double]?, inShares: Bool) -> String {
                guard let values, !values.isEmpty else { return "none" }
                let unit = inShares ? "of the glass" : "mm"
                return values.map { number($0, inShares: inShares) }.joined(separator: ", ") + " " + unit
            }
            let verdictText: String
            switch verdict {
            case .accepted: verdictText = "accepted"
            case .refused(let problem): verdictText = "refused (\(problem.rawValue))"
            }
            let orientationText = orientation.map {
                "\($0.quarterTurns * 90)°" + ($0.isFlipped ? " flipped" : "")
            } ?? "none"
            let glassText: String
            switch (glassSource, glassMM) {
            case (.shares?, _):
                glassText = "unknown (shares of the glass)"
            case (let source?, let size?):
                glassText = "\(number(Double(size.width), inShares: false)) × "
                    + "\(number(Double(size.height), inShares: false)) mm (\(source.rawValue))"
            default:
                glassText = "none"
            }
            let spreadText = spread.map { list([$0], inShares: fitInShares) } ?? "none"
            return "Set-up corners: \(touchscreenName) [\(touchscreen.rawValue)] round \(round): \(verdictText); "
                + "orientation \(orientationText); glass \(glassText); "
                + "taps \(list(fromFit, inShares: fitInShares)) from fit; spread \(spreadText); "
                + "travel \(list(travel, inShares: travelInShares)) (\(travelSource.rawValue)); "
                + "moved \(list(moved, inShares: travelInShares))"
        }
    }

    // MARK: - Constants

    /// How soon after a change a landing is still taken as meant for what was shown before, in
    /// seconds. `SetUpSession` holds its answers to it too.
    public static let reactionTime: TimeInterval = 0.4
    /// How long after the flow starts every landing is ignored, in seconds. `SetUpSession` holds
    /// its answers to it too, from when the mode begins.
    public static let startQuiet: TimeInterval = 1
    /// How long any step waits without input before the flow ends by itself, in seconds; and how
    /// long set-up mode waits without input in any stage before it ends.
    public static let idleTimeout: TimeInterval = 120
    /// How far a tap's finger may move from where it landed, in millimetres on the glass.
    public static let tapTravelMM: Double = 5
    /// How far a tap's finger may move from where it landed when neither the touchscreen nor the
    /// display gives the glass a size, as a share of the glass.
    public static let tapTravel: CGFloat = 0.03
    /// How far each tap may be from where its target falls under the fit, in millimetres on the
    /// glass, before the round is refused: one wild tap must not be averaged in. To be tuned from
    /// real taps.
    public static let tapReachMM: Double = 8
    /// How far the taps may be from where their targets fall under the fit, as a root mean square,
    /// in millimetres on the glass, before the round is refused. To be tuned from real taps.
    public static let fitSpreadMM: Double = 6
    /// How far the shape of the glass the touchscreen reports may be from the shape of the
    /// display's picture, each its longer side over its shorter, for the size step to offer the
    /// touchscreen's report: the larger over the smaller at most 1 + this.
    public static let shapeTolerance: Double = 0.15

    /// The targets the corners step offers, in order: `Calibration.targets`, every one a point of
    /// the picture (0…1 on each axis). One that isn't would be a programming error, and is never
    /// offered: without all four, no flow that needs the corners starts.
    static let targets: [CGPoint] = Calibration.targets.filter { (0...1).contains($0.x) && (0...1).contains($0.y) }

    /// Whether the corners can be offered: every one of `Calibration.targets`, and at least the four
    /// a fit needs.
    static var canCalibrate: Bool {
        targets.count == Calibration.targets.count && targets.count >= 4
    }

    // MARK: - State

    private let touchscreen: TouchscreenID
    private let touchscreenName: String
    private let purpose: SetUpPurpose
    private let reportedSizeMM: CGSize?
    private let current: Pairing?
    private let currentDiagonal: Double?
    /// Every display, as last told: where a display that mirrors another finds it.
    private var displays: [DisplayFacts]
    private var step: Step
    /// What is on the glass, as far as the flow is concerned.
    private var glass: Glass = .clear
    /// When the flow started: a landing before `startedAt + startQuiet` is ignored.
    private let startedAt: TimeInterval
    /// The latest time the flow has been given. It never goes back.
    private var now: TimeInterval
    /// When what the flow shows last changed: a landing before `changedAt + reactionTime` is ignored.
    private var changedAt: TimeInterval
    /// Whether a command changed the step since the last frame or tick: the change is then timed by
    /// the next one, and every landing until then is ignored.
    private var changePending = false
    /// When the flow last had input: `idleTimeout` runs from it.
    private var lastInput: TimeInterval
    /// In the check step, the contact followed for input, where it was when it last was input.
    private var resting: Resting?
    /// What the last round of the corners measured.
    private var report: CornersReport?
    /// How many rounds of the corners have ended.
    private var rounds = 0
    /// The travel of each tap of the round in progress so far.
    private var roundTravel: [Double] = []
    /// The travel each tap refused as moved in the round in progress was refused at.
    private var roundMoved: [Double] = []
    /// The size the person confirmed in this flow, once they have.
    private var answer: SizeAnswer?
    /// How the flow finished, once it has.
    private var ending: Event?

    private enum Step: Equatable, Sendable {
        /// The display, and the taps so far: as many as the index of the target shown.
        case corners(DisplayFacts, taps: [CalibrationTap], problem: SetUpProblem?)
        case size(DisplayFacts, Fitted)
        /// The mapping touches are shown with; its display is the display in use.
        case check(TouchMapping)
    }

    /// How the glass is fitted: what a fit, or a stored pairing, says.
    private struct Fitted: Equatable, Sendable {
        var orientation: Orientation
        var alignment: GlassAlignment

        static let asFitted = Fitted(orientation: .asFitted, alignment: .wholeGlass)
    }

    private enum Glass: Equatable, Sendable {
        /// Nothing down, as far as the flow knows: the next frame with a contact is a landing.
        case clear
        /// Fingers down that are no touch the flow acts on; it waits for the glass to clear.
        case ignored
        /// One finger down in the corners step, that may be a tap.
        case tapping(Tap)
        /// The touch in the corners step is no tap, for this reason, which is shown when it lifts.
        case refused(SetUpProblem)
    }

    /// The contact followed in the check step, and where it was when it last counted as input.
    private struct Resting: Equatable, Sendable {
        let id: Int
        let at: CGPoint
    }

    /// One finger, from its landing, that may be a tap.
    private struct Tap: Equatable, Sendable {
        let id: Int
        /// Where it landed, on the glass, within 0…1.
        let landing: CGPoint
        /// Every position so far, added up, and how many: each within 0…1, so no sum overflows.
        var sum: CGPoint
        var count: Int
        /// The farthest it has moved from where it landed, as its travel is judged.
        var travel: Double = 0

        init(id: Int, at point: CGPoint) {
            self.id = id
            landing = point
            sum = point
            count = 1
        }

        mutating func add(_ point: CGPoint) {
            sum.x += point.x
            sum.y += point.y
            count += 1
        }

        var mean: CGPoint { CGPoint(x: sum.x / CGFloat(count), y: sum.y / CGFloat(count)) }
    }

    private enum SizeAnswer: Equatable, Sendable {
        case asReported
        case inches(Double)

        var inches: Double? {
            if case .inches(let inches) = self { return inches }
            return nil
        }
    }

    // MARK: - Starting

    /// The flow at its first step, at `time`; `nil` when it can't start:
    /// - there isn't exactly one candidate, or it isn't usable: the built-in display; a display
    ///   with a number that isn't finite in its facts; a display with nowhere for a touch to land
    ///   (no `TouchMapping`, or one that mirrors a display not in `allDisplays` exactly once);
    /// - `.calibrate` or `.test` whose one candidate isn't `current`'s display: the display with its
    ///   stored UUID, when one in `allDisplays` has it; otherwise one with its UUID or its
    ///   fingerprint, as `DisplayMatcher` would match it;
    /// - `time` isn't finite.
    ///
    /// What it keeps is sound, so that a flow always equals itself: a display with a number that
    /// isn't finite in its frame, native size or reported size is no display the flow uses, in
    /// `candidates` or `allDisplays`; a diagonal that isn't finite is none, as the settings store
    /// it; and a reported glass size without two finite sides above zero is none.
    public init?(_ start: Start, at time: TimeInterval) {
        guard time.isFinite, start.candidates.count == 1 else { return nil }
        let allDisplays = start.allDisplays.filter(Self.isSound)
        let candidates = Self.usable(start.candidates.filter(Self.isSound), among: allDisplays)
        switch start.purpose {
        case .full:
            guard candidates.count == 1, Self.canCalibrate else { return nil }
            step = .corners(candidates[0], taps: [], problem: nil)
        case .calibrate:
            guard Self.canCalibrate,
                let display = Self.ownDisplay(candidates, current: start.current, among: start.allDisplays)
            else { return nil }
            step = .corners(display, taps: [], problem: nil)
        case .test:
            guard let current = start.current,
                let display = Self.ownDisplay(candidates, current: current, among: start.allDisplays),
                let mapping = Self.mapping(Fitted(orientation: current.orientation, alignment: current.alignment),
                                           on: display, among: allDisplays)
            else { return nil }
            step = .check(mapping)
        }
        touchscreen = start.touchscreen
        touchscreenName = start.touchscreenName
        purpose = start.purpose
        reportedSizeMM = start.reportedSizeMM.flatMap { Self.isUsable($0) ? $0 : nil }
        current = start.current
        // As the settings store it: one that isn't finite is none.
        currentDiagonal = start.currentDiagonal.flatMap { $0.isFinite ? $0 : nil }
        displays = allDisplays
        startedAt = time
        now = time
        changedAt = time
        lastInput = time
    }

    // MARK: - What the interface draws

    public var snapshot: SetUpSnapshot {
        SetUpSnapshot(touchscreen: touchscreen, touchscreenName: touchscreenName, purpose: purpose, step: shownStep)
    }

    /// What the last round of the corners measured, accepted or refused; `nil` before the first
    /// round has ended. Kept until the next round ends.
    public var lastCornersReport: CornersReport? { report }

    /// The mapping the check step shows touches with; `nil` before the check step, and once the
    /// flow has finished.
    public var checkMapping: TouchMapping? {
        guard ending == nil, case .check(let mapping) = step else { return nil }
        return mapping
    }

    /// When the flow last had input, on the host's clock: `idleTimeout` runs from it. `SetUpSession`
    /// reads it, so that set-up mode's own time limit counts the flow's input too.
    var lastInputAt: TimeInterval { lastInput }

    /// Whether a `.full` flow could start on `display` alone, `displays` being every connected
    /// display: it is sound, not built in, the only display in `displays` with its ID, and a touch
    /// on it has somewhere to land.
    static func canStartFull(on display: DisplayFacts, among displays: [DisplayFacts]) -> Bool {
        guard canCalibrate, isSound(display), displays.filter({ $0.displayID == display.displayID }).count == 1
        else { return false }
        return usable([display], among: displays.filter(isSound)).count == 1
    }

    /// Set-up mode's candidates among `displays`, every connected display, in their order: each one
    /// a `.full` flow could start on (`canStartFull`) that is alone with its picture among them. Two
    /// that show the same picture (one mirrors the other, or both mirror a third) are both left out:
    /// a click on the picture they share can't say which of them the glass is on, and Done would
    /// store a guess. A display mirroring one that is no candidate (the built-in display) is alone
    /// with its picture, and stays.
    static func setUpModeCandidates(among displays: [DisplayFacts]) -> [DisplayFacts] {
        let possible = displays.filter { canStartFull(on: $0, among: displays) }
        let showing = possible.reduce(into: [UInt32: Int]()) { counts, display in
            counts[picture(of: display), default: 0] += 1
        }
        return possible.filter { showing[picture(of: $0)] == 1 }
    }

    /// The display whose picture `display` shows: the one it mirrors, else itself.
    private static func picture(of display: DisplayFacts) -> UInt32 {
        guard let original = display.mirrors, original != display.displayID else { return display.displayID }
        return original
    }

    private var shownStep: SetUpStep {
        switch step {
        case .corners(let display, let taps, let problem):
            let index = min(taps.count, Self.targets.count - 1)
            return .corners(display: display.displayID, target: Self.targets[index], index: index, problem: problem)
        case .size(let display, let fitted):
            return .size(
                display: display.displayID,
                displayReports: Self.offerable(Self.plausibleDiagonal(display.sizeMM, on: display)),
                touchscreenReports: Self.offerable(touchscreenDiagonal(on: display, fitted: fitted)),
                current: shownDiagonal)
        case .check(let mapping):
            return .check(display: mapping.display.displayID)
        }
    }

    /// The touchscreen's own report, when it is plausible on `display` and has the shape of its
    /// picture: its glass size laid along the display's frame. The glass reports in its own axes; a
    /// quarter turn of the fit, or of the display in macOS, lays its width along the frame's height,
    /// and both together lay it back. The shapes are compared each as its longer side over its
    /// shorter, so which way round doesn't matter: within `shapeTolerance`, or a glass of another
    /// shape (the ILITEK's 16:9 on the 8:3 "12.3FHD") would be offered as this display's size.
    private func touchscreenDiagonal(on display: DisplayFacts, fitted: Fitted) -> Double? {
        guard let glass = reportedSizeMM, Self.isUsable(display.frame.size) else { return nil }
        let shapes = [Self.longOverShort(glass), Self.longOverShort(display.frame.size)]
        guard let wider = shapes.max(), let narrower = shapes.min(), wider / narrower <= 1 + Self.shapeTolerance
        else { return nil }
        let turns = fitted.orientation.quarterTurns + Self.quarterTurns(display.rotation)
        let alongFrame = turns % 2 == 1 ? CGSize(width: glass.height, height: glass.width) : glass
        return Self.plausibleDiagonal(alongFrame, on: display)
    }

    /// The override the size step shows: the one confirmed earlier in this flow (after a redo), else
    /// the one in force now, when `SurfaceSize` would use it.
    private var shownDiagonal: Double? {
        switch answer {
        case .inches(let inches): return inches
        case .asReported: return nil
        case nil: return Self.offerable(currentDiagonal)
        }
    }

    /// `inches`, when the size step could take it back from the person: within
    /// `SurfaceSize.plausibleDiagonals`. A display can report a plausible density and a diagonal
    /// outside it, and a choice that `confirmSize` would refuse must not be offered.
    private static func offerable(_ inches: Double?) -> Double? {
        guard let inches, SurfaceSize.plausibleDiagonals.contains(inches) else { return nil }
        return inches
    }

    // MARK: - What the model feeds it

    /// A frame of the touchscreen being set up.
    public mutating func handle(_ frame: ContactFrame) -> Event {
        if let ending { return ending }
        advance(to: frame.time)
        if let ending { return ending }
        if frame.contacts.isEmpty {
            glassCleared()
        } else {
            switch glass {
            case .clear: landed(frame)
            case .ignored, .refused: followResting(frame.contacts)
            case .tapping(let tap): glass = following(tap, frame.contacts)
            }
        }
        return ending ?? .stillRunning
    }

    /// The time passing. Needed about ten times a second in every step: every step ends itself after
    /// `idleTimeout` without input; and a change a command made is timed by it.
    public mutating func tick(at time: TimeInterval) -> Event {
        if let ending { return ending }
        advance(to: time)
        return ending ?? .stillRunning
    }

    /// The person's answer in the size step: inches, or `nil` for as reported. A number that isn't
    /// within `SurfaceSize.plausibleDiagonals` is refused, and the step stays. Anywhere else,
    /// nothing.
    public mutating func confirmSize(inches: Double?) -> Event {
        if let ending { return ending }
        guard case .size(let display, let fitted) = step else { return .stillRunning }
        if let inches, !SurfaceSize.plausibleDiagonals.contains(inches) { return .stillRunning }
        answer = inches.map(SizeAnswer.inches) ?? .asReported
        enterCheck(on: display, fitted)
        changePending = true
        return ending ?? .stillRunning
    }

    /// From the check step, back to the first corner, the taps forgotten. Nothing for `.test`,
    /// anywhere but the check step, or before the check has been seen (see `checkHasBeenSeen`).
    public mutating func redo() -> Event {
        if let ending { return ending }
        guard purpose != .test, case .check(let mapping) = step, checkHasBeenSeen else { return .stillRunning }
        step = .corners(mapping.display, taps: [], problem: nil)
        resting = nil
        changePending = true
        return .stillRunning
    }

    /// From the check step, the end: the outcome for `.full` and `.calibrate`, `nil` for `.test`.
    /// Anywhere but the check step, or before the check has been seen, nothing.
    public mutating func done() -> Event {
        if let ending { return ending }
        guard case .check(let mapping) = step, checkHasBeenSeen else { return .stillRunning }
        switch purpose {
        case .test:
            return finish(nil)
        case .calibrate:
            return finish(Outcome(
                display: current?.display ?? DisplayIdentity(mapping.display), orientation: mapping.orientation,
                alignment: mapping.alignment, diagonalInches: currentDiagonal))
        case .full:
            let diagonal: Double?
            switch answer {
            case .inches(let inches): diagonal = inches
            case .asReported: diagonal = nil
            case nil: diagonal = currentDiagonal  // never: the check step of `.full` follows the size step
            }
            return finish(Outcome(
                display: DisplayIdentity(mapping.display), orientation: mapping.orientation,
                alignment: mapping.alignment, diagonalInches: diagonal))
        }
    }

    /// Whether the check has been on show long enough for Done or Redo to be meant for it: the
    /// change to it is no longer pending, and `reactionTime` has passed since it appeared, by the
    /// latest time the flow has been given. So a second press of Return on the size card, or Return
    /// held, can't skip the check. (The model ticks the flow at the moment of every command.)
    private var checkHasBeenSeen: Bool {
        !changePending && now >= changedAt + Self.reactionTime
    }

    /// Whether the flow shows the check and would ignore a Done or Redo now as too soon after it
    /// appeared (see `checkHasBeenSeen`), by the latest time it has been given. The model reads it
    /// at a command's moment, so that a Done that came too soon is logged as ignored rather than
    /// read like a hang.
    public var isCheckTooRecent: Bool {
        guard case .check = step else { return false }
        return !checkHasBeenSeen
    }

    /// The end, storing nothing.
    public mutating func cancel() -> Event {
        if let ending { return ending }
        return finish(nil)
    }

    /// The displays changed: `connected` is every connected display now. Ends the flow if the
    /// display in use has gone.
    ///
    /// A display has gone when no display in `connected` has its ID and its identity (UUID and
    /// fingerprint) exactly once, or it has nowhere for a touch to land now. A display holding a
    /// number that isn't finite is left out of `connected`, as `init` leaves it out.
    /// - Corners: if where the targets fall on the display's own picture moved (it was turned in
    ///   macOS, or started or stopped mirroring), the taps so far were for another picture: the
    ///   corners start again, as a change, and a tap in progress is no tap. Otherwise the taps stay.
    /// - Size and check: the fit stays; the check maps onto the display as it is now.
    public mutating func displaysChanged(_ connected: [DisplayFacts], at time: TimeInterval) -> Event {
        if let ending { return ending }
        advance(to: time)
        if let ending { return ending }
        let before = displays
        displays = connected.filter(Self.isSound)
        switch step {
        case .corners(let display, let taps, let problem):
            guard let present = stillHere(display), let targets = Self.nativeTargets(on: present, among: displays)
            else { return finish(nil) }
            if targets == Self.nativeTargets(on: display, among: before) {
                step = .corners(present, taps: taps, problem: problem)
            } else {
                step = .corners(present, taps: [], problem: nil)
                changedAt = now
                roundTravel = []
                roundMoved = []
                if glass != .clear { glass = .ignored }
            }
        case .size(let display, let fitted):
            guard let present = stillHere(display) else { return finish(nil) }
            step = .size(present, fitted)
        case .check(let mapping):
            let fitted = Fitted(orientation: mapping.orientation, alignment: mapping.alignment)
            guard let present = stillHere(mapping.display),
                let remapped = Self.mapping(fitted, on: present, among: displays)
            else { return finish(nil) }
            step = .check(remapped)
        }
        return .stillRunning
    }

    // MARK: - Private: time

    /// Brings the clock to `time`, unless it is earlier than the latest or isn't a time. A change a
    /// command made is timed now, and is input. Then: the end, after `idleTimeout` without input.
    private mutating func advance(to time: TimeInterval) {
        guard time.isFinite, time >= now else { return }
        if changePending {
            changePending = false
            changedAt = time
            lastInput = time
        }
        now = time
        if now - lastInput >= Self.idleTimeout {
            finish(nil)
        }
    }

    // MARK: - Private: touches

    /// A frame with contacts after one with none: input, whatever comes of it.
    private mutating func landed(_ frame: ContactFrame) {
        glass = .ignored
        lastInput = now
        // Not a number fails these too.
        let isTouch = !changePending && frame.time >= changedAt + Self.reactionTime
            && frame.time >= startedAt + Self.startQuiet
        switch step {
        case .corners:
            guard isTouch else { return }
            guard frame.contacts.count == 1 else {
                glass = .refused(.tooManyFingers)
                return
            }
            if let point = Self.glassPoint(frame.contacts[0].position) {
                glass = .tapping(Tap(id: frame.contacts[0].id, at: point))
            }
        case .size:
            break
        case .check:
            followResting(frame.contacts, landing: true)
        }
    }

    /// In the check step, a frame of a touch: input when the contact followed has moved further
    /// than a tap may since it last was, or, at a landing, the touch itself. A hand left resting
    /// on the glass is not input. When the contact followed is gone, the frame's first one is
    /// followed from where it is, which is not input either.
    private mutating func followResting(_ contacts: [Contact], landing: Bool = false) {
        guard case .check(let mapping) = step, let first = contacts.first else { return }
        if !landing, let resting, let same = contacts.first(where: { $0.id == resting.id }) {
            guard let point = Self.glassPoint(same.position),
                !isWithinTravel(point, of: resting.at, on: mapping.display)
            else { return }
            lastInput = now
            self.resting = Resting(id: same.id, at: point)
            return
        }
        resting = Self.glassPoint(first.position).map { Resting(id: first.id, at: $0) }
    }

    /// The glass of a tap in progress after `contacts`, a frame with at least one. A tap refused as
    /// moved leaves its travel for the round's report.
    private mutating func following(_ tap: Tap, _ contacts: [Contact]) -> Glass {
        guard contacts.count == 1, contacts[0].id == tap.id else { return .refused(.tooManyFingers) }
        guard let point = Self.glassPoint(contacts[0].position) else { return .ignored }
        guard case .corners(let display, _, _) = step else { return .refused(.moved) }
        let travel = self.travel(from: tap.landing, to: point, on: display)
        guard travel <= travelLimit(on: display) else {
            roundMoved.append(travel)
            return .refused(.moved)
        }
        var tap = tap
        tap.add(point)
        tap.travel = max(tap.travel, travel)
        return .tapping(tap)
    }

    /// Whether `point` is within a tap's travel of `landing` on the glass over `display`.
    private func isWithinTravel(_ point: CGPoint, of landing: CGPoint, on display: DisplayFacts) -> Bool {
        travel(from: landing, to: point, on: display) <= travelLimit(on: display)
    }

    /// How far `point` is from `landing`, as a tap's travel is judged on the glass over `display`:
    /// in millimetres on the sizes the glass may have before there is a fit (the shorter distance
    /// of them), else in shares of the glass.
    private func travel(from landing: CGPoint, to point: CGPoint, on display: DisplayFacts) -> Double {
        let dx = Double(point.x - landing.x), dy = Double(point.y - landing.y)
        let sizes = glassSizesBeforeAFit(on: display).sizes
        guard !sizes.isEmpty else { return hypot(dx, dy) }
        return sizes.map { hypot(dx * Double($0.width), dy * Double($0.height)) }.min() ?? hypot(dx, dy)
    }

    /// The most a tap may travel on the glass over `display`: `tapTravelMM`, or `tapTravel` of the
    /// glass when nothing gives it a size.
    private func travelLimit(on display: DisplayFacts) -> Double {
        glassSizesBeforeAFit(on: display).sizes.isEmpty ? Double(Self.tapTravel) : Self.tapTravelMM
    }

    /// The sizes the glass over `display` may have, in its own axes, before a fit says which way
    /// round it lies, and where they came from: the touchscreen's report, when it is plausible on
    /// `display` either way round; else the display's picture, either way round; else none.
    private func glassSizesBeforeAFit(on display: DisplayFacts) -> (sizes: [CGSize], source: CornersReport.Source) {
        if let report = reportedSizeMM,
            Self.plausibleDiagonal(report, on: display) != nil
                || Self.plausibleDiagonal(Self.swapped(report), on: display) != nil
        {
            return ([report], .reported)
        }
        guard let picture = pictureMM(of: display) else { return ([], .shares) }
        return ([picture, Self.swapped(picture)], .display)
    }

    /// A frame with no contacts: in the corners step, a tap or a refusal ends.
    private mutating func glassCleared() {
        let lifted = glass
        glass = .clear
        resting = nil
        guard case .corners(let display, var taps, _) = step else { return }
        switch lifted {
        case .tapping(let tap):
            guard let targets = Self.nativeTargets(on: display, among: displays), taps.count < targets.count else {
                return  // never: the display in use has a mapping, and a round ends at its last target
            }
            taps.append(CalibrationTap(target: targets[taps.count], glass: tap.mean))
            roundTravel.append(tap.travel)
            changedAt = now
            lastInput = now
            if taps.count < targets.count {
                step = .corners(display, taps: taps, problem: nil)
            } else {
                endRound(on: display, taps)
            }
        case .refused(let problem):
            step = .corners(display, taps: taps, problem: problem)
        case .clear, .ignored:
            break
        }
    }

    /// The fourth tap: the fit, or the corners again; and the round's report either way.
    private mutating func endRound(on display: DisplayFacts, _ taps: [CalibrationTap]) {
        rounds += 1
        var measured = CornersReport(
            touchscreen: touchscreen, touchscreenName: touchscreenName, round: rounds, verdict: .accepted,
            orientation: nil, glassMM: nil, glassSource: nil, fromFit: nil, spread: nil, travel: roundTravel,
            travelSource: glassSizesBeforeAFit(on: display).source, moved: roundMoved)
        roundTravel = []
        roundMoved = []
        var fitted: Fitted?
        var problem: SetUpProblem?
        switch Calibration.fit(taps) {
        case .success(let fit):
            // The limits apply in millimetres when the glass has a size; in shares of the glass,
            // only `Calibration`'s own did, and the distances are reported as shares.
            let glass = glassMM(on: display, under: Fitted(orientation: fit.orientation, alignment: fit.alignment))
            let distances = Self.distancesFromFit(taps, under: fit, glassMM: glass?.size ?? CGSize(width: 1, height: 1))
            measured.orientation = fit.orientation
            measured.glassMM = glass?.size
            measured.glassSource = glass?.source ?? .shares
            measured.fromFit = distances
            measured.spread = Self.rootMeanSquare(distances)
            if glass == nil || Self.lieNear(distances) {
                fitted = Fitted(orientation: fit.orientation, alignment: fit.alignment)
            } else {
                problem = .tapsDidNotFit
            }
        case .failure(.ambiguous):
            problem = .ambiguous
        case .failure:
            problem = .tapsDidNotFit
        }
        measured.verdict = problem.map(CornersReport.Verdict.refused) ?? .accepted
        report = measured
        if let fitted {
            if purpose == .full {
                step = .size(display, fitted)
            } else {
                enterCheck(on: display, fitted)
            }
            return
        }
        step = .corners(display, taps: [], problem: problem)
        changedAt = now
    }

    private mutating func enterCheck(on display: DisplayFacts, _ fitted: Fitted) {
        guard let mapping = Self.mapping(fitted, on: display, among: displays) else {
            finish(nil)  // never: a display in use has a mapping, and the fit doesn't change whether it does
            return
        }
        step = .check(mapping)
    }

    @discardableResult
    private mutating func finish(_ outcome: Outcome?) -> Event {
        let event = Event.finished(outcome)
        ending = event
        return event
    }

    /// Whether `taps` lie near enough where their targets fall on the glass under `fit`, on a glass
    /// `glassMM` in size in its own axes: each within `tapReachMM`, and their root mean square
    /// within `fitSpreadMM`. Where a target falls is `rect.origin + target × rect.size` on the
    /// oriented glass, taken back to the glass's own axes by the orientation, where the
    /// millimetres are. A number that isn't finite is never near.
    ///
    /// `Calibration` holds the fit to a root-mean-square 0.04 of the glass, which lets one tap
    /// 0.113 of the glass off (60 mm on a 23.8″ glass) be averaged in. With the four corner targets
    /// a tap off by d, the other three true, lies d / 2 from its fitted place, so `tapReachMM`
    /// refuses one more than 16 mm off.
    static func tapsLieNearTheirTargets(_ taps: [CalibrationTap], under fit: Calibration.Fit, glassMM: CGSize) -> Bool {
        lieNear(distancesFromFit(taps, under: fit, glassMM: glassMM))
    }

    /// Each tap's distance from where its target falls on the glass under `fit`, on a glass
    /// `glassMM` in size in its own axes (1 × 1 gives shares of the glass); see
    /// `tapsLieNearTheirTargets(_:under:glassMM:)`.
    private static func distancesFromFit(
        _ taps: [CalibrationTap], under fit: Calibration.Fit, glassMM: CGSize
    ) -> [Double] {
        let rect = fit.alignment.pictureRect
        return taps.map { tap in
            let place = fit.orientation.inverse(CGPoint(
                x: rect.origin.x + tap.target.x * rect.size.width, y: rect.origin.y + tap.target.y * rect.size.height))
            return hypot(
                Double(tap.glass.x - place.x) * Double(glassMM.width),
                Double(tap.glass.y - place.y) * Double(glassMM.height))
        }
    }

    /// Whether distances from the fit in millimetres are within the limits: each within
    /// `tapReachMM`, and their root mean square within `fitSpreadMM`. None, or one that isn't a
    /// number, is never near.
    private static func lieNear(_ distances: [Double]) -> Bool {
        guard !distances.isEmpty, distances.allSatisfy({ $0 <= tapReachMM }) else { return false }
        return rootMeanSquare(distances) <= fitSpreadMM
    }

    private static func rootMeanSquare(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return (values.reduce(0) { $0 + $1 * $1 } / Double(values.count)).squareRoot()
    }

    /// The size of the glass in millimetres, in its own axes, when it is fitted to `display` as
    /// `fitted` says: what the touchscreen reports, when that, laid along the display's frame, is
    /// plausible there by `SurfaceSize`'s density rule; else the display's picture laid along the
    /// glass; else `nil`.
    ///
    /// The picture (see `pictureMM(of:)`) is in the frame's orientation: turned back from the macOS
    /// rotation it is the display's own picture, which covers the alignment's rectangle of the
    /// oriented glass, so the oriented glass is the picture over the rectangle's extent; and turned
    /// back from the fit's quarter turns it is the glass in its own axes.
    private func glassMM(
        on display: DisplayFacts, under fitted: Fitted
    ) -> (size: CGSize, source: CornersReport.Source)? {
        if let report = reportedSizeMM {
            // Laid along the frame, as the size step lays it: plausible there, or passed over.
            let turns = fitted.orientation.quarterTurns + Self.quarterTurns(display.rotation)
            let alongFrame = turns % 2 == 1 ? Self.swapped(report) : report
            if Self.plausibleDiagonal(alongFrame, on: display) != nil { return (report, .reported) }
        }
        guard let picture = pictureMM(of: display) else { return nil }
        let own = Self.quarterTurns(display.rotation) % 2 == 1 ? Self.swapped(picture) : picture
        let rect = fitted.alignment.pictureRect
        let oriented = CGSize(width: own.width / rect.size.width, height: own.height / rect.size.height)
        let glass = fitted.orientation.quarterTurns % 2 == 1 ? Self.swapped(oriented) : oriented
        return Self.isUsable(glass) ? (glass, .display) : nil
    }

    /// The size of `display`'s picture in millimetres, in its frame's orientation, when it is
    /// known: the confirmed diagonal (only for `.calibrate`: in `.full` the override in force may be
    /// another display's), else the display's own report when it is plausible.
    private func pictureMM(of display: DisplayFacts) -> CGSize? {
        if purpose == .calibrate, let inches = Self.offerable(currentDiagonal) {
            return SurfaceSize.millimetres(display: display, diagonalInches: inches)
        }
        return Self.plausibleDiagonal(display.sizeMM, on: display) != nil ? display.sizeMM : nil
    }

    private static func swapped(_ size: CGSize) -> CGSize {
        CGSize(width: size.height, height: size.width)
    }

    /// A contact's position as a glass point within 0…1, as the reader clamps it; `nil` when a
    /// coordinate isn't finite.
    private static func glassPoint(_ position: CGPoint) -> CGPoint? {
        guard position.x.isFinite, position.y.isFinite else { return nil }
        return CGPoint(x: min(max(position.x, 0), 1), y: min(max(position.y, 0), 1))
    }

    // MARK: - Private: displays

    /// `candidates` that can be calibrated against: see `init`.
    private static func usable(_ candidates: [DisplayFacts], among displays: [DisplayFacts]) -> [DisplayFacts] {
        candidates.filter { !$0.isBuiltIn && mapping(.asFitted, on: $0, among: displays) != nil }
    }

    /// For `.calibrate` and `.test`: the one candidate, if it is `current`'s display, as
    /// `DisplayMatcher` would match it. When a display in `displays` carries the stored UUID, it
    /// must be that one: a twin with the same fingerprint is another display.
    private static func ownDisplay(
        _ candidates: [DisplayFacts], current: Pairing?, among displays: [DisplayFacts]
    ) -> DisplayFacts? {
        guard candidates.count == 1, let current else { return nil }
        let display = candidates[0]
        let uuid = current.display.uuid
        if identifies(uuid), displays.contains(where: { $0.uuid == uuid }) {
            return display.uuid == uuid ? display : nil
        }
        let sameUUID = uuid == display.uuid && identifies(uuid)
        return sameUUID || current.display.hasSameFingerprint(as: display) ? display : nil
    }

    /// Whether `uuid` can identify a display, as `DisplayMatcher` has it: it holds a hex digit other
    /// than 0.
    private static func identifies(_ uuid: String) -> Bool {
        uuid.contains { ($0.hexDigitValue ?? 0) != 0 }
    }

    /// `display` as `displays` has it now; `nil` when it has gone (see `displaysChanged`).
    private func stillHere(_ display: DisplayFacts) -> DisplayFacts? {
        let matches = displays.filter { $0.displayID == display.displayID }
        guard matches.count == 1, DisplayIdentity(matches[0]) == DisplayIdentity(display), !matches[0].isBuiltIn,
            Self.mapping(.asFitted, on: matches[0], among: displays) != nil
        else { return nil }
        return matches[0]
    }

    /// The mapping onto `display`, through the display it mirrors when it mirrors one, as the
    /// resolver builds it. `nil` when that display isn't in `displays` exactly once, or there is
    /// nowhere for a touch to land.
    private static func mapping(
        _ fitted: Fitted, on display: DisplayFacts, among displays: [DisplayFacts]
    ) -> TouchMapping? {
        var content: DisplayFacts?
        if let original = display.mirrors, original != display.displayID {
            let originals = displays.filter { $0.displayID == original }
            guard originals.count == 1 else { return nil }
            content = originals[0]
        }
        return TouchMapping(
            orientation: fitted.orientation, alignment: fitted.alignment, display: display, content: content)
    }

    /// Where the targets fall on `display`'s own unrotated picture: what the glass is fitted against.
    /// Each is within 0…1, as `nativePoint(forDisplay:)` gives it.
    private static func nativeTargets(on display: DisplayFacts, among displays: [DisplayFacts]) -> [CGPoint]? {
        guard let mapping = mapping(.asFitted, on: display, among: displays) else { return nil }
        return targets.map { mapping.nativePoint(forDisplay: $0) }
    }

    // MARK: - Private: sizes

    /// The diagonal of `sizeMM`, in inches, when it is plausible on `display` by `SurfaceSize`'s
    /// density rule (50 to 400 points per inch across and down `display.frame`); `nil` otherwise.
    ///
    /// Asked of `SurfaceSize` itself, so that the rule is never written twice: with no override,
    /// `millimetres` gives the reported size exactly when it is plausible. Otherwise it gives the
    /// size at 96 points per inch, which is plausible, so equal only when the report is that size;
    /// or, for a frame with no usable size, a fixed fallback, which is why a frame less than a
    /// point across, or not finite, has no plausible size here.
    static func plausibleDiagonal(_ sizeMM: CGSize, on display: DisplayFacts) -> Double? {
        let frame = display.frame.size
        guard isUsable(sizeMM), frame.width.isFinite, frame.height.isFinite, frame.width >= 1, frame.height >= 1 else {
            return nil
        }
        var reporting = display
        reporting.sizeMM = sizeMM
        guard SurfaceSize.millimetres(display: reporting, diagonalInches: nil) == sizeMM else { return nil }
        let inches = SurfaceSize.diagonalInches(of: sizeMM)
        return inches.isFinite ? inches : nil
    }

    /// Whether every number in `display`'s frame, native size and reported size is finite. One that
    /// isn't is broken facts, never a display to light or calibrate against; and a value holding a
    /// number that isn't finite doesn't equal itself.
    private static func isSound(_ display: DisplayFacts) -> Bool {
        let frame = display.frame
        return [
            frame.origin.x, frame.origin.y, frame.size.width, frame.size.height, display.nativePixels.width,
            display.nativePixels.height, display.sizeMM.width, display.sizeMM.height,
        ].allSatisfy(\.isFinite)
    }

    /// Whether both sides of `size` are finite and above zero.
    private static func isUsable(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    /// `size`'s longer side over its shorter; `size` is usable.
    private static func longOverShort(_ size: CGSize) -> Double {
        Double(max(size.width, size.height) / min(size.width, size.height))
    }

    /// A macOS rotation in quarter turns, 0…3, as `TouchMapping` takes it: modulo 360, and 0 when it
    /// isn't a whole number of quarter turns.
    private static func quarterTurns(_ degrees: Int) -> Int {
        degrees % 90 == 0 ? (degrees / 90) & 3 : 0
    }
}
