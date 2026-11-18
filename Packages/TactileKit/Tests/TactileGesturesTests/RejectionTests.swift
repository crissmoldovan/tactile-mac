import XCTest
@testable import TactileGestures

/// The contact filter's rejection rules: palms (not confident, too wide, a whole hand) and touches
/// that start near the edge.
final class RejectionTests: XCTestCase {

    /// The ILITEK's glass, in millimetres.
    private let surface = CGSize(width: 527, height: 296)

    /// A contact at (`x`, `y`) mm on `surface` (the ILITEK's glass unless given).
    private func finger(_ id: Int, _ x: Double = 200, _ y: Double = 150, size: CGSize? = nil,
                        confident: Bool? = nil, on surface: CGSize? = nil) -> Finger {
        let glass = surface ?? self.surface
        return Finger(id: id, location: CGPoint(x: x / glass.width, y: y / glass.height), size: size,
                      isConfident: confident)
    }

    private func ids(_ fingers: [Finger]) -> [Int] {
        fingers.map(\.id)
    }

    private let palmOnly = RejectionRules(palm: true, edgeMarginMM: 0)

    // MARK: - Not confident

    func testAContactThePanelSaysIsNotAFingerIsNeverSeen() {
        var filter = ContactFilter(rules: palmOnly)
        let seen = filter.live([finger(0, confident: false), finger(1, 300, 150, confident: true)],
                               at: 0, surfaceSize: surface)
        XCTAssertEqual(ids(seen), [1])
        XCTAssertEqual(filter.refused, [0])
        XCTAssertFalse(filter.mustCancel)     // refused as it appeared: never seen, nothing to cancel
    }

    func testWithPalmOffANotConfidentContactCounts() {
        var filter = ContactFilter(rules: .none)
        XCTAssertEqual(ids(filter.live([finger(0, confident: false)], at: 0, surfaceSize: surface)), [0])
    }

    func testAContactWithoutAConfidenceFlagCounts() {
        var filter = ContactFilter(rules: palmOnly)
        XCTAssertEqual(ids(filter.live([finger(0, confident: nil)], at: 0, surfaceSize: surface)), [0])
    }

    // MARK: - Too wide

    func testAContactWiderThan25MillimetresIsNeverSeen() {
        var filter = ContactFilter(rules: palmOnly)
        let seen = filter.live([finger(0, 100, 100, size: CGSize(width: 26, height: 10)),
                                finger(1, 200, 100, size: CGSize(width: 10, height: 25.5)),
                                finger(2, 300, 100, size: CGSize(width: 25, height: 25))],
                               at: 0, surfaceSize: surface)
        XCTAssertEqual(ids(seen), [2])        // 25 mm is not over 25
        XCTAssertEqual(filter.refused, [0, 1])
    }

    func testWithPalmOffAWideContactCounts() {
        var filter = ContactFilter(rules: .none)
        XCTAssertEqual(ids(filter.live([finger(0, size: CGSize(width: 40, height: 40))], at: 0, surfaceSize: surface)),
                       [0])
    }

    func testAContactWithoutASizeCounts() {
        var filter = ContactFilter(rules: palmOnly)
        XCTAssertEqual(ids(filter.live([finger(0, size: nil)], at: 0, surfaceSize: surface)), [0])
    }

    // MARK: - Turning out to be a palm

    /// Review focus 3: a contact that grows past 25 mm in its third frame.
    func testAContactThatWidensInItsThirdFrameMustCancelOnceAndIsRefusedFromThen() {
        var filter = ContactFilter(rules: palmOnly)
        let small = CGSize(width: 9, height: 9), wide = CGSize(width: 30, height: 18)
        XCTAssertEqual(ids(filter.live([finger(0, size: small)], at: 0, surfaceSize: surface)), [0])
        XCTAssertFalse(filter.mustCancel)
        XCTAssertEqual(ids(filter.live([finger(0, size: small)], at: 0.01, surfaceSize: surface)), [0])
        XCTAssertFalse(filter.mustCancel)
        XCTAssertEqual(ids(filter.live([finger(0, size: wide)], at: 0.02, surfaceSize: surface)), [])
        XCTAssertTrue(filter.mustCancel)
        XCTAssertEqual(ids(filter.live([finger(0, size: small)], at: 0.03, surfaceSize: surface)), [])   // still refused
        XCTAssertFalse(filter.mustCancel)
        XCTAssertEqual(filter.refused, [0])
        XCTAssertEqual(ids(filter.live([], at: 0.04, surfaceSize: surface)), [])
        XCTAssertTrue(filter.refused.isEmpty)
    }

    func testAContactThatLosesConfidenceAfterItCountedMustCancel() {
        var filter = ContactFilter(rules: palmOnly)
        _ = filter.live([finger(0, confident: true), finger(1, 300, 150, confident: true)], at: 0, surfaceSize: surface)
        XCTAssertEqual(ids(filter.live([finger(0, confident: true), finger(1, 300, 150, confident: false)],
                                       at: 0.01, surfaceSize: surface)), [0])
        XCTAssertTrue(filter.mustCancel)
    }

    // MARK: - A whole hand

    /// Review focus 4: four fingers within 0.1 s, then a fifth 0.05 s later.
    func testAFifthFingerJoiningFourWithinTheWindowRefusesAllFiveAndMustCancel() {
        var filter = ContactFilter(rules: palmOnly)
        var down: [Finger] = []
        for (id, time) in [(0, 0.0), (1, 0.03), (2, 0.06), (3, 0.1)] {
            down.append(finger(id, 150 + Double(id) * 30, 150))
            XCTAssertEqual(ids(filter.live(down, at: time, surfaceSize: surface)), Array(0...id))
            XCTAssertFalse(filter.mustCancel)
        }
        down.append(finger(4, 270, 150))
        XCTAssertEqual(ids(filter.live(down, at: 0.15, surfaceSize: surface)), [])
        XCTAssertTrue(filter.mustCancel)
        XCTAssertEqual(filter.refused, [0, 1, 2, 3, 4])
    }

    func testFiveFingersLandingOverASecondAreAllLetThrough() {
        var filter = ContactFilter(rules: palmOnly)
        var down: [Finger] = []
        for id in 0..<5 {
            down.append(finger(id, 150 + Double(id) * 30, 150))
            XCTAssertEqual(ids(filter.live(down, at: Double(id) * 0.25, surfaceSize: surface)), Array(0...id))
        }
        XCTAssertTrue(filter.refused.isEmpty)
    }

    func testTenFingersLandingTogetherAreAllRefused() {
        var filter = ContactFilter(rules: palmOnly)
        let hand = (0..<10).map { finger($0, 100 + Double($0) * 25, 150) }
        XCTAssertEqual(ids(filter.live(hand, at: 0, surfaceSize: surface)), [])
        XCTAssertEqual(filter.refused, Set(0..<10))
        XCTAssertFalse(filter.mustCancel)
        XCTAssertEqual(ids(filter.live(hand, at: 0.5, surfaceSize: surface)), [])
    }

    func testAfterARefusedHandLiftsANewFingerIsLive() {
        var filter = ContactFilter(rules: palmOnly)
        let hand = (0..<5).map { finger($0, 100 + Double($0) * 25, 150) }
        _ = filter.live(hand, at: 0, surfaceSize: surface)
        _ = filter.live([], at: 0.5, surfaceSize: surface)
        XCTAssertEqual(ids(filter.live([finger(0, 300, 200)], at: 0.6, surfaceSize: surface)), [0])
    }

    /// Decision: a hand resting on the glass doesn't stop the other hand. A finger landing well
    /// after the hand is not part of it.
    func testAFingerLandingLongAfterARestingHandIsLive() {
        var filter = ContactFilter(rules: palmOnly)
        let hand = (0..<5).map { finger($0, 100 + Double($0) * 25, 250) }
        _ = filter.live(hand, at: 0, surfaceSize: surface)
        XCTAssertEqual(ids(filter.live(hand + [finger(7, 400, 60)], at: 1, surfaceSize: surface)), [7])
    }

    /// Decision: the hand rule counts every contact down, the ones refused for other reasons too.
    func testContactsRefusedForOtherReasonsStillMakeAHand() {
        var filter = ContactFilter(rules: palmOnly)
        let contacts = [finger(0, 100, 150), finger(1, 130, 150), finger(2, 160, 150),
                        finger(3, 190, 150, confident: false), finger(4, 220, 150, confident: false)]
        XCTAssertEqual(ids(filter.live(contacts, at: 0, surfaceSize: surface)), [])
    }

    func testWithPalmOffAHandIsLetThrough() {
        var filter = ContactFilter(rules: .none)
        let hand = (0..<10).map { finger($0, 100 + Double($0) * 25, 150) }
        XCTAssertEqual(ids(filter.live(hand, at: 0, surfaceSize: surface)), Array(0..<10))
    }

    // MARK: - Near the edge

    func testATouchStartingWithinTheMarginOfAnyEdgeIsRefused() {
        let rules = RejectionRules(palm: false, edgeMarginMM: 5)
        let near = [finger(0, 4, 150), finger(1, 523, 150), finger(2, 200, 4), finger(3, 200, 292)]
        for contact in near {
            var filter = ContactFilter(rules: rules)
            XCTAssertEqual(ids(filter.live([contact], at: 0, surfaceSize: surface)), [], "\(contact.location)")
        }
        let inside = [finger(0, 6, 150), finger(1, 521, 150), finger(2, 200, 6), finger(3, 200, 290)]
        for contact in inside {
            var filter = ContactFilter(rules: rules)
            XCTAssertEqual(ids(filter.live([contact], at: 0, surfaceSize: surface)), [contact.id], "\(contact.location)")
        }
    }

    func testWithAMarginOfZeroATouchAtTheEdgeCounts() {
        var filter = ContactFilter(rules: RejectionRules(palm: false, edgeMarginMM: 0))
        XCTAssertEqual(ids(filter.live([finger(0, 0, 0), finger(1, 4, 150)], at: 0, surfaceSize: surface)), [0, 1])
    }

    func testATouchStartingNearTheEdgeStaysRefusedAsItMovesIn() {
        var filter = ContactFilter(rules: RejectionRules(palm: false, edgeMarginMM: 5))
        XCTAssertEqual(ids(filter.live([finger(0, 3, 150)], at: 0, surfaceSize: surface)), [])
        XCTAssertEqual(ids(filter.live([finger(0, 50, 150)], at: 0.1, surfaceSize: surface)), [])
        XCTAssertFalse(filter.mustCancel)
    }

    func testATouchStartingInsideIsUnaffectedWhenItMovesToTheEdge() {
        var filter = ContactFilter(rules: RejectionRules(palm: false, edgeMarginMM: 5))
        XCTAssertEqual(ids(filter.live([finger(0, 50, 150)], at: 0, surfaceSize: surface)), [0])
        XCTAssertEqual(ids(filter.live([finger(0, 1, 150)], at: 0.1, surfaceSize: surface)), [0])
        XCTAssertFalse(filter.mustCancel)
    }

    /// Each axis in millimetres: on a glass 1600 × 600 mm, 0.004 of the width is 6.4 mm from the
    /// edge, outside a 5 mm margin, and 0.004 of the height is 2.4 mm, inside it.
    func testTheEdgeIsMeasuredInMillimetresOnEachAxis() {
        let wide = CGSize(width: 1600, height: 600)
        let rules = RejectionRules(palm: false, edgeMarginMM: 5)
        var across = ContactFilter(rules: rules)
        XCTAssertEqual(ids(across.live([Finger(id: 0, location: CGPoint(x: 0.004, y: 0.5))], at: 0, surfaceSize: wide)),
                       [0])
        var down = ContactFilter(rules: rules)
        XCTAssertEqual(ids(down.live([Finger(id: 0, location: CGPoint(x: 0.5, y: 0.004))], at: 0, surfaceSize: wide)),
                       [])
        var right = ContactFilter(rules: rules)
        XCTAssertEqual(ids(right.live([Finger(id: 0, location: CGPoint(x: 0.996, y: 0.5))], at: 0, surfaceSize: wide)),
                       [0])
        var bottom = ContactFilter(rules: rules)
        XCTAssertEqual(ids(bottom.live([Finger(id: 0, location: CGPoint(x: 0.5, y: 0.996))], at: 0, surfaceSize: wide)),
                       [])
    }

    func testAPointOffTheGlassIsWithinAnyMargin() {
        var filter = ContactFilter(rules: RejectionRules(palm: false, edgeMarginMM: 2))
        XCTAssertEqual(ids(filter.live([Finger(id: 0, location: CGPoint(x: -0.01, y: 0.5))], at: 0, surfaceSize: surface)),
                       [])
    }

    func testASurfaceSizeThatIsNotUsableSwitchesTheEdgeRuleOffForThatFrame() {
        let rules = RejectionRules(palm: false, edgeMarginMM: 5)
        for size in [CGSize.zero, CGSize(width: -527, height: 296), CGSize(width: CGFloat.nan, height: 296),
                     CGSize(width: 527, height: CGFloat.infinity)] {
            var filter = ContactFilter(rules: rules)
            XCTAssertEqual(ids(filter.live([Finger(id: 0, location: CGPoint(x: 0.001, y: 0.5))], at: 0, surfaceSize: size)),
                           [0], "\(size)")
            // It landed in a frame the rule couldn't judge; later frames don't judge it either.
            XCTAssertEqual(ids(filter.live([Finger(id: 0, location: CGPoint(x: 0.001, y: 0.5))], at: 0.01,
                                           surfaceSize: surface)), [0], "\(size)")
        }
    }

    func testTheMarginIsClampedToTenAndANonFiniteOneIsZero() {
        XCTAssertEqual(RejectionRules(edgeMarginMM: 20).edgeMarginMM, 10)
        XCTAssertEqual(RejectionRules(edgeMarginMM: -3).edgeMarginMM, 0)
        XCTAssertEqual(RejectionRules(edgeMarginMM: .nan).edgeMarginMM, 0)
        XCTAssertEqual(RejectionRules(edgeMarginMM: .infinity).edgeMarginMM, 0)
        var rules = RejectionRules()
        rules.edgeMarginMM = 12
        XCTAssertEqual(rules.edgeMarginMM, 10)
        rules.edgeMarginMM = -.infinity
        XCTAssertEqual(rules.edgeMarginMM, 0)
        rules.edgeMarginMM = 4.5
        XCTAssertEqual(rules.edgeMarginMM, 4.5)
    }

    // MARK: - The finger limit

    func testTheFingerLimitStillActsAndARefusedPalmLeavesItsRoom() {
        var filter = ContactFilter(fingerLimit: 1, rules: palmOnly)
        XCTAssertEqual(ids(filter.live([finger(9, confident: false)], at: 0, surfaceSize: surface)), [])
        XCTAssertEqual(ids(filter.live([finger(9, confident: false), finger(0, 300, 150)], at: 0.1,
                                       surfaceSize: surface)), [0])
        XCTAssertEqual(ids(filter.live([finger(9, confident: false), finger(0, 300, 150), finger(1, 350, 150)],
                                       at: 0.2, surfaceSize: surface)), [0])
        XCTAssertEqual(filter.refused, [1, 9])
    }

    // MARK: - Without time and size

    /// The `live(_:)` that takes no time and no size applies only the finger limit, plus the palm
    /// rules that need neither.
    func testLiveWithoutTimeOrSizeAppliesOnlyConfidenceAndWidthWithPalmOn() {
        var filter = ContactFilter(rules: RejectionRules(palm: true, edgeMarginMM: 10))
        let hand = (0..<5).map { finger($0, 100 + Double($0) * 25, 150) }
        XCTAssertEqual(ids(filter.live(hand)), [0, 1, 2, 3, 4])                      // no time: no hand
        XCTAssertEqual(ids(filter.live(hand + [finger(5, 1, 150)])), [0, 1, 2, 3, 4, 5])   // no size: no edge
        XCTAssertEqual(ids(filter.live(hand + [finger(5, 1, 150), finger(6, confident: false),
                                               finger(7, size: CGSize(width: 30, height: 30))])),
                       [0, 1, 2, 3, 4, 5])
    }

    func testTheExistingInitRefusesNothingButTheLimit() {
        var filter = ContactFilter()
        XCTAssertEqual(filter.rules, .none)
        let anything = (0..<10).map { finger($0, 1 + Double($0) * 50, 1, size: CGSize(width: 40, height: 40), confident: false) }
        XCTAssertEqual(ids(filter.live(anything, at: 0, surfaceSize: surface)), Array(0..<10))
        XCTAssertFalse(filter.mustCancel)
    }

    // MARK: - Stored

    func testRulesSurviveJSONAndLoadFromAnEmptyObjectWithTheDefaults() throws {
        let rules = RejectionRules(palm: false, edgeMarginMM: 4.5)
        XCTAssertEqual(try JSONDecoder().decode(RejectionRules.self, from: JSONEncoder().encode(rules)), rules)
        XCTAssertEqual(try JSONDecoder().decode(RejectionRules.self, from: Data("{}".utf8)), RejectionRules())
        XCTAssertEqual(RejectionRules(), RejectionRules(palm: true, edgeMarginMM: 0))
        XCTAssertEqual(RejectionRules.none, RejectionRules(palm: false, edgeMarginMM: 0))
        XCTAssertEqual(try JSONDecoder().decode(RejectionRules.self, from: Data(#"{"edgeMarginMM":25}"#.utf8)).edgeMarginMM, 10)
        XCTAssertEqual(try JSONDecoder().decode(RejectionRules.self, from: Data(#"{"palm":false}"#.utf8)),
                       RejectionRules.none)
    }

    // MARK: - Through the engine

    /// Review focus 3, end to end: a tap whose contact turns palm in its third frame. The engine
    /// is cancelled, and the palm lifting is not a click.
    func testATapByAContactThatTurnsPalmIsCancelledAndDoesNotClick() {
        let s = TouchScript(rules: palmOnly)
        let small = CGSize(width: 9, height: 9), wide = CGSize(width: 40, height: 30)
        func frame(_ size: CGSize) {
            s.send(TouchFrame(time: s.time + 0.01, fingers: [Finger(id: 0, location: TouchScript.at(100, 100), size: size)],
                              surfaceSize: TouchScript.surface))
        }
        frame(small)
        frame(small)
        frame(wide)
        frame(wide)
        s.lift()
        s.wait(1)
        XCTAssertEqual(s.names, ["session began", "move", "session cancelled"])
        XCTAssertTrue(s.clickCounts.isEmpty)
    }

    /// Review focus 4, end to end: a fifth finger lands within the landing window of a four-finger
    /// swipe. Nothing is recognised and nothing is clicked.
    func testAFifthFingerJoiningAFourFingerSwipeCancelsItAndNothingIsRecognised() {
        let s = TouchScript(rules: palmOnly)
        s.frame([(0, 200, 200), (1, 230, 200)])
        s.frame(after: 0.05, [(0, 200, 200), (1, 230, 200), (2, 260, 200), (3, 290, 200)])
        s.frame(after: 0.05, [(0, 200, 200), (1, 230, 200), (2, 260, 200), (3, 290, 200), (4, 320, 220)])
        s.move([0, 1, 2, 3, 4].map { id in
            let x = 200 + Double(id) * 30, y = id == 4 ? 220.0 : 200
            return (id, (x, y), (x, y - 40))
        }, steps: 20)
        s.lift()
        s.wait(1)
        XCTAssertEqual(s.names, ["session began", "move", "session cancelled"])
    }

    func testAHandRestingThenLiftingLeavesTheNextTapAClick() {
        let s = TouchScript(rules: palmOnly)
        let hand = (0..<5).map { ($0, 100 + Double($0) * 25, 250.0) }
        s.frame(hand)
        for _ in 0..<20 { s.frame(after: 0.02, hand) }
        s.lift()
        s.frame(after: 0.2, [(0, 300, 100)])
        s.lift(after: 0.05)
        XCTAssertEqual(s.names, ["session began", "move", "click 1"])
    }

    func testATapNearTheEdgeIsIgnoredAndOneInsideClicks() {
        let s = TouchScript(rules: RejectionRules(palm: false, edgeMarginMM: 5))
        s.frame([(0, 2, 150)])
        s.lift(after: 0.05)
        s.wait(1)
        XCTAssertTrue(s.actions.isEmpty)
        s.frame([(0, 20, 150)])
        s.lift(after: 0.05)
        XCTAssertEqual(s.names, ["session began", "move", "click 1"])
    }
}
