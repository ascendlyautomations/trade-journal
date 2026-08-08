import Foundation

nonisolated protocol SendMessageUseCase: Sendable {
    func execute(
        conversationID: ConversationID,
        body: String,
        attachments: [MessageAttachment]
    ) async throws -> Message
}
