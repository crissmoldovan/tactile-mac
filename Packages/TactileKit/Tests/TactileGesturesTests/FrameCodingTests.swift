import XCTest
@testable import TactileGestures

final class FrameCodingTests: XCTestCase {

    func testRecordingRoundTrips() throws {
        let frames = [
            TouchFrame(time: 1.5, fingers: [Finger(id: 0, location: CGPoint(x: 0.25, y: 0.5))],
                       surfaceSize: CGSize(width: 527, height: 296)),
            TouchFrame(time: 1.51, fingers: [], surfaceSize: CGSize(width: 527, height: 296)),
        ]
        let encoder = JSONEncoder()
        var data = Data()
        for frame in frames {
            data.append(try encoder.encode(frame))
            data.append(UInt8(ascii: "\n"))
        }
        XCTAssertEqual(try TouchFrame.decodeLines(data), frames)
    }

    func testFramesRecordedWithoutFingerExtrasStillDecode() throws {
        let line = #"{"time":1.5,"surfaceSize":[500,300],"fingers":[{"id":3,"location":[0.25,0.5]}]}"#
        let frames = try TouchFrame.decodeLines(Data(line.utf8))
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].fingers[0].id, 3)
        XCTAssertNil(frames[0].fingers[0].size)
        XCTAssertNil(frames[0].fingers[0].isConfident)
    }

    func testFingerExtrasRoundTrip() throws {
        let finger = Finger(id: 1, location: CGPoint(x: 0.1, y: 0.2),
                            size: CGSize(width: 9, height: 12), isConfident: false)
        let frame = TouchFrame(time: 2, fingers: [finger], surfaceSize: CGSize(width: 240, height: 90))
        XCTAssertEqual(try TouchFrame.decodeLines(JSONEncoder().encode(frame)), [frame])
    }

    func testGestureOptionsDefaultToEverythingOnAndSurviveMissingKeys() throws {
        XCTAssertEqual(GestureOptions.all, GestureOptions())
        XCTAssertTrue(GestureOptions().twoFingerScroll && GestureOptions().pinch
                      && GestureOptions().twoFingerTap && GestureOptions().swipes)
        XCTAssertEqual(try JSONDecoder().decode(GestureOptions.self, from: Data("{}".utf8)), .all)
        var options = GestureOptions()
        options.pinch = false
        XCTAssertEqual(try JSONDecoder().decode(GestureOptions.self, from: JSONEncoder().encode(options)), options)
    }

    func testEachGestureOptionDecodesIntoItsOwnField() throws {
        let fields: [(key: String, field: WritableKeyPath<GestureOptions, Bool>)] = [
            ("twoFingerScroll", \.twoFingerScroll), ("pinch", \.pinch),
            ("twoFingerTap", \.twoFingerTap), ("swipes", \.swipes),
        ]
        for (key, field) in fields {
            var expected = GestureOptions.all
            expected[keyPath: field] = false
            let json = #"{"\#(key)":false}"#
            XCTAssertEqual(try JSONDecoder().decode(GestureOptions.self, from: Data(json.utf8)), expected, json)
        }
    }

    func testBehaviourChoicesHaveStableStoredNames() {
        XCTAssertEqual(OneFingerMode.allCases.map(\.rawValue), ["automatic", "alwaysDrag", "alwaysScroll"])
        XCTAssertEqual(PointerReturn.allCases.map(\.rawValue), ["backWhereItWas", "staysWhereTouched"])
    }
}
