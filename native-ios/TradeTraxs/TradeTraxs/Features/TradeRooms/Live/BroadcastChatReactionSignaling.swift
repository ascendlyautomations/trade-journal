import Foundation

struct BroadcastChatReactionItem: Hashable, Sendable, Identifiable {
    var messageId: String
    var userId: String
    var emoji: String
    var updatedAt: Date

    var id: String { "\(messageId)-\(userId)" }
}

enum TradeRoomBroadcastChatReactionConstants {
    static let topic = "tt_broadcast_chat_reaction"
    static let minInterval: TimeInterval = 0.25
}

enum BroadcastChatReactionSignaling {
    private struct Payload: Codable {
        var type: String
        var messageId: String
        var userId: String
        var emoji: String?
        var sentAt: Double
    }

    static func encodeOutgoing(
        messageId: String,
        userId: String,
        emoji: String?
    ) throws -> Data {
        let trimmedMessageId = messageId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessageId.isEmpty else {
            throw NSError(domain: "BroadcastChatReaction", code: 1)
        }
        let normalized: String?
        if let emoji {
            normalized = MessageReactionValidation.normalize(emoji)
            guard normalized != nil else {
                throw NSError(domain: "BroadcastChatReaction", code: 2)
            }
        } else {
            normalized = nil
        }
        let payload = Payload(
            type: "chat_reaction",
            messageId: trimmedMessageId,
            userId: userId,
            emoji: normalized,
            sentAt: Date().timeIntervalSince1970 * 1000
        )
        return try JSONEncoder().encode(payload)
    }

    static func parseIncoming(
        data: Data,
        senderIdentity: String
    ) -> (messageId: String, userId: String, emoji: String?, updatedAt: Date)? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.type == "chat_reaction",
              payload.userId == senderIdentity
        else { return nil }

        let messageId = payload.messageId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageId.isEmpty else { return nil }

        let emoji: String?
        if let raw = payload.emoji, !raw.isEmpty {
            guard let normalized = MessageReactionValidation.normalize(raw) else { return nil }
            emoji = normalized
        } else {
            emoji = nil
        }

        let updatedAt = Date(timeIntervalSince1970: payload.sentAt / 1000)
        return (messageId, payload.userId, emoji, updatedAt)
    }

    static func apply(
        _ reactions: [BroadcastChatReactionItem],
        messageId: String,
        userId: String,
        emoji: String?,
        updatedAt: Date
    ) -> [BroadcastChatReactionItem] {
        let withoutUser = reactions.filter { !($0.messageId == messageId && $0.userId == userId) }
        guard let emoji, !emoji.isEmpty else { return withoutUser }
        return withoutUser + [
            BroadcastChatReactionItem(
                messageId: messageId,
                userId: userId,
                emoji: emoji,
                updatedAt: updatedAt
            ),
        ]
    }
}