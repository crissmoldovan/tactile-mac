import Foundation
import XCTest

@testable import TactileUpdates

/// Versions are read in one spelling, and ordered by version, then build.
final class VersionTests: XCTestCase {

    func testAReleaseVersionHasThreePartsOfDigits() {
        XCTAssertEqual(ReleaseVersion("0.6.0"), ReleaseVersion(major: 0, minor: 6, patch: 0))
        XCTAssertEqual(ReleaseVersion("12.0.345"), ReleaseVersion(major: 12, minor: 0, patch: 345))
        XCTAssertEqual(ReleaseVersion("0.6.0")?.description, "0.6.0")
        for text in ["", "0.6", "0.6.0.1", "v0.6.0", "0.6.0-beta", "0..6", "0.6.", ".6.0", "0.06.0", "00.6.0",
                     "0.6.x", "0.6.-1", "+1.0.0", " 0.6.0", "0.6.0 ", "1234567890.0.0", "٠.٦.٠", "unknown"] {
            XCTAssertNil(ReleaseVersion(text), text)
        }
    }

    func testVersionsAreOrderedPartByPartAsNumbers() {
        let ordered = ["0.0.0", "0.0.1", "0.1.0", "0.5.0", "0.5.9", "0.6.0", "0.9.0", "0.10.0", "1.0.0", "10.0.0"]
            .compactMap(ReleaseVersion.init)
        XCTAssertEqual(ordered.count, 10)
        XCTAssertEqual(ordered.sorted(), ordered)
        XCTAssertGreaterThan(ReleaseVersion("0.10.0")!, ReleaseVersion("0.9.9")!)
    }

    func testTheVersionDecidesBeforeTheBuild() {
        func vb(_ version: String, _ build: Int) -> VersionAndBuild {
            VersionAndBuild(version: ReleaseVersion(version)!, build: build)
        }
        XCTAssertGreaterThan(vb("0.6.0", 1), vb("0.5.0", 999), "a newer version wins whatever the builds")
        XCTAssertGreaterThan(vb("0.6.0", 413), vb("0.6.0", 412), "the same version: the higher build")
        XCTAssertEqual(vb("0.6.0", 412), vb("0.6.0", 412))
        XCTAssertFalse(vb("0.6.0", 412) > vb("0.6.0", 412), "the same version and build isn't newer")
        XCTAssertLessThan(vb("0.5.9", 1000), vb("0.6.0", 1))
    }

    func testABuildIsAPositiveIntegerInDigits() {
        XCTAssertEqual(VersionAndBuild.build("412"), 412)
        XCTAssertEqual(VersionAndBuild.build("1"), 1)
        for text in ["", "0", "-1", "4.1", "41a", " 412", "+412", "99999999999999999999"] {
            XCTAssertNil(VersionAndBuild.build(text), text)
        }
    }

    func testARunningAppWhoseVersionCantBeReadCountsAsTheLowest() {
        let app = RunningApp(version: "unknown", build: "", bundleURL: URL(fileURLWithPath: "/x/Tactile.app"),
                             processID: 1, systemVersion: SystemVersion(major: 14))
        XCTAssertEqual(app.versionAndBuild, VersionAndBuild(version: ReleaseVersion(major: 0, minor: 0, patch: 0), build: 0))
        let release = RunningApp(version: "0.5.0", build: "7", bundleURL: app.bundleURL, processID: 1,
                                 systemVersion: SystemVersion(major: 14))
        XCTAssertEqual(release.versionAndBuild, VersionAndBuild(version: ReleaseVersion("0.5.0")!, build: 7))
    }

    func testAMacOSVersionHasOneToThreeParts() {
        XCTAssertEqual(SystemVersion("14.0"), SystemVersion(major: 14, minor: 0, patch: 0))
        XCTAssertEqual(SystemVersion("14"), SystemVersion(major: 14))
        XCTAssertEqual(SystemVersion("15.1.2"), SystemVersion(major: 15, minor: 1, patch: 2))
        XCTAssertEqual(SystemVersion("14.0")?.description, "14.0")
        XCTAssertEqual(SystemVersion("15.1.2")?.description, "15.1.2")
        for text in ["", "14.", "14.0.0.0", "fourteen", "14.x", "-14", "14 .0"] {
            XCTAssertNil(SystemVersion(text), text)
        }
        XCTAssertLessThan(SystemVersion("14.6")!, SystemVersion("15.0")!)
        XCTAssertLessThan(SystemVersion("14.6")!, SystemVersion("14.10")!)
        XCTAssertEqual(SystemVersion(OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0)),
                       SystemVersion(major: 26, minor: 1))
    }
}
