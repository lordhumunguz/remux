import SwiftUI
import UIKit

struct TmuxCommandPaletteSheet: View {
    let theme: TerminalTheme
    var profileTag: String? = nil
    var quotaPercent: Int? = nil
    let onSelectAction: (TmuxCommandPaletteAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredCategories, id: \.self) { category in
                    Section {
                        ForEach(actions(for: category)) { action in
                            Button {
                                triggerHaptic()
                                dismiss()
                                onSelectAction(action)
                            } label: {
                                actionRow(action)
                            }
                            .buttonStyle(.plain)
                            .remuxAppListRowSurface()
                            .accessibilityIdentifier("terminal.command.\(action.id)")
                        }
                    } header: {
                        Text(category.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(RemuxAppPalette.sectionHeader)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .remuxAppGroupedScrollBackground()
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search commands..."
            )
            .navigationTitle("Commands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.weight(.medium))
                }

                if profileTag != nil || quotaPercent != nil {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 6) {
                            Text("Commands")
                                .font(.headline)
                            if let profileTag {
                                Text(profileTag)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(TerminalSelectionSheetPalette.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(TerminalSelectionSheetPalette.row))
                            }
                            if let quota = quotaPercent {
                                TmuxAgentQuotaPill(percent: quota)
                            }
                        }
                    }
                }
            }
        }
    }

    private var filteredCategories: [TmuxCommandPaletteCategory] {
        TmuxCommandPaletteCategory.allCases.filter { category in
            !actions(for: category).isEmpty
        }
    }

    private func actions(for category: TmuxCommandPaletteCategory) -> [TmuxCommandPaletteAction] {
        TmuxCommandPaletteAction.allCases.filter { action in
            action.category == category && action.matches(query: searchText)
        }
    }

    private func actionRow(_ action: TmuxCommandPaletteAction) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(iconBackgroundColor(for: action.category))
                    .frame(width: 30, height: 30)

                Image(systemName: action.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconForegroundColor(for: action.category))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(action.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let shortcutHint = action.shortcutHint {
                Text(shortcutHint)
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private func iconBackgroundColor(for category: TmuxCommandPaletteCategory) -> Color {
        switch category {
        case .sessionAndServer:
            Color.orange.opacity(0.15)
        case .windowAndLayout:
            Color.blue.opacity(0.15)
        case .byronAgents:
            Color.purple.opacity(0.15)
        }
    }

    private func iconForegroundColor(for category: TmuxCommandPaletteCategory) -> Color {
        switch category {
        case .sessionAndServer:
            Color.orange
        case .windowAndLayout:
            Color.blue
        case .byronAgents:
            Color.purple
        }
    }

    private func triggerHaptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
