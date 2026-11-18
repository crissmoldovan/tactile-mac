// How a touchscreen's glass sits on its display's picture: its orientation and its alignment. Both
// describe the hardware, are stored with the pairing, and are the first two steps of the path of a
// point (see `TouchMapping`).

import CoreGraphics
import Foundation

/// How the glass is fixed relative to the display's own, unrotated picture: one of 8, four quarter
/// turns, each plain or flipped. It belongs to the hardware: rotating the display in macOS doesn't
/// change it.
///
/// Applied to a glass point (0…1 on each axis, origin top-left): if flipped, x becomes 1 − x; then,
/// `quarterTurns` times, (x, y) becomes (1 − y, x), the same turn as `TouchMapping.rotate` by 90.
/// The 8 are the 8 symmetries of the square: no two are alike, and one applied after another is one
/// of the 8.
public struct Orientation: Hashable, Codable, Sendable, CaseIterable {
    /// How many quarter turns follow the flip: 0…3. A number outside that range, whether given to
    /// `init`, set here or decoded, is taken modulo 4: 4 is 0 and −1 is 3.
    public var quarterTurns: Int {
        didSet { quarterTurns &= 3 }
    }
    /// Whether the glass is mirrored left to right, before it is turned.
    public var isFlipped: Bool

    public init(quarterTurns: Int, isFlipped: Bool) {
        self.quarterTurns = quarterTurns & 3
        self.isFlipped = isFlipped
    }

    /// The glass fitted straight on the picture: neither turned nor flipped.
    public static let asFitted = Orientation(quarterTurns: 0, isFlipped: false)

    /// All 8: the four quarter turns plain, then the four flipped. `asFitted` is first.
    public static let allCases: [Orientation] = [false, true].flatMap { isFlipped in
        (0..<4).map { Orientation(quarterTurns: $0, isFlipped: isFlipped) }
    }

    /// `p`, a glass point, on the display's own unrotated picture. Exact and unclamped: a point off
    /// the glass stays off it, and a finite point gives a finite point.
    public func apply(_ p: CGPoint) -> CGPoint {
        Self.turned(isFlipped ? CGPoint(x: 1 - p.x, y: p.y) : p, quarterTurns: quarterTurns)
    }

    /// What `apply` undoes: a point on the display's own unrotated picture, back on the glass.
    public func inverse(_ p: CGPoint) -> CGPoint {
        let unturned = Self.turned(p, quarterTurns: 4 - quarterTurns)
        return isFlipped ? CGPoint(x: 1 - unturned.x, y: unturned.y) : unturned
    }

    /// `p` turned `quarterTurns` times, each (x, y) → (1 − y, x); `quarterTurns` is taken modulo 4.
    static func turned(_ p: CGPoint, quarterTurns: Int) -> CGPoint {
        switch quarterTurns & 3 {
        case 1: return CGPoint(x: 1 - p.y, y: p.x)
        case 2: return CGPoint(x: 1 - p.x, y: 1 - p.y)
        case 3: return CGPoint(x: p.y, y: 1 - p.x)
        default: return p
        }
    }

    private enum CodingKeys: String, CodingKey {
        case quarterTurns, isFlipped
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            quarterTurns: try container.decode(Int.self, forKey: .quarterTurns),
            isFlipped: try container.decode(Bool.self, forKey: .isFlipped))
    }
}

/// Where the picture's edges fall on the glass, once the glass is oriented: the rectangle of the
/// oriented glass that the picture occupies, in the glass's own 0…1 coordinates, origin top-left. It
/// can reach past the glass where the picture is larger than it.
///
/// It is kept as given. `TouchMapping` maps with the whole glass in place of a rectangle that isn't
/// one: a width or height that is zero, negative or not a number, or an origin, size or far corner
/// that isn't finite. Unlike a display's frame, such a rectangle doesn't stop the mapping.
///
/// Named for the glass so that it never clashes with SwiftUI's `Alignment` in the app.
public struct GlassAlignment: Equatable, Codable, Sendable {
    public var pictureRect: CGRect

    public init(pictureRect: CGRect) {
        self.pictureRect = pictureRect
    }

    /// The picture covers the glass exactly: (0, 0, 1, 1).
    public static let wholeGlass = GlassAlignment(pictureRect: CGRect(x: 0, y: 0, width: 1, height: 1))
}
