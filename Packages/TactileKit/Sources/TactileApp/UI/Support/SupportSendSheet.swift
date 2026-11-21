// The "what will be sent" sheet: every file of the report with its size and Open, which shows its
// exact content read only; then, where sending is on, the email, the note and the privacy sentence,
// and Send; always Save Report…; and, where the report goes to GitHub instead, a plain word that
// GitHub issues are public and the button that opens a touchscreen report there.
//
// It is no larger than the check window's content (`SupportSheetFit`), whatever the window's size:
// its title stays at the top and its buttons at the bottom, and what lies between scrolls when it
// doesn't fit, the file list giving up height first.

import AppKit
import SwiftUI
import TactileSupport

struct SupportSendSheet: View {
    @Bindable var session: SupportCheckSession
    /// The check window's content: the sheet is no larger, less a margin.
    var room: CGSize
    @Environment(\.dismiss) private var dismiss
    @State private var viewing: Viewing?

    /// The file Open shows.
    struct Viewing: Identifiable {
        let file: SupportFile
        var id: String { file.name }
    }

    /// Left clear at the sides of what scrolls, inside it, so a text field's focus ring isn't cut.
    private static let ringRoom: CGFloat = 4

    var body: some View {
        let content = SupportSendSheetContent(stage: session.sendStage, form: session.form, saved: session.savedAs != nil)
        let size = SupportSheetFit.sheet(in: room)
        VStack(alignment: .leading, spacing: 14) {
            Text(Wording.sendSheetTitle)
                .font(.title3.weight(.semibold))
                .supportPart(.title)
            GeometryReader { middle in
                ScrollView(.vertical) {
                    SupportSheetColumn(height: middle.size.height, spacing: 14) {
                        Text(Wording.sendSheetIntro)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        files
                            .layoutValue(key: SupportSheetColumn.Shrinks.self, value: true)
                        if content.showsForm {
                            form(enabled: content.formIsEnabled)
                        }
                        if let message = content.message {
                            Text(message)
                                .foregroundStyle(session.sendStage == .sent ? .primary : .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let saved = session.savedAs {
                            Label(Wording.reportSaved(saved), systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if session.saveFailed {
                            Label(Wording.saveFailed, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        if content.showsGitHub {
                            gitHub
                        }
                    }
                    .padding(.horizontal, Self.ringRoom)
                }
                .padding(.horizontal, -Self.ringRoom)
            }
            buttons(content)
                .supportPart(.buttons)
        }
        .padding(22)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $viewing) { viewing in
            SupportFileViewer(file: viewing.file, room: size)
        }
    }

    @ViewBuilder
    private var files: some View {
        if let archive = session.archive {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(archive.files, id: \.name) { file in
                        SupportFileRow(file: file) { viewing = Viewing(file: file) }
                    }
                }
            }
            .frame(minHeight: SupportSheetFit.fileListMinimum, idealHeight: SupportSheetFit.fileListHeight,
                   maxHeight: SupportSheetFit.fileListHeight)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
            .supportPart(.files)
        } else if let failure = session.archiveFailure {
            Label(Wording.reportFailed(failure), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(Wording.makingReport).foregroundStyle(.secondary)
            }
            .frame(minHeight: SupportSheetFit.fileListMinimum, idealHeight: SupportSheetFit.fileListHeight,
                   maxHeight: SupportSheetFit.fileListHeight)
        }
    }

    private func form(enabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Wording.emailLabel)
            TextField(Wording.emailLabel, text: $session.form.email, prompt: Text(Wording.emailPrompt))
                .textContentType(.emailAddress)
                .labelsHidden()
            if let problem = session.form.emailProblem {
                Text(problem).font(.caption).foregroundStyle(.orange)
            }
            Text(Wording.noteLabel)
                .padding(.top, 4)
            TextField(Wording.noteLabel, text: $session.form.note, prompt: Text(Wording.notePrompt), axis: .vertical)
                .lineLimit(2...4)
                .labelsHidden()
            HStack {
                if let problem = session.form.noteProblem {
                    Text(problem).foregroundStyle(.orange)
                }
                Spacer()
                Text(session.form.noteCount).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.caption)
            Text(Wording.supportPrivacy)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textFieldStyle(.roundedBorder)
        .disabled(!enabled)
    }

    private var gitHub: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Wording.githubIsPublic)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Button(Wording.openGitHubReport) { session.openGitHub() }
                .disabled(session.savedAs == nil)
        }
    }

    private func buttons(_ content: SupportSendSheetContent) -> some View {
        HStack {
            if content.showsSaveReport {
                Button(Wording.saveReport) { session.save() }
                    .disabled(session.archive == nil)
            }
            Spacer()
            if content.stopsSending {
                Button(Wording.stopSending) { session.cancelSending() }
                    .keyboardShortcut(.cancelAction)
            } else {
                Button(session.sendStage == .sent ? Wording.supportDone : content.showsForm ? Wording.cancel : Wording.close) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            if content.showsSend {
                Button(Wording.send) { session.send() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!content.sendEnabled || session.archive == nil)
            }
        }
    }
}

/// One row of the file list: the file's name and size, and Open.
struct SupportFileRow: View {
    let file: SupportFile
    let open: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(file.name)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                Spacer()
                Text(Wording.fileSize(file.size))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button(Wording.openFile, action: open)
                    .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            Divider()
        }
    }
}

/// One file of the report, exactly as it goes, read only. A sheet on the sheet, no larger than it
/// (`SupportSheetFit`): its file's name at the top, Close at the bottom, the text scrolling between.
struct SupportFileViewer: View {
    let file: SupportFile
    /// The sheet it is shown on.
    var room: CGSize
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let size = SupportSheetFit.viewer(on: room)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(file.name)
                    .font(.system(.headline, design: .monospaced))
                Spacer()
                Text(Wording.fileSize(file.size)).foregroundStyle(.secondary)
            }
            .supportPart(.title)
            ReadOnlyText(text: file.text)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            HStack {
                Spacer()
                Button(Wording.close) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .supportPart(.buttons)
        }
        .padding(18)
        .frame(width: size.width, height: size.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// The sheet's middle, top to bottom and `spacing` apart: each part as tall as it needs, but the one
/// marked `Shrinks` (the file list), which takes what is left of `height` within its own least and
/// most. When even its least leaves the column taller than `height`, the scroll view it is in scrolls.
/// A `VStack` can't do this there: inside a scroll view it is offered no height to share out.
struct SupportSheetColumn: Layout {
    /// The height to fill: the scroll view's.
    var height: CGFloat
    var spacing: CGFloat

    /// Marks the part that gives up height.
    struct Shrinks: LayoutValueKey {
        static let defaultValue = false
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? SupportSheetFit.idealSheet.width
        return CGSize(width: width, height: heights(width: width, subviews: subviews).reduce(gaps(subviews), +))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for (subview, height) in zip(subviews, heights(width: bounds.width, subviews: subviews)) {
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: height))
            y += height + spacing
        }
    }

    private func gaps(_ subviews: Subviews) -> CGFloat {
        spacing * CGFloat(max(0, subviews.count - 1))
    }

    /// Each part's height at `width`: its own, but the shrinking one's, which shares out what is left.
    private func heights(width: CGFloat, subviews: Subviews) -> [CGFloat] {
        let own = subviews.map { $0[Shrinks.self] ? nil : $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        let shrinking = CGFloat(max(1, own.filter { $0 == nil }.count))
        let left = max(0, height - own.compactMap { $0 }.reduce(gaps(subviews), +)) / shrinking
        return zip(subviews, own).map { subview, own in
            own ?? subview.sizeThatFits(ProposedViewSize(width: width, height: left)).height
        }
    }
}

/// The parts of the check's window, its sheet and the file viewer that must always show: the title
/// at the top and the row of buttons at the bottom; and the sheet's file list, which may shrink only
/// so far. Their bounds go up as a preference, for the tests that hold them inside what shows them.
enum SupportPart: Hashable {
    case title, files, buttons
}

struct SupportParts: PreferenceKey {
    static let defaultValue: [SupportPart: Anchor<CGRect>] = [:]

    static func reduce(value: inout [SupportPart: Anchor<CGRect>], nextValue: () -> [SupportPart: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, next in next }
    }
}

extension View {
    func supportPart(_ part: SupportPart) -> some View {
        anchorPreference(key: SupportParts.self, value: .bounds) { [part: $0] }
    }
}

/// A read-only text view that copes with a long file: AppKit's, scrolling, selectable, monospaced.
struct ReadOnlyText: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        if let view = scroll.documentView as? NSTextView {
            view.isEditable = false
            view.isSelectable = true
            view.isRichText = false
            view.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            view.textContainerInset = NSSize(width: 6, height: 6)
            view.string = text
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        if let view = scroll.documentView as? NSTextView, view.string != text { view.string = text }
    }
}
