import Foundation
import UIKit

enum GhosttyHardwareShortcut: Equatable, Sendable {
    case newWindow
    case splitPaneRight
    case splitPaneDown
    case closePane
    case previousWindow
    case nextWindow
    case selectWindow(Int)
    case toggleZoom
    case showSessions
    case resumeAgent
    case jumpToBlockedAgent
    case toggleComposer
    case clearScreen
    case showCommandPalette
}

enum GhosttyHardwareKeyCommandFactory {
    @MainActor
    static func makeCommands(action: Selector) -> [UIKeyCommand] {
        var commands: [UIKeyCommand] = [
            UIKeyCommand(
                title: "Command Palette",
                action: action,
                input: "p",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: "New Window",
                action: action,
                input: "t",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: "Split Pane Right",
                action: action,
                input: "d",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: "Split Pane Down",
                action: action,
                input: "d",
                modifierFlags: [.command, .shift]
            ),
            UIKeyCommand(
                title: "Close Pane",
                action: action,
                input: "w",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: "Previous Window",
                action: action,
                input: "[",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: "Next Window",
                action: action,
                input: "]",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: "Toggle Zoom",
                action: action,
                input: "z",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: "Switch Session",
                action: action,
                input: "o",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: "Resume Agent",
                action: action,
                input: "r",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: "Jump to Blocked Agent",
                action: action,
                input: "j",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: "Toggle Composer",
                action: action,
                input: "e",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: "Clear Screen",
                action: action,
                input: "k",
                modifierFlags: .command
            ),
        ]

        for i in 1...9 {
            commands.append(
                UIKeyCommand(
                    title: "Window \(i)",
                    action: action,
                    input: "\(i)",
                    modifierFlags: .command
                )
            )
        }

        return commands
    }

    static func resolve(input: String?, modifierFlags: UIKeyModifierFlags) -> GhosttyHardwareShortcut? {
        guard let input else { return nil }

        if modifierFlags == [.command, .shift] && input.lowercased() == "d" {
            return .splitPaneDown
        }

        guard modifierFlags == .command else { return nil }

        switch input.lowercased() {
        case "t": return .newWindow
        case "d": return .splitPaneRight
        case "w": return .closePane
        case "[": return .previousWindow
        case "]": return .nextWindow
        case "z": return .toggleZoom
        case "o": return .showSessions
        case "r": return .resumeAgent
        case "j": return .jumpToBlockedAgent
        case "e": return .toggleComposer
        case "k": return .clearScreen
        case "p": return .showCommandPalette
        case "1"..."9":
            if let num = Int(input) {
                return .selectWindow(num - 1)
            }
            return nil
        default:
            return nil
        }
    }
}
