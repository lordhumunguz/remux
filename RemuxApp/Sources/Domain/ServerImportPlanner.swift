import Foundation

enum ServerImportSource: String, Equatable, Sendable {
    case sshConfig
    case tailscale
}

struct ServerImportCandidate: Identifiable, Equatable, Sendable {
    enum Auth: Equatable, Sendable {
        /// The ssh config named an identity file. Only its path is carried;
        /// key material is never read by import, so the user attaches the key
        /// in server setup afterwards.
        case privateKey(identityFile: String)
        /// Authenticate with SSH `none`, as expected by Tailscale SSH.
        case tailscaleSSH
        /// No credential information was available; the user completes
        /// authentication in server setup, which verifies before saving.
        case unset
    }

    let id: UUID
    let source: ServerImportSource
    let displayName: String
    let host: String
    let port: Int
    let username: String
    let auth: Auth
    let detail: String?
    let isDuplicate: Bool

    init(
        id: UUID = UUID(),
        source: ServerImportSource,
        displayName: String,
        host: String,
        port: Int,
        username: String,
        auth: Auth,
        detail: String? = nil,
        isDuplicate: Bool
    ) {
        self.id = id
        self.source = source
        self.displayName = displayName
        self.host = host
        self.port = port
        self.username = username
        self.auth = auth
        self.detail = detail
        self.isDuplicate = isDuplicate
    }
}

struct ImportedServerProfile: Equatable, Sendable {
    let server: SavedServer
    let identity: SSHIdentity
}

/// Maps parsed ssh-config hosts and Tailscale peers into import candidates.
/// A candidate is a duplicate when an existing profile or an earlier
/// candidate in the same batch already matches its host, port, and username
/// (compared case-insensitively); duplicates stay visible in the picker but
/// can neither be selected nor imported.
enum ServerImportPlanner {
    static func sshConfigCandidates(
        from file: SSHConfigFile,
        existingServers: [SavedServer],
        defaultUsername: String
    ) -> [ServerImportCandidate] {
        var batchKeys = Set<String>()
        return file.hosts.map { host in
            let username = host.user ?? defaultUsername
            let port = host.port ?? 22
            let isBatchDuplicate = !batchKeys.insert(
                duplicateKey(host: host.hostName, port: port, username: username)
            ).inserted
            return ServerImportCandidate(
                source: .sshConfig,
                displayName: host.alias,
                host: host.hostName,
                port: port,
                username: username,
                auth: host.identityFile.map { .privateKey(identityFile: $0) } ?? .unset,
                isDuplicate: isBatchDuplicate || isDuplicate(
                    host: host.hostName,
                    port: port,
                    username: username,
                    in: existingServers
                )
            )
        }
    }

    static func tailscaleCandidates(
        from peers: [TailscalePeer],
        existingServers: [SavedServer],
        defaultUsername: String
    ) -> [ServerImportCandidate] {
        var batchKeys = Set<String>()
        return peers
            .filter { $0.online }
            .compactMap { peer in
                let host = !peer.dnsName.isEmpty ? peer.dnsName : peer.tailscaleIP
                guard let host, !host.isEmpty else { return nil }
                let detail = [peer.os, peer.userLoginName]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                let isBatchDuplicate = !batchKeys.insert(
                    duplicateKey(host: host, port: 22, username: defaultUsername)
                ).inserted
                return ServerImportCandidate(
                    source: .tailscale,
                    displayName: !peer.hostName.isEmpty ? peer.hostName : host,
                    host: host,
                    port: 22,
                    username: defaultUsername,
                    auth: .tailscaleSSH,
                    detail: detail.isEmpty ? nil : detail,
                    isDuplicate: isBatchDuplicate || isDuplicate(
                        host: host,
                        port: 22,
                        username: defaultUsername,
                        in: existingServers
                    )
                )
            }
    }

    /// Builds repository-ready profiles for the selected candidates.
    /// Duplicates are skipped even if they were passed in, and no credentials
    /// are stored: private-key and unset identities are completed in server
    /// setup, while Tailscale SSH needs no stored credential.
    static func makeProfiles(
        for candidates: [ServerImportCandidate]
    ) -> [ImportedServerProfile] {
        candidates
            .filter { !$0.isDuplicate }
            .map { candidate in
                let authenticationKind: SSHAuthenticationKind
                switch candidate.auth {
                case .privateKey:
                    authenticationKind = .privateKey
                case .tailscaleSSH:
                    authenticationKind = .none
                case .unset:
                    authenticationKind = .password
                }
                let identity = SSHIdentity(
                    name: candidate.displayName,
                    authenticationKind: authenticationKind
                )
                let server = SavedServer(
                    displayName: candidate.displayName,
                    host: candidate.host,
                    port: candidate.port,
                    username: candidate.username,
                    identityID: identity.id
                )
                return ImportedServerProfile(server: server, identity: identity)
            }
    }

    private static func isDuplicate(
        host: String,
        port: Int,
        username: String,
        in existingServers: [SavedServer]
    ) -> Bool {
        existingServers.contains { server in
            server.host.caseInsensitiveCompare(host) == .orderedSame &&
                server.port == port &&
                server.username.caseInsensitiveCompare(username) == .orderedSame
        }
    }

    private static func duplicateKey(host: String, port: Int, username: String) -> String {
        "\(host.lowercased())\u{1F}\(port)\u{1F}\(username.lowercased())"
    }
}
