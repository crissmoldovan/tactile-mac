import Foundation

/// What one moving finger does.
public enum OneFingerMode: String, CaseIterable, Codable, Sendable {
    /// Drag or scroll, depending on what's under the finger.
    case automatic
    case alwaysDrag
    case alwaysScroll
}

/// Where the pointer goes after a touch.
public enum PointerReturn: String, CaseIterable, Codable, Sendable {
    /// Back to where it was, if that was on another screen.
    case backWhereItWas
    /// Left where the last finger lifted.
    case staysWhereTouched
}

/// Which gestures are on, beyond a plain tap, drag and scroll with one finger.
public struct GestureOptions: Equatable, Codable, Sendable {
    public var twoFingerScroll = true
    public var pinch = true
    public var twoFingerTap = true
    public var swipes = true
    /// One finger resting 0.6 s, then lifted, right-clicks. A one-finger gesture: it doesn't count
    /// towards `fingerLimit`.
    public var longPress = true
    /// Two fingers turning about each other rotate.
    public var rotate = true

    public init() {}

    public static let all = GestureOptions()

    /// `options` with every gesture beyond one finger off, and the one-finger ones (long-press) as
    /// they were: for a touchscreen that reports one point, or one set to use one finger only. Its
    /// `fingerLimit` is 1, and stays 1 when a multi-finger gesture is added here.
    public static func oneFingerOnly(keeping options: GestureOptions) -> GestureOptions {
        var result = options
        result.twoFingerScroll = false
        result.pinch = false
        result.twoFingerTap = false
        result.swipes = false
        result.rotate = false
        return result
    }

    /// The most fingers a touchscreen with these options can use at once, for its `ContactFilter`:
    /// 1 when every gesture beyond one finger is off, so a second contact such as a resting palm is
    /// refused; otherwise `nil`, no limit. Computed, so the stored settings don't change.
    public var fingerLimit: Int? {
        twoFingerScroll || pinch || twoFingerTap || swipes || rotate ? nil : 1
    }

    /// Any key that's missing keeps its default, so settings saved before an option existed still load.
    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        twoFingerScroll = try container.decodeIfPresent(Bool.self, forKey: .twoFingerScroll) ?? twoFingerScroll
        pinch = try container.decodeIfPresent(Bool.self, forKey: .pinch) ?? pinch
        twoFingerTap = try container.decodeIfPresent(Bool.self, forKey: .twoFingerTap) ?? twoFingerTap
        swipes = try container.decodeIfPresent(Bool.self, forKey: .swipes) ?? swipes
        longPress = try container.decodeIfPresent(Bool.self, forKey: .longPress) ?? longPress
        rotate = try container.decodeIfPresent(Bool.self, forKey: .rotate) ?? rotate
        // A touchscreen set to one finger before rotate existed saved the four older multi-finger
        // gestures off and no rotate. It stays one finger: rotate comes out off too.
        let olderMultiFinger: [CodingKeys] = [.twoFingerScroll, .pinch, .twoFingerTap, .swipes]
        if !container.contains(.rotate),
           try olderMultiFinger.allSatisfy({ try container.decodeIfPresent(Bool.self, forKey: $0) == false }) {
            rotate = false
        }
    }
}
