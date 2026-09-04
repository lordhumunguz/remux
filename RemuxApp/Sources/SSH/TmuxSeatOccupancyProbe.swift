import Foundation

/// Pre-attach probe: does an interactive (non-control) client currently view
/// the target tmux session? Runs through an ordinary SSH exec channel like
/// session discovery, never the control channel. Every failure mode (no
/// server, no such session, tmux missing, transport error) reads as "not
/// occupied" so a failed probe never blocks connecting.
enum TmuxSeatOccupancyProbe {
    static func probe(
        using claimedRoot: RemuxSSHClaimedRoot,
        tmuxExecutable: String,
        sessionName: String,
        trace: RemuxTransportStartupTrace
    ) async throws -> Bool {
        let result = try await RemuxSSHExecSession.run(
            using: claimedRoot,
            command: SSHTmuxControlCommandBuilder.seatOccupancyCommand(
                tmuxExecutable: tmuxExecutable,
                sessionName: sessionName
            ),
            stdin: nil,
            trace: trace
        )
        return isOccupied(result)
    }

    static func isOccupied(_ result: RemuxSSHExecResult) -> Bool {
        guard result.exitStatus == 0,
              let text = String(data: result.stdout, encoding: .utf8)
        else { return false }
        return TmuxSeatContract.hasInteractiveViewer(listClientsOutput: text)
    }
}
