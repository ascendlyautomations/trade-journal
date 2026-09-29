import Foundation

/// Persisted structured-share pointer — mirrors web `messages.type` + id columns.
nonisolated enum SharedContentReference: Hashable, Codable, Sendable {
    case feedPost(PostID)
    case profilePost(PostID)
    case achievementPost(PostID)
    case reel(ReelID)
    case trade(TradeID)

    var messageType: String {
        switch self {
        case .feedPost: return "post"
        case .profilePost: return "profile_post"
        case .achievementPost: return "achievement_post"
        case .reel: return "reel"
        case .trade: return "trade"
        }
    }

    var messageKind: MessageKind {
        switch self {
        case .feedPost: return .feedPostShare
        case .profilePost: return .profilePostShare
        case .achievementPost: return .achievementPostShare
        case .reel: return .reelShare
        case .trade: return .tradeShare
        }
    }

    var inboxPreview: String {
        switch self {
        case .feedPost: return "Shared a post"
        case .profilePost: return "Shared a post"
        case .achievementPost: return "Shared an achievement"
        case .reel: return "Shared a clip"
        case .trade: return "Shared a trade"
        }
    }

    var stableKey: String {
        switch self {
        case .feedPost(let id): return "feedPost:\(id.rawValue)"
        case .profilePost(let id): return "profilePost:\(id.rawValue)"
        case .achievementPost(let id): return "achievementPost:\(id.rawValue)"
        case .reel(let id): return "reel:\(id.rawValue)"
        case .trade(let id): return "trade:\(id.rawValue)"
        }
    }

    static func resolve(
        type: String?,
        postID: String?,
        profilePostID: String?,
        achievementPostID: String?,
        reelID: String?,
        tradeID: String?
    ) -> SharedContentReference? {
        let normalized = type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "post":
            if let raw = postID?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                return .feedPost(PostID(raw))
            }
        case "profile_post":
            if let raw = profilePostID?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                return .profilePost(PostID(raw))
            }
        case "achievement_post":
            if let raw = achievementPostID?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                return .achievementPost(PostID(raw))
            }
        case "reel":
            if let raw = reelID?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                return .reel(ReelID(raw))
            }
        case "trade":
            if let raw = tradeID?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                return .trade(TradeID(raw))
            }
        default:
            break
        }

        if let raw = tradeID?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return .trade(TradeID(raw))
        }
        if let raw = postID?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return .feedPost(PostID(raw))
        }
        if let raw = profilePostID?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return .profilePost(PostID(raw))
        }
        if let raw = achievementPostID?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return .achievementPost(PostID(raw))
        }
        if let raw = reelID?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return .reel(ReelID(raw))
        }
        return nil
    }
}

nonisolated enum SharedContentRoomMessageSupport {
    static func encode(reference: SharedContentReference) -> String {
        var payload: [String: String] = ["share_type": reference.messageType]
        switch reference {
        case .feedPost(let id):
            payload["post_id"] = id.rawValue
        case .profilePost(let id):
            payload["profile_post_id"] = id.rawValue
        case .achievementPost(let id):
            payload["achievement_post_id"] = id.rawValue
        case .reel(let id):
            payload["reel_id"] = id.rawValue
        case .trade(let id):
            payload["trade_id"] = id.rawValue
        }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return json
    }

    static func decode(from content: String?) -> SharedContentReference? {
        guard let raw = content?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let shareType = (json["share_type"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return SharedContentReference.resolve(
            type: shareType,
            postID: json["post_id"] as? String,
            profilePostID: json["profile_post_id"] as? String,
            achievementPostID: json["achievement_post_id"] as? String,
            reelID: json["reel_id"] as? String,
            tradeID: json["trade_id"] as? String
        )
    }

    static func isStructuredShare(type: String?, content: String?) -> Bool {
        let normalized = type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "post", "profile_post", "achievement_post", "reel":
            return true
        default:
            return decode(from: content) != nil
        }
    }
}

nonisolated enum SharedContentMessageSupport {
    static func messageKind(
        type: String?,
        postID: String?,
        profilePostID: String?,
        achievementPostID: String?,
        reelID: String?,
        tradeID: String?
    ) -> MessageKind? {
        guard let reference = SharedContentReference.resolve(
            type: type,
            postID: postID,
            profilePostID: profilePostID,
            achievementPostID: achievementPostID,
            reelID: reelID,
            tradeID: tradeID
        ) else { return nil }
        return reference.messageKind
    }

    static func preview(
        for message: Message,
        type: String? = nil
    ) -> String? {
        if let reference = message.sharedContent {
            return reference.inboxPreview
        }
        if let kind = type.flatMap({ MessageKind(rawValue: $0) }) {
            switch kind {
            case .feedPostShare, .profilePostShare: return "Shared a post"
            case .achievementPostShare: return "Shared an achievement"
            case .reelShare: return "Shared a clip"
            case .tradeShare: return "Shared a trade"
            default: break
            }
        }
        return nil
    }

    static func preview(fromStoredType type: String?) -> String? {
        guard let normalized = type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty
        else { return nil }
        switch normalized {
        case "post", "profile_post": return "Shared a post"
        case "achievement_post": return "Shared an achievement"
        case "reel": return "Shared a clip"
        case "trade": return "Shared a trade"
        default: return nil
        }
    }

    /// True for internal share rows (Post / Trade / Achievement / Reel) in DM + Trade Room bubbles.
    static func isInternallySharedContent(_ message: Message) -> Bool {
        if message.sharedContent != nil { return true }
        switch message.kind {
        case .tradeShare, .feedPostShare, .profilePostShare, .achievementPostShare, .reelShare:
            return true
        default:
            return false
        }
    }

    /// Optional sender note attached to a structured share — not structured JSON / placeholders.
    static func userWrittenMessage(for message: Message) -> String? {
        guard isInternallySharedContent(message) else { return nil }
        return normalizedUserWrittenBody(message.body)
    }

    static func normalizedUserWrittenBody(_ body: String?) -> String? {
        let trimmed = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        if SharedContentRoomMessageSupport.decode(from: trimmed) != nil { return nil }
        if StoryShareMessageSupport.decode(from: trimmed) != nil { return nil }
        if StoryReplyMessageSupport.decode(from: trimmed) != nil { return nil }
        if isPlaceholderShareBody(trimmed) { return nil }
        return trimmed
    }

    static func isPlaceholderShareBody(_ body: String) -> Bool {
        let normalized = body.trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized {
        case "Shared a trade", "Shared a post", "Shared a clip", "Shared an achievement":
            return true
        default:
            return false
        }
    }

    /// Plain-text companion row bundled visually below a structured share (web + native share flows).
    static func isCompanionTextMessage(_ message: Message) -> Bool {
        guard message.replyToMessageID == nil else { return false }
        switch message.kind {
        case .text:
            break
        case .media, .voice, .storyReply, .storyShare, .system:
            return false
        case .tradeShare, .feedPostShare, .profilePostShare, .achievementPostShare, .reelShare:
            return false
        }
        if message.sharedContent != nil { return false }
        if !message.attachments.isEmpty { return false }
        return normalizedUserWrittenBody(message.body) != nil
    }

    private static let shareCompanionMaxInterval: TimeInterval = 120

    struct ShareCaptionBundling: Sendable {
        var captionByShareID: [MessageID: String] = [:]
        var hiddenMessageIDs: Set<MessageID> = []
    }

    /// Pairs optional sender notes with share rows (card-first layout); hides consumed text rows.
    static func bundleShareCaptions(in messages: [Message]) -> ShareCaptionBundling {
        var result = ShareCaptionBundling()

        for index in messages.indices {
            let share = messages[index]
            guard isInternallySharedContent(share) else { continue }
            if let inline = userWrittenMessage(for: share) {
                result.captionByShareID[share.id] = inline
            }
            if result.captionByShareID[share.id] == nil,
               index + 1 < messages.count
            {
                let next = messages[index + 1]
                if isCompanionTextMessage(next),
                   next.senderProfileID == share.senderProfileID,
                   abs(next.createdAt.timeIntervalSince(share.createdAt)) <= shareCompanionMaxInterval
                {
                    if let caption = normalizedUserWrittenBody(next.body) {
                        result.captionByShareID[share.id] = caption
                        result.hiddenMessageIDs.insert(next.id)
                    }
                }
            }
        }

        for index in messages.indices {
            let share = messages[index]
            guard isInternallySharedContent(share), result.captionByShareID[share.id] == nil else { continue }
            guard index > 0 else { continue }
            let previous = messages[index - 1]
            guard !result.hiddenMessageIDs.contains(previous.id),
                  isCompanionTextMessage(previous),
                  previous.senderProfileID == share.senderProfileID,
                  abs(share.createdAt.timeIntervalSince(previous.createdAt)) <= shareCompanionMaxInterval,
                  let caption = normalizedUserWrittenBody(previous.body)
            else { continue }
            result.captionByShareID[share.id] = caption
            result.hiddenMessageIDs.insert(previous.id)
        }

        return result
    }
}
