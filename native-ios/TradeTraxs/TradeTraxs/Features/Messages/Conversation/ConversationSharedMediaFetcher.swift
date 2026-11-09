import Foundation

/// Paginated `get_conversation_shared_media` — same contract as web `conversationSharedMedia.ts`.
nonisolated enum ConversationSharedMediaFetcher {
    private struct RPCParams: Encodable {
        let p_conversation_id: String
        let p_before_created_at: String?
        let p_before_id: String?
        let p_limit: Int
    }

    private struct RPCRow: Decodable {
        let message_id: String?
        let sender_id: String?
        let image_url: String?
        let created_at: String?
    }

    static func fetch(
        conversationID: ConversationID,
        cursor: ConversationSharedMediaCursor?,
        rpc: any RPCClient
    ) async -> ConversationSharedMediaFetchResult {
        let params = RPCParams(
            p_conversation_id: conversationID.rawValue,
            p_before_created_at: cursor?.createdAt,
            p_before_id: cursor?.id.rawValue,
            p_limit: ConversationSharedMediaSupport.pageSize
        )
        do {
            let body = try JSONEncoder().encode(params)
            let data = try await rpc.call(
                functionName: "get_conversation_shared_media",
                jsonBody: body
            )
            let rows = try JSONDecoder().decode([RPCRow].self, from: data)
            let items = rows.compactMap(mapRow)
            return .success(items)
        } catch {
            return .failure(UserFacingError.message(for: error))
        }
    }

    private static func mapRow(_ row: RPCRow) -> ConversationSharedMediaItem? {
        let messageID = (row.message_id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let imageURL = (row.image_url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let createdAt = (row.created_at ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageID.isEmpty, !imageURL.isEmpty, !createdAt.isEmpty else { return nil }
        let sender: ProfileID?
        if let raw = row.sender_id?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            sender = ProfileID(raw)
        } else {
            sender = nil
        }
        return ConversationSharedMediaItem(
            id: MessageID(messageID),
            senderID: sender,
            imageURL: imageURL,
            createdAt: createdAt
        )
    }
}

/// In-memory gallery cache for the app session — avoids refetching page 1 on every open.
actor ConversationSharedMediaSessionCache {
    static let shared = ConversationSharedMediaSessionCache()

    struct Snapshot: Sendable {
        var items: [ConversationSharedMediaItem]
        var hasMore: Bool
    }

    private var snapshots: [String: Snapshot] = [:]

    func snapshot(conversationID: ConversationID) -> Snapshot? {
        snapshots[conversationID.rawValue]
    }

    func replace(conversationID: ConversationID, items: [ConversationSharedMediaItem], hasMore: Bool) {
        snapshots[conversationID.rawValue] = Snapshot(items: items, hasMore: hasMore)
    }

    func clear(conversationID: ConversationID) {
        snapshots.removeValue(forKey: conversationID.rawValue)
    }
}
