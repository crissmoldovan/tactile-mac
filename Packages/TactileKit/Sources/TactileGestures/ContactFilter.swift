import CoreGraphics
import Foundation

/// Which contacts a touchscreen's `ContactFilter` refuses, beyond its finger limit.
///
/// Neither touchscreen surveyed so far (the ILITEK and the wch.cn strip) reports a contact's
/// confidence or size, so on them the not-confident and too-wide rules never act: only the
/// whole-hand and edge rules can.
public struct RejectionRules: Equatable, Codable, Sendable {
    /// Ignore contacts the panel marks as not confident or wider than 25 mm, and whole hands: five
    /// or more contacts down that all landed within 0.2 s of the first of them.
    public var palm: Bool
    /// Ignore touches that start within this many millimetres of an edge. 0 is off; at most 10.
    /// Kept within 0…10; a value that isn't finite becomes 0.
    public var edgeMarginMM: Double {
        didSet { edgeMarginMM = Self.clamped(edgeMarginMM) }
    }

    public init(palm: Bool = true, edgeMarginMM: Double = 0) {
        self.palm = palm
        self.edgeMarginMM = Self.clamped(edgeMarginMM)
    }

    /// Nothing refused: the rules of a filter made without any.
    public static let none = RejectionRules(palm: false, edgeMarginMM: 0)

    /// Any key that's missing keeps its default, so settings saved before a rule existed still load.
    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        palm = try container.decodeIfPresent(Bool.self, forKey: .palm) ?? palm
        edgeMarginMM = Self.clamped(try container.decodeIfPresent(Double.self, forKey: .edgeMarginMM) ?? edgeMarginMM)
    }

    private static func clamped(_ margin: Double) -> Double {
        margin.isFinite ? min(10, max(0, margin)) : 0
    }
}

/// Decides which of a touchscreen's contacts count, before the pointer arbiter and the gesture
/// engine see them. A refused contact is invisible to both, and stays refused until it lifts.
/// Contacts are told apart by their contact ID, never by where the panel lists them.
///
/// The rules, each refusing a contact until it lifts:
/// - **Finger limit:** on a one-finger-only touchscreen, a contact that lands while a finger is
///   already down, typically a resting palm, is refused. Contacts the other rules refuse take no
///   room.
/// - **Palm** (`rules.palm`): a contact the panel marks as not confident, or wider than 25 mm, in
///   any frame; and a whole hand, five or more contacts down that all landed within 0.2 s of the
///   first of them, every one of them.
/// - **Edge** (`rules.edgeMarginMM`): a touch whose first position is within the margin of an edge.
///   One that starts inside and moves to the edge is unaffected.
///
/// A contact refused as it first appears is simply never seen. One refused after it was let
/// through (it widened, lost confidence, or joined a hand) sets `mustCancel` for that call.
///
/// Known limit: on a one-finger-only touchscreen whose panel reports neither confidence nor size,
/// the first contact down is the one that acts, so a palm that lands before the finger takes the
/// gesture. Helping that waits for a recording of a real palm.
///
/// Call on the main thread, like the arbiter and the engine it feeds.
public struct ContactFilter: Sendable {

    /// The most fingers this touchscreen can use at once; `nil` for no limit. A change applies to
    /// fingers that land afterwards: a finger that counts keeps counting, a refused one stays refused.
    public var fingerLimit: Int?

    /// Which contacts to refuse beyond the finger limit. A change applies from the next frame: a
    /// rule switched on can refuse a contact already down (the palm rules) or landing (the edge).
    public var rules: RejectionRules

    /// The contact IDs currently refused. Each stays refused until a frame arrives without it.
    public private(set) var refused: Set<Int> = []

    /// True after a call to `live` in which a contact that had been let through was refused. The
    /// caller must then cancel the engine's session before giving it the frame, so the vanished
    /// contact is not read as a lift; the engine, once cancelled, ignores the fingers still down
    /// until all have lifted. False after every other call.
    public private(set) var mustCancel = false

    /// The contact IDs that count. Each keeps counting until a frame arrives without it.
    private var counting: Set<Int> = []

    /// When each contact down was first seen, for the whole-hand rule. Only `live(_:at:surfaceSize:)`
    /// knows the time.
    private var landedAt: [Int: TimeInterval] = [:]

    private let constants = GestureConstants.standard

    /// A filter with a finger limit and no other rules, as before rejection existed.
    public init(fingerLimit: Int? = nil) {
        self.init(fingerLimit: fingerLimit, rules: .none)
    }

    public init(fingerLimit: Int? = nil, rules: RejectionRules) {
        self.fingerLimit = fingerLimit
        self.rules = rules
    }

    /// Call once per frame with every finger in it, its time and the surface size in millimetres.
    /// Returns the fingers that count, in the order given. A surface size that isn't finite and
    /// positive switches the edge rule off for this frame.
    public mutating func live(_ fingers: [Finger], at time: TimeInterval, surfaceSize: CGSize) -> [Finger] {
        filter(fingers, time: time, surface: surfaceSize)
    }

    /// Call once per frame with every finger in it. Returns the fingers that count, in the order
    /// given. Without the time and the surface size, only the finger limit applies, and with `palm`
    /// on the not-confident and too-wide rules: not the whole-hand or edge rules.
    ///
    /// Don't mix it with `live(_:at:surfaceSize:)` on one filter: a contact that lands through this
    /// call has no landing time, so the whole-hand rule never counts it, even in later timed calls.
    public mutating func live(_ fingers: [Finger]) -> [Finger] {
        filter(fingers, time: nil, surface: nil)
    }

    private mutating func filter(_ fingers: [Finger], time: TimeInterval?, surface: CGSize?) -> [Finger] {
        mustCancel = false
        // A panel can list one contact twice in a report. It is still one finger; its first entry counts.
        var present = Set<Int>()
        let reported = fingers.filter { present.insert($0.id).inserted }

        // A contact missing from this frame has lifted, whether it counted or was refused.
        counting.formIntersection(present)
        refused.formIntersection(present)
        landedAt = landedAt.filter { present.contains($0.key) }

        let landing = present.subtracting(counting).subtracting(refused)
        if let time {
            for id in landing { landedAt[id] = time }
        }

        // The rules that refuse a contact whatever came before, whether it counts yet or not.
        var refusing = Set<Int>()
        if rules.palm {
            refusing.formUnion(reported.filter(isPalm).map(\.id))
            if time != nil { refusing.formUnion(hand()) }
        }
        if rules.edgeMarginMM > 0, let surface, surface.width.isFinite, surface.height.isFinite,
           surface.width > 0, surface.height > 0 {
            refusing.formUnion(reported.filter {
                landing.contains($0.id) && isNearEdge($0.location, on: surface)
            }.map(\.id))
        }
        if !refusing.isDisjoint(with: counting) { mustCancel = true }
        counting.subtract(refusing)
        refused.formUnion(refusing)

        // Contacts landing in this frame that no rule refused take whatever room the limit leaves,
        // lowest contact ID first, whatever order the panel lists them in. The rest are refused.
        let admitted = landing.subtracting(refused).sorted()
        let room = fingerLimit.map { max(0, $0 - counting.count) } ?? admitted.count
        counting.formUnion(admitted.prefix(room))
        refused.formUnion(admitted.dropFirst(room))

        return reported.filter { counting.contains($0.id) }
    }

    /// Not confident, or wider than a finger, by the panel's own account. A panel that reports
    /// neither never trips this.
    private func isPalm(_ finger: Finger) -> Bool {
        if finger.isConfident == false { return true }
        guard let size = finger.size else { return false }
        return max(size.width, size.height) > constants.palmWidthMM
    }

    /// Every contact down in a group of `handContactCount` or more that all landed within
    /// `swipeLanding` of the first of them. Contacts refused for other reasons count too: the
    /// rule is about what is touching the glass.
    private func hand() -> Set<Int> {
        let landings = landedAt.sorted { $0.value < $1.value }
        var hand = Set<Int>()
        for (index, first) in landings.enumerated() {
            let group = landings[index...].prefix { $0.value - first.value <= constants.swipeLanding }
            if group.count >= constants.handContactCount { hand.formUnion(group.map(\.key)) }
        }
        return hand
    }

    /// Within the edge margin of any edge, each axis measured in millimetres on the glass.
    private func isNearEdge(_ location: CGPoint, on surface: CGSize) -> Bool {
        let margin = rules.edgeMarginMM
        let x = Double(location.x * surface.width), y = Double(location.y * surface.height)
        return x < margin || Double(surface.width) - x < margin || y < margin || Double(surface.height) - y < margin
    }
}
