// The "what will be sent" sheet: every file of the report with its size and Open, which shows its
// exact content read only; then, where sending is on, the email, the note and the privacy sentence,
// and Send; always Save Report…; and, where the report goes to GitHub instead, a plain word that
// GitHub issues are public and the button that opens a touchscreen report there.

import AppKit
import SwiftUI
import TactileSupport

struct SupportSendSheet: View {
    static let size = CGSize(width: 580, height: 720)

    @Bindable var session: SupportCheckSession
    @Environment(\.dismiss) private var dismiss
    @State private var viewing: Viewing?

    /// The file Open shows.
    struct Viewing: Identifiable {
        let file: SupportFile
        var id: String { file.name }
    }

    var body: some View {
        let content = SupportSendSheetContent(stage: session.sendStage, form: session.form, saved: session.savedAs != nil)
        VStack(alignment: .leading, spacing: 14) {
            Text(Wording.sendSheetTitle)
                .font(.title3.weight(.semibold))
            Text(Wording.sendSheetIntro)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            files
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
            Spacer(minLength: 0)
            buttons(content)
        }
        .padding(22)
        .frame(width: SupportSendSheet.size.width, height: SupportSendSheet.size.height, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $viewing) { viewing in
            SupportFileViewer(file: viewing.file)
        }
    }

    @ViewBuilder
    private var files: some View {
        if let archive = session.archive {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(archive.files, id: \.name) { file in
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
                            Button(Wording.openFile) { viewing = Viewing(file: file) }
                                .controlSize(.small)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        Divider()
                    }
                }
            }
            .frame(height: 285)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
        } else if let failure = session.archiveFailure {
            Label(Wording.reportFailed(failure), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(Wording.makingReport).foregroundStyle(.secondary)
            }
            .frame(height: 285)
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
            Button(session.sendStage == .sent ? Wording.supportDone : content.showsForm ? Wording.cancel : Wording.close) { dismiss() }
                .keyboardShortcut(.cancelAction)
            if content.showsSend {
                Button(Wording.send) { session.send() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!content.sendEnabled || session.archive == nil)
            }
        }
    }
}

/// One file of the report, exactly as it goes, read only.
struct SupportFileViewer: View {
    let file: SupportFile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(file.name)
                    .font(.system(.headline, design: .monospaced))
                Spacer()
                Text(Wording.fileSize(file.size)).foregroundStyle(.secondary)
            }
            ReadOnlyText(text: file.text)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            HStack {
                Spacer()
                Button(Wording.close) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 640, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
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
