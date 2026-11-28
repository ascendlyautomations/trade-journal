import Foundation

@MainActor
final class GeneralTradeCoachSessionStore {
    static let shared = GeneralTradeCoachSessionStore()

    private(set) var pendingReopenConversationID: AIConversationID?

    private init() {}

    func noteReopenConversation(id: AIConversationID) {
        pendingReopenConversationID = id
    }

    func clearReopenConversation() {
        pendingReopenConversationID = nil
    }
}