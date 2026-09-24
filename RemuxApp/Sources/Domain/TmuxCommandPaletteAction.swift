import Foundation

enum TmuxCommandPaletteCategory: String, CaseIterable, Sendable {
    case sessionAndServer = "Session & Server"
    case windowAndLayout = "Window & Layout"
    case byronAgents = "Byron Agents"
}

enum TmuxCommandPaletteAction: String, CaseIterable, Identifiable, Sendable {
    case saveSession
    case restoreSession
    case reloadConfig
    case toggleAccordion
    case toggleStatusBar
    case newWindow
    case splitRight
    case splitDown
    case toggleZoom
    case copyMode
    case closePane
    case clearScrollback
    case byronClaude
    case byronWork
    case byronPersonal
    case byronMuse
    case byronGrok
    case resumeAgent
    case jumpToBlockedAgent

    var id: String { rawValue }

    var category: TmuxCommandPaletteCategory {
        switch self {
        case .saveSession, .restoreSession, .reloadConfig, .toggleAccordion, .toggleStatusBar:
            .sessionAndServer
        case .newWindow, .splitRight, .splitDown, .toggleZoom, .copyMode, .closePane, .clearScrollback:
            .windowAndLayout
        case .byronClaude, .byronWork, .byronPersonal, .byronMuse, .byronGrok, .resumeAgent, .jumpToBlockedAgent:
            .byronAgents
        }
    }

    var title: String {
        switch self {
        case .saveSession: "Save Tmux Session"
        case .restoreSession: "Restore Tmux Session"
        case .reloadConfig: "Reload Config"
        case .toggleAccordion: "Toggle Responsive Accordion"
        case .toggleStatusBar: "Toggle Status Bar"
        case .newWindow: "New Window"
        case .splitRight: "Split Pane Right"
        case .splitDown: "Split Pane Down"
        case .toggleZoom: "Toggle Pane Zoom"
        case .copyMode: "Enter Copy Mode"
        case .closePane: "Close Current Pane"
        case .clearScrollback: "Clear Screen"
        case .byronClaude: "Launch Claude (default)"
        case .byronWork: "Launch Claude (work)"
        case .byronPersonal: "Launch Claude (personal)"
        case .byronMuse: "Launch Muse (Codestral)"
        case .byronGrok: "Launch Grok (xAI)"
        case .resumeAgent: "Resume Waiting Agent"
        case .jumpToBlockedAgent: "Jump to Blocked Agent"
        }
    }

    var subtitle: String {
        switch self {
        case .saveSession: "Run tmux-async-save.sh"
        case .restoreSession: "Run tmux-resurrect restore"
        case .reloadConfig: "source-file ~/.tmux.conf"
        case .toggleAccordion: "Switch single-pane focus accordion"
        case .toggleStatusBar: "set-option -g status"
        case .newWindow: "Create fresh tmux window"
        case .splitRight: "Split pane horizontally to the right"
        case .splitDown: "Split pane vertically downwards"
        case .toggleZoom: "Maximize or unmaximize focused pane"
        case .copyMode: "Inspect scrollback history in copy mode"
        case .closePane: "Kill current active pane"
        case .clearScrollback: "Clear terminal buffer"
        case .byronClaude: "byron"
        case .byronWork: "byron c work"
        case .byronPersonal: "byron c personal"
        case .byronMuse: "byron muse"
        case .byronGrok: "byron grok"
        case .resumeAgent: "Send newline / resume waiting agent"
        case .jumpToBlockedAgent: "Focus pane requiring user confirmation"
        }
    }

    var systemImage: String {
        switch self {
        case .saveSession: "arrow.down.doc.fill"
        case .restoreSession: "arrow.clockwise.circle.fill"
        case .reloadConfig: "arrow.triangle.2.circlepath"
        case .toggleAccordion: "arrow.left.and.right.square"
        case .toggleStatusBar: "menubar.rectangle"
        case .newWindow: "plus.rectangle.on.rectangle"
        case .splitRight: "square.split.2x1"
        case .splitDown: "square.split.1x2"
        case .toggleZoom: "arrow.up.left.and.arrow.down.right"
        case .copyMode: "text.magnifyingglass"
        case .closePane: "xmark.circle"
        case .clearScrollback: "trash"
        case .byronClaude: "sparkles"
        case .byronWork: "briefcase.fill"
        case .byronPersonal: "person.fill"
        case .byronMuse: "brain"
        case .byronGrok: "bolt.fill"
        case .resumeAgent: "play.circle.fill"
        case .jumpToBlockedAgent: "exclamationmark.triangle.fill"
        }
    }

    var shortcutHint: String? {
        switch self {
        case .newWindow: "⌘T"
        case .splitRight: "⌘D"
        case .splitDown: "⇧⌘D"
        case .toggleZoom: "⌘Z"
        case .closePane: "⌘W"
        case .clearScrollback: "⌘K"
        case .resumeAgent: "⌘R"
        case .jumpToBlockedAgent: "⌘J"
        default: nil
        }
    }

    var serverCommand: String? {
        switch self {
        case .saveSession:
            "run-shell ~/.dotfiles/scripts/tmux/tmux-async-save.sh"
        case .restoreSession:
            "run-shell ~/.tmux/plugins/tmux-resurrect/scripts/restore.sh"
        case .reloadConfig:
            "source-file ~/.tmux.conf"
        case .toggleAccordion:
            "if-shell -F \"#{==:#{@responsive_accordion},on}\" \"set -g @responsive_accordion off\" \"set -g @responsive_accordion on\""
        case .toggleStatusBar:
            "set-option -g status"
        default:
            nil
        }
    }

    var byronProfile: ByronProfile? {
        switch self {
        case .byronClaude: .claude
        case .byronWork: .work
        case .byronPersonal: .personal
        case .byronMuse: .muse
        case .byronGrok: .grok
        default: nil
        }
    }

    func matches(query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return true }
        return title.lowercased().contains(trimmed)
            || subtitle.lowercased().contains(trimmed)
            || category.rawValue.lowercased().contains(trimmed)
            || (shortcutHint?.lowercased().contains(trimmed) ?? false)
    }
}
