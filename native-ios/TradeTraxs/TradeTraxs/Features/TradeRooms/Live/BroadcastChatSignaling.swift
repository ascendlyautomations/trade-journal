import Foundation

enum BroadcastChatSendResult: Equatable, Sendable {
    case sent
    case failed(String)
}

enum TradeRoomBroadcastChatConstants {
    static let topic = "tt_broadcast_chat"
    /// Raise-hand signals for livestream viewers, separate from General Voice (`tt_general_voice_hand`).
    static let handTopic = "tt_broadcast_hand"
    static let maxLength = 500
    static let maxMessages = 200
    static let replyPreviewMaxLength = 100
}

/// Snapshot of the message being replied to (embedded in payload for clients that no longer hold the original).
struct BroadcastChatReplyReference: Hashable, Sendable, Codable {
    var messageId: String
    var userId: String
    var displayName: String
    var textPreview: String
}

struct BroadcastChatMessageItem: Identifiable, Hashable, Sendable {
    var id: String
    var userId: String
    var displayName: String
    var text: String
    var sentAt: Date
    var imageURL: String?
    var tradeID: TradeID?
    var replyTo: BroadcastChatReplyReference?
}

struct BroadcastChatScrollRequest: Equatable, Sendable {
    var messageID: String
    var token: UInt64
}

enum BroadcastChatReplyFormatting {
    static func previewText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > TradeRoomBroadcastChatConstants.replyPreviewMaxLength else {
            return trimmed
        }
        let end = trimmed.index(
            trimmed.startIndex,
            offsetBy: TradeRoomBroadcastChatConstants.replyPreviewMaxLength
        )
        return String(trimmed[..<end]) + "…"
    }

    static func reference(for message: BroadcastChatMessageItem, displayName: String) -> BroadcastChatReplyReference {
        let preview: String = {
            let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return previewText(trimmed)
            }
            if message.imageURL != nil {
                return "Photo"
            }
            if message.tradeID != nil {
                return "Shared a trade"
            }
            return "Message"
        }()
        return BroadcastChatReplyReference(
            messageId: message.id,
            userId: message.userId,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? message.displayName
                : displayName,
            textPreview: preview
        )
    }
}

enum BroadcastChatPayload: Codable, Sendable {
    case chat(
        userId: String,
        displayName: String,
        avatarUrl: String?,
        text: String,
        sentAt: Double,
        imageURL: String?,
        tradeID: String?,
        replyTo: BroadcastChatReplyReference?
    )

    enum CodingKeys: String, CodingKey {
        case type
        case userId
        case displayName
        case avatarUrl
        case text
        case sentAt
        case imageUrl
        case tradeId
        case replyToMessageId
        case replyToUserId
        case replyToDisplayName
        case replyToTextPreview
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        guard type == "chat" else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown")
        }
        let replyTo = Self.decodeReplyReference(from: c)
        let imageURL = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        let tradeID = try c.decodeIfPresent(String.self, forKey: .tradeId)
        self = .chat(
            userId: try c.decode(String.self, forKey: .userId),
            displayName: try c.decode(String.self, forKey: .displayName),
            avatarUrl: try c.decodeIfPresent(String.self, forKey: .avatarUrl),
            text: try c.decode(String.self, forKey: .text),
            sentAt: try c.decode(Double.self, forKey: .sentAt),
            imageURL: imageURL,
            tradeID: tradeID,
            replyTo: replyTo
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .chat(userId, displayName, avatarUrl, text, sentAt, imageURL, tradeID, replyTo):
            try c.encode("chat", forKey: .type)
            try c.encode(userId, forKey: .userId)
            try c.encode(displayName, forKey: .displayName)
            try c.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
            try c.encode(text, forKey: .text)
            try c.encode(sentAt, forKey: .sentAt)
            if let imageURL, BroadcastChatAttachmentPolicy.isAllowedBroadcastImageURL(imageURL) {
                try c.encode(imageURL, forKey: .imageUrl)
            }
            if let tradeID {
                let trimmed = tradeID.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    try c.encode(trimmed, forKey: .tradeId)
                }
            }
            if let replyTo {
                try c.encode(replyTo.messageId, forKey: .replyToMessageId)
                try c.encode(replyTo.userId, forKey: .replyToUserId)
                try c.encode(replyTo.displayName, forKey: .replyToDisplayName)
                try c.encode(replyTo.textPreview, forKey: .replyToTextPreview)
            }
        }
    }

    static func encodeOutgoing(
        userId: String,
        displayName: String,
        avatarUrl: String?,
        text: String,
        imageURL: String? = nil,
        tradeID: TradeID? = nil,
        replyTo: BroadcastChatReplyReference? = nil
    ) throws -> Data {
        try JSONEncoder().encode(
            BroadcastChatPayload.chat(
                userId: userId,
                displayName: displayName,
                avatarUrl: avatarUrl,
                text: text,
                sentAt: Date().timeIntervalSince1970 * 1000,
                imageURL: imageURL,
                tradeID: tradeID?.rawValue,
                replyTo: replyTo
            )
        )
    }

    static func parseIncoming(data: Data, senderIdentity: String) -> BroadcastChatMessageItem? {
        guard let payload = try? JSONDecoder().decode(BroadcastChatPayload.self, from: data) else {
            return nil
        }
        guard case let .chat(userId, displayName, _, text, sentAt, imageURL, tradeIDRaw, replyTo) = payload else {
            return nil
        }
        guard userId == senderIdentity else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedImage = imageURL.flatMap { url -> String? in
            BroadcastChatAttachmentPolicy.isAllowedBroadcastImageURL(url) ? url : nil
        }
        let sanitizedTrade = BroadcastChatAttachmentPolicy.sanitizedTradeID(tradeIDRaw)
        guard !trimmed.isEmpty || sanitizedImage != nil || sanitizedTrade != nil else { return nil }
        if !trimmed.isEmpty, trimmed.count > TradeRoomBroadcastChatConstants.maxLength {
            return nil
        }
        let sanitizedReply: BroadcastChatReplyReference? = {
            guard let replyTo else { return nil }
            return isValidReplyReference(replyTo) ? replyTo : nil
        }()
        return BroadcastChatMessageItem(
            id: "\(userId)-\(Int(sentAt))",
            userId: userId,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Member"
                : displayName,
            text: trimmed,
            sentAt: Date(timeIntervalSince1970: sentAt / 1000),
            imageURL: sanitizedImage,
            tradeID: sanitizedTrade,
            replyTo: sanitizedReply
        )
    }

    private static func decodeReplyReference(from c: KeyedDecodingContainer<CodingKeys>) -> BroadcastChatReplyReference? {
        guard let messageId = try? c.decode(String.self, forKey: .replyToMessageId) else {
            return nil
        }
        let trimmedId = messageId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return nil }
        guard
            let userId = try? c.decode(String.self, forKey: .replyToUserId),
            let displayName = try? c.decode(String.self, forKey: .replyToDisplayName),
            let textPreview = try? c.decode(String.self, forKey: .replyToTextPreview)
        else {
            return nil
        }
        return BroadcastChatReplyReference(
            messageId: trimmedId,
            userId: userId.trimmingCharacters(in: .whitespacesAndNewlines),
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            textPreview: textPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func isValidReplyReference(_ reply: BroadcastChatReplyReference) -> Bool {
        guard !reply.messageId.isEmpty, !reply.userId.isEmpty else { return false }
        guard !reply.displayName.isEmpty, !reply.textPreview.isEmpty else { return false }
        return reply.textPreview.count <= TradeRoomBroadcastChatConstants.replyPreviewMaxLength + 4
    }
}