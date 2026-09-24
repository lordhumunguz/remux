import SwiftUI

/// Colors mirror the user's tmux status bar (Tokyo Night): red for blocked,
/// amber for working.
enum TmuxAgentStatePalette {
    static let blocked = Color(red: 0xF7 / 255, green: 0x76 / 255, blue: 0x8E / 255)
    static let working = Color(red: 0xE0 / 255, green: 0xAF / 255, blue: 0x68 / 255)
    static let done = Color(red: 0x9E / 255, green: 0xCE / 255, blue: 0x6A / 255)
    static let unseen = TerminalSelectionSheetPalette.secondary
}

/// The pane-mark badge shared by the pane topology cards and the session
/// switcher rows: `!` when blocked, `⚡` when working, `✓` when finished,
/// or a dot when unseen. Renders nothing for idle non-agent panes.
struct TmuxAgentStateBadge: View {
    let state: TmuxPaneAgentState
    var isDone: Bool = false
    var font: Font = .system(size: 12, weight: .bold)

    var body: some View {
        switch state {
        case .blocked:
            Text("!")
                .font(font)
                .foregroundStyle(TmuxAgentStatePalette.blocked)
        case .working:
            Text("⚡")
                .font(font)
                .foregroundStyle(TmuxAgentStatePalette.working)
        case .unseen:
            if isDone {
                Text("✓")
                    .font(font)
                    .foregroundStyle(TmuxAgentStatePalette.done)
            } else {
                Circle()
                    .fill(TmuxAgentStatePalette.unseen)
                    .frame(width: 6, height: 6)
            }
        case .idle:
            if isDone {
                Text("✓")
                    .font(font)
                    .foregroundStyle(TmuxAgentStatePalette.done)
            } else {
                EmptyView()
            }
        }
    }

    static func accessibilityLabel(for state: TmuxPaneAgentState, isDone: Bool = false) -> String? {
        switch state {
        case .blocked:
            "agent blocked"
        case .working:
            "agent working"
        case .unseen:
            isDone ? "agent finished" : "unseen update"
        case .idle:
            isDone ? "agent finished" : nil
        }
    }
}

/// Quota percent pill (e.g. `W36%`), colored amber at >=75% and bold red at >=90%.
struct TmuxAgentQuotaPill: View {
    let percent: Int
    var font: Font? = nil

    var body: some View {
        Text("W\(percent)%")
            .font(font ?? .system(size: 10, weight: percent >= 90 ? .bold : .medium, design: .monospaced))
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(backgroundColor, in: Capsule())
            .accessibilityLabel("weekly quota \(percent) percent")
    }

    var foregroundColor: Color {
        if percent >= 90 {
            return TmuxAgentStatePalette.blocked
        } else if percent >= 75 {
            return TmuxAgentStatePalette.working
        } else {
            return TerminalSelectionSheetPalette.secondary
        }
    }

    var backgroundColor: Color {
        if percent >= 90 {
            return TmuxAgentStatePalette.blocked.opacity(0.18)
        } else if percent >= 75 {
            return TmuxAgentStatePalette.working.opacity(0.18)
        } else {
            return TerminalSelectionSheetPalette.row.opacity(0.6)
        }
    }
}

/// Renders the agent identity glyph, Byron profile name (or compact profile tag),
/// quota percent pill, and optional completion recency pill.
struct TmuxAgentProfilePillView: View {
    let resolution: AgentResolution
    var quotaPercent: Int? = nil
    var doneRelativeText: String? = nil
    var prefersCompactProfile: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Text(resolution.identity.glyph)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(resolution.identity.accent)
                .accessibilityHidden(true)

            Text(prefersCompactProfile ? resolution.compactLabel : resolution.byronProfileName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TerminalSelectionSheetPalette.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            if let quotaPercent {
                TmuxAgentQuotaPill(percent: quotaPercent)
                    .fixedSize()
            }

            if let doneRelativeText {
                Text("✓ \(doneRelativeText)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(TmuxAgentStatePalette.done)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(TmuxAgentStatePalette.done.opacity(0.18), in: Capsule())
                    .accessibilityLabel("finished \(doneRelativeText)")
            }
        }
    }
}
