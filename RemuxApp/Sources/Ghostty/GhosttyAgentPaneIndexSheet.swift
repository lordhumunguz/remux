import SwiftUI

/// Session-wide pane list grouped by project. Selecting a row focuses that
/// pane, including one in another tmux window. The window grid stays one
/// action away.
struct GhosttyAgentPaneIndexSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ghosttyTerminalChromeStyle) private var chromeStyle

    let groups: [AgentPaneIndexGroup]
    let sessionName: String
    let contentHeight: CGFloat
    let onSelect: (UUID) -> Void
    let onShowWindows: () -> Void

    var body: some View {
        NavigationStack {
            TerminalSelectionSheetContent(context: contextLabel) {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if groups.isEmpty {
                            Text("No panes")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(TerminalSelectionSheetPalette.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(groups) { group in
                                groupSection(group)
                            }
                        }
                    }
                    .padding(.horizontal, TerminalSelectionSheetLayout.horizontalContentPadding)
                }
                .frame(height: contentHeight)
                .accessibilityIdentifier("terminal.agentpanes.scroll")
            } actions: {
                TerminalSelectionSheetActionButton(
                    title: "Windows",
                    systemName: "rectangle.on.rectangle",
                    accessibilityIdentifier: "terminal.agentpanes.windows",
                    action: onShowWindows
                )
            }
            .navigationTitle("Panes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        Haptic.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close Panes")
                    .accessibilityIdentifier("terminal.agentpanes.close")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("terminal.agentpanes.sheet")
    }

    private var contextLabel: String {
        let count = groups.reduce(0) { $0 + $1.rows.count }
        let noun = count == 1 ? "pane" : "panes"
        let blocked = groups.reduce(0) { count, group in
            count + group.rows.filter(\.agentInfo.isBlocked).count
        }
        var text = "\(sessionName) · \(count) \(noun)"
        if blocked == 1 {
            text += " · 1 needs you"
        } else if blocked > 1 {
            text += " · \(blocked) need you"
        }
        return text
    }

    private func groupSection(_ group: AgentPaneIndexGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TerminalSelectionSheetPalette.secondary)
                .lineLimit(1)

            ForEach(group.rows) { row in
                paneRow(row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func paneRow(_ row: AgentPaneIndexRow) -> some View {
        Button {
            Haptic.selection()
            onSelect(row.id)
        } label: {
            HStack(alignment: .center, spacing: 8) {
                TmuxAgentStateBadge(state: row.agentInfo.state, isDone: row.agentInfo.isDone)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(TerminalSelectionSheetPalette.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if row.isFocused {
                            Text("current")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(chromeStyle.selectedStroke)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        if let quota = row.agentInfo.quotaPercent {
                            TmuxAgentQuotaPill(percent: quota)
                        }
                        if let done = row.agentInfo.doneRelativeText() {
                            TmuxAgentCompletionPill(text: done)
                        }
                    }

                    if let detail = detailLine(row) {
                        Text(detail)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(TerminalSelectionSheetPalette.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                row.isFocused
                    ? chromeStyle.selectedStroke.opacity(0.16)
                    : TerminalSelectionSheetPalette.row.opacity(0.84),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        row.isFocused
                            ? chromeStyle.selectedStroke
                            : TerminalSelectionSheetPalette.stroke,
                        lineWidth: row.isFocused ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("terminal.agentpane.\(row.id.uuidString)")
        .accessibilityLabel(accessibilityLabel(for: row))
        .accessibilityAddTraits(row.isFocused ? .isSelected : [])
    }

    private func detailLine(_ row: AgentPaneIndexRow) -> String? {
        var parts: [String] = []
        if let name = row.resolution?.identity.displayName, name != row.title {
            parts.append(name)
        }
        if let profile = row.resolution?.profileTag, !profile.isEmpty {
            parts.append(profile)
        }
        if let model = row.agentInfo.modelDisplayText {
            parts.append(model)
        }
        if let checkout = row.checkoutName, checkout != row.title {
            parts.append(checkout)
        }
        if let branch = row.branch {
            parts.append(branch)
        }
        if row.showsWindowName {
            parts.append(row.windowName)
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private func accessibilityLabel(for row: AgentPaneIndexRow) -> String {
        var parts = [row.title]
        if let detail = detailLine(row) { parts.append(detail) }
        if let state = TmuxAgentStateBadge.accessibilityLabel(
            for: row.agentInfo.state,
            isDone: row.agentInfo.isDone
        ) {
            parts.append(state)
        }
        if row.isFocused { parts.append("current") }
        return parts.joined(separator: ", ")
    }
}
