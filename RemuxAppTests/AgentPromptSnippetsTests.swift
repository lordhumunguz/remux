import XCTest
@testable import Remux

final class AgentPromptSnippetsTests: XCTestCase {
    func testShipsTheCanonicalCockpitSnippetList() {
        XCTAssertEqual(
            AgentPromptSnippets.all.map(\.id),
            [
                "review_uncommitted_diffs",
                "review_branch_against_main",
                "review_pr_feedback",
                "find_refactoring_opportunities",
                "create_spec",
                "create_implementation_plan",
                "switch_to_plan_mode",
                "switch_to_implement_mode",
            ]
        )
        XCTAssertEqual(
            AgentPromptSnippets.all.map(\.name),
            [
                "Review uncommitted diffs",
                "Review branch against main",
                "Review PR feedback",
                "Find refactoring opportunities",
                "Create spec",
                "Create implementation plan",
                "Switch to plan mode",
                "Switch to implement mode",
            ]
        )
    }

    func testReadOnlyReviewAndPlanningSnippetsFireImmediately() {
        let immediate = AgentPromptSnippets.all.filter { !$0.requiresConfirmation }
        XCTAssertEqual(
            immediate.map(\.id),
            [
                "review_uncommitted_diffs",
                "review_branch_against_main",
                "review_pr_feedback",
                "find_refactoring_opportunities",
                "create_spec",
                "create_implementation_plan",
            ]
        )
    }

    func testModeSwitchingSnippetsRequireConfirmation() {
        let confirming = AgentPromptSnippets.all.filter(\.requiresConfirmation)
        XCTAssertEqual(
            confirming.map(\.id),
            ["switch_to_plan_mode", "switch_to_implement_mode"]
        )
    }

    func testEverySnippetEmbedsAPrompt() {
        for snippet in AgentPromptSnippets.all {
            XCTAssertFalse(
                snippet.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(snippet.id) must embed prompt text"
            )
        }
    }

    func testEmbeddedPromptsCarryTheCockpitInstructions() {
        XCTAssertEqual(
            snippet("review_uncommitted_diffs").prompt,
            """
            Inspect current uncommitted git diff.
            Prioritize correctness, maintainability, hidden coupling, and test gaps.
            Do not edit files.
            Return concise findings with severity and recommended fixes.
            """
        )
        XCTAssertEqual(
            snippet("review_branch_against_main").prompt,
            """
            Compare the current branch against the base branch.
            Focus on behavior changes, missing tests, and deployment risk.
            Do not edit files.
            """
        )
        XCTAssertEqual(
            snippet("review_pr_feedback").prompt,
            """
            Inspect unresolved PR comments and requested changes.
            Separate must-fix issues from optional suggestions.
            Do not edit files unless a follow-up implementation action is approved.
            """
        )
        XCTAssertEqual(
            snippet("find_refactoring_opportunities").prompt,
            """
            Identify small refactors that reduce duplication or risk.
            Avoid speculative architecture changes.
            Return a prioritized list with file references.
            """
        )
        XCTAssertEqual(
            snippet("create_spec").prompt,
            """
            Draft a concise implementation spec from current repo context.
            Include scope, risks, validation, and rollout notes.
            """
        )
        XCTAssertEqual(
            snippet("create_implementation_plan").prompt,
            """
            Produce a step-by-step implementation plan.
            Call out contract changes, tests, and rollback strategy.
            """
        )
        XCTAssertEqual(
            snippet("switch_to_plan_mode").prompt,
            """
            Switch the coding session to plan mode.
            Inspect and propose only until implementation mode is approved.
            """
        )
        XCTAssertEqual(
            snippet("switch_to_implement_mode").prompt,
            """
            Switch the coding session to implementation mode.
            Keep changes scoped to the approved plan.
            """
        )
    }

    private func snippet(_ id: String) -> AgentPromptSnippet {
        guard let snippet = AgentPromptSnippets.all.first(where: { $0.id == id }) else {
            XCTFail("missing snippet \(id)")
            return AgentPromptSnippets.all[0]
        }
        return snippet
    }
}
