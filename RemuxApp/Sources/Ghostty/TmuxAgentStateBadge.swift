import SwiftUI

/// Colors mirror the user's tmux status bar (Tokyo Night): red for blocked,
/// amber for working.
enum TmuxAgentStatePalette {
    static let blocked = Color(red: 0xF7 / 255, green: 0x76 / 255, blue: 0x8E / 255)
    static let working = Color(red: 0xE0 / 255, green: 0xAF / 255, blue: 0x68 / 255)
    static let unseen = TerminalSelectionSheetPalette.secondary
}

/// The pane-mark badge shared by the pane topology cards and the session
/// switcher rows: `!` when blocked, `⚡` when working, a dot when unseen.
/// Renders nothing for idle panes.
struct TmuxAgentStateBadge: View {
    let state: TmuxPaneAgentState
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
            Circle()
                .fill(TmuxAgentStatePalette.unseen)
                .frame(width: 6, height: 6)
        case .idle:
            EmptyView()
        }
    }

    static func accessibilityLabel(for state: TmuxPaneAgentState) -> String? {
        switch state {
        case .blocked:
            "agent blocked"
        case .working:
            "agent working"
        case .unseen:
            "unseen update"
        case .idle:
            nil
        }
    }
}
