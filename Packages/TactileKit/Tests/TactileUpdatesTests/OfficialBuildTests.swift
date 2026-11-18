import CryptoKit
import Foundation
import Security
import XCTest

@testable import TactileUpdates

/// Only the official build updates itself: Tactile's bundle identifier, and a code signature that
/// satisfies the requirement updates are checked against (a Developer ID of Tactile's team). Any
/// other build, a fork's or one signed ad hoc, asks no site at all. Where the official build asks,
/// and which keys it trusts, are read from its Info.plist.
final class OfficialBuildTests: XCTestCase {

    /// A signature check that answers as told, and records what it was asked.
    private final class FakeSelfSignature: SelfSignatureChecking, @unchecked Sendable {
        let answer: Bool
        private(set) var asked: [String] = []
        init(_ answer: Bool) { self.answer = answer }
        func satisfies(_ requirement: String) -> Bool {
            asked.append(requirement)
            return answer
        }
    }

    private static let other = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()

    // MARK: - Who updates

    func testTheOfficialBuildUpdates() {
        let signature = FakeSelfSignature(true)
        let availability = UpdateAvailability.decide(
            bundleIdentifier: "com.crissmoldovan.tactile", info: nil, signature: signature)
        XCTAssertEqual(availability, .on(.builtIn))
        XCTAssertTrue(availability.isOn)
        XCTAssertEqual(signature.asked, [SecurityCodeSignatureCheck.developerIDRequirement],
                       "its own signature is checked against the requirement updates are checked against")
    }

    func testTheOfficialIdentityIsTactilesBundleIdentifierAndTheUpdatesRequirement() {
        XCTAssertEqual(OfficialBuild.bundleIdentifier, "com.crissmoldovan.tactile")
        XCTAssertEqual(OfficialBuild.requirement, SecurityCodeSignatureCheck.developerIDRequirement)
        XCTAssertTrue(OfficialBuild.requirement.contains(#"identifier "com.crissmoldovan.tactile""#))
        XCTAssertTrue(OfficialBuild.requirement.contains(#"certificate leaf[subject.OU] = "75K3LTUM8A""#))
    }

    func testAnotherBundleIdentifierTurnsUpdatesOff() {
        for identifier in ["com.example.tactile", "com.crissmoldovan.tactile.debug", "com.crissmoldovan.Tactile", ""] {
            let availability = UpdateAvailability.decide(
                bundleIdentifier: identifier, info: nil, signature: FakeSelfSignature(true))
            XCTAssertEqual(availability, .off(.otherBundleIdentifier), identifier)
            XCTAssertFalse(availability.isOn, identifier)
        }
        XCTAssertEqual(UpdateAvailability.decide(bundleIdentifier: nil, info: nil, signature: FakeSelfSignature(true)),
                       .off(.otherBundleIdentifier))
    }

    /// Signed ad hoc, by another team, by Apple Development, or not at all: the requirement isn't
    /// satisfied, and nothing asks any site.
    func testAnAdHocOrOtherTeamSignatureTurnsUpdatesOff() {
        let availability = UpdateAvailability.decide(
            bundleIdentifier: "com.crissmoldovan.tactile", info: nil, signature: FakeSelfSignature(false))
        XCTAssertEqual(availability, .off(.notSignedByTheDeveloper))
        XCTAssertFalse(availability.isOn)
    }

    /// The Security framework's own check of this process. The test runner is not Tactile (with
    /// Xcode 27 it is even signed ad hoc), so the requirement fails; the runner's own designated
    /// requirement passes, so the check isn't simply always false.
    func testTheRealCheckOfThisProcessRefusesWhatIsntTactile() throws {
        let check = SecuritySelfSignatureCheck()
        XCTAssertNotEqual(check.status(OfficialBuild.requirement), errSecSuccess)
        XCTAssertFalse(check.satisfies(OfficialBuild.requirement))
        XCTAssertNotEqual(check.status("this is not a requirement"), errSecSuccess, "one that doesn't compile fails")
        XCTAssertEqual(UpdateAvailability.current(), .off(.otherBundleIdentifier), "the test runner's bundle isn't Tactile's")

        var me: SecCode?
        var onDisk: SecStaticCode?
        var designated: SecRequirement?
        var text: CFString?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &onDisk) == errSecSuccess, let onDisk,
              SecCodeCopyDesignatedRequirement(onDisk, [], &designated) == errSecSuccess, let designated,
              SecRequirementCopyString(designated, [], &text) == errSecSuccess, let text
        else { throw XCTSkip("The test runner has no designated requirement: it isn't signed.") }
        XCTAssertEqual(check.status(text as String), errSecSuccess, "a requirement this process meets: \(text)")
    }

    /// An ad hoc signature, as the linker gives this test bundle, can't satisfy the requirement:
    /// it names no certificate, so no team.
    func testAnAdHocSignatureNeverSatisfiesTheRequirement() throws {
        let executable = try XCTUnwrap(Bundle(for: Self.self).executableURL)
        XCTAssertNotEqual(SecurityCodeSignatureCheck(requirement: OfficialBuild.requirement).check(executable), errSecSuccess)
    }

    // MARK: - What the Info.plist says

    func testTheBuiltInSettingsAreTodays() {
        XCTAssertEqual(UpdateSettings.builtIn.site, .builtIn)
        XCTAssertEqual(UpdateSettings.builtIn.site.base.absoluteString, "https://tactilemac.com")
        XCTAssertEqual(UpdateSettings.builtIn.keys, UpdateTrust.productionKeys)
        XCTAssertEqual(UpdateSettings.baseURLKey, "TactileUpdateBaseURL")
        XCTAssertEqual(UpdateSettings.keysKey, "TactileUpdateKeys")
    }

    func testThePlistValuesAreRead() throws {
        let raw = Fixture.key.publicKey.rawRepresentation.base64EncodedString()
        let settings = try UpdateSettings.read(info: [
            "TactileUpdateBaseURL": "https://updates.example.com",
            "TactileUpdateKeys": "t1:\(raw) t2:\(Self.other)",
        ]).get()
        XCTAssertEqual(settings.site.base.absoluteString, "https://updates.example.com")
        XCTAssertEqual(settings.keys, ["t1": raw, "t2": Self.other])
        XCTAssertEqual(UpdateTrust(base64Keys: settings.keys).keys.count, 2)

        let official = UpdateAvailability.decide(
            bundleIdentifier: "com.crissmoldovan.tactile",
            info: ["TactileUpdateBaseURL": "https://updates.example.com", "TactileUpdateKeys": "t1:\(raw)"],
            signature: FakeSelfSignature(true))
        XCTAssertEqual(official, .on(UpdateSettings(site: UpdateSite(base: "https://updates.example.com")!, keys: ["t1": raw])))
        XCTAssertEqual(try UpdateSettings.read(info: ["TactileUpdateBaseURL": "https://localhost:3200"]).get().site.host,
                       "localhost", "https on this Mac is https")
    }

    func testKeysMayBeSeparatedBySpacesCommasOrNewLines() {
        let raw = Fixture.key.publicKey.rawRepresentation.base64EncodedString()
        for text in ["t1:\(raw),t2:\(Self.other)", " t1:\(raw) ,\n t2:\(Self.other)\n", "t1:\(raw)\tt2:\(Self.other)",
                     "t1:\(raw),,t2:\(Self.other),"] {
            XCTAssertEqual(UpdateSettings.parseKeys(text), ["t1": raw, "t2": Self.other], text)
        }
    }

    /// An unset build setting expands to nothing, and a missing key is the same: the built-in values
    /// stand.
    func testMissingOrEmptyValuesMeanTodays() {
        XCTAssertEqual(UpdateSettings.read(info: nil), .success(.builtIn))
        XCTAssertEqual(UpdateSettings.read(info: [:]), .success(.builtIn))
        XCTAssertEqual(UpdateSettings.read(info: ["TactileUpdateBaseURL": "", "TactileUpdateKeys": " \n"]), .success(.builtIn))
        XCTAssertEqual(UpdateAvailability.decide(bundleIdentifier: "com.crissmoldovan.tactile", info: ["TactileUpdateKeys": ""],
                                                 signature: FakeSelfSignature(true)), .on(.builtIn))
    }

    /// A value that is there but can't be used turns updates off: the build asks no site, rather than
    /// fall back to tactilemac.com and k1. The site must be an https origin, on this Mac too; every
    /// key entry must be `<id>:<base64 of 32 bytes>`, each ID once.
    func testAValueThatCantBeUsedTurnsUpdatesOff() {
        let raw = Fixture.key.publicKey.rawRepresentation.base64EncodedString()
        for url in ["http://updates.example.com", "http://localhost:3200", "http://127.0.0.1:3200",
                    "https://updates.example.com/api", "not a url", "$(TACTILE_UPDATE_BASE_URL)", "https:"] {
            XCTAssertEqual(UpdateSettings.read(info: ["TactileUpdateBaseURL": url]),
                           .failure(UnusableUpdateSetting(key: "TactileUpdateBaseURL")), url)
            XCTAssertEqual(UpdateAvailability.decide(bundleIdentifier: "com.crissmoldovan.tactile",
                                                     info: ["TactileUpdateBaseURL": url], signature: FakeSelfSignature(true)),
                           .off(.unusableSetting("TactileUpdateBaseURL")), url)
        }
        for keys in ["k1", "k1:", ":\(raw)", "t1:not-base64", "t1:\(Data(count: 31).base64EncodedString())",
                     "bad/id:\(raw)", "\(String(repeating: "k", count: 33)):\(raw)", "$(TACTILE_UPDATE_KEYS)",
                     "t1:\(raw) junk", "t1:\(raw) t2:short", "t1:\(raw) t1:\(Self.other)", "t1:\(raw) t1:\(raw)"] {
            XCTAssertNil(UpdateSettings.parseKeys(keys), "all or nothing: \(keys)")
            XCTAssertEqual(UpdateSettings.read(info: ["TactileUpdateKeys": keys]),
                           .failure(UnusableUpdateSetting(key: "TactileUpdateKeys")), keys)
            XCTAssertEqual(UpdateAvailability.decide(bundleIdentifier: "com.crissmoldovan.tactile",
                                                     info: ["TactileUpdateKeys": keys], signature: FakeSelfSignature(true)),
                           .off(.unusableSetting("TactileUpdateKeys")), keys)
        }
        XCTAssertEqual(UpdateSettings.read(info: ["TactileUpdateBaseURL": 42]),
                       .failure(UnusableUpdateSetting(key: "TactileUpdateBaseURL")), "not text")
        XCTAssertEqual(UpdateSettings.read(info: ["TactileUpdateKeys": ["k1"]]),
                       .failure(UnusableUpdateSetting(key: "TactileUpdateKeys")), "not text")
        XCTAssertEqual(UpdatesOffReason.unusableSetting("TactileUpdateKeys").logDescription,
                       "its Info.plist’s TactileUpdateKeys can’t be used")
    }

    /// The build settings give the official build today's values, through its Info.plist:
    /// tactilemac.com and the key k1, as `UpdateSettings.builtIn` has them. They live in
    /// `Config/Updates.xcconfig`, which `Signing.xcconfig` includes before the local file, so they can
    /// be overridden; none is set in the project file, where it would win over every xcconfig.
    func testTheProjectsDefaultsAreTodays() throws {
        let mac = try Self.macFolder()
        let project = try String(contentsOf: mac.appendingPathComponent("Tactile.xcodeproj/project.pbxproj"), encoding: .utf8)
        XCTAssertFalse(project.contains("TACTILE_UPDATE_"), "set in the project file, it would win over the xcconfigs")

        let updates = try String(contentsOf: mac.appendingPathComponent("Config/Updates.xcconfig"), encoding: .utf8)
        let settings = Self.xcconfigSettings(updates)
        XCTAssertEqual(settings["TACTILE_UPDATE_BASE_URL"], "https://tactilemac.com", "with its // kept from the comment")
        let keys = try XCTUnwrap(settings["TACTILE_UPDATE_KEYS"])
        XCTAssertEqual(UpdateSettings.parseKeys(keys), UpdateTrust.productionKeys)
        XCTAssertEqual(UpdateSettings.read(info: ["TactileUpdateBaseURL": try XCTUnwrap(settings["TACTILE_UPDATE_BASE_URL"]),
                                                  "TactileUpdateKeys": keys]), .success(.builtIn))

        let signing = try String(contentsOf: mac.appendingPathComponent("Config/Signing.xcconfig"), encoding: .utf8)
        let lines = signing.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let included = try XCTUnwrap(lines.firstIndex(of: #"#include "Updates.xcconfig""#))
        let local = try XCTUnwrap(lines.firstIndex(of: #"#include? "Signing.local.xcconfig""#))
        XCTAssertLessThan(included, local, "the local file comes last, so it can override the update settings")

        let plistData = try Data(contentsOf: mac.appendingPathComponent("Tactile/Info.plist"))
        let info = try XCTUnwrap(PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any])
        XCTAssertEqual(info["TactileUpdateBaseURL"] as? String, "$(TACTILE_UPDATE_BASE_URL)")
        XCTAssertEqual(info["TactileUpdateKeys"] as? String, "$(TACTILE_UPDATE_KEYS)")
        XCTAssertTrue(project.contains("INFOPLIST_FILE = Tactile/Info.plist;"))
    }

    /// The repository's root (where Tactile.xcodeproj is), found from this file's own path.
    private static func macFolder(from file: String = #filePath) throws -> URL {
        var folder = URL(fileURLWithPath: file).deletingLastPathComponent()
        while folder.pathComponents.count > 1 {
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent("Tactile.xcodeproj").path) {
                return folder
            }
            folder.deleteLastPathComponent()
        }
        throw XCTSkip("Not inside the repository: no Tactile.xcodeproj above \(file)")
    }

    /// An xcconfig's settings as Xcode reads them: `//` starts a comment, and `$()` expands to
    /// nothing (the way to write `//` in a value). Includes and conditional settings aren't followed.
    private static func xcconfigSettings(_ text: String) -> [String: String] {
        var settings: [String: String] = [:]
        for line in text.split(separator: "\n") {
            var content = String(line)
            if let comment = content.range(of: "//") { content = String(content[..<comment.lowerBound]) }
            guard !content.hasPrefix("#"), let equals = content.firstIndex(of: "=") else { continue }
            let name = content[..<equals].trimmingCharacters(in: .whitespaces)
            let value = content[content.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            settings[name] = value.replacingOccurrences(of: "$()", with: "")
        }
        return settings
    }

    // MARK: - Where the official build asks

    func testTheUserDefaultStillPointsTheOfficialBuildAtAPreviewSite() {
        let configured = UpdateSite(base: "https://updates.example.com")!
        XCTAssertEqual(UpdateSite.resolve(override: nil, fallback: configured), configured)
        XCTAssertEqual(UpdateSite.resolve(override: "", fallback: configured), configured)
        XCTAssertEqual(UpdateSite.resolve(override: "not a url", fallback: configured), configured)
        XCTAssertEqual(UpdateSite.resolve(override: "https://preview.example.com", fallback: configured).host,
                       "preview.example.com")
    }

    // MARK: - The live updater

    /// The live environment uses the site and keys it is given, and only those: none of the built-in
    /// keys is added, and the user default changes the site alone. Making it sends nothing.
    func testTheLiveUpdaterUsesTheSettingsItIsGiven() throws {
        let raw = Fixture.key.publicKey.rawRepresentation.base64EncodedString()
        let settings = UpdateSettings(site: UpdateSite(base: "https://updates.example.com")!, keys: ["t1": raw])
        let environment = UpdateEnvironment.live(settings: settings, preferences: MemoryPreferences(), quit: {})
        XCTAssertEqual(environment.site, settings.site)
        XCTAssertEqual(Array(environment.verifier.trust.keys.keys), ["t1"])
        XCTAssertEqual(environment.verifier.trust.keys["t1"]?.rawRepresentation.base64EncodedString(), raw)

        let previewed = UpdateEnvironment.live(
            settings: settings, preferences: MemoryPreferences(baseURLOverride: "https://preview.example.com"), quit: {})
        XCTAssertEqual(previewed.site.host, "preview.example.com")
        XCTAssertEqual(Array(previewed.verifier.trust.keys.keys), ["t1"], "the user default never changes the keys")
    }
}
