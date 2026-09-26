import Foundation

/// Encodes ``trade_ai_messages`` insert rows for PostgREST (JSON array of objects).
nonisolated enum TradeAIMessagePersistence {
    static func sanitizeContent(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return " " }
        return trimmed
    }

    static func makeInsertRows(
        messages: [TradeAIMessage],
        tradeID: TradeID,
        userID: UserID
    ) -> [TradeAIMessageInsertRow] {
        messages.map { message in
            TradeAIMessageInsertRow(
                id: message.id,
                trade_id: tradeID.rawValue,
                user_id: userID.rawValue,
                role: message.role.rawValue,
                content: sanitizeContent(message.content),
                prompt_key: message.promptKey,
                created_at: ISO8601.string(from: message.createdAt)
            )
        }
    }

    static func encodeInsertPayload(_ rows: [TradeAIMessageInsertRow]) throws -> Data {
        try SupabaseJSONEncoding.encode(rows)
    }
}

/// Wire shape for `public.trade_ai_messages` inserts.
nonisolated struct TradeAIMessageInsertRow: Encodable, Sendable, Equatable {
    var id: String
    var trade_id: String
    var user_id: String
    var role: String
    var content: String
    var prompt_key: String?
    var created_at: String
}
