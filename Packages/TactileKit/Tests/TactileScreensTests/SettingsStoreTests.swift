import CoreGraphics
import Foundation
import TactileGestures
import XCTest
@testable import TactileScreens

// The desk's displays are `DeskDisplays`, in DisplayMatcherTests.swift.

/// The wch.cn touchscreen, on the strip.
private let wch = TouchscreenIdentity.baseID(vendorID: 0x27c0, productID: 0x0859, serial: "TEST-SERIAL-0001")
/// A touchscreen whose serial holds a quote, a colon and a letter that isn't ASCII.
private let odd = TouchscreenIdentity.baseID(vendorID: 0x222a, productID: 0x0001, serial: #"say "hi": ü"#)

/// Settings with every field away from its default: two touchscreens, one paired, and two display
/// names.
private func everythingSet() -> TactileSettings {
    var paired = TouchscreenSettings()
    paired.lastSeenName = "wch.cn TouchScreen"
    paired.pair(with: DisplayIdentity(DeskDisplays.strip))
    paired.pairing?.orientation = Orientation(quarterTurns: 3, isFlipped: true)
    paired.pairing?.alignment = GlassAlignment(
        pictureRect: CGRect(x: 0.00989, y: 0.03187, width: 0.98022, height: 0.95844))
    paired.pairing?.displayName = "12.3FHD"
    paired.diagonalInches = 12.3
    paired.gestures.pinch = false
    paired.gestures.twoFingerTap = false

    var other = TouchscreenSettings()
    other.customName = #"Desk "left": Größe"#
    other.lastSeenName = "TouchScreen"
    other.isOn = false
    other.whenOff = .leaveToMacOS
    other.oneFinger = .alwaysDrag
    other.pointerReturn = .staysWhereTouched
    other.showsCircles = false
    other.gestures.twoFingerScroll = false
    other.gestures.swipes = false
    other.diagonalInches = 1.0 / 3.0
    other.rejection = RejectionRules(palm: false, edgeMarginMM: 2.5)
    other.wasOfferedSetUp = true

    var settings = TactileSettings()
    settings.isOn = false
    settings.debugLogging = true
    settings.recordsFrames = true
    settings.swipesFollowFingers = true
    settings.displayNames = [DeskDisplays.strip.uuid: "Strip", DeskDisplays.hdmi.uuid: #"Über "HDMI""#]
    settings.touchscreens = [wch: paired, odd: other]
    return settings
}

/// Whether anything is at `url`, even a symbolic link to nothing.
private func exists(_ url: URL) -> Bool {
    (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
}

/// The names in `folder`, sorted.
private func names(in folder: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
}

/// The path a file was set aside at; `nil` for any other outcome.
private func setAsidePath(_ outcome: SettingsStore.LoadOutcome) -> String? {
    guard case .setAside(let url) = outcome else { return nil }
    return url.path
}

/// Sets `url`'s permissions.
private func setPermissions(_ permissions: Int, of url: URL) throws {
    try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
}

/// What a load on another thread returned.
private final class Returned: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: (settings: TactileSettings, outcome: SettingsStore.LoadOutcome)?

    var value: (settings: TactileSettings, outcome: SettingsStore.LoadOutcome)? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

final class SettingsStoreTests: XCTestCase {

    /// A new empty folder for this test, removed when it ends.
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: folder)
            XCTAssertFalse(exists(folder), "the test's folder was left behind: \(folder.path)")
        }
        return folder
    }

    private func store(in folder: URL, named name: String = "settings.json") -> SettingsStore {
        SettingsStore(fileURL: folder.appendingPathComponent(name))
    }

    /// Asserts that `result` is the defaults, with the file set aside as `name` beside it, holding
    /// `bytes`, and nothing left where it was.
    private func assertSetAside(
        _ result: (settings: TactileSettings, outcome: SettingsStore.LoadOutcome), from file: URL, as name: String,
        holding bytes: Data, _ message: String = "", line: UInt = #line
    ) {
        XCTAssertEqual(result.settings, TactileSettings(), message, line: line)
        guard case .setAside(let url) = result.outcome else {
            return XCTFail("\(result.outcome) is not setAside. \(message)", line: line)
        }
        XCTAssertEqual(url.path, file.deletingLastPathComponent().appendingPathComponent(name).path, message, line: line)
        XCTAssertTrue(url.lastPathComponent.hasPrefix(file.lastPathComponent + ".broken"), message, line: line)
        XCTAssertFalse(exists(file), "still at the original path. \(message)", line: line)
        XCTAssertEqual(try? Data(contentsOf: url), bytes, message, line: line)
    }

    // MARK: - The brief's table

    func testRoundTrip() throws {
        let folder = try makeFolder()
        let store = store(in: folder)
        let settings = everythingSet()
        try store.save(settings)
        let (loaded, outcome) = store.load()
        XCTAssertEqual(outcome, .loaded)
        XCTAssertEqual(loaded, settings)
        XCTAssertEqual(loaded.touchscreens[wch]?.pairing?.orientation, Orientation(quarterTurns: 3, isFlipped: true))
        XCTAssertEqual(loaded.touchscreens[odd]?.diagonalInches, 1.0 / 3.0)
    }

    func testTheFileIsReadable() throws {
        let folder = try makeFolder()
        let store = store(in: folder)
        try store.save(everythingSet())
        let data = try Data(contentsOf: store.fileURL)

        let top = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(top["version"] as? Int, 1)
        XCTAssertEqual(Set(top.keys), ["debugLogging", "displayNames", "isOn", "recordsFrames", "swipesFollowFingers",
                                       "touchscreens", "version"])
        let screens = try XCTUnwrap(top["touchscreens"] as? [String: Any])
        XCTAssertEqual(Set(screens.keys), ["27c0:0859:TEST-SERIAL-0001", #"222a:0001:say "hi": ü"#])
        let screen = try XCTUnwrap(screens[wch.rawValue] as? [String: Any])
        XCTAssertEqual(
            Set(screen.keys),
            ["diagonalInches", "gestures", "isOn", "lastSeenName", "pairing", "pointerReturn",
             "rejection", "showsCircles", "wasOfferedSetUp", "whenOff"], "the one-finger default is left out")
        let pairing = try XCTUnwrap(screen["pairing"] as? [String: Any])
        XCTAssertEqual(Set(pairing.keys), ["alignment", "display", "displayName", "orientation"])
        XCTAssertNil(screen["oneFinger"])
        let oddScreen = try XCTUnwrap(screens[odd.rawValue] as? [String: Any])
        XCTAssertEqual(Set(oddScreen.keys).count, 12)  // no pairing; a one-finger choice, and its flag
        XCTAssertEqual(oddScreen["oneFinger"] as? String, "alwaysDrag")
        XCTAssertEqual(oddScreen["oneFingerChosen"] as? Bool, true)

        // Pretty-printed, with the keys sorted.
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("{\n  \""), text)
        let positions = ["debugLogging", "displayNames", "isOn", "recordsFrames", "swipesFollowFingers", "touchscreens", "version"]
            .compactMap { text.range(of: "\n  \"\($0)\" : ")?.lowerBound }
        XCTAssertEqual(positions.count, 7, text)
        XCTAssertEqual(positions, positions.sorted(), text)
    }

    func testNoFileGivesDefaultsAndWritesNothing() throws {
        let folder = try makeFolder()
        let (settings, outcome) = store(in: folder).load()
        XCTAssertEqual(settings, TactileSettings())
        XCTAssertEqual(outcome, .noFile)
        XCTAssertEqual(try names(in: folder), [])

        // Nor is a missing folder made.
        let missing = SettingsStore(fileURL: folder.appendingPathComponent("Tactile/settings.json"))
        XCTAssertEqual(missing.load().outcome, .noFile)
        XCTAssertEqual(try names(in: folder), [])
    }

    func testADamagedFileIsSetAside() throws {
        let folder = try makeFolder()
        let store = store(in: folder)
        let bytes = Data(#"{"version":1,"touchscr"#.utf8)
        try bytes.write(to: store.fileURL)
        assertSetAside(store.load(), from: store.fileURL, as: "settings.json.broken", holding: bytes)
    }

    func testAFileFromANewerVersionIsSetAside() throws {
        let folder = try makeFolder()
        let store = store(in: folder)
        try store.save(everythingSet())
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertTrue(text.contains(#""version" : 1"#))
        let bytes = Data(text.replacingOccurrences(of: #""version" : 1"#, with: #""version" : 2"#).utf8)
        try bytes.write(to: store.fileURL)
        assertSetAside(store.load(), from: store.fileURL, as: "settings.json.broken", holding: bytes)
    }

    func testSettingAsideNeverOverwritesAnEarlierBrokenFile() throws {
        let folder = try makeFolder()
        let store = store(in: folder)
        let first = Data("first".utf8), second = Data("second".utf8)
        try first.write(to: store.fileURL)
        assertSetAside(store.load(), from: store.fileURL, as: "settings.json.broken", holding: first)
        try second.write(to: store.fileURL)
        assertSetAside(store.load(), from: store.fileURL, as: "settings.json.broken-2", holding: second)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("settings.json.broken")), first)
        XCTAssertEqual(try names(in: folder), ["settings.json.broken", "settings.json.broken-2"])
    }

    func testSaveCreatesTheFolder() throws {
        let folder = try makeFolder()
        let store = SettingsStore(fileURL: folder.appendingPathComponent("Application Support/Tactile/settings.json"))
        try store.save(everythingSet())
        XCTAssertEqual(store.load().outcome, .loaded)
        XCTAssertEqual(try names(in: folder.appendingPathComponent("Application Support/Tactile")), ["settings.json"])
    }

    // MARK: - Files that can't be used

    func testEveryFileThatCannotBeUsedIsSetAsideWithItsBytes() throws {
        let folder = try makeFolder()
        let unusable: [(String, Data)] = [
            ("empty", Data()),
            ("only white space", Data(" \n\t".utf8)),
            ("not JSON", Data("isOn = true".utf8)),
            ("not UTF-8", Data([0xff, 0xfe, 0x7b, 0x7d])),
            ("cut off", Data(#"{"version":1,"touchscreens":{"27c0:0859:X":{"isOn":fal"#.utf8)),
            ("null", Data("null".utf8)),
            ("an array", Data("[]".utf8)),
            ("a number", Data("1".utf8)),
            ("touchscreens an array", Data(#"{"version":1,"touchscreens":[]}"#.utf8)),
            ("a touchscreen null", Data(#"{"version":1,"touchscreens":{"A":null}}"#.utf8)),
            ("a touchscreen a string", Data(#"{"version":1,"touchscreens":{"A":"on"}}"#.utf8)),
            ("one field of the wrong type", Data(#"{"version":1,"touchscreens":{"A":{},"B":{"isOn":"no"}}}"#.utf8)),
            ("a choice this version lacks", Data(#"{"version":1,"touchscreens":{"A":{"oneFinger":"alwaysClick"}}}"#.utf8)),
            ("a version that is a string", Data(#"{"version":"1"}"#.utf8)),
            ("a newer version", Data(#"{"version":2}"#.utf8)),
            ("a number too large", Data(#"{"version":1,"touchscreens":{"A":{"diagonalInches":1e999}}}"#.utf8)),
            ("nested too deep", Data(String(repeating: "[", count: 100_000).utf8)),
        ]
        for (name, bytes) in unusable {
            let place = folder.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: place, withIntermediateDirectories: false)
            let store = store(in: place)
            try bytes.write(to: store.fileURL)
            assertSetAside(store.load(), from: store.fileURL, as: "settings.json.broken", holding: bytes, name)
            XCTAssertEqual(try names(in: place), ["settings.json.broken"], name)

            // Then a save starts a fresh file, which loads.
            try store.save(everythingSet())
            XCTAssertEqual(store.load().outcome, .loaded, name)
            XCTAssertEqual(try Data(contentsOf: place.appendingPathComponent("settings.json.broken")), bytes, name)
        }
    }

    /// A file larger than 1 MiB is set aside without being read. This one is 64 MiB of nothing: a
    /// sparse file, which takes almost no room on the disk, but would take 64 MiB of memory to read.
    func testALargeFileIsSetAsideUnread() throws {
        let folder = try makeFolder()
        let store = store(in: folder)
        let size = 64 << 20
        try Data(#"{"version":1}"#.utf8).write(to: store.fileURL)
        let handle = try FileHandle(forWritingTo: store.fileURL)
        try handle.truncate(atOffset: UInt64(size))
        try handle.close()
        let allocated = try store.fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize
        XCTAssertLessThan(try XCTUnwrap(allocated), 1 << 20, "the file should be sparse, not 64 MiB written to the disk")

        let (settings, outcome) = store.load()
        XCTAssertEqual(settings, TactileSettings())
        let url = folder.appendingPathComponent("settings.json.broken")
        XCTAssertEqual(setAsidePath(outcome), url.path)
        XCTAssertFalse(exists(store.fileURL))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.size] as? NSNumber)?.intValue, size, "the set-aside file keeps its size")
    }

    /// A file of 1 MiB is read; one byte more and it is set aside unread, though it holds settings
    /// this version could read.
    func testAFileOfMoreThan1MiBIsSetAsideThoughItHoldsSettings() throws {
        XCTAssertEqual(SettingsStore.mostBytes, 1 << 20)
        let folder = try makeFolder()
        let settings = Data(#"{"version":1,"isOn":false}"#.utf8)
        func padded(to count: Int) -> Data {
            settings + Data(repeating: UInt8(ascii: " "), count: count - settings.count)
        }

        let fits = store(in: folder, named: "fits.json")
        try padded(to: SettingsStore.mostBytes).write(to: fits.fileURL)
        let loaded = fits.load()
        XCTAssertEqual(loaded.outcome, .loaded)
        XCTAssertFalse(loaded.settings.isOn)

        let tooLarge = store(in: folder, named: "too-large.json")
        let bytes = padded(to: SettingsStore.mostBytes + 1)
        try bytes.write(to: tooLarge.fileURL)
        assertSetAside(tooLarge.load(), from: tooLarge.fileURL, as: "too-large.json.broken", holding: bytes)
    }

    func testANameThatIsTakenIsSkippedWhateverHasIt() throws {
        let folder = try makeFolder()
        let store = store(in: folder)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("settings.json.broken"), withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("settings.json.broken-2"),
            withDestinationURL: folder.appendingPathComponent("nowhere"))
        try Data("third".utf8).write(to: folder.appendingPathComponent("settings.json.broken-3"))
        let bytes = Data("damaged".utf8)
        try bytes.write(to: store.fileURL)

        assertSetAside(store.load(), from: store.fileURL, as: "settings.json.broken-4", holding: bytes)
        XCTAssertEqual(
            try names(in: folder),
            ["settings.json.broken", "settings.json.broken-2", "settings.json.broken-3", "settings.json.broken-4"])
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: folder.appendingPathComponent("settings.json.broken-2").path),
            folder.appendingPathComponent("nowhere").path)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("settings.json.broken-3")), Data("third".utf8))
    }

    func testAFolderInPlaceOfTheFileIsSetAside() throws {
        let folder = try makeFolder()
        let store = store(in: folder)
        try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: false)
        try Data("kept".utf8).write(to: store.fileURL.appendingPathComponent("inside"))

        let (settings, outcome) = store.load()
        XCTAssertEqual(settings, TactileSettings())
        XCTAssertEqual(setAsidePath(outcome), folder.appendingPathComponent("settings.json.broken").path)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("settings.json.broken/inside")), Data("kept".utf8))
        XCTAssertFalse(exists(store.fileURL))

        try store.save(everythingSet())
        XCTAssertEqual(store.load().outcome, .loaded)
    }

    func testAPipeInPlaceOfTheFileIsSetAsideWithoutWaitingForAWriter() throws {
        let folder = try makeFolder()
        let file = folder.appendingPathComponent("settings.json")
        XCTAssertEqual(mkfifo(file.path, 0o600), 0)

        let returned = Returned()
        let done = expectation(description: "load returned")
        DispatchQueue.global().async {
            returned.value = SettingsStore(fileURL: file).load()
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        let result = try XCTUnwrap(returned.value)
        XCTAssertEqual(result.settings, TactileSettings())
        XCTAssertEqual(setAsidePath(result.outcome), folder.appendingPathComponent("settings.json.broken").path)
        XCTAssertFalse(exists(file))
    }

    func testAFileThatCannotBeReadIsSetAside() throws {
        try XCTSkipIf(geteuid() == 0, "root can read any file")
        let folder = try makeFolder()
        let store = store(in: folder)
        try store.save(everythingSet())
        let bytes = try Data(contentsOf: store.fileURL)
        try setPermissions(0, of: store.fileURL)

        let (settings, outcome) = store.load()
        XCTAssertEqual(settings, TactileSettings())
        let url = folder.appendingPathComponent("settings.json.broken")
        XCTAssertEqual(setAsidePath(outcome), url.path)
        XCTAssertFalse(exists(store.fileURL))
        try setPermissions(0o600, of: url)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    /// The set-aside name is too long for the file system, so the file can't be renamed, though it
    /// could be written over.
    func testAFileThatCannotBeSetAsideIsNeverWrittenOver() throws {
        let folder = try makeFolder()
        let name = String(repeating: "s", count: 245) + ".json"
        let store = store(in: folder, named: name)
        let bytes = Data(#"{"version":1,"touchscr"#.utf8)
        try bytes.write(to: store.fileURL)

        let (settings, outcome) = store.load()
        XCTAssertEqual(settings, TactileSettings())
        XCTAssertEqual(outcome, .couldNotSetAside)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), bytes)

        XCTAssertThrowsError(try store.save(everythingSet()))
        XCTAssertThrowsError(try store.save(TactileSettings()))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), bytes)
        XCTAssertEqual(try names(in: folder), [name])

        // A new store hasn't seen the file, but its load finds the same.
        XCTAssertEqual(self.store(in: folder, named: name).load().outcome, .couldNotSetAside)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), bytes)
    }

    func testAFileInAFolderThatCannotBeWrittenIsLeftAsItIs() throws {
        try XCTSkipIf(geteuid() == 0, "root can write any folder")
        let folder = try makeFolder()
        let store = store(in: folder)
        let bytes = Data("damaged".utf8)
        try bytes.write(to: store.fileURL)
        try setPermissions(0o555, of: folder)
        defer { try? setPermissions(0o755, of: folder) }

        let (settings, outcome) = store.load()
        XCTAssertEqual(settings, TactileSettings())
        XCTAssertEqual(outcome, .couldNotSetAside)
        XCTAssertThrowsError(try store.save(everythingSet()))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), bytes)
        XCTAssertEqual(try names(in: folder), ["settings.json"])

        // Once the folder can be written, the next save sets the file aside first.
        try setPermissions(0o755, of: folder)
        try store.save(everythingSet())
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("settings.json.broken")), bytes)
        XCTAssertEqual(store.load().settings, everythingSet())
    }

    func testAFileThatCouldNotBeSetAsideAndIsThenRemovedIsNoLongerInTheWay() throws {
        try XCTSkipIf(geteuid() == 0, "root can write any folder")
        let folder = try makeFolder()
        let store = store(in: folder)
        try Data("damaged".utf8).write(to: store.fileURL)
        try setPermissions(0o555, of: folder)
        defer { try? setPermissions(0o755, of: folder) }
        XCTAssertEqual(store.load().outcome, .couldNotSetAside)

        try setPermissions(0o755, of: folder)
        try FileManager.default.removeItem(at: store.fileURL)
        try store.save(everythingSet())
        XCTAssertEqual(try names(in: folder), ["settings.json"])
        XCTAssertEqual(store.load().outcome, .loaded)
    }

    func testSaveThrowsWhenTheFolderCannotBeWritten() throws {
        try XCTSkipIf(geteuid() == 0, "root can write any folder")
        let folder = try makeFolder()
        try setPermissions(0o555, of: folder)
        defer { try? setPermissions(0o755, of: folder) }

        let store = store(in: folder)
        XCTAssertEqual(store.load().outcome, .noFile)
        XCTAssertThrowsError(try store.save(everythingSet()))
        let nested = SettingsStore(fileURL: folder.appendingPathComponent("Tactile/settings.json"))
        XCTAssertThrowsError(try nested.save(everythingSet()))
        XCTAssertEqual(try names(in: folder), [])
    }

    // MARK: - Saving

    func testSaveReplacesTheFileAndLeavesNothingElse() throws {
        let folder = try makeFolder()
        let store = store(in: folder)
        try store.save(everythingSet())
        var changed = everythingSet()
        changed.touchscreens[wch]?.unpair()
        changed.displayNames = [:]
        try store.save(changed)
        XCTAssertEqual(try names(in: folder), ["settings.json"])
        XCTAssertEqual(store.load().settings, changed)
    }

    func testTwoStoresOnOneFileTheLastSaveWins() throws {
        let folder = try makeFolder()
        let first = store(in: folder), second = store(in: folder)
        var off = TactileSettings()
        off.isOn = false
        let full = everythingSet()

        try first.save(full)
        try second.save(off)
        XCTAssertEqual(first.load().settings, off)
        try first.save(full)
        let (settings, outcome) = second.load()
        XCTAssertEqual(outcome, .loaded)
        XCTAssertEqual(settings, full)
        XCTAssertEqual(try names(in: folder), ["settings.json"])
    }

    /// JSON can't hold a number that isn't finite. The settings never do either: such a diagonal is
    /// no diagonal and such an alignment is the whole glass, from the moment they are set.
    func testNumbersJSONCannotHoldNeverStopASave() throws {
        let folder = try makeFolder()
        let store = store(in: folder)
        var settings = everythingSet()
        settings.touchscreens[wch]?.diagonalInches = .nan
        settings.touchscreens[wch]?.pairing?.alignment.pictureRect.origin.x = .infinity
        settings.touchscreens[odd]?.diagonalInches = -.infinity
        XCTAssertNoThrow(try store.save(settings))

        let (loaded, outcome) = store.load()
        XCTAssertEqual(outcome, .loaded)
        XCTAssertEqual(loaded, settings)
        XCTAssertNil(loaded.touchscreens[wch]?.diagonalInches)
        XCTAssertEqual(loaded.touchscreens[wch]?.pairing?.alignment, .wholeGlass)
        XCTAssertEqual(loaded.touchscreens[wch]?.pairing?.orientation, Orientation(quarterTurns: 3, isFlipped: true))
        XCTAssertNil(loaded.touchscreens[odd]?.diagonalInches)
    }

    /// What is saved is in this version's format, whatever `version` says, so it always loads again.
    func testSaveWritesTheCurrentVersion() throws {
        let folder = try makeFolder()
        let store = store(in: folder)
        for version in [0, -1, 2, 99, Int.max] {
            var settings = everythingSet()
            settings.version = version
            try store.save(settings)
            let top = try JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any]
            XCTAssertEqual(top?["version"] as? Int, 1, "\(version)")
            let (loaded, outcome) = store.load()
            XCTAssertEqual(outcome, .loaded, "\(version)")
            XCTAssertEqual(loaded, everythingSet(), "\(version)")
        }
    }

    /// A serial may hold anything; its ID comes back from the file byte for byte, not just as an
    /// equal string (Swift counts "é" and "e" + "◌́" as equal).
    func testIDsSurviveTheFileExactly() throws {
        let serials = [
            "TEST-SERIAL-0001", "", "V06.00.00.00", #"say "hi""#, "a:b:c:", "@01141000:x", #"back\slash/slash"#,
            "\u{0}\u{1}\u{7}\u{8}\u{1B}\u{7F}", "tab\tnew\nline\r", "Füße", "e\u{301}", "👆🏽", "שלום",
            "\u{FEFF}bom", "\u{2028}\u{2029}", #"{"}"#, " ", "%41%00", "\u{10FFFF}",
        ]
        var settings = TactileSettings()
        for (number, serial) in serials.enumerated() {
            let base = TouchscreenIdentity.baseID(vendorID: 0x222a, productID: number, serial: serial)
            var screen = TouchscreenSettings()
            screen.lastSeenName = serial
            screen.customName = serial
            settings.touchscreens[base] = screen
            settings.touchscreens[TouchscreenIdentity.portID(base, locationID: 0x0114_1000)] = screen
            settings.displayNames["\(number)" + serial] = serial
        }
        XCTAssertEqual(settings.touchscreens.count, serials.count * 2)

        let folder = try makeFolder()
        let store = store(in: folder)
        try store.save(settings)
        let (loaded, outcome) = store.load()
        XCTAssertEqual(outcome, .loaded)
        XCTAssertEqual(loaded, settings)

        func bytes(_ strings: some Sequence<String>) -> Set<[UInt8]> { Set(strings.map { Array($0.utf8) }) }
        XCTAssertEqual(bytes(loaded.touchscreens.keys.map(\.rawValue)), bytes(settings.touchscreens.keys.map(\.rawValue)))
        XCTAssertEqual(bytes(loaded.touchscreens.values.map(\.lastSeenName)), bytes(serials))
        XCTAssertEqual(bytes(loaded.touchscreens.values.compactMap(\.customName)), bytes(serials))
        XCTAssertEqual(bytes(loaded.displayNames.keys), bytes(settings.displayNames.keys))
        XCTAssertEqual(bytes(loaded.displayNames.values), bytes(serials))
        // And each record is still under its own ID: the ID ends with the serial its record holds.
        for (id, screen) in loaded.touchscreens {
            XCTAssertTrue(id.rawValue.utf8.reversed().starts(with: screen.lastSeenName.utf8.reversed()), id.rawValue)
        }
    }

    /// No Tactile writes a key twice, or two keys Swift counts as one, but a file that has them
    /// still loads, with one of each.
    func testAKeyGivenTwiceDoesNotStopALoad() throws {
        let folder = try makeFolder()
        let store = store(in: folder)
        try Data(
            "{\"touchscreens\":{\"A\":{\"isOn\":false},\"A\":{\"isOn\":true},\"\u{e9}\":{},\"e\u{301}\":{}},\"isOn\":true,\"isOn\":false}"
                .utf8
        ).write(to: store.fileURL)
        let (settings, outcome) = store.load()
        XCTAssertEqual(outcome, .loaded)
        XCTAssertEqual(settings.touchscreens.count, 2)
    }
}
