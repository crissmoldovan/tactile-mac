import Foundation
import XCTest

@testable import TactileUpdates

/// The site's answer is read field by field, every field required and checked, and each thing wrong
/// with it named.
final class AnswerTests: XCTestCase {

    func testTheContractsAnswerIsRead() throws {
        let offer = Fixture.offer()
        let read = try UpdateOffer.read(Fixture.answer(offer)).get()
        XCTAssertEqual(read, offer)
        XCTAssertEqual(read.version.description, "0.6.0")
        XCTAssertEqual(read.build, 412)
        XCTAssertEqual(read.minimumSystemVersion, SystemVersion(major: 14))
        XCTAssertEqual(read.publishedAt, Date(timeIntervalSince1970: 1_794_996_000))
        XCTAssertEqual(read.archive.url.absoluteString, "https://tactilemac.com/api/mac/archive/0.6.0")
        XCTAssertEqual(read.archive.keyID, "t1")
        XCTAssertEqual(read.archive.signature.count, 64)
        XCTAssertEqual(read.paragraphs, ["Faster scrolling.", "A fix."])
    }

    /// The contract's own example, as text: the field names exactly as the website writes them.
    func testTheContractsExampleAsWritten() throws {
        let signature = Data(repeating: 7, count: 64).base64EncodedString()
        let text = """
        { "version": "0.6.0", "build": 412, "minimumSystemVersion": "14.0",
          "publishedAt": "2026-11-18T10:00:00Z", "notes": "One paragraph per line, plain text.",
          "archive": { "url": "https://tactilemac.com/api/mac/archive/0.6.0", "size": 7340032,
                       "sha256": "\(String(repeating: "ab", count: 32))", "signature": "\(signature)", "keyId": "k1" } }
        """
        let offer = try UpdateOffer.read(Data(text.utf8)).get()
        XCTAssertEqual(offer.archive.size, 7_340_032)
        XCTAssertEqual(offer.archive.keyID, "k1")
        XCTAssertEqual(offer.notes, "One paragraph per line, plain text.")
    }

    func testFieldsTheContractDoesntNameAreIgnored() throws {
        let data = Fixture.answer { object in
            object["schema"] = 1
            object["dmg"] = ["name": "Tactile-0.6.0.dmg", "size": 7_864_320]
            var archive = object["archive"] as! [String: Any]
            archive["name"] = "Tactile-0.6.0.zip"
            object["archive"] = archive
        }
        XCTAssertEqual(try UpdateOffer.read(data).get(), Fixture.offer())
    }

    func testAMissingOrNullFieldIsNamed() {
        for field in ["version", "build", "minimumSystemVersion", "publishedAt", "notes", "archive"] {
            XCTAssertEqual(problem(Fixture.answer { $0[field] = nil }), .missing(field), field)
            XCTAssertEqual(problem(Fixture.answer { $0[field] = NSNull() }), .missing(field), "\(field) null")
        }
        for field in ["url", "size", "sha256", "signature", "keyId"] {
            XCTAssertEqual(problem(Fixture.answer { Self.archive(&$0) { $0[field] = nil } }), .missing("archive.\(field)"), field)
        }
    }

    func testAFieldOfTheWrongTypeIsNamed() {
        XCTAssertEqual(problem(Fixture.answer { $0["version"] = 6 }), .invalid("version"))
        XCTAssertEqual(problem(Fixture.answer { $0["build"] = "412" }), .invalid("build"))
        XCTAssertEqual(problem(Fixture.answer { $0["build"] = 412.5 }), .invalid("build"))
        XCTAssertEqual(problem(Fixture.answer { $0["build"] = true }), .invalid("build"))
        XCTAssertEqual(problem(Fixture.answer { $0["archive"] = "Tactile.zip" }), .invalid("archive"))
        XCTAssertEqual(problem(Fixture.answer { Self.archive(&$0) { $0["size"] = "7340032" } }), .invalid("archive.size"))
    }

    func testAValueThatIsntAllowedIsNamed() {
        let cases: [(String, (inout [String: Any]) -> Void)] = [
            ("version", { $0["version"] = "0.6" }),
            ("version", { $0["version"] = "v0.6.0" }),
            ("build", { $0["build"] = 0 }),
            ("build", { $0["build"] = -3 }),
            ("minimumSystemVersion", { $0["minimumSystemVersion"] = "Sonoma" }),
            ("publishedAt", { $0["publishedAt"] = "18 November 2026" }),
            ("publishedAt", { $0["publishedAt"] = "2026-11-18" }),
            ("notes", { $0["notes"] = String(repeating: "x", count: UpdateOffer.longestNotes + 1) }),
            ("archive.url", { Self.archive(&$0) { $0["url"] = "/api/mac/archive/0.6.0" } }),
            ("archive.url", { Self.archive(&$0) { $0["url"] = "ftp://tactilemac.com/x.zip" } }),
            ("archive.url", { Self.archive(&$0) { $0["url"] = "file:///tmp/Tactile.zip" } }),
            ("archive.size", { Self.archive(&$0) { $0["size"] = 0 } }),
            ("archive.size", { Self.archive(&$0) { $0["size"] = UpdateOffer.largestArchive + 1 } }),
            ("archive.sha256", { Self.archive(&$0) { $0["sha256"] = String(repeating: "a", count: 63) } }),
            ("archive.sha256", { Self.archive(&$0) { $0["sha256"] = String(repeating: "A", count: 64) } }),
            ("archive.sha256", { Self.archive(&$0) { $0["sha256"] = String(repeating: "g", count: 64) } }),
            ("archive.signature", { Self.archive(&$0) { $0["signature"] = "not base64!" } }),
            ("archive.signature", { Self.archive(&$0) { $0["signature"] = Data(count: 63).base64EncodedString() } }),
            ("archive.signature", { Self.archive(&$0) {
                $0["signature"] = Data(count: 64).base64EncodedString().replacingOccurrences(of: "=", with: "")
            } }),
            ("archive.keyId", { Self.archive(&$0) { $0["keyId"] = "" } }),
            ("archive.keyId", { Self.archive(&$0) { $0["keyId"] = "k 1" } }),
            ("archive.keyId", { Self.archive(&$0) { $0["keyId"] = String(repeating: "k", count: 33) } }),
        ]
        for (field, change) in cases {
            XCTAssertEqual(problem(Fixture.answer(changes: change)), .invalid(field), field)
        }
    }

    func testFractionsOfASecondAreAllowedInTheDate() throws {
        let offer = try UpdateOffer.read(Fixture.answer { $0["publishedAt"] = "2026-11-18T10:00:00.250Z" }).get()
        XCTAssertEqual(offer.publishedAt.timeIntervalSince1970, 1_794_996_000.25, accuracy: 0.001)
    }

    func testWhatIsntAJSONObjectIsntRead() {
        XCTAssertEqual(problem(Data()), .notJSON)
        XCTAssertEqual(problem(Data("<html>Vercel</html>".utf8)), .notJSON)
        XCTAssertEqual(problem(Data("[1, 2]".utf8)), .notJSON)
        XCTAssertEqual(problem(Data(#"{"error": "no release"}"#.utf8)), .missing("version"))
    }

    func testAnAnswerTooLargeIsntRead() {
        let large = Fixture.answer { $0["padding"] = String(repeating: " ", count: UpdateOffer.largestAnswer) }
        XCTAssertEqual(problem(large), .tooLarge)
    }

    func testTheNotesAreParagraphsOneALine() {
        let offer = Fixture.offer(notes: "First.\n\n  Second, indented.  \r\nThird.\n")
        XCTAssertEqual(offer.paragraphs, ["First.", "Second, indented.", "Third."])
    }

    // MARK: -

    private func problem(_ data: Data) -> AnswerProblem? {
        if case .failure(let problem) = UpdateOffer.read(data) { return problem }
        return nil
    }

    private static func archive(_ object: inout [String: Any], _ change: (inout [String: Any]) -> Void) {
        var archive = object["archive"] as! [String: Any]
        change(&archive)
        object["archive"] = archive
    }
}
