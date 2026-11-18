import Darwin
import Foundation
import TactileGestures

/// Appends every frame to a JSON Lines file, so real sessions can become test fixtures.
/// Turn it on with `defaults write com.crissmoldovan.tactile recordFrames -bool YES`.
public final class FrameRecorder {
    public let url: URL
    /// True until a write fails. After that the recorder drops every frame, for good.
    public private(set) var isRecording = true
    private let handle: FileHandle
    private let encoder = JSONEncoder()

    /// Records to a file that is already open. Tests use it to hand the recorder a handle that fails.
    init(url: URL, handle: FileHandle) {
        self.url = url
        self.handle = handle
    }

    /// Creates a new file and records to it. Never shares or overwrites a file: when the name is
    /// taken, it adds `-2`, `-3` and so on before the extension.
    /// - Parameters:
    ///   - label: names the touchscreen. The file name starts with it, every character other than
    ///     `A–Z a–z 0–9` replaced by `-`, so each touchscreen records to its own file.
    public convenience init?(directory: URL, label: String, now: Date = Date()) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let safeLabel = String(label.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
        let name = "\(safeLabel)-frames-\(formatter.string(from: now))"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        for number in 1... {
            let url = directory.appendingPathComponent(number == 1 ? "\(name).jsonl" : "\(name)-\(number).jsonl")
            // O_EXCL: fails with EEXIST instead of opening a file that is already there.
            let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644)
            if descriptor >= 0 {
                self.init(url: url, handle: FileHandle(fileDescriptor: descriptor, closeOnDealloc: true))
                return
            }
            guard errno == EEXIST else { return nil }
        }
        return nil
    }

    /// A recorder writing the touchscreen named `label` to `~/Library/Logs/Tactile` when the
    /// `recordFrames` default is on; otherwise nil.
    public static func fromDefaults(_ defaults: UserDefaults = .standard, label: String) -> FrameRecorder? {
        guard defaults.bool(forKey: "recordFrames") else { return nil }
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return FrameRecorder(directory: library.appendingPathComponent("Logs/Tactile"), label: label)
    }

    /// Writes the frame as one line. A write that fails, such as on a full disk, drops the frame
    /// and stops the recorder for good; `isRecording` turns false.
    public func append(_ frame: TouchFrame) {
        guard isRecording, var line = try? encoder.encode(frame) else { return }
        line.append(UInt8(ascii: "\n"))
        do {
            // The throwing write: the older `write(_:)` raises an exception Swift can't catch.
            try handle.write(contentsOf: line)
        } catch {
            isRecording = false
        }
    }
}
