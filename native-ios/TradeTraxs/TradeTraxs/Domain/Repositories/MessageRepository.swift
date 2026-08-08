import Foundation

nonisolated protocol MessageRepository: Sendable {
    func conversations(page: PageRequest) async throws -> CursorPage<Conversation>
    func conversation(id: ConversationID) async throws -> Conversation
    func messages(
        in conversationID: ConversationID,
        page: PageRequest
    ) async throws -> CursorPage<Message>
    func send(_ message: Message) async throws -> Message
    func markRead(conversationID: ConversationID, upTo messageID: MessageID) async throws
    func createConversation(participantIDs: [ProfileID]) async throws -> Conversation
}
