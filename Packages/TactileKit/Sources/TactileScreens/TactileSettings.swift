// The settings: each touchscreen's, and Tactile's own. `SettingsStore` keeps them in one JSON file.

import CoreGraphics
import Foundation
import TactileGestures

// How the settings read a file: every type here takes its default for a field that is missing or
// `null`, and ignores a field it doesn't know, so a file this version writes loads in every later
// one, and a later one may add fields. A field that is there with a value of the wrong type, or with
// a choice this version doesn't have, is not taken for its default: the file can't be decoded, and
// the store sets it aside whole and says so. Taking the default would load the rest and then, on the
// next save, write over the value the person set, without a word.
//
// The values a pairing is made of are decoded whole by their own types: `DisplayIdentity` needs all
// six of its fields, `Orientation` both of its, `GlassAlignment` its rectangle. Every version writes
// them whole, and guessing part of one (a display's serial, whether the glass is flipped) could send
// touches to the wrong display or the wrong place, so a pairing with one incomplete is damaged.
//
// JSON can't hold a number that isn't finite, and saving must not fail because of one. So the
// settings never hold one: a diagonal that isn't finite becomes no diagonal, and an alignment with a
// number that isn't finite becomes the whole glass, as soon as it is set or decoded. That is what
// `SurfaceSize` and `TouchMapping` already make of them, so nothing changes but what is kept. A file
// the store reads can't give one, as `JSONDecoder` refuses a number too large for a `Double`; a
// decoder set to read "inf" or "nan" as numbers can, and gets the same: no diagonal, the whole glass.

/// What a touchscreen that is off does with its touches.
public enum WhenOff: String, Codable, CaseIterable, Sendable {
    /// Tactile keeps the touchscreen and does nothing with its touches.
    case ignoreTouches
    /// Tactile lets go of the touchscreen, and macOS treats it as it would without Tactile.
    case leaveToMacOS
}

/// A touchscreen's display, and how its glass sits on that display's picture.
///
/// In the file, `display` is the one field without a default: a pairing without it is damaged.
/// `orientation` defaults to `asFitted`, `alignment` to `wholeGlass` and `displayName` to "".
public struct Pairing: Equatable, Codable, Sendable {
    /// The display, as the pairing keeps it to find it again. It alone says which display this is.
    public var display: DisplayIdentity
    /// How the glass is fixed on the display's own, unrotated picture.
    public var orientation: Orientation
    /// Where the picture's edges fall on the glass. One with a number that isn't finite is stored as
    /// `wholeGlass`, however it is set.
    public var alignment: GlassAlignment {
        didSet { alignment = Self.storable(alignment) }
    }
    /// The display's name when it was last seen, so a pairing whose display is away can still be
    /// named; "" while none is known. Only a name: it takes no part in which display this is.
    public var displayName: String

    /// A pairing with `display`: as fitted, on the whole glass, with no name, unless told otherwise.
    public init(
        display: DisplayIdentity, orientation: Orientation = .asFitted, alignment: GlassAlignment = .wholeGlass,
        displayName: String = ""
    ) {
        self.display = display
        self.orientation = orientation
        self.alignment = Self.storable(alignment)
        self.displayName = displayName
    }

    private enum CodingKeys: String, CodingKey {
        case display, orientation, alignment, displayName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            display: try container.decode(DisplayIdentity.self, forKey: .display),
            orientation: try container.decodeIfPresent(Orientation.self, forKey: .orientation) ?? .asFitted,
            alignment: try container.decodeIfPresent(GlassAlignment.self, forKey: .alignment) ?? .wholeGlass,
            displayName: try container.decodeIfPresent(String.self, forKey: .displayName) ?? "")
    }

    /// `alignment`, or `wholeGlass` if a number in its rectangle isn't finite.
    private static func storable(_ alignment: GlassAlignment) -> GlassAlignment {
        let rect = alignment.pictureRect
        let numbers = [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height]
        return numbers.allSatisfy(\.isFinite) ? alignment : .wholeGlass
    }
}

/// One touchscreen's settings. A touchscreen seen for the first time starts from these defaults.
public struct TouchscreenSettings: Equatable, Codable, Sendable {
    /// The name the person gave it; `nil` for none.
    public var customName: String? = nil
    /// The name the device reported when it was last connected.
    public var lastSeenName = ""
    /// Whether Tactile handles its touches.
    public var isOn = true
    /// What it does with touches while it is off.
    public var whenOff = WhenOff.ignoreTouches
    /// Its display and fit; `nil` while it is unpaired, when it does nothing.
    public var pairing: Pairing? = nil
    /// The diagonal of its glass in inches, as the person confirmed it, for a display that reports
    /// the wrong size; `nil` to use the size the display reports. One that isn't finite is stored as
    /// `nil`, however it is set or decoded; any finite one is kept as given (`SurfaceSize` uses one
    /// only from 3 to 200 inches, `SurfaceSize.plausibleDiagonals`, and passes over any other).
    public var diagonalInches: Double? = nil {
        didSet { diagonalInches = Self.storable(diagonalInches) }
    }
    /// What one moving finger does, as the person chose it; `nil` for the default for this
    /// touchscreen, which the app works out from what kind of touchscreen it is (Always scroll for
    /// one that gives one finger, Automatic for the others).
    ///
    /// In the file: omitted for the default; a choice as its raw value, with `oneFingerChosen` set to
    /// `true`. A file of 0.4.0 or earlier stores `"automatic"` for the default and for a choice of
    /// Automatic alike, without `oneFingerChosen`; it is read as the default, since nothing can tell
    /// the two apart. Every other value is read as the choice it names, with or without the flag.
    public var oneFinger: OneFingerMode? = nil
    /// Whether the touchscreen gave one finger the last time it said where its touches come from:
    /// `true` when they came from its mouse interface (it stayed in mouse mode), `false` when from
    /// its touch interface; `nil` while it never has. The app keeps it up to date, writing it when it
    /// changes, so that the one-finger default can be worked out from a touchscreen's first touch
    /// after a launch, before it has said anything. A fact of the device, not behaviour.
    public var lastGaveOneFinger: Bool? = nil
    /// Where the pointer goes after a touch.
    public var pointerReturn = PointerReturn.backWhereItWas
    /// Whether circles show where the fingers are.
    public var showsCircles = true
    /// Which gestures beyond one finger are on.
    public var gestures = GestureOptions.all
    /// Which contacts it ignores: palms, and touches that start near an edge.
    public var rejection = RejectionRules()
    /// Whether Tactile has offered to set it up, so the offer is made once.
    public var wasOfferedSetUp = false

    public init() {}

    /// Pairs it with `display`. If it is already paired with that display (an identity equal in all
    /// six fields), its orientation, alignment and remembered display name are kept: the name takes
    /// no part in which display it is. Any other display starts as fitted, on the whole glass, with
    /// no name: the old fit belonged to the old glass-on-display combination.
    public mutating func pair(with display: DisplayIdentity) {
        guard pairing?.display != display else { return }
        pairing = Pairing(display: display)
    }

    /// Unpairs it, forgetting the display and the fit.
    public mutating func unpair() {
        pairing = nil
    }

    /// Takes the behaviour settings from `other`: `oneFinger` (the choice, or the default, as it is),
    /// `pointerReturn`, `showsCircles`, `gestures`, `rejection` and `whenOff`. Nothing else: not the
    /// name, the pairing, `isOn`, the diagonal, `wasOfferedSetUp` or `lastGaveOneFinger`.
    public mutating func copyBehaviour(from other: TouchscreenSettings) {
        oneFinger = other.oneFinger
        pointerReturn = other.pointerReturn
        showsCircles = other.showsCircles
        gestures = other.gestures
        rejection = other.rejection
        whenOff = other.whenOff
    }

    /// Puts the behaviour settings, those `copyBehaviour` copies, back to their defaults (the one-finger
    /// choice to `nil`, the default for the touchscreen), and leaves the rest.
    public mutating func resetBehaviour() {
        copyBehaviour(from: TouchscreenSettings())
    }

    /// The name to show: the custom name without spaces around it, unless that leaves nothing (as
    /// `DisplayLabel` treats a display's); otherwise `lastSeenName`.
    public var displayName: String {
        let custom = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? lastSeenName : custom
    }

    private enum CodingKeys: String, CodingKey {
        case customName, lastSeenName, isOn, whenOff, pairing, diagonalInches, oneFinger, oneFingerChosen,
            lastGaveOneFinger, pointerReturn, showsCircles, gestures, rejection, wasOfferedSetUp
    }

    /// Any field that is missing or `null` keeps its default. A diagonal that isn't finite, which a
    /// decoder set to read "inf" or "nan" can give, is no diagonal, as when one is set: `didSet`
    /// doesn't run here. `"automatic"` without `oneFingerChosen` is the default (see `oneFinger`).
    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        customName = try container.decodeIfPresent(String.self, forKey: .customName) ?? customName
        lastSeenName = try container.decodeIfPresent(String.self, forKey: .lastSeenName) ?? lastSeenName
        isOn = try container.decodeIfPresent(Bool.self, forKey: .isOn) ?? isOn
        whenOff = try container.decodeIfPresent(WhenOff.self, forKey: .whenOff) ?? whenOff
        pairing = try container.decodeIfPresent(Pairing.self, forKey: .pairing) ?? pairing
        diagonalInches = Self.storable(try container.decodeIfPresent(Double.self, forKey: .diagonalInches))
        let oneFingerChoice = try container.decodeIfPresent(OneFingerMode.self, forKey: .oneFinger)
        let oneFingerChosen = try container.decodeIfPresent(Bool.self, forKey: .oneFingerChosen) ?? false
        oneFinger = oneFingerChoice == .automatic && !oneFingerChosen ? nil : oneFingerChoice
        lastGaveOneFinger = try container.decodeIfPresent(Bool.self, forKey: .lastGaveOneFinger)
        pointerReturn = try container.decodeIfPresent(PointerReturn.self, forKey: .pointerReturn) ?? pointerReturn
        showsCircles = try container.decodeIfPresent(Bool.self, forKey: .showsCircles) ?? showsCircles
        gestures = try container.decodeIfPresent(GestureOptions.self, forKey: .gestures) ?? gestures
        rejection = try container.decodeIfPresent(RejectionRules.self, forKey: .rejection) ?? rejection
        wasOfferedSetUp = try container.decodeIfPresent(Bool.self, forKey: .wasOfferedSetUp) ?? wasOfferedSetUp
    }

    /// Writes every field, leaving out those that are `nil`, as the synthesized encoding would; and
    /// `oneFingerChosen` beside a one-finger choice, so that a choice of Automatic is read back as a
    /// choice (see `oneFinger`).
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(customName, forKey: .customName)
        try container.encode(lastSeenName, forKey: .lastSeenName)
        try container.encode(isOn, forKey: .isOn)
        try container.encode(whenOff, forKey: .whenOff)
        try container.encodeIfPresent(pairing, forKey: .pairing)
        try container.encodeIfPresent(diagonalInches, forKey: .diagonalInches)
        if let oneFinger {
            try container.encode(oneFinger, forKey: .oneFinger)
            try container.encode(true, forKey: .oneFingerChosen)
        }
        try container.encodeIfPresent(lastGaveOneFinger, forKey: .lastGaveOneFinger)
        try container.encode(pointerReturn, forKey: .pointerReturn)
        try container.encode(showsCircles, forKey: .showsCircles)
        try container.encode(gestures, forKey: .gestures)
        try container.encode(rejection, forKey: .rejection)
        try container.encode(wasOfferedSetUp, forKey: .wasOfferedSetUp)
    }

    /// `diagonal`, or `nil` if it isn't finite.
    private static func storable(_ diagonal: Double?) -> Double? {
        diagonal.flatMap { $0.isFinite ? $0 : nil }
    }
}

/// All of Tactile's settings: its own, and each touchscreen's.
///
/// In the file, `touchscreens` is a JSON object keyed by each ID's text, and `displayNames` one keyed
/// by display UUID. See the top of this file for how a file is read.
public struct TactileSettings: Equatable, Codable, Sendable {
    /// The version of the file format this Tactile writes. A file with a higher one was written by a
    /// newer Tactile and isn't read: the store sets it aside.
    public static let currentVersion = 1

    /// The version of the file these settings were read from: `currentVersion` for new settings, and
    /// possibly lower for a file an earlier Tactile wrote. A file without one counts as version 1,
    /// the first. Saving always writes `currentVersion`, whatever this says: what is saved is in this
    /// version's format, and so always loads again.
    public var version = currentVersion
    /// Whether Tactile is on at all.
    public var isOn = true
    /// Each touchscreen's settings, under its ID.
    public var touchscreens: [TouchscreenID: TouchscreenSettings] = [:]
    /// The names the person gave displays, by display UUID.
    public var displayNames: [String: String] = [:]
    /// Whether Tactile writes a detailed log.
    public var debugLogging = false
    /// Whether Tactile records the frames of touches it reads.
    public var recordsFrames = false
    /// Whether three- and four-finger swipes left and right follow the fingers, where they can.
    /// Experimental, and off unless the person switches it on.
    public var swipesFollowFingers = false

    public init() {}

    /// What a file without a `version` counts as.
    private static let firstVersion = 1

    private enum CodingKeys: String, CodingKey {
        case version, isOn, touchscreens, displayNames, debugLogging, recordsFrames, swipesFollowFingers
    }

    /// Any field that is missing or `null` keeps its default. A file whose version is higher than
    /// `currentVersion` is refused before anything else in it is read.
    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.firstVersion
        guard version <= Self.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version, in: container,
                debugDescription: "Written by a newer Tactile, as version \(version); this one reads up to \(Self.currentVersion).")
        }
        isOn = try container.decodeIfPresent(Bool.self, forKey: .isOn) ?? isOn
        touchscreens = try container.decodeIfPresent([TouchscreenID: TouchscreenSettings].self, forKey: .touchscreens)
            ?? touchscreens
        displayNames = try container.decodeIfPresent([String: String].self, forKey: .displayNames) ?? displayNames
        debugLogging = try container.decodeIfPresent(Bool.self, forKey: .debugLogging) ?? debugLogging
        recordsFrames = try container.decodeIfPresent(Bool.self, forKey: .recordsFrames) ?? recordsFrames
        swipesFollowFingers = try container.decodeIfPresent(Bool.self, forKey: .swipesFollowFingers) ?? swipesFollowFingers
    }

    /// Writes every field, with `currentVersion` as the version.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(isOn, forKey: .isOn)
        try container.encode(touchscreens, forKey: .touchscreens)
        try container.encode(displayNames, forKey: .displayNames)
        try container.encode(debugLogging, forKey: .debugLogging)
        try container.encode(recordsFrames, forKey: .recordsFrames)
        try container.encode(swipesFollowFingers, forKey: .swipesFollowFingers)
    }
}
