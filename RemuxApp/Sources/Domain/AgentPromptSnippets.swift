import Foundation

/// One-tap prompt snippets sent as keys into the attached pane. The prompt
/// text is embedded from the user's cockpit snippet config
/// (config/snippets/*.yaml) so the app carries no runtime file dependency.
struct AgentPromptSnippet: Identifiable, Equatable, Sendable {
    enum Category: String, Equatable, Sendable {
        case review
        case planning
        case mode
    }

    enum Risk: String, Equatable, Sendable {
        case readOnly = "read_only"
        case safeLocal = "safe_local"
    }

    let id: String
    let name: String
    let prompt: String
    let category: Category
    let risk: Risk

    /// Read-only review/planning snippets fire immediately; mode switches
    /// and write-ish snippets confirm first.
    var requiresConfirmation: Bool {
        category == .mode || risk != .readOnly
    }
}

enum AgentPromptSnippets {
    static let all: [AgentPromptSnippet] = [
        AgentPromptSnippet(
            id: "review_uncommitted_diffs",
            name: "Review uncommitted diffs",
            prompt: """
                Inspect current uncommitted git diff.
                Prioritize correctness, maintainability, hidden coupling, and test gaps.
                Do not edit files.
                Return concise findings with severity and recommended fixes.
                """,
            category: .review,
            risk: .readOnly
        ),
        AgentPromptSnippet(
            id: "review_branch_against_main",
            name: "Review branch against main",
            prompt: """
                Compare the current branch against the base branch.
                Focus on behavior changes, missing tests, and deployment risk.
                Do not edit files.
                """,
            category: .review,
            risk: .readOnly
        ),
        AgentPromptSnippet(
            id: "review_pr_feedback",
            name: "Review PR feedback",
            prompt: """
                Inspect unresolved PR comments and requested changes.
                Separate must-fix issues from optional suggestions.
                Do not edit files unless a follow-up implementation action is approved.
                """,
            category: .review,
            risk: .readOnly
        ),
        AgentPromptSnippet(
            id: "find_refactoring_opportunities",
            name: "Find refactoring opportunities",
            prompt: """
                Identify small refactors that reduce duplication or risk.
                Avoid speculative architecture changes.
                Return a prioritized list with file references.
                """,
            category: .review,
            risk: .readOnly
        ),
        AgentPromptSnippet(
            id: "create_spec",
            name: "Create spec",
            prompt: """
                Draft a concise implementation spec from current repo context.
                Include scope, risks, validation, and rollout notes.
                """,
            category: .planning,
            risk: .readOnly
        ),
        AgentPromptSnippet(
            id: "create_implementation_plan",
            name: "Create implementation plan",
            prompt: """
                Produce a step-by-step implementation plan.
                Call out contract changes, tests, and rollback strategy.
                """,
            category: .planning,
            risk: .readOnly
        ),
        AgentPromptSnippet(
            id: "switch_to_plan_mode",
            name: "Switch to plan mode",
            prompt: """
                Switch the coding session to plan mode.
                Inspect and propose only until implementation mode is approved.
                """,
            category: .mode,
            risk: .readOnly
        ),
        AgentPromptSnippet(
            id: "switch_to_implement_mode",
            name: "Switch to implement mode",
            prompt: """
                Switch the coding session to implementation mode.
                Keep changes scoped to the approved plan.
                """,
            category: .mode,
            risk: .safeLocal
        ),
    ]
}
