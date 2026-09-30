import Foundation

enum ByronProfile: String, CaseIterable, Identifiable, Sendable {
    case work = "work"
    case personal = "personal"
    case muse = "muse"
    case grok = "grok"
    case claude = "claude"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .work: "Claude (work)"
        case .personal: "Claude (personal)"
        case .muse: "Muse (Codestral)"
        case .grok: "Grok (xAI)"
        case .claude: "Claude (default)"
        }
    }

    var shortLabel: String {
        switch self {
        case .work: "work"
        case .personal: "personal"
        case .muse: "muse"
        case .grok: "grok"
        case .claude: "claude"
        }
    }

    /// Typed into the pane's shell. These are the dotfiles launchers, not
    /// Byron CLI subcommands: bare `byron` is the usage report, and `byron`
    /// has no `c`, `muse`, or `grok` commands. `c` is Codex; Claude is `cc`.
    var command: String {
        switch self {
        case .work: "cc work"
        case .personal: "cc personal"
        case .muse: "muse"
        case .grok: "grok"
        case .claude: "cc"
        }
    }

    var executionLine: String {
        "\(command)\n"
    }
}

enum ByronLaunchAction: String, CaseIterable, Identifiable, Sendable {
    case inCurrentPane
    case splitRight
    case splitDown
    case newWindow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inCurrentPane: "Run in Current Pane"
        case .splitRight: "Split Right & Run"
        case .splitDown: "Split Down & Run"
        case .newWindow: "New Window & Run"
        }
    }
}
