// The real desk, as the model and the pipelines see it: five displays and two touchscreens.
//
// Frames are in points, origin at the top-left of the main display, y growing downwards, as
// `DisplayFacts` has them. The displays are those of the design's *The desk today*, with origins
// that fit their labels: "HDMI" above the main display, "12.3FHD" below it, "LG HDR 4K" to the
// right and "Display" to the left. The same values as `DeskDisplays` in TactileScreensTests.

import CoreGraphics
import Foundation
import TactileApp
import TactileDevices
import TactileGestures
import TactileScreens

enum DeskFixture {

    /// While true, every behaviour that came after 0.2.0 is off in what the fixtures make: long-press
    /// and rotate in their gestures, and no rejection rules. The 2b suites run a second time with it
    /// on (`TouchPipelineTestsWithNewOptionsOff`, `TactileModelTestsWithNewOptionsOff`), so 0.2.0's
    /// behaviour is still what they test. Set by those suites' `setUp`, cleared by their `tearDown`.
    static var newOptionsOff = false

    /// `options` with long-press and rotate off while `newOptionsOff`.
    static func asConfigured(_ options: GestureOptions) -> GestureOptions {
        guard newOptionsOff else { return options }
        var options = options
        options.longPress = false
        options.rotate = false
        return options
    }

    // MARK: - Displays

    /// The Mac's own display: main, at the origin.
    static let builtIn = DisplayFacts(
        displayID: 1, uuid: "FACADE00-0000-4000-8000-000000000001", vendor: 0x0610, model: 0xa050, serial: 0,
        nativePixels: CGSize(width: 3024, height: 1964), sizeMM: CGSize(width: 302, height: 196), name: "Built-in",
        frame: CGRect(x: 0, y: 0, width: 2056, height: 1329), rotation: 0, isBuiltIn: true, isMain: true,
        mirrors: nil)

    /// The 27″ 4K monitor, to the right.
    static let lg = DisplayFacts(
        displayID: 2, uuid: "1E6D5B14-0000-0000-2B1F-0104B53C2278", vendor: 0x1e6d, model: 0x5b14, serial: 0x0006_d3b1,
        nativePixels: CGSize(width: 3840, height: 2160), sizeMM: CGSize(width: 597, height: 336), name: "LG HDR 4K",
        frame: CGRect(x: 2056, y: 0, width: 3008, height: 1692), rotation: 0, isBuiltIn: false, isMain: false,
        mirrors: nil)

    /// The 2K monitor the ILITEK sits on, above the main display. It reports 27″; it is 23.8″.
    static let hdmi = DisplayFacts(
        displayID: 3, uuid: "4C2D0E10-0000-0000-0A20-0104B53C2278", vendor: 0x4c2d, model: 0x0e10, serial: 1,
        nativePixels: CGSize(width: 2560, height: 1440), sizeMM: CGSize(width: 602, height: 329), name: "HDMI",
        frame: CGRect(x: -252, y: -1440, width: 2560, height: 1440), rotation: 0, isBuiltIn: false, isMain: false,
        mirrors: nil)

    /// The strip the wch.cn touchscreen sits on, below the main display. It reports 10.1″; it is 12.3″.
    static let strip = DisplayFacts(
        displayID: 4, uuid: "2D1E0123-0000-0000-1A21-0103802D1A78", vendor: 0x2d1e, model: 0x0123, serial: 0,
        nativePixels: CGSize(width: 1920, height: 720), sizeMM: CGSize(width: 240, height: 90), name: "12.3FHD",
        frame: CGRect(x: 228, y: 1329, width: 1600, height: 600), rotation: 0, isBuiltIn: false, isMain: false,
        mirrors: nil)

    /// The 18″ monitor, to the left.
    static let display = DisplayFacts(
        displayID: 5, uuid: "3A495678-0000-0000-0F22-0104A5271878", vendor: 0x3a49, model: 0x5678, serial: 1,
        nativePixels: CGSize(width: 2560, height: 1600), sizeMM: CGSize(width: 388, height: 242), name: "Display",
        frame: CGRect(x: -2048, y: 24, width: 2048, height: 1280), rotation: 0, isBuiltIn: false, isMain: false,
        mirrors: nil)

    static let displays = [builtIn, lg, hdmi, strip, display]

    /// Where the pointer is before any touching in the pipeline and model tests: the middle of the
    /// main display, which no touchscreen is on.
    static let pointerHome = CGPoint(x: 1028, y: 664)

    // MARK: - Touchscreens

    static let ilitekFacts = TouchscreenFacts(
        vendorID: 0x222a, productID: 0x0001, serial: "V06.00.00.00", locationID: 0x0114_1000, name: "ILITEK-TP")
    static let stripFacts = TouchscreenFacts(
        vendorID: 0x27c0, productID: 0x0859, serial: "TEST-SERIAL-0001", locationID: 0x0113_0000, name: "TouchScreen")

    static let ilitekID = TouchscreenIdentity.baseID(vendorID: 0x222a, productID: 0x0001, serial: "V06.00.00.00")
    static let stripID = TouchscreenIdentity.baseID(vendorID: 0x27c0, productID: 0x0859, serial: "TEST-SERIAL-0001")

    static let ilitekHandle = DeviceHandle(rawValue: 1)
    static let stripHandle = DeviceHandle(rawValue: 2)

    /// The ILITEK as the device layer announces it: released, as every touchscreen connects.
    static func ilitek(
        handle: DeviceHandle = ilitekHandle, status: DeviceStatus = DeviceStatus(), facts: TouchscreenFacts = ilitekFacts
    ) -> ConnectedTouchscreen {
        ConnectedTouchscreen(
            handle: handle, facts: facts, maxContacts: 10, reportedSizeMM: CGSize(width: 476, height: 268),
            hasMouseInterface: true, reportsPalms: false, status: status)
    }

    /// The wch.cn strip as the device layer announces it.
    static func stripScreen(
        handle: DeviceHandle = stripHandle, status: DeviceStatus = DeviceStatus(), facts: TouchscreenFacts = stripFacts
    ) -> ConnectedTouchscreen {
        ConnectedTouchscreen(
            handle: handle, facts: facts, maxContacts: 10, reportedSizeMM: CGSize(width: 217, height: 91),
            hasMouseInterface: true, reportsPalms: false, status: status)
    }

    /// A taken touchscreen's status: exclusive, its touches from `origin`.
    static func taken(origin: TouchOrigin = .touchInterface, inputMode: InputModeStatus = .noInputModeSetting,
                      exclusive: ExclusiveAccess = .held) -> DeviceStatus {
        DeviceStatus(state: .taken, inputMode: inputMode, touchOrigin: origin, exclusive: exclusive)
    }

    // MARK: - Settings

    /// A touchscreen's settings, paired with `display` as fitted, with a diagonal override; with
    /// every behaviour after 0.2.0 off while `newOptionsOff`.
    static func paired(_ name: String, with display: DisplayFacts?, diagonal: Double? = nil) -> TouchscreenSettings {
        var settings = TouchscreenSettings()
        settings.lastSeenName = name
        if let display { settings.pair(with: DisplayIdentity(display)) }
        settings.diagonalInches = diagonal
        settings.gestures = asConfigured(settings.gestures)
        if newOptionsOff { settings.rejection = .none }
        return settings
    }

    /// The desk's settings: the ILITEK paired with "HDMI" (23.8″), the strip with "12.3FHD" (12.3″).
    static var settings: TactileSettings {
        var settings = TactileSettings()
        settings.touchscreens[ilitekID] = paired("ILITEK-TP", with: hdmi, diagonal: 23.8)
        settings.touchscreens[stripID] = paired("TouchScreen", with: strip, diagonal: 12.3)
        return settings
    }

    /// Everything known on the desk with both touchscreens taken and working: the ILITEK sending
    /// touches, the strip one finger from its mouse interface.
    static var inputs: AppInputs {
        AppInputs(
            appVersion: "0.2.0",
            settings: settings,
            connected: [ilitek(status: taken()), stripScreen(status: taken(origin: .mouseInterface, inputMode: .switchedToMultiTouch))],
            records: [ilitekHandle: ilitekID, stripHandle: stripID],
            displays: displays,
            hasAccessibilityAccess: true,
            isSessionActive: true,
            isAsleep: false,
            isTouchUpRunning: false,
            areMissionControlShortcutsOn: true,
            settingsWereSetAside: false,
            isQuitting: false)
    }

    /// The mapping a touchscreen fitted straight on `display` has.
    static func mapping(on display: DisplayFacts) -> TouchMapping {
        TouchMapping(orientation: .asFitted, alignment: .wholeGlass, display: display, content: nil)!
    }

    /// What a touchscreen fitted straight on `display` drives with; with every behaviour after
    /// 0.2.0 off while `newOptionsOff`.
    static func driving(
        on display: DisplayFacts, diagonal: Double?, options: GestureOptions = .all,
        oneFinger: OneFingerMode = .automatic, pointerReturn: PointerReturn = .backWhereItWas, showsCircles: Bool = true,
        rejection: RejectionRules = RejectionRules(), swipesFollowFingers: Bool = false
    ) -> Driving {
        Driving(
            mapping: mapping(on: display),
            surfaceSizeMM: SurfaceSize.millimetres(display: display, diagonalInches: diagonal),
            displayFrame: display.frame, displayID: display.displayID, options: asConfigured(options), oneFinger: oneFinger,
            pointerReturn: pointerReturn, showsCircles: showsCircles, rejection: newOptionsOff ? .none : rejection,
            swipesFollowFingers: swipesFollowFingers)
    }

    /// Every gesture beyond one finger switched off (and long-press too while `newOptionsOff`).
    static var noGestures: GestureOptions { asConfigured(.oneFingerOnly(keeping: GestureOptions())) }
}

/// `value` with `change` made to it.
func with<Value>(_ value: Value, _ change: (inout Value) -> Void) -> Value {
    var value = value
    change(&value)
    return value
}
