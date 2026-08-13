import Foundation

/// Inbox bootstrap — conversations plus profiles already embedded in the PostgREST join.
nonisolated struct ConversationListResult: Sendable {
    var items: [Conversation]
    var nextCursor: String?
    /// Participant profiles from `conversation_participants.profiles(...)` — seed session cache.
    var embeddedProfiles: [Profile]

    var page: CursorPage<Conversation> {
        CursorPage(items: items, nextCursor: nextCursor)
    }
}

nonisolated protocol MessageRepository: Sendable {
    /// Inbox list — web `fetchUserDmConversations` + unread/mute pipeline.
    func conversations(page: PageRequest) async throws -> ConversationListResult
    func conversation(id: ConversationID) async throws -> Conversation
    func messages(
        in conversationID: ConversationID,
        page: PageRequest
    ) async throws -> CursorPage<Message>
    func send(_ message: Message) async throws -> Message
    /// Web `mark_conversation_read(p_conversation_id)` — no extra parameters.
    func markRead(conversationID: ConversationID) async throws
    /// Web `ensureDmConversation` — find existing 1:1 or create shell + participants.
    func createConversation(participantIDs: [ProfileID]) async throws -> Conversation
    /// Web messages `handleDeleteConversation` — delete own `conversation_participants` row.
    func deleteConversation(id: ConversationID) async throws
}
