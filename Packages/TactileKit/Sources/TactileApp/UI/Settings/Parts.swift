// Small pieces the panes share.

import AppKit
import SwiftUI

/// How a view asks the model for something. Every control sends an `AppCommand`; none keeps a copy
/// of a setting.
typealias PerformCommand = @MainActor (AppCommand) -> Void

/// The coloured dot of a touchscreen's state.
struct StatusDot: View {
    var indicator: StatusIndicator

    var body: some View {
        Group {
            if indicator == .inactive {
                Circle().strokeBorder(Color.secondary, lineWidth: 1.5)
            } else {
                Circle().fill(color)
            }
        }
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
    }

    private var color: Color {
        switch indicator {
        case .working: return .green
        case .needsSetUp: return .orange
        case .waiting: return .gray
        case .problem: return .red
        case .settingUp: return .accentColor
        case .inactive: return .clear
        }
    }
}

/// The tile at the head of a touchscreen's pane: Tactile's glyph, in colour while it is in use.
struct TouchscreenTile: View {
    var isActive: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isActive ? Color.accentColor.gradient : Color.gray.gradient)
            .frame(width: 42, height: 42)
            .overlay(TouchGlyphView(color: .white).frame(width: 26, height: 26))
            .shadow(color: .black.opacity(0.18), radius: 0.75, y: 0.5)
            .accessibilityHidden(true)
    }
}

/// A label with a quieter line beneath it, as System Settings draws a setting and its explanation.
struct ExplainedLabel: View {
    var title: String
    var explanation: String?
    /// Greyed, for a control that can't be used.
    var isDimmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundStyle(isDimmed ? .tertiary : .primary)
            if let explanation {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(isDimmed ? .quaternary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Why a button beside it can't be used now: a quiet line, with the button's help saying the same.
/// Nothing for a touchscreen that can't be told apart: its note, just above, says why.
struct UnavailableReason: View {
    var reason: SetUpAvailability.Reason

    var body: some View {
        if reason != .cannotBeToldApart {
            Text(Wording.setUpUnavailable(reason))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A footnote under a group.
struct Footnote: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
