import Foundation

nonisolated protocol MessageRepository: Sendable {
    /// Inbox list — web `fetchUserDmConversations` + unread/mute pipeline.
    func conversations(page: PageRequest) async throws -> CursorPage<Conversation>
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
