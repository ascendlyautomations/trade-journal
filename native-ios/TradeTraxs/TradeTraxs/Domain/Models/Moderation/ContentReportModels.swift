import Foundation

nonisolated enum ContentReportTargetType: String, Sendable, CaseIterable, Codable {
    case user
    case trade
    case post
    case reel
    case story
    case achievement
    case comment
    case directMessage = "direct_message"
    case tradeRoom = "trade_room"
    case tradeRoomMessage = "trade_room_message"
}

nonisolated enum ContentReportReason: String, Sendable, CaseIterable, Codable, Identifiable {
    case harassment
    case spam
    case scam
    case inappropriate
    case hate
    case impersonation
    case dangerous
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .harassment: return "Harassment or bullying"
        case .spam: return "Spam"
        case .scam: return "Scam or fraud"
        case .inappropriate: return "Inappropriate content"
        case .hate: return "Hate or abusive content"
        case .impersonation: return "Impersonation"
        case .dangerous: return "Dangerous content"
        case .other: return "Other"
        }
    }
}

/// Normalized report target for the shared moderation sheet.
nonisolated struct ContentReportTarget: Equatable, Sendable {
    let type: ContentReportTargetType
    let targetID: String
    let reportedUserID: ProfileID?

    static func user(_ profileID: ProfileID) -> ContentReportTarget {
        ContentReportTarget(type: .user, targetID: profileID.rawValue, reportedUserID: profileID)
    }

    static func trade(_ tradeID: TradeID, ownerID: ProfileID) -> ContentReportTarget {
        ContentReportTarget(type: .trade, targetID: tradeID.rawValue, reportedUserID: ownerID)
    }

    static func post(_ postID: PostID, ownerID: ProfileID) -> ContentReportTarget {
        ContentReportTarget(type: .post, targetID: postID.rawValue, reportedUserID: ownerID)
    }

    static func reel(_ reelID: ReelID, ownerID: ProfileID) -> ContentReportTarget {
        ContentReportTarget(type: .reel, targetID: reelID.rawValue, reportedUserID: ownerID)
    }

    static func story(_ storyID: StoryID, ownerID: ProfileID) -> ContentReportTarget {
        ContentReportTarget(type: .story, targetID: storyID.rawValue, reportedUserID: ownerID)
    }

    static func achievement(_ achievementID: AchievementID, ownerID: ProfileID) -> ContentReportTarget {
        ContentReportTarget(
            type: .achievement,
            targetID: achievementID.rawValue,
            reportedUserID: ownerID
        )
    }

    static func comment(_ commentID: CommentID, authorID: ProfileID) -> ContentReportTarget {
        ContentReportTarget(type: .comment, targetID: commentID.rawValue, reportedUserID: authorID)
    }

    static func directMessage(_ messageID: MessageID, senderID: ProfileID) -> ContentReportTarget {
        ContentReportTarget(
            type: .directMessage,
            targetID: messageID.rawValue,
            reportedUserID: senderID
        )
    }

    static func tradeRoom(_ roomID: RoomID, ownerID: ProfileID?) -> ContentReportTarget {
        ContentReportTarget(type: .tradeRoom, targetID: roomID.rawValue, reportedUserID: ownerID)
    }

    static func tradeRoomMessage(_ messageID: RoomMessageID, senderID: ProfileID) -> ContentReportTarget {
        ContentReportTarget(
            type: .tradeRoomMessage,
            targetID: messageID.rawValue,
            reportedUserID: senderID
        )
    }
}

/// Presentation payload for the shared report sheet.
struct ContentReportRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let target: ContentReportTarget
    let subjectTitle: String
    /// When set, success UI may offer optional block after report.
    var blockUserOffer: ProfileID?
}

enum ContentReportSubmissionError: Error, Equatable, Sendable {
    case notAuthenticated
    case duplicate
    case serverMessage(String)
    case unknown
}
