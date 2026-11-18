import Foundation
import ReleaseCore
import XCTest

/// `check-settings`: the built app's Info.plist, read by the app's own rules (TactileUpdates), must
/// trust the key the release is signed with and ask the official site. Anything else would ship a
/// Tactile that can't take the next update, or asks another site, or has updates off.
final class UpdateSettingsCheckTests: XCTestCase {
    private let publicKey = UpdateKey.encode(UpdateKey.newPrivateKey().publicKey)
    private let otherKey = UpdateKey.encode(UpdateKey.newPrivateKey().publicKey)
    private let site = "https://tactilemac.com"

    /// A folder laid out like an app, with these Info.plist entries, in XML or binary form.
    private func app(_ entries: [String: Any], binary: Bool = false) throws -> URL {
        let app = try makeTemporaryFolder(self).appendingPathComponent("Tactile.app")
        var info: [String: Any] = ["CFBundleIdentifier": "com.crissmoldovan.tactile"]
        info.merge(entries) { $1 }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: binary ? .binary : .xml, options: 0)
        try write(data, to: app, "Contents/Info.plist")
        return app
    }

    private func run(_ app: URL, keyID: String = "k1", site: String? = nil) -> (Int32, Printed) {
        let printed = Printed()
        let status = Tool.run(["check-settings", "--key-id", keyID, "--public-key", publicKey, "--site", site ?? self.site, app.path],
                              store: FakeKeyStore(), console: printed.console)
        return (status, printed)
    }

    func testAnAppThatTrustsTheKeyAndAsksTheSitePasses() throws {
        for binary in [false, true] {
            let built = try app(["TactileUpdateBaseURL": site, "TactileUpdateKeys": "k1:\(publicKey) k2:\(otherKey)"], binary: binary)
            let (status, printed) = run(built)
            XCTAssertEqual(status, 0, printed.all)
            XCTAssertEqual(printed.out, ["Info.plist: trusts k1 (\(publicKey)) among k1, k2, and asks https://tactilemac.com."])
        }
        XCTAssertEqual(run(try app(["TactileUpdateBaseURL": site, "TactileUpdateKeys": "k2:\(otherKey) k1:\(publicKey)"]),
                           keyID: "k1").0, 0)
    }

    func testAnAppThatDoesntTrustTheSigningKeyIsRefused() throws {
        let (status, printed) = run(try app(["TactileUpdateBaseURL": site, "TactileUpdateKeys": "k1:\(otherKey)"]))
        XCTAssertEqual(status, 1)
        XCTAssertTrue(printed.all.contains("doesn’t trust k1 with that public key"), printed.all)
        let (missing, said) = run(try app(["TactileUpdateBaseURL": site, "TactileUpdateKeys": "k2:\(publicKey)"]))
        XCTAssertEqual(missing, 1)
        XCTAssertTrue(said.all.contains("trusts only k2"), said.all)
    }

    /// The app turns updates off for a list it can't read whole, so the release must not ship it.
    func testAKeyListTheAppWouldRefuseIsRefused() throws {
        for keys in ["k1:\(publicKey) k2:typo", "k1:\(publicKey) k1:\(otherKey)", "k1:\(publicKey),junk", "$(TACTILE_UPDATE_KEYS)"] {
            let (status, printed) = run(try app(["TactileUpdateBaseURL": site, "TactileUpdateKeys": keys]))
            XCTAssertEqual(status, 1, keys)
            XCTAssertTrue(printed.all.contains("updates would be off"), printed.all)
        }
    }

    func testAnAppThatAsksAnotherSiteIsRefused() throws {
        for other in ["https://preview.example.com", "https://tactilemac.com:8443", "http://localhost:3200", "https://tactilemac.com/api"] {
            let (status, printed) = run(try app(["TactileUpdateBaseURL": other, "TactileUpdateKeys": "k1:\(publicKey)"]))
            XCTAssertEqual(status, 1, other)
            XCTAssertFalse(printed.err.isEmpty, other)
        }
        XCTAssertEqual(run(try app(["TactileUpdateBaseURL": "https://preview.example.com", "TactileUpdateKeys": "k1:\(publicKey)"]),
                           site: "https://preview.example.com").0, 0, "the site expected is the one given")
        XCTAssertEqual(run(try app(["TactileUpdateBaseURL": site, "TactileUpdateKeys": "k1:\(publicKey)"]),
                           site: "http://tactilemac.com").0, 2, "the site expected must be an https origin")
    }

    /// The release's values must be in the Info.plist itself: without them the app would fall back to
    /// the keys and site compiled into it, which no one checks here.
    func testAnAppWhosePlistNamesNoKeysOrSiteIsRefused() throws {
        for entries in [["TactileUpdateBaseURL": site], ["TactileUpdateKeys": "k1:\(publicKey)"],
                        ["TactileUpdateBaseURL": "", "TactileUpdateKeys": "k1:\(publicKey)"]] as [[String: Any]] {
            let (status, printed) = run(try app(entries))
            XCTAssertEqual(status, 1, "\(entries)")
            XCTAssertTrue(printed.all.contains("names no"), printed.all)
        }
        let noPlist = try makeTemporaryFolder(self).appendingPathComponent("Tactile.app")
        try FileManager.default.createDirectory(at: noPlist, withIntermediateDirectories: true)
        XCTAssertEqual(run(noPlist).0, 1)
    }

    func testTheCommandIsListed() {
        XCTAssertTrue(Tool.usage.contains("check-settings --key-id <id> --public-key <base64> --site <url> <app>"))
    }
}
