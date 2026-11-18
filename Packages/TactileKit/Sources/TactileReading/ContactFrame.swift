// What a touchscreen reader hands up: the fingers down on the glass at one moment.

import CoreGraphics
import Foundation

/// One finger down on the glass.
public struct Contact: Equatable, Sendable {
    /// The panel's contact identifier. It stays the same while the finger is down; a panel may give
    /// it to the next finger as soon as this one lifts.
    public var id: Int
    /// Where the finger is, as a glass point: 0…1 on each axis, origin top-left of the glass's own
    /// coordinates.
    public var position: CGPoint
    /// The contact's width and height, in the panel's own units, when the panel reports them.
    public var size: CGSize?
    /// The panel's Confidence flag, when it reports one: true for a finger, false for, say, a palm.
    public var isConfident: Bool?

    public init(id: Int, position: CGPoint, size: CGSize? = nil, isConfident: Bool? = nil) {
        self.id = id
        self.position = position
        self.size = size
        self.isConfident = isConfident
    }
}

/// Every finger down on the glass at one moment.
public struct ContactFrame: Equatable, Sendable {
    /// The moment, on the host's clock, in seconds.
    public var time: TimeInterval
    /// Every finger down on the glass at `time`, in ascending contact ID order, one per ID. Empty
    /// when the glass is clear.
    public var contacts: [Contact]

    public init(time: TimeInterval, contacts: [Contact]) {
        self.time = time
        self.contacts = contacts
    }
}
