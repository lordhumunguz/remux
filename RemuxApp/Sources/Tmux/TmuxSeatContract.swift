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

    static func classify(exitDetail: String?) -> ExitClassification {
        guard let detail = exitDetail?.trimmingCharacters(in: .whitespacesAndNewlines),
              !detail.isEmpty
        else {
            // A bare %exit is how a detach arrives on servers that do not
            // send a reason; on a single-seat setup that is the common case.
            // Re-attaching is still safe when the session did die: the
            // attach command recreates it.
            return .seatTaken
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
