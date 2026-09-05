import Foundation

/// Canonical project/worktree grouping for pane directories.
///
/// Maps a pane's current path to a canonical project key plus an optional
/// worktree detail, so panes and sessions group the way the fleet is
/// actually organized: one project with many checkouts (numbered clones,
/// git worktrees), not many unrelated directory names.
///
/// Derivation rules, in order:
///
/// 1. Path → project directory name:
///    - The first component after a `Local` component wins
///      (`~/Local/uni/Sources` → `uni`); deeper nesting collapses to the
///      top-level directory under `Local`.
///    - Otherwise the first component under the user's home directory
///      (depth-1 project dirs such as `~/dotfiles`). Home comes from
///      `homeDirectory` when provided, else is inferred from a leading
///      `/home/<user>` or `/Users/<user>` pair.
///    - The home directory itself, `/`, and paths outside home with no
///      `Local` component (e.g. `/tmp/build`) derive nothing.
///
/// 2. Directory name → (projectKey, worktreeDetail?):
///    a. `<base>-worktree-<rest>` / `<base>-wt-<rest>` split at the first
///       explicit separator; both sides must be non-empty. A dangling
///       separator (`uni-worktree-`) keeps the full name opaque.
///    b. Plain `<base>-<task>` collapses only when the longest dash
///       prefix is in `knownProjects` — conservative, so projects with
///       real dashes in their names keep their full name.
///    c. Trailing-digit clones (`uni2` → `uni`) collapse when the digit
///       run is 1–2 digits, the remaining base is at least two characters
///       and ends in a letter, and the base is in `knownProjects` — or
///       `knownProjects` is empty, where the base-looking prefix alone
///       decides. A project literally named `app2` therefore keeps its
///       name whenever the registry has data and no `app` base is known.
///    d. Otherwise the full directory name is the project.
///
/// 3. Worktree details drop a trailing random suffix
///    (`adgroup.HdLq7V` → `adgroup`): a final dot segment of 6+
///    alphanumerics mixing letters and digits.
///
/// `knownProjects` is the observed project registry. It is derived from
/// data — the directory names currently seen across panes, plus the bases
/// of explicit worktree names — never hardcoded.
enum RemuxProjectGrouping {
    struct Context: Equatable, Sendable {
        let projectKey: String
        let worktreeDetail: String?
    }

    /// Pane directory metadata for one session: the focused pane's path
    /// plus every pane path in the session's latest topology.
    struct PanePaths: Equatable, Sendable {
        let focusedPath: String?
        let allPaths: [String]
    }

    /// Derives the project context for one pane path. Returns nil when the
    /// path carries no project signal (home itself, root, non-home paths
    /// without a `Local` component), so callers can fall back to raw
    /// display.
    static func derive(
        path: String,
        homeDirectory: String? = nil,
        knownProjects: Set<String> = []
    ) -> Context? {
        guard let name = projectDirectoryName(
            path: path,
            homeDirectory: homeDirectory
        ) else { return nil }
        return parse(directoryName: name, knownProjects: knownProjects)
    }

    /// Builds the observed project registry from pane paths: every project
    /// directory name seen, plus the base of every explicit worktree name.
    static func observedProjects(
        paths: [String],
        homeDirectory: String? = nil
    ) -> Set<String> {
        var projects = Set<String>()
        for path in paths {
            guard let name = projectDirectoryName(
                path: path,
                homeDirectory: homeDirectory
            ) else { continue }
            projects.insert(name)
            if let explicit = splitExplicitWorktree(name) {
                projects.insert(explicit.base)
            }
        }
        return projects
    }

    /// Resolves one context for a whole session: the focused pane's
    /// directory wins; without it, the majority project across panes
    /// (first-seen on ties). Returns nil when no pane path derives.
    static func sessionContext(
        _ panePaths: PanePaths,
        homeDirectory: String? = nil,
        knownProjects: Set<String> = []
    ) -> Context? {
        if let focusedPath = panePaths.focusedPath,
           let focused = derive(
               path: focusedPath,
               homeDirectory: homeDirectory,
               knownProjects: knownProjects
           ) {
            return focused
        }

        var firstContextByKey: [String: Context] = [:]
        var counts: [String: Int] = [:]
        var order: [String] = []
        for path in panePaths.allPaths {
            guard let context = derive(
                path: path,
                homeDirectory: homeDirectory,
                knownProjects: knownProjects
            ) else { continue }
            if firstContextByKey[context.projectKey] == nil {
                firstContextByKey[context.projectKey] = context
                order.append(context.projectKey)
            }
            counts[context.projectKey, default: 0] += 1
        }
        guard let winner = order.max(by: { counts[$0, default: 0] < counts[$1, default: 0] }) else {
            return nil
        }
        return firstContextByKey[winner]
    }

    // MARK: Path → project directory name

    private static func projectDirectoryName(
        path: String,
        homeDirectory: String?
    ) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty else { return nil }

        if let localIndex = components.firstIndex(of: "Local") {
            guard localIndex + 1 < components.count else { return nil }
            return components[localIndex + 1]
        }

        guard let homeComponents = homeComponents(
            for: components,
            homeDirectory: homeDirectory
        ) else { return nil }
        guard components.count > homeComponents.count,
              components.starts(with: homeComponents)
        else { return nil }
        let relative = components.dropFirst(homeComponents.count)
        guard let candidate = relative.first, candidate != "Local" else { return nil }
        return candidate
    }

    private static func homeComponents(
        for pathComponents: [String],
        homeDirectory: String?
    ) -> [String]? {
        if let homeDirectory {
            let components = homeDirectory
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            if !components.isEmpty { return components }
        }
        guard let root = pathComponents.first,
              ["home", "Users"].contains(root),
              pathComponents.count >= 2
        else { return nil }
        return Array(pathComponents.prefix(2))
    }

    // MARK: Directory name → context

    private static func parse(
        directoryName name: String,
        knownProjects: Set<String>
    ) -> Context {
        if name.contains("-worktree-") || name.contains("-wt-") {
            guard let explicit = splitExplicitWorktree(name) else {
                // Dangling separator (`uni-worktree-`): keep the name opaque.
                return Context(projectKey: name, worktreeDetail: nil)
            }
            return Context(
                projectKey: explicit.base,
                worktreeDetail: cleanedDetail(explicit.rest)
            )
        }

        if let dashed = splitKnownDashPrefix(name, knownProjects: knownProjects) {
            return Context(
                projectKey: dashed.base,
                worktreeDetail: cleanedDetail(dashed.rest)
            )
        }

        if let base = numberedCloneBase(name, knownProjects: knownProjects) {
            return Context(projectKey: base, worktreeDetail: nil)
        }

        return Context(projectKey: name, worktreeDetail: nil)
    }

    private static func splitExplicitWorktree(_ name: String) -> (base: String, rest: String)? {
        for separator in ["-worktree-", "-wt-"] {
            guard let range = name.range(of: separator) else { continue }
            let base = String(name[name.startIndex..<range.lowerBound])
            let rest = String(name[range.upperBound...])
            guard !base.isEmpty, !rest.isEmpty else { continue }
            return (base, rest)
        }
        return nil
    }

    private static func splitKnownDashPrefix(
        _ name: String,
        knownProjects: Set<String>
    ) -> (base: String, rest: String)? {
        var match: (base: String, rest: String)?
        var index = name.startIndex
        while let hyphen = name[index...].firstIndex(of: "-") {
            let base = String(name[name.startIndex..<hyphen])
            let rest = String(name[name.index(after: hyphen)...])
            if !base.isEmpty, !rest.isEmpty, knownProjects.contains(base) {
                match = (base, rest)
            }
            index = name.index(after: hyphen)
        }
        return match
    }

    private static func numberedCloneBase(
        _ name: String,
        knownProjects: Set<String>
    ) -> String? {
        var digitCount = 0
        var index = name.endIndex
        while index > name.startIndex {
            let previous = name.index(before: index)
            guard name[previous].isNumber else { break }
            digitCount += 1
            index = previous
        }
        guard (1...2).contains(digitCount) else { return nil }
        let base = String(name[name.startIndex..<index])
        guard base.count >= 2, base.last?.isLetter == true else { return nil }
        guard knownProjects.isEmpty || knownProjects.contains(base) else { return nil }
        return base
    }

    private static func cleanedDetail(_ rest: String) -> String? {
        guard let dotIndex = rest.lastIndex(of: ".") else {
            return rest.isEmpty ? nil : rest
        }
        let tail = rest[rest.index(after: dotIndex)...]
        let head = String(rest[rest.startIndex..<dotIndex])
        guard tail.count >= 6,
              tail.allSatisfy(\.isLetterOrNumberOrASCII),
              tail.contains(where: \.isNumber),
              tail.contains(where: \.isLetter)
        else { return rest.isEmpty ? nil : rest }
        return head.isEmpty ? nil : head
    }
}

private extension Character {
    var isLetterOrNumberOrASCII: Bool {
        isASCII && (isLetter || isNumber)
    }
}
