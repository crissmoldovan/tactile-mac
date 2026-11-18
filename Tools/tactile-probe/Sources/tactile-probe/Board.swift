// What the windows on the glass say, and where each line goes. The content is plain values; the
// layout measures text with AppKit but needs no window, so both are tested without showing anything.
// BoardWindows.swift puts them on the displays.

import AppKit

// MARK: - Content

enum BoardPhase: Equatable {
    /// Before the first take: press Enter to start.
    case getReady
    case waiting(secondsLeft: Int, fraction: Double)
    case recording(seconds: Double)
    case result(GlassVerdict, isLast: Bool)
    case finished
}

enum BoardTone: Equatable { case neutral, waiting, recording, good, bad }

/// The window on the display being surveyed.
struct InstructionScreen: Equatable {
    var cue: String
    var heading: String
    var body: String
    var note: String?
    var statusLine: String
    var tone: BoardTone
    /// Fraction of the wait left, 1…0, while waiting for the first touch.
    var bar: Double?
    var keys: String?
    var warning: String?
    var footer: String
    /// A frame round the whole display, when this display is known to be the one.
    var framed: Bool

    var allText: String { [cue, heading, body, note, statusLine, keys, warning, footer].compactMap { $0 }.joined(separator: "\n") }
}

func instructionScreen(take: TakeSpec, position: Int, of count: Int, phase: BoardPhase, knowsDisplay: Bool,
                       touchscreenName: String, warning: String?) -> InstructionScreen {
    var screen = InstructionScreen(
        cue: knowsDisplay ? "TOUCH THIS SCREEN" : "Use the \(touchscreenName) touchscreen",
        heading: "Take \(take.number) of \(Takes.count) · \(take.title)",
        body: take.prompt, note: take.note, statusLine: "", tone: .neutral, bar: nil, keys: nil, warning: warning,
        footer: "\(position) of \(count) in this run   ·   \(touchscreenName)   ·   type in the terminal: these windows never take the keyboard",
        framed: knowsDisplay)
    switch phase {
    case .getReady:
        // Touches do nothing yet: the screen is marked by its frame, and asks for Enter.
        screen.cue = "GET READY"
        screen.heading = "First: take \(take.number) of \(Takes.count) · \(take.title)"
        screen.statusLine = "Press Enter in the terminal to start"
    case .waiting(let secondsLeft, let fraction):
        screen.statusLine = "Waiting for your touch · \(secondsLeft) s"
        screen.tone = .waiting
        screen.bar = min(max(fraction, 0), 1)
    case .recording(let seconds):
        screen.statusLine = String(format: "Recording · %.1f s · lift when you have finished", seconds)
        screen.tone = .recording
    case .result(let verdict, let isLast):
        screen.statusLine = verdict.text
        screen.tone = verdict.good ? .good : .bad
        screen.keys = isLast ? "Enter: finish   ·   R: do it again" : "Enter: next take   ·   R: do it again   ·   S: stop here"
    case .finished:
        screen.cue = "ALL DONE"
        screen.heading = "The survey is saved"
        screen.body = "What was recorded is saved, and the touchscreen is back as it was found. These windows close by themselves."
        screen.note = nil
        screen.statusLine = "All done. Thank you."
        screen.tone = .good
        screen.warning = nil
    }
    return screen
}

/// The window on every other external display.
struct NotThisOneScreen: Equatable {
    var targetName: String?
    var title: String { "Not this one" }
    /// The target has its green frame from before the first take, while its cue still says GET READY.
    var detail: String {
        targetName.map { "Touch only \($0): the screen with the green frame." } ?? "Touch only the screen with the green frame."
    }
    var allText: String { title + "\n" + detail }
}

enum BoardContent: Equatable {
    case instruction(InstructionScreen)
    case notThisOne(NotThisOneScreen)
    /// While the survey asks which display the touchscreen is on: each display's number in the list.
    case number(Int, name: String)
}

/// What every display shows, for one instruction screen. Every window catches the clicks that
/// land on it: a touchscreen that is not held (the other one, or this one before its held takes)
/// clicks, and a click on the desktop would make Finder the active app and take the keyboard
/// from the terminal. The Mac's own display has no window, so the terminal there stays clickable.
func boardWindows(plan: BoardPlan, instruction: InstructionScreen) -> (contents: [UInt32: BoardContent], catchingClicks: Set<UInt32>) {
    var contents: [UInt32: BoardContent] = [:]
    for d in plan.instructionDisplays { contents[d.displayID] = .instruction(instruction) }
    for d in plan.notThisOneDisplays { contents[d.displayID] = .notThisOne(NotThisOneScreen(targetName: plan.target?.name)) }
    return (contents, Set(contents.keys))
}

// MARK: - Colours and type

enum BoardStyle {
    static let background = NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.09, alpha: 1)
    static let cue = NSColor(calibratedRed: 0.30, green: 0.90, blue: 0.45, alpha: 1)
    static let frame = cue
    static let text = NSColor(calibratedWhite: 0.97, alpha: 1)
    static let quiet = NSColor(calibratedWhite: 0.68, alpha: 1)
    static let waiting = NSColor(calibratedRed: 1.00, green: 0.78, blue: 0.25, alpha: 1)
    static let recording = NSColor(calibratedRed: 0.45, green: 0.75, blue: 1.00, alpha: 1)
    static let bad = NSColor(calibratedRed: 1.00, green: 0.42, blue: 0.40, alpha: 1)
    static let warningBand = NSColor(calibratedRed: 0.70, green: 0.10, blue: 0.10, alpha: 1)
    static let barTrack = NSColor(calibratedWhite: 1, alpha: 0.15)
    static let veil = NSColor(calibratedWhite: 0, alpha: 0.45)
    static let plate = NSColor(calibratedRed: 0.45, green: 0.06, blue: 0.06, alpha: 0.96)

    static func colour(_ tone: BoardTone) -> NSColor {
        switch tone {
        case .neutral: return text
        case .waiting: return waiting
        case .recording: return recording
        case .good: return cue
        case .bad: return bad
        }
    }
}

enum BlockRole: String { case cue, heading, body, note, warning, status, keys, footer, title, detail, number, name }

struct LaidOutBlock {
    let role: BlockRole
    let text: NSAttributedString
    let frame: CGRect
    let fontSize: CGFloat
    /// A band drawn behind the text, edge to edge of the content.
    let band: CGRect?
}

private func attributed(_ text: String, size: CGFloat, weight: NSFont.Weight, colour: NSColor,
                        alignment: NSTextAlignment = .left) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.lineHeightMultiple = 1.05
    return NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: colour, .paragraphStyle: paragraph,
    ])
}

private func measure(_ text: NSAttributedString, width: CGFloat) -> CGSize {
    let r = text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                              options: [.usesLineFragmentOrigin, .usesFontLeading])
    return CGSize(width: ceil(r.width), height: ceil(r.height))
}

/// One block before it is placed: its text, measured at the width it may use.
private struct Measured {
    let role: BlockRole
    let text: NSAttributedString
    let size: CGSize
    let fontSize: CGFloat
    let gapAfter: CGFloat
    let singleLine: Bool
    var banded: Bool = false
}

// MARK: - The instruction

/// Every line of an instruction screen, placed for one display. The take's own words sit at the
/// top; the status, the countdown and the keys at the bottom, so they don't move as the take's
/// text changes. Type is as large as fits: it shrinks, all together, until everything does.
struct InstructionLayout {
    /// The smallest body type, in points, the layout shrinks to before it reports that it does not fit.
    static let smallestUnit: CGFloat = 12

    let blocks: [LaidOutBlock]
    /// The countdown: the whole track, and the part still left.
    let bar: (track: CGRect, filled: CGRect)?
    let border: CGRect?
    let borderWidth: CGFloat
    let fits: Bool
    let bodyFontSize: CGFloat

    init(_ screen: InstructionScreen, size: CGSize) {
        let side = min(size.width, size.height)
        let borderWidth = screen.framed ? max(6, (side * 0.014).rounded()) : 0
        let inset = max(20, side * 0.05) + borderWidth
        let width = max(1, size.width - 2 * inset)
        let height = max(1, size.height - 2 * inset)

        func build(_ u: CGFloat) -> (top: [Measured], bottom: [Measured], barHeight: CGFloat) {
            func block(_ role: BlockRole, _ text: String, _ scale: CGFloat, _ weight: NSFont.Weight, _ colour: NSColor,
                       gap: CGFloat, single: Bool = false, alignment: NSTextAlignment = .left) -> Measured {
                let s = attributed(text, size: (u * scale).rounded(.down), weight: weight, colour: colour, alignment: alignment)
                let measured = single ? s.size() : measure(s, width: width)
                return Measured(role: role, text: s, size: CGSize(width: ceil(measured.width), height: ceil(measured.height)),
                                fontSize: (u * scale).rounded(.down), gapAfter: u * gap, singleLine: single)
            }
            var top = [
                block(.cue, screen.cue, 1.25, .heavy, BoardStyle.cue, gap: 0.45, single: true, alignment: .center),
                block(.heading, screen.heading, 0.8, .bold, BoardStyle.text, gap: 0.3),
                block(.body, screen.body, 1.0, .medium, BoardStyle.text, gap: 0.25),
            ]
            if let note = screen.note { top.append(block(.note, note, 0.6, .regular, BoardStyle.quiet, gap: 0)) }
            var bottom: [Measured] = []
            if let warning = screen.warning {
                var w = block(.warning, warning, 0.7, .bold, BoardStyle.text, gap: 0.35)
                w.banded = true
                bottom.append(w)
            }
            bottom.append(block(.status, screen.statusLine, 0.8, .semibold, BoardStyle.colour(screen.tone),
                                gap: screen.bar != nil ? 0.2 : 0.3))
            let barHeight = screen.bar != nil ? max(8, u * 0.22) : 0
            if let keys = screen.keys { bottom.append(block(.keys, keys, 0.6, .medium, BoardStyle.text, gap: 0.3)) }
            bottom.append(block(.footer, screen.footer, 0.4, .regular, BoardStyle.quiet, gap: 0))
            return (top, bottom, barHeight)
        }

        func total(_ blocks: [Measured]) -> CGFloat {
            blocks.reduce(0) { $0 + $1.size.height + $1.gapAfter }
        }

        var u = min(size.height / 8.5, size.width / 18, 110)
        var built = build(u)
        var fits = false
        while true {
            let barSpace = built.barHeight > 0 ? built.barHeight + u * 0.3 : 0
            let needed = total(built.top) + total(built.bottom) + barSpace + u * 0.5
            let lines = (built.top + built.bottom).allSatisfy { !$0.singleLine || $0.size.width <= width }
            if needed <= height && lines { fits = true; break }
            // Below this the words could no longer be read from where a person stands to touch.
            guard u * 0.95 >= InstructionLayout.smallestUnit else { break }
            u *= 0.95
            built = build(u)
        }

        var blocks: [LaidOutBlock] = []
        var y = inset
        for m in built.top {
            let x = m.singleLine ? inset + max(0, (width - m.size.width) / 2) : inset
            blocks.append(LaidOutBlock(role: m.role, text: m.text, frame: CGRect(x: x, y: y, width: min(m.size.width, width), height: m.size.height),
                                       fontSize: m.fontSize, band: nil))
            y += m.size.height + m.gapAfter
        }
        // The bottom group, top to bottom, ending at the bottom margin. The countdown bar sits
        // right under the status line.
        var bar: (CGRect, CGRect)?
        let barSpace = built.barHeight > 0 ? built.barHeight + u * 0.3 : 0
        var bottomY = size.height - inset - total(built.bottom) - barSpace
        for m in built.bottom {
            let frame = CGRect(x: inset, y: bottomY, width: min(m.size.width, width), height: m.size.height)
            let pad = m.fontSize * 0.25
            let band = m.banded
                ? CGRect(x: inset - pad, y: frame.minY - pad, width: width + 2 * pad, height: frame.height + 2 * pad)
                    .intersection(CGRect(origin: .zero, size: size))
                : nil
            blocks.append(LaidOutBlock(role: m.role, text: m.text, frame: frame, fontSize: m.fontSize, band: band))
            bottomY += m.size.height + m.gapAfter
            if m.role == .status, let fraction = screen.bar, built.barHeight > 0 {
                let track = CGRect(x: inset, y: bottomY, width: width, height: built.barHeight)
                bar = (track, CGRect(x: inset, y: bottomY, width: (width * CGFloat(fraction)).rounded(), height: built.barHeight))
                bottomY += built.barHeight + u * 0.3
            }
        }
        self.blocks = blocks
        self.bar = bar
        self.border = screen.framed ? CGRect(origin: .zero, size: size).insetBy(dx: borderWidth / 2, dy: borderWidth / 2) : nil
        self.borderWidth = borderWidth
        self.fits = fits && blocks.allSatisfy { CGRect(origin: .zero, size: size).contains($0.frame) }
            && (blocks.filter { [.cue, .heading, .body, .note].contains($0.role) }.map(\.frame.maxY).max() ?? 0)
                <= (blocks.filter { ![.cue, .heading, .body, .note].contains($0.role) }.map(\.frame.minY).min() ?? size.height)
        self.bodyFontSize = blocks.first { $0.role == .body }?.fontSize ?? 0
    }
}

// MARK: - Not this one

struct NotThisOneLayout {
    let plate: CGRect
    let blocks: [LaidOutBlock]
    let fits: Bool

    init(_ screen: NotThisOneScreen, size: CGSize) {
        let side = min(size.width, size.height)
        let maxWidth = size.width * 0.8
        var u = min(size.height / 5, size.width / 12, 150)
        var title = attributed(screen.title, size: u, weight: .heavy, colour: BoardStyle.text, alignment: .center)
        var detail = attributed(screen.detail, size: u * 0.33, weight: .medium, colour: BoardStyle.text, alignment: .center)
        var fits = false
        while true {
            let t = title.size()
            let d = measure(detail, width: maxWidth - u)
            if t.width + u <= maxWidth, t.height + d.height + u * 1.4 <= size.height - 2 * max(20, side * 0.05) { fits = true; break }
            guard u * 0.95 >= 24 else { break }
            u *= 0.95
            title = attributed(screen.title, size: u, weight: .heavy, colour: BoardStyle.text, alignment: .center)
            detail = attributed(screen.detail, size: u * 0.33, weight: .medium, colour: BoardStyle.text, alignment: .center)
        }
        let t = title.size()
        let d = measure(detail, width: maxWidth - u)
        let plateSize = CGSize(width: min(maxWidth, max(t.width, d.width) + u), height: t.height + d.height + u * 0.9)
        let plate = CGRect(x: (size.width - plateSize.width) / 2, y: (size.height - plateSize.height) / 2,
                           width: plateSize.width, height: plateSize.height)
        let titleFrame = CGRect(x: plate.minX, y: plate.minY + u * 0.35, width: plate.width, height: ceil(t.height))
        let detailFrame = CGRect(x: plate.minX + u * 0.5, y: titleFrame.maxY + u * 0.15, width: plate.width - u, height: d.height)
        self.plate = plate
        self.blocks = [
            LaidOutBlock(role: .title, text: title, frame: titleFrame, fontSize: u, band: nil),
            LaidOutBlock(role: .detail, text: detail, frame: detailFrame, fontSize: u * 0.33, band: nil),
        ]
        self.fits = fits && CGRect(origin: .zero, size: size).contains(plate)
    }
}

// MARK: - A display's number

struct NumberLayout {
    let blocks: [LaidOutBlock]
    let fits: Bool

    init(number: Int, name: String, size: CGSize) {
        var big = min(size.height * 0.5, size.width * 0.3)
        var numberText = attributed("\(number)", size: big, weight: .heavy, colour: BoardStyle.text, alignment: .center)
        var nameText = attributed(name, size: big * 0.18, weight: .semibold, colour: BoardStyle.text, alignment: .center)
        var fits = false
        while true {
            let n = numberText.size()
            let m = nameText.size()
            if n.height + m.height <= size.height * 0.9, m.width <= size.width * 0.9, n.width <= size.width * 0.9 { fits = true; break }
            guard big * 0.95 >= 48 else { break }
            big *= 0.95
            numberText = attributed("\(number)", size: big, weight: .heavy, colour: BoardStyle.text, alignment: .center)
            nameText = attributed(name, size: big * 0.18, weight: .semibold, colour: BoardStyle.text, alignment: .center)
        }
        let n = numberText.size()
        let m = nameText.size()
        let top = (size.height - n.height - m.height) / 2
        blocks = [
            LaidOutBlock(role: .number, text: numberText, frame: CGRect(x: 0, y: top, width: size.width, height: ceil(n.height)),
                         fontSize: big, band: nil),
            LaidOutBlock(role: .name, text: nameText, frame: CGRect(x: 0, y: top + ceil(n.height), width: size.width, height: ceil(m.height)),
                         fontSize: big * 0.18, band: nil),
        ]
        self.fits = fits
    }
}

// MARK: - Drawing

/// Draws one display's content. Flipped, so layouts measure from the top.
final class BoardView: NSView {
    var content: BoardContent {
        didSet { if content != oldValue { needsDisplay = true } }
    }

    init(frame: CGRect, content: BoardContent) {
        self.content = content
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool {
        if case .instruction = content { return true }
        return false
    }

    /// Clicks that land here do nothing. Keys never come here: the window can't become key.
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}

    override func draw(_ dirtyRect: NSRect) {
        let size = bounds.size
        switch content {
        case .instruction(let screen):
            BoardStyle.background.setFill()
            bounds.fill()
            let layout = InstructionLayout(screen, size: size)
            if let border = layout.border {
                let path = NSBezierPath(rect: border)
                path.lineWidth = layout.borderWidth
                BoardStyle.frame.setStroke()
                path.stroke()
            }
            for block in layout.blocks {
                if let band = block.band {
                    BoardStyle.warningBand.setFill()
                    NSBezierPath(roundedRect: band, xRadius: block.fontSize * 0.2, yRadius: block.fontSize * 0.2).fill()
                }
                block.text.draw(with: block.frame, options: [.usesLineFragmentOrigin, .usesFontLeading])
            }
            if let bar = layout.bar {
                let radius = bar.track.height / 2
                BoardStyle.barTrack.setFill()
                NSBezierPath(roundedRect: bar.track, xRadius: radius, yRadius: radius).fill()
                BoardStyle.waiting.setFill()
                if bar.filled.width > 0 { NSBezierPath(roundedRect: bar.filled, xRadius: radius, yRadius: radius).fill() }
            }
        case .notThisOne(let screen):
            BoardStyle.veil.setFill()
            bounds.fill()
            let layout = NotThisOneLayout(screen, size: size)
            BoardStyle.plate.setFill()
            let radius = layout.blocks[0].fontSize * 0.2
            NSBezierPath(roundedRect: layout.plate, xRadius: radius, yRadius: radius).fill()
            for block in layout.blocks { block.text.draw(with: block.frame, options: [.usesLineFragmentOrigin, .usesFontLeading]) }
        case .number(let number, let name):
            NSColor(calibratedWhite: 0, alpha: 0.6).setFill()
            bounds.fill()
            for block in NumberLayout(number: number, name: name, size: size).blocks {
                block.text.draw(with: block.frame, options: [.usesLineFragmentOrigin, .usesFontLeading])
            }
        }
    }
}
