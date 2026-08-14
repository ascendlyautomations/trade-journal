import Foundation

/// Single source of truth for the app-icon badge: Activity unread + DM unread.
///
/// Matches server `countAppIconBadge` (Activity + Messages). Room unread is tracked
/// in the inbox UI but is not part of the APNs app-icon formula.
@MainActor
enum AppIconBadgeSync {
    static func refresh(animated: Bool = true) {
        let activity = ActivityInboxStore.shared.unreadCount
        let directMessages = MessagesInboxStore.shared.totalDirectMessageUnread
        AppIconBadgeController.shared.setBadge(activity + directMessages, animated: animated)
    }
}
