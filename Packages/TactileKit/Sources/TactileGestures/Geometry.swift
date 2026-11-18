import CoreGraphics
import Foundation

extension CGPoint {
    static func - (a: CGPoint, b: CGPoint) -> CGVector {
        CGVector(dx: a.x - b.x, dy: a.y - b.y)
    }
}

extension CGVector {
    var length: Double {
        Double((dx * dx + dy * dy).squareRoot())
    }

    func scaled(by factor: Double) -> CGVector {
        CGVector(dx: Double(dx) * factor, dy: Double(dy) * factor)
    }
}

func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
    CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
}

func centroid(_ points: [CGPoint]) -> CGPoint {
    guard !points.isEmpty else { return .zero }
    let count = CGFloat(points.count)
    return CGPoint(x: points.reduce(0) { $0 + $1.x } / count, y: points.reduce(0) { $0 + $1.y } / count)
}

/// The direction of `v` in degrees, anticlockwise from the right as seen on a display whose y
/// grows downwards; `nil` for no direction at all.
func directionDegrees(_ v: CGVector) -> Double? {
    guard v.length > 0 else { return nil }
    return atan2(-Double(v.dy), Double(v.dx)) * 180 / .pi
}

/// The turn from direction `from` to direction `to`, in degrees, the short way round: more than
/// -180 and at most 180. Positive is anticlockwise.
func turnDegrees(from: Double, to: Double) -> Double {
    var turn = (to - from).truncatingRemainder(dividingBy: 360)
    if turn > 180 { turn -= 360 } else if turn <= -180 { turn += 360 }
    return turn
}

/// The angle between two directions, in degrees from 0 to 180.
func angleDegrees(_ a: CGVector, _ b: CGVector) -> Double {
    let lengths = a.length * b.length
    guard lengths > 0 else { return 180 }
    let cosine = max(-1, min(1, Double(a.dx * b.dx + a.dy * b.dy) / lengths))
    return acos(cosine) * 180 / .pi
}
