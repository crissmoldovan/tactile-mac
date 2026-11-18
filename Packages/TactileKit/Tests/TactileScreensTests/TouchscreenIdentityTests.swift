import Foundation
import XCTest
import TactileScreens

// The desk's two touchscreens, as their USB descriptors report them.

/// The wch.cn "TouchScreen": its serial is a real serial number.
private func wchStrip(at location: UInt32) -> TouchscreenFacts {
    TouchscreenFacts(
        vendorID: 0x27c0, productID: 0x0859, serial: "TEST-SERIAL-0001", locationID: location, name: "TouchScreen")
}

/// The ILITEK "ILITEK-TP": its "serial" is a firmware version every unit of the model shares, so two
/// of them are identical twins.
private func ilitek(at location: UInt32) -> TouchscreenFacts {
    TouchscreenFacts(
        vendorID: 0x222a, productID: 0x0001, serial: "V06.00.00.00", locationID: location, name: "ILITEK-TP")
}

/// A touchscreen of the ILITEK's model whose serial looks like a port ID.
private func lookalike(_ serial: String, at location: UInt32) -> TouchscreenFacts {
    TouchscreenFacts(vendorID: 0x222a, productID: 0x0001, serial: serial, locationID: location, name: "ILITEK-TP")
}

/// Serials that look like port IDs: the ILITEK's port ID on portA in the old form, which put the
/// port last, and in the current form.
private let portLikeSerials = ["V06.00.00.00@01141000", "@01141000:222a:0001:V06.00.00.00"]

private let wchBase = TouchscreenIdentity.baseID(vendorID: 0x27c0, productID: 0x0859, serial: "TEST-SERIAL-0001")
private let ilitekBase = TouchscreenIdentity.baseID(vendorID: 0x222a, productID: 0x0001, serial: "V06.00.00.00")

/// An ILITEK's record by port.
private func byPort(_ location: UInt32) -> TouchscreenID {
    TouchscreenIdentity.portID(ilitekBase, locationID: location)
}

private func baseID(of screen: TouchscreenFacts) -> TouchscreenID {
    TouchscreenIdentity.baseID(vendorID: screen.vendorID, productID: screen.productID, serial: screen.serial)
}

// USB ports, as location IDs. The ILITEK was on portA during the survey; portD is below the others.
private let portA: UInt32 = 0x0114_1000
private let portB: UInt32 = 0x0114_2000
private let portC: UInt32 = 0x0114_3000
private let portD: UInt32 = 0x0112_0000
private let portE: UInt32 = 0x0113_0000

private func assign(
    connected: [TouchscreenFacts], current: [UInt32: TouchscreenID] = [:], stored: Set<TouchscreenID> = []
) -> [UInt32: TouchscreenID] {
    TouchscreenIdentity.assign(connected: connected, current: current, stored: stored)
}

private func hex(_ location: UInt32) -> String {
    String(format: "%08x", location)
}

/// One call to `assign`, and its answer.
private struct Call: CustomStringConvertible {
    let connected: [TouchscreenFacts]
    let current: [UInt32: TouchscreenID]
    let stored: Set<TouchscreenID>
    let answer: [UInt32: TouchscreenID]

    init(connected: [TouchscreenFacts], current: [UInt32: TouchscreenID] = [:], stored: Set<TouchscreenID> = []) {
        self.connected = connected
        self.current = current
        self.stored = stored
        answer = assign(connected: connected, current: current, stored: stored)
    }

    var description: String {
        let screens = connected.map { "\($0.serial) on \(hex($0.locationID))" }
        let current = self.current.map { "\(hex($0.key)): \($0.value)" }.sorted()
        return "connected \(screens), current \(current), stored \(stored.map(\.rawValue).sorted())"
    }
}

// The examples the brief's tests walk one by one.

private let aNewLoneStrip = Call(connected: [wchStrip(at: portA)])
private let aNewLoneILITEK = Call(connected: [ilitek(at: portA)])
private let aKnownILITEKOnAnotherPort = Call(connected: [ilitek(at: portB)], stored: [ilitekBase])
private let twoNewTwins = Call(connected: [ilitek(at: portA), ilitek(at: portB)])
/// The twin arrives on a port below the known one's, so taking arrivals in location order alone
/// would hand it the known one's record.
private let aTwinArrivingBelowTheKnownOne = Call(
    connected: [ilitek(at: portB), ilitek(at: portD)], current: [portB: ilitekBase], stored: [ilitekBase])
private let aTwinArrivingAboveTheKnownOne = Call(
    connected: [ilitek(at: portB), ilitek(at: portC)], current: [portB: ilitekBase], stored: [ilitekBase])
private let aTwinBackAloneOnItsOldPort = Call(connected: [ilitek(at: portB)], stored: [ilitekBase, byPort(portB)])

/// Every call the property tests check:
/// - the examples above;
/// - three identical touchscreens with every subset of their records stored: all at once, and one at
///   a time in every order, each answer the next call's `current`, then unplugged in that order;
/// - the same for two ILITEKs and two touchscreens of their model whose serials look like port IDs;
/// - ILITEKs still connected, as `assign` can have answered for them, while any of a twin below, a
///   twin above and the strip arrive, with every subset of their records stored.
private let everyCall: [Call] = {
    var calls = [
        aNewLoneStrip, aNewLoneILITEK, aKnownILITEKOnAnotherPort, twoNewTwins, aTwinArrivingBelowTheKnownOne,
        aTwinArrivingAboveTheKnownOne, aTwinBackAloneOnItsOldPort,
    ]

    calls += comingAndGoing(
        [ilitek(at: portA), ilitek(at: portB), ilitek(at: portC)],
        records: [ilitekBase, byPort(portA), byPort(portB), byPort(portC)])

    let lookalikes = [lookalike(portLikeSerials[0], at: portC), lookalike(portLikeSerials[1], at: portD)]
    calls += comingAndGoing(
        [ilitek(at: portA), ilitek(at: portB)] + lookalikes,
        records: [ilitekBase, byPort(portA)] + lookalikes.map(baseID(of:)))

    let befores: [[UInt32: TouchscreenID]] = [
        [portA: ilitekBase],
        [portA: byPort(portA)],
        [portA: byPort(portA), portB: ilitekBase],
        [portA: ilitekBase, portB: byPort(portB)],
    ]
    let arrivals = [ilitek(at: portD), ilitek(at: portC), wchStrip(at: portE)]
    let records = [
        ilitekBase, byPort(portA), byPort(portB), byPort(portC), byPort(portD), wchBase,
        TouchscreenIdentity.portID(wchBase, locationID: portE),
    ]
    for before in befores {
        let stillConnected = before.keys.sorted().map { ilitek(at: $0) }
        for arrived in subsets(of: arrivals) {
            for stored in subsets(of: records).map(Set.init) {
                calls.append(Call(connected: stillConnected + arrived, current: before, stored: stored))
            }
        }
    }
    return calls
}()

/// `screens` with every subset of `records` stored: all at once, and one at a time in every order,
/// each answer the next call's `current`, then unplugged in the same order.
private func comingAndGoing(_ screens: [TouchscreenFacts], records: [TouchscreenID]) -> [Call] {
    var calls: [Call] = []
    for stored in subsets(of: records).map(Set.init) {
        calls.append(Call(connected: screens, stored: stored))
        for order in permutations(of: screens) {
            var connected: [TouchscreenFacts] = []
            var current: [UInt32: TouchscreenID] = [:]
            func step() {
                let call = Call(connected: connected, current: current, stored: stored)
                calls.append(call)
                current = call.answer
            }
            for screen in order {
                connected.append(screen)
                step()
            }
            for screen in order {
                connected.removeAll { $0.locationID == screen.locationID }
                step()
            }
        }
    }
    return calls
}

/// The app's side of `assign`: what is plugged in, the last answer, and the settings file, which
/// gains a record for each touchscreen given one.
private struct Desk {
    var connected: [TouchscreenFacts] = []
    var current: [UInt32: TouchscreenID] = [:]
    var stored: Set<TouchscreenID> = []

    mutating func plug(_ screen: TouchscreenFacts) {
        connected.append(screen)
        update()
    }

    mutating func unplug(_ location: UInt32) {
        connected.removeAll { $0.locationID == location }
        update()
    }

    private mutating func update() {
        current = assign(connected: connected, current: current, stored: stored)
        stored.formUnion(current.values)
    }
}

private func subsets<T>(of items: [T]) -> [[T]] {
    items.reduce([[]]) { partial, item in partial + partial.map { $0 + [item] } }
}

private func permutations<T>(of items: [T]) -> [[T]] {
    guard !items.isEmpty else { return [[]] }
    return items.indices.flatMap { index -> [[T]] in
        var rest = items
        let item = rest.remove(at: index)
        return permutations(of: rest).map { [item] + $0 }
    }
}

final class TouchscreenIdentityTests: XCTestCase {

    // MARK: - The brief's tests

    func testIDsLookLikeVendorProductSerial() {
        XCTAssertEqual(wchBase.rawValue, "27c0:0859:TEST-SERIAL-0001")
        XCTAssertEqual(ilitekBase.rawValue, "222a:0001:V06.00.00.00")
        XCTAssertEqual(byPort(0x0114_1000).rawValue, "@01141000:222a:0001:V06.00.00.00")
        XCTAssertEqual(wchBase.description, "27c0:0859:TEST-SERIAL-0001")
        XCTAssertEqual(byPort(0x0114_1000).description, "@01141000:222a:0001:V06.00.00.00")

        let noSerial = TouchscreenIdentity.baseID(vendorID: 0x222a, productID: 0x0001, serial: "")
        XCTAssertEqual(noSerial.rawValue, "222a:0001:")
        XCTAssertEqual(TouchscreenIdentity.portID(noSerial, locationID: portA).rawValue, "@01141000:222a:0001:")

        // Always four and eight digits, in lower case.
        XCTAssertEqual(TouchscreenIdentity.baseID(vendorID: 0x5ac, productID: 0x12, serial: "S").rawValue, "05ac:0012:S")
        XCTAssertEqual(TouchscreenIdentity.baseID(vendorID: 0, productID: 0, serial: "S").rawValue, "0000:0000:S")
        XCTAssertEqual(
            TouchscreenIdentity.baseID(vendorID: 0xABCD, productID: 0xFFFF, serial: "AbC").rawValue, "abcd:ffff:AbC")
        XCTAssertEqual(TouchscreenIdentity.portID(wchBase, locationID: 1).rawValue, "@00000001:27c0:0859:TEST-SERIAL-0001")
        XCTAssertEqual(
            TouchscreenIdentity.portID(wchBase, locationID: 0xFFFF_FFFF).rawValue, "@ffffffff:27c0:0859:TEST-SERIAL-0001")

        // The serial exactly as reported, whatever it holds.
        let oddSerial = TouchscreenIdentity.baseID(vendorID: 0x222a, productID: 0x0001, serial: " a:b@01141000 é ")
        XCTAssertEqual(oddSerial.rawValue, "222a:0001: a:b@01141000 é ")

        for base in [wchBase, ilitekBase, noSerial, oddSerial] {
            XCTAssertFalse(TouchscreenIdentity.isByPort(base), "\(base)")
            for location: UInt32 in [0, 1, portA, 0xFFFF_FFFF] {
                let id = TouchscreenIdentity.portID(base, locationID: location)
                XCTAssertTrue(TouchscreenIdentity.isByPort(id), "\(id)")
            }
        }
        // Text of neither form isn't by port: seven digits, nine digits, an upper-case digit, no "@",
        // no colon.
        for text in [
            "@0114100:222a:0001:x", "@011410000:222a:0001:x", "@0114100A:222a:0001:x", "01141000:222a:0001:x",
            "@01141000", "",
        ] {
            XCTAssertFalse(TouchscreenIdentity.isByPort(TouchscreenID(rawValue: text)), text)
        }
    }

    func testNoSerialCanMakeABaseIDLookLikeAPortID() {
        let serials = ["@01141000", "x@01141000", "@01141000:222a:0001:", ""] + portLikeSerials + ["V06.00.00.00"]
        // The two panels' vendor and product, none, and values no USB device can report.
        let models = [(0x222a, 0x0001), (0x27c0, 0x0859), (0, 0), (-1, 0x1_0000)]
        let bases = models.flatMap { vendor, product in
            serials.map { TouchscreenIdentity.baseID(vendorID: vendor, productID: product, serial: $0) }
        }
        let locations: [UInt32] = [0, 1, portA, portB, 0xFFFF_FFFF]
        let ports = bases.flatMap { base in locations.map { TouchscreenIdentity.portID(base, locationID: $0) } }

        for base in bases {
            XCTAssertFalse(TouchscreenIdentity.isByPort(base), "\(base)")
            XCTAssertFalse(ports.contains(base), "\(base) is a port ID too")
        }
        for port in ports {
            XCTAssertTrue(TouchscreenIdentity.isByPort(port), "\(port)")
        }
        XCTAssertEqual(Set(bases + ports).count, bases.count + ports.count, "two of these IDs are the same")
    }

    func testEveryConnectedTouchscreenGetsARecord() {
        for call in everyCall {
            XCTAssertEqual(Set(call.answer.keys), Set(call.connected.map(\.locationID)), "\(call)")
        }
        // One location listed twice, which USB doesn't allow: still one record for each location.
        for connected in [
            [ilitek(at: portA), ilitek(at: portA), ilitek(at: portB)],
            [ilitek(at: portA), wchStrip(at: portA), ilitek(at: portB)],
        ] {
            XCTAssertEqual(Set(assign(connected: connected).keys), [portA, portB])
        }
    }

    func testADictionaryKeyedByIDCodesAsAnObject() throws {
        let records = [wchBase: 1, byPort(portA): 2]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(records)
        XCTAssertEqual(
            String(decoding: data, as: UTF8.self),
            #"{"27c0:0859:TEST-SERIAL-0001":1,"@01141000:222a:0001:V06.00.00.00":2}"#)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Int])
        XCTAssertEqual(Set(object.keys), ["27c0:0859:TEST-SERIAL-0001", "@01141000:222a:0001:V06.00.00.00"])
        XCTAssertEqual(try JSONDecoder().decode([TouchscreenID: Int].self, from: data), records)
    }

    func testANewLoneTouchscreenGetsItsBaseID() {
        XCTAssertEqual(aNewLoneStrip.answer, [portA: wchBase])
        // The ILITEK too: its serial is shared by every unit of the model, but alone it is told apart
        // by it all the same.
        XCTAssertEqual(aNewLoneILITEK.answer, [portA: ilitekBase])
    }

    func testAKnownTouchscreenKeepsItsRecordOnAnotherPort() {
        XCTAssertEqual(aKnownILITEKOnAnotherPort.answer, [portB: ilitekBase])
    }

    func testTwoNewIdenticalTouchscreensAreToldApartByPort() {
        XCTAssertEqual(twoNewTwins.answer, [portA: byPort(portA), portB: byPort(portB)])
    }

    func testAKnownOneKeepsItsRecordWhenItsTwinArrives() {
        XCTAssertEqual(aTwinArrivingBelowTheKnownOne.answer, [portB: ilitekBase, portD: byPort(portD)])
        XCTAssertEqual(aTwinArrivingAboveTheKnownOne.answer, [portB: ilitekBase, portC: byPort(portC)])
    }

    func testATwinComingBackAloneOnItsOldPortGetsItsPortRecord() {
        XCTAssertEqual(aTwinBackAloneOnItsOldPort.answer, [portB: byPort(portB)])
    }

    func testNoRecordIsEverSharedByTwoConnectedTouchscreens() {
        for call in everyCall {
            XCTAssertEqual(Set(call.answer.values).count, call.answer.count, "\(call) → \(call.answer)")
        }
    }

    func testAStillConnectedTouchscreenNeverChangesRecord() {
        var checked = 0
        for call in everyCall {
            let connected = Set(call.connected.map(\.locationID))
            for (location, record) in call.current where connected.contains(location) {
                XCTAssertEqual(call.answer[location], record, "\(call)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 4_000)
    }

    // MARK: - Beyond the brief

    func testAnIDCodesAsAPlainString() throws {
        let ids = [wchBase, byPort(portA)]
        let data = try JSONEncoder().encode(ids)
        XCTAssertEqual(
            String(decoding: data, as: UTF8.self), #"["27c0:0859:TEST-SERIAL-0001","@01141000:222a:0001:V06.00.00.00"]"#)
        XCTAssertEqual(try JSONDecoder().decode([TouchscreenID].self, from: data), ids)

        let odd = TouchscreenIdentity.baseID(vendorID: 0x222a, productID: 0x0001, serial: "a\"b\\c:@é\u{0}")
        XCTAssertEqual(try JSONDecoder().decode([TouchscreenID].self, from: JSONEncoder().encode([odd])), [odd])

        XCTAssertThrowsError(
            try JSONDecoder().decode([TouchscreenID].self, from: Data(#"[{"rawValue":"27c0:0859:TEST-SERIAL-0001"}]"#.utf8)))
    }

    func testTheAnswerDoesNotDependOnTheOrderOfConnected() {
        let connected = [ilitek(at: portA), ilitek(at: portB), wchStrip(at: portC), ilitek(at: portD)]
        let records = [ilitekBase, byPort(portA), byPort(portB), byPort(portD), wchBase]
        let currents: [[UInt32: TouchscreenID]] = [[:], [portB: ilitekBase], [portC: wchBase, portA: byPort(portA)]]
        for current in currents {
            for stored in subsets(of: records).map(Set.init) {
                let expected = assign(connected: connected, current: current, stored: stored)
                XCTAssertEqual(expected.count, connected.count)
                for order in permutations(of: connected) {
                    XCTAssertEqual(
                        assign(connected: order, current: current, stored: stored), expected,
                        "order \(order), current \(current), stored \(stored)")
                }
            }
        }
    }

    /// Three identical touchscreens plugged in one at a time, the first unplugged, then plugged back
    /// into a fourth port, with the settings file gaining each record as it is given.
    func testThreeTwinsComingAndGoing() {
        var desk = Desk()
        desk.plug(ilitek(at: portA))
        XCTAssertEqual(desk.current, [portA: ilitekBase])
        desk.plug(ilitek(at: portB))
        XCTAssertEqual(desk.current, [portA: ilitekBase, portB: byPort(portB)])
        desk.plug(ilitek(at: portC))
        XCTAssertEqual(desk.current, [portA: ilitekBase, portB: byPort(portB), portC: byPort(portC)])
        desk.unplug(portA)
        XCTAssertEqual(desk.current, [portB: byPort(portB), portC: byPort(portC)])
        desk.plug(ilitek(at: portD))
        XCTAssertEqual(desk.current, [portB: byPort(portB), portC: byPort(portC), portD: ilitekBase])
        XCTAssertEqual(desk.stored, [ilitekBase, byPort(portB), byPort(portC)])
    }

    func testOneLocationListedTwiceDoesNotTrap() {
        // The same touchscreen twice, as a caller listing it once per interface would.
        XCTAssertEqual(assign(connected: [ilitek(at: portA), ilitek(at: portA)]), [portA: ilitekBase])
        XCTAssertEqual(
            assign(connected: [ilitek(at: portA), ilitek(at: portA), ilitek(at: portB)]),
            [portA: byPort(portA), portB: byPort(portB)])

        // Two different touchscreens at one location, which USB doesn't allow: one record for the
        // location, whatever the order, and the one already holding a record there keeps it.
        let both = [ilitek(at: portA), wchStrip(at: portA)]
        let answer = assign(connected: both)
        XCTAssertEqual(answer.count, 1)
        XCTAssertTrue([[portA: ilitekBase], [portA: wchBase]].contains(answer), "\(answer)")
        XCTAssertEqual(assign(connected: both.reversed()), answer)
        for record in [ilitekBase, wchBase] {
            XCTAssertEqual(assign(connected: both, current: [portA: record]), [portA: record])
            XCTAssertEqual(assign(connected: both.reversed(), current: [portA: record]), [portA: record])
        }
    }

    func testARecordInCurrentIsKeptOnlyByTheTouchscreenItBelongsTo() {
        // Its touchscreen has gone: the record is dropped from the answer, and free for whoever comes.
        XCTAssertEqual(assign(connected: [], current: [portA: ilitekBase], stored: [ilitekBase]), [:])
        XCTAssertEqual(
            assign(connected: [ilitek(at: portB)], current: [portA: ilitekBase], stored: [ilitekBase]),
            [portB: ilitekBase])

        // Another model is at its port now, a change the caller didn't pass on: it isn't given the
        // record.
        XCTAssertEqual(
            assign(connected: [wchStrip(at: portA)], current: [portA: ilitekBase], stored: [ilitekBase]),
            [portA: wchBase])
        // Nor is a twin given another port's record.
        XCTAssertEqual(
            assign(connected: [ilitek(at: portA)], current: [portA: byPort(portB)], stored: [byPort(portB)]),
            [portA: ilitekBase])

        // One record twice in `current`, which `assign` never answers: the lower location keeps it.
        XCTAssertEqual(
            assign(
                connected: [ilitek(at: portA), ilitek(at: portB)],
                current: [portA: ilitekBase, portB: ilitekBase], stored: [ilitekBase]),
            [portA: ilitekBase, portB: byPort(portB)])
    }

    func testAnotherModelsPortRecordIsNotTaken() {
        // An ILITEK was remembered by port on portA; the strip is there now.
        XCTAssertEqual(
            assign(connected: [wchStrip(at: portA)], stored: [ilitekBase, byPort(portA)]), [portA: wchBase])
        XCTAssertEqual(
            assign(connected: [wchStrip(at: portA), ilitek(at: portB)], stored: [byPort(portA)]),
            [portA: wchBase, portB: ilitekBase])
    }

    /// A touchscreen whose serial looks like the ILITEK's port ID on portA takes only its own records,
    /// and the ILITEK there still gets its own.
    func testASerialThatLooksLikeAPortIDTakesNoOtherTouchscreensRecord() {
        for serial in portLikeSerials {
            let other = lookalike(serial, at: portC)
            let otherBase = baseID(of: other)
            XCTAssertNotEqual(otherBase, byPort(portA), serial)

            // Alone on portA, with the ILITEK's port record stored: not given it.
            XCTAssertEqual(
                assign(connected: [lookalike(serial, at: portA)], stored: [byPort(portA)]), [portA: otherBase])

            // The lookalike, then a twin elsewhere, then the ILITEK on portA: each has its own.
            var desk = Desk(stored: [byPort(portA)])
            desk.plug(other)
            desk.plug(ilitek(at: portB))
            desk.plug(ilitek(at: portA))
            XCTAssertEqual(desk.current, [portC: otherBase, portB: ilitekBase, portA: byPort(portA)], serial)
        }
    }
}
