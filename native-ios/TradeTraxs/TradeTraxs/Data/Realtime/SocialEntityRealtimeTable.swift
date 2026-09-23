import Foundation

/// Postgres tables that back Feed/Profile social entities (not likes/comments).
nonisolated enum SocialEntityRealtimeTable: String, Sendable, CaseIterable {
    case posts
    case profilePosts = "profile_posts"
    case trades
    case reels
    case achievementPosts = "achievement_posts"

    var authorColumn: String { "user_id" }
    var idColumn: String { "id" }

    static let inFilterMaxIDs = 100

    static func realtimeAuthorFilter(table: SocialEntityRealtimeTable, authorIDs: [String]) -> String {
        let unique = Array(Set(authorIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
            .sorted()
        guard !unique.isEmpty, unique.count <= inFilterMaxIDs else {
            return "\(table.authorColumn)=eq.__invalid_empty__"
        }
        return "\(table.authorColumn)=in.(\(unique.joined(separator: ",")))"
    }

    static func realtimeEntityFilter(table: SocialEntityRealtimeTable, entityIDs: [String]) -> String {
        let unique = Array(Set(entityIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
            .sorted()
        guard !unique.isEmpty, unique.count <= inFilterMaxIDs else {
            return "\(table.idColumn)=eq.__invalid_empty__"
        }
        return "\(table.idColumn)=in.(\(unique.joined(separator: ",")))"
    }

    static func stableRouteSuffix(table: SocialEntityRealtimeTable, key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "\(table.rawValue)-empty" }
        return "\(table.rawValue)-\(trimmed.prefix(48))"
    }
}

nonisolated enum SocialEntityRealtimeMutation: Sendable {
    case insert
    case update
    case delete
}

/// Canonical internal entity Realtime signal — parsed from postgres_changes payloads.
nonisolated struct SocialEntityRealtimeEvent: Sendable, Hashable {
    var table: SocialEntityRealtimeTable
    var mutation: SocialEntityRealtimeMutation
    var entityID: String
    var authorID: String?
    /// Like row id — duplicate delivery dedupe.
    var eventRowID: String?
    var payload: SocialEntityRealtimePayload
}

/// Narrow summary seed from Realtime row — not authoritative detail.
nonisolated struct SocialEntityRealtimePayload: Sendable, Hashable {
    var caption: String?
    var mediaURL: String?
    var tradeID: String?
    var achievementID: String?
    var createdAt: Date?
    var isPublic: Bool?
    var imageCropJSON: String?
}

nonisolated enum SocialEntityRealtimeSemantics {
    static func parseEvent(
        table: SocialEntityRealtimeTable,
        mutation: SocialEntityRealtimeMutation,
        record: [String: Any]?,
        oldRecord: [String: Any]?
    ) -> SocialEntityRealtimeEvent? {
        let row = record ?? oldRecord
        guard let row else { return nil }
        let entityID = (row[table.idColumn] as? String) ?? ""
        guard !entityID.isEmpty else { return nil }
        let authorID = row[table.authorColumn] as? String

        var payload = SocialEntityRealtimePayload()
        payload.caption = (row["content"] as? String) ?? (row["description"] as? String) ?? (row["caption"] as? String)
        payload.mediaURL = (row["image_url"] as? String) ?? (row["video_url"] as? String) ?? (row["thumbnail_url"] as? String)
        payload.tradeID = row["trade_id"] as? String
        payload.achievementID = row["achievement_id"] as? String
        if let created = row["created_at"] as? String {
            payload.createdAt = ISO8601DateFormatter().date(from: created)
        }
        if let isPublic = row["is_public"] as? Bool {
            payload.isPublic = isPublic
        } else if let isPublic = row["is_public"] as? NSNumber {
            payload.isPublic = isPublic.boolValue
        }
        if let crop = row["image_crop"] {
            if let data = try? JSONSerialization.data(withJSONObject: crop),
               let text = String(data: data, encoding: .utf8)
            {
                payload.imageCropJSON = text
            }
        }

        return SocialEntityRealtimeEvent(
            table: table,
            mutation: mutation,
            entityID: entityID,
            authorID: authorID,
            eventRowID: entityID,
            payload: payload
        )
    }
}
