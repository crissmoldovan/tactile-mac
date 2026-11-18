import CryptoKit
import Foundation
import XCTest

@testable import TactileUpdates

/// The trusted keys: signatures are checked with the key the answer names; a key not listed, or an
/// empty list, refuses every update.
final class TrustTests: XCTestCase {

    func testASignatureVerifiesWithTheKeyItNames() {
        let bytes = Fixture.archiveBytes
        let signature = try! Fixture.key.signature(for: bytes)
        XCTAssertEqual(Fixture.trust.verify(signature: signature, over: bytes, keyID: "t1"), .valid)
    }

    func testAnyChangedByteOrSignatureIsRefused() {
        let bytes = Fixture.archiveBytes
        let signature = try! Fixture.key.signature(for: bytes)
        var changed = bytes
        changed[100] ^= 1
        XCTAssertEqual(Fixture.trust.verify(signature: signature, over: changed, keyID: "t1"), .invalidSignature)
        XCTAssertEqual(Fixture.trust.verify(signature: signature, over: bytes + Data([0]), keyID: "t1"), .invalidSignature)
        var badSignature = signature
        badSignature[0] ^= 1
        XCTAssertEqual(Fixture.trust.verify(signature: badSignature, over: bytes, keyID: "t1"), .invalidSignature)
        XCTAssertEqual(Fixture.trust.verify(signature: Data(count: 64), over: bytes, keyID: "t1"), .invalidSignature)
    }

    func testAnotherKeysSignatureIsRefused() {
        let other = Curve25519.Signing.PrivateKey()
        let bytes = Fixture.archiveBytes
        XCTAssertEqual(Fixture.trust.verify(signature: try! other.signature(for: bytes), over: bytes, keyID: "t1"),
                       .invalidSignature)
    }

    func testAKeyIDNotListedIsRefused() {
        let bytes = Fixture.archiveBytes
        let signature = try! Fixture.key.signature(for: bytes)
        XCTAssertEqual(Fixture.trust.verify(signature: signature, over: bytes, keyID: "k1"), .unknownKey)
        XCTAssertEqual(UpdateTrust(keys: [:]).verify(signature: signature, over: bytes, keyID: "t1"), .unknownKey)
    }

    func testKeysAreReadAsTheContractWritesThem() {
        let raw = Fixture.key.publicKey.rawRepresentation.base64EncodedString()
        let trust = UpdateTrust(base64Keys: ["t1": raw, "short": Data(count: 31).base64EncodedString(), "junk": "!!"])
        XCTAssertEqual(Array(trust.keys.keys), ["t1"], "a key that doesn't decode to 32 bytes is left out")
        let bytes = Fixture.archiveBytes
        XCTAssertEqual(trust.verify(signature: try! Fixture.key.signature(for: bytes), over: bytes, keyID: "t1"), .valid)
    }

    /// Every key a release adds to the production list decodes: none is silently dropped.
    func testEveryProductionKeyDecodes() {
        XCTAssertEqual(UpdateTrust.production.keys.count, UpdateTrust.productionKeys.count)
        for (id, text) in UpdateTrust.productionKeys {
            XCTAssertEqual(Data(base64Encoded: text)?.count, 32, id)
        }
    }

    /// The release tool's first key, compiled in as the literal the release script looks for in the
    /// built app.
    func testTheProductionListTrustsK1() {
        XCTAssertEqual(UpdateTrust.productionKeys["k1"], "IpKoBBLRNGZ8WqpbNod6gXQdjESJc0xYOjHdBUwbxYI=")
        XCTAssertEqual(UpdateTrust.production.keys["k1"]?.rawRepresentation.base64EncodedString(),
                       "IpKoBBLRNGZ8WqpbNod6gXQdjESJc0xYOjHdBUwbxYI=")
    }

    /// A key made by a test is never trusted by the production list, so a test's update can't pass for
    /// a release: not under a key ID the list lacks, nor under `k1`, whose private half is elsewhere.
    func testTheProductionListRefusesWhatATestSigned() {
        let bytes = Fixture.archiveBytes
        let signature = try! Fixture.key.signature(for: bytes)
        XCTAssertEqual(UpdateTrust.production.verify(signature: signature, over: bytes, keyID: "t1"), .unknownKey)
        XCTAssertEqual(UpdateTrust.production.verify(signature: signature, over: bytes, keyID: "k1"), .invalidSignature)
        XCTAssertEqual(UpdateTrust(keys: [:]).verify(signature: signature, over: bytes, keyID: "k1"), .unknownKey,
                       "an empty list refuses every update")
    }
}

/// The site: tactilemac.com unless the user default names another https origin; the answer is asked
/// for there, and the archive downloaded only from there or GitHub's download hosts.
final class SiteTests: XCTestCase {

    func testTheBuiltInSiteIsTactilemacDotCom() {
        XCTAssertEqual(UpdateSite.builtIn.base.absoluteString, "https://tactilemac.com")
        XCTAssertEqual(UpdateSite.builtIn.host, "tactilemac.com")
        XCTAssertEqual(UpdateSite.resolve(override: nil), .builtIn)
        XCTAssertEqual(UpdateSite.resolve(override: ""), .builtIn)
        XCTAssertEqual(UpdateSite.overrideKey, "TactileUpdateBaseURL")
    }

    func testThePreviewSiteOverrides() {
        let site = UpdateSite.resolve(override: "https://tactile-git-updates-cristian.vercel.app")
        XCTAssertEqual(site.base.absoluteString, "https://tactile-git-updates-cristian.vercel.app")
        XCTAssertEqual(UpdateSite.resolve(override: "https://Preview.Example.com/").base.absoluteString,
                       "https://preview.example.com")
        XCTAssertEqual(UpdateSite.resolve(override: "http://localhost:3000").base.absoluteString, "http://localhost:3000")
        XCTAssertEqual(UpdateSite.resolve(override: "http://127.0.0.1:3000").base.absoluteString, "http://127.0.0.1:3000")
    }

    func testAnOverrideThatIsntAnOriginIsIgnored() {
        for text in ["http://tactilemac.com", "http://preview.example.com", "ftp://tactilemac.com",
                     "https://tactilemac.com/api", "https://tactilemac.com?x=1", "https://tactilemac.com#top",
                     "https://user:secret@tactilemac.com", "https://", "tactilemac.com", "not a url", "file:///tmp"] {
            XCTAssertNil(UpdateSite(base: text), text)
            XCTAssertEqual(UpdateSite.resolve(override: text), .builtIn, text)
        }
    }

    func testTheAnswerIsAskedForWithTheRunningVersionAndBuild() {
        let url = UpdateSite.builtIn.answerURL(version: "0.5.0", build: "300")
        XCTAssertEqual(url.absoluteString, "https://tactilemac.com/api/mac/update?version=0.5.0&build=300")
        let local = UpdateSite(base: "http://localhost:3000")!.answerURL(version: "0.5.0", build: "1")
        XCTAssertEqual(local.absoluteString, "http://localhost:3000/api/mac/update?version=0.5.0&build=1")
        let odd = UpdateSite.builtIn.answerURL(version: "0.5 &x=1", build: "")
        XCTAssertEqual(URLComponents(url: odd, resolvingAgainstBaseURL: false)?.queryItems,
                       [URLQueryItem(name: "version", value: "0.5 &x=1"), URLQueryItem(name: "build", value: "")],
                       "what the bundle says is sent as a value, never as more of the query")
        XCTAssertEqual(odd.host, "tactilemac.com")
        XCTAssertEqual(odd.path, "/api/mac/update")
    }

    func testOnlyTheSitesOwnOriginIsOnTheSite() {
        let site = UpdateSite.builtIn
        let on = ["https://tactilemac.com/api/mac/archive/0.6.0", "https://TACTILEMAC.com/x", "https://tactilemac.com:443/x",
                  "https://tactilemac.com"]
        let off = ["http://tactilemac.com/api/mac/archive/0.6.0", "https://www.tactilemac.com/x", "https://tactilemac.com:8443/x",
                   "https://tactilemac.com.evil.example/x", "https://evil.example/tactilemac.com",
                   "https://tactilemac.com@evil.example/x", "https://user@tactilemac.com/x",
                   "https://objects.githubusercontent.com/x", "file:///api/mac/archive"]
        for text in on { XCTAssertTrue(site.isOnSite(URL(string: text)!), text) }
        for text in off { XCTAssertFalse(site.isOnSite(URL(string: text)!), text) }
        let local = UpdateSite(base: "http://localhost:3000")!
        XCTAssertTrue(local.isOnSite(URL(string: "http://localhost:3000/api/mac/archive/0.6.0")!))
        XCTAssertFalse(local.isOnSite(URL(string: "http://localhost:3001/api/mac/archive/0.6.0")!))
        XCTAssertFalse(local.isOnSite(URL(string: "http://localhost/api")!))
    }

    /// GitHub's download addresses carry a short-lived signature in their query: the log never shows
    /// a query, a fragment or a user.
    func testTheLogShowsAnAddressWithoutItsQuery() {
        let signed = URL(string: "https://release-assets.githubusercontent.com/github-production-release-asset/1/2?X-Amz-Signature=abc&token=xyz#f")!
        XCTAssertEqual(UpdateSite.loggable(signed),
                       "https://release-assets.githubusercontent.com/github-production-release-asset/1/2")
        XCTAssertEqual(UpdateSite.loggable(URL(string: "https://user:secret@tactilemac.com:8443/api/mac/update?version=1")!),
                       "https://tactilemac.com:8443/api/mac/update")
        XCTAssertEqual(UpdateSite.loggable(nil), "?")
    }

    func testTheDownloadMayGoToTheSiteOrGitHubsDownloadHostsOnly() {
        let site = UpdateSite.builtIn
        let allowed = ["https://tactilemac.com/api/mac/archive/0.6.0",
                       "https://objects.githubusercontent.com/github-production-release-asset/1?sig=x",
                       "https://release-assets.githubusercontent.com/github-production-release-asset/1?sig=x",
                       "https://release-assets.githubusercontent.com:443/x"]
        let refused = ["http://objects.githubusercontent.com/x", "https://objects.githubusercontent.com:8443/x",
                       "https://github.com/crissmoldovan/tactile-mac/releases/download/mac-v0.6.0/Tactile-0.6.0.zip",
                       "https://raw.githubusercontent.com/x", "https://objects.githubusercontent.com.evil.example/x",
                       "https://evil.example/objects.githubusercontent.com", "https://user@objects.githubusercontent.com/x",
                       "https://example.com/Tactile.zip"]
        for text in allowed { XCTAssertTrue(site.allowsDownload(from: URL(string: text)!), text) }
        for text in refused { XCTAssertFalse(site.allowsDownload(from: URL(string: text)!), text) }
    }
}
