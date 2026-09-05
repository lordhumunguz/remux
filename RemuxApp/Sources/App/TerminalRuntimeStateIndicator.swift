import SwiftUI

struct TerminalRuntimeStateIndicator: View {
    let state: TerminalRuntimeState

    private var presentation: TerminalRuntimeStatusPresentation {
        TerminalRuntimeStatusPresentation.projection(for: state)
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(presentation.label)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch presentation.tone {
        case .connecting:
            Color(uiColor: .remuxConnectingStatus)
        case .reconnecting:
            Color(uiColor: .remuxReconnectingStatus)
        case .connected:
            Color(uiColor: .remuxConnectedStatus)
        case .disconnected:
            Color(uiColor: .remuxDisconnectedStatus)
        }
    }
}

private extension UIColor {
    // Dark variants are Tokyo Night's semantic colors: blue #7aa2f7,
    // amber #e0af68, green #9ece6a, red #f7768e.
    static let remuxConnectingStatus = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            UIColor(red: 0.478, green: 0.635, blue: 0.969, alpha: 1.0)
        default:
            .systemBlue
        }
    }

    static let remuxReconnectingStatus = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            UIColor(red: 0.878, green: 0.686, blue: 0.408, alpha: 1.0)
        default:
            .systemOrange
        }
    }

    static let remuxConnectedStatus = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            UIColor(red: 0.620, green: 0.808, blue: 0.416, alpha: 1.0)
        default:
            .systemGreen
        }
    }

    static let remuxDisconnectedStatus = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            UIColor(red: 0.969, green: 0.463, blue: 0.557, alpha: 1.0)
        default:
            .systemRed
        }
    }
}
