import Foundation

enum TradeRoomBroadcastChatConstants {
    static let topic = "tt_broadcast_chat"
    /// Raise-hand signals for livestream viewers — separate from General Voice (`tt_general_voice_hand`).
    static let handTopic = "tt_broadcast_hand"
    static let maxLength = 500
    static let maxMessages = 200
}

struct BroadcastChatMessageItem: Identifiable, Hashable, Sendable {
    var id: String
    var userId: String
    var displayName: String
    var text: String
    var sentAt: Date
}

enum BroadcastChatPayload: Codable, Sendable {
    case chat(
        userId: String,
        displayName: String,
        avatarUrl: String?,
        text: String,
        sentAt: Double
    )

    enum CodingKeys: String, CodingKey {
        case type
        case userId
        case displayName
        case avatarUrl
        case text
        case sentAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        guard type == "chat" else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown")
        }
        self = .chat(
            userId: try c.decode(String.self, forKey: .userId),
            displayName: try c.decode(String.self, forKey: .displayName),
            avatarUrl: try c.decodeIfPresent(String.self, forKey: .avatarUrl),
            text: try c.decode(String.self, forKey: .text),
            sentAt: try c.decode(Double.self, forKey: .sentAt)
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .chat(userId, displayName, avatarUrl, text, sentAt):
            try c.encode("chat", forKey: .type)
            try c.encode(userId, forKey: .userId)
            try c.encode(displayName, forKey: .displayName)
            try c.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
            try c.encode(text, forKey: .text)
            try c.encode(sentAt, forKey: .sentAt)
        }
    }

    static func encodeOutgoing(
        userId: String,
        displayName: String,
        avatarUrl: String?,
        text: String
    ) throws -> Data {
        try JSONEncoder().encode(
            BroadcastChatPayload.chat(
                userId: userId,
                displayName: displayName,
                avatarUrl: avatarUrl,
                text: text,
                sentAt: Date().timeIntervalSince1970 * 1000
            )
        )
    }

    static func parseIncoming(data: Data, senderIdentity: String) -> BroadcastChatMessageItem? {
        guard let payload = try? JSONDecoder().decode(BroadcastChatPayload.self, from: data) else {
            return nil
        }
        guard case let .chat(userId, displayName, _, text, sentAt) = payload else { return nil }
        guard userId == senderIdentity else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= TradeRoomBroadcastChatConstants.maxLength else {
            return nil
        }
        return BroadcastChatMessageItem(
            id: "\(userId)-\(Int(sentAt))",
            userId: userId,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Member"
                : displayName,
            text: trimmed,
            sentAt: Date(timeIntervalSince1970: sentAt / 1000)
        )
    }
}
