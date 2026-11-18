import Foundation
import XCTest
@testable import TactileOutput

final class MissionControlShortcutsTests: XCTestCase {

    func testMissingEntriesCountAsOn() {
        XCTAssertTrue(MissionControlShortcuts.allEnabled(in: nil))
        XCTAssertTrue(MissionControlShortcuts.allEnabled(in: [:]))
        XCTAssertTrue(MissionControlShortcuts.allEnabled(in: ["79": ["enabled": true], "81": ["enabled": NSNumber(value: true)]]))
    }

    func testOneShortcutTurnedOffIsReported() {
        XCTAssertFalse(MissionControlShortcuts.allEnabled(in: ["32": ["enabled": false]]))
        XCTAssertFalse(MissionControlShortcuts.allEnabled(in: ["81": ["enabled": NSNumber(value: false)]]))
    }

    func testUnrelatedShortcutsAreIgnored() {
        XCTAssertTrue(MissionControlShortcuts.allEnabled(in: ["64": ["enabled": false]]))
    }
}
