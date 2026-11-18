// Terminal input and output, and the safety net that puts every touchscreen back as it was
// found on every way out: normal end, errors, exit(), Ctrl-C, SIGTERM and a closed terminal.

import Foundation

/// Prints at once, even when stdout is a pipe.
func say(_ text: String = "", terminator: String = "\n") {
    FileHandle.standardOutput.write((text + terminator).data(using: .utf8) ?? Data())
}

func warn(_ text: String) {
    FileHandle.standardError.write((text + "\n").data(using: .utf8) ?? Data())
}

/// Monotonic time in nanoseconds, on the same clock as HID report timestamps.
enum Clock {
    static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func ns(fromMach mach: UInt64) -> UInt64 {
        mach / UInt64(timebase.denom) * UInt64(timebase.numer)
            + (mach % UInt64(timebase.denom)) * UInt64(timebase.numer) / UInt64(timebase.denom)
    }

    static func now() -> UInt64 { ns(fromMach: mach_absolute_time()) }

    static func seconds(_ from: UInt64, _ to: UInt64) -> Double { to >= from ? Double(to - from) / 1e9 : -Double(from - to) / 1e9 }
}

/// Lets the main run loop keep running (so HID reports, signals and the windows on the glass are
/// handled) while waiting for the person to press Enter.
final class LineReader {
    private var buffer: [UInt8] = []
    private(set) var reachedEnd = false
    let isTerminal = isatty(0) != 0

    /// Drops anything typed while a take was running, so a stray Enter does not answer the next
    /// question. Only for a real terminal: piped input is a script and must be kept.
    func discardTypedAhead() {
        guard isTerminal else { return }
        tcflush(0, TCIFLUSH)
        buffer.removeAll()
    }

    /// The next line without its newline, or nil once input has ended.
    func readLine() -> String? {
        while true {
            if let newline = buffer.firstIndex(of: 10) {
                let line = Array(buffer[..<newline])
                buffer.removeSubrange(...newline)
                return String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if reachedEnd {
                if buffer.isEmpty { return nil }
                let line = String(decoding: buffer, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                buffer.removeAll()
                return line
            }
            var pfd = pollfd(fd: 0, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, 0)
            if ready > 0 {
                var chunk = [UInt8](repeating: 0, count: 4096)
                let n = read(0, &chunk, chunk.count)
                if n > 0 { buffer += chunk[0..<n] } else if n == 0 || errno != EINTR { reachedEnd = true }
                continue
            }
            if ready < 0, errno != EINTR { reachedEnd = true; continue }
            pumpEvents(0.05)
        }
    }
}

/// One place that knows how to put everything back. `cleanup` must be safe to call twice.
final class Safety {
    static let shared = Safety()

    var cleanup: (() -> Void)?
    var onSignal: ((Int32) -> Void)?
    private var sources: [DispatchSourceSignal] = []
    private var handlingSignal = false

    func install() {
        signal(SIGPIPE, SIG_IGN)
        // Ctrl-Z would freeze the run with the touchscreen held and the windows up.
        signal(SIGTSTP, SIG_IGN)
        for sig in [SIGINT, SIGTERM, SIGHUP, SIGQUIT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { Safety.shared.handle(sig) }
            source.resume()
            sources.append(source)
        }
        atexit { Safety.shared.runCleanup() }
    }

    func runCleanup() {
        let work = cleanup
        cleanup = nil
        work?()
    }

    private func handle(_ sig: Int32) {
        guard !handlingSignal else { return }
        handlingSignal = true
        say("")
        say("Stopping (signal \(sig)). Putting the touchscreens back as they were found...")
        if let onSignal { onSignal(sig) } else { runCleanup() }
        exit(128 + sig)
    }
}
