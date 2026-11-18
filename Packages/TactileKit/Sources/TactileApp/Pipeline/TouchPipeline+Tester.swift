// What a touch pipeline tells the gesture tester, while the tester is open for its touchscreen.

import CoreGraphics
import Foundation
import TactileGestures

/// Why a pipeline didn't act on a contact on its glass.
public enum IgnoredBecause: String, CaseIterable, Equatable, Sendable {
    /// The panel marked it as not a finger, or it is wider than one (palm rejection).
    case palm
    /// Five or more contacts landing together: a whole hand (palm rejection).
    case hand
    /// It started within the edge margin.
    case edge
    /// A contact beyond the first on a touchscreen that uses one finger.
    case beyondOneFinger
    /// The other touchscreen has the pointer: its touch goes on, and this one is drawn hollow.
    case otherTouchscreenHasThePointer
    /// It was down before the pipeline could follow it (when it began, or after a silence): it is
    /// not acted on until the glass clears.
    case alreadyDown
    /// What is left of a touch cut short: not acted on until no finger counts.
    case restOfATouchCutShort
}

/// Why a pipeline cut a touch short.
public enum CutShortBecause: String, Equatable, Sendable {
    /// A contact that had counted was refused: a palm or a hand.
    case palm
    /// The other touchscreen took the pointer.
    case takenOver
    /// Nothing came for `TouchPipeline.silenceLimit` with fingers down: the lift was lost.
    case silence
    /// It stopped driving, or where its touches land changed.
    case stopped
}

/// One thing a pipeline tells its observer, in the order it happens.
public enum TouchObservation: Equatable, Sendable {
    /// A frame: every contact on the glass, by contact ID, and those not acted on, with why. Told
    /// before the engine's actions for the frame. After a silence, the glass as the pipeline now
    /// takes it: empty.
    case frame(onGlass: Set<Int>, ignored: [Int: IgnoredBecause])
    /// One of the engine's actions, once carried out. `held`: a three- or four-finger swipe the
    /// tester holds, for which nothing was posted.
    case action(GestureAction, held: Bool)
    /// The touch in flight is cut short; the engine's cancel follows, closing what was under way.
    /// Told only when there was a session to cancel.
    case cutShort(CutShortBecause)
}

/// The gesture tester's ear on one touchscreen's pipeline (see `TouchPipeline.observer`).
@MainActor
public protocol TouchPipelineObserver: AnyObject {
    /// Whether three- and four-finger swipes that begin now are held: recorded and not done. Read
    /// when each swipe is decided; a followed swipe keeps what it began with to its end.
    var holdsSwipes: Bool { get }
    func pipeline(_ pipeline: TouchPipeline, saw observation: TouchObservation, at time: TimeInterval)
}

extension TouchPipeline {

    /// Tells the observer of a frame: its `fingers`; those `filter` refuses, each with why; and
    /// every other finger, as `rest`, when the frame went no further. Nothing without an observer.
    func observeFrame(_ fingers: [Finger], refusedBy filter: ContactFilter?, rest: IgnoredBecause?,
                      surface: CGSize, at time: TimeInterval) {
        guard let observer else { return }
        var ignored: [Int: IgnoredBecause] = [:]
        for finger in fingers {
            if let filter, filter.refused.contains(finger.id) {
                ignored[finger.id] = Self.whyRefused(finger, rules: filter.rules, fingerLimit: filter.fingerLimit,
                                                     contactsOnGlass: fingers.count, surface: surface)
            } else if let rest {
                ignored[finger.id] = rest
            }
        }
        observer.pipeline(self, saw: .frame(onGlass: Set(fingers.map(\.id)), ignored: ignored), at: time)
    }

    /// Why a contact the contact filter refuses was refused, by the filter's own rules, in the order
    /// they decide: the panel's word or its size (palm), five or more contacts down (a hand), where it
    /// started (the edge), else the finger limit. The filter says only that it refuses; this is for
    /// the gesture tester's words, and is tested against the filter. Its one approximation: five or
    /// more contacts on the glass with palm rejection on are taken for a hand, whenever they landed.
    nonisolated static func whyRefused(_ finger: Finger, rules: RejectionRules, fingerLimit: Int?, contactsOnGlass: Int,
                           surface: CGSize) -> IgnoredBecause {
        let constants = GestureConstants.standard
        if rules.palm {
            if finger.isConfident == false { return .palm }
            if let size = finger.size, max(size.width, size.height) > constants.palmWidthMM { return .palm }
            if contactsOnGlass >= constants.handContactCount { return .hand }
        }
        let margin = rules.edgeMarginMM
        if margin > 0, surface.width.isFinite, surface.height.isFinite, surface.width > 0, surface.height > 0 {
            let x = Double(finger.location.x * surface.width), y = Double(finger.location.y * surface.height)
            if x < margin || Double(surface.width) - x < margin || y < margin || Double(surface.height) - y < margin {
                return .edge
            }
        }
        if fingerLimit != nil { return .beyondOneFinger }
        return rules.palm ? .hand : .palm
    }
}
