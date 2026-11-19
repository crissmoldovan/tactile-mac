@testable import TactileApp
import XCTest

/// The order of General's groups: Touchscreen Not Listed? sits near the top, where a person whose
/// touchscreen Tactile doesn't list looks first, not below the fold.
final class GeneralPaneOrderTests: XCTestCase {

    func testTouchscreenNotListedComesStraightAfterTactileAndLaunchAtLogin() {
        XCTAssertEqual(GeneralPane.order, [.warnings, .tactile, .notListed, .diagnostics, .experimental, .updates, .version])
    }
}
