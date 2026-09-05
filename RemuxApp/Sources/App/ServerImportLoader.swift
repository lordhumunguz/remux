import Foundation

enum ServerImportError: Error, Equatable, LocalizedError {
    case unreadableSSHConfig
    case noImportableHosts
    case tailscaleUnavailable
    case tailscaleFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableSSHConfig:
            "The SSH config file could not be read."
        case .noImportableHosts:
            "No importable hosts were found."
        case .tailscaleUnavailable:
            "The Tailscale CLI is not installed on this Mac."
        case .tailscaleFailed(let detail):
            detail
        }
    }
}

/// Loads import candidates from on-disk sources. Parsing and mapping stay in
/// `SSHConfigFileParser` / `TailscaleStatusParser` / `ServerImportPlanner`;
/// this type only performs file and process I/O. Identity file contents are
/// never read — only their paths travel with the candidates.
enum ServerImportLoader {
    static func sshConfigCandidates(
        from url: URL,
        existingServers: [SavedServer],
        defaultUsername: String = NSUserName()
    ) throws -> [ServerImportCandidate] {
        let rootText: String
        do {
            rootText = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ServerImportError.unreadableSSHConfig
        }
        return try sshConfigCandidates(
            rootText: rootText,
            existingServers: existingServers,
            defaultUsername: defaultUsername
        )
    }

    static func sshConfigCandidates(
        rootText: String,
        existingServers: [SavedServer],
        defaultUsername: String = NSUserName()
    ) throws -> [ServerImportCandidate] {
        let homeDirectoryPath = NSHomeDirectory()
        let composed = SSHConfigFileComposer.compose(
            rootText: rootText,
            homeDirectoryPath: homeDirectoryPath
        ) { path in
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return try? String(contentsOfFile: path, encoding: .utf8)
        }
        let file = SSHConfigFileParser.parse(composed, homeDirectoryPath: homeDirectoryPath)
        let candidates = ServerImportPlanner.sshConfigCandidates(
            from: file,
            existingServers: existingServers,
            defaultUsername: defaultUsername
        )
        guard !candidates.isEmpty else {
            throw ServerImportError.noImportableHosts
        }
        return candidates
    }
}

#if os(macOS)
extension ServerImportLoader {
    static func defaultSSHConfigCandidates(
        existingServers: [SavedServer],
        defaultUsername: String = NSUserName()
    ) throws -> [ServerImportCandidate] {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".ssh/config")
        return try sshConfigCandidates(
            from: url,
            existingServers: existingServers,
            defaultUsername: defaultUsername
        )
    }

    static func tailscaleCandidates(
        existingServers: [SavedServer],
        defaultUsername: String = NSUserName()
    ) throws -> [ServerImportCandidate] {
        guard let cli = tailscaleCLIPath() else {
            throw ServerImportError.tailscaleUnavailable
        }
        let data = try runTailscaleStatus(cli: cli)
        let peers = try TailscaleStatusParser.parse(data: data)
        let candidates = ServerImportPlanner.tailscaleCandidates(
            from: peers,
            existingServers: existingServers,
            defaultUsername: defaultUsername
        )
        guard !candidates.isEmpty else {
            throw ServerImportError.noImportableHosts
        }
        return candidates
    }

    /// Mirrors the lookup in ~/.dotfiles/scripts/ios/ssh-mac.sh.
    private static func tailscaleCLIPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/tailscale",
            "/usr/local/bin/tailscale",
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        ]
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    private static func runTailscaleStatus(cli: String) throws -> Data {
        // A temp file rather than a Pipe: large tailnets can exceed the pipe
        // buffer, and a file lets the process finish without a reader.
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("remux-tailscale-status-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = ["status", "--json"]
        process.standardError = FileHandle.nullDevice
        do {
            let handle = try FileHandle(forWritingTo: outputURL)
            process.standardOutput = handle
            try process.run()
            process.waitUntilExit()
            try? handle.close()
        } catch {
            throw ServerImportError.tailscaleFailed("Tailscale status could not be run.")
        }
        guard process.terminationStatus == 0 else {
            throw ServerImportError.tailscaleFailed(
                "Tailscale status failed. Check that Tailscale is running."
            )
        }
        do {
            return try Data(contentsOf: outputURL)
        } catch {
            throw ServerImportError.tailscaleFailed("Tailscale status could not be read.")
        }
    }
}
#endif
