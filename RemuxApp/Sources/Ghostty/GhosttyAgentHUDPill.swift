import SwiftUI

/// Floating HUD pill in the terminal viewport. The top line is the project
/// and branch. The line under it is the agent. Tapping opens the pane index.
struct GhosttyAgentHUDPill: View {
    let resolution: AgentResolution?
    let agentInfo: TmuxPaneAgentInfo
    var placeText: String? = nil
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .trailing, spacing: 2) {
                if let placeText, !placeText.isEmpty {
                    Text(placeText)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(TerminalSelectionSheetPalette.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                if showsAgentRow {
                    HStack(spacing: 6) {
                        statusIcon
                        labelView
                        if let quota = agentInfo.quotaPercent {
                            TmuxAgentQuotaPill(percent: quota, font: .system(size: 9, weight: .bold, design: .monospaced))
                        }
                    }
                }
            }
            .frame(maxWidth: 260, alignment: .trailing)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(GhosttyPhoneChromePalette.dock.opacity(0.92))
                    .overlay {
                        Capsule().strokeBorder(borderColor, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("terminal.agent-hud")
        .accessibilityLabel(accessibilityLabel)
    }

    private var showsAgentRow: Bool {
        agentInfo.isBlocked
            || agentInfo.isWorking
            || agentInfo.isDone
            || resolution != nil
            || agentInfo.agentTool != nil
            || agentInfo.quotaPercent != nil
    }

    @ViewBuilder
    private var statusIcon: some View {
        if agentInfo.isBlocked {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(TmuxAgentStatePalette.blocked)
        } else if agentInfo.isWorking {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(TmuxAgentStatePalette.working)
        } else if agentInfo.isDone {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(TmuxAgentStatePalette.done)
        } else if let resolution {
            Text(resolution.identity.glyph)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(resolution.identity.accent)
        }
    }

    @ViewBuilder
    private var labelView: some View {
        if agentInfo.isBlocked {
            Text("Needs input")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TmuxAgentStatePalette.blocked)
        } else if agentInfo.isDone, let relative = agentInfo.doneRelativeText() {
            HStack(spacing: 3) {
                Text(agentName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.primary)
                if let model = agentInfo.modelDisplayText {
                    Text(model)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(TerminalSelectionSheetPalette.secondary)
                        .lineLimit(1)
                }
                Text(relative)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(TmuxAgentStatePalette.done)
            }
        } else {
            HStack(spacing: 3) {
                Text(agentName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.primary)
                if let profile = resolution?.profileTag {
                    Text(":\(profile)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(TerminalSelectionSheetPalette.secondary)
                }
                if let model = agentInfo.modelDisplayText {
                    Text(model)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(TerminalSelectionSheetPalette.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var agentName: String {
        resolution?.identity.displayName ?? "Agent"
    }

    private var borderColor: Color {
        if agentInfo.isBlocked {
            return TmuxAgentStatePalette.blocked.opacity(0.6)
        } else if agentInfo.isWorking {
            return TmuxAgentStatePalette.working.opacity(0.4)
        } else if agentInfo.isDone {
            return TmuxAgentStatePalette.done.opacity(0.4)
        } else {
            return TerminalSelectionSheetPalette.secondary.opacity(0.3)
        }
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if let placeText, !placeText.isEmpty { parts.append(placeText) }
        if showsAgentRow {
            parts.append(agentName)
            parts.append(agentInfo.state.rawValue)
        }
        parts.append("tap to show panes")
        return parts.joined(separator: ", ")
    }
}
