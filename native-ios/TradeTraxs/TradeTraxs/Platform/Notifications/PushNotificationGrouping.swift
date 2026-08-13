import Foundation

/// Client-side grouping / collapse copy for push + Activity presentation.
///
/// Server already coalesces DMs via APNs `thread-id` / `collapse-id` and batches likes.
/// Native mirrors iMessage / Instagram rules for inbox + foreground presentation:
/// - DMs collapse to “{Name} sent N messages” after 3+
/// - Likes / comments group per target
/// - Follows, mentions, and replies stay individual
enum PushNotificationGrouping {
    /// Stable APNs / Notification Center thread key for a DM conversation.
    static func dmThreadID(conversationID: ConversationID) -> String {
        "dm:\(conversationID.rawValue)"
    }

    /// Stable thread key for a Trade Room channel.
    static func roomThreadID(roomID: RoomID, sectionID: String?) -> String {
        if let sectionID, !sectionID.isEmpty {
            return "room:\(roomID.rawValue):section:\(sectionID)"
        }
        return "room:\(roomID.rawValue)"
    }

    /// iMessage-style collapse body after rapid messages in one conversation.
    static func dmCollapseBody(senderName: String, count: Int) -> String {
        let n = max(1, count)
        if n == 1 { return "" }
        if n == 2 { return "" }
        return "\(senderName) sent \(n) messages"
    }

    /// Whether a notification type must never be grouped.
    static func mustRemainIndividual(type: String) -> Bool {
        switch type.lowercased() {
        case "follow",
             "follow_request",
             "follow_request_accepted",
             "room_mention",
             "mention",
             "reply":
            return true
        default:
            return false
        }
    }

    /// Engagement target key — never crosses trades / posts / reels.
    static func engagementGroupKey(for notification: ActivityNotification) -> String? {
        switch notification.kind {
        case .like:
            if let commentID = notification.commentID {
                return "comment_like:\(commentID.rawValue)"
            }
            if let postID = notification.postID {
                return "like:post:\(postID.rawValue)"
            }
            if let profilePostID = notification.profilePostID {
                return "like:profile_post:\(profilePostID.rawValue)"
            }
            if let achievementPostID = notification.achievementPostID {
                return "like:achievement:\(achievementPostID.rawValue)"
            }
            if let reelID = notification.reelID {
                return "like:reel:\(reelID.rawValue)"
            }
            if let tradeID = notification.tradeID {
                return "like:trade:\(tradeID.rawValue)"
            }
            return nil
        case .comment:
            // Replies / mentions stay individual.
            if notification.isReply || notification.isMention { return nil }
            if let postID = notification.postID {
                return "comment:post:\(postID.rawValue)"
            }
            if let profilePostID = notification.profilePostID {
                return "comment:profile_post:\(profilePostID.rawValue)"
            }
            if let achievementPostID = notification.achievementPostID {
                return "comment:achievement:\(achievementPostID.rawValue)"
            }
            if let reelID = notification.reelID {
                return "comment:reel:\(reelID.rawValue)"
            }
            if let tradeID = notification.tradeID {
                return "comment:trade:\(tradeID.rawValue)"
            }
            return nil
        default:
            return nil
        }
    }

    static func likeGroupTitle(actorNames: [String], total: Int, targetNoun: String) -> String {
        let names = actorNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let n = max(total, names.count)
        if n <= 0 { return "Someone liked your \(targetNoun)" }
        if n == 1 { return "\(names.first ?? "Someone") liked your \(targetNoun)" }
        if n == 2 {
            let second = names.count > 1 ? names[1] : "someone else"
            return "\(names.first ?? "Someone") and \(second) liked your \(targetNoun)"
        }
        if names.count >= 2 {
            let others = n - 2
            return "\(names[0]), \(names[1]) and \(others) other\(others == 1 ? "" : "s") liked your \(targetNoun)"
        }
        let others = n - 1
        return "\(names.first ?? "Someone") and \(others) other\(others == 1 ? "" : "s") liked your \(targetNoun)"
    }

    static func commentGroupTitle(actorNames: [String], total: Int, targetNoun: String) -> String {
        let names = actorNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let n = max(total, names.count)
        if n <= 0 { return "Someone commented on your \(targetNoun)" }
        if n == 1 { return "\(names.first ?? "Someone") commented on your \(targetNoun)" }
        if n == 2 {
            let second = names.count > 1 ? names[1] : "someone else"
            return "\(names.first ?? "Someone") and \(second) commented on your \(targetNoun)"
        }
        if names.count >= 2 {
            let others = n - 2
            return "\(names[0]), \(names[1]) and \(others) other\(others == 1 ? "" : "s") commented on your \(targetNoun)"
        }
        let others = n - 1
        return "\(names.first ?? "Someone") and \(others) other\(others == 1 ? "" : "s") commented on your \(targetNoun)"
    }

    /// Trade Room subtitle / secondary line: `Futures Lounge • #gold`.
    static func roomChannelLabel(roomName: String?, sectionName: String?) -> String {
        ActivityNotificationFormatting.roomChannelTitle(roomName: roomName, sectionName: sectionName)
            .replacingOccurrences(of: " · ", with: " • ")
    }
}
