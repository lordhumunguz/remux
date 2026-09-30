import Foundation

/// The place line for the terminal HUD: project, optional worktree, and
/// branch. The branch stays even when it is `main`, because the terminal
/// itself does not say where the pane is.
enum AgentPlaceLabel {
    static func text(
        path: String,
        branch: String?,
        knownProjects: Set<String> = []
    ) -> String? {
        let branchText = normalized(branch)
        let place = placeText(path: path, knownProjects: knownProjects)
        switch (place, branchText) {
        case let (place?, branchText?):
            return "\(place) · \(branchText)"
        case let (place?, nil):
            return place
        case let (nil, branchText?):
            return branchText
        case (nil, nil):
            return nil
        }
    }

    private static func placeText(
        path: String,
        knownProjects: Set<String>
    ) -> String? {
        guard let context = RemuxProjectGrouping.derive(
            path: path,
            knownProjects: knownProjects
        ) else { return nil }
        if let detail = context.worktreeDetail, !detail.isEmpty {
            return "\(context.projectKey)/\(detail)"
        }
        return RemuxProjectGrouping.collapsedDirectoryName(
            path: path,
            context: context
        ) ?? context.projectKey
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}

/// One pane in the session, already joined to its window and agent metadata.
struct AgentPaneIndexSource: Equatable, Sendable {
    let surfaceID: UUID
    let windowSurfaceID: UUID
    let windowName: String
    let path: String
    let command: String
    let agentInfo: TmuxPaneAgentInfo
    let isFocused: Bool
}

struct AgentPaneIndexRow: Identifiable, Equatable, Sendable {
    let id: UUID
    let windowSurfaceID: UUID
    var windowName: String
    var showsWindowName: Bool
    let title: String
    let branch: String?
    let projectKey: String?
    let checkoutName: String?
    let resolution: AgentResolution?
    let agentInfo: TmuxPaneAgentInfo
    let isFocused: Bool
    let sortRank: Int
}

struct AgentPaneIndexGroup: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let rows: [AgentPaneIndexRow]
    let attentionRank: Int
}

/// Session-wide pane list. Groups are projects. Inside a project, and across
/// projects, blocked panes come first, then an unviewed finished turn, then
/// working, then idle. tmux windows stay on the row only when a project
/// spans more than one of them. A numbered clone keeps its directory name.
enum AgentPaneIndex {
    static func groups(from sources: [AgentPaneIndexSource]) -> [AgentPaneIndexGroup] {
        let knownProjects = RemuxProjectGrouping.observedProjects(
            paths: sources.map(\.path)
        )
        var buckets: [String: [AgentPaneIndexRow]] = [:]
        var order: [String] = []
        for source in sources {
            let row = makeRow(from: source, knownProjects: knownProjects)
            let key = row.projectKey ?? ""
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(row)
        }

        let groups = order.compactMap { key -> AgentPaneIndexGroup? in
            guard let rows = buckets[key], !rows.isEmpty else { return nil }
            let sorted = rows.sorted(by: rowPrecedes)
            let windowCount = Set(sorted.map(\.windowSurfaceID)).count
            let labeled = sorted.map { row -> AgentPaneIndexRow in
                var copy = row
                copy.showsWindowName = windowCount > 1 && !row.windowName.isEmpty
                return copy
            }
            let rank = labeled.map(\.sortRank).min() ?? TmuxPaneAgentState.idle.sessionSortRank
            return AgentPaneIndexGroup(
                id: key.isEmpty ? "\u{0}" : key,
                title: key.isEmpty ? "Other" : key,
                rows: labeled,
                attentionRank: rank
            )
        }

        return groups.sorted { lhs, rhs in
            if lhs.attentionRank != rhs.attentionRank {
                return lhs.attentionRank < rhs.attentionRank
            }
            let lhsOther = lhs.id == "\u{0}"
            let rhsOther = rhs.id == "\u{0}"
            if lhsOther != rhsOther { return !lhsOther }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private static func makeRow(
        from source: AgentPaneIndexSource,
        knownProjects: Set<String>
    ) -> AgentPaneIndexRow {
        let context = RemuxProjectGrouping.derive(
            path: source.path,
            knownProjects: knownProjects
        )
        let resolution = AgentDetection.resolve(
            tool: source.agentInfo.agentTool,
            command: source.command
        )
        return AgentPaneIndexRow(
            id: source.surfaceID,
            windowSurfaceID: source.windowSurfaceID,
            windowName: displayWindowName(source.windowName),
            showsWindowName: false,
            title: title(context: context, resolution: resolution, source: source),
            branch: normalizedBranch(source.agentInfo.gitBranch),
            projectKey: context?.projectKey,
            checkoutName: context.flatMap {
                RemuxProjectGrouping.collapsedDirectoryName(
                    path: source.path,
                    context: $0
                )
            },
            resolution: resolution,
            agentInfo: source.agentInfo,
            isFocused: source.isFocused,
            sortRank: source.agentInfo.state.sessionSortRank
        )
    }

    private static func title(
        context: RemuxProjectGrouping.Context?,
        resolution: AgentResolution?,
        source: AgentPaneIndexSource
    ) -> String {
        if let detail = context?.worktreeDetail, !detail.isEmpty {
            return detail
        }
        if let resolution {
            return resolution.identity.displayName
        }
        let command = source.command.trimmingCharacters(in: .whitespacesAndNewlines)
        if !command.isEmpty { return command }
        let directory = (source.path as NSString).lastPathComponent
        if !directory.isEmpty, directory != "/" { return directory }
        return "Pane"
    }

    private static func normalizedBranch(_ branch: String?) -> String? {
        guard let trimmed = branch?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    private static func displayWindowName(_ name: String) -> String {
        let scalars = name.unicodeScalars.filter {
            $0.properties.generalCategory != .control
        }
        return String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func rowPrecedes(
        _ lhs: AgentPaneIndexRow,
        _ rhs: AgentPaneIndexRow
    ) -> Bool {
        if lhs.sortRank != rhs.sortRank { return lhs.sortRank < rhs.sortRank }
        let order = lhs.title.localizedStandardCompare(rhs.title)
        if order != .orderedSame { return order == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
