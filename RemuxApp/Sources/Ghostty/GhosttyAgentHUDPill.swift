import SwiftUI

/// Floating HUD pill in the terminal viewport showing current agent activity,
/// Byron profile, quota usage, and completion recency. Tapping opens the Command Palette.
struct GhosttyAgentHUDPill: View {
    let resolution: AgentResolution?
    let agentInfo: TmuxPaneAgentInfo
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                statusIcon
                labelView
                if let quota = agentInfo.quotaPercent {
                    TmuxAgentQuotaPill(percent: quota, font: .system(size: 9, weight: .bold, design: .monospaced))
                }
            }
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
        "\(agentName), \(agentInfo.state.rawValue), tap for command palette"
    }
}
