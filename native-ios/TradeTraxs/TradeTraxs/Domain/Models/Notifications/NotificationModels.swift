import Foundation

nonisolated enum ActivityNotificationKind: String, Hashable, Codable, Sendable {
    case like
    case comment
    case follow
    case followRequest
    case roomJoin
    case roomMention
    case message
    case achievement
    case affiliate
    case tradingReport
    case system
}

/// Inbox activity item. Named to avoid clashing with Foundation.Notification.
nonisolated struct ActivityNotification: Hashable, Codable, Sendable, Identifiable {
    var id: NotificationID
    var kind: ActivityNotificationKind
    var actorProfileID: ProfileID?
    var title: String
    var body: String
    var tradeID: TradeID?
    var postID: PostID?
    var conversationID: ConversationID?
    var roomID: RoomID?
    var createdAt: Date
    var isRead: Bool
}
