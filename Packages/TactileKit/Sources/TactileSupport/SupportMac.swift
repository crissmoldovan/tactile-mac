// The Mac a report comes from, as mac.json says it: no serial number, no name.

import Foundation

/// The Mac and the Tactile a check ran on.
public struct SupportMac: Equatable, Sendable {
    /// The model identifier: "Mac15,6".
    public var model: String
    /// macOS's version: "26.1", or "26.1.2".
    public var macOS: String
    public var tactileVersion: String
    public var tactileBuild: String
    /// How many displays are connected.
    public var displays: Int

    public init(model: String, macOS: String, tactileVersion: String, tactileBuild: String, displays: Int) {
        self.model = model
        self.macOS = macOS
        self.tactileVersion = tactileVersion
        self.tactileBuild = tactileBuild
        self.displays = displays
    }

    /// This Mac: `hw.model`, macOS's version, the main bundle's version and build, and `displays`.
    public static func current(displays: Int) -> SupportMac {
        let bundle = Bundle.main
        return SupportMac(
            model: modelIdentifier() ?? "unknown",
            macOS: version(ProcessInfo.processInfo.operatingSystemVersion),
            tactileVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            tactileBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            displays: displays)
    }

    /// "26.1", or "26.1.2" when there is a patch version.
    public static func version(_ version: OperatingSystemVersion) -> String {
        version.patchVersion == 0
            ? "\(version.majorVersion).\(version.minorVersion)"
            : "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// `sysctl hw.model`.
    private static func modelIdentifier() -> String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return nil }
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}
