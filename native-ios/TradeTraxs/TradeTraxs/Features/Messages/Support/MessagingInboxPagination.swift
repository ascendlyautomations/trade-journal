import Foundation

/// Inbox bootstrap pagination + Realtime watch window (V2 RPC cursor).
enum MessagingInboxPagination {
    nonisolated static let pageSize = 40
    /// Recent inbox rows subscribed on `inbox-dms` — not every paginated historical row.
    static let realtimeWatchConversationCount = 40

    static func conversationIDsForRealtimeWatch(
        _ conversations: [Conversation],
        alwaysInclude conversationID: ConversationID? = nil
    ) -> [String] {
        var ids = Array(conversations.prefix(realtimeWatchConversationCount).map(\.id.rawValue))
        if let conversationID,
           !ids.contains(conversationID.rawValue)
        {
            ids.append(conversationID.rawValue)
        }
        return ids
    }
}
