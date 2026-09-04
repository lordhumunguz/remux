import Foundation

/// Server-side responsive-layout conventions used by some tmux
/// configurations (e.g. dotfiles that grow the focused pane themselves when
/// the client is narrow). All probes tolerate servers without those
/// conventions: a missing option or a failed query simply means "not
/// enabled" and Remux keeps its own behavior.
enum TmuxResponsiveAccordion {
    static let optionName = "@responsive_accordion"
    static let showOptionCommand = "show-option -gv \(optionName)"

    /// The server hook checks the option for the literal value `on`; any
    /// other value (or a missing option) leaves Remux's own zoom policy in
    /// charge.
    static func isEnabled(showOptionOutput: String) -> Bool {
        showOptionOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "on"
    }
}
