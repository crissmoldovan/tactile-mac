import XCTest
@testable import TactileOutput

final class ElementClassifierTests: XCTestCase {

    func testIconsDragEvenInsideAScrollingList() {
        XCTAssertEqual(ElementClassifier.intent(roles: ["AXImage", "AXGroup", "AXList", "AXScrollArea"], hasSelectedText: false), .drag)
    }

    func testEmptySpaceInAScrollAreaScrolls() {
        XCTAssertEqual(ElementClassifier.intent(roles: ["AXList", "AXScrollArea", "AXWindow"], hasSelectedText: false), .scroll)
    }

    func testWebPagesScrollEvenOverImages() {
        XCTAssertEqual(ElementClassifier.intent(roles: ["AXImage", "AXGroup", "AXWebArea", "AXScrollArea"], hasSelectedText: false), .scroll)
    }

    func testSelectedTextDrags() {
        XCTAssertEqual(ElementClassifier.intent(roles: ["AXTextArea", "AXScrollArea"], hasSelectedText: true), .drag)
    }

    func testTitleBarsAndSlidersDrag() {
        XCTAssertEqual(ElementClassifier.intent(roles: ["AXWindow", "AXApplication"], hasSelectedText: false), .drag)
        XCTAssertEqual(ElementClassifier.intent(roles: ["AXSlider", "AXGroup", "AXScrollArea"], hasSelectedText: false), .drag)
    }

    func testCanvasesAndUnknownElementsDrag() {
        XCTAssertEqual(ElementClassifier.intent(roles: ["AXGroup", "AXWindow"], hasSelectedText: false), .drag)
        XCTAssertEqual(ElementClassifier.intent(roles: [], hasSelectedText: false), .drag)
    }

    func testAnAnswerThatDidNotFinishInTimeIsAlwaysDrag() {
        XCTAssertEqual(ElementClassifier.intent(roles: ["AXWebArea"], hasSelectedText: false, completed: false), .drag)
        XCTAssertEqual(ElementClassifier.intent(roles: ["AXTextArea", "AXScrollArea"], hasSelectedText: false, completed: false), .drag)
        XCTAssertEqual(ElementClassifier.intent(roles: ["AXWebArea"], hasSelectedText: false, completed: true), .scroll)
        XCTAssertEqual(ElementClassifier.intent(roles: ["AXWebArea"], hasSelectedText: false, completed: true),
                       ElementClassifier.intent(roles: ["AXWebArea"], hasSelectedText: false))
    }
}
