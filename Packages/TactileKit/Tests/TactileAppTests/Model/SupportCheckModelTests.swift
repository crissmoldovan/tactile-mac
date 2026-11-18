import Foundation
@testable import TactileApp
import TactileDevices
import TactileScreens
import XCTest

private typealias Desk = DeskFixture

/// The model lets go of a touchscreen while it is checked, so the check can take it exactly as
/// Tactile does, and takes it back when the check ends. Nothing here opens a device.
@MainActor
final class SupportCheckModelTests: XCTestCase {

    private func deskHarness() throws -> ModelHarness {
        let harness = try ModelHarness(settings: Desk.settings, fileBytes: nil, writesStateFile: false)
        addTeardownBlock { @MainActor in harness.cleanUp() }
        harness.source.plugIn(Desk.ilitek())
        harness.source.plugIn(Desk.stripScreen())
        harness.model.start()
        return harness
    }

    func testTheTouchscreenCheckedIsLetGoAndTakenBack() throws {
        let harness = try deskHarness()
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .taken)
        let saves = harness.model.saves

        harness.model.perform(.beginSupportCheck(Desk.ilitekID))
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .released, "let go before the check takes it")
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .released)
        XCTAssertEqual(harness.source.state(of: Desk.stripHandle), .taken, "the other touchscreen carries on")
        XCTAssertEqual(harness.touchscreen(Desk.stripID)?.mode, .driving)

        harness.model.perform(.endSupportCheck)
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .taken, "taken back")
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .driving)
        XCTAssertEqual(harness.model.saves, saves, "nothing about a check is saved")
    }

    func testACheckDoesntBeginWhileASetUpRuns() throws {
        let harness = try deskHarness()
        harness.model.perform(.beginSetUpMode)
        XCTAssertNotNil(harness.model.snapshot.setUpMode)
        harness.model.perform(.beginSupportCheck(Desk.ilitekID))
        XCTAssertNotEqual(harness.source.state(of: Desk.ilitekHandle), .released, "refused: set-up mode has it")
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .settingUp)
    }

    func testEndingACheckThatIsntRunningChangesNothing() throws {
        let harness = try deskHarness()
        let before = harness.model.snapshot
        harness.model.perform(.endSupportCheck)
        XCTAssertEqual(harness.model.snapshot, before)
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .taken)
    }
}
