// Versions: a release's, a release with its build, and macOS's.

import Foundation

/// A release's version, `major.minor.patch`, as the tag `mac-v<version>`, `update.json` and the app's
/// `CFBundleShortVersionString` carry it: "0.6.0". Three parts, ASCII digits only, no leading zero
/// (but "0" itself), so each version has one spelling and the text compared is the text tagged.
public struct ReleaseVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Self.number(parts[0]), let minor = Self.number(parts[1]), let patch = Self.number(parts[2])
        else { return nil }
        self.init(major: major, minor: minor, patch: patch)
    }

    /// A part of a version: one to nine ASCII digits, without a leading zero unless it is "0".
    static func number(_ text: Substring) -> Int? {
        guard (1...9).contains(text.count), text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        guard text.count == 1 || text.first != "0" else { return nil }
        return Int(text)
    }

    public static func < (a: ReleaseVersion, b: ReleaseVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }
}

/// A version with its build: what decides whether an update is newer. The version first, then the
/// build (`CFBundleVersion`, an integer that only grows).
public struct VersionAndBuild: Comparable, Hashable, Sendable, CustomStringConvertible {
    public var version: ReleaseVersion
    public var build: Int

    public init(version: ReleaseVersion, build: Int) {
        self.version = version
        self.build = build
    }

    public static func < (a: VersionAndBuild, b: VersionAndBuild) -> Bool {
        a.version != b.version ? a.version < b.version : a.build < b.build
    }

    public var description: String { "\(version) (\(build))" }

    /// A build as `CFBundleVersion` or the answer's `build` carries it: a positive integer in ASCII
    /// digits.
    public static func build(_ text: String) -> Int? {
        guard (1...18).contains(text.count), text.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(text), value > 0
        else { return nil }
        return value
    }
}

/// A macOS version: "14.0", "14", "15.1.2". `minimumSystemVersion` in the answer; the running Mac's
/// from `ProcessInfo`.
public struct SystemVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int = 0, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init(_ version: OperatingSystemVersion) {
        self.init(major: version.majorVersion, minor: version.minorVersion, patch: version.patchVersion)
    }

    /// One to three parts of ASCII digits.
    public init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard (1...4).contains(part.count), part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(part)
            else { return nil }
            numbers.append(number)
        }
        numbers += Array(repeating: 0, count: 3 - numbers.count)
        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2])
    }

    public static func < (a: SystemVersion, b: SystemVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }

    /// "14.0", "15.1.2": the patch only when it isn't 0.
    public var description: String {
        patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
    }
}

/// The copy of Tactile that is running: what it compares an update with, and what it replaces.
public struct RunningApp: Equatable, Sendable {
    /// `CFBundleShortVersionString`, as the bundle says it.
    public var version: String
    /// `CFBundleVersion`, as the bundle says it.
    public var build: String
    /// The app bundle, its symbolic links resolved.
    public var bundleURL: URL
    public var processID: Int32
    public var systemVersion: SystemVersion

    public init(version: String, build: String, bundleURL: URL, processID: Int32, systemVersion: SystemVersion) {
        self.version = version
        self.build = build
        self.bundleURL = bundleURL
        self.processID = processID
        self.systemVersion = systemVersion
    }

    /// The version and build to compare with. A version or build that can't be read counts as the
    /// lowest (0.0.0, build 0), so any valid release is newer than it.
    public var versionAndBuild: VersionAndBuild {
        VersionAndBuild(
            version: ReleaseVersion(version) ?? ReleaseVersion(major: 0, minor: 0, patch: 0),
            build: VersionAndBuild.build(build) ?? 0)
    }

    /// This process: the main bundle, its versions, and macOS's.
    public static var current: RunningApp {
        let bundle = Bundle.main
        return RunningApp(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            bundleURL: bundle.bundleURL.resolvingSymlinksInPath(),
            processID: ProcessInfo.processInfo.processIdentifier,
            systemVersion: SystemVersion(ProcessInfo.processInfo.operatingSystemVersion))
    }
}
