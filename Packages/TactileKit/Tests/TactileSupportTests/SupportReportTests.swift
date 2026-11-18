import Foundation
import TactileDevices
import TactileReading
import TactileSupport
import XCTest

/// The report's files: which, in what order, what each holds, and that no serial number is in any.
final class SupportReportTests: XCTestCase {

    // MARK: - The list

    func testTheFilesInTheirOrder() throws {
        let files = SupportReport.files(try Fixture.ilitekInput())
        XCTAssertEqual(files.map(\.name), [
            "summary.txt", "device.json", "descriptors/interface-1.hex", "descriptors/interface-2.hex", "switches.json",
            "touches.json", "tactile-log.txt", "mac.json", "manifest.json",
        ])
        XCTAssertTrue(files.allSatisfy { $0.size == $0.data.count && $0.size > 0 })
        XCTAssertTrue(files.allSatisfy { SupportReport.isExpectedName($0.name) })
    }

    func testAMouseOnlyDevicesFiles() {
        let files = SupportReport.files(Fixture.pointerInput())
        XCTAssertEqual(files.map(\.name), [
            "summary.txt", "device.json", "descriptors/interface-1.hex", "switches.json", "touches.json", "tactile-log.txt",
            "mac.json", "manifest.json",
        ])
    }

    /// tactilemac.com takes at most 32 entries in a zip: the seven files, the descriptors folder, and
    /// at most 24 descriptors. Those left out are counted in device.json.
    func testAtMostTwentyFourDescriptorsGo() throws {
        var input = Fixture.pointerInput()
        let one = input.device.interfaces[0]
        let many = (0..<30).map { n in
            SupportInterface(id: UInt64(1000 + n), role: n == 0 ? .pointer : .other, usages: one.usages,
                             descriptor: one.descriptor, maxInputReportSize: 6)
        }
        input.device = SupportDevice(
            id: input.device.id, kind: .mouseOnly, vendorID: 0x1234, productID: 0x5678, product: "Many", manufacturer: "",
            serial: "", locationID: 0x0120_0000, interfaces: many)
        input.identity = SupportIdentity(input.device)
        let files = SupportReport.files(input)
        XCTAssertEqual(files.filter { $0.name.hasPrefix("descriptors/") }.count, SupportReport.maxDescriptorFiles)
        XCTAssertLessThanOrEqual(files.count + 1, 32, "with the descriptors folder's own entry")
        let device = try Fixture.json(files[named: "device.json"])
        XCTAssertEqual(device["descriptors_left_out"] as? Int, 6)
        XCTAssertEqual(((device["interfaces"] as? [[String: Any]])?.last)?["descriptor_file"] as? String, nil)
    }

    func testOnlyTheReportsOwnNamesAreExpected() {
        for name in ["summary.txt", "descriptors/interface-12.hex", "manifest.json", "tactile-log.txt"] {
            XCTAssertTrue(SupportReport.isExpectedName(name), name)
        }
        for name in ["../summary.txt", "descriptors/x.hex", "descriptors/interface-1.txt", "notes.txt", "__MACOSX/._summary.txt",
                     "descriptors/interface-0.hex", "descriptors/interface-01.hex"] {
            XCTAssertFalse(SupportReport.isExpectedName(name), name)
        }
    }

    // MARK: - The manifest

    func testTheManifestHashesEveryOtherFile() throws {
        let files = SupportReport.files(try Fixture.ilitekInput(logLines: ["a line"]))
        let manifest = try Fixture.json(files[named: "manifest.json"])
        XCTAssertEqual(manifest["schema"] as? Int, 1)
        let hashes = try XCTUnwrap(manifest["files"] as? [String: String])
        XCTAssertEqual(Set(hashes.keys), Set(files.map(\.name).filter { $0 != "manifest.json" }))
        for file in files where file.name != "manifest.json" {
            XCTAssertEqual(hashes[file.name], Fixture.sha256(file.data), file.name)
        }
    }

    // MARK: - No serial number, anywhere

    func testNoSerialNumberIsInAnyFile() throws {
        let log = [
            #"2026-11-18T09:00:00.000Z [devices] Connected device-3: 1234:5678 "Panel POINTER-SERIAL-0042" serial "POINTER-SERIAL-0042" at 0x01200000"#,
        ]
        for input in [try Fixture.ilitekInput(logLines: [#"serial "V06.00.00.00""#]), Fixture.pointerInput(logLines: log)] {
            for file in SupportReport.files(input) {
                let text = String(decoding: file.data, as: UTF8.self)
                XCTAssertFalse(text.contains(input.device.serial), "\(file.name) holds the serial")
                XCTAssertFalse(text.lowercased().contains("\"serial"), "\(file.name) has a serial field")
            }
        }
        let device = try Fixture.json(SupportReport.files(Fixture.pointerInput())[named: "device.json"])
        XCTAssertEqual(device["product"] as? String, "Panel [serial removed]")
    }

    // MARK: - Each file

    func testDeviceJSON() throws {
        let device = try Fixture.json(SupportReport.files(try Fixture.ilitekInput())[named: "device.json"])
        XCTAssertEqual(device["usb_id"] as? String, "222a:0001")
        XCTAssertEqual(device["vendor_id"] as? Int, 0x222a)
        XCTAssertEqual(device["product_id"] as? Int, 1)
        XCTAssertEqual(device["product"] as? String, "ILITEK-TP")
        XCTAssertEqual(device["manufacturer"] as? String, "ILITEK")
        XCTAssertEqual(device["kind"] as? String, "touchscreen")
        XCTAssertEqual(device["finger_collections"] as? Int, 10)
        XCTAssertEqual(device["has_input_mode"] as? Bool, false)
        XCTAssertEqual(device["has_certification_blob"] as? Bool, true)
        XCTAssertEqual(device["contact_count_maximum"] as? Int, 10)
        XCTAssertNil(device["location_id"], "where it is plugged in isn't sent")

        let interfaces = try XCTUnwrap(device["interfaces"] as? [[String: Any]])
        XCTAssertEqual(interfaces.count, 2)
        let touch = interfaces[0]
        XCTAssertEqual(touch["number"] as? Int, 1)
        XCTAssertEqual(touch["role"] as? String, "touch")
        XCTAssertEqual(touch["usages"] as? [String], ["0x000d/0x0004"])
        XCTAssertEqual(touch["descriptor_file"] as? String, "descriptors/interface-1.hex")
        XCTAssertEqual(touch["descriptor_length"] as? Int, 743)
        let summary = try XCTUnwrap(touch["descriptor"] as? [String: Any])
        XCTAssertEqual(summary["application_collections"] as? [String], ["0x000d/0x0004"])
        XCTAssertEqual(summary["feature_reports"] as? [[String: Int]], [["id": 6, "length": 258]])
        XCTAssertEqual(summary["certification_blob_report"] as? Int, 6)
        XCTAssertEqual(summary["absolute_pointer"] as? Bool, false)
        let decoded = try XCTUnwrap(touch["decoded"] as? [String: Any])
        XCTAssertEqual(decoded["kind"] as? String, "touchscreen")
        XCTAssertEqual(decoded["finger_collections"] as? Int, 10)
        XCTAssertEqual((decoded["surface_mm"] as? [Double])?.count, 2)
        XCTAssertEqual((interfaces[1]["descriptor"] as? [String: Any])?["absolute_pointer"] as? Bool, true)
    }

    func testTheDescriptorsAreHexSixteenBytesALine() throws {
        let files = SupportReport.files(try Fixture.ilitekInput())
        let text = String(decoding: try XCTUnwrap(files[named: "descriptors/interface-1.hex"]).data, as: UTF8.self)
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, (743 + 15) / 16)
        XCTAssertTrue(lines[0].hasPrefix("05 0d 09 04 a1 01"))
        XCTAssertEqual(lines[0].split(separator: " ").count, 16)
        XCTAssertTrue(text.hasSuffix("\n"))
        XCTAssertEqual(SupportReport.bytes(fromHex: text), try Fixture.ilitek().interfaces[0].descriptor)
    }

    func testSwitchesJSON() throws {
        let switches = try Fixture.json(SupportReport.files(try Fixture.ilitekInput())[named: "switches.json"])
        XCTAssertEqual(switches["skipped"] as? Bool, false)
        let opens = try XCTUnwrap(switches["opens"] as? [[String: Any]])
        XCTAssertEqual(opens.map { $0["held"] as? String }, ["exclusively", "shared"])
        XCTAssertEqual(opens[1]["exclusive_io_return"] as? String, "0xe00002c5")
        XCTAssertEqual(opens[1]["shared_io_return"] as? String, "0x00000000")
        let reads = try XCTUnwrap(switches["feature_reads"] as? [[String: Any]])
        XCTAssertEqual(reads.count, 1)
        XCTAssertEqual(reads[0]["report_id"] as? Int, 6)
        XCTAssertEqual(reads[0]["contents"] as? [String], ["Contact Count Maximum", "certification blob"])
        XCTAssertEqual(reads[0]["length_asked"] as? Int, 258)
        XCTAssertEqual(reads[0]["length_returned"] as? Int, 258)
        XCTAssertEqual(reads[0]["io_return"] as? String, "0x00000000")
        XCTAssertEqual((reads[0]["bytes"] as? String)?.prefix(8), "060aabab")
        XCTAssertEqual(switches["has_input_mode"] as? Bool, false)
        XCTAssertNil(switches["input_mode_write"])

        let mouseOnly = try Fixture.json(SupportReport.files(Fixture.pointerInput())[named: "switches.json"])
        XCTAssertEqual(mouseOnly["skipped"] as? Bool, true)
        XCTAssertEqual(mouseOnly["why"] as? String, "mouse-only: it has no touch interface to read or switch")
        XCTAssertEqual((mouseOnly["feature_reads"] as? [Any])?.count, 0)
    }

    /// A digitiser Tactile doesn't drive: nothing read or switched, and the report says why.
    func testADigitisersSwitchesSayWhyNothingWasSwitched() throws {
        var input = Fixture.pointerInput()
        let interface = input.device.interfaces[0]
        input.device = SupportDevice(
            id: "0eef:7200@01600000", kind: .digitizer, vendorID: 0x0eef, productID: 0x7200, product: "Panel", manufacturer: "",
            serial: "", locationID: 0x0160_0000,
            interfaces: [SupportInterface(id: interface.id, role: .digitizer, usages: [.init(page: 0x0D, usage: 0x05)],
                                          descriptor: interface.descriptor, maxInputReportSize: 6)])
        input.identity = SupportIdentity(input.device)
        let files = SupportReport.files(input)
        let switches = try Fixture.json(files[named: "switches.json"])
        XCTAssertEqual(switches["skipped"] as? Bool, true)
        XCTAssertEqual(switches["why"] as? String,
                       "digitiser: Tactile drives only touchscreens, so it read and switched nothing; its digitiser interfaces, "
                       + "a touch pad's included, were only listened to")
        let summary = String(decoding: try XCTUnwrap(files[named: "summary.txt"]).data, as: UTF8.self)
        XCTAssertTrue(summary.contains("Skipped: Tactile drives only touchscreens, so it read and switched nothing on this digitiser."),
                      summary)
    }

    func testTouchesJSON() throws {
        let touches = try Fixture.json(SupportReport.files(try Fixture.ilitekInput())[named: "touches.json"])
        let steps = try XCTUnwrap(touches["steps"] as? [[String: Any]])
        XCTAssertEqual(steps.map { $0["fingers"] as? Int }, [1, 2, 5])
        XCTAssertEqual(steps.map { $0["ending"] as? String }, ["done", "skipped", "time up"])
        let one = steps[0]
        XCTAssertEqual(one["origin"] as? String, "touchInterface")
        XCTAssertEqual(one["fingers_at_once"] as? [Int], [1])
        XCTAssertEqual(one["reports_seen"] as? Int, 40)
        let reports = try XCTUnwrap(one["reports"] as? [[String: Any]])
        XCTAssertEqual(reports.count, 40)
        XCTAssertEqual(reports[1]["interface"] as? Int, 1)
        XCTAssertEqual(reports[1]["bytes"] as? String, "04010100")
        XCTAssertEqual(reports[1]["ms"] as? Double, 510)
        let interfaces = try XCTUnwrap(one["interfaces"] as? [[String: Any]])
        XCTAssertEqual(interfaces.map { $0["role"] as? String }, ["touch", "mouse"])
        XCTAssertEqual(interfaces[0]["x_range"] as? [Double], [0.25, 0.5])
        XCTAssertEqual(try XCTUnwrap(interfaces[0]["reports_per_second"] as? Double), 100, accuracy: 1e-6)
        XCTAssertNil(interfaces[1]["reports_per_second"])
    }

    func testRawReportsCanBeTrimmed() throws {
        let files = SupportReport.files(try Fixture.ilitekInput(), reportsPerStep: 5)
        let steps = try XCTUnwrap(try Fixture.json(files[named: "touches.json"])["steps"] as? [[String: Any]])
        XCTAssertEqual((steps[0]["reports"] as? [Any])?.count, 5)
        XCTAssertEqual(steps[0]["reports_seen"] as? Int, 40, "what was seen still says so")
        XCTAssertEqual(steps[0]["reports_kept"] as? Int, 5)
    }

    func testMacJSON() throws {
        let mac = try Fixture.json(SupportReport.files(try Fixture.ilitekInput())[named: "mac.json"])
        XCTAssertEqual(mac as NSDictionary, [
            "model": "Mac15,6", "macos": "26.1", "tactile_version": "0.7.0", "tactile_build": "512", "displays": 2,
        ] as NSDictionary)
    }

    func testTheLogFileHoldsTheLinesItWasGiven() throws {
        let files = SupportReport.files(try Fixture.ilitekInput(logLines: ["one", "two"]))
        XCTAssertEqual(String(decoding: try XCTUnwrap(files[named: "tactile-log.txt"]).data, as: UTF8.self), "one\ntwo\n")
        let none = SupportReport.files(try Fixture.ilitekInput())
        XCTAssertEqual(String(decoding: try XCTUnwrap(none[named: "tactile-log.txt"]).data, as: UTF8.self),
                       "No lines of Tactile’s log about this touchscreen in this session.\n")
        let trimmed = SupportReport.files(try Fixture.ilitekInput(logLines: ["one", "two", "three"]), logLines: 2)
        XCTAssertEqual(String(decoding: try XCTUnwrap(trimmed[named: "tactile-log.txt"]).data, as: UTF8.self),
                       "(1 earlier line left out)\ntwo\nthree\n")
    }

    func testTheSummarySaysWhatHappenedInPlainWords() throws {
        let text = String(decoding: try XCTUnwrap(SupportReport.files(try Fixture.ilitekInput())[named: "summary.txt"]).data,
                          as: UTF8.self)
        for line in [
            "ILITEK-TP (222a:0001), made by ILITEK: a touchscreen.",
            "Verdict: works with one finger. One finger at a time came through its touch interface.",
            "1. What it is",
            "Interface 1 (touch): Touch Screen; 10 finger collections; 743-byte descriptor.",
            "Interface 2 (mouse): Mouse, Pointer, vendor-defined; 107-byte descriptor.",
            "2. Switches",
            "Interface 1 (touch): held exclusively.",
            "Interface 2 (mouse): held shared (exclusive: IOReturn 0xe00002c5).",
            "Read feature report 0x06 (Contact Count Maximum, certification blob): 258 bytes asked, 258 returned in 0.013 s, IOReturn 0x00000000.",
            "Contact Count Maximum: 10.",
            "No Input Mode setting: nothing written.",
            "3. Touches",
            "One finger: done after 3.3 s. 40 reports; 1 finger at once; read from the touch interface.",
            "Two fingers: skipped after 3.3 s. No reports.",
            "Five fingers: time up after 3.3 s. 3 reports; 1 finger at once; read from the touch interface.",
            "Tactile 0.7.0 (512) on macOS 26.1, Mac15,6, 2 displays.",
        ] {
            XCTAssertTrue(text.contains(line), "missing: \(line)\n\n\(text)")
        }
    }

    func testTheSummaryOfAMouseOnlyDevice() throws {
        let text = String(decoding: try XCTUnwrap(SupportReport.files(Fixture.pointerInput())[named: "summary.txt"]).data,
                          as: UTF8.self)
        for line in [
            "Panel [serial removed] (1234:5678), made by Example Panels: a touchscreen that is only a mouse.",
            "Verdict: works with one finger. It sends one finger, as a mouse.",
            "Skipped: it is only a mouse, so there is nothing to read or switch.",
            "One finger: done after 2.0 s. 2 reports; 1 finger at once; read from the mouse interface.",
        ] {
            XCTAssertTrue(text.contains(line), "missing: \(line)\n\n\(text)")
        }
    }
}
