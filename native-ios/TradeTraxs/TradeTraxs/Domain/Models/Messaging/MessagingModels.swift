import Foundation

nonisolated enum MessageKind: String, Hashable, Codable, Sendable {
    case text
    case tradeShare
    case media
    case system
}

nonisolated struct Conversation: Hashable, Codable, Sendable, Identifiable {
    var id: ConversationID
    var participantProfileIDs: [ProfileID]
    var title: String?
    var lastMessagePreview: String?
    var lastMessageAt: Date?
    var unreadCount: Int
    var isMuted: Bool
    var updatedAt: Date
}

nonisolated struct MessageAttachment: Hashable, Codable, Sendable, Identifiable {
    var id: String
    var media: MediaReference
    var tradeID: TradeID?
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
}
