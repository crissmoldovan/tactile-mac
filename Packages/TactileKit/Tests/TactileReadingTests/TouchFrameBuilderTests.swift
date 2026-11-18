import CoreGraphics
import XCTest
import TactileReading
import TactileTestSupport

/// The ILITEK "ILITEK-TP" in survey B.
private let ilitekVendorID = 0x222a, ilitekProductID = 0x0001

/// A slot with a finger down.
private func down(_ slot: Int, id: Int, _ x: CGFloat, _ y: CGFloat) -> SlotReading {
    SlotReading(slot: slot, contactID: id, tip: true, position: CGPoint(x: x, y: y))
}

/// A slot whose finger has just lifted: the tip is off, the rest as it was.
private func lifted(_ slot: Int, id: Int, _ x: CGFloat = 0.5, _ y: CGFloat = 0.5) -> SlotReading {
    SlotReading(slot: slot, contactID: id, tip: false, position: CGPoint(x: x, y: y))
}

/// A slot the panel left blank.
private func blank(_ slot: Int) -> SlotReading {
    SlotReading(slot: slot, contactID: 0, tip: false, position: .zero)
}

/// A touch report as a panel with `slotsPerReport` finger collections sends it: the given slots
/// first, then blank ones.
private func report(_ contactCount: Int?, _ slots: [SlotReading], slotsPerReport: Int = 10) -> TouchReport {
    let padding = (slots.count..<max(slots.count, slotsPerReport)).map(blank)
    return TouchReport(contactCount: contactCount, slots: slots + padding)
}

private func ids(_ frame: ContactFrame?) -> [Int]? { frame.map { $0.contacts.map(\.id) } }

final class TouchFrameBuilderTests: XCTestCase {

    // MARK: - Hand-built reports

    func testOneFingerDownMoveLift() {
        var builder = TouchFrameBuilder()
        let frames = [
            builder.add(report(1, [down(0, id: 0, 0.2, 0.3)]), at: 10.000),
            builder.add(report(1, [down(0, id: 0, 0.25, 0.3)]), at: 10.010),
            builder.add(report(1, [lifted(0, id: 0, 0.25, 0.3)]), at: 10.020),
        ]
        XCTAssertEqual(frames, [
            ContactFrame(time: 10.000, contacts: [Contact(id: 0, position: CGPoint(x: 0.2, y: 0.3))]),
            ContactFrame(time: 10.010, contacts: [Contact(id: 0, position: CGPoint(x: 0.25, y: 0.3))]),
            ContactFrame(time: 10.020, contacts: []),
        ])
    }

    func testFramesListContactsInContactIDOrder() {
        var builder = TouchFrameBuilder()
        let frame = builder.add(report(3, [down(0, id: 7, 0.7, 0.1), down(1, id: 2, 0.2, 0.1), down(2, id: 5, 0.5, 0.1)]), at: 1)
        XCTAssertEqual(ids(frame), [2, 5, 7])
        XCTAssertEqual(frame?.contacts.map(\.position.x), [0.2, 0.5, 0.7], "each contact keeps its own position")

        // Ten IDs in descending order: neither report order nor any other order but sorting gives
        // them ascending.
        let descending = (0..<10).map { slot in down(slot, id: 9 - slot, CGFloat(9 - slot) / 10, 0.5) }
        let ten = builder.add(report(10, descending), at: 2)
        XCTAssertEqual(ids(ten), Array(0...9))
        XCTAssertEqual(ten?.contacts.map(\.position.x), (0...9).map { CGFloat($0) / 10 }, "each contact keeps its own position")
    }

    func testAFingerChangingSlotKeepsItsIdentity() {
        var builder = TouchFrameBuilder()
        _ = builder.add(report(2, [down(0, id: 0, 0.1, 0.1), down(1, id: 1, 0.6, 0.6)]), at: 1.00)
        let second = builder.add(report(2, [down(0, id: 1, 0.62, 0.61), lifted(1, id: 0, 0.1, 0.1)]), at: 1.01)
        XCTAssertEqual(second?.contacts, [Contact(id: 1, position: CGPoint(x: 0.62, y: 0.61))])
    }

    func testAContactMissingFromACompleteScanHasLifted() {
        var builder = TouchFrameBuilder()
        let first = builder.add(report(2, [down(0, id: 0, 0.1, 0.1), down(1, id: 1, 0.6, 0.6)]), at: 1.00)
        let second = builder.add(report(1, [down(0, id: 1, 0.6, 0.6)]), at: 1.01)
        XCTAssertEqual(ids(first), [0, 1])
        XCTAssertEqual(ids(second), [1])
    }

    func testAScanSplitOverTwoReports() {
        var builder = TouchFrameBuilder()
        let first = builder.add(report(3, [down(0, id: 0, 0.1, 0.1), down(1, id: 1, 0.2, 0.2)], slotsPerReport: 2), at: 5.000)
        let second = builder.add(report(0, [down(0, id: 2, 0.3, 0.3)], slotsPerReport: 2), at: 5.004)
        XCTAssertNil(first, "the scan is still arriving")
        XCTAssertEqual(ids(second), [0, 1, 2])
        XCTAssertEqual(second?.time, 5.000, "a frame is timed at its scan's first report")
    }

    /// An interface can have touch reports of more than one size. A scan whose first report carries
    /// fewer slots than its count continues until its count has been read, even when the
    /// interface's largest report has room for that many.
    func testASmallerReportLayoutCanSplitAScan() {
        var builder = TouchFrameBuilder()
        let first = builder.add(report(3, [down(0, id: 0, 0.1, 0.1), down(1, id: 1, 0.2, 0.2)], slotsPerReport: 2), at: 7.000)
        let second = builder.add(report(0, [down(0, id: 2, 0.3, 0.3)], slotsPerReport: 1), at: 7.004)
        XCTAssertNil(first, "the scan is still arriving")
        XCTAssertEqual(ids(second), [0, 1, 2])
        XCTAssertEqual(second?.time, 7.000, "a frame is timed at its scan's first report")
    }

    func testASlotWithNoPositionIsIgnored() {
        var builder = TouchFrameBuilder()
        let noPosition = SlotReading(slot: 0, contactID: 3, tip: true, position: nil)
        XCTAssertEqual(ids(builder.add(report(2, [noPosition, down(1, id: 4, 0.4, 0.4)]), at: 1)), [4])
        XCTAssertEqual(ids(builder.add(report(1, [noPosition]), at: 2)), [])
    }

    // MARK: - The ILITEK's recorded takes

    /// Survey B's ILITEK take `number`, its touch interface's reports decoded and built into frames
    /// by a builder of its own.
    private func ilitekFrames(take number: Int) throws -> [ContactFrame] {
        let ilitek = try XCTUnwrap(SurveyFixtures.surveyB.touchscreen(vendorID: ilitekVendorID, productID: ilitekProductID))
        let interface = try XCTUnwrap(ilitek.interfaces.first { $0.key == "touchscreen" }, "no touchscreen interface")
        let decoder = try XCTUnwrap(InterfaceDecoder(descriptor: interface.descriptor), "the descriptor did not parse")
        let take = try XCTUnwrap(ilitek.takes.first { $0.number == number }, "no take \(number)")
        var builder = TouchFrameBuilder()
        var frames: [ContactFrame] = []
        for (index, recorded) in take.reports.enumerated() where recorded.interfaceKey == "touchscreen" {
            guard case .touch(let touch)? = decoder.decode(recorded.bytes) else {
                XCTFail("take \(number) report \(index) did not decode as a touch report")
                continue
            }
            if let frame = builder.add(touch, at: recorded.hostTime) { frames.append(frame) }
        }
        return frames
    }

    func testTheILITEKTracksTenFingers() throws {
        let frames = try ilitekFrames(take: 3)
        XCTAssertEqual(frames.map(\.contacts.count).max(), 10)
    }

    /// Review Focus 2: the ILITEK gives the second tap the contact ID the first one had, in the
    /// very next touch after the lift. Only the empty frame between them makes them two touches.
    func testTheILITEKDoubleTapIsTwoTouches() throws {
        let frames = try ilitekFrames(take: 10)
        // The glass was clear before the take's first report.
        let states = [false] + frames.map { !$0.contacts.isEmpty }
        let collapsed = states.enumerated().filter { $0.offset == 0 || states[$0.offset - 1] != $0.element }.map(\.element)
        XCTAssertEqual(collapsed, [false, true, false, true, false], "empty → down → empty → down → empty")
        XCTAssertEqual(collapsed.filter { $0 }.count, 2, "two runs of frames with a finger down")
        XCTAssertEqual(Set(frames.flatMap { $0.contacts.map(\.id) }), [0], "both taps have contact ID 0")
    }

    func testEveryILITEKTakeEndsWithAClearGlass() throws {
        for take in 1...15 {
            let frames = try ilitekFrames(take: take)
            XCTAssertFalse(frames.isEmpty, "take \(take) built no frame")
            XCTAssertEqual(frames.last?.contacts, [], "take \(take) does not end with a clear glass")
        }
    }

    func testILITEKContactIDsAreStableWhileDown() throws {
        for take in 1...15 {
            let frames = try ilitekFrames(take: take)
            var largest = 0.0
            var compared = 0
            for (before, after) in zip(frames, frames.dropFirst()) {
                for contact in after.contacts {
                    guard let previous = before.contacts.first(where: { $0.id == contact.id }) else { continue }
                    let moved = hypot(Double(contact.position.x - previous.position.x), Double(contact.position.y - previous.position.y))
                    largest = max(largest, moved)
                    compared += 1
                }
            }
            XCTAssertGreaterThan(compared, 0, "take \(take): no contact ID was in two consecutive frames, so nothing was compared")
            XCTAssertLessThanOrEqual(largest, 0.2, "take \(take): a contact jumped \(largest) of the glass between frames")
        }
    }

    // MARK: - Beyond the plan's table: inputs the rules must survive

    func testAPanelWithNoContactCountGivesAFrameForEveryReport() {
        var builder = TouchFrameBuilder()
        let frames = [
            builder.add(report(nil, [down(0, id: 1, 0.1, 0.1)], slotsPerReport: 4), at: 1.00),
            builder.add(report(nil, [blank(0), blank(1), blank(2), down(3, id: 1, 0.2, 0.1)], slotsPerReport: 4), at: 1.01),
            builder.add(report(nil, [], slotsPerReport: 4), at: 1.02),
        ]
        XCTAssertEqual(frames.map(ids), [[1], [1], []])
    }

    /// A report with no Contact Count is a complete scan, read up to its 256th slot: what is beyond
    /// is not read, and the scan never continues into the next report.
    func testAReportWithNoContactCountIsReadUpToIts256thSlot() {
        var builder = TouchFrameBuilder()
        let slots = (0..<300).map { down($0, id: $0, 0.5, 0.5) }
        XCTAssertEqual(ids(builder.add(TouchReport(contactCount: nil, slots: slots), at: 1)), Array(0..<256))
        XCTAssertEqual(ids(builder.add(TouchReport(contactCount: nil, slots: [down(0, id: 299, 0.5, 0.5)]), at: 2)), [299])
    }

    /// A Contact Count says how many of a report's slots carry contacts; what a panel leaves in the
    /// slots after them is not read. The ILITEK's count always covered every slot that carried data.
    func testSlotsBeyondTheContactCountAreNotRead() {
        var builder = TouchFrameBuilder()
        let frame = builder.add(report(1, [down(0, id: 0, 0.1, 0.1), down(1, id: 1, 0.6, 0.6)]), at: 1)
        XCTAssertEqual(ids(frame), [0])
    }

    /// A panel that stops in the middle of a split scan: the next report with a Contact Count
    /// starts a new scan, timed at itself, and nothing of the unfinished one reaches a frame.
    func testAnUnfinishedSplitScanGivesWayToTheNextScan() {
        var builder = TouchFrameBuilder()
        XCTAssertNil(builder.add(report(3, [down(0, id: 0, 0.1, 0.1), down(1, id: 1, 0.2, 0.2)], slotsPerReport: 2), at: 1.0))
        // Silence, then a scan that fits one report.
        let whole = builder.add(report(1, [down(0, id: 5, 0.5, 0.5)], slotsPerReport: 2), at: 2.0)
        XCTAssertEqual(whole, ContactFrame(time: 2.0, contacts: [Contact(id: 5, position: CGPoint(x: 0.5, y: 0.5))]))

        // Another unfinished split scan, then a split scan that completes.
        XCTAssertNil(builder.add(report(3, [down(0, id: 0, 0.1, 0.1), down(1, id: 1, 0.2, 0.2)], slotsPerReport: 2), at: 3.0))
        XCTAssertNil(builder.add(report(4, [down(0, id: 6, 0.6, 0.6), down(1, id: 7, 0.7, 0.7)], slotsPerReport: 2), at: 4.0))
        let split = builder.add(report(0, [down(0, id: 8, 0.8, 0.8), down(1, id: 9, 0.9, 0.9)], slotsPerReport: 2), at: 4.004)
        XCTAssertEqual(ids(split), [6, 7, 8, 9])
        XCTAssertEqual(split?.time, 4.0)

        // A report that continues no scan has a Contact Count of 0: a scan with nothing down.
        XCTAssertEqual(builder.add(report(0, [down(0, id: 2, 0.2, 0.2)], slotsPerReport: 2), at: 5.0),
                       ContactFrame(time: 5.0, contacts: []))
    }

    /// One contact ID in two slots of one scan is one contact. A slot with the tip on wins over one
    /// with the tip off, and the first slot with the tip on gives the position.
    func testOneContactIDInTwoSlotsIsOneContact() {
        var builder = TouchFrameBuilder()
        let bothDown = builder.add(report(2, [down(0, id: 3, 0.3, 0.3), down(1, id: 3, 0.9, 0.9)]), at: 1)
        XCTAssertEqual(bothDown?.contacts, [Contact(id: 3, position: CGPoint(x: 0.3, y: 0.3))])
        let liftedFirst = builder.add(report(2, [lifted(0, id: 3), down(1, id: 3, 0.31, 0.3)]), at: 2)
        XCTAssertEqual(liftedFirst?.contacts, [Contact(id: 3, position: CGPoint(x: 0.31, y: 0.3))])
        let liftedSecond = builder.add(report(2, [down(0, id: 3, 0.32, 0.3), lifted(1, id: 3)]), at: 3)
        XCTAssertEqual(liftedSecond?.contacts, [Contact(id: 3, position: CGPoint(x: 0.32, y: 0.3))])
    }

    func testATipOffForAContactNeverDownChangesNothing() {
        var builder = TouchFrameBuilder()
        XCTAssertEqual(builder.add(report(1, [lifted(0, id: 4)]), at: 1), ContactFrame(time: 1, contacts: []))
        XCTAssertEqual(ids(builder.add(report(2, [down(0, id: 0, 0.1, 0.1), lifted(1, id: 9)]), at: 2)), [0])
    }

    func testASlotWithNoContactIDIsIgnored() {
        var builder = TouchFrameBuilder()
        let noID = SlotReading(slot: 0, contactID: nil, tip: true, position: CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(ids(builder.add(report(2, [noID, down(1, id: 4, 0.4, 0.4)]), at: 1)), [4])
    }

    /// Reports come from whatever is plugged in. None may trap the builder, and however long it
    /// runs it holds one scan at most: a scan reads 256 slots at most, whatever its count says.
    func testNoReportCanTrapTheBuilderOrGrowIt() {
        let odd: [SlotReading] = [
            SlotReading(slot: -1, contactID: nil, tip: true, position: CGPoint(x: 0.5, y: 0.5)),
            SlotReading(slot: 99, contactID: Int.min, tip: true, position: nil),
            SlotReading(slot: 0, contactID: Int.max, tip: true, position: CGPoint(x: -3, y: 7),
                        size: CGSize(width: -1, height: 0), isConfident: false),
            SlotReading(slot: 0, contactID: Int.min, tip: true, position: CGPoint(x: CGFloat.nan, y: .infinity)),
        ]
        let reports = [
            TouchReport(contactCount: Int.max, slots: odd),
            TouchReport(contactCount: Int.min, slots: odd),
            TouchReport(contactCount: -1, slots: odd),
            TouchReport(contactCount: 0, slots: []),
            TouchReport(contactCount: nil, slots: odd),
            TouchReport(contactCount: 3, slots: []),
            TouchReport(contactCount: 2, slots: odd + odd + odd),
        ]
        var builder = TouchFrameBuilder()
        for (index, report) in (reports + reports.reversed()).enumerated() {
            _ = builder.add(report, at: TimeInterval(index))
        }
        // A count far larger than any panel's slots, then reports of ten new contacts each.
        XCTAssertNil(builder.add(TouchReport(contactCount: Int.max, slots: []), at: 100))
        var frame: ContactFrame?
        var reportsRead = 0
        while frame == nil, reportsRead < 1_000 {
            let slots = (0..<10).map { down($0, id: reportsRead * 10 + $0, 0.5, 0.5) }
            frame = builder.add(TouchReport(contactCount: 0, slots: slots), at: 100 + TimeInterval(reportsRead))
            reportsRead += 1
        }
        XCTAssertEqual(reportsRead, 26, "the scan ends once 256 slots are read")
        XCTAssertEqual(frame?.contacts.count, 256)
        XCTAssertEqual(frame?.time, 100)
    }
}
