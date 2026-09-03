import Foundation

nonisolated enum MessageKind: String, Hashable, Codable, Sendable {
    case text
    case tradeShare
    case media
    case voice
    case storyReply = "story_reply"
    case system
}

/// Domain conversation — mirrors web inbox row fields (`DmConversationRow` + unread/mute).
nonisolated struct Conversation: Hashable, Codable, Sendable, Identifiable {
    var id: ConversationID
    var participantProfileIDs: [ProfileID]
    /// Group name, or peer display name for 1:1 (web `displayName` / profile `name`).
    var title: String?
    /// Peer `@username` for 1:1 DMs (nil for groups).
    var peerUsername: String?
    var avatar: MediaReference?
    var isGroup: Bool
    var isPinned: Bool
    var lastMessagePreview: String?
    var lastMessageAt: Date?
    /// Canonical latest message for preview tie-break and stale-event rejection.
    var lastMessageID: MessageID? = nil
    var unreadCount: Int
    var isMuted: Bool
    var updatedAt: Date
}

nonisolated struct MessageAttachment: Hashable, Codable, Sendable, Identifiable {
    var id: String
    var media: MediaReference
    var tradeID: TradeID?
    /// Voice message duration in seconds — persisted server-side as `audio_duration_ms`.
    var durationSeconds: Double? = nil
}

nonisolated struct Message: Hashable, Codable, Sendable, Identifiable {
    var id: MessageID
    var conversationID: ConversationID
    var senderProfileID: ProfileID
    var kind: MessageKind
    var body: String?
    var attachments: [MessageAttachment]
    var replyToMessageID: MessageID?
    var createdAt: Date
    var isReadByViewer: Bool
    /// Trade Room only — web `room_message_reactions` embed.
    var roomReactions: [RoomMessageReaction] = []
}
