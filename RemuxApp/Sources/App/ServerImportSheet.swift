import SwiftUI

struct ServerImportPresentation: Equatable {
    let source: ServerImportSource
    var candidates: [ServerImportCandidate]
    var selection: Set<ServerImportCandidate.ID>
    var isImporting: Bool

    init(source: ServerImportSource, candidates: [ServerImportCandidate]) {
        self.source = source
        self.candidates = candidates
        selection = Set(candidates.filter { !$0.isDuplicate }.map(\.id))
        isImporting = false
    }

    var selectedCandidates: [ServerImportCandidate] {
        candidates.filter { selection.contains($0.id) }
    }
}

/// Entry point shared by the library toolbar and the empty state. On iOS the
/// only source is an exported ssh config picked through the file importer,
/// so the control is a plain button; macOS additionally reads the real
/// ~/.ssh/config and discovers Tailscale peers, so it gets a menu.
struct LibraryImportControl<Label: View>: View {
    let onImport: (ServerImportSource) -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
#if os(macOS)
        Menu {
            Button("From ~/.ssh/config") { onImport(.sshConfig) }
            Button("From Tailscale…") { onImport(.tailscale) }
        } label: {
            label()
        }
#else
        Button {
            onImport(.sshConfig)
        } label: {
            label()
        }
#endif
    }
}

struct ServerImportSheet: View {
    @Binding var presentation: ServerImportPresentation
    let onCancel: () -> Void
    let onImport: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(presentation.candidates) { candidate in
                        ServerImportCandidateRow(
                            candidate: candidate,
                            isSelected: presentation.selection.contains(candidate.id),
                            onToggle: { toggle(candidate) }
                        )
                    }
                } footer: {
                    Text(footerText)
                }
            }
            .navigationTitle("Import Servers")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(presentation.isImporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", action: onImport)
                        .fontWeight(.semibold)
                        .disabled(presentation.selection.isEmpty || presentation.isImporting)
                        .accessibilityIdentifier("server-import.import")
                }
            }
            .interactiveDismissDisabled(presentation.isImporting)
        }
    }

    private var footerText: String {
        switch presentation.source {
        case .sshConfig:
            "Identity files are never copied. Attach keys in server setup after importing."
        case .tailscale:
            "Devices import with Tailscale SSH authentication."
        }
    }

    private func toggle(_ candidate: ServerImportCandidate) {
        guard !candidate.isDuplicate else { return }
        if presentation.selection.contains(candidate.id) {
            presentation.selection.remove(candidate.id)
        } else {
            presentation.selection.insert(candidate.id)
        }
    }
}

private struct ServerImportCandidateRow: View {
    let candidate: ServerImportCandidate
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(hostLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(authLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if candidate.isDuplicate {
                    Text("Already in library")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(candidate.isDuplicate)
        .accessibilityIdentifier("server-import.row.\(candidate.displayName)")
    }

    private var hostLabel: String {
        let userPrefix = candidate.username.isEmpty ? "" : "\(candidate.username)@"
        return "\(userPrefix)\(candidate.host):\(candidate.port)"
    }

    private var authLabel: String {
        switch candidate.auth {
        case .privateKey(let identityFile):
            "Private key · \(URL(fileURLWithPath: identityFile).lastPathComponent)"
        case .tailscaleSSH:
            if let detail = candidate.detail {
                "Tailscale SSH · \(detail)"
            } else {
                "Tailscale SSH"
            }
        case .unset:
            "Finish authentication in setup"
        }
    }
}
