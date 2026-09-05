import Foundation

/// Single-seat contract shared with tmux setups that enforce one attached
/// viewer per session (a new viewer detaches the previous one, which then
/// waits for deliberate input to take the seat back).
enum TmuxSeatContract {
    /// What a tmux `%exit` line means for the seat. tmux sends `%exit` with
    /// no detail on this server's version (next-3.8) for every teardown
    /// path, while newer builds append a reason such as
    /// `detached (from session main)`.
    enum ExitClassification: Equatable, Sendable {
        /// The control client was detached while the session lives on;
        /// re-attaching is the deliberate way to take the seat back.
        case seatTaken
        /// The server or session actually went away.
        case serverExited
    }

    /// Probe for the seat convention: dotfiles that enforce one attached
    /// viewer hook `client-attached` to detach the previous client.
    static let showHooksCommand = "show-hooks -g client-attached"

    /// Reads `show-hooks -g client-attached` output: the seat contract is in
    /// force when the hook hands attachments to `detach-client`.
    static func detectsSeatContract(showHooksOutput: String) -> Bool {
        showHooksOutput.contains("detach-client")
    }

    /// `seatContractDetected` is the per-attachment result of the hook
    /// probe. A bare `%exit` only means "detached by another viewer" when
    /// the hook is present; on plain servers the same line also reports
    /// kill-session/kill-server, so unknown or failed probes read as a real
    /// exit. An explicit `detached…` reason is always a taken seat.
    static func classify(
        exitDetail: String?,
        seatContractDetected: Bool
    ) -> ExitClassification {
        guard let detail = exitDetail?.trimmingCharacters(in: .whitespacesAndNewlines),
              !detail.isEmpty
        else {
            // A bare %exit is how a detach arrives on servers that do not
            // send a reason. Re-attaching is still safe when the session
            // did die on a seat-contract server: the attach recreates it.
            return seatContractDetected ? .seatTaken : .serverExited
        }
        if detail.lowercased().hasPrefix("detached") {
            return .seatTaken
        }
        return .serverExited
    }

    /// Parses `list-clients -F '#{client_control_mode}'` output: one line per
    /// attached client, `1` for control-mode clients like Remux itself and
    /// `0` for interactive viewers. Any interactive viewer holds the seat.
    static func hasInteractiveViewer(listClientsOutput: String) -> Bool {
        listClientsOutput
            .split(whereSeparator: \.isNewline)
            .contains { $0.trimmingCharacters(in: .whitespaces) == "0" }
    }
}
