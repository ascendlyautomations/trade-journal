import Foundation

/// Mirrors web `NotificationPreferenceKey` / `notification_preferences` columns.
nonisolated enum NotificationPreferenceKey: String, Hashable, Codable, Sendable, CaseIterable {
    case notificationsEnabled = "notifications_enabled"
    case likesEnabled = "likes_enabled"
    case commentsEnabled = "comments_enabled"
    case repliesEnabled = "replies_enabled"
    case mentionsEnabled = "mentions_enabled"
    case reactionsEnabled = "reactions_enabled"
    case followersEnabled = "followers_enabled"
    case followRequestsEnabled = "follow_requests_enabled"
    case followRequestAcceptsEnabled = "follow_request_accepts_enabled"
    case directMessagesEnabled = "direct_messages_enabled"
    case storyRepliesEnabled = "story_replies_enabled"
    case sharesEnabled = "shares_enabled"
    case roomMessagesEnabled = "room_messages_enabled"
    case roomMentionsEnabled = "room_mentions_enabled"
    case roomJoinsEnabled = "room_joins_enabled"
    case achievementLikesEnabled = "achievement_likes_enabled"
    case achievementCommentsEnabled = "achievement_comments_enabled"
    case achievementUnlocksEnabled = "achievement_unlocks_enabled"
    case productUpdatesEnabled = "product_updates_enabled"
    case maintenanceEnabled = "maintenance_enabled"
    case announcementsEnabled = "announcements_enabled"
}

/// Persisted notification delivery preferences (`public.notification_preferences`).
nonisolated struct NotificationPreferences: Hashable, Codable, Sendable {
    var userID: ProfileID
    var values: [NotificationPreferenceKey: Bool]
    var updatedAt: Date?

    static func defaults(for userID: ProfileID) -> NotificationPreferences {
        var values: [NotificationPreferenceKey: Bool] = [:]
        for key in NotificationPreferenceKey.allCases {
            values[key] = true
        }
        return NotificationPreferences(userID: userID, values: values, updatedAt: nil)
    }

    func isEnabled(_ key: NotificationPreferenceKey) -> Bool {
        if key != .notificationsEnabled, values[.notificationsEnabled] == false {
            return false
        }
        return values[key] ?? true
    }

    mutating func set(_ key: NotificationPreferenceKey, enabled: Bool) {
        values[key] = enabled
    }
}

/// Logical grouping for Settings → Notifications hierarchy.
nonisolated enum NotificationPreferenceCategory: String, Hashable, Codable, Sendable, CaseIterable {
    case master
    case messages
    case social
    case rooms
    case achievements
    case product

    var title: String {
        switch self {
        case .master: return "Push Notifications"
        case .messages: return "Messages"
        case .social: return "Social Activity"
        case .rooms: return "Trade Rooms"
        case .achievements: return "Achievements"
        case .product: return "Product Updates"
        }
    }

    var settingsRoute: SettingsRoute? {
        switch self {
        case .master: return nil
        case .messages: return .notificationsMessages
        case .social: return .notificationsSocial
        case .rooms: return .notificationsRooms
        case .achievements: return .notificationsAchievements
        case .product: return .notificationsProduct
        }
    }

    var keys: [NotificationPreferenceKey] {
        switch self {
        case .master:
            return [.notificationsEnabled]
        case .messages:
            return [.directMessagesEnabled, .storyRepliesEnabled, .sharesEnabled]
        case .social:
            return [
                .likesEnabled,
                .commentsEnabled,
                .repliesEnabled,
                .mentionsEnabled,
                .reactionsEnabled,
                .followersEnabled,
                .followRequestsEnabled,
                .followRequestAcceptsEnabled,
            ]
        case .rooms:
            return [.roomMessagesEnabled, .roomMentionsEnabled, .roomJoinsEnabled]
        case .achievements:
            return [
                .achievementLikesEnabled,
                .achievementCommentsEnabled,
                .achievementUnlocksEnabled,
            ]
        case .product:
            return [.productUpdatesEnabled, .maintenanceEnabled, .announcementsEnabled]
        }
    }
}

extension NotificationPreferenceKey {
    var title: String {
        switch self {
        case .notificationsEnabled: return "Allow Notifications"
        case .likesEnabled: return "Likes"
        case .commentsEnabled: return "Comments"
        case .repliesEnabled: return "Replies"
        case .mentionsEnabled: return "Mentions"
        case .reactionsEnabled: return "Reactions"
        case .followersEnabled: return "New Followers"
        case .followRequestsEnabled: return "Follow Requests"
        case .followRequestAcceptsEnabled: return "Accepted Follow Requests"
        case .directMessagesEnabled: return "Direct Messages"
        case .storyRepliesEnabled: return "Story Replies"
        case .sharesEnabled: return "Shares"
        case .roomMessagesEnabled: return "Room Messages"
        case .roomMentionsEnabled: return "Room Mentions"
        case .roomJoinsEnabled: return "Room Joins"
        case .achievementLikesEnabled: return "Achievement Likes"
        case .achievementCommentsEnabled: return "Achievement Comments"
        case .achievementUnlocksEnabled: return "Achievement Unlocks"
        case .productUpdatesEnabled: return "Product Updates"
        case .maintenanceEnabled: return "Maintenance"
        case .announcementsEnabled: return "Announcements"
        }
    }

    /// Short helper shown under the toggle title.
    var subtitle: String? {
        switch self {
        case .notificationsEnabled:
            return "Turns all TradeTraxs notifications on or off"
        case .likesEnabled:
            return "When someone likes your posts or trades"
        case .commentsEnabled:
            return "When someone comments on your content"
        case .repliesEnabled:
            return "When someone replies to your comments"
        case .mentionsEnabled:
            return "When someone mentions you"
        case .reactionsEnabled:
            return "When someone reacts to your messages"
        case .followersEnabled:
            return "When someone starts following you"
        case .followRequestsEnabled:
            return "When someone requests to follow your private profile"
        case .followRequestAcceptsEnabled:
            return "When your follow request is accepted"
        case .directMessagesEnabled:
            return "New direct messages"
        case .storyRepliesEnabled:
            return "Replies to your stories"
        case .sharesEnabled:
            return "When someone shares content with you"
        case .roomMessagesEnabled:
            return "New messages in trade rooms you belong to"
        case .roomMentionsEnabled:
            return "When you’re mentioned in a trade room"
        case .roomJoinsEnabled:
            return "When someone joins a room you own"
        case .achievementLikesEnabled:
            return "Likes on your achievements"
        case .achievementCommentsEnabled:
            return "Comments on your achievements"
        case .achievementUnlocksEnabled:
            return "When you unlock a new achievement"
        case .productUpdatesEnabled:
            return "New features and product news"
        case .maintenanceEnabled:
            return "Planned downtime and service notices"
        case .announcementsEnabled:
            return "Important TradeTraxs announcements"
        }
    }
}

extension NotificationPreferenceCategory {
    var sectionFooter: String {
        switch self {
        case .master:
            return "Choose which notifications you’d like to receive."
        case .messages:
            return "Alerts for direct messages, story replies, and shares."
        case .social:
            return "Activity on your posts, profile, and follows."
        case .rooms:
            return "Updates from trade rooms you’re in."
        case .achievements:
            return "Activity related to achievements."
        case .product:
            return "News and notices from TradeTraxs."
        }
    }
}
