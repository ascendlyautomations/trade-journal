import Foundation

/// Inbox types mirrored from web `NOTIFICATION_INBOX_TYPES`.
nonisolated enum NotificationInboxType {
    static let all: [String] = [
        "like",
        "comment",
        "room_join",
        "room_mention",
        "follow",
        "follow_request",
        "follow_request_accepted",
        "affiliate_referral",
        "affiliate_commission_earned",
        "trading_report",
    ]

    static let set = Set(all)
}

/// Persisted `notifications.type` values that appear in Activity.
nonisolated enum ActivityNotificationKind: String, Hashable, Codable, Sendable {
    case like
    case comment
    case follow
    case followRequest = "follow_request"
    case followRequestAccepted = "follow_request_accepted"
    case roomJoin = "room_join"
    case roomMention = "room_mention"
    case affiliateReferral = "affiliate_referral"
    case affiliateCommissionEarned = "affiliate_commission_earned"
    case tradingReport = "trading_report"
    /// Messaging-only / legacy — excluded from Activity inbox queries.
    case message
    case system

    var isInboxType: Bool {
        NotificationInboxType.set.contains(rawValue)
    }

    static func parse(_ raw: String?) -> ActivityNotificationKind {
        guard let raw, !raw.isEmpty else { return .system }
        if let exact = ActivityNotificationKind(rawValue: raw) { return exact }
        // Legacy camelCase from earlier native stubs.
        switch raw {
        case "followRequest": return .followRequest
        case "followRequestAccepted": return .followRequestAccepted
        case "roomJoin": return .roomJoin
        case "roomMention": return .roomMention
        case "tradingReport": return .tradingReport
        case "affiliate": return .affiliateReferral
        case "achievement": return .system
        default: return .system
        }
    }
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
    var profilePostID: PostID?
    var achievementPostID: PostID?
    var reelID: ReelID?
    var commentID: CommentID?
    var conversationID: ConversationID?
    var roomID: RoomID?
    var roomMessageID: RoomMessageID?
    var followRequestID: String?
    var roomSlug: String?
    var roomName: String?
    var sectionID: String?
    var sectionName: String?
    var messagePreview: String?
    var reportID: ReportID?
    var affiliateHref: String?
    var createdAt: Date
    var isRead: Bool
}

/// Pending private-profile follow request (from `follow_requests`, not notification rows).
nonisolated struct FollowRequest: Hashable, Codable, Sendable, Identifiable {
    var id: FollowRequestID
    var requesterProfileID: ProfileID
    var createdAt: Date
}
