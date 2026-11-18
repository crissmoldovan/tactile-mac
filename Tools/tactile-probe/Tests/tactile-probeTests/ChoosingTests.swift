import XCTest
@testable import tactile_probe

/// Choosing the touchscreen to survey and the display that shows its instructions.
final class ChoosingTests: XCTestCase {
    // MARK: Fixtures

    static func display(_ id: UInt32, _ name: String?, uuid: String, builtIn: Bool = false) -> DisplayInfo {
        DisplayInfo(
            displayID: id, name: name, vendorNumber: 0, modelNumber: 0, serialNumber: 0, uuid: uuid,
            physicalSizeMM: Size(width: 600, height: 330), pixelSize: IntSize(width: 2560, height: 1440),
            pointSize: Size(width: 2560, height: 1440), rotationDegrees: 0, origin: Point(x: 0, y: 0),
            builtIn: builtIn, main: builtIn, active: true, asleep: false, refreshRateHz: 60, backingScaleFactor: 1,
            mirroring: MirroringInfo(inMirrorSet: false, mirrorsDisplayID: nil, alwaysInMirrorSet: false, primaryDisplayID: id))
    }

    /// The desk on 2026-11-14, with made-up UUIDs.
    var desk: [DisplayInfo] { Self.deskDisplays }
    static let deskDisplays: [DisplayInfo] = [
        display(1, "Built-in Retina Display", uuid: "U-BUILTIN", builtIn: true),
        display(2, "LG HDR 4K", uuid: "U-LG"),
        display(3, "HDMI", uuid: "U-HDMI"),
        display(4, "12.3FHD", uuid: "U-STRIP"),
        display(5, "Display", uuid: "U-DISPLAY"),
    ]

    let wch = TouchscreenCandidate(number: 1, usbID: "27c0:0859", locationID: "0x01130000", name: "TouchScreen by wch.cn")
    let ilitek = TouchscreenCandidate(number: 2, usbID: "222a:0001", locationID: "0x01141000", name: "ILITEK-TP by ILITEK")

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("tactile-probe-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let folder { try? FileManager.default.removeItem(at: folder) }
    }

    // MARK: The touchscreen

    func testTheOnlyTouchscreenIsChosenWithoutAName() {
        XCTAssertEqual(chooseTouchscreen(named: nil, among: [ilitek]), .chosen(ilitek, reason: .onlyOneConnected))
    }

    func testTwoTouchscreensAndNoNameMeansListThemAndStop() {
        XCTAssertEqual(chooseTouchscreen(named: nil, among: [wch, ilitek]), .nameOne([wch, ilitek]))
    }

    func testANamedTouchscreenIsChosenFromSeveral() {
        XCTAssertEqual(chooseTouchscreen(named: "222a:0001", among: [wch, ilitek]), .chosen(ilitek, reason: .named))
        XCTAssertEqual(chooseTouchscreen(named: "27c0:0859", among: [wch, ilitek]), .chosen(wch, reason: .named))
    }

    func testANamedTouchscreenIsChosenEvenWhenItIsTheOnlyOne() {
        XCTAssertEqual(chooseTouchscreen(named: "222a:0001", among: [ilitek]), .chosen(ilitek, reason: .named))
    }

    func testANameThatMatchesNothingIsRefused() {
        XCTAssertEqual(chooseTouchscreen(named: "1234:5678", among: [wch, ilitek]), .notConnected("1234:5678", connected: [wch, ilitek]))
    }

    func testTwoIdenticalTouchscreensCannotBeToldApart() {
        let twin = TouchscreenCandidate(number: 3, usbID: "222a:0001", locationID: "0x01142000", name: "ILITEK-TP by ILITEK")
        XCTAssertEqual(chooseTouchscreen(named: "222a:0001", among: [wch, ilitek, twin]), .cannotTellApart([ilitek, twin]))
    }

    func testNoTouchscreenConnected() {
        XCTAssertEqual(chooseTouchscreen(named: nil, among: []), .noneConnected)
        XCTAssertEqual(chooseTouchscreen(named: "222a:0001", among: []), .noneConnected)
    }

    // MARK: --display

    func testADisplayIsFoundByItsID() {
        XCTAssertEqual(findDisplay("3", among: desk), .found(desk[2]))
        XCTAssertEqual(findDisplay("4", among: desk), .found(desk[3]), "an ID wins over a name that contains the digit (LG HDR 4K)")
        XCTAssertEqual(findDisplay("9", among: desk), .notFound)
    }

    func testADisplayIsFoundByItsNameInAnyCase() {
        XCTAssertEqual(findDisplay("HDMI", among: desk), .found(desk[2]))
        XCTAssertEqual(findDisplay("hdmi", among: desk), .found(desk[2]))
        XCTAssertEqual(findDisplay("12.3fhd", among: desk), .found(desk[3]))
        XCTAssertEqual(findDisplay("Display", among: desk), .found(desk[4]), "a whole name wins over a part of another")
    }

    func testADisplayIsFoundByAPartOfItsNameWhenThatPartIsUnique() {
        XCTAssertEqual(findDisplay("12.3", among: desk), .found(desk[3]))
        XCTAssertEqual(findDisplay("lg", among: desk), .found(desk[1]))
        XCTAssertEqual(findDisplay("Retina", among: desk), .found(desk[0]))
    }

    func testAPartThatFitsSeveralNamesIsRefused() {
        XCTAssertEqual(findDisplay("HD", among: desk), .ambiguous([desk[1], desk[2], desk[3]]))
    }

    func testAnUnnamedDisplayIsFoundOnlyByID() {
        let mirrored = Self.display(6, nil, uuid: "U-MIRROR")
        XCTAssertEqual(findDisplay("6", among: desk + [mirrored]), .found(mirrored))
        XCTAssertEqual(findDisplay("U-MIRROR", among: desk + [mirrored]), .notFound)
    }

    // MARK: Tactile's state file

    /// A state file as the app writes it (`AppSnapshot`, pretty-printed with sorted keys). Only
    /// `usbID`, `location` and `pairedDisplayID` of a touchscreen, and `id` and `uuid` of a display,
    /// are read.
    private func stateFile(touchscreens: String, displays: String) throws -> URL {
        let text = """
        {
          "appVersion" : "0.2.0",
          "debugLogging" : false,
          "displays" : [\(displays)],
          "isOn" : true,
          "touchscreens" : [\(touchscreens)],
          "warnings" : [ "accessibilityMissing" ]
        }
        """
        let url = folder.appendingPathComponent("state.json")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func touchscreenEntry(usbID: String, location: String?, paired: UInt32?, name: String = "ILITEK-TP") -> String {
        var fields = [
            "\"device\" : \"touch interface, held\"", "\"deviceName\" : \"\(name)\"", "\"displayChoices\" : []",
            "\"id\" : \"\(usbID):V06.00.00.00\"", "\"isConnected\" : true", "\"isOn\" : true", "\"mode\" : \"driving\"",
            "\"name\" : \"\(name)\"", "\"notes\" : []", "\"serial\" : \"V06.00.00.00\"",
            "\"status\" : { \"pairedWith\" : { \"detail\" : \"2560 × 1440\", \"name\" : \"HDMI\" } }",
            "\"usbID\" : \"\(usbID)\"", "\"whenOff\" : \"ignoreTouches\"",
        ]
        if let location { fields.append("\"location\" : \"\(location)\"") }
        if let paired { fields.append("\"pairedDisplayID\" : \(paired)") }
        return "{ " + fields.joined(separator: ", ") + " }"
    }

    private func displayEntry(id: UInt32, uuid: String, name: String) -> String {
        """
        { "detail" : "", "frame" : [[0, 0], [2560, 1440]], "id" : \(id), "isBuiltIn" : false, "isMain" : false, \
        "name" : "\(name)", "uuid" : "\(uuid)" }
        """
    }

    private func pairing(_ url: URL, for touchscreen: TouchscreenCandidate) -> StatePairing {
        pairingFromStateFile(at: url, usbID: touchscreen.usbID, locationID: touchscreen.locationID, displays: desk)
    }

    func testThePairingIsReadFromTheStateFile() throws {
        let url = try stateFile(
            touchscreens: touchscreenEntry(usbID: "222a:0001", location: "01141000", paired: 3) + ", "
                + touchscreenEntry(usbID: "27c0:0859", location: "01130000", paired: 4, name: "TouchScreen"),
            displays: displayEntry(id: 3, uuid: "U-HDMI", name: "HDMI") + ", " + displayEntry(id: 4, uuid: "U-STRIP", name: "12.3FHD"))
        XCTAssertEqual(pairing(url, for: ilitek), .paired(desk[2]))
        XCTAssertEqual(pairing(url, for: wch), .paired(desk[3]))
    }

    func testADisplayWhoseIDChangedIsFoundByItsUUID() throws {
        let url = try stateFile(touchscreens: touchscreenEntry(usbID: "222a:0001", location: "01141000", paired: 7),
                                displays: displayEntry(id: 7, uuid: "U-HDMI", name: "HDMI"))
        XCTAssertEqual(pairing(url, for: ilitek), .paired(desk[2]))
    }

    func testAnIDNowUsedByAnotherDisplayIsNotTrusted() throws {
        // The state file says display 3 was a monitor that is not connected now; display 3 today is another one.
        let url = try stateFile(touchscreens: touchscreenEntry(usbID: "222a:0001", location: "01141000", paired: 3),
                                displays: displayEntry(id: 3, uuid: "U-SOMETHING-ELSE", name: "Old monitor"))
        guard case .notKnown = pairing(url, for: ilitek) else { return XCTFail("a stale pairing was trusted") }
    }

    func testWithoutTheDisplaysUUIDTheIDMustBeConnected() throws {
        let known = try stateFile(touchscreens: touchscreenEntry(usbID: "222a:0001", location: "01141000", paired: 3), displays: "")
        XCTAssertEqual(pairing(known, for: ilitek), .paired(desk[2]))
        let gone = try stateFile(touchscreens: touchscreenEntry(usbID: "222a:0001", location: "01141000", paired: 9), displays: "")
        guard case .notKnown = pairing(gone, for: ilitek) else { return XCTFail("a display that is not connected was used") }
    }

    func testAnUnpairedTouchscreenIsNotKnown() throws {
        let url = try stateFile(touchscreens: touchscreenEntry(usbID: "222a:0001", location: "01141000", paired: nil), displays: "")
        guard case .notKnown(let why) = pairing(url, for: ilitek) else { return XCTFail() }
        XCTAssertTrue(why.contains("not paired"), why)
    }

    func testATouchscreenTheStateFileDoesNotListIsNotKnown() throws {
        let url = try stateFile(touchscreens: touchscreenEntry(usbID: "27c0:0859", location: "01130000", paired: 4), displays: "")
        guard case .notKnown = pairing(url, for: ilitek) else { return XCTFail() }
    }

    func testTwoEntriesWithTheSameUSBIDAreToldApartByLocation() throws {
        let url = try stateFile(
            touchscreens: touchscreenEntry(usbID: "222a:0001", location: "01142000", paired: 2) + ", "
                + touchscreenEntry(usbID: "222a:0001", location: "01141000", paired: 3),
            displays: "")
        XCTAssertEqual(pairing(url, for: ilitek), .paired(desk[2]))
    }

    func testTwoEntriesWithTheSameUSBIDAndNoMatchingLocationAreNotKnown() throws {
        let url = try stateFile(
            touchscreens: touchscreenEntry(usbID: "222a:0001", location: "01142000", paired: 2) + ", "
                + touchscreenEntry(usbID: "222a:0001", location: nil, paired: 3),
            displays: "")
        guard case .notKnown = pairing(url, for: ilitek) else { return XCTFail("guessed between two entries") }
    }

    func testAMissingStateFileIsNotKnown() {
        let url = folder.appendingPathComponent("state.json")
        guard case .notKnown(let why) = pairing(url, for: ilitek) else { return XCTFail() }
        XCTAssertTrue(why.contains("no state file"), why)
    }

    func testAnUnreadableStateFileIsNotKnown() throws {
        let url = folder.appendingPathComponent("state.json")
        for text in ["", "{", "not json", "[1, 2]", "{\"touchscreens\": 5}"] {
            try text.write(to: url, atomically: true, encoding: .utf8)
            guard case .notKnown = pairing(url, for: ilitek) else { return XCTFail(text) }
        }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("folder.json"), withIntermediateDirectories: true)
        guard case .notKnown = pairing(folder.appendingPathComponent("folder.json"), for: ilitek) else { return XCTFail("a folder") }
    }

    // MARK: Which source wins

    func testTheArgumentWinsAndTheStateFileIsNotNeeded() throws {
        let url = folder.appendingPathComponent("state.json")
        try "garbage".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(chooseDisplay(argument: "HDMI", stateFile: url, touchscreen: ilitek, displays: desk), .chosen(desk[2], .argument))
    }

    func testTheArgumentWinsOverAPairing() throws {
        let url = try stateFile(touchscreens: touchscreenEntry(usbID: "222a:0001", location: "01141000", paired: 4), displays: "")
        XCTAssertEqual(chooseDisplay(argument: "hdmi", stateFile: url, touchscreen: ilitek, displays: desk), .chosen(desk[2], .argument))
    }

    func testABadArgumentStopsTheRunRatherThanFallingBack() throws {
        let url = try stateFile(touchscreens: touchscreenEntry(usbID: "222a:0001", location: "01141000", paired: 3), displays: "")
        guard case .badArgument(let message) = chooseDisplay(argument: "Projector", stateFile: url, touchscreen: ilitek, displays: desk)
        else { return XCTFail() }
        XCTAssertTrue(message.contains("Projector"), message)
        XCTAssertTrue(message.contains("HDMI") && message.contains("12.3FHD"), "it lists the displays there are: \(message)")
        guard case .badArgument = chooseDisplay(argument: "HD", stateFile: url, touchscreen: ilitek, displays: desk)
        else { return XCTFail("an ambiguous name was accepted") }
    }

    func testWithoutAnArgumentThePairingIsUsed() throws {
        let url = try stateFile(touchscreens: touchscreenEntry(usbID: "222a:0001", location: "01141000", paired: 3), displays: "")
        XCTAssertEqual(chooseDisplay(argument: nil, stateFile: url, touchscreen: ilitek, displays: desk), .chosen(desk[2], .stateFile))
    }

    func testWithNeitherTheDisplayIsNotKnown() {
        let url = folder.appendingPathComponent("state.json")
        guard case .notKnown(let why) = chooseDisplay(argument: nil, stateFile: url, touchscreen: ilitek, displays: desk)
        else { return XCTFail() }
        XCTAssertFalse(why.isEmpty)
    }

    func testTheDefaultStateFileIsTactiles() {
        XCTAssertTrue(defaultStateFileURL.path.hasSuffix("/Library/Application Support/Tactile/state.json"), defaultStateFileURL.path)
    }

    // MARK: Which displays show what

    func testTheChosenDisplayShowsTheInstructionAndEveryOtherExternalOneSaysNotThisOne() {
        let plan = BoardPlan(target: desk[2], displays: desk)
        XCTAssertEqual(plan.instructionDisplays.map(\.displayID), [3])
        XCTAssertEqual(plan.notThisOneDisplays.map(\.displayID), [2, 4, 5], "the built-in display shows nothing")
        XCTAssertTrue(plan.knowsTheDisplay)
    }

    func testWithNoDisplayKnownEveryExternalDisplayShowsTheInstruction() {
        let plan = BoardPlan(target: nil, displays: desk)
        XCTAssertEqual(plan.instructionDisplays.map(\.displayID), [2, 3, 4, 5])
        XCTAssertEqual(plan.notThisOneDisplays.map(\.displayID), [])
        XCTAssertFalse(plan.knowsTheDisplay)
    }

    func testAChosenBuiltInDisplayStillShowsTheInstruction() {
        let plan = BoardPlan(target: desk[0], displays: desk)
        XCTAssertEqual(plan.instructionDisplays.map(\.displayID), [1])
        XCTAssertEqual(plan.notThisOneDisplays.map(\.displayID), [2, 3, 4, 5])
    }

    func testTheQuestionOffersEveryExternalDisplay() {
        XCTAssertEqual(displayQuestionChoices(desk).map(\.displayID), [2, 3, 4, 5])
    }
}
