import XCTest
@testable import Remux

final class TmuxPaneAgentStateTests: XCTestCase {
    private let separator = TmuxPaneAgentMetadata.fieldSeparator

    private func line(
        _ paneID: String,
        _ blocked: String = "",
        _ working: String = "",
        _ unseen: String = "",
        _ branch: String = "",
        _ repo: String = "",
        _ model: String = ""
    ) -> String {
        [paneID, blocked, working, unseen, branch, repo, model]
            .joined(separator: separator)
    }

    func testParsesBlockedWorkingUnseenWithPanePrecedence() {
        let body = [
            line("%1", "1", "1"),
            line("%2", "0", "1"),
            line("%3", "0", "0", "1"),
            line("%4"),
        ].joined(separator: "\n")

        let infos = TmuxPaneAgentMetadata.parseListPanesBody(body)

        XCTAssertEqual(infos[1]?.state, .blocked, "blocked beats working on one pane")
        XCTAssertEqual(infos[2]?.state, .working)
        XCTAssertEqual(infos[3]?.state, .unseen)
        XCTAssertEqual(infos[4]?.state, .idle)
    }

    func testMissingAndZeroOptionsDegradeToIdle() {
        let body = [
            line("%1"),
            line("%2", "0", "0", "0"),
        ].joined(separator: "\n")

        let infos = TmuxPaneAgentMetadata.parseListPanesBody(body)

        XCTAssertEqual(infos[1], .idle)
        XCTAssertEqual(infos[2], .idle)
    }

    func testParsesGitAndModelFieldsAndToleratesTheirAbsence() {
        let body = [
            line("%1", "1", "", "", "feature/agent-state", "remux", "claude-opus-4.1"),
            line("%2"),
        ].joined(separator: "\n")

        let infos = TmuxPaneAgentMetadata.parseListPanesBody(body)

        XCTAssertEqual(infos[1]?.gitBranch, "feature/agent-state")
        XCTAssertEqual(infos[1]?.gitRepo, "remux")
        XCTAssertEqual(infos[1]?.agentModel, "claude-opus-4.1")
        XCTAssertNil(infos[2]?.gitBranch)
        XCTAssertNil(infos[2]?.gitRepo)
        XCTAssertNil(infos[2]?.agentModel)
    }

    func testSkipsMalformedLines() {
        let body = [
            "not-a-pane",
            line("%1", "1"),
            "%2",
        ].joined(separator: "\n")

        let infos = TmuxPaneAgentMetadata.parseListPanesBody(body)

        XCTAssertEqual(infos.count, 1, "lines without the full field set are skipped")
        XCTAssertEqual(infos[1]?.state, .blocked)
        XCTAssertNil(infos[2])
    }

    func testListPanesCommandQueriesEveryPaneOption() {
        let command = TmuxPaneAgentMetadata.listPanesCommand

        for option in [
            "#{pane_id}",
            "#{@ai_blocked}",
            "#{@claude_working}",
            "#{@ai_unseen}",
            "#{@pane_git_branch}",
            "#{@pane_git_repo}",
            "#{@pane_agent_model}",
        ] {
            XCTAssertTrue(command.contains(option), "missing \(option)")
        }
        XCTAssertTrue(command.hasPrefix("list-panes -s -F "))
    }

    func testSessionAggregateRanksBlockedAboveUnseenAboveWorking() {
        XCTAssertEqual(
            TmuxPaneAgentState.sessionAggregate(of: [.idle, .working, .unseen, .blocked]),
            .blocked
        )
        XCTAssertEqual(
            TmuxPaneAgentState.sessionAggregate(of: [.idle, .working, .unseen]),
            .unseen
        )
        XCTAssertEqual(
            TmuxPaneAgentState.sessionAggregate(of: [.idle, .working]),
            .working
        )
        XCTAssertEqual(TmuxPaneAgentState.sessionAggregate(of: [.idle, .idle]), .idle)
        XCTAssertEqual(TmuxPaneAgentState.sessionAggregate(of: []), .idle)
    }

    func testBlockedTrackerRaisesOneAlertPerEpisode() {
        var tracker = TmuxAgentBlockedTracker()
        let blocked: [TmuxPaneID: TmuxPaneAgentInfo] = [7: TmuxPaneAgentInfo(state: .blocked)]
        let unblocked: [TmuxPaneID: TmuxPaneAgentInfo] = [7: .idle]

        XCTAssertEqual(tracker.update(with: blocked), [7])
        XCTAssertEqual(
            tracker.update(with: blocked),
            [],
            "a pane that stays blocked is one episode"
        )
        XCTAssertEqual(tracker.update(with: unblocked), [])
        XCTAssertEqual(
            tracker.update(with: blocked),
            [7],
            "leaving blocked ends the episode; a later block alerts again"
        )
        XCTAssertEqual(
            tracker.update(with: [:]),
            [],
            "a removed pane ends its episode silently"
        )
    }

    func testBlockedAlertPolicy() {
        let backgrounded = TmuxAgentBlockedAlertPolicy(
            isAppActive: false,
            isSessionPresented: true,
            viewedPaneID: 7
        )
        XCTAssertTrue(
            backgrounded.shouldNotify(paneID: 7),
            "a backgrounded app alerts even for the pane that was on screen"
        )

        let otherPane = TmuxAgentBlockedAlertPolicy(
            isAppActive: true,
            isSessionPresented: true,
            viewedPaneID: 7
        )
        XCTAssertTrue(otherPane.shouldNotify(paneID: 8))
        XCTAssertFalse(
            otherPane.shouldNotify(paneID: 7),
            "the user is already looking at the blocked pane"
        )

        let otherSession = TmuxAgentBlockedAlertPolicy(
            isAppActive: true,
            isSessionPresented: false,
            viewedPaneID: 7
        )
        XCTAssertTrue(
            otherSession.shouldNotify(paneID: 7),
            "an unpresented session alerts even for its active pane"
        )
    }
}
