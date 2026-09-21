import Foundation

/// Feed `rpc_v1_feed_bootstrap` nested trade payload → canonical ``TradeSummary`` (no full ``Trade``).
nonisolated enum TradeSummaryFeedMapper {
    static func mapTradeRow(_ row: FeedItemV1) -> TradeSummary? {
        guard let tradeID = string(row.payload, keys: ["trade_id"]),
              !tradeID.isEmpty
        else { return nil }

        let nested = object(row.payload["trades"]) ?? [:]
        let wire = TradeSummaryWireV1(
            summary_schema: "trade_summary_v1",
            id: tradeID,
            user_id: string(row.payload, keys: ["user_id"]) ?? row.author_id,
            ticker: string(nested, keys: ["ticker"]),
            direction: string(nested, keys: ["direction"]),
            pnl: flexibleNumber(row.payload["pnl"]) ?? flexibleNumber(nested["pnl"]),
            rr: flexibleNumber(row.payload["rr"]) ?? flexibleNumber(nested["rr"]),
            points: flexibleNumber(nested["points"]),
            contracts: flexibleNumber(nested["contracts"]),
            entry_time: string(nested, keys: ["entry_time"]) ?? row.created_at,
            exit_time: string(nested, keys: ["exit_time"]),
            created_at: row.created_at,
            is_public: PostgresFlexibleBool(boolValue(nested["is_public"]) ?? true),
            public_description: string(nested, keys: ["public_description"]),
            note_preview: string(nested, keys: ["note_preview", "public_description"]),
            image_url: string(row.payload, keys: ["image_url"]),
            image_crop: decodeImageCrop(row.payload["image_crop"]),
            image_display_mode: string(nested, keys: ["image_display_mode"]),
            mode: string(nested, keys: ["mode"]),
            account_type: string(nested, keys: ["account_type"]),
            trade_mode: string(nested, keys: ["trade_mode"]),
            duration_seconds: flexibleNumber(nested["duration_seconds"]),
            duration_text: string(nested, keys: ["duration_text"])
        )
        return try? TradeSummaryMapper.map(from: wire)
    }

    static func mapLinkedTradePayload(
        payload: [String: JSONValue],
        tradeID: TradeID,
        authorID: String
    ) -> TradeSummary? {
        let nested = object(payload["trades"]) ?? payload
        let wire = TradeSummaryWireV1(
            summary_schema: "trade_summary_v1",
            id: tradeID.rawValue,
            user_id: string(nested, keys: ["user_id"]) ?? authorID,
            ticker: string(nested, keys: ["ticker"]),
            direction: string(nested, keys: ["direction"]),
            pnl: flexibleNumber(nested["pnl"]),
            rr: flexibleNumber(nested["rr"]),
            points: flexibleNumber(nested["points"]),
            contracts: flexibleNumber(nested["contracts"]),
            entry_time: string(nested, keys: ["entry_time"]) ?? string(payload, keys: ["created_at"]),
            exit_time: string(nested, keys: ["exit_time"]),
            created_at: string(nested, keys: ["created_at"])
                ?? string(payload, keys: ["created_at"])
                ?? "",
            is_public: PostgresFlexibleBool(boolValue(nested["is_public"]) ?? true),
            public_description: string(nested, keys: ["public_description"]),
            note_preview: string(nested, keys: ["note_preview", "public_description"]),
            image_url: string(payload, keys: ["image_url"]),
            image_crop: decodeImageCrop(payload["image_crop"]),
            image_display_mode: string(nested, keys: ["image_display_mode"]),
            mode: string(nested, keys: ["mode"]),
            account_type: string(nested, keys: ["account_type"]),
            trade_mode: string(nested, keys: ["trade_mode"]),
            duration_seconds: flexibleNumber(nested["duration_seconds"]),
            duration_text: string(nested, keys: ["duration_text"])
        )
        return try? TradeSummaryMapper.map(from: wire)
    }

    // MARK: - JSON helpers (FeedRpcProjectionSeeder parity)

    private static func string(_ payload: [String: JSONValue], keys: [String]) -> String? {
        for key in keys {
            if case .string(let value) = payload[key], !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func object(_ value: JSONValue?) -> [String: JSONValue]? {
        guard case .object(let nested) = value else { return nil }
        return nested
    }

    private static func flexibleNumber(_ value: JSONValue?) -> PostgresFlexibleDouble? {
        switch value {
        case .number(let n):
            return PostgresFlexibleDouble(n)
        case .string(let s):
            if let d = Double(s) { return PostgresFlexibleDouble(d) }
            return nil
        default:
            return nil
        }
    }

    private static func boolValue(_ value: JSONValue?) -> Bool? {
        switch value {
        case .bool(let b): return b
        case .number(let n): return n != 0
        default: return nil
        }
    }

    private static func decodeImageCrop(_ value: JSONValue?) -> JSONValue? {
        value
    }
}
