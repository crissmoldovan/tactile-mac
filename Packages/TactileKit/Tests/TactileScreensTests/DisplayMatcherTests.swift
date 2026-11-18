import CoreGraphics
import Foundation
import XCTest
@testable import TactileScreens

// The desk's five displays, as the app will read them. Names, picture sizes, positions and the sizes
// "HDMI" and "12.3FHD" report are the desk's; UUIDs, vendor and model codes are made up but shaped
// like the real ones. `DisplayLabelTests` uses them too.

/// The desk's five displays, around the built-in one, which is main.
enum DeskDisplays {
    /// The Mac's own display: main, at the origin.
    static let builtIn = DisplayFacts(
        displayID: 1, uuid: "FACADE00-0000-4000-8000-000000000001", vendor: 0x0610, model: 0xa050, serial: 0,
        nativePixels: CGSize(width: 3024, height: 1964), sizeMM: CGSize(width: 302, height: 196), name: "Built-in",
        frame: CGRect(x: 0, y: 0, width: 2056, height: 1329), rotation: 0, isBuiltIn: true, isMain: true,
        mirrors: nil)

    /// The 27″ 4K monitor, to the right. It reports a 597 × 336 mm picture: 26.97″.
    static let lg = DisplayFacts(
        displayID: 2, uuid: "1E6D5B14-0000-0000-2B1F-0104B53C2278", vendor: 0x1e6d, model: 0x5b14, serial: 0x0006_d3b1,
        nativePixels: CGSize(width: 3840, height: 2160), sizeMM: CGSize(width: 597, height: 336), name: "LG HDR 4K",
        frame: CGRect(x: 2056, y: 0, width: 3008, height: 1692), rotation: 0, isBuiltIn: false, isMain: false,
        mirrors: nil)

    /// The 2K monitor the ILITEK sits on, above. It reports 602 × 329 mm, 27″; it is really 23.8″.
    static let hdmi = DisplayFacts(
        displayID: 3, uuid: "4C2D0E10-0000-0000-0A20-0104B53C2278", vendor: 0x4c2d, model: 0x0e10, serial: 1,
        nativePixels: CGSize(width: 2560, height: 1440), sizeMM: CGSize(width: 602, height: 329), name: "HDMI",
        frame: CGRect(x: -252, y: -1440, width: 2560, height: 1440), rotation: 0, isBuiltIn: false, isMain: false,
        mirrors: nil)

    /// The strip the wch.cn touchscreen sits on, below. It reports 240 × 90 mm, 10.1″; it is really 12.3″.
    static let strip = DisplayFacts(
        displayID: 4, uuid: "2D1E0123-0000-0000-1A21-0103802D1A78", vendor: 0x2d1e, model: 0x0123, serial: 0,
        nativePixels: CGSize(width: 1920, height: 720), sizeMM: CGSize(width: 240, height: 90), name: "12.3FHD",
        frame: CGRect(x: 228, y: 1329, width: 1600, height: 600), rotation: 0, isBuiltIn: false, isMain: false,
        mirrors: nil)

    /// The 18″ monitor, to the left. It reports 388 × 242 mm.
    static let display = DisplayFacts(
        displayID: 5, uuid: "3A495678-0000-0000-0F22-0104A5271878", vendor: 0x3a49, model: 0x5678, serial: 1,
        nativePixels: CGSize(width: 2560, height: 1600), sizeMM: CGSize(width: 388, height: 242), name: "Display",
        frame: CGRect(x: -2048, y: 24, width: 2048, height: 1280), rotation: 0, isBuiltIn: false, isMain: false,
        mirrors: nil)

    static let all = [builtIn, lg, hdmi, strip, display]
}

private let ilitek = TouchscreenIdentity.baseID(vendorID: 0x222a, productID: 0x0001, serial: "V06.00.00.00")
private let wch = TouchscreenIdentity.baseID(vendorID: 0x27c0, productID: 0x0859, serial: "TEST-SERIAL-0001")
/// A third touchscreen, for tests that need one.
private let thirdScreen = TouchscreenIdentity.baseID(vendorID: 0x1234, productID: 0x5678, serial: "3")

private func resolve(
    _ pairings: [TouchscreenID: DisplayIdentity], _ connected: [DisplayFacts]
) -> [TouchscreenID: UInt32] {
    DisplayMatcher.resolve(pairings: pairings, connected: connected)
}

/// `display`'s identity, with another UUID.
private func identity(of display: DisplayFacts, uuid: String) -> DisplayIdentity {
    var identity = DisplayIdentity(display)
    identity.uuid = uuid
    return identity
}

/// `display` with `change` made to it.
private func changed(_ display: DisplayFacts, _ change: (inout DisplayFacts) -> Void) -> DisplayFacts {
    var display = display
    change(&display)
    return display
}

/// `display`, as another connected display of the same model: its own display ID and UUID, and its own
/// place in the arrangement.
private func twin(of display: DisplayFacts, displayID: UInt32, uuid: String) -> DisplayFacts {
    var twin = display
    twin.displayID = displayID
    twin.uuid = uuid
    twin.frame.origin.x += 10_000
    return twin
}

/// `items` in every rotation, and each of those reversed: every item comes first, and every two
/// items come in both orders.
private func rotationsAndReversals<T>(of items: [T]) -> [[T]] {
    let rotations = items.indices.map { Array(items[$0...] + items[..<$0]) }
    return rotations + rotations.map { $0.reversed() }
}

private func permutations<T>(of items: [T]) -> [[T]] {
    guard !items.isEmpty else { return [[]] }
    return items.indices.flatMap { index -> [[T]] in
        var rest = items
        let item = rest.remove(at: index)
        return permutations(of: rest).map { [item] + $0 }
    }
}

final class DisplayMatcherTests: XCTestCase {

    // MARK: - The brief's tests

    func testAUUIDMatchWins() {
        let answer = resolve([ilitek: DisplayIdentity(DeskDisplays.hdmi)], DeskDisplays.all)
        XCTAssertEqual(answer, [ilitek: DeskDisplays.hdmi.displayID])
    }

    func testAChangedUUIDFallsBackToAUniqueFingerprint() {
        let pairing = identity(of: DeskDisplays.hdmi, uuid: "00000000-1111-2222-3333-444444444444")
        XCTAssertTrue(pairing.hasSameFingerprint(as: DeskDisplays.hdmi))
        XCTAssertEqual(resolve([ilitek: pairing], DeskDisplays.all), [ilitek: DeskDisplays.hdmi.displayID])
    }

    func testTwoDisplaysWithOneFingerprintAreNeverGuessed() {
        let other = twin(of: DeskDisplays.hdmi, displayID: 6, uuid: "4C2D0E10-0000-0000-0A20-FFFFFFFFFFFF")
        XCTAssertTrue(DisplayIdentity(DeskDisplays.hdmi).hasSameFingerprint(as: other))
        let pairing = identity(of: DeskDisplays.hdmi, uuid: "00000000-1111-2222-3333-444444444444")

        XCTAssertEqual(resolve([ilitek: pairing], DeskDisplays.all + [other]), [:])
    }

    func testADisplayClaimedByUUIDIsNotOfferedByFingerprint() {
        let pairings = [
            ilitek: DisplayIdentity(DeskDisplays.hdmi),
            wch: identity(of: DeskDisplays.hdmi, uuid: "00000000-1111-2222-3333-444444444444"),
        ]
        XCTAssertEqual(resolve(pairings, DeskDisplays.all), [ilitek: DeskDisplays.hdmi.displayID])
    }

    func testTwoPairingsNeverShareADisplay() {
        let pairings = [
            ilitek: identity(of: DeskDisplays.hdmi, uuid: "00000000-1111-2222-3333-444444444444"),
            wch: identity(of: DeskDisplays.hdmi, uuid: "55555555-6666-7777-8888-999999999999"),
        ]
        XCTAssertEqual(resolve(pairings, DeskDisplays.all), [:])
    }

    func testTheBuiltInDisplayIsNeverAMatch() {
        XCTAssertEqual(resolve([ilitek: DisplayIdentity(DeskDisplays.builtIn)], DeskDisplays.all), [:])
        // Not by fingerprint either.
        let pairing = identity(of: DeskDisplays.builtIn, uuid: "00000000-1111-2222-3333-444444444444")
        XCTAssertEqual(resolve([ilitek: pairing], DeskDisplays.all), [:])
    }

    func testADisconnectedDisplayIsNoMatch() {
        let connected = DeskDisplays.all.filter { $0.displayID != DeskDisplays.hdmi.displayID }
        XCTAssertEqual(resolve([ilitek: DisplayIdentity(DeskDisplays.hdmi)], connected), [:])
        XCTAssertEqual(resolve([ilitek: DisplayIdentity(DeskDisplays.hdmi)], []), [:])
    }

    /// Two identical displays, each with its own touchscreen. The ILITEK is paired with "HDMI", the
    /// wch.cn with its twin. "HDMI" is off and the wch.cn is unplugged. The wch.cn's pairing must
    /// still be passed, though its touchscreen isn't connected: it is what claims the twin.
    func testARememberedTouchscreensPairingStillClaimsItsDisplay() {
        let twinOfHDMI = twin(of: DeskDisplays.hdmi, displayID: 6, uuid: "4C2D0E10-0000-0000-0A20-FFFFFFFFFFFF")
        let connected = DeskDisplays.all.filter { $0.displayID != DeskDisplays.hdmi.displayID } + [twinOfHDMI]
        let stored = [ilitek: DisplayIdentity(DeskDisplays.hdmi), wch: DisplayIdentity(twinOfHDMI)]

        // The wrong way: only the connected touchscreen's pairing. Its UUID is gone, the twin looks
        // unclaimed and has its fingerprint, so the ILITEK's touches would land on the wch.cn's display.
        XCTAssertEqual(resolve([ilitek: DisplayIdentity(DeskDisplays.hdmi)], connected), [ilitek: twinOfHDMI.displayID])

        // The right way: every stored pairing. The twin is the wch.cn's, so the ILITEK gets nothing,
        // and the wch.cn's answer isn't used while it is unplugged.
        XCTAssertEqual(resolve(stored, connected), [wch: twinOfHDMI.displayID])
    }

    // MARK: - More

    func testTheDesksTwoPairingsBothResolve() {
        let pairings = [ilitek: DisplayIdentity(DeskDisplays.hdmi), wch: DisplayIdentity(DeskDisplays.strip)]
        XCTAssertEqual(
            resolve(pairings, DeskDisplays.all),
            [ilitek: DeskDisplays.hdmi.displayID, wch: DeskDisplays.strip.displayID])
        XCTAssertEqual(resolve([:], DeskDisplays.all), [:])
    }

    func testAnIdentityKeepsEverythingButTheFingerprintIgnoresTheUUID() {
        let identity = DisplayIdentity(DeskDisplays.hdmi)
        XCTAssertEqual(identity.uuid, DeskDisplays.hdmi.uuid)
        XCTAssertEqual(identity.vendor, 0x4c2d)
        XCTAssertEqual(identity.model, 0x0e10)
        XCTAssertEqual(identity.serial, 1)
        XCTAssertEqual(identity.nativeWidth, 2560)
        XCTAssertEqual(identity.nativeHeight, 1440)

        var other = DeskDisplays.hdmi
        other.uuid = "another"
        other.displayID = 99
        other.name = "Another name"
        other.frame = CGRect(x: 5000, y: 5000, width: 1280, height: 720)
        other.sizeMM = .zero
        other.rotation = 90
        other.mirrors = 1
        XCTAssertTrue(identity.hasSameFingerprint(as: other))

        for change in [
            { (facts: inout DisplayFacts) in facts.vendor += 1 },
            { (facts: inout DisplayFacts) in facts.model += 1 },
            { (facts: inout DisplayFacts) in facts.serial += 1 },
            { (facts: inout DisplayFacts) in facts.nativePixels.width += 1 },
            { (facts: inout DisplayFacts) in facts.nativePixels.height += 1 },
        ] {
            var changed = DeskDisplays.hdmi
            change(&changed)
            XCTAssertFalse(identity.hasSameFingerprint(as: changed))
        }
    }

    func testAnIdentityCodesAndComesBack() throws {
        let identity = DisplayIdentity(DeskDisplays.strip)
        let data = try JSONEncoder().encode(identity)
        XCTAssertEqual(try JSONDecoder().decode(DisplayIdentity.self, from: data), identity)
    }

    /// A pairing's UUID names one connected display while its fingerprint is another's: the UUID wins,
    /// and the display it passed over stays free for others.
    func testAUUIDMatchBeatsAFingerprintMatchElsewhere() {
        var pairing = DisplayIdentity(DeskDisplays.hdmi)
        pairing.uuid = DeskDisplays.display.uuid
        XCTAssertEqual(resolve([ilitek: pairing], DeskDisplays.all), [ilitek: DeskDisplays.display.displayID])

        let byFingerprint = identity(of: DeskDisplays.hdmi, uuid: "00000000-1111-2222-3333-444444444444")
        XCTAssertEqual(
            resolve([ilitek: pairing, wch: byFingerprint], DeskDisplays.all),
            [ilitek: DeskDisplays.display.displayID, wch: DeskDisplays.hdmi.displayID])
    }

    /// An empty UUID, one that is only whitespace, or the all-zero one, identifies nothing: a pairing
    /// with one isn't matched to a display that has one too.
    func testAnEmptyUUIDIdentifiesNothing() {
        let notHDMI = DeskDisplays.all.filter { $0.displayID != DeskDisplays.hdmi.displayID }
        for noUUID in ["", " ", "\t\n", "00000000-0000-0000-0000-000000000000"] {
            let pairing = identity(of: DeskDisplays.hdmi, uuid: noUUID)
            // "12.3FHD" has no UUID either; its fingerprint is its own.
            let connected = notHDMI.map { display in
                changed(display) { if $0.displayID == DeskDisplays.strip.displayID { $0.uuid = noUUID } }
            }
            XCTAssertEqual(resolve([ilitek: pairing], connected), [:], noUUID.debugDescription)
        }
    }

    /// A pairing with no UUID goes straight to its fingerprint.
    func testAPairingWithNoUUIDCanStillMatchByAUniqueFingerprint() {
        for noUUID in ["", " ", "\t\n"] {
            let pairing = identity(of: DeskDisplays.hdmi, uuid: noUUID)
            XCTAssertEqual(
                resolve([ilitek: pairing], DeskDisplays.all), [ilitek: DeskDisplays.hdmi.displayID],
                noUUID.debugDescription)

            // Also when another connected display has no UUID either.
            let connected = DeskDisplays.all.map { display in
                changed(display) { if $0.displayID == DeskDisplays.strip.displayID { $0.uuid = noUUID } }
            }
            XCTAssertEqual(
                resolve([ilitek: pairing], connected), [ilitek: DeskDisplays.hdmi.displayID], noUUID.debugDescription)
        }
    }

    /// Two connected displays with no UUID, each paired: each pairing finds its own by fingerprint.
    func testTwoDisplaysWithNoUUIDAreNotConfused() {
        for noUUID in ["", " ", "\t\n"] {
            let hdmi = changed(DeskDisplays.hdmi) { $0.uuid = noUUID }
            let strip = changed(DeskDisplays.strip) { $0.uuid = noUUID }
            let connected = [DeskDisplays.builtIn, DeskDisplays.lg, hdmi, strip, DeskDisplays.display]
            XCTAssertEqual(
                resolve([ilitek: DisplayIdentity(hdmi), wch: DisplayIdentity(strip)], connected),
                [ilitek: hdmi.displayID, wch: strip.displayID], noUUID.debugDescription)
        }
    }

    /// A damaged settings file names one display for two touchscreens. Neither gets it, and a third
    /// touchscreen with its fingerprint doesn't either: by its UUID it belongs to one of the two.
    func testTwoPairingsWithOneUUIDGetNothing() {
        let both = [ilitek: DisplayIdentity(DeskDisplays.hdmi), wch: DisplayIdentity(DeskDisplays.hdmi)]
        XCTAssertEqual(resolve(both, DeskDisplays.all), [:])

        // The two differ in fingerprint: still neither, though one fingerprint fits.
        var unlike = DisplayIdentity(DeskDisplays.hdmi)
        unlike.serial = 2
        XCTAssertEqual(resolve([ilitek: DisplayIdentity(DeskDisplays.hdmi), wch: unlike], DeskDisplays.all), [:])

        let third = identity(of: DeskDisplays.hdmi, uuid: "00000000-1111-2222-3333-444444444444")
        XCTAssertEqual(resolve(both.merging([thirdScreen: third]) { $1 }, DeskDisplays.all), [:])

        // Other pairings are unaffected.
        XCTAssertEqual(
            resolve(both.merging([thirdScreen: DisplayIdentity(DeskDisplays.strip)]) { $1 }, DeskDisplays.all),
            [thirdScreen: DeskDisplays.strip.displayID])
    }

    /// Three pairings and two connected displays, all with one fingerprint and none by UUID: no match.
    func testThreePairingsAndTwoDisplaysOfOneFingerprintGetNothing() {
        let other = twin(of: DeskDisplays.hdmi, displayID: 6, uuid: "4C2D0E10-0000-0000-0A20-FFFFFFFFFFFF")
        let pairings = [
            ilitek: identity(of: DeskDisplays.hdmi, uuid: "A"),
            wch: identity(of: DeskDisplays.hdmi, uuid: "B"),
            thirdScreen: identity(of: DeskDisplays.hdmi, uuid: "C"),
        ]
        XCTAssertEqual(resolve(pairings, DeskDisplays.all + [other]), [:])

        // One of them by UUID: that one matches, and the other two can't share the one left.
        var byUUID = pairings
        byUUID[ilitek] = DisplayIdentity(other)
        XCTAssertEqual(resolve(byUUID, DeskDisplays.all + [other]), [ilitek: other.displayID])
    }

    /// Two connected displays report one UUID: it names neither, and a pairing with it doesn't fall
    /// back to a third display of its model elsewhere.
    func testAUUIDTwoConnectedDisplaysReportNamesNeither() {
        let pairing = DisplayIdentity(DeskDisplays.hdmi)
        var same = twin(of: DeskDisplays.hdmi, displayID: 6, uuid: DeskDisplays.hdmi.uuid)
        XCTAssertEqual(resolve([ilitek: pairing], DeskDisplays.all + [same]), [:])

        let twinElsewhere = twin(of: DeskDisplays.hdmi, displayID: 7, uuid: "4C2D0E10-0000-0000-0A20-EEEEEEEEEEEE")
        XCTAssertEqual(resolve([ilitek: pairing], DeskDisplays.all + [same, twinElsewhere]), [:])

        // The two differ in fingerprint, and the pairing's fits one of them: still neither.
        same.serial = 2
        XCTAssertEqual(resolve([ilitek: pairing], DeskDisplays.all + [same]), [:])

        // While a pairing names that UUID, neither is offered by fingerprint to another pairing.
        let elsewhere = identity(of: DeskDisplays.hdmi, uuid: "00000000-1111-2222-3333-444444444444")
        XCTAssertEqual(resolve([ilitek: pairing, wch: elsewhere], DeskDisplays.all + [same]), [:])

        // When no pairing names it, the fingerprint works as ever: one of the two has this one's.
        XCTAssertEqual(resolve([wch: elsewhere], DeskDisplays.all + [same]), [wch: DeskDisplays.hdmi.displayID])
    }

    /// One display listed twice, as no caller should: its UUID names neither entry, and the pairing
    /// doesn't fall back to another display of its model.
    func testADisplayListedTwiceIsNoMatch() {
        let pairing = DisplayIdentity(DeskDisplays.hdmi)
        XCTAssertEqual(resolve([ilitek: pairing], DeskDisplays.all + [DeskDisplays.hdmi]), [:])

        let twinElsewhere = twin(of: DeskDisplays.hdmi, displayID: 7, uuid: "4C2D0E10-0000-0000-0A20-EEEEEEEEEEEE")
        let byFingerprint = identity(of: DeskDisplays.hdmi, uuid: "00000000-1111-2222-3333-444444444444")
        XCTAssertEqual(resolve([ilitek: pairing], DeskDisplays.all + [DeskDisplays.hdmi, twinElsewhere]), [:])
        XCTAssertEqual(resolve([ilitek: byFingerprint], DeskDisplays.all + [DeskDisplays.hdmi, twinElsewhere]), [:])

        // One display ID given to two different displays: neither is a match, by UUID or by
        // fingerprint. Other displays are unaffected.
        var clash = DeskDisplays.lg
        clash.displayID = DeskDisplays.hdmi.displayID
        clash.uuid = "1E6D5B14-0000-0000-2B1F-FFFFFFFFFFFF"
        let pairings = [ilitek: DisplayIdentity(DeskDisplays.hdmi), wch: DisplayIdentity(DeskDisplays.strip)]
        XCTAssertEqual(resolve(pairings, DeskDisplays.all + [clash]), [wch: DeskDisplays.strip.displayID])
        let byFingerprints = [
            ilitek: identity(of: DeskDisplays.hdmi, uuid: "A"), wch: identity(of: DeskDisplays.lg, uuid: "B"),
        ]
        XCTAssertEqual(resolve(byFingerprints, [DeskDisplays.hdmi, clash]), [:])
    }

    /// A display that shows another's picture is still a display a touchscreen can sit on.
    func testAMirroringDisplayCanBeMatched() {
        var mirror = DeskDisplays.hdmi
        mirror.mirrors = DeskDisplays.builtIn.displayID
        mirror.frame = DeskDisplays.builtIn.frame
        let connected = [DeskDisplays.builtIn, DeskDisplays.lg, mirror, DeskDisplays.strip, DeskDisplays.display]
        XCTAssertEqual(resolve([ilitek: DisplayIdentity(DeskDisplays.hdmi)], connected), [ilitek: mirror.displayID])
        let byFingerprint = identity(of: DeskDisplays.hdmi, uuid: "00000000-1111-2222-3333-444444444444")
        XCTAssertEqual(resolve([ilitek: byFingerprint], connected), [ilitek: mirror.displayID])
    }

    /// The answer is the same whatever the order of `connected` and of the pairings. It never gives
    /// one display to two touchscreens, never the built-in one, and a touchscreen only the display
    /// its pairing names by UUID, or else one with its fingerprint.
    ///
    /// A dictionary's iteration order can't be chosen, so the pairings are given as a list, in every
    /// order, to `resolve(orderedPairings:connected:)`, which holds the algorithm; the public
    /// `resolve` forwards to it.
    func testTheAnswerDoesNotDependOnOrder() {
        let twinOfHDMI = twin(of: DeskDisplays.hdmi, displayID: 6, uuid: "4C2D0E10-0000-0000-0A20-FFFFFFFFFFFF")
        let displays = [DeskDisplays.builtIn, DeskDisplays.hdmi, DeskDisplays.strip, twinOfHDMI, DeskDisplays.display]
        let screens = [ilitek, wch, thirdScreen]
        // What each touchscreen can be paired with: nothing, or a display by its UUID, or with a UUID
        // that is gone.
        let paired = [DeskDisplays.hdmi, DeskDisplays.strip, twinOfHDMI, DeskDisplays.builtIn]
        let choices: [DisplayIdentity?] =
            [nil] + paired.flatMap { [DisplayIdentity($0), identity(of: $0, uuid: "gone \($0.displayID)")] }
        let orders = rotationsAndReversals(of: displays)

        var checked = 0, compared = 0
        for first in choices {
            for second in choices {
                for third in choices {
                    let list = zip(screens, [first, second, third]).compactMap { screen, choice in
                        choice.map { (screen, $0) }
                    }
                    let pairings = Dictionary(uniqueKeysWithValues: list)
                    let expected = DisplayMatcher.resolve(orderedPairings: list, connected: displays)
                    XCTAssertEqual(resolve(pairings, displays), expected, "\(pairings)")

                    XCTAssertEqual(Set(expected.values).count, expected.count, "one display twice: \(pairings)")
                    XCTAssertFalse(expected.values.contains(DeskDisplays.builtIn.displayID), "\(pairings)")
                    for (screen, displayID) in expected {
                        guard let pairing = pairings[screen], let display = displays.first(where: {
                            $0.displayID == displayID
                        }) else {
                            XCTFail("\(screen) got \(displayID): \(pairings)")
                            continue
                        }
                        let byUUID = display.uuid == pairing.uuid
                        let byFingerprint = !displays.contains { $0.uuid == pairing.uuid }
                            && pairing.hasSameFingerprint(as: display)
                        XCTAssertTrue(byUUID || byFingerprint, "\(screen) got \(displayID): \(pairings)")
                    }

                    for listOrder in permutations(of: list) {
                        for order in orders {
                            let answer = DisplayMatcher.resolve(orderedPairings: listOrder, connected: order)
                            XCTAssertEqual(
                                answer, expected, "\(listOrder.map { $0.0 }), \(order.map(\.displayID))")
                            compared += 1
                        }
                    }
                    checked += 1
                }
            }
        }
        XCTAssertEqual(checked, 729)
        // 1 set of no pairings, 24 of one, 192 of two in 2 orders, 512 of three in 6 orders: 3,481
        // orders of the pairings, each against 10 orders of `connected`.
        XCTAssertEqual(compared, 34_810)
    }

    /// A touchscreen listed twice, which only the list form can hold, gets no match and doesn't trap.
    /// Its entries still name their displays and count as rivals.
    func testATouchscreenListedTwiceGetsNoMatch() {
        let byFingerprint = identity(of: DeskDisplays.hdmi, uuid: "00000000-1111-2222-3333-444444444444")
        let cases: [([(TouchscreenID, DisplayIdentity)], [TouchscreenID: UInt32])] = [
            ([(ilitek, DisplayIdentity(DeskDisplays.hdmi)), (ilitek, DisplayIdentity(DeskDisplays.hdmi))], [:]),
            ([(ilitek, DisplayIdentity(DeskDisplays.hdmi)), (ilitek, DisplayIdentity(DeskDisplays.strip))], [:]),
            ([(ilitek, DisplayIdentity(DeskDisplays.hdmi)), (ilitek, byFingerprint)], [:]),
            // "HDMI" is named by UUID, so the other touchscreen can't have it by fingerprint.
            (
                [(ilitek, DisplayIdentity(DeskDisplays.hdmi)), (ilitek, DisplayIdentity(DeskDisplays.strip)),
                 (wch, byFingerprint)], [:]
            ),
            // Others are unaffected.
            (
                [(ilitek, DisplayIdentity(DeskDisplays.hdmi)), (ilitek, byFingerprint),
                 (wch, DisplayIdentity(DeskDisplays.strip))], [wch: DeskDisplays.strip.displayID]
            ),
        ]
        for (list, expected) in cases {
            for listOrder in permutations(of: list) {
                XCTAssertEqual(
                    DisplayMatcher.resolve(orderedPairings: listOrder, connected: DeskDisplays.all), expected,
                    "\(listOrder.map { "\($0.0): \($0.1.uuid)" })")
            }
        }
    }
}
