import SwiftUI

/// A coding-agent CLI that can run inside a tmux pane, detected from the
/// pane's current command. Glyphs and accent colors mirror the user's
/// byron agent registry (byron/agent_tools.py); goose has no registry entry
/// and uses a distinct pentagon glyph of its own.
enum AgentIdentity: String, CaseIterable, Equatable, Sendable {
    case claudeCode = "claude_code"
    case codex = "codex"
    case opencode = "opencode"
    case kimiCode = "kimi_code"
    case grok = "grok_build"
    case goose = "goose"
    case cursor = "cursor"
    case antigravity = "antigravity"
    case museCode = "muse_code"

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .opencode: "OpenCode"
        case .kimiCode: "Kimi Code"
        case .grok: "Grok"
        case .goose: "Goose"
        case .cursor: "Cursor"
        case .antigravity: "Antigravity"
        case .museCode: "Muse Code"
        }
    }

    var glyph: String {
        switch self {
        case .claudeCode: "✦"
        case .codex: "⬢"
        case .opencode: "❯"
        case .kimiCode: "☾"
        case .grok: "𝕏"
        case .goose: "⬟"
        case .cursor: "⌖"
        case .antigravity: "▲"
        case .museCode: "◈"
        }
    }

    /// Resume command for a pane where the agent exited back to a shell.
    /// Cursor, Antigravity, and Goose have no resume flow.
    var resumeCommand: String? {
        switch self {
        case .claudeCode: "claude --resume"
        case .codex: "codex resume"
        case .opencode: "opencode --continue"
        case .kimiCode: "kimi -S"
        case .grok: "grok --resume"
        case .museCode: "muse resume"
        case .goose, .cursor, .antigravity: nil
        }
    }

    var accent: Color {
        Color(
            red: accentRGB.red,
            green: accentRGB.green,
            blue: accentRGB.blue
        )
    }

    /// xterm 256-palette index carried over from the byron registry.
    var accentXtermIndex: Int {
        switch self {
        case .claudeCode: 216
        case .codex: 42
        case .opencode: 141
        case .kimiCode: 75
        case .grok: 250
        case .goose: 220
        case .cursor: 51
        case .antigravity: 39
        case .museCode: 213
        }
    }

    var accentRGB: (red: Double, green: Double, blue: Double) {
        Self.xterm256RGB(accentXtermIndex)
    }

    static func xterm256RGB(_ index: Int) -> (red: Double, green: Double, blue: Double) {
        switch index {
        case 16...231:
            let levels: [Double] = [0, 95, 135, 175, 215, 255]
            let value = index - 16
            let red = levels[value / 36]
            let green = levels[(value % 36) / 6]
            let blue = levels[value % 6]
            return (red / 255, green / 255, blue / 255)
        case 232...255:
            let level = Double(8 + (index - 232) * 10) / 255
            return (level, level, level)
        default:
            return (1, 1, 1)
        }
    }
}

/// Maps a pane's current command to the coding agent running in it, if any.
/// Substring matching on the lowercased command keeps version-suffixed
/// wrappers (e.g. `claude-2.1`, `kimi2`) detectable, mirroring cockpit's
/// pane-sync detection.
enum AgentDetection {
    static func agent(forCommand command: String) -> AgentIdentity? {
        let cmd = command.lowercased()
        if cmd.contains("claude") { return .claudeCode }
        if cmd.contains("codex") { return .codex }
        if cmd.contains("opencode") { return .opencode }
        if cmd.contains("kimi") { return .kimiCode }
        if cmd.contains("grok") { return .grok }
        if cmd.contains("goose") { return .goose }
        if cmd.contains("cursor") { return .cursor }
        if cmd.contains("muse") { return .museCode }
        if cmd.contains("gemini") || cmd.contains("antigravity") { return .antigravity }
        return nil
    }
}

/// Picks the next window (after the current one, wrapping) whose panes
/// include a detected agent, mirroring the user's `Alt+a` tmux binding in
/// spirit: cycle through agent windows, not unread state.
enum AgentWindowCycle {
    static func nextAgentWindowIndex(
        hasAgentByWindow: [Bool],
        currentIndex: Int?
    ) -> Int? {
        guard !hasAgentByWindow.isEmpty else { return nil }
        let start = ((currentIndex ?? -1) + 1 + hasAgentByWindow.count)
            % hasAgentByWindow.count
        for offset in 0..<hasAgentByWindow.count {
            let index = (start + offset) % hasAgentByWindow.count
            if hasAgentByWindow[index] { return index }
        }
        return nil
    }
}
