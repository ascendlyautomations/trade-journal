import Foundation

enum MessageReplySupport {
    static let previewMaxLength = 80

    struct Target: Equatable, Sendable {
        var messageID: MessageID
        var authorName: String
        var preview: String
    }

    struct ParentPresentation: Equatable, Sendable {
        var parentMessageID: MessageID
        var authorName: String
        var preview: String
        var isUnavailable: Bool
    }

    static func truncatePreview(_ text: String, max: Int = previewMaxLength) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.count > max else { return trimmed }
        return String(trimmed.prefix(max)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    static func authorLabel(
        profile: Profile?,
        fallback: String = "Someone"
    ) -> String {
        guard let profile else { return fallback }
        let resolved = ConversationThreadSupport.senderDisplayName(for: profile)
        if resolved == ProfileIdentitySanitizer.neutralFallbackName {
            return fallback
        }
        return resolved
    }

    /// Display name for quoted reply UI — prefers hydrated profile, then lightweight inbox metadata.
    static func quotedAuthorName(
        senderProfileID: ProfileID,
        profile: Profile?,
        viewerID: ProfileID?,
        peerProfileID: ProfileID?,
        peerUsername: String?,
        conversationTitle: String?
    ) -> String {
        if let profile {
            return authorLabel(profile: profile, fallback: "Someone")
        }
        if let peerProfileID, senderProfileID == peerProfileID {
            if let title = ProfileIdentitySanitizer.sanitizedPublicField(conversationTitle) {
                return title
            }
            if let username = ProfileIdentitySanitizer.leaderboardUsername(peerUsername) {
                return username
            }
        }
        _ = viewerID
        return "Someone"
    }

    /// Composer strip label when starting a reply (includes “yourself” for the viewer).
    static func composerReplyAuthorName(
        item: ConversationBubbleItem,
        viewerID: ProfileID?,
        profile: Profile?,
        peerProfileID: ProfileID?,
        peerUsername: String?,
        conversationTitle: String?
    ) -> String {
        if item.isOutgoing, let viewerID, item.message.senderProfileID == viewerID {
            return "yourself"
        }
        return quotedAuthorName(
            senderProfileID: item.message.senderProfileID,
            profile: profile ?? item.authorProfile,
            viewerID: viewerID,
            peerProfileID: peerProfileID,
            peerUsername: peerUsername,
            conversationTitle: conversationTitle
        )
    }

    static func target(
        from item: ConversationBubbleItem,
        authorName: String
    ) -> Target {
        Target(
            messageID: item.id,
            authorName: authorName,
            preview: previewText(from: item)
        )
    }

    static func parentPresentation(
        parentMessageID: MessageID,
        parentItem: ConversationBubbleItem?,
        senderProfile: Profile?,
        viewerID: ProfileID?,
        peerProfileID: ProfileID?,
        peerUsername: String?,
        conversationTitle: String?
    ) -> ParentPresentation {
        guard let parentItem else {
            return ParentPresentation(
                parentMessageID: parentMessageID,
                authorName: "",
                preview: "",
                isUnavailable: true
            )
        }
        let authorName = quotedAuthorName(
            senderProfileID: parentItem.message.senderProfileID,
            profile: senderProfile ?? parentItem.authorProfile,
            viewerID: viewerID,
            peerProfileID: peerProfileID,
            peerUsername: peerUsername,
            conversationTitle: conversationTitle
        )
        return ParentPresentation(
            parentMessageID: parentMessageID,
            authorName: authorName,
            preview: previewText(from: parentItem),
            isUnavailable: false
        )
    }

    static func previewText(from item: ConversationBubbleItem) -> String {
        let message = item.message
        if message.kind == .storyReply,
           let payload = StoryReplyMessageSupport.decode(from: message.body)
        {
            return truncatePreview(StoryReplyMessageSupport.replyText(from: payload) ?? "Replied to your story")
        }
        if message.kind == .storyShare || StoryShareMessageSupport.decode(from: message.body) != nil {
            return truncatePreview(StoryShareMessageSupport.previewText(from: message.body))
        }
        if message.kind == .tradeShare {
            return "Shared a trade"
        }
        if message.kind == .feedPostShare || message.kind == .profilePostShare {
            return "Shared a post"
        }
        if message.kind == .achievementPostShare {
            return "Shared an achievement"
        }
        if message.kind == .reelShare {
            return "Shared a clip"
        }
        if message.kind == .voice || item.voiceReference != nil {
            return "Voice message"
        }
        if let imageRef = item.imageReference, message.kind != .tradeShare {
            if let caption = item.resolvedShareUserCaption?.trimmingCharacters(in: .whitespacesAndNewlines),
               !caption.isEmpty
            {
                return truncatePreview(caption)
            }
            if let body = message.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
                return truncatePreview(body)
            }
            _ = imageRef
            return "Sent an image"
        }
        if let text = item.copyableMessageText ?? item.text {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return truncatePreview(trimmed)
            }
        }
        if let body = message.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            return truncatePreview(body)
        }
        return "New message"
    }
}
