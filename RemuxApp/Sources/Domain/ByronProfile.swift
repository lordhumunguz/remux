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

    var command: String {
        switch self {
        case .work: "byron c work"
        case .personal: "byron c personal"
        case .muse: "byron muse"
        case .grok: "byron grok"
        case .claude: "byron"
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
