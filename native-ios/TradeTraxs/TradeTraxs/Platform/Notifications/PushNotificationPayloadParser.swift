import Foundation

/// Maps APNs `userInfo` (and Activity-equivalent payloads) into typed ``NotificationDestination``.
///
/// Reuses the existing server payload shape from `lib/server/push/apns.ts`:
/// `href`, `type`, `conversationId`, `roomId`, `roomSlug`, `followRequestId`, `aps.badge`.
enum PushNotificationPayloadParser {
    static func parse(userInfo: [AnyHashable: Any]) -> NotificationDestination {
        let strings = stringMap(from: userInfo)
        let type = (strings["type"] ?? strings["notificationType"] ?? "").lowercased()
        let href = strings["href"]
        let hrefQuery = queryItems(from: href)

        let conversationID = firstNonEmpty(
            strings["conversationId"],
            strings["conversation_id"],
            hrefQuery["conversation"],
            pathID(from: href, prefix: "messages")
        ).map { ConversationID($0) }

        let roomID = firstNonEmpty(
            strings["roomId"],
            strings["room_id"],
            hrefQuery["room"]
        ).map { RoomID($0) }

        let sectionID = firstNonEmpty(
            strings["sectionId"],
            strings["section_id"],
            hrefQuery["section"]
        )
        let messageID = firstNonEmpty(
            strings["messageId"],
            strings["message_id"],
            hrefQuery["message"]
        )
        let tradeID = firstNonEmpty(
            strings["tradeId"],
            strings["trade_id"],
            pathID(from: href, prefix: "trade"),
            hrefQuery["trade"]
        ).map { TradeID($0) }
        var postID = firstNonEmpty(
            strings["postId"],
            strings["post_id"],
            strings["profile_post_id"],
            pathID(from: href, prefix: "post"),
            hrefQuery["post"]
        ).map { PostID($0) }
        let achievementPostID = firstNonEmpty(
            strings["achievementPostId"],
            strings["achievement_post_id"],
            hrefQuery["achievement"]
        ).map { PostID($0) }
        // Achievement posts share PostID routing via FeedRoute.achievement when type is known;
        // fall back to postID so NotificationRouter can open the achievement.
        if postID == nil, let achievementPostID {
            postID = achievementPostID
        }
        let reelID = firstNonEmpty(
            strings["reelId"],
            strings["reel_id"],
            pathID(from: href, prefix: "reel"),
            hrefQuery["reel"]
        ).map { ReelID($0) }
        let profileID = firstNonEmpty(
            strings["senderId"],
            strings["sender_id"],
            strings["profileId"],
            strings["profile_id"],
            pathID(from: href, prefix: "profile"),
            pathID(from: href, prefix: "u")
        ).map { ProfileID($0) }
        let reportID = firstNonEmpty(
            strings["reportId"],
            strings["report_id"],
            hrefQuery["report"]
        ).map { ReportID($0) }
        let commentID = firstNonEmpty(
            strings["commentId"],
            strings["comment_id"]
        )
        let threadID = firstNonEmpty(messageID, commentID, strings["thread-id"], strings["threadId"])

        var raw = strings
        if let sectionID { raw["section_id"] = sectionID }
        if let messageID { raw["message_id"] = messageID }
        if let commentID { raw["comment_id"] = commentID }
        if let href { raw["href"] = href }
        if let achievementPostID {
            raw["achievement_post_id"] = achievementPostID.rawValue
        }
        if let roomSlug = firstNonEmpty(strings["roomSlug"], strings["room_slug"]) {
            raw["room_slug"] = roomSlug
        }

        let category = category(for: type, conversationID: conversationID, roomID: roomID, reportID: reportID)

        return NotificationDestination(
            category: category,
            threadID: threadID,
            tradeID: tradeID,
            postID: postID,
            reelID: reelID,
            profileID: profileID,
            conversationID: conversationID,
            roomID: roomID,
            reportID: reportID,
            sectionID: sectionID,
            messageID: messageID,
            rawUserInfo: raw
        )
    }

    static func badgeValue(from userInfo: [AnyHashable: Any]) -> Int? {
        if let aps = userInfo["aps"] as? [AnyHashable: Any] {
            if let badge = aps["badge"] as? Int { return max(0, badge) }
            if let badge = aps["badge"] as? NSNumber { return max(0, badge.intValue) }
            if let badge = aps["badge"] as? String, let value = Int(badge) { return max(0, value) }
        }
        return nil
    }

    // MARK: - Private

    private static func category(
        for type: String,
        conversationID: ConversationID?,
        roomID: RoomID?,
        reportID: ReportID?
    ) -> NotificationDestination.NotificationCategory {
        switch type {
        case "message", "dm", "direct_message":
            return .directMessage
        case "room_message":
            return .roomMessage
        case "room_mention":
            return .roomMention
        case "follow_request":
            return .followRequest
        case "trading_report":
            return .tradingReport
        case "daily_check_in":
            return .dailyCheckIn
        case "like", "like_batch", "like_milestone", "comment", "follow",
             "follow_request_accepted", "follow_batch", "room_join",
             "affiliate_referral", "affiliate_commission_earned",
             "announcement", "announcements", "product_update", "maintenance":
            return .activity
        default:
            if conversationID != nil { return .directMessage }
            if roomID != nil { return .roomMessage }
            if reportID != nil { return .tradingReport }
            return type.isEmpty ? .unknown : .activity
        }
    }

    private static func stringMap(from userInfo: [AnyHashable: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in userInfo {
            let keyString = String(describing: key)
            if keyString == "aps" { continue }
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { result[keyString] = trimmed }
            } else if let number = value as? NSNumber {
                result[keyString] = number.stringValue
            }
        }
        return result
    }

    private static func queryItems(from href: String?) -> [String: String] {
        guard let href, !href.isEmpty else { return [:] }
        let url: URL?
        if href.hasPrefix("http") {
            url = URL(string: href)
        } else if href.hasPrefix("/") {
            url = URL(string: "https://www.tradetraxs.com\(href)")
        } else {
            url = URL(string: href)
        }
        guard let url else { return [:] }
        var items: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            guard let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                continue
            }
            items[item.name] = value
        }
        return items
    }

    private static func pathID(from href: String?, prefix: String) -> String? {
        guard let href else { return nil }
        let path: String
        if let url = URL(string: href.hasPrefix("/") ? "https://www.tradetraxs.com\(href)" : href) {
            path = url.path
        } else {
            path = href
        }
        let parts = path.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(of: prefix), parts.indices.contains(index + 1) else {
            return nil
        }
        let value = parts[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let value {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
}
