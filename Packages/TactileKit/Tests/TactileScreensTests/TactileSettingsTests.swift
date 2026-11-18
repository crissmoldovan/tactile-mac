import CoreGraphics
import Foundation
import TactileGestures
import XCTest
@testable import TactileScreens

// The desk's displays are `DeskDisplays`, in DisplayMatcherTests.swift.

private let hdmi = DisplayIdentity(DeskDisplays.hdmi)
private let strip = DisplayIdentity(DeskDisplays.strip)

/// The wch.cn touchscreen, on the strip.
private let wch = TouchscreenIdentity.baseID(vendorID: 0x27c0, productID: 0x0859, serial: "TEST-SERIAL-0001")

/// The rectangle calibration fitted for the wch.cn panel on the strip.
private let fitted = GlassAlignment(pictureRect: CGRect(x: 0.00989, y: 0.03187, width: 0.98022, height: 0.95844))

private func decode(_ json: String) throws -> TactileSettings {
    try JSONDecoder().decode(TactileSettings.self, from: Data(json.utf8))
}

/// Touchscreen settings with every behaviour field away from its default.
private func everyBehaviourChanged() -> TouchscreenSettings {
    var screen = TouchscreenSettings()
    screen.oneFinger = .alwaysScroll
    screen.pointerReturn = .staysWhereTouched
    screen.showsCircles = false
    screen.gestures.pinch = false
    screen.gestures.swipes = false
    screen.rejection = RejectionRules(palm: false, edgeMarginMM: 4)
    screen.whenOff = .leaveToMacOS
    return screen
}

/// Touchscreen settings with every field that isn't behaviour away from its default.
private func everythingButBehaviourChanged() -> TouchscreenSettings {
    var screen = TouchscreenSettings()
    screen.customName = "Strip"
    screen.lastSeenName = "wch.cn TouchScreen"
    screen.isOn = false
    screen.pairing = Pairing(display: strip, orientation: Orientation(quarterTurns: 1, isFlipped: true), alignment: fitted,
                             displayName: "12.3FHD")
    screen.diagonalInches = 12.3
    screen.wasOfferedSetUp = true
    return screen
}

/// A file as version 1 was first written, by Tactile 0.2.0, by hand. Every choice of every setting
/// 0.2.0 had is spelled out in it once, the defaults included, so renaming a choice breaks the tests
/// that read it.
private let version1File = """
    {
      "debugLogging" : true,
      "displayNames" : { "2D1E0123-0000-0000-1A21-0103802D1A78" : "Strip" },
      "isOn" : false,
      "recordsFrames" : true,
      "touchscreens" : {
        "1234:5678:3" : {
          "oneFinger" : "alwaysDrag"
        },
        "222a:0001:V06.00.00.00" : {
          "lastSeenName" : "ILITEK-TP",
          "oneFinger" : "automatic",
          "pointerReturn" : "backWhereItWas",
          "whenOff" : "ignoreTouches"
        },
        "27c0:0859:TEST-SERIAL-0001" : {
          "customName" : "Strip",
          "diagonalInches" : 12.3,
          "gestures" : { "pinch" : false, "swipes" : false, "twoFingerScroll" : true, "twoFingerTap" : true },
          "isOn" : false,
          "lastSeenName" : "wch.cn TouchScreen",
          "oneFinger" : "alwaysScroll",
          "pairing" : {
            "alignment" : { "pictureRect" : [ [ 0.00989, 0.03187 ], [ 0.98022, 0.95844 ] ] },
            "display" : {
              "model" : 291, "nativeHeight" : 720, "nativeWidth" : 1920, "serial" : 0,
              "uuid" : "2D1E0123-0000-0000-1A21-0103802D1A78", "vendor" : 11550
            },
            "orientation" : { "isFlipped" : true, "quarterTurns" : 1 }
          },
          "pointerReturn" : "staysWhereTouched",
          "showsCircles" : false,
          "whenOff" : "leaveToMacOS"
        }
      },
      "version" : 1
    }
    """

final class TactileSettingsTests: XCTestCase {

    // MARK: - The brief's table

    func testDefaults() {
        let screen = TouchscreenSettings()
        XCTAssertNil(screen.customName)
        XCTAssertEqual(screen.lastSeenName, "")
        XCTAssertTrue(screen.isOn)
        XCTAssertEqual(screen.whenOff, .ignoreTouches)
        XCTAssertNil(screen.pairing)
        XCTAssertNil(screen.diagonalInches)
        XCTAssertNil(screen.oneFinger, "the default for the touchscreen")
        XCTAssertEqual(screen.pointerReturn, .backWhereItWas)
        XCTAssertTrue(screen.showsCircles)
        XCTAssertEqual(screen.gestures, .all)
        XCTAssertEqual(screen.rejection, RejectionRules())
        XCTAssertEqual(screen.rejection, RejectionRules(palm: true, edgeMarginMM: 0), "palm on, no edge margin")
        XCTAssertFalse(screen.wasOfferedSetUp)

        let settings = TactileSettings()
        XCTAssertEqual(TactileSettings.currentVersion, 1)
        XCTAssertEqual(settings.version, 1)
        XCTAssertTrue(settings.isOn)
        XCTAssertEqual(settings.touchscreens, [:])
        XCTAssertEqual(settings.displayNames, [:])
        XCTAssertFalse(settings.debugLogging)
        XCTAssertFalse(settings.recordsFrames)
        XCTAssertFalse(settings.swipesFollowFingers, "experimental, and off unless switched on")

        XCTAssertEqual(WhenOff.allCases, [.ignoreTouches, .leaveToMacOS])
        let pairing = Pairing(display: hdmi)
        XCTAssertEqual(pairing.display, hdmi)
        XCTAssertEqual(pairing.orientation, .asFitted)
        XCTAssertEqual(pairing.alignment, .wholeGlass)
        XCTAssertEqual(pairing.displayName, "")
    }

    func testAFileWithOnlyOneFieldLoadsWithEveryDefault() throws {
        let settings = try decode(#"{"version":1,"touchscreens":{"27c0:0859:X":{"isOn":false}}}"#)
        let id = TouchscreenID(rawValue: "27c0:0859:X")
        var off = TouchscreenSettings()
        off.isOn = false
        var expected = TactileSettings()
        expected.touchscreens = [id: off]
        XCTAssertEqual(settings, expected)
        XCTAssertEqual(settings.touchscreens[id]?.isOn, false)
        XCTAssertEqual(settings.touchscreens[id]?.gestures, .all)
    }

    func testPairingWithTheSameDisplayKeepsTheFit() {
        var screen = TouchscreenSettings()
        screen.pair(with: hdmi)
        XCTAssertEqual(screen.pairing, Pairing(display: hdmi))
        screen.pairing?.orientation = Orientation(quarterTurns: 2, isFlipped: true)
        screen.pairing?.alignment = fitted
        screen.pair(with: hdmi)
        XCTAssertEqual(screen.pairing?.display, hdmi)
        XCTAssertEqual(screen.pairing?.orientation, Orientation(quarterTurns: 2, isFlipped: true))
        XCTAssertEqual(screen.pairing?.alignment, fitted)
    }

    func testPairingWithAnotherDisplayStartsAfresh() {
        var screen = TouchscreenSettings()
        screen.pair(with: hdmi)
        screen.pairing?.orientation = Orientation(quarterTurns: 2, isFlipped: true)
        screen.pairing?.alignment = fitted
        screen.pair(with: strip)
        XCTAssertEqual(screen.pairing, Pairing(display: strip))
        XCTAssertEqual(screen.pairing?.orientation, .asFitted)
        XCTAssertEqual(screen.pairing?.alignment, .wholeGlass)

        // Another display is any other identity: here the same UUID with another serial.
        screen.pairing?.alignment = fitted
        var sameUUID = strip
        sameUUID.serial = 2
        screen.pair(with: sameUUID)
        XCTAssertEqual(screen.pairing, Pairing(display: sameUUID))

        screen.unpair()
        XCTAssertNil(screen.pairing)
    }

    /// The remembered display name is only a name: which display a pairing means is its identity
    /// alone. Pairing again with the same display keeps the fit whatever name is remembered, and
    /// another display forgets the name with the fit.
    func testTheRememberedDisplayNameIsNotPartOfWhichDisplay() {
        var screen = TouchscreenSettings()
        screen.pair(with: hdmi)
        screen.pairing?.orientation = Orientation(quarterTurns: 2, isFlipped: true)
        screen.pairing?.alignment = fitted
        screen.pairing?.displayName = "HDMI"
        let named = screen.pairing

        // The display was renamed since: the same display, so the fit and the name stay.
        var renamed = screen
        renamed.pairing?.displayName = "Studio Display"
        renamed.pair(with: hdmi)
        XCTAssertEqual(renamed.pairing?.display, named?.display)
        XCTAssertEqual(renamed.pairing?.orientation, Orientation(quarterTurns: 2, isFlipped: true))
        XCTAssertEqual(renamed.pairing?.alignment, fitted)
        XCTAssertEqual(renamed.pairing?.displayName, "Studio Display")

        screen.pair(with: hdmi)
        XCTAssertEqual(screen.pairing, named)

        // Another display starts afresh, its name with it.
        screen.pair(with: strip)
        XCTAssertEqual(screen.pairing, Pairing(display: strip))
        XCTAssertEqual(screen.pairing?.displayName, "")
    }

    func testCopyAndResetTouchOnlyBehaviour() {
        let source = everyBehaviourChanged()
        let original = everythingButBehaviourChanged()

        var copy = original
        copy.copyBehaviour(from: source)
        var expected = source
        expected.customName = original.customName
        expected.lastSeenName = original.lastSeenName
        expected.isOn = original.isOn
        expected.pairing = original.pairing
        expected.diagonalInches = original.diagonalInches
        expected.wasOfferedSetUp = original.wasOfferedSetUp
        XCTAssertEqual(copy, expected)
        XCTAssertEqual(copy.rejection, RejectionRules(palm: false, edgeMarginMM: 4), "rejection is behaviour")

        // Copying takes nothing but behaviour from the other: its name, pairing, on, diagonal and
        // whether set-up was offered stay this one's.
        var other = everythingButBehaviourChanged()
        other.copyBehaviour(from: TouchscreenSettings())
        XCTAssertEqual(other, original)

        var reset = copy
        reset.resetBehaviour()
        XCTAssertEqual(reset, original)
    }

    func testDisplayNamePrefersTheCustomOne() {
        var screen = TouchscreenSettings()
        screen.lastSeenName = "TouchScreen"
        screen.customName = "Strip"
        XCTAssertEqual(screen.displayName, "Strip")
        screen.customName = ""
        XCTAssertEqual(screen.displayName, "TouchScreen")
        screen.customName = nil
        XCTAssertEqual(screen.displayName, "TouchScreen")

        // Trimmed, as a display's custom name is in `DisplayLabel`.
        screen.customName = "  Strip \n"
        XCTAssertEqual(screen.displayName, "Strip")
        screen.customName = " \t\n"
        XCTAssertEqual(screen.displayName, "TouchScreen")
    }

    // MARK: - Reading what a file holds

    /// The 0.2.0 file: every later version must read it to exactly this.
    func testAVersion1FileLoadsInFull() throws {
        let settings = try decode(version1File)
        var screen = everythingButBehaviourChanged()
        screen.copyBehaviour(from: everyBehaviourChanged())
        // Fields that came after 0.2.0 aren't in the file: each is at its default.
        screen.rejection = RejectionRules()
        screen.wasOfferedSetUp = false
        screen.pairing?.displayName = ""
        var dragging = TouchscreenSettings()
        dragging.oneFinger = .alwaysDrag
        var ilitek = TouchscreenSettings()
        ilitek.lastSeenName = "ILITEK-TP"
        ilitek.oneFinger = nil  // "automatic" in a file of 0.4.0 or earlier: the default
        ilitek.pointerReturn = .backWhereItWas
        ilitek.whenOff = .ignoreTouches
        var expected = TactileSettings()
        expected.isOn = false
        expected.debugLogging = true
        expected.recordsFrames = true
        expected.displayNames = [strip.uuid: "Strip"]
        expected.touchscreens = [
            wch: screen, TouchscreenID(rawValue: "222a:0001:V06.00.00.00"): ilitek,
            TouchscreenID(rawValue: "1234:5678:3"): dragging,
        ]
        XCTAssertEqual(settings, expected)
    }

    /// Review Focus 6: a 0.2.0 file loads; every touchscreen keeps its pairing and orientation, and
    /// what came after 0.2.0 is at its default: rejection, set-up not yet offered, no display name.
    func testA020FileLoadsWithEveryNewFieldAtItsDefault() throws {
        let settings = try decode(version1File)
        XCTAssertEqual(settings.touchscreens.count, 3)
        for (id, screen) in settings.touchscreens {
            XCTAssertEqual(screen.rejection, RejectionRules(), "\(id)")
            XCTAssertFalse(screen.wasOfferedSetUp, "\(id)")
            XCTAssertEqual(screen.pairing?.displayName ?? "", "", "\(id)")
        }
        let stripPairing = try XCTUnwrap(settings.touchscreens[wch]?.pairing)
        XCTAssertEqual(stripPairing.display, strip)
        XCTAssertEqual(stripPairing.orientation, Orientation(quarterTurns: 1, isFlipped: true))
        XCTAssertEqual(stripPairing.alignment, fitted)
        XCTAssertFalse(settings.swipesFollowFingers)
    }

    /// A file as Tactile 0.3.0 writes it, by hand, every field of its format in it: it loads in
    /// full, and swipes don't follow the fingers until the person says so.
    func testA030FileLoadsInFullWithSwipesNotFollowingTheFingers() throws {
        let settings = try decode(
            """
            {
              "debugLogging" : false,
              "displayNames" : { },
              "isOn" : true,
              "recordsFrames" : false,
              "touchscreens" : {
                "27c0:0859:TEST-SERIAL-0001" : {
                  "customName" : "Strip",
                  "diagonalInches" : 12.3,
                  "gestures" : {
                    "longPress" : false, "pinch" : false, "rotate" : false, "swipes" : false,
                    "twoFingerScroll" : true, "twoFingerTap" : true
                  },
                  "isOn" : false,
                  "lastSeenName" : "wch.cn TouchScreen",
                  "oneFinger" : "alwaysScroll",
                  "pairing" : {
                    "alignment" : { "pictureRect" : [ [ 0.00989, 0.03187 ], [ 0.98022, 0.95844 ] ] },
                    "display" : {
                      "model" : 291, "nativeHeight" : 720, "nativeWidth" : 1920, "serial" : 0,
                      "uuid" : "2D1E0123-0000-0000-1A21-0103802D1A78", "vendor" : 11550
                    },
                    "displayName" : "12.3FHD",
                    "orientation" : { "isFlipped" : true, "quarterTurns" : 1 }
                  },
                  "pointerReturn" : "staysWhereTouched",
                  "rejection" : { "edgeMarginMM" : 4, "palm" : false },
                  "showsCircles" : false,
                  "wasOfferedSetUp" : true,
                  "whenOff" : "leaveToMacOS"
                }
              },
              "version" : 1
            }
            """)
        var screen = everythingButBehaviourChanged()
        screen.copyBehaviour(from: everyBehaviourChanged())
        screen.gestures.longPress = false
        screen.gestures.rotate = false
        var expected = TactileSettings()
        expected.touchscreens = [wch: screen]
        XCTAssertEqual(settings, expected)
        XCTAssertFalse(settings.swipesFollowFingers)
    }

    func testAMissingOrNullFieldTakesItsDefault() throws {
        XCTAssertEqual(try decode("{}"), TactileSettings())
        XCTAssertEqual(try decode(#"{"touchscreens":{"A":{}}}"#).touchscreens, [TouchscreenID(rawValue: "A"): TouchscreenSettings()])

        let nulls = try decode(
            #"{"version":null,"isOn":null,"touchscreens":null,"displayNames":null,"debugLogging":null,"recordsFrames":null,"#
                + #""swipesFollowFingers":null}"#)
        XCTAssertEqual(nulls, TactileSettings())
        let screenNulls = try decode(
            #"{"touchscreens":{"A":{"customName":null,"lastSeenName":null,"isOn":null,"whenOff":null,"pairing":null,"#
                + #""diagonalInches":null,"oneFinger":null,"pointerReturn":null,"showsCircles":null,"gestures":null,"#
                + #""rejection":null,"wasOfferedSetUp":null}}}"#)
        XCTAssertEqual(screenNulls.touchscreens, [TouchscreenID(rawValue: "A"): TouchscreenSettings()])

        // A pairing with only its display is as fitted, on the whole glass.
        let display = try String(decoding: JSONEncoder().encode(hdmi), as: UTF8.self)
        let paired = try decode(#"{"touchscreens":{"A":{"pairing":{"display":"# + display + "}}}}")
        XCTAssertEqual(paired.touchscreens[TouchscreenID(rawValue: "A")]?.pairing, Pairing(display: hdmi))
        let unnamed = try decode(#"{"touchscreens":{"A":{"pairing":{"displayName":null,"display":"# + display + "}}}}")
        XCTAssertEqual(unnamed.touchscreens[TouchscreenID(rawValue: "A")]?.pairing, Pairing(display: hdmi))

        // Rejection missing a rule keeps that rule's default.
        let rejection = try decode(#"{"touchscreens":{"A":{"rejection":{"edgeMarginMM":5}}}}"#)
        XCTAssertEqual(rejection.touchscreens[TouchscreenID(rawValue: "A")]?.rejection, RejectionRules(palm: true, edgeMarginMM: 5))

        // Gestures missing some switches keep those on.
        let gestures = try decode(#"{"touchscreens":{"A":{"gestures":{"pinch":false}}}}"#)
        var pinchOff = GestureOptions.all
        pinchOff.pinch = false
        XCTAssertEqual(gestures.touchscreens[TouchscreenID(rawValue: "A")]?.gestures, pinchOff)
    }

    func testAFileWithoutAVersionIsTheFirstAndAnOlderNumberStillLoads() throws {
        XCTAssertEqual(try decode(#"{"isOn":false}"#).version, 1)
        XCTAssertEqual(try decode(#"{"version":0,"isOn":false}"#).version, 0)
        XCTAssertEqual(try decode(#"{"version":-3,"isOn":false}"#).isOn, false)
    }

    func testUnknownFieldsAreIgnored() throws {
        let display = try String(decoding: JSONEncoder().encode(hdmi), as: UTF8.self)
        let settings = try decode(
            #"{"version":1,"launchAtLogin":true,"future":{"a":[1,null,"x"]},"touchscreens":{"A":{"palmRejection":true,"#
                + #""edgeMargin":4.5,"gestures":{"threeFingerDrag":false,"pinch":false},"pairing":{"note":"x","display":"#
                + display.dropLast() + #","edid":"00ff"},"orientation":{"quarterTurns":1,"isFlipped":false,"tilt":3},"#
                + #""alignment":{"pictureRect":[[0,0],[1,1]],"skew":0}}}}}"#)
        var screen = TouchscreenSettings()
        screen.gestures.pinch = false
        screen.pairing = Pairing(display: hdmi, orientation: Orientation(quarterTurns: 1, isFlipped: false))
        var expected = TactileSettings()
        expected.touchscreens = [TouchscreenID(rawValue: "A"): screen]
        XCTAssertEqual(settings, expected)
    }

    /// A value that is there but isn't one this version can read is not taken for the default: the
    /// file can't be decoded, and the store sets it aside whole.
    func testAValueThisVersionCannotReadIsAnError() {
        let display = #"{"uuid":"U","vendor":1,"model":2,"serial":3,"nativeWidth":4,"nativeHeight":5}"#
        let unreadable = [
            "null", "[]", #""settings""#, "5",
            #"{"version":"1"}"#, #"{"version":1.5}"#, #"{"version":1e400}"#, #"{"isOn":"yes"}"#, #"{"isOn":1}"#,
            #"{"swipesFollowFingers":"on"}"#, #"{"swipesFollowFingers":1}"#,
            #"{"touchscreens":[]}"#, #"{"touchscreens":"none"}"#,
            #"{"touchscreens":{"A":null}}"#, #"{"touchscreens":{"A":"on"}}"#, #"{"touchscreens":{"A":[]}}"#,
            #"{"touchscreens":{"A":{"isOn":"no"}}}"#, #"{"touchscreens":{"A":{"customName":5}}}"#,
            #"{"touchscreens":{"A":{"diagonalInches":"23.8"}}}"#, #"{"touchscreens":{"A":{"oneFinger":"alwaysClick"}}}"#,
            #"{"touchscreens":{"A":{"whenOff":"sleep"}}}"#, #"{"touchscreens":{"A":{"pointerReturn":true}}}"#,
            #"{"touchscreens":{"A":{"gestures":{"pinch":"off"}}}}"#, #"{"touchscreens":{"A":{"gestures":[]}}}"#,
            #"{"displayNames":{"U":1}}"#, #"{"displayNames":["U"]}"#,
            #"{"touchscreens":{"A":{"wasOfferedSetUp":"no"}}}"#, #"{"touchscreens":{"A":{"rejection":[]}}}"#,
            #"{"touchscreens":{"A":{"rejection":{"palm":"on"}}}}"#, #"{"touchscreens":{"A":{"rejection":{"edgeMarginMM":"4"}}}}"#,
            #"{"touchscreens":{"A":{"pairing":{"display":"# + display + #","displayName":5}}}}"#,
            // A pairing without its display, or with part of one: there's no display to default to.
            #"{"touchscreens":{"A":{"pairing":{}}}}"#,
            #"{"touchscreens":{"A":{"pairing":{"orientation":{"quarterTurns":1,"isFlipped":false}}}}}"#,
            #"{"touchscreens":{"A":{"pairing":{"display":{"uuid":"U","vendor":1,"model":2,"nativeWidth":4,"nativeHeight":5}}}}}"#,
            #"{"touchscreens":{"A":{"pairing":{"display":null}}}}"#,
            // Half an orientation or an alignment isn't guessed either.
            #"{"touchscreens":{"A":{"pairing":{"display":"# + display + #","orientation":{"quarterTurns":1}}}}}"#,
            #"{"touchscreens":{"A":{"pairing":{"display":"# + display + #","alignment":{}}}}}"#,
            #"{"touchscreens":{"A":{"pairing":{"display":"# + display + #","alignment":{"pictureRect":[0,0,1,1]}}}}}"#,
        ]
        for json in unreadable {
            XCTAssertThrowsError(try decode(json), json)
        }
    }

    func testAFileFromANewerVersionIsRefusedWhateverElseItHolds() {
        XCTAssertThrowsError(try decode(#"{"version":2}"#))
        XCTAssertThrowsError(try decode(#"{"version":2,"isOn":false,"touchscreens":{}}"#))
        XCTAssertThrowsError(try decode(#"{"version":9223372036854775807}"#))
    }

    // MARK: - Numbers JSON can't hold

    /// A diagonal that isn't finite is no diagonal, which is what `SurfaceSize` already makes of it.
    /// It is stopped when it is set, so the settings always say what the file will.
    func testADiagonalThatIsNotFiniteIsNoOverride() {
        for value in [Double.nan, -.nan, .signalingNaN, .infinity, -.infinity] {
            var screen = TouchscreenSettings()
            screen.diagonalInches = 23.8
            screen.diagonalInches = value
            XCTAssertNil(screen.diagonalInches, "\(value)")
        }
        // Finite values are kept as given, even those `SurfaceSize` ignores.
        for value in [0, -0.0, -12.3, 1e-300, .greatestFiniteMagnitude] {
            var screen = TouchscreenSettings()
            screen.diagonalInches = value
            XCTAssertEqual(screen.diagonalInches, value)
        }
    }

    /// A decoder that reads "inf" and "nan" as numbers can give a diagonal that isn't finite. It is
    /// no diagonal, as when one is set.
    func testADecodedDiagonalThatIsNotFiniteIsNoOverride() throws {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        let id = TouchscreenID(rawValue: "A")
        for value in ["inf", "-inf", "nan"] {
            let json = #"{"touchscreens":{"A":{"diagonalInches":"\#(value)"}}}"#
            let settings = try decoder.decode(TactileSettings.self, from: Data(json.utf8))
            XCTAssertNil(settings.touchscreens[id]?.diagonalInches, value)
            XCTAssertEqual(settings.touchscreens[id], TouchscreenSettings(), value)
        }
        let finite = try decoder.decode(TactileSettings.self, from: Data(#"{"touchscreens":{"A":{"diagonalInches":23.8}}}"#.utf8))
        XCTAssertEqual(finite.touchscreens[id]?.diagonalInches, 23.8)
    }

    /// An alignment with a number that isn't finite is the whole glass, which is what `TouchMapping`
    /// already makes of it; however it is set.
    func testAnAlignmentThatIsNotFiniteIsTheWholeGlass() {
        let unfinished: [CGRect] = [
            CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1), CGRect(x: 0, y: CGFloat.infinity, width: 1, height: 1),
            CGRect(x: 0, y: 0, width: CGFloat.nan, height: 1), CGRect(x: 0, y: 0, width: 1, height: -CGFloat.infinity),
            .null,
        ]
        for rect in unfinished {
            XCTAssertEqual(Pairing(display: hdmi, alignment: GlassAlignment(pictureRect: rect)).alignment, .wholeGlass, "\(rect)")

            var pairing = Pairing(display: hdmi, alignment: fitted)
            pairing.alignment = GlassAlignment(pictureRect: rect)
            XCTAssertEqual(pairing.alignment, .wholeGlass, "\(rect)")

            var screen = TouchscreenSettings()
            screen.pairing = Pairing(display: hdmi, alignment: fitted)
            screen.pairing?.alignment.pictureRect = rect
            XCTAssertEqual(screen.pairing?.alignment, .wholeGlass, "\(rect)")
        }
        // One number changed in place, deep inside the settings.
        var settings = TactileSettings()
        settings.touchscreens[wch] = everythingButBehaviourChanged()
        settings.touchscreens[wch]?.pairing?.alignment.pictureRect.size.width = .nan
        XCTAssertEqual(settings.touchscreens[wch]?.pairing?.alignment, .wholeGlass)
        settings.touchscreens[wch]?.pairing?.alignment = fitted
        settings.touchscreens[wch]?.pairing?.alignment.pictureRect.origin.y = -.infinity
        XCTAssertEqual(settings.touchscreens[wch]?.pairing?.alignment, .wholeGlass)
        settings.touchscreens[wch]?.diagonalInches = .nan
        XCTAssertNil(settings.touchscreens[wch]?.diagonalInches)
        // Finite rectangles are kept as given, even those `TouchMapping` doesn't use.
        for rect in [CGRect(x: 0, y: 0, width: -1, height: 0), .infinite, fitted.pictureRect] {
            XCTAssertEqual(Pairing(display: hdmi, alignment: GlassAlignment(pictureRect: rect)).alignment.pictureRect, rect)
        }
    }

    // MARK: - The one-finger choice (0.5.0)

    func testTheOneFingerChoiceIsTheDefaultUntilOneIsMade() throws {
        XCTAssertNil(TouchscreenSettings().oneFinger)
        // A file of 0.4.0 or earlier: "automatic" was the default and a choice of Automatic alike.
        let old = try decode(#"{"touchscreens":{"A":{"oneFinger":"automatic"}}}"#)
        XCTAssertNil(old.touchscreens[TouchscreenID(rawValue: "A")]?.oneFinger, "read as the default")
        // Any other value is the choice it names, with the flag or without.
        for mode in [OneFingerMode.alwaysDrag, .alwaysScroll] {
            let without = try decode(#"{"touchscreens":{"A":{"oneFinger":""# + mode.rawValue + #""}}}"#)
            XCTAssertEqual(without.touchscreens[TouchscreenID(rawValue: "A")]?.oneFinger, mode)
            let with = try decode(#"{"touchscreens":{"A":{"oneFinger":""# + mode.rawValue + #"","oneFingerChosen":true}}}"#)
            XCTAssertEqual(with.touchscreens[TouchscreenID(rawValue: "A")]?.oneFinger, mode)
        }
        // A choice of Automatic, written by 0.5.0, with its flag.
        let chosen = try decode(#"{"touchscreens":{"A":{"oneFinger":"automatic","oneFingerChosen":true}}}"#)
        XCTAssertEqual(chosen.touchscreens[TouchscreenID(rawValue: "A")]?.oneFinger, .automatic)
        let notChosen = try decode(#"{"touchscreens":{"A":{"oneFinger":"automatic","oneFingerChosen":false}}}"#)
        XCTAssertNil(notChosen.touchscreens[TouchscreenID(rawValue: "A")]?.oneFinger)
        // The flag of the wrong type is damage, as any field of the wrong type is.
        XCTAssertThrowsError(try decode(#"{"touchscreens":{"A":{"oneFinger":"automatic","oneFingerChosen":"yes"}}}"#))
    }

    func testEveryOneFingerChoiceAndTheDefaultRoundTrip() throws {
        for choice in [nil] + OneFingerMode.allCases.map(Optional.some) {
            var settings = TactileSettings()
            settings.touchscreens[wch] = with(TouchscreenSettings()) { $0.oneFinger = choice }
            let data = try JSONEncoder().encode(settings)
            XCTAssertEqual(try JSONDecoder().decode(TactileSettings.self, from: data), settings, "\(String(describing: choice))")
            let screen = try XCTUnwrap(
                (JSONSerialization.jsonObject(with: data) as? [String: Any])?["touchscreens"] as? [String: [String: Any]])[wch.rawValue]
            XCTAssertEqual(screen?["oneFinger"] as? String, choice?.rawValue, "\(String(describing: choice))")
            XCTAssertEqual(screen?["oneFingerChosen"] as? Bool, choice.map { _ in true }, "\(String(describing: choice))")
        }
    }

    /// Fix round 1, item 6: whether a touchscreen last gave one finger, an optional key: left out
    /// while unknown, read back as written, missing in a file of 0.4.0 or earlier; a fact of the
    /// device, so copying and resetting the behaviour leave it.
    func testWhetherATouchscreenLastGaveOneFingerIsKept() throws {
        XCTAssertNil(TouchscreenSettings().lastGaveOneFinger)
        XCTAssertNil(try decode(version1File).touchscreens[wch]?.lastGaveOneFinger)
        for value in [nil, true, false] as [Bool?] {
            var settings = TactileSettings()
            settings.touchscreens[wch] = with(TouchscreenSettings()) { $0.lastGaveOneFinger = value }
            let data = try JSONEncoder().encode(settings)
            XCTAssertEqual(try JSONDecoder().decode(TactileSettings.self, from: data), settings)
            let screen = try XCTUnwrap(
                (JSONSerialization.jsonObject(with: data) as? [String: Any])?["touchscreens"] as? [String: [String: Any]])[wch.rawValue]
            XCTAssertEqual(screen?["lastGaveOneFinger"] as? Bool, value, "\(String(describing: value))")
            XCTAssertEqual(screen?.keys.contains("lastGaveOneFinger"), value != nil)
        }
        XCTAssertThrowsError(try decode(#"{"touchscreens":{"A":{"lastGaveOneFinger":"yes"}}}"#), "of the wrong type: damage")
        var screen = TouchscreenSettings()
        screen.lastGaveOneFinger = true
        screen.copyBehaviour(from: TouchscreenSettings())
        XCTAssertEqual(screen.lastGaveOneFinger, true)
        screen.resetBehaviour()
        XCTAssertEqual(screen.lastGaveOneFinger, true)
    }

    func testCopyAndResetCarryTheOneFingerChoice() {
        var source = TouchscreenSettings()
        source.oneFinger = .automatic
        var target = TouchscreenSettings()
        target.copyBehaviour(from: source)
        XCTAssertEqual(target.oneFinger, .automatic, "a choice of Automatic is carried as a choice")
        target.copyBehaviour(from: TouchscreenSettings())
        XCTAssertNil(target.oneFinger, "the default is carried as the default: each touchscreen's own")
        target.oneFinger = .alwaysDrag
        target.resetBehaviour()
        XCTAssertNil(target.oneFinger, "reset: the default")
    }
}

/// `value` with `change` made to it.
private func with<Value>(_ value: Value, _ change: (inout Value) -> Void) -> Value {
    var value = value
    change(&value)
    return value
}
