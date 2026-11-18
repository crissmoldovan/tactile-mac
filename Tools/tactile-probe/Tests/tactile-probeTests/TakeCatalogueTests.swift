import XCTest
@testable import tactile_probe

final class TakeCatalogueTests: XCTestCase {
    /// The twenty takes as the first survey recorded them. Tests in TactileKit find takes by number
    /// and title in the survey files, so none of these may ever change.
    private let firstSurvey: [(number: Int, id: String, title: String)] = [
        (1, "identify-circle", "Find the touchscreen"),
        (2, "two-fingers-rest", "Two fingers resting"),
        (3, "max-fingers", "As many fingers as you can"),
        (4, "exclusive-circle", "Circle, touchscreen held by this tool"),
        (5, "corner-top-left", "Corner: top-left"),
        (6, "corner-top-right", "Corner: top-right"),
        (7, "corner-bottom-right", "Corner: bottom-right"),
        (8, "corner-bottom-left", "Corner: bottom-left"),
        (9, "tap", "One-finger tap"),
        (10, "double-tap", "Double tap"),
        (11, "drag", "Drag"),
        (12, "rest-then-drag", "Rest, then drag"),
        (13, "press-and-hold", "Press and hold"),
        (14, "two-finger-scroll-flick", "Two-finger scroll ending in a flick"),
        (15, "pinch", "Pinch out, then in"),
        (16, "two-finger-tap", "Two-finger tap"),
        (17, "two-finger-rotate", "Two-finger twist"),
        (18, "three-finger-swipe-left", "Three-finger swipe left"),
        (19, "four-finger-swipe-up", "Four-finger swipe up"),
        (20, "palm", "Palm"),
    ]

    func testTheFirstTwentyTakesKeepTheirNumbersIDsAndTitles() {
        for take in firstSurvey {
            let spec = Takes.take(take.number)
            XCTAssertEqual(spec?.id, take.id, "take \(take.number)")
            XCTAssertEqual(spec?.title, take.title, "take \(take.number)")
        }
    }

    func testTwoTakesAreAddedAtTheEnd() {
        XCTAssertEqual(Takes.count, 22)
        XCTAssertEqual(Takes.take(21)?.id, "two-finger-flick")
        XCTAssertEqual(Takes.take(22)?.id, "second-finger-late")
        XCTAssertTrue(Takes.take(21)?.prompt.contains("TWO") == true)
        XCTAssertTrue(Takes.take(21)?.prompt.lowercased().contains("still moving") == true,
                      "the point of take 21 is lifting while the fingers move; take 14's fingers stopped first")
        XCTAssertTrue(Takes.take(22)?.prompt.lowercased().contains("half a second") == true)
    }

    func testNumbersRunFromOneWithoutGapsAndIDsAreUnique() {
        XCTAssertEqual(Takes.all.map(\.number), Array(1...Takes.count))
        XCTAssertEqual(Set(Takes.all.map(\.id)).count, Takes.count)
        XCTAssertNil(Takes.take(0))
        XCTAssertNil(Takes.take(Takes.count + 1))
    }

    func testEachTakeRunsInTheStateTheFirstSurveyUsed() {
        let asFound = Takes.all.filter { $0.state == .asFound }.map(\.number)
        let multiTouch = Takes.all.filter { $0.state == .multiTouch }.map(\.number)
        let exclusive = Takes.all.filter { $0.state == .exclusive }.map(\.number)
        XCTAssertEqual(asFound, [1])
        XCTAssertEqual(multiTouch, [2, 3, 5, 6, 7, 8])
        XCTAssertEqual(exclusive, [4] + Array(9...22))
        XCTAssertEqual(Takes.all.filter(\.isCorner).map(\.number), [5, 6, 7, 8])
    }

    func testNoTakeTalksAboutThePointer() {
        // A line about the pointer led the person to stop a good run. The takes say what to do
        // with the fingers, and nothing about the pointer.
        for spec in Takes.all {
            XCTAssertFalse(spec.prompt.lowercased().contains("pointer"), "take \(spec.number)")
            XCTAssertFalse((spec.note ?? "").lowercased().contains("pointer"), "take \(spec.number)")
        }
    }

    // MARK: Selection

    func testSelectionPicksTakesInCatalogueOrder() {
        XCTAssertEqual(TakeSelection.all.takes.map(\.number), Array(1...22))
        XCTAssertEqual(TakeSelection.from(16).takes.map(\.number), [16, 17, 18, 19, 20, 21, 22])
        XCTAssertEqual(TakeSelection.from(22).takes.map(\.number), [22])
        XCTAssertEqual(TakeSelection.only([5, 16, 22]).takes.map(\.number), [5, 16, 22])
    }

    func testFromSixteenIsTheFiveMissingAndTheTwoNew() {
        // ILITEK takes 16–20 were never recorded; 21 and 22 are new.
        XCTAssertEqual(TakeSelection.from(16).takes.map(\.id), [
            "two-finger-tap", "two-finger-rotate", "three-finger-swipe-left", "four-finger-swipe-up", "palm",
            "two-finger-flick", "second-finger-late",
        ])
    }

    func testSelectionDescribesItselfInWords() {
        XCTAssertEqual(TakeSelection.all.text, "all 22 takes")
        XCTAssertEqual(TakeSelection.from(16).text, "takes 16 to 22 (7 takes)")
        XCTAssertEqual(TakeSelection.from(22).text, "take 22 only")
        XCTAssertEqual(TakeSelection.only([16, 17, 22]).text, "takes 16, 17 and 22 (3 takes)")
        XCTAssertEqual(TakeSelection.only([9]).text, "take 9 only")
        XCTAssertEqual(TakeSelection.all.numbers, Array(1...22))
    }
}
