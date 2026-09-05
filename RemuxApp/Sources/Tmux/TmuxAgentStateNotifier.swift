import Foundation
import UserNotifications

/// Boundary for the "agent blocked" alert so the tmux session stack stays
/// testable without a notification center.
protocol TmuxAgentStateNotifying: Sendable {
    func notifyAgentBlocked(_ notification: TmuxAgentBlockedNotification)
    /// Drops the banner for a pane that is no longer blocked or whose
    /// session went away.
    func clearAgentBlocked(sessionName: String, paneID: TmuxPaneID)
}

/// Posts one local notification per blocked episode. Authorization is
/// requested lazily on the first alert; a denied or undetermined status
/// simply drops that alert.
struct TmuxAgentStateNotifier: TmuxAgentStateNotifying {
    static let shared = TmuxAgentStateNotifier()

    private static let categoryIdentifier = "remux.agent-blocked"

    /// Pane IDs are per-server, so the session scopes the identifier;
    /// without it the same pane on two servers would share one banner.
    static func identifier(sessionName: String, paneID: TmuxPaneID) -> String {
        "\(categoryIdentifier).\(sessionName).\(paneID.rawValue)"
    }

    func notifyAgentBlocked(_ notification: TmuxAgentBlockedNotification) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Agent needs your input"
            content.body = Self.body(for: notification)
            content.sound = .default
            content.threadIdentifier = notification.sessionName
            let request = UNNotificationRequest(
                identifier: Self.identifier(
                    sessionName: notification.sessionName,
                    paneID: notification.paneID
                ),
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

    func clearAgentBlocked(sessionName: String, paneID: TmuxPaneID) {
        let identifier = Self.identifier(sessionName: sessionName, paneID: paneID)
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    private static func body(for notification: TmuxAgentBlockedNotification) -> String {
        let command = notification.currentCommand
        let location = notification.currentPath.isEmpty
            ? notification.sessionName
            : "\(notification.sessionName) · \(notification.currentPath)"
        return command.isEmpty
            ? "\(location) is waiting on a permission prompt."
            : "\(location): \(command) is waiting on a permission prompt."
    }
}

/// Shows the blocked-agent alerts even while the app is foreground, which is
/// the "user is viewing a different pane" case. The session stack only posts
/// an alert the user is not already looking at.
final class RemuxUserNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = RemuxUserNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
