import XCTest

@testable import TactileApp

/// Bringing Settings to the front: when an activation counts as refused, and what is tried next.
final class SettingsActivationTests: XCTestCase {

    func testTheCooperativeAttemptIsEnoughWhenTheAppIsActiveAndTheWindowKey() {
        XCTAssertNil(ActivationStep.next(after: .cooperative, isActive: true, isKey: true))
    }

    func testARefusedActivationMakesTactileARegularApp() {
        XCTAssertEqual(ActivationStep.next(after: .cooperative, isActive: false, isKey: false), .becomeRegular)
        XCTAssertEqual(ActivationStep.next(after: .cooperative, isActive: false, isKey: true), .becomeRegular)
        XCTAssertEqual(ActivationStep.next(after: .cooperative, isActive: true, isKey: false), .becomeRegular,
                       "not both: the window isn't in front with focus")
    }

    func testStillInactiveAsARegularAppForcesActivation() {
        XCTAssertEqual(ActivationStep.next(after: .becomeRegular, isActive: false, isKey: false), .force)
        XCTAssertEqual(ActivationStep.next(after: .becomeRegular, isActive: false, isKey: true), .force)
    }

    func testActiveAsARegularAppIsEnough() {
        XCTAssertNil(ActivationStep.next(after: .becomeRegular, isActive: true, isKey: true))
        XCTAssertNil(ActivationStep.next(after: .becomeRegular, isActive: true, isKey: false),
                     "forcing activation can't make an active app's window key")
    }

    func testNothingComesAfterForcing() {
        for (active, key) in [(false, false), (true, false), (false, true), (true, true)] {
            XCTAssertNil(ActivationStep.next(after: .force, isActive: active, isKey: key))
        }
    }
}
