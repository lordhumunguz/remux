import Foundation
import XCTest
@testable import Remux

final class SessionSwitcherProjectionTests: XCTestCase {
    @MainActor
    func testLastOpenedPresentationUsesJustNowForRecentDates() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)

        XCTAssertEqual(
            SessionLastOpenedText.value(
                for: referenceDate.addingTimeInterval(-30),
                relativeTo: referenceDate
            ),
            "Opened just now"
        )
    }

    func testProjectionPreservesCanonicalActiveOrderAndMarksSelection() {
        let production = makeServer(name: "Production")
        let macMini = makeServer(name: "Mac Mini")
        let newest = makeWorkspace(
            server: production,
            name: "api",
            lastOpenedAt: Date(timeIntervalSince1970: 300)
        )
        let selected = makeWorkspace(
            server: macMini,
            name: "codex",
            lastOpenedAt: Date(timeIntervalSince1970: 100)
        )

        let projection = SessionSwitcherProjection(
            snapshot: snapshot(
                servers: [production, macMini],
                workspaces: [newest, selected]
            ),
            activeSessions: [
                makeSession(server: production, workspace: newest),
                makeSession(server: macMini, workspace: selected),
            ],
            selectedSessionID: selected.id
        )

        XCTAssertEqual(projection.activeSessions.map(\.id), [newest.id, selected.id])
        XCTAssertEqual(projection.activeSessions.map(\.sessionName), ["api", "codex"])
        XCTAssertEqual(projection.activeSessions.map(\.serverName), ["Production", "Mac Mini"])
        XCTAssertEqual(projection.activeSessions.map(\.isSelected), [false, true])
    }

    func testProjectionKeepsEveryActiveRuntimeWhenNamesMatch() {
        let server = makeServer(name: "Production")
        let first = makeWorkspace(
            server: server,
            name: "shared",
            lastOpenedAt: Date(timeIntervalSince1970: 200)
        )
        let second = makeWorkspace(
            server: server,
            name: "shared",
            lastOpenedAt: Date(timeIntervalSince1970: 100)
        )

        let projection = SessionSwitcherProjection(
            snapshot: snapshot(servers: [server], workspaces: [first, second]),
            activeSessions: [
                makeSession(server: server, workspace: first),
                makeSession(server: server, workspace: second),
            ],
            discoveryStates: [server.id: loadedDiscovery(["shared"])],
            selectedSessionID: second.id
        )

        XCTAssertEqual(projection.activeSessions.map(\.id), [first.id, second.id])
        XCTAssertEqual(projection.activeSessions.map(\.isSelected), [false, true])
        XCTAssertTrue(projection.availableSessions.isEmpty)
    }

    func testProjectionSeparatesConfirmedRecentFromGlobalAvailableSessions() {
        let production = makeServer(name: "Production")
        let staging = makeServer(name: "Staging")
        let active = makeWorkspace(
            server: production,
            name: "active",
            lastOpenedAt: Date(timeIntervalSince1970: 300)
        )
        let recent = makeWorkspace(
            server: production,
            name: "recent",
            lastOpenedAt: Date(timeIntervalSince1970: 200)
        )
        let missing = makeWorkspace(
            server: production,
            name: "gone",
            lastOpenedAt: Date(timeIntervalSince1970: 100)
        )

        let projection = SessionSwitcherProjection(
            snapshot: snapshot(
                servers: [production, staging],
                workspaces: [active, recent, missing]
            ),
            activeSessions: [makeSession(server: production, workspace: active)],
            discoveryStates: [
                production.id: loadedDiscovery(["active", "recent", "remote"]),
                staging.id: loadedDiscovery(["logs"]),
            ],
            selectedSessionID: active.id
        )

        XCTAssertEqual(projection.activeSessions.map(\.id), [active.id])
        XCTAssertEqual(projection.recentSessions.map(\.id), [recent.id])
        XCTAssertEqual(
            projection.availableSessions.map(\.id),
            [
                RemoteTmuxSessionIdentity(serverID: production.id, sessionName: "remote"),
                RemoteTmuxSessionIdentity(serverID: staging.id, sessionName: "logs"),
            ]
        )
        XCTAssertFalse(projection.recentSessions.contains { $0.id == missing.id })
        XCTAssertFalse(
            projection.availableSessions.contains { $0.id.sessionName == "recent" }
        )
        XCTAssertEqual(projection.availableSessionNames(on: production.id), ["remote"])
        XCTAssertEqual(projection.availableSessionNames(on: staging.id), ["logs"])
    }

    func testProjectionKeepsLargeAvailableInventoryOutOfQuickSheet() {
        let server = makeServer(name: "Production")
        let projection = SessionSwitcherProjection(
            snapshot: snapshot(servers: [server], workspaces: []),
            activeSessions: [],
            discoveryStates: [
                server.id: loadedDiscovery(["one", "two", "three", "four", "five"]),
            ],
            selectedSessionID: nil
        )

        XCTAssertEqual(projection.availableSessions.count, 5)
        XCTAssertEqual(projection.inlineAvailableSessions.count, 3)
        XCTAssertEqual(projection.hiddenAvailableSessionCount, 2)
        XCTAssertEqual(
            projection.availableSessionNames(on: server.id),
            projection.availableSessions.map(\.id.sessionName)
        )
        XCTAssertEqual(
            projection.inlineAvailableSessions.map(\.id.sessionName),
            Array(projection.availableSessions.prefix(3)).map(\.id.sessionName)
        )
    }

    func testProjectionIncludesEveryInactiveWorkspaceInRecentOrder() {
        let server = makeServer(name: "Mac Mini")
        let workspaces = (0..<7).map { index in
            makeWorkspace(
                server: server,
                name: "session-\(index)",
                lastOpenedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        let projection = SessionSwitcherProjection(
            snapshot: snapshot(servers: [server], workspaces: workspaces),
            activeSessions: [],
            selectedSessionID: nil
        )

        XCTAssertEqual(projection.recentSessions.count, 7)
        XCTAssertEqual(
            projection.recentSessions.map(\.sessionName),
            (0..<7).reversed().map { "session-\($0)" }
        )
        XCTAssertEqual(projection.recentSessions.map(\.serverName), Array(repeating: "Mac Mini", count: 7))
    }

    func testProjectionExcludesActiveWorkspaceFromRecentSessionsByIdentity() {
        let server = makeServer(name: "Production")
        let persistedActive = makeWorkspace(
            server: server,
            name: "api",
            lastOpenedAt: Date(timeIntervalSince1970: 100)
        )
        var runtimeActive = persistedActive
        runtimeActive.lastOpenedAt = Date(timeIntervalSince1970: 300)
        let recent = makeWorkspace(
            server: server,
            name: "logs",
            lastOpenedAt: Date(timeIntervalSince1970: 200)
        )

        let projection = SessionSwitcherProjection(
            snapshot: snapshot(
                servers: [server],
                workspaces: [persistedActive, recent]
            ),
            activeSessions: [makeSession(server: server, workspace: runtimeActive)],
            selectedSessionID: runtimeActive.id
        )

        XCTAssertEqual(projection.activeSessions.map(\.id), [runtimeActive.id])
        XCTAssertEqual(projection.recentSessions.map(\.id), [recent.id])
    }

    func testProjectionOmitsWorkspaceWhoseServerIsUnavailable() {
        let savedServer = makeServer(name: "Production")
        let missingServer = makeServer(name: "Removed")
        let available = makeWorkspace(
            server: savedServer,
            name: "api",
            lastOpenedAt: Date(timeIntervalSince1970: 100)
        )
        let orphan = makeWorkspace(
            server: missingServer,
            name: "orphan",
            lastOpenedAt: Date(timeIntervalSince1970: 200)
        )

        let projection = SessionSwitcherProjection(
            snapshot: snapshot(
                servers: [savedServer],
                workspaces: [available, orphan]
            ),
            activeSessions: [],
            selectedSessionID: nil
        )

        XCTAssertEqual(projection.recentSessions.map(\.id), [available.id])
    }

    func testOrderedServersPlacesCurrentServerFirstThenSortsByName() {
        let production = makeServer(name: "Production")
        let macMini = makeServer(name: "Mac Mini")
        let staging = makeServer(name: "Staging")

        let ordered = SessionSwitcherProjection.orderedServers(
            [production, staging, macMini],
            currentServerID: staging.id
        )

        XCTAssertEqual(ordered.map(\.id), [staging.id, macMini.id, production.id])
    }

    func testActiveSessionsSortByAgentUrgencyThenCanonicalOrder() {
        let server = makeServer(name: "Production")
        let idleNewest = makeWorkspace(
            server: server,
            name: "idle-newest",
            lastOpenedAt: Date(timeIntervalSince1970: 400)
        )
        let blockedOldest = makeWorkspace(
            server: server,
            name: "blocked-oldest",
            lastOpenedAt: Date(timeIntervalSince1970: 100)
        )
        let unseen = makeWorkspace(
            server: server,
            name: "unseen",
            lastOpenedAt: Date(timeIntervalSince1970: 300)
        )
        let working = makeWorkspace(
            server: server,
            name: "working",
            lastOpenedAt: Date(timeIntervalSince1970: 200)
        )
        let blockedNewer = makeWorkspace(
            server: server,
            name: "blocked-newer",
            lastOpenedAt: Date(timeIntervalSince1970: 250)
        )

        let projection = SessionSwitcherProjection(
            snapshot: snapshot(
                servers: [server],
                workspaces: [idleNewest, blockedOldest, unseen, working, blockedNewer]
            ),
            activeSessions: [
                makeSession(server: server, workspace: idleNewest, agentState: .idle),
                makeSession(server: server, workspace: blockedOldest, agentState: .blocked),
                makeSession(server: server, workspace: unseen, agentState: .unseen),
                makeSession(server: server, workspace: working, agentState: .working),
                makeSession(server: server, workspace: blockedNewer, agentState: .blocked),
            ],
            selectedSessionID: nil
        )

        XCTAssertEqual(
            projection.activeSessions.map(\.id),
            [blockedNewer.id, blockedOldest.id, unseen.id, working.id, idleNewest.id],
            "blocked first, then unseen, then working, then idle; canonical order within a group"
        )
        XCTAssertEqual(
            projection.activeSessions.map(\.agentState),
            [.blocked, .blocked, .unseen, .working, .idle]
        )
    }

    func testProjectionGroupsActiveSessionsByCanonicalProject() {
        let server = makeServer(name: "Mac Mini")
        let base = makeWorkspace(
            server: server,
            name: "uni",
            lastOpenedAt: Date(timeIntervalSince1970: 300)
        )
        let worktree = makeWorkspace(
            server: server,
            name: "adgroup",
            lastOpenedAt: Date(timeIntervalSince1970: 200)
        )
        let clone = makeWorkspace(
            server: server,
            name: "uni-followup",
            lastOpenedAt: Date(timeIntervalSince1970: 100)
        )

        let projection = SessionSwitcherProjection(
            snapshot: snapshot(servers: [server], workspaces: [base, worktree, clone]),
            activeSessions: [
                makeSession(server: server, workspace: base),
                makeSession(server: server, workspace: worktree),
                makeSession(server: server, workspace: clone),
            ],
            selectedSessionID: worktree.id,
            projectContexts: [
                base.id: RemuxProjectGrouping.Context(
                    projectKey: "uni",
                    worktreeDetail: nil
                ),
                worktree.id: RemuxProjectGrouping.Context(
                    projectKey: "reporting_queries",
                    worktreeDetail: "adgroup"
                ),
                clone.id: RemuxProjectGrouping.Context(
                    projectKey: "uni",
                    worktreeDetail: nil
                ),
            ]
        )

        XCTAssertTrue(projection.usesActiveProjectGrouping)
        XCTAssertTrue(projection.ungroupedActiveSessions.isEmpty)
        XCTAssertEqual(
            projection.activeProjectGroups.map(\.projectKey),
            ["uni", "reporting_queries"]
        )
        XCTAssertEqual(
            projection.activeProjectGroups[0].sessions.map(\.id),
            [base.id, clone.id]
        )
        XCTAssertEqual(
            projection.activeProjectGroups[1].sessions.map(\.distinguishingTitle),
            ["adgroup"]
        )
        XCTAssertEqual(
            projection.activeProjectGroups[0].sessions.map(\.distinguishingTitle),
            ["uni", "uni-followup"]
        )
    }

    func testProjectionFallsBackToFlatActiveListWithoutProjectContexts() {
        let server = makeServer(name: "Mac Mini")
        let first = makeWorkspace(
            server: server,
            name: "uni",
            lastOpenedAt: Date(timeIntervalSince1970: 200)
        )
        let second = makeWorkspace(
            server: server,
            name: "smetl",
            lastOpenedAt: Date(timeIntervalSince1970: 100)
        )

        let projection = SessionSwitcherProjection(
            snapshot: snapshot(servers: [server], workspaces: [first, second]),
            activeSessions: [
                makeSession(server: server, workspace: first),
                makeSession(server: server, workspace: second),
            ],
            selectedSessionID: nil
        )

        XCTAssertFalse(projection.usesActiveProjectGrouping)
        XCTAssertEqual(projection.activeProjectGroups, [])
        XCTAssertEqual(
            projection.ungroupedActiveSessions.map(\.id),
            [first.id, second.id]
        )
    }

    func testProjectionKeepsUnresolvedSessionsUngroupedAlongsideGroups() {
        let server = makeServer(name: "Mac Mini")
        let resolved = makeWorkspace(
            server: server,
            name: "uni",
            lastOpenedAt: Date(timeIntervalSince1970: 200)
        )
        let connecting = makeWorkspace(
            server: server,
            name: "smetl",
            lastOpenedAt: Date(timeIntervalSince1970: 100)
        )

        let projection = SessionSwitcherProjection(
            snapshot: snapshot(servers: [server], workspaces: [resolved, connecting]),
            activeSessions: [
                makeSession(server: server, workspace: resolved),
                makeSession(server: server, workspace: connecting),
            ],
            selectedSessionID: nil,
            projectContexts: [
                resolved.id: RemuxProjectGrouping.Context(
                    projectKey: "uni",
                    worktreeDetail: nil
                ),
            ]
        )

        XCTAssertTrue(projection.usesActiveProjectGrouping)
        XCTAssertEqual(projection.activeProjectGroups.map(\.projectKey), ["uni"])
        XCTAssertEqual(
            projection.ungroupedActiveSessions.map(\.id),
            [connecting.id]
        )
    }

    private func snapshot(
        servers: [SavedServer],
        workspaces: [SavedWorkspace]
    ) -> ConnectionLibrarySnapshot {
        ConnectionLibrarySnapshot(servers: servers, workspaces: workspaces)
    }

    private func makeWorkspace(
        server: SavedServer,
        name: String,
        lastOpenedAt: Date
    ) -> SavedWorkspace {
        SavedWorkspace(
            serverID: server.id,
            sessionName: name,
            lastOpenedAt: lastOpenedAt
        )
    }

    private func makeSession(
        server: SavedServer,
        workspace: SavedWorkspace,
        agentState: TmuxPaneAgentState = .idle
    ) -> ActiveTerminalSession {
        let auth = ResolvedSSHAuth.password(
            username: server.username,
            password: "test-password",
            identityID: server.identityID,
            displayLabel: server.displayName
        )
        return ActiveTerminalSession(
            target: TmuxConnectionTarget(
                server: server,
                workspace: workspace,
                sshAuth: auth
            ),
            runtimeState: .connected,
            agentState: agentState
        )
    }

    private func loadedDiscovery(_ names: [String]) -> TmuxSessionDiscoveryState {
        TmuxSessionDiscoveryState.idle.finishingRefresh(with: names)
    }

    private func makeServer(name: String) -> SavedServer {
        SavedServer(
            displayName: name,
            host: "\(name.lowercased().replacingOccurrences(of: " ", with: "-")).example.test",
            username: "tester",
            identityID: UUID()
        )
    }
}
