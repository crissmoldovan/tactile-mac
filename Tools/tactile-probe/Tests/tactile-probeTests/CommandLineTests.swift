import XCTest
@testable import tactile_probe

final class CommandLineTests: XCTestCase {
    private func survey(_ args: String...) throws -> SurveyOptions {
        guard case .survey(let options) = try parseCommandLine(["survey"] + args) else {
            XCTFail("not a survey command")
            throw CommandLineError("not a survey")
        }
        return options
    }

    private func surveyError(_ args: String...) -> String? {
        do {
            _ = try parseCommandLine(["survey"] + args)
            return nil
        } catch let error as CommandLineError {
            return error.message
        } catch {
            return "\(error)"
        }
    }

    // MARK: Commands

    func testListWithAndWithoutJSON() throws {
        XCTAssertEqual(try parseCommandLine(["list"]), .list(jsonPath: nil))
        XCTAssertEqual(try parseCommandLine(["list", "--json", "out.json"]), .list(jsonPath: "out.json"))
    }

    func testVersionHelpAndUnknownCommands() throws {
        XCTAssertEqual(try parseCommandLine(["--version"]), .version)
        XCTAssertEqual(try parseCommandLine(["help"]), .help)
        XCTAssertThrowsError(try parseCommandLine([]))
        XCTAssertThrowsError(try parseCommandLine(["survay"]))
    }

    func testListTakesNoSurveyOptions() {
        XCTAssertThrowsError(try parseCommandLine(["list", "--from", "3"]))
    }

    // MARK: Survey defaults and plain options

    func testSurveyDefaults() throws {
        let options = try survey()
        XCTAssertNil(options.touchscreen)
        XCTAssertNil(options.display)
        XCTAssertEqual(options.selection, .all)
        XCTAssertEqual(options.stepTimeout, 30)
        XCTAssertNil(options.outDir)
        XCTAssertEqual(options.arguments, [])
    }

    func testSurveyKeepsItsArgumentsForTheFile() throws {
        let options = try survey("--touchscreen", "222a:0001", "--from", "16")
        XCTAssertEqual(options.arguments, ["--touchscreen", "222a:0001", "--from", "16"])
    }

    func testOutAndStepTimeout() throws {
        let options = try survey("--out", "~/Desktop", "--step-timeout", "45")
        XCTAssertEqual(options.outDir, "~/Desktop")
        XCTAssertEqual(options.stepTimeout, 45)
        XCTAssertNotNil(surveyError("--step-timeout", "0"))
        XCTAssertNotNil(surveyError("--step-timeout", "soon"))
    }

    func testUnknownMissingAndRepeatedOptionsAreRefused() {
        XCTAssertNotNil(surveyError("--screen", "HDMI"))
        XCTAssertNotNil(surveyError("--display"))
        XCTAssertNotNil(surveyError("--display", "HDMI", "--display", "12.3FHD"))
    }

    // MARK: --no-windows

    func testWindowsAreOnUnlessSwitchedOff() throws {
        XCTAssertTrue(try survey().showsWindows)
        let options = try survey("--no-windows", "--touchscreen", "222a:0001")
        XCTAssertFalse(options.showsWindows)
        XCTAssertEqual(options.touchscreen, "222a:0001", "a switch takes no value")
        XCTAssertFalse(try survey("--touchscreen", "222a:0001", "--no-windows").showsWindows)
        XCTAssertNotNil(surveyError("--no-windows", "--no-windows"))
        XCTAssertThrowsError(try parseCommandLine(["list", "--no-windows"]))
    }

    // MARK: --touchscreen

    func testTouchscreenIsAVendorAndProductID() throws {
        XCTAssertEqual(try survey("--touchscreen", "222a:0001").touchscreen, "222a:0001")
        XCTAssertEqual(try survey("--touchscreen", "27C0:0859").touchscreen, "27c0:0859", "written in lower case, as the survey writes USB IDs")
        for bad in ["222a0001", "ILITEK-TP", "222a:1", "222a:00001", "zzzz:0001", ""] {
            let message = surveyError("--touchscreen", bad)
            XCTAssertNotNil(message, bad)
            XCTAssertTrue(message?.contains("vendor:product") == true, "\(bad): \(message ?? "")")
        }
    }

    // MARK: --display

    func testDisplayIsKeptAsTyped() throws {
        XCTAssertEqual(try survey("--display", "HDMI").display, "HDMI")
        XCTAssertEqual(try survey("--display", "3").display, "3")
        XCTAssertNotNil(surveyError("--display", "  "))
    }

    // MARK: --from and --only

    func testFrom() throws {
        XCTAssertEqual(try survey("--from", "16").selection, .from(16))
        XCTAssertEqual(try survey("--from", "1").selection, .from(1))
        XCTAssertEqual(try survey("--from", "\(Takes.count)").selection, .from(Takes.count))
        for bad in ["0", "\(Takes.count + 1)", "-3", "sixteen", "16,17"] {
            XCTAssertNotNil(surveyError("--from", bad), bad)
        }
    }

    func testOnlyListsAreSortedAndDeduplicated() throws {
        XCTAssertEqual(try survey("--only", "16,17,22").selection, .only([16, 17, 22]))
        XCTAssertEqual(try survey("--only", "22,16,16").selection, .only([16, 22]))
        XCTAssertEqual(try survey("--only", "9").selection, .only([9]))
        XCTAssertEqual(try survey("--only", " 16 , 18 ").selection, .only([16, 18]))
    }

    func testOnlyTakesRanges() throws {
        XCTAssertEqual(try survey("--only", "16-20,22").selection, .only([16, 17, 18, 19, 20, 22]))
        XCTAssertEqual(try survey("--only", "5-8").selection, .only([5, 6, 7, 8]))
    }

    func testBadOnlyListsAreRefused() {
        for bad in ["", ",", "16,,17", "0", "\(Takes.count + 1)", "20-16", "16-", "a,b", "16-17-18"] {
            XCTAssertNotNil(surveyError("--only", bad), bad)
        }
    }

    func testFromAndOnlyTogetherAreRefused() {
        let message = surveyError("--from", "16", "--only", "17")
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("--from") == true && message?.contains("--only") == true)
    }
}
