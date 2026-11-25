import Foundation

struct BroadcastFloatingReaction: Identifiable, Hashable, Sendable {
    var id: String
    var emoji: String
    var userId: String
    var sentAt: Date
    /// 0…1 horizontal anchor on the video layer.
    var originX: CGFloat
}

enum TradeRoomBroadcastReactionConstants {
    static let topic = "tt_broadcast_reaction"
    static let minInterval: TimeInterval = 0.3
    static let burstMax = 12
    static let burstWindow: TimeInterval = 8
}

enum BroadcastReactionSignaling {
    private struct Payload: Codable {
        var type: String
        var userId: String
        var emoji: String
        var sentAt: Double
        var originX: Double?
    }

    static func encodeOutgoing(
        userId: String,
        emoji: String,
        originX: Double?
    ) throws -> Data {
        guard let normalized = MessageReactionValidation.normalize(emoji) else {
            throw NSError(domain: "BroadcastReaction", code: 1)
        }
        let payload = Payload(
            type: "reaction",
            userId: userId,
            emoji: normalized,
            sentAt: Date().timeIntervalSince1970 * 1000,
            originX: originX
        )
        return try JSONEncoder().encode(payload)
    }

    static func parseIncoming(data: Data, senderIdentity: String) -> BroadcastFloatingReaction? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.type == "reaction",
              payload.userId == senderIdentity,
              let emoji = MessageReactionValidation.normalize(payload.emoji)
        else { return nil }

        let originX: CGFloat
        if let raw = payload.originX, raw >= 0, raw <= 1 {
            originX = CGFloat(raw)
        } else {
            originX = CGFloat.random(in: 0.2 ... 0.8)
        }

        let sentAt = Date(timeIntervalSince1970: payload.sentAt / 1000)
        return BroadcastFloatingReaction(
            id: "\(payload.userId)-\(Int(payload.sentAt))-\(emoji)",
            emoji: emoji,
            userId: payload.userId,
            sentAt: sentAt,
            originX: originX
        )
    }
}