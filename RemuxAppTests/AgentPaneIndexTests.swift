import XCTest
@testable import Remux

final class AgentPaneIndexTests: XCTestCase {
    func testPlaceLabelKeepsBranchIncludingMain() {
        XCTAssertEqual(
            AgentPlaceLabel.text(
                path: "/Users/fei/Local/remux",
                branch: "main"
            ),
            "remux · main"
        )
        XCTAssertEqual(
            AgentPlaceLabel.text(
                path: "/Users/fei/Local/uni-worktree-fix",
                branch: "feat/pane-index",
                knownProjects: ["uni"]
            ),
            "uni/fix · feat/pane-index"
        )
        XCTAssertEqual(
            AgentPlaceLabel.text(
                path: "/Users/fei/Local/uni2",
                branch: "main",
                knownProjects: ["uni"]
            ),
            "uni2 · main"
        )
        XCTAssertEqual(
            AgentPlaceLabel.text(path: "/tmp/build", branch: "wip"),
            "wip"
        )
        XCTAssertNil(AgentPlaceLabel.text(path: "/tmp/build", branch: "  "))
        XCTAssertNil(AgentPlaceLabel.text(path: "", branch: nil))
    }

    func testGroupsByProjectAndSortsAttentionFirst() {
        let remuxWorking = UUID()
        let remuxIdle = UUID()
        let byronBlocked = UUID()
        let groups = AgentPaneIndex.groups(from: [
            source(
                id: remuxIdle,
                window: UUID(),
                path: "/Users/fei/Local/remux",
                command: "zsh",
                state: .idle,
                branch: "main"
            ),
            source(
                id: byronBlocked,
                window: UUID(),
                path: "/Users/fei/Local/byron",
                command: "codex",
                tool: "cx",
                state: .blocked,
                branch: "main"
            ),
            source(
                id: remuxWorking,
                window: UUID(),
                path: "/Users/fei/Local/remux",
                command: "2.1.257",
                tool: "cld:work",
                state: .working,
                branch: "feat/pane-index",
                model: "opus5[xhigh] W43%"
            ),
        ])

        XCTAssertEqual(groups.map(\.title), ["byron", "remux"])
        XCTAssertEqual(groups[0].rows.map(\.id), [byronBlocked])
        XCTAssertEqual(groups[0].rows[0].title, "Codex")
        XCTAssertEqual(groups[0].rows[0].branch, "main")

        XCTAssertEqual(groups[1].rows.map(\.id), [remuxWorking, remuxIdle])
        XCTAssertEqual(groups[1].rows[0].title, "Claude Code")
        XCTAssertEqual(groups[1].rows[0].resolution?.profileTag, "work")
        XCTAssertEqual(groups[1].rows[0].agentInfo.modelDisplayText, "opus5[xhigh]")
        XCTAssertEqual(groups[1].rows[0].branch, "feat/pane-index")
        XCTAssertEqual(groups[1].rows[1].title, "zsh")
        XCTAssertEqual(groups[1].rows[1].branch, "main")
    }

    func testWorktreeIsTheRowTitleInsideItsProject() {
        let worktree = UUID()
        let checkout = UUID()
        let window = UUID()
        let groups = AgentPaneIndex.groups(from: [
            source(
                id: checkout,
                window: window,
                path: "/Users/fei/Local/uni",
                command: "zsh",
                state: .idle,
                branch: "main"
            ),
            source(
                id: worktree,
                window: window,
                path: "/Users/fei/Local/uni-worktree-fix",
                command: "agy-1.2.3",
                state: .unseen,
                branch: "fix/index"
            ),
        ])

        XCTAssertEqual(groups.map(\.title), ["uni"])
        XCTAssertEqual(groups[0].rows.map(\.id), [worktree, checkout])
        XCTAssertEqual(groups[0].rows[0].title, "fix")
        XCTAssertNil(groups[0].rows[0].checkoutName)
        XCTAssertEqual(groups[0].rows[0].resolution?.identity, .antigravity)
        XCTAssertFalse(groups[0].rows[0].showsWindowName)
    }

    func testNumberedCloneKeepsItsDirectoryInsideTheProject() {
        let canonical = UUID()
        let clone = UUID()
        let window = UUID()
        let groups = AgentPaneIndex.groups(from: [
            source(
                id: canonical,
                window: window,
                path: "/Users/fei/Local/uni",
                command: "zsh",
                state: .idle,
                branch: "main"
            ),
            source(
                id: clone,
                window: window,
                path: "/Users/fei/Local/uni2/Sources",
                command: "zsh",
                state: .idle,
                branch: "main"
            ),
        ])

        XCTAssertEqual(groups.map(\.title), ["uni"])
        let rows = Dictionary(uniqueKeysWithValues: groups[0].rows.map { ($0.id, $0) })
        XCTAssertEqual(rows[canonical]?.title, "zsh")
        XCTAssertNil(rows[canonical]?.checkoutName)
        XCTAssertEqual(rows[clone]?.title, "zsh")
        XCTAssertEqual(rows[clone]?.checkoutName, "uni2")
    }

    func testWindowNameShowsOnlyWhenAProjectSpansWindows() {
        let firstWindow = UUID()
        let secondWindow = UUID()
        let groups = AgentPaneIndex.groups(from: [
            source(
                id: UUID(),
                window: firstWindow,
                windowName: "agents",
                path: "/Users/fei/Local/remux",
                command: "claude",
                state: .working,
                branch: "main"
            ),
            source(
                id: UUID(),
                window: secondWindow,
                windowName: "review\u{0001}",
                path: "/Users/fei/Local/remux",
                command: "codex",
                state: .idle,
                branch: "main"
            ),
            source(
                id: UUID(),
                window: UUID(),
                windowName: "solo",
                path: "/Users/fei/Local/byron",
                command: "zsh",
                state: .idle,
                branch: "main"
            ),
        ])

        let remux = groups.first { $0.title == "remux" }
        XCTAssertEqual(remux?.rows.map(\.showsWindowName), [true, true])
        XCTAssertEqual(remux?.rows.map(\.windowName), ["agents", "review"])
        XCTAssertEqual(
            groups.first { $0.title == "byron" }?.rows.map(\.showsWindowName),
            [false]
        )
    }

    func testFocusedIdlePaneStaysBehindABlockedSibling() {
        let blocked = UUID()
        let focused = UUID()
        let groups = AgentPaneIndex.groups(from: [
            source(
                id: focused,
                window: UUID(),
                path: "/Users/fei/Local/remux",
                command: "zsh",
                state: .idle,
                branch: "main",
                isFocused: true
            ),
            source(
                id: blocked,
                window: UUID(),
                path: "/Users/fei/Local/remux",
                command: "claude",
                state: .blocked,
                branch: "main"
            ),
        ])

        XCTAssertEqual(groups[0].rows.map(\.id), [blocked, focused])
        XCTAssertTrue(groups[0].rows[1].isFocused)
    }

    func testPanesOutsideAProjectStayInOtherUnlessTheyNeedAttention() {
        let otherBlocked = UUID()
        let groups = AgentPaneIndex.groups(from: [
            source(
                id: UUID(),
                window: UUID(),
                path: "/Users/fei/Local/remux",
                command: "zsh",
                state: .idle,
                branch: "main"
            ),
            source(
                id: otherBlocked,
                window: UUID(),
                path: "/tmp/notes",
                command: "vim",
                state: .blocked,
                branch: nil
            ),
        ])

        XCTAssertEqual(groups.map(\.title), ["Other", "remux"])
        XCTAssertEqual(groups[0].rows.map(\.id), [otherBlocked])
        XCTAssertNil(groups[0].rows[0].branch)
    }

    private func source(
        id: UUID,
        window: UUID,
        windowName: String = "",
        path: String,
        command: String,
        tool: String? = nil,
        state: TmuxPaneAgentState,
        branch: String?,
        model: String? = nil,
        isFocused: Bool = false
    ) -> AgentPaneIndexSource {
        AgentPaneIndexSource(
            surfaceID: id,
            windowSurfaceID: window,
            windowName: windowName,
            path: path,
            command: command,
            agentInfo: TmuxPaneAgentInfo(
                state: state,
                gitBranch: branch,
                agentModel: model,
                agentTool: tool
            ),
            isFocused: isFocused
        )
    }
}
