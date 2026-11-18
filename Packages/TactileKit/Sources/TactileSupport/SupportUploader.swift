// Sending a report to tactilemac.com, which relays it to RequestPort: the request as the site reads
// it, its answers, the email and note checks, and which builds may send at all. The network is behind
// `SupportTransport`, so the tests never touch it.

import Foundation
import TactileDevices
import TactileUpdates

/// Who may send: only the official build, to the site its updates ask.
public enum SupportSending: Equatable, Sendable {
    /// The official build: it sends to this site.
    case on(UpdateSite)
    /// Any other build, a fork's or one signed ad hoc: it only offers Save Report….
    case off

    /// From the update decision (`UpdateAvailability`): the official build sends to the site of its
    /// Info.plist (`TACTILE_UPDATE_BASE_URL`), or to the user default `TactileUpdateBaseURL` when that
    /// names a site, exactly as its updates do. Any other build sends nothing anywhere.
    public static func decide(_ availability: UpdateAvailability, overrideBaseURL: String?) -> SupportSending {
        guard case .on(let settings) = availability else { return .off }
        return .on(UpdateSite.resolve(override: overrideBaseURL, fallback: settings.site))
    }
}

/// The `fields` part: what RequestPort files the request by. Exactly these eight, as the site takes them.
public struct SupportFields: Equatable, Sendable, Encodable {
    /// "222a:0001", lower-case.
    public var usbID: String
    /// The product's name, no serial number in it: 1 to 64 characters.
    public var product: String
    /// `full`, `one-finger` or `none`.
    public var verdict: String
    /// `touchscreen` or `mouse-only`: a digitiser Tactile doesn't list goes as a touchscreen.
    public var kind: String
    public var appVersion: String
    public var appBuild: Int
    public var macOS: String
    public var macModel: String

    enum CodingKeys: String, CodingKey {
        case usbID = "usb_id", product, verdict, kind, appVersion = "app_version", appBuild = "app_build", macOS = "macos",
             macModel = "mac_model"
    }

    /// Nil when Tactile's build isn't a number, as only a build from source can be.
    public init?(_ input: SupportReportInput) {
        guard let build = Int(input.mac.tactileBuild), (0...999_999_999).contains(build) else { return nil }
        usbID = input.device.usbID.lowercased()
        product = Self.productName(input)
        verdict = input.verdict.rawValue
        kind = input.device.kind == .mouseOnly ? SupportDeviceKind.mouseOnly.rawValue : SupportDeviceKind.touchscreen.rawValue
        appVersion = input.mac.tactileVersion
        appBuild = build
        macOS = input.mac.macOS
        macModel = input.mac.model
    }

    /// The product's name, redacted, without control characters, at most 64 UTF-16 units (as the
    /// site counts them) and trimmed; "USB device <id>" when nothing is left.
    private static func productName(_ input: SupportReportInput) -> String {
        let redacted = SupportRedaction.redact(input.device.product, serials: [input.device.serial], home: nil)
        var name = String(String.UnicodeScalarView(redacted.unicodeScalars.filter { !SupportForm.isControl($0) }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.utf16.count > 64 { name.removeLast() }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "USB device \(input.device.usbID.lowercased())" : name
    }
}

/// One request: the zip, the email, the note, Tactile's version and build, and the fields.
public struct SupportRequest: Equatable, Sendable {
    public var bundle: Data
    /// Trimmed.
    public var email: String
    /// Cleaned (`SupportForm.cleanNote`); empty for none.
    public var note: String
    public var fields: SupportFields

    /// Nil when the fields can't be made (`SupportFields`).
    public init?(bundle: Data, input: SupportReportInput, email: String, note: String) {
        guard let fields = SupportFields(input) else { return nil }
        self.bundle = bundle
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = SupportForm.cleanNote(note)
        self.fields = fields
    }
}

/// What the site answered, as the sheet tells it.
public enum SupportAnswer: Equatable, Sendable {
    /// 202: RequestPort has it, and has emailed the person a confirm link.
    case sent
    /// A 4xx with `{error, reason}`: the site refused the request, and says why in plain words (an
    /// email that doesn't look right, one RequestPort couldn't email…). The person can fix it and send
    /// again, or save the report.
    case refused(error: String, reason: String)
    /// 429: too many requests from here for now.
    case tryLater
    /// 408 (`too_slow`), or the upload timed out here: it took too long. The person can save the
    /// report, or try again.
    case tooSlow
    /// 503 (`support_unavailable`, sending not switched on yet), 502, any other 5xx, a network
    /// failure, an answer not from the site, anything else: the report wasn't filed. Save Report… is
    /// the way.
    case unavailable
}

/// Makes a request, and gives back the body and how it ended. A redirect is never followed.
public protocol SupportTransport: Sendable {
    func perform(_ request: URLRequest) async throws -> (Data, HTTPResult)
}

/// URLSession, ephemeral: no cookies, no cache, and every redirect refused.
public final class URLSessionSupportTransport: SupportTransport, @unchecked Sendable {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        session = URLSession(configuration: configuration)
    }

    public func perform(_ request: URLRequest) async throws -> (Data, HTTPResult) {
        let (data, response) = try await session.data(for: request, delegate: NoRedirects())
        return (data, HTTPResult(status: (response as? HTTPURLResponse)?.statusCode ?? 0, url: response.url))
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}

/// Sends a report to `<site>/api/support/requests`.
///
/// First it asks `GET <site>/api/support/status`, with a 5-second limit: only
/// `{"available": true}`, from the site, lets the report go. Anything else (`{"available": false}`,
/// another answer, an error, the limit) means sending isn't switched on, and nothing is uploaded.
///
/// The request is `multipart/form-data`, each part once: `bundle` (the zip, as the file
/// `tactile-report.zip`), `email`, `note` (left out when empty), `app` (`{"version", "build"}`) and
/// `fields` (`SupportFields`). The answer counts only when it comes from the site itself.
public struct SupportUploader: Sendable {
    public static let path = "/api/support/requests"
    public static let statusPath = "/api/support/status"
    /// How long the status may take.
    public static let statusSeconds: TimeInterval = 5

    public let site: UpdateSite
    private let transport: SupportTransport
    private let boundary: @Sendable () -> String

    public init(site: UpdateSite, transport: SupportTransport = URLSessionSupportTransport(),
                boundary: @escaping @Sendable () -> String = { "TactileReport-\(UUID().uuidString)" }) {
        self.site = site
        self.transport = transport
        self.boundary = boundary
    }

    public var url: URL { address(Self.path) }
    public var statusURL: URL { address(Self.statusPath) }

    private func address(_ path: String) -> URL {
        var components = URLComponents(url: site.base, resolvingAgainstBaseURL: false)!
        components.path = path
        return components.url!
    }

    /// Whether the site takes reports now: `{"available": true}` with 200, from the site, within
    /// `statusSeconds`. Asks nothing else and sends nothing of a report.
    public func isAvailable() async -> Bool {
        var request = URLRequest(url: statusURL, timeoutInterval: Self.statusSeconds)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, result) = try? await transport.perform(request), result.status == 200,
              let from = result.url, site.isOnSite(from),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return (object["available"] as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue } ?? false
    }

    /// Asks whether the site takes reports, and only then uploads.
    public func send(_ request: SupportRequest) async -> SupportAnswer {
        guard await isAvailable() else { return .unavailable }
        return await upload(request)
    }

    /// Uploads, without asking first: the caller has asked (`isAvailable`). Cancelling the task
    /// cancels the request, though what has already reached the site stays there.
    public func upload(_ request: SupportRequest) async -> SupportAnswer {
        let boundary = boundary()
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = Self.multipart(request, boundary: boundary)
        do {
            let (data, result) = try await transport.perform(urlRequest)
            guard let from = result.url, site.isOnSite(from) else { return .unavailable }
            return Self.answer(status: result.status, body: data)
        } catch let error as URLError where error.code == .timedOut {
            return .tooSlow
        } catch {
            return .unavailable
        }
    }

    /// The body: each part as the site reads it.
    public static func multipart(_ request: SupportRequest, boundary: String) -> Data {
        var body = Data()
        func part(_ name: String, filename: String? = nil, type: String? = nil, _ data: Data) {
            body.append(Data("--\(boundary)\r\n".utf8))
            var disposition = "Content-Disposition: form-data; name=\"\(name)\""
            if let filename { disposition += "; filename=\"\(filename)\"" }
            body.append(Data((disposition + "\r\n").utf8))
            if let type { body.append(Data("Content-Type: \(type)\r\n".utf8)) }
            body.append(Data("\r\n".utf8))
            body.append(data)
            body.append(Data("\r\n".utf8))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let app = (try? encoder.encode(App(version: request.fields.appVersion, build: request.fields.appBuild))) ?? Data()
        let fields = (try? encoder.encode(request.fields)) ?? Data()
        part("bundle", filename: "tactile-report.zip", type: "application/zip", request.bundle)
        part("email", Data(request.email.utf8))
        if !request.note.isEmpty { part("note", Data(request.note.utf8)) }
        part("app", app)
        part("fields", fields)
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    private struct App: Encodable {
        var version: String
        var build: Int
    }

    /// What an answer from the site means.
    public static func answer(status: Int, body: Data) -> SupportAnswer {
        switch status {
        case 202:
            return .sent
        case 429:
            return .tryLater
        case 408:
            return .tooSlow
        case 400..<500:
            guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let error = object["error"] as? String, let reason = object["reason"] as? String
            else { return .unavailable }
            let plain = plainText(reason)
            return plain.isEmpty ? .unavailable : .refused(error: error, reason: plain)
        default:
            return .unavailable
        }
    }

    /// A reason as one plain line of at most 300 characters: no control characters, spaces closed up.
    static func plainText(_ text: String) -> String {
        let spaced = String(String.UnicodeScalarView(text.unicodeScalars.map { SupportForm.isControl($0) ? " " : $0 }))
        let line = spaced.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return String(line.trimmingCharacters(in: .whitespaces).prefix(300))
    }
}

/// The sheet's email and note, checked as the site checks them, so the person hears at once.
public enum SupportForm {
    public static let maxNoteCharacters = 1000
    public static let maxNoteBytes = 5000

    public enum NoteProblem: Equatable, Sendable {
        /// More than 1,000 characters, or more than 5,000 bytes.
        case tooLong
    }

    /// A well-formed address, as the site has it: at most 254 characters with no control
    /// characters; a dot-atom local part of at most 64; an @; and a domain of two or more labels,
    /// the last a name.
    public static func isEmail(_ text: String) -> Bool {
        guard text.utf16.count <= 254, !text.unicodeScalars.contains(where: isControl),
              let at = text.lastIndex(of: "@"), at != text.startIndex
        else { return false }
        let local = String(text[..<at])
        let labels = String(text[text.index(after: at)...]).components(separatedBy: ".")
        let atom = #"[\p{L}\p{N}!#$%&'*+/=?^_`{|}~-]+"#
        guard local.utf16.count <= 64, matches(local, "^\(atom)(?:\\.\(atom))*$") else { return false }
        guard labels.count >= 2, labels.allSatisfy({ matches($0, #"^[\p{L}\p{N}](?:[\p{L}\p{N}-]{0,61}[\p{L}\p{N}])?$"#) }),
              let last = labels.last
        else { return false }
        return matches(last, #"^(?:\p{L}{2,63}|[Xx][Nn]--[a-zA-Z0-9-]{1,59})$"#)
    }

    /// The note as the site will read it: new lines as `\n`, control characters other than tab and
    /// new line taken out, and trimmed.
    public static func cleanNote(_ text: String) -> String {
        let unified = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let kept = unified.unicodeScalars.filter { !isControl($0) || $0 == "\n" || $0 == "\t" }
        return String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Why the site wouldn't take the note (after `cleanNote`), or nil.
    public static func noteProblem(_ note: String) -> NoteProblem? {
        let note = cleanNote(note)
        return note.count > maxNoteCharacters || note.utf8.count > maxNoteBytes ? .tooLong : nil
    }

    /// C0 and C1 control characters, and DEL.
    static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value <= 31 || (127...159).contains(scalar.value)
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
