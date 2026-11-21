@testable import TactileApp
import XCTest

/// The order of General's groups. The touch devices Tactile doesn't list have moved to Touchscreen
/// Check, the sidebar's item after General (`TouchscreenCheckEntryTests`).
final class GeneralPaneOrderTests: XCTestCase {

    func testTheOrderOfGeneralsGroups() {
        XCTAssertEqual(GeneralPane.order, [.warnings, .tactile, .diagnostics, .experimental, .updates, .version])
    }
}
