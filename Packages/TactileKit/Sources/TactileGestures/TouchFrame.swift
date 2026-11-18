import CoreGraphics
import Foundation

/// One finger on the glass in one frame.
public struct Finger: Codable, Equatable, Sendable {
    /// The panel's contact ID. It stays the same while the finger is down; panels reuse IDs after a lift.
    public var id: Int
    /// Where the finger is on the screen the panel is mapped to: 0…1 on each axis, origin top-left.
    public var location: CGPoint
    /// The contact's width and height in millimetres, or `nil` when the panel doesn't report it.
    public var size: CGSize?
    /// The panel's own "this is a finger" flag, or `nil` when the panel doesn't report it.
    public var isConfident: Bool?

    public init(id: Int, location: CGPoint, size: CGSize? = nil, isConfident: Bool? = nil) {
        self.id = id
        self.location = location
        self.size = size
        self.isConfident = isConfident
    }
}

/// Everything a panel reported in one complete report.
public struct TouchFrame: Codable, Equatable, Sendable {
    /// Seconds on a monotonic clock. The app uses `ProcessInfo.processInfo.systemUptime`.
    public var time: TimeInterval
    /// Every finger that counts, after the contact filter: by the time a frame reaches the pointer
    /// arbiter and the engine, the contacts the filter refuses are gone from it. A finger missing
    /// from a frame has lifted.
    public var fingers: [Finger]
    /// The touch surface in millimetres, in the same orientation as `Finger.location`.
    public var surfaceSize: CGSize

    public init(time: TimeInterval, fingers: [Finger], surfaceSize: CGSize) {
        self.time = time
        self.fingers = fingers
        self.surfaceSize = surfaceSize
    }

    /// Reads a recording: one JSON-encoded frame per line.
    public static func decodeLines(_ data: Data) throws -> [TouchFrame] {
        let decoder = JSONDecoder()
        return try data.split(separator: UInt8(ascii: "\n")).map { try decoder.decode(TouchFrame.self, from: Data($0)) }
    }
}
