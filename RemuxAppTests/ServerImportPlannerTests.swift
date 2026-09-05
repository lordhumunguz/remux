import XCTest
@testable import Remux

final class ServerImportPlannerTests: XCTestCase {
    func testSSHConfigCandidatesMapHostsWithDefaults() {
        let file = SSHConfigFile(
            hosts: [
                SSHConfigHost(
                    alias: "macpro",
                    hostName: "100.64.0.1",
                    user: "fei",
                    port: 2222,
                    identityFile: "/Users/test/.ssh/id_ed25519"
                ),
                SSHConfigHost(
                    alias: "web",
                    hostName: "web",
                    user: nil,
                    port: nil,
                    identityFile: nil
                ),
            ]
        )

        let candidates = ServerImportPlanner.sshConfigCandidates(
            from: file,
            existingServers: [],
            defaultUsername: "localuser"
        )

        XCTAssertEqual(candidates.count, 2)

        let macpro = candidates[0]
        XCTAssertEqual(macpro.source, .sshConfig)
        XCTAssertEqual(macpro.displayName, "macpro")
        XCTAssertEqual(macpro.host, "100.64.0.1")
        XCTAssertEqual(macpro.port, 2222)
        XCTAssertEqual(macpro.username, "fei")
        XCTAssertEqual(
            macpro.auth,
            .privateKey(identityFile: "/Users/test/.ssh/id_ed25519")
        )
        XCTAssertFalse(macpro.isDuplicate)

        let web = candidates[1]
        XCTAssertEqual(web.port, 22)
        XCTAssertEqual(web.username, "localuser")
        XCTAssertEqual(web.auth, .unset)
    }

    func testSSHConfigCandidatesMarkDuplicatesCaseInsensitively() {
        let existing = SavedServer(
            displayName: "Existing",
            host: "Web.Example.Test",
            port: 22,
            username: "Deploy"
        )
        let file = SSHConfigFile(
            hosts: [
                SSHConfigHost(
                    alias: "web",
                    hostName: "web.example.test",
                    user: "deploy",
                    port: nil,
                    identityFile: nil
                ),
            ]
        )

        let candidates = ServerImportPlanner.sshConfigCandidates(
            from: file,
            existingServers: [existing],
            defaultUsername: "localuser"
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertTrue(candidates[0].isDuplicate)
    }

    func testSSHConfigCandidatesTreatDifferentPortOrUserAsDistinct() {
        let existing = SavedServer(
            displayName: "Existing",
            host: "web.example.test",
            port: 22,
            username: "deploy"
        )
        let file = SSHConfigFile(
            hosts: [
                SSHConfigHost(
                    alias: "web-alt-port",
                    hostName: "web.example.test",
                    user: "deploy",
                    port: 2222,
                    identityFile: nil
                ),
                SSHConfigHost(
                    alias: "web-alt-user",
                    hostName: "web.example.test",
                    user: "root",
                    port: nil,
                    identityFile: nil
                ),
            ]
        )

        let candidates = ServerImportPlanner.sshConfigCandidates(
            from: file,
            existingServers: [existing],
            defaultUsername: "localuser"
        )

        XCTAssertEqual(candidates.map(\.isDuplicate), [false, false])
    }

    func testSSHConfigCandidatesMarkInBatchDuplicatesCaseInsensitively() {
        let file = SSHConfigFile(
            hosts: [
                SSHConfigHost(
                    alias: "macpro",
                    hostName: "100.64.0.1",
                    user: "fei",
                    port: nil,
                    identityFile: nil
                ),
                SSHConfigHost(
                    alias: "macpro-alt",
                    hostName: "100.64.0.1",
                    user: "FEI",
                    port: nil,
                    identityFile: nil
                ),
                SSHConfigHost(
                    alias: "macpro-other-user",
                    hostName: "100.64.0.1",
                    user: "root",
                    port: nil,
                    identityFile: nil
                ),
            ]
        )

        let candidates = ServerImportPlanner.sshConfigCandidates(
            from: file,
            existingServers: [],
            defaultUsername: "localuser"
        )

        XCTAssertEqual(candidates.map(\.isDuplicate), [false, true, false])
    }

    func testTailscaleCandidatesKeepOnlinePeersWithTailscaleAuth() {
        let peers = [
            TailscalePeer(
                hostName: "feis-macbook-pro",
                dnsName: "feis-macbook-pro.tail1234.ts.net",
                os: "macOS",
                online: true,
                tailscaleIP: "100.64.0.1",
                userLoginName: "fei@github"
            ),
            TailscalePeer(
                hostName: "offline-box",
                dnsName: "offline-box.tail1234.ts.net",
                os: "linux",
                online: false,
                tailscaleIP: "100.64.0.2",
                userLoginName: nil
            ),
        ]

        let candidates = ServerImportPlanner.tailscaleCandidates(
            from: peers,
            existingServers: [],
            defaultUsername: "fei"
        )

        XCTAssertEqual(candidates.count, 1)
        let candidate = candidates[0]
        XCTAssertEqual(candidate.source, .tailscale)
        XCTAssertEqual(candidate.displayName, "feis-macbook-pro")
        XCTAssertEqual(candidate.host, "feis-macbook-pro.tail1234.ts.net")
        XCTAssertEqual(candidate.port, 22)
        XCTAssertEqual(candidate.username, "fei")
        XCTAssertEqual(candidate.auth, .tailscaleSSH)
        XCTAssertEqual(candidate.detail, "macOS · fei@github")
    }

    func testTailscaleCandidatesFallBackToIPAndSkipAddresslessPeers() {
        let peers = [
            TailscalePeer(
                hostName: "no-dns",
                dnsName: "",
                os: nil,
                online: true,
                tailscaleIP: "100.64.0.7",
                userLoginName: nil
            ),
            TailscalePeer(
                hostName: "no-address",
                dnsName: "",
                os: nil,
                online: true,
                tailscaleIP: nil,
                userLoginName: nil
            ),
        ]

        let candidates = ServerImportPlanner.tailscaleCandidates(
            from: peers,
            existingServers: [],
            defaultUsername: "fei"
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].host, "100.64.0.7")
        XCTAssertEqual(candidates[0].displayName, "no-dns")
        XCTAssertNil(candidates[0].detail)
    }

    func testTailscaleCandidatesMarkDuplicates() {
        let existing = SavedServer(
            displayName: "Existing",
            host: "feis-macbook-pro.tail1234.ts.net",
            port: 22,
            username: "fei"
        )
        let peers = [
            TailscalePeer(
                hostName: "feis-macbook-pro",
                dnsName: "feis-macbook-pro.tail1234.ts.net",
                os: "macOS",
                online: true,
                tailscaleIP: "100.64.0.1",
                userLoginName: nil
            ),
        ]

        let candidates = ServerImportPlanner.tailscaleCandidates(
            from: peers,
            existingServers: [existing],
            defaultUsername: "fei"
        )

        XCTAssertEqual(candidates.map(\.isDuplicate), [true])
    }

    func testMakeProfilesMapsAuthKindsAndLinksIdentity() {
        let candidates = [
            ServerImportCandidate(
                source: .sshConfig,
                displayName: "macpro",
                host: "100.64.0.1",
                port: 22,
                username: "fei",
                auth: .privateKey(identityFile: "/Users/test/.ssh/id_ed25519"),
                isDuplicate: false
            ),
            ServerImportCandidate(
                source: .tailscale,
                displayName: "macair",
                host: "macair.tail1234.ts.net",
                port: 22,
                username: "fei",
                auth: .tailscaleSSH,
                isDuplicate: false
            ),
            ServerImportCandidate(
                source: .sshConfig,
                displayName: "web",
                host: "web.example.test",
                port: 2200,
                username: "deploy",
                auth: .unset,
                isDuplicate: false
            ),
        ]

        let profiles = ServerImportPlanner.makeProfiles(for: candidates)

        XCTAssertEqual(profiles.count, 3)
        XCTAssertEqual(profiles.map(\.identity.authenticationKind), [.privateKey, .none, .password])
        for profile in profiles {
            XCTAssertEqual(profile.server.identityID, profile.identity.id)
            XCTAssertEqual(profile.identity.name, profile.server.displayName)
        }
        XCTAssertEqual(profiles[2].server.port, 2200)
        XCTAssertEqual(profiles[2].server.username, "deploy")
    }

    func testMakeProfilesSkipsDuplicates() {
        let candidates = [
            ServerImportCandidate(
                source: .sshConfig,
                displayName: "web",
                host: "web.example.test",
                port: 22,
                username: "deploy",
                auth: .unset,
                isDuplicate: true
            ),
        ]

        XCTAssertEqual(ServerImportPlanner.makeProfiles(for: candidates), [])
    }
}
