// Where Tactile asks for updates, and where it lets an update come from.

import Foundation

/// Tactile's website, which tells it the newest version and hands it the update. The official
/// build asks the site its Info.plist names (`UpdateSettings`, from the build setting
/// `TACTILE_UPDATE_BASE_URL`): `https://tactilemac.com`, the one thing an installed copy can never
/// stop depending on, unless the build says otherwise. The user default `TactileUpdateBaseURL`
/// changes it, for a copy pointed at a preview site: an `https` origin, or `http` on this Mac
/// (`localhost`, `127.0.0.1`) for the website run locally; anything else in it is ignored. A build
/// that isn't the official one asks no site at all (`UpdateAvailability`).
///
/// Whatever the address, an update is installed only when it passes every check of
/// `UpdateVerifier`: the site is a courier, not trusted with what it carries.
public struct UpdateSite: Equatable, Sendable {
    /// The built-in address: what the official build asks when its Info.plist names no other.
    public static let builtIn = UpdateSite(validated: URL(string: "https://tactilemac.com")!)
    /// The user default that can point Tactile elsewhere.
    public static let overrideKey = "TactileUpdateBaseURL"
    /// The hosts GitHub hands a release's files out from, which the archive route may redirect to.
    public static let downloadHosts: Set<String> = ["objects.githubusercontent.com", "release-assets.githubusercontent.com"]

    /// The origin: a scheme, a host and perhaps a port, with no path.
    public let base: URL

    private init(validated base: URL) {
        self.base = base
    }

    /// The site at `text`, or nil when it isn't an origin Tactile may ask: `https://host[:port]`, or
    /// `http://` on this Mac unless `allowingHTTPOnThisMac` is false (the Info.plist's site is https
    /// only; the user default may name the website run locally), with no user, password, path (but
    /// "/"), query or fragment.
    public init?(base text: String, allowingHTTPOnThisMac: Bool = true) {
        guard let components = URLComponents(string: text.trimmingCharacters(in: .whitespaces)),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil,
              components.path.isEmpty || components.path == "/",
              components.query == nil, components.fragment == nil
        else { return nil }
        switch scheme {
        case "https": break
        case "http": guard allowingHTTPOnThisMac, Self.isThisMac(host) else { return nil }
        default: return nil
        }
        var origin = URLComponents()
        origin.scheme = scheme
        origin.host = host
        origin.port = components.port
        guard let url = origin.url else { return nil }
        self.init(validated: url)
    }

    /// The site to ask: the override when it is a valid origin, else `fallback`, the site the
    /// build names (the built-in address unless it says otherwise).
    public static func resolve(override text: String?, fallback: UpdateSite = builtIn) -> UpdateSite {
        guard let text, !text.isEmpty else { return fallback }
        guard let site = UpdateSite(base: text) else {
            UpdatesLog.log.error("\(overrideKey, privacy: .public) “\(text, privacy: .public)” isn’t an https origin; asking \(fallback.base.absoluteString, privacy: .public)")
            return fallback
        }
        return site
    }

    /// The host, as the person reads it: "tactilemac.com".
    public var host: String { base.host ?? base.absoluteString }

    /// `<base>/api/mac/update?version=<version>&build=<build>`: the newest release. The query is
    /// for the site's logs; the answer doesn't depend on it.
    public func answerURL(version: String, build: String) -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.path = "/api/mac/update"
        components.percentEncodedQueryItems = [
            URLQueryItem(name: "version", value: Self.queryValue(version)),
            URLQueryItem(name: "build", value: Self.queryValue(build)),
        ]
        return components.url!
    }

    /// `text` percent-encoded but for RFC 3986's unreserved characters, so nothing in it can end the
    /// value or start another.
    private static func queryValue(_ text: String) -> String {
        var unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        unreserved.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// Whether `url` is on this site's origin: the same scheme, host and port (a missing port being
    /// the scheme's own), with no user or password in it.
    public func isOnSite(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil,
              let scheme = components.scheme?.lowercased(), let host = components.host?.lowercased()
        else { return false }
        return scheme == base.scheme
            && host == base.host
            && Self.port(components.port, scheme: scheme) == Self.port(base.port, scheme: scheme)
    }

    /// Whether the download of the archive may go to `url`: this site's origin, or one of GitHub's
    /// download hosts over https on its usual port.
    public func allowsDownload(from url: URL) -> Bool {
        if isOnSite(url) { return true }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil,
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased()
        else { return false }
        return Self.downloadHosts.contains(host) && (components.port == nil || components.port == 443)
    }

    /// `url` as the log may show it: its scheme, host, port and path, never its query or fragment,
    /// which for GitHub's download addresses carry a short-lived signature.
    public static func loggable(_ url: URL?) -> String {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "?" }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string ?? "?"
    }

    private static func port(_ port: Int?, scheme: String) -> Int? {
        port ?? (scheme == "https" ? 443 : scheme == "http" ? 80 : nil)
    }

    private static func isThisMac(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1"
    }
}
