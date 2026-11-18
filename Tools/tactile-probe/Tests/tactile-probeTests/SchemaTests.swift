import XCTest
@testable import tactile_probe

/// The survey file: old files still read, and a file with the new takes reads through the tool's
/// own types and through TactileKit's loader (`SurveyFixtures.swift`, linked into this target).
final class SchemaTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("tactile-probe-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let folder { try? FileManager.default.removeItem(at: folder) }
    }

    private static func firstSurvey(_ name: String) throws -> SurveyFile {
        let url = SurveyFixtures.surveysDirectory(from: #filePath).appendingPathComponent(name)
        return try JSONDecoder().decode(SurveyFile.self, from: Data(contentsOf: url))
    }

    static let surveyAName = "tactile-survey-20261114-070943.json"
    static let surveyBName = "tactile-survey-20261114-071756.json"

    // MARK: Old files

    func testTheFirstSurveysStillDecodeWithTheToolsTypes() throws {
        let a = try Self.firstSurvey(Self.surveyAName)
        let b = try Self.firstSurvey(Self.surveyBName)
        XCTAssertEqual(a.touchscreens.map { $0.takes.count }, [20, 2])
        XCTAssertEqual(b.touchscreens.map { $0.takes.count }, [0, 16])
        XCTAssertEqual(b.touchscreens[1].takes.last?.number, 16)
        // What they lack, they lack as absent keys.
        XCTAssertNil(a.settings.arguments)
        XCTAssertNil(a.settings.takesSelected)
        XCTAssertNil(a.touchscreens[0].display?.source)
    }

    func testTheFirstSurveysStillLoadThroughTactileKitsLoader() {
        XCTAssertEqual(SurveyFixtures.surveyA.touchscreen(vendorID: 0x27c0, productID: 0x0859)?.takes.count, 20)
        XCTAssertEqual(SurveyFixtures.surveyB.touchscreen(vendorID: 0x222a, productID: 0x0001)?.takes.count, 16)
    }

    // MARK: A file with the new takes

    /// A survey file as a run of `survey --touchscreen 222a:0001 --display HDMI --from 16` writes it,
    /// with real ILITEK reports (survey B's pinch) standing in for each take's touches.
    private func newSurvey() throws -> SurveyFile {
        let b = try Self.firstSurvey(Self.surveyBName)
        let reports = b.touchscreens[1].takes.first { $0.number == 15 }!.reports
        let takes = TakeSelection.from(16).takes.map { spec in
            Take(id: spec.id, number: spec.number, title: spec.title, prompt: spec.prompt, mode: "exclusive", inputMode: nil,
                 exclusiveInterfaces: ["touchscreen", "mouse"], attempt: 1, result: "recorded", endReason: "lifted",
                 summary: "Got it: 2 fingers, lifted cleanly.", promptedAtNs: 1, startedAtNs: reports.first?.hostTimeNs,
                 endedAtNs: reports.last.map { $0.hostTimeNs + 700_000_000 }, waitedSeconds: 1.5, durationSeconds: 2.9,
                 reportSpanSeconds: 2.2, reportCounts: ["touchscreen": reports.count], otherTouchscreenReports: 0,
                 staleReportsDiscarded: 0, pointer: nil, facts: nil, tap: nil, reports: reports)
        }
        let list = b.list
        let sections = list.touchscreens.map { listed -> TouchscreenSurvey in
            let chosen = listed.usbID == "222a:0001"
            return TouchscreenSurvey(
                number: listed.number, locationID: listed.locationID,
                name: "\(listed.product ?? "") by \(listed.manufacturer ?? "")",
                identifiedBy: chosen ? IdentifiedBy.named : IdentifiedBy.notChosen,
                status: chosen ? "done" : SectionStatus.notChosen,
                display: chosen ? DisplayAnswer(answer: "HDMI", displayID: 3, name: "HDMI", choices: [], source: .argument) : nil,
                inputModeFound: nil, inputModeFoundName: nil, actions: [], takes: chosen ? takes : [])
        }
        return SurveyFile(
            format: "tactile-probe survey", formatVersion: 1, environment: list.environment,
            settings: SurveySettings(stepTimeoutSeconds: 30, takeLimitSeconds: 15, liftQuietSeconds: 0.7, quietWithContactsDownSeconds: 3,
                                     arguments: ["--touchscreen", "222a:0001", "--display", "HDMI", "--from", "16"],
                                     takesSelected: TakeSelection.from(16).numbers),
            list: list, conflictingApps: [], touchscreens: sections, restore: [],
            completed: true, interrupted: false, endedBecause: "finished")
    }

    private func write(_ survey: SurveyFile) throws -> URL {
        let url = folder.appendingPathComponent("tactile-survey-new.json")
        try encodeSurvey(survey).write(to: url)
        return url
    }

    /// The loader reads files by name from Fixtures/surveys; this reaches the temporary
    /// folder from there, so nothing is written into the repository. It climbs to the root with
    /// more ".." than needed (they stop at the root), so a link in the checkout's path can't
    /// leave it short.
    private func loaderName(for url: URL) -> String {
        let surveys = SurveyFixtures.surveysDirectory(from: #filePath).pathComponents
        let target = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        return (Array(repeating: "..", count: surveys.count + 8) + target.dropFirst()).joined(separator: "/")
    }

    func testANewFileRoundTripsThroughTheToolsTypes() throws {
        let original = try newSurvey()
        let decoded = try JSONDecoder().decode(SurveyFile.self, from: Data(contentsOf: write(original)))
        XCTAssertEqual(decoded.settings.arguments, ["--touchscreen", "222a:0001", "--display", "HDMI", "--from", "16"])
        XCTAssertEqual(decoded.settings.takesSelected, [16, 17, 18, 19, 20, 21, 22])
        let ilitek = decoded.touchscreens[1]
        XCTAssertEqual(ilitek.display?.source, .argument)
        XCTAssertEqual(ilitek.identifiedBy, "named with --touchscreen")
        XCTAssertEqual(decoded.touchscreens[0].status, "not chosen")
        XCTAssertEqual(ilitek.takes.map(\.number), [16, 17, 18, 19, 20, 21, 22])
        XCTAssertEqual(ilitek.takes.map(\.id), TakeSelection.from(16).takes.map(\.id))
        XCTAssertEqual(ilitek.takes[5].reports.map(\.bytes), original.touchscreens[1].takes[5].reports.map(\.bytes))
    }

    func testTheSourceIsWrittenInWords() throws {
        let text = String(decoding: try encodeSurvey(try newSurvey()), as: UTF8.self)
        XCTAssertTrue(text.contains("\"source\" : \"--display\""))
        XCTAssertFalse(text.contains("null"), "an absent key means not applicable; null is never written")
    }

    func testANewFileLoadsThroughTactileKitsLoader() throws {
        let original = try newSurvey()
        let url = try write(original)
        let loaded = SurveyFixtures.Survey.load(fileName: loaderName(for: url))

        let ilitek = try XCTUnwrap(loaded.touchscreen(vendorID: 0x222a, productID: 0x0001))
        XCTAssertEqual(ilitek.takes.map(\.number), [16, 17, 18, 19, 20, 21, 22])
        XCTAssertEqual(ilitek.takes.map(\.title), TakeSelection.from(16).takes.map(\.title))
        XCTAssertEqual(ilitek.interfaces.map(\.key), ["touchscreen", "mouse"])
        XCTAssertFalse(ilitek.interfaces[0].descriptor.isEmpty)

        let recorded = original.touchscreens[1].takes[6].reports
        let read = ilitek.takes[6].reports
        XCTAssertEqual(read.count, recorded.count)
        XCTAssertEqual(read.first?.interfaceKey, "touchscreen")
        XCTAssertEqual(read.first?.hostTime, recorded.first.map { TimeInterval($0.hostTimeNs) / 1_000_000_000 })
        XCTAssertEqual(read.first?.fingers?.count, recorded.first?.fingers?.count)
        XCTAssertEqual(read.first?.bytes.count, recorded.first?.length)

        let wch = try XCTUnwrap(loaded.touchscreen(vendorID: 0x27c0, productID: 0x0859))
        XCTAssertEqual(wch.takes.count, 0, "the touchscreen not chosen is listed, with no takes")
    }
}
