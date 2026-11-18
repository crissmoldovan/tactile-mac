import Foundation
import TactileDevices
import TactileSupport
import TactileUpdates
import XCTest

/// Sending a report to tactilemac.com: the request, as the relay reads it; each of its answers; the
/// email and note checks; and that only the official build sends. A fake transport answers: nothing
/// here touches the network.
final class SupportUploaderTests: XCTestCase {

    /// Records each request, and answers as told: the status, `{"available":true}` unless told
    /// otherwise; the upload, `answer`.
    private final class FakeTransport: SupportTransport, @unchecked Sendable {
        var requests: [URLRequest] = []
        var answer: (Data, HTTPResult)?
        var failure: Error?
        var status: (Data, HTTPResult)?
        var statusFailure: Error?

        func perform(_ request: URLRequest) async throws -> (Data, HTTPResult) {
            requests.append(request)
            if request.url?.path == "/api/support/status" {
                if let statusFailure { throw statusFailure }
                return status ?? (Data(#"{"available":true}"#.utf8), HTTPResult(status: 200, url: request.url))
            }
            if let failure { throw failure }
            return answer ?? (Data(), HTTPResult(status: 500, url: request.url))
        }

        var uploads: [URLRequest] { requests.filter { $0.httpMethod == "POST" } }
    }

    private let site = UpdateSite.builtIn
    private let endpoint = URL(string: "https://tactilemac.com/api/support/requests")!

    private func request(note: String = "It only clicks.", build: String = "512") throws -> SupportRequest {
        var input = try Fixture.ilitekInput()
        input.mac.tactileBuild = build
        return try XCTUnwrap(SupportRequest(bundle: Data([0x50, 0x4B, 0x05, 0x06]), input: input, email: " someone@example.com ",
                                            note: note))
    }

    private func answer(_ status: Int, _ body: String = "", from url: URL? = nil) async throws -> SupportAnswer {
        let transport = FakeTransport()
        transport.answer = (Data(body.utf8), HTTPResult(status: status, url: url ?? endpoint))
        return await SupportUploader(site: site, transport: transport).send(try request())
    }

    // MARK: - The request

    /// The parts of a multipart body, by name: their headers and their bytes.
    private func parts(_ body: Data, boundary: String) -> [(name: String, headers: String, data: Data)] {
        let delimiter = Data("--\(boundary)".utf8)
        var parts: [(String, String, Data)] = []
        var rest = body[...]
        while let start = rest.range(of: delimiter) {
            rest = rest[start.upperBound...]
            if rest.starts(with: Data("--".utf8)) { break }
            guard let end = rest.range(of: delimiter) else { break }
            var part = rest[rest.startIndex..<end.lowerBound]
            part = part.dropFirst(2).dropLast(2)  // the CRLF after the delimiter, and the one before the next
            guard let split = part.range(of: Data("\r\n\r\n".utf8)) else { continue }
            let headers = String(decoding: part[part.startIndex..<split.lowerBound], as: UTF8.self)
            let name = headers.components(separatedBy: "name=\"").dropFirst().first?.components(separatedBy: "\"").first ?? ""
            parts.append((name, headers, Data(part[split.upperBound...])))
        }
        return parts
    }

    func testTheRequestIsAMultipartPOSTToTheSite() async throws {
        let transport = FakeTransport()
        transport.answer = (Data(#"{"status":"check-email"}"#.utf8), HTTPResult(status: 202, url: endpoint))
        let uploader = SupportUploader(site: site, transport: transport, boundary: { "TactileBoundary1234" })
        _ = await uploader.send(try request())
        let sent = try XCTUnwrap(transport.uploads.first)
        XCTAssertEqual(sent.url, endpoint)
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "multipart/form-data; boundary=TactileBoundary1234")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Accept"), "application/json")

        let body = try XCTUnwrap(sent.httpBody)
        XCTAssertTrue(body.suffix(25) == Data("--TactileBoundary1234--\r\n".utf8))
        let parts = parts(body, boundary: "TactileBoundary1234")
        XCTAssertEqual(parts.map(\.name), ["bundle", "email", "note", "app", "fields"])
        XCTAssertTrue(parts[0].headers.contains(#"filename="tactile-report.zip""#))
        XCTAssertTrue(parts[0].headers.contains("Content-Type: application/zip"))
        XCTAssertEqual(parts[0].data, Data([0x50, 0x4B, 0x05, 0x06]))
        XCTAssertEqual(String(decoding: parts[1].data, as: UTF8.self), "someone@example.com")
        XCTAssertEqual(String(decoding: parts[2].data, as: UTF8.self), "It only clicks.")
        for part in parts.dropFirst() {
            XCTAssertFalse(part.headers.contains("filename"), "\(part.name) is a plain field")
        }

        let app = try XCTUnwrap(JSONSerialization.jsonObject(with: parts[3].data) as? [String: Any])
        XCTAssertEqual(app as NSDictionary, ["version": "0.7.0", "build": 512] as NSDictionary)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: parts[4].data) as? [String: Any])
        XCTAssertEqual(fields as NSDictionary, [
            "usb_id": "222a:0001", "product": "ILITEK-TP", "verdict": "one-finger", "kind": "touchscreen",
            "app_version": "0.7.0", "app_build": 512, "macos": "26.1", "mac_model": "Mac15,6",
        ] as NSDictionary)
    }

    func testAnEmptyNoteIsLeftOut() async throws {
        let transport = FakeTransport()
        let uploader = SupportUploader(site: site, transport: transport, boundary: { "B0" })
        _ = await uploader.send(try request(note: "  \n "))
        let body = try XCTUnwrap(transport.uploads.first?.httpBody)
        XCTAssertEqual(parts(body, boundary: "B0").map(\.name), ["bundle", "email", "app", "fields"])
    }

    func testTheFieldsAreWhatTheSiteTakes() throws {
        var pointer = Fixture.pointerInput()
        let fields = try XCTUnwrap(SupportFields(pointer))
        XCTAssertEqual(fields.kind, "mouse-only")
        XCTAssertEqual(fields.product, "Panel [serial removed]", "no serial number")
        XCTAssertEqual(fields.verdict, "one-finger")
        XCTAssertEqual(fields.appBuild, 512)

        pointer.device = SupportDevice(
            id: "ABCD:00EF@1", kind: .digitizer, vendorID: 0xABCD, productID: 0x00EF, product: String(repeating: "Pen. ", count: 30),
            manufacturer: "", serial: "", locationID: 1, interfaces: pointer.device.interfaces)
        let digitizer = try XCTUnwrap(SupportFields(pointer))
        XCTAssertEqual(digitizer.usbID, "abcd:00ef", "lower-case")
        XCTAssertEqual(digitizer.kind, "touchscreen", "the site knows touchscreens and mouse-only ones")
        XCTAssertEqual(digitizer.product.utf16.count, 64)
        XCTAssertFalse(digitizer.product.hasSuffix(" "))

        pointer.device = SupportDevice(
            id: "x", kind: .mouseOnly, vendorID: 1, productID: 2, product: " \u{7}", manufacturer: "", serial: "", locationID: 1,
            interfaces: [])
        XCTAssertEqual(SupportFields(pointer)?.product, "USB device 0001:0002", "never empty")

        pointer.mac.tactileBuild = "unknown"
        XCTAssertNil(SupportFields(pointer), "a build that isn't a number can't be sent")
        XCTAssertNil(SupportRequest(bundle: Data(), input: pointer, email: "someone@example.com", note: ""))
    }

    // MARK: - The answers

    func testTheSitesAnswers() async throws {
        let sent = try await answer(202, #"{"status":"check-email"}"#)
        XCTAssertEqual(sent, .sent)
        let badEmail = try await answer(400, #"{"error":"email_invalid","reason":"That email address doesn't look right."}"#)
        XCTAssertEqual(badEmail, .refused(error: "email_invalid", reason: "That email address doesn't look right."))
        let mailFailed = try await answer(400, #"{"error":"mail_failed","reason":"We couldn't email you; check the address."}"#)
        XCTAssertEqual(mailFailed, .refused(error: "mail_failed", reason: "We couldn't email you; check the address."))
        let tooLarge = try await answer(413, #"{"error":"too_large","reason":"The report is larger than 2 MB."}"#)
        XCTAssertEqual(tooLarge, .refused(error: "too_large", reason: "The report is larger than 2 MB."))
        let limited = try await answer(429, #"{"error":"rate_limited","reason":"Too many."}"#)
        XCTAssertEqual(limited, .tryLater)

        for (status, body) in [(503, #"{"error":"support_unavailable"}"#), (502, #"{"error":"upstream"}"#), (500, ""), (504, "<html>"),
                               (400, "not json"), (400, #"{"error":"x"}"#), (404, ""), (200, #"{"status":"check-email"}"#),
                               (301, "")] {
            let unavailable = try await answer(status, body)
            XCTAssertEqual(unavailable, .unavailable, "\(status) \(body)")
        }
        let elsewhere = try await answer(202, #"{"status":"check-email"}"#, from: URL(string: "https://example.com/api/support/requests"))
        XCTAssertEqual(elsewhere, .unavailable, "an answer from another site isn't the site's")
    }

    func testAReasonIsShownAsPlainText() async throws {
        let long = String(repeating: "a", count: 400)
        let refused = try await answer(400, #"{"error":"x","reason":"Line one\u0007\n line two  \#(long)"}"#)
        guard case .refused(_, let reason) = refused else { return XCTFail("\(refused)") }
        XCTAssertTrue(reason.hasPrefix("Line one line two aaa"))
        XCTAssertEqual(reason.count, 300)
    }

    // MARK: - Whether sending is switched on

    func testTheStatusIsAskedBeforeAnythingIsUploaded() async throws {
        let transport = FakeTransport()
        transport.answer = (Data(#"{"status":"check-email"}"#.utf8), HTTPResult(status: 202, url: endpoint))
        let answer = await SupportUploader(site: site, transport: transport).send(try request())
        XCTAssertEqual(answer, .sent)
        XCTAssertEqual(transport.requests.map(\.httpMethod), ["GET", "POST"])
        let status = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(status.url, URL(string: "https://tactilemac.com/api/support/status"))
        XCTAssertEqual(status.timeoutInterval, 5)
        XCTAssertNil(status.httpBody, "the status carries nothing of the report")
    }

    func testWhenSendingIsntSwitchedOnNothingIsUploaded() async throws {
        let site = self.site
        let notAvailable: [(Data, HTTPResult)] = [
            (Data(#"{"available":false}"#.utf8), HTTPResult(status: 200, url: site.base.appendingPathComponent("api/support/status"))),
            (Data(#"{"available":"yes"}"#.utf8), HTTPResult(status: 200, url: site.base.appendingPathComponent("api/support/status"))),
            (Data("not json".utf8), HTTPResult(status: 200, url: site.base.appendingPathComponent("api/support/status"))),
            (Data(#"{"available":true}"#.utf8), HTTPResult(status: 503, url: site.base.appendingPathComponent("api/support/status"))),
            (Data(#"{"available":true}"#.utf8), HTTPResult(status: 404, url: site.base.appendingPathComponent("api/support/status"))),
            (Data(#"{"available":true}"#.utf8), HTTPResult(status: 200, url: URL(string: "https://example.com/api/support/status"))),
        ]
        for status in notAvailable {
            let transport = FakeTransport()
            transport.status = status
            let uploader = SupportUploader(site: site, transport: transport)
            let available = await uploader.isAvailable()
            XCTAssertFalse(available, "\(status.1.status) \(String(decoding: status.0, as: UTF8.self))")
            let answer = await uploader.send(try request())
            XCTAssertEqual(answer, .unavailable)
            XCTAssertEqual(transport.uploads, [], "nothing is uploaded")
        }

        let timedOut = FakeTransport()
        timedOut.statusFailure = URLError(.timedOut)
        let answer = await SupportUploader(site: site, transport: timedOut).send(try request())
        XCTAssertEqual(answer, .unavailable)
        XCTAssertEqual(timedOut.uploads, [])
    }

    /// The switch can flip between the status and the upload: a 503 then is unavailable all the same.
    func testA503AfterTheStatusSaidYesIsUnavailable() async throws {
        let unavailable = try await answer(503, #"{"error":"support_unavailable"}"#)
        XCTAssertEqual(unavailable, .unavailable)
    }

    func testANetworkFailureIsUnavailable() async throws {
        let transport = FakeTransport()
        transport.failure = URLError(.notConnectedToInternet)
        let answer = await SupportUploader(site: site, transport: transport).send(try request())
        XCTAssertEqual(answer, .unavailable)
    }

    // MARK: - Only the official build sends

    func testOnlyTheOfficialBuildSends() throws {
        let preview = try XCTUnwrap(UpdateSite(base: "https://preview.tactilemac.com"))
        let settings = UpdateSettings(site: preview, keys: UpdateSettings.builtIn.keys)
        XCTAssertEqual(SupportSending.decide(.on(settings), overrideBaseURL: nil), .on(preview), "the site updates ask")
        XCTAssertEqual(SupportSending.decide(.on(.builtIn), overrideBaseURL: "http://localhost:3200"),
                       .on(try XCTUnwrap(UpdateSite(base: "http://localhost:3200"))), "the same override as updates")
        XCTAssertEqual(SupportSending.decide(.on(.builtIn), overrideBaseURL: "ftp://nowhere"), .on(.builtIn))
        for reason in [UpdatesOffReason.otherBundleIdentifier, .notSignedByTheDeveloper, .unusableSetting("TactileUpdateBaseURL")] {
            XCTAssertEqual(SupportSending.decide(.off(reason), overrideBaseURL: "https://tactilemac.com"), .off, "\(reason)")
        }
    }

    // MARK: - The email and the note

    func testTheEmailIsCheckedAsTheSiteChecksIt() {
        for good in ["someone@example.com", "a.b+c@mail.example.co.uk", "jürgen@exämple.de", "x@xn--bcher-kva.example"] {
            XCTAssertTrue(SupportForm.isEmail(good), good)
        }
        for bad in ["", "someone", "@example.com", "someone@", "someone@example", "some one@example.com", "a..b@example.com",
                    "someone@-example.com", "someone@example.c", "someone@example.123", "a@b@c.com",
                    String(repeating: "a", count: 65) + "@example.com", "tab\t@example.com"] {
            XCTAssertFalse(SupportForm.isEmail(bad), bad)
        }
    }

    func testTheNoteIsCheckedAsTheSiteChecksIt() {
        XCTAssertEqual(SupportForm.cleanNote("  one\r\ntwo\rthree\u{7}\tfour \n"), "one\ntwo\nthree\tfour")
        XCTAssertNil(SupportForm.noteProblem(String(repeating: "a", count: 1000)))
        XCTAssertEqual(SupportForm.noteProblem(String(repeating: "a", count: 1001)), .tooLong)
        XCTAssertNil(SupportForm.noteProblem(String(repeating: "😀", count: 1000)), "1,000 characters, 4,000 bytes")
        XCTAssertEqual(SupportForm.noteProblem(String(repeating: "👍🏽", count: 700)), .tooLong, "700 characters, 5,600 bytes")
        XCTAssertNil(SupportForm.noteProblem(""))
    }
}
