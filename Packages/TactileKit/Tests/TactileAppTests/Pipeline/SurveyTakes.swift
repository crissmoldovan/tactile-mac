// The survey's takes as the device layer would hand them up: frames of contacts at glass points.
//
// The real device layer (`TouchscreenReader`) is another stream's; until it is joined, these read
// the recordings with `TactileReading` directly, as it does. Survey A's wch.cn strip, takes 1–20,
// only ever sent mouse reports and is read as one finger; survey B's ILITEK, takes 1–15, sent touch
// reports. Take numbers and what each is: each take's `title` and `prompt` in the recordings
// (`Fixtures/surveys`).

import CoreGraphics
import Foundation
import TactileReading
import TactileTestSupport

enum SurveyTakes {
    struct Missing: Error, CustomStringConvertible {
        let description: String
    }

    static let ilitekTakes = 1...15
    static let stripTakes = 1...20

    /// Survey B's ILITEK take `number`, from its touchscreen interface.
    static func ilitek(take number: Int) throws -> [ContactFrame] {
        guard let ilitek = SurveyFixtures.surveyB.touchscreen(vendorID: 0x222a, productID: 0x0001),
              let interface = ilitek.interfaces.first(where: { $0.key == "touchscreen" }),
              let decoder = InterfaceDecoder(descriptor: interface.descriptor),
              let take = ilitek.takes.first(where: { $0.number == number })
        else { throw Missing(description: "no ILITEK take \(number)") }
        var builder = TouchFrameBuilder()
        var frames: [ContactFrame] = []
        for report in take.reports where report.interfaceKey == "touchscreen" {
            guard case .touch(let touch)? = decoder.decode(report.bytes) else {
                throw Missing(description: "ILITEK take \(number): a report that isn't a touch report")
            }
            if let frame = builder.add(touch, at: report.hostTime) { frames.append(frame) }
        }
        return frames
    }

    /// Survey A's wch.cn take `number`, from its mouse interface, read as one finger with the
    /// device layer's 50 ms guard.
    static func strip(take number: Int) throws -> [ContactFrame] {
        guard let strip = SurveyFixtures.surveyA.touchscreen(vendorID: 0x27c0, productID: 0x0859),
              let interface = strip.interfaces.first(where: { $0.key == "mouse" }),
              let decoder = InterfaceDecoder(descriptor: interface.descriptor),
              let take = strip.takes.first(where: { $0.number == number })
        else { throw Missing(description: "no strip take \(number)") }
        var reader = PointerFingerReader(guardInterval: 0.05)
        var frames: [ContactFrame] = []
        for report in take.reports where report.interfaceKey == "mouse" {
            guard case .pointer(let pointer)? = decoder.decode(report.bytes) else {
                throw Missing(description: "strip take \(number): a report that isn't a pointer report")
            }
            if let frame = reader.add(pointer, at: report.hostTime) { frames.append(frame) }
        }
        return frames
    }
}

/// A frame of contacts at glass points: `(id, x, y)`.
func glassFrame(_ time: TimeInterval, _ fingers: (Int, CGFloat, CGFloat)...) -> ContactFrame {
    ContactFrame(time: time, contacts: fingers.map { Contact(id: $0.0, position: CGPoint(x: $0.1, y: $0.2)) })
}

/// A seeded generator, so a "random" test fails the same way every time.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
