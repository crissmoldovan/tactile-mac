// A display's facts, what a pairing keeps of its display, and which connected display each pairing
// means now.

import CoreGraphics
import Foundation

/// What macOS says about one connected display. The app fills it from CoreGraphics and AppKit.
public struct DisplayFacts: Equatable, Sendable {
    /// The display's ID for as long as it stays connected (`CGDirectDisplayID`).
    public var displayID: UInt32
    /// The display's UUID as macOS gives it.
    public var uuid: String
    /// The vendor number the display reports.
    public var vendor: Int
    /// The model number the display reports.
    public var model: Int
    /// The serial number the display reports. Often 0 or 1, the same on every unit of a model.
    public var serial: Int
    /// The panel's own largest mode, in pixels, unrotated.
    public var nativePixels: CGSize
    /// The physical size the display reports, in millimetres; zero when it reports none. It can be
    /// wrong: "HDMI" reports 27″ and is 23.8″.
    public var sizeMM: CGSize
    /// The display's name as macOS shows it.
    public var name: String
    /// Where its picture is in the global desktop, in points: origin at the top-left of the main
    /// display, y growing downwards.
    public var frame: CGRect
    /// Its rotation as macOS reports it: 0, 90, 180 or 270.
    public var rotation: Int
    /// Whether it is the Mac's own display.
    public var isBuiltIn: Bool
    /// Whether it is the main display, the one at the origin.
    public var isMain: Bool
    /// The display whose picture this one shows, when it mirrors another; `nil` otherwise.
    public var mirrors: UInt32?

    public init(
        displayID: UInt32, uuid: String, vendor: Int, model: Int, serial: Int, nativePixels: CGSize, sizeMM: CGSize,
        name: String, frame: CGRect, rotation: Int, isBuiltIn: Bool, isMain: Bool, mirrors: UInt32?
    ) {
        self.displayID = displayID
        self.uuid = uuid
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.nativePixels = nativePixels
        self.sizeMM = sizeMM
        self.name = name
        self.frame = frame
        self.rotation = rotation
        self.isBuiltIn = isBuiltIn
        self.isMain = isMain
        self.mirrors = mirrors
    }
}

/// What a pairing keeps of its display, to find it again: the display's UUID, and its fingerprint,
/// which is everything else here: vendor, model, serial and native pixel size.
public struct DisplayIdentity: Hashable, Codable, Sendable {
    public var uuid: String
    public var vendor: Int
    public var model: Int
    public var serial: Int
    public var nativeWidth: Int
    public var nativeHeight: Int

    public init(uuid: String, vendor: Int, model: Int, serial: Int, nativeWidth: Int, nativeHeight: Int) {
        self.uuid = uuid
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.nativeWidth = nativeWidth
        self.nativeHeight = nativeHeight
    }

    /// The identity of a connected display. The native size is taken in whole pixels: rounded, and 0
    /// if it isn't a number or is too large to write.
    public init(_ facts: DisplayFacts) {
        self.init(
            uuid: facts.uuid, vendor: facts.vendor, model: facts.model, serial: facts.serial,
            nativeWidth: Self.wholePixels(facts.nativePixels.width),
            nativeHeight: Self.wholePixels(facts.nativePixels.height))
    }

    /// Whether `facts` has this identity's vendor, model, serial and native pixel size. The UUID
    /// isn't compared.
    public func hasSameFingerprint(as facts: DisplayFacts) -> Bool {
        fingerprint == DisplayIdentity(facts).fingerprint
    }

    /// Everything but the UUID.
    fileprivate struct Fingerprint: Hashable {
        let vendor: Int
        let model: Int
        let serial: Int
        let nativeWidth: Int
        let nativeHeight: Int
    }

    fileprivate var fingerprint: Fingerprint {
        Fingerprint(vendor: vendor, model: model, serial: serial, nativeWidth: nativeWidth, nativeHeight: nativeHeight)
    }

    private static func wholePixels(_ value: CGFloat) -> Int {
        guard value.isFinite, let whole = Int(exactly: value.rounded()) else { return 0 }
        return whole
    }
}

/// Which connected display each stored pairing means now.
///
/// Tactile never guesses: a touch on the wrong display is worse than no touch. Where the rules below
/// can't be certain, the touchscreen is left out of the answer, as if its display weren't connected.
///
/// Pass every stored pairing, connected or only remembered, and use the answers only for connected
/// touchscreens. A remembered touchscreen's pairing still claims its display. Left out, its display
/// looks unclaimed: with two identical displays, one of them off, the touchscreen paired with the one
/// that is off would take the other by its fingerprint, and its touches would land on the display of
/// the touchscreen that is unplugged.
public enum DisplayMatcher {

    /// The display ID each paired touchscreen's display has now. A touchscreen with no certain match
    /// is absent.
    ///
    /// Pass every stored pairing, connected or only remembered, and use the answers only for
    /// connected touchscreens. A remembered touchscreen's pairing still claims its display (see
    /// `DisplayMatcher`).
    ///
    /// 1. **By UUID.** A pairing whose UUID a connected display has takes that display, if no other
    ///    connected display has that UUID and no other pairing names it. Matched or not, such a
    ///    pairing is settled here: it never falls back to its fingerprint, which could pick another
    ///    display of its model.
    /// 2. **By fingerprint.** For each pairing whose UUID no connected display has: the connected
    ///    displays with its fingerprint that step 1 left unclaimed. If there is exactly one, and no
    ///    other such pairing has the same fingerprint, the pairing takes it. A display is claimed in
    ///    step 1 when any pairing's UUID names it, whether or not that pairing got it.
    /// 3. Otherwise no match.
    ///
    /// A UUID with no hex digit other than 0 identifies nothing: one that is empty, only whitespace, or
    /// the null UUID, 00000000-0000-0000-0000-000000000000. A pairing with one goes straight to step 2,
    /// and a display with one is never claimed by UUID, though it can still be taken by its
    /// fingerprint. A device layer may write "" or the null UUID where macOS gave no UUID.
    ///
    /// The built-in display is never a match, and is never counted as a candidate. Two pairings never
    /// share a display.
    ///
    /// Malformed input doesn't trap and is never guessed through. A UUID that two pairings name (a
    /// damaged settings file), or that two connected displays have, gives no match to any pairing
    /// with it. A display ID listed more than once in `connected` is no match for anyone, though it
    /// still counts as a candidate, so it can make a fingerprint ambiguous. The answer never depends
    /// on the order of `connected` or of `pairings`.
    public static func resolve(
        pairings: [TouchscreenID: DisplayIdentity], connected: [DisplayFacts]
    ) -> [TouchscreenID: UInt32] {
        resolve(orderedPairings: pairings.map { ($0.key, $0.value) }, connected: connected)
    }

    /// `resolve(pairings:connected:)` with the pairings as a list, so that tests can give them in
    /// every order: a dictionary's iteration order can't be chosen.
    ///
    /// A touchscreen listed more than once, which a dictionary can't hold, gets no match. Each of its
    /// entries still names its display by UUID and still counts as a rival for its fingerprint, as
    /// any pairing's would.
    static func resolve(
        orderedPairings pairings: [(TouchscreenID, DisplayIdentity)], connected: [DisplayFacts]
    ) -> [TouchscreenID: UInt32] {
        let screensWithID = counts(of: pairings.map { $0.0 })
        let displaysWithID = counts(of: connected.map(\.displayID))
        let displaysWithUUID = counts(of: connected.map(\.uuid).filter(isUUID))
        let pairingsWithUUID = counts(of: pairings.map { $0.1.uuid }.filter(isUUID))

        /// Whether a pairing can be given `display`: not the built-in one, and not one whose display
        /// ID stands for more than one display.
        func canTake(_ display: DisplayFacts) -> Bool {
            !display.isBuiltIn && displaysWithID[display.displayID] == 1
        }

        var answer: [TouchscreenID: UInt32] = [:]

        // 1. By UUID.
        var byFingerprint: [DisplayIdentity.Fingerprint: [TouchscreenID]] = [:]
        for (screen, identity) in pairings {
            guard let carriers = displaysWithUUID[identity.uuid] else {
                byFingerprint[identity.fingerprint, default: []].append(screen)
                continue
            }
            guard carriers == 1, pairingsWithUUID[identity.uuid] == 1,
                let display = connected.first(where: { $0.uuid == identity.uuid }), canTake(display)
            else { continue }
            answer[screen] = display.displayID
        }

        // 2. By fingerprint, among the displays no pairing names by UUID.
        var unclaimed: [DisplayIdentity.Fingerprint: [DisplayFacts]] = [:]
        for display in connected where !display.isBuiltIn && pairingsWithUUID[display.uuid] == nil {
            unclaimed[DisplayIdentity(display).fingerprint, default: []].append(display)
        }
        for (fingerprint, screens) in byFingerprint {
            guard screens.count == 1, let candidates = unclaimed[fingerprint], candidates.count == 1,
                canTake(candidates[0])
            else { continue }
            answer[screens[0]] = candidates[0].displayID
        }
        return answer.filter { screensWithID[$0.key] == 1 }
    }

    /// Whether `uuid` can identify a display: it holds a hex digit other than 0. So one that is empty,
    /// only whitespace, or all zeros (the null UUID) can't.
    private static func isUUID(_ uuid: String) -> Bool {
        uuid.contains { ($0.hexDigitValue ?? 0) != 0 }
    }

    private static func counts<Key: Hashable>(of keys: [Key]) -> [Key: Int] {
        keys.reduce(into: [:]) { counts, key in counts[key, default: 0] += 1 }
    }
}
