import CoreGraphics
import XCTest
@testable import TactileGestures
@testable import TactileOutput

final class FrameRecorderTests: XCTestCase {

    func testRecordedFramesReadBackAsTheSameFrames() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = try XCTUnwrap(FrameRecorder(directory: directory, label: "ILITEK-TP 222a:0001"))
        let frames = [
            TouchFrame(time: 1, fingers: [Finger(id: 3, location: CGPoint(x: 0.5, y: 0.25))], surfaceSize: CGSize(width: 527, height: 296)),
            TouchFrame(time: 1.01, fingers: [], surfaceSize: CGSize(width: 527, height: 296)),
        ]
        frames.forEach(recorder.append)
        XCTAssertEqual(try TouchFrame.decodeLines(Data(contentsOf: recorder.url)), frames)
    }

    func testRecordingIsOffUnlessTurnedOn() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        XCTAssertNil(FrameRecorder.fromDefaults(defaults, label: "ILITEK-TP 222a:0001"))
    }

    func testEachTouchscreenRecordsToAFileNamedAfterIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = try XCTUnwrap(FrameRecorder(directory: directory, label: "ILITEK-TP 222a:0001",
                                                   now: Date(timeIntervalSince1970: 0)))
        XCTAssertTrue(recorder.url.lastPathComponent.hasPrefix("ILITEK-TP-222a-0001-"))
    }

    func testTwoRecordersStartedInTheSameSecondNeverShareAFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 0)
        let first = try XCTUnwrap(FrameRecorder(directory: directory, label: "Touch Screen", now: now))
        let second = try XCTUnwrap(FrameRecorder(directory: directory, label: "Touch-Screen", now: now))
        XCTAssertNotEqual(first.url, second.url)

        let frame = TouchFrame(time: 1, fingers: [], surfaceSize: CGSize(width: 100, height: 50))
        first.append(frame)
        second.append(frame)
        second.append(frame)
        XCTAssertEqual(try TouchFrame.decodeLines(Data(contentsOf: first.url)).count, 1)
        XCTAssertEqual(try TouchFrame.decodeLines(Data(contentsOf: second.url)).count, 2)
    }

    /// Review of Task 7: a write that fails, such as on a full disk, raised an exception Swift
    /// can't catch. A handle that is already closed fails the same way without filling a disk.
    func testAFailedWriteStopsTheRecorderWithoutCrashing() throws {
        let handle = try XCTUnwrap(FileHandle(forWritingAtPath: "/dev/null"))
        try handle.close()
        let recorder = FrameRecorder(url: URL(fileURLWithPath: "/dev/null"), handle: handle)
        XCTAssertTrue(recorder.isRecording)

        let frame = TouchFrame(time: 1, fingers: [], surfaceSize: CGSize(width: 100, height: 50))
        recorder.append(frame)
        XCTAssertFalse(recorder.isRecording)
        recorder.append(frame)
        XCTAssertFalse(recorder.isRecording)
    }
}
