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
        _ model: String = "",
        _ tool: String = "",
        _ pct: String = ""
    ) -> String {
        [paneID, blocked, working, unseen, branch, repo, model, tool, pct]
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

    func testParsesAgentToolAndQuotaPercentFields() {
        let body = [
            line("%1", "1", "", "", "feature/byron", "remux", "claude-3-7-sonnet", "claude:work", "W36%"),
            line("%2", "", "1", "", "", "", "", "muse", "75"),
            line("%3", "", "", "", "", "", "", "grok", "92%"),
            line("%4"),
        ].joined(separator: "\n")

        let infos = TmuxPaneAgentMetadata.parseListPanesBody(body)

        XCTAssertEqual(infos[1]?.agentTool, "claude:work")
        XCTAssertEqual(infos[1]?.quotaPercent, 36)
        XCTAssertEqual(infos[2]?.agentTool, "muse")
        XCTAssertEqual(infos[2]?.quotaPercent, 75)
        XCTAssertEqual(infos[3]?.agentTool, "grok")
        XCTAssertEqual(infos[3]?.quotaPercent, 92)
        XCTAssertNil(infos[4]?.agentTool)
        XCTAssertNil(infos[4]?.quotaPercent)
    }

    func testQuotaPercentParsingVariousFormats() {
        XCTAssertEqual(TmuxPaneAgentMetadata.parseQuotaPercent("36"), 36)
        XCTAssertEqual(TmuxPaneAgentMetadata.parseQuotaPercent("36%"), 36)
        XCTAssertEqual(TmuxPaneAgentMetadata.parseQuotaPercent("W36%"), 36)
        XCTAssertEqual(TmuxPaneAgentMetadata.parseQuotaPercent("w75%"), 75)
        XCTAssertEqual(TmuxPaneAgentMetadata.parseQuotaPercent("90"), 90)
        XCTAssertEqual(TmuxPaneAgentMetadata.parseQuotaPercent("0%"), 0)
        XCTAssertEqual(TmuxPaneAgentMetadata.parseQuotaPercent("100%"), 100)
        XCTAssertEqual(TmuxPaneAgentMetadata.parseQuotaPercent("  W82%  "), 82)
        XCTAssertEqual(TmuxPaneAgentMetadata.parseQuotaPercent("36.4%"), 36)
        XCTAssertEqual(TmuxPaneAgentMetadata.parseQuotaPercent("36.6%"), 37)
        XCTAssertNil(TmuxPaneAgentMetadata.parseQuotaPercent(""))
        XCTAssertNil(TmuxPaneAgentMetadata.parseQuotaPercent("   "))
        XCTAssertNil(TmuxPaneAgentMetadata.parseQuotaPercent("none"))
        XCTAssertNil(TmuxPaneAgentMetadata.parseQuotaPercent("W"))
        XCTAssertNil(TmuxPaneAgentMetadata.parseQuotaPercent("w"))
        XCTAssertNil(TmuxPaneAgentMetadata.parseQuotaPercent("%"))
        XCTAssertNil(TmuxPaneAgentMetadata.parseQuotaPercent("W%"))
        XCTAssertNil(TmuxPaneAgentMetadata.parseQuotaPercent("-5"))
        XCTAssertNil(TmuxPaneAgentMetadata.parseQuotaPercent("W-10%"))
        XCTAssertNil(TmuxPaneAgentMetadata.parseQuotaPercent("nan"))
        XCTAssertNil(TmuxPaneAgentMetadata.parseQuotaPercent("NaN"))
        XCTAssertNil(TmuxPaneAgentMetadata.parseQuotaPercent("inf"))
        XCTAssertNil(TmuxPaneAgentMetadata.parseQuotaPercent("-inf"))
        XCTAssertNil(TmuxPaneAgentMetadata.parseQuotaPercent("infinity"))
        XCTAssertNil(TmuxPaneAgentMetadata.parseQuotaPercent("Wnan%"))
        XCTAssertNil(TmuxPaneAgentMetadata.parseQuotaPercent("1001"))
    }

    func testGracefulDegradationWithLegacyFieldCounts() {
        // Line with only 7 fields from legacy server
        let legacy7Fields = ["%1", "1", "0", "0", "main", "remux", "claude-sonnet"].joined(separator: separator)
        let infos = TmuxPaneAgentMetadata.parseListPanesBody(legacy7Fields)

        XCTAssertEqual(infos[1]?.state, .blocked)
        XCTAssertEqual(infos[1]?.gitBranch, "main")
        XCTAssertEqual(infos[1]?.agentModel, "claude-sonnet")
        XCTAssertNil(infos[1]?.agentTool)
        XCTAssertNil(infos[1]?.quotaPercent)
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
            "#{@pane_agent_tool}",
            "#{@pane_agent_pct}",
            "#{@ai_done_at}",
        ] {
            XCTAssertTrue(command.contains(option), "missing \(option)")
        }
        XCTAssertTrue(command.hasPrefix("list-panes -s -F "))
    }

    func testParsesDoneAtEpochTimestamp() {
        let epoch: TimeInterval = 1758679200
        let fields = [
            "%1", "0", "0", "1", "main", "remux", "claude-sonnet", "claude:work", "36",
            String(Int(epoch))
        ].joined(separator: separator)

        let infos = TmuxPaneAgentMetadata.parseListPanesBody(fields)
        guard let info = infos[1] else {
            return XCTFail("Expected info for pane 1")
        }

        XCTAssertEqual(info.state, .unseen)
        XCTAssertEqual(info.agentTool, "claude:work")
        XCTAssertEqual(info.quotaPercent, 36)
        XCTAssertEqual(info.doneAt, Date(timeIntervalSince1970: epoch))
        XCTAssertTrue(info.isDone)

        XCTAssertNil(TmuxPaneAgentMetadata.parseEpochDate(""))
        XCTAssertNil(TmuxPaneAgentMetadata.parseEpochDate("0"))
        XCTAssertNil(TmuxPaneAgentMetadata.parseEpochDate("-10"))
        XCTAssertNil(TmuxPaneAgentMetadata.parseEpochDate("not_a_number"))
    }

    func testDoneRelativeTextFormatting() {
        let base = Date(timeIntervalSince1970: 100_000)

        var info = TmuxPaneAgentInfo(state: .idle, doneAt: Date(timeIntervalSince1970: 99_980))
        XCTAssertEqual(info.doneRelativeText(now: base), "just now")

        info.doneAt = Date(timeIntervalSince1970: 99_880) // 120s ago
        XCTAssertEqual(info.doneRelativeText(now: base), "2m")

        info.doneAt = Date(timeIntervalSince1970: 92_800) // 7200s (2h) ago
        XCTAssertEqual(info.doneRelativeText(now: base), "2h")

        info.doneAt = Date(timeIntervalSince1970: 10_000) // 90000s (1d) ago
        XCTAssertEqual(info.doneRelativeText(now: base), "1d")

        info.doneAt = Date(timeIntervalSince1970: 100_050) // future
        XCTAssertNil(info.doneRelativeText(now: base))

        let noDone = TmuxPaneAgentInfo(state: .idle)
        XCTAssertNil(noDone.doneRelativeText(now: base))
    }

    func testGracefulDegradationWith9Fields() {
        // Line with 9 fields (no @ai_done_at from older server)
        let fields9 = ["%1", "0", "0", "0", "main", "remux", "claude-sonnet", "claude:work", "36"].joined(separator: separator)
        let infos = TmuxPaneAgentMetadata.parseListPanesBody(fields9)

        XCTAssertEqual(infos[1]?.state, .idle)
        XCTAssertEqual(infos[1]?.agentTool, "claude:work")
        XCTAssertEqual(infos[1]?.quotaPercent, 36)
        XCTAssertNil(infos[1]?.doneAt)
        XCTAssertFalse(infos[1]?.isDone ?? true)
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

        XCTAssertEqual(
            tracker.update(with: unblocked),
            [],
            "the first snapshot only seeds the baseline"
        )
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

    func testBlockedTrackerSeedsAlreadyBlockedPanesWithoutAlerting() {
        var tracker = TmuxAgentBlockedTracker()
        let blocked: [TmuxPaneID: TmuxPaneAgentInfo] = [
            7: TmuxPaneAgentInfo(state: .blocked),
            8: TmuxPaneAgentInfo(state: .blocked),
        ]

        XCTAssertEqual(
            tracker.update(with: blocked),
            [],
            "attaching to a session with blocked panes is not an alert burst"
        )
        XCTAssertEqual(
            tracker.update(with: blocked.merging([9: TmuxPaneAgentInfo(state: .blocked)]) {
                _, new in new
            }),
            [9],
            "only panes blocked after the baseline alert"
        )

        tracker.reset()
        XCTAssertEqual(
            tracker.update(with: blocked),
            [],
            "a reset re-arms the silent baseline"
        )
    }

    func testRepollGateFloorsEventPollsButNotTheTimer() {
        var gate = TmuxAgentMetadataRepollGate(minimumInterval: 2)

        XCTAssertTrue(gate.admit(at: 10), "the first event poll always fires")
        XCTAssertFalse(gate.admit(at: 11.5), "event polls inside the floor are dropped")
        XCTAssertTrue(gate.admit(at: 12), "the floor boundary admits again")

        gate.recordPoll(at: 12.5)
        XCTAssertFalse(
            gate.admit(at: 13),
            "a timer poll refreshes the floor for event polls"
        )
        XCTAssertTrue(gate.admit(at: 14.5))

        gate.reset()
        XCTAssertTrue(gate.admit(at: 14.6), "a reset clears the floor")
    }

    func testAgentBlockedNotificationIdentifierScopesPaneToSession() {
        let identifier = TmuxAgentStateNotifier.identifier(sessionName: "main", paneID: 7)

        XCTAssertNotEqual(
            identifier,
            TmuxAgentStateNotifier.identifier(sessionName: "ops", paneID: 7),
            "pane IDs are per-server; the session keeps banners distinct"
        )
        XCTAssertNotEqual(
            identifier,
            TmuxAgentStateNotifier.identifier(sessionName: "main", paneID: 8)
        )
        XCTAssertTrue(identifier.contains("main"))
        XCTAssertTrue(identifier.hasPrefix("remux.agent-blocked."))
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

    func testBlockedAgentAttentionFormatting() {
        let attention = TmuxBlockedAgentAttention(
            paneID: 5,
            windowID: 2,
            windowName: "agent-window",
            currentCommand: "claude",
            agent: .claudeCode
        )
        XCTAssertEqual(attention.title, "✦ Claude Code needs input")
        XCTAssertEqual(attention.location, "in agent-window")

        let unnamed = TmuxBlockedAgentAttention(
            paneID: 8,
            windowID: 1,
            windowName: nil,
            currentCommand: "zsh",
            agent: nil
        )
        XCTAssertEqual(unnamed.title, "Agent needs input")
        XCTAssertEqual(unnamed.location, "in pane 8")
    }

    @MainActor
    func testUserNotificationActionHandlerRegistration() {
        var received: (session: String, paneID: TmuxPaneID)?
        RemuxUserNotificationDelegate.setNotificationActionHandler { session, paneID in
            received = (session, paneID)
        }
        RemuxUserNotificationDelegate.setNotificationActionHandler(nil)
        XCTAssertNil(received)
    }

    func testAgentCompletedTrackerBaselineAndTurnDetection() {
        var tracker = TmuxAgentCompletedTracker()
        let t1 = Date(timeIntervalSince1970: 100_000)
        let t2 = Date(timeIntervalSince1970: 100_500)

        let initial: [TmuxPaneID: TmuxPaneAgentInfo] = [
            1: TmuxPaneAgentInfo(state: .unseen, doneAt: t1),
            2: TmuxPaneAgentInfo(state: .working),
        ]

        // 1. Initial snapshot only establishes baseline
        XCTAssertEqual(
            tracker.update(with: initial),
            [],
            "first snapshot establishes baseline and does not burst alerts"
        )

        // 2. Pane 2 finishes a turn with doneAt
        let pane2Done: [TmuxPaneID: TmuxPaneAgentInfo] = [
            1: TmuxPaneAgentInfo(state: .unseen, doneAt: t1),
            2: TmuxPaneAgentInfo(state: .unseen, doneAt: t2),
        ]
        XCTAssertEqual(tracker.update(with: pane2Done), [2])

        // 3. Same state does not re-alert
        XCTAssertEqual(tracker.update(with: pane2Done), [])

        // 4. Pane 1 runs another turn with newer doneAt
        let t3 = Date(timeIntervalSince1970: 101_000)
        let pane1NewDone: [TmuxPaneID: TmuxPaneAgentInfo] = [
            1: TmuxPaneAgentInfo(state: .unseen, doneAt: t3),
            2: TmuxPaneAgentInfo(state: .unseen, doneAt: t2),
        ]
        XCTAssertEqual(tracker.update(with: pane1NewDone), [1])

        // 5. Reset clears baseline
        tracker.reset()
        XCTAssertEqual(
            tracker.update(with: pane1NewDone),
            [],
            "reset establishes a new baseline"
        )
    }

    func testAgentCompletedNotificationFormattingAndIdentifier() {
        let identifier = TmuxAgentStateNotifier.completedIdentifier(sessionName: "dev", paneID: 3)
        XCTAssertTrue(identifier.contains("dev"))
        XCTAssertTrue(identifier.contains("3"))
        XCTAssertTrue(identifier.hasPrefix("remux.agent-completed."))

        let notifClaude = TmuxAgentCompletedNotification(
            sessionName: "remux",
            paneID: 1,
            agentTool: "claude:work",
            currentCommand: "claude",
            currentPath: "~/Local/remux"
        )
        XCTAssertEqual(
            TmuxAgentStateNotifier.completedTitle(for: notifClaude),
            "Claude Code finished turn"
        )
        XCTAssertEqual(
            TmuxAgentStateNotifier.completedBody(for: notifClaude),
            "remux · ~/Local/remux: claude:work is ready for your next prompt."
        )

        let notifGeneric = TmuxAgentCompletedNotification(
            sessionName: "ops",
            paneID: 2,
            agentTool: nil,
            currentCommand: "zsh",
            currentPath: ""
        )
        XCTAssertEqual(
            TmuxAgentStateNotifier.completedTitle(for: notifGeneric),
            "Agent finished turn"
        )
        XCTAssertEqual(
            TmuxAgentStateNotifier.completedBody(for: notifGeneric),
            "ops is ready for your next prompt."
        )
    }
}
