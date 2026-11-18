// Asking the site and downloading from it: behind a protocol, URLSession in the app and a fake in
// the tests, which never touch the network.

import Foundation

/// How a request ended: its status, and the address the answer finally came from, after any
/// redirects that were followed.
public struct HTTPResult: Equatable, Sendable {
    public var status: Int
    public var url: URL?

    public init(status: Int, url: URL?) {
        self.status = status
        self.url = url
    }
}

/// Getting an answer and downloading a file over HTTP. A redirect is followed only to an address
/// `allowingRedirect` accepts; a refused one ends the request with the redirect's own status (3xx),
/// which the caller reads as refused.
public protocol UpdateNetwork: Sendable {
    /// GETs `url`, and returns the body and how it ended.
    func fetch(_ url: URL, allowingRedirect: @escaping @Sendable (URL) -> Bool) async throws -> (Data, HTTPResult)
    /// GETs `url` into the file `destination`, which must not exist yet, and returns how it ended.
    func download(_ url: URL, to destination: URL, allowingRedirect: @escaping @Sendable (URL) -> Bool) async throws -> HTTPResult
}

/// The network as the app has it: an ephemeral URLSession, with no cookies and no cache, and a
/// delegate on each request that refuses any redirect the caller doesn't allow.
public final class URLSessionUpdateNetwork: UpdateNetwork, @unchecked Sendable {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 15 * 60
        session = URLSession(configuration: configuration)
    }

    public func fetch(_ url: URL, allowingRedirect: @escaping @Sendable (URL) -> Bool) async throws -> (Data, HTTPResult) {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request, delegate: RedirectGuard(allow: allowingRedirect))
        return (data, Self.result(response))
    }

    public func download(_ url: URL, to destination: URL, allowingRedirect: @escaping @Sendable (URL) -> Bool) async throws -> HTTPResult {
        let (temporary, response) = try await session.download(
            for: URLRequest(url: url), delegate: RedirectGuard(allow: allowingRedirect))
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return Self.result(response)
    }

    private static func result(_ response: URLResponse) -> HTTPResult {
        HTTPResult(status: (response as? HTTPURLResponse)?.statusCode ?? 0, url: response.url)
    }
}

/// Refuses a redirect to anywhere `allow` doesn't accept.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let allow: @Sendable (URL) -> Bool

    init(allow: @escaping @Sendable (URL) -> Bool) {
        self.allow = allow
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard let url = request.url, allow(url) else {
            UpdatesLog.log.error("refused a redirect from \(UpdateSite.loggable(response.url), privacy: .public) to \(UpdateSite.loggable(request.url), privacy: .public)")
            return nil
        }
        return request
    }
}
