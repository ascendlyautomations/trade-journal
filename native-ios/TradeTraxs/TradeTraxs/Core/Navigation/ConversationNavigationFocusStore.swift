import Foundation

/// Per-conversation DM navigation intents (push / deep link) with monotonic revisions.
///
/// Seed before ``NavigationCoordinator/openExternal``; ``ConversationViewModel`` applies once the thread is ready.
@MainActor
final class ConversationNavigationFocusStore {
    static let shared = ConversationNavigationFocusStore()

    struct NavigationIntent: Equatable, Sendable {
        var conversationID: ConversationID
        var messageID: MessageID?
        var revision: UInt64 = 0
    }

    private var intents: [ConversationID: NavigationIntent] = [:]
    private var revisionByConversation: [ConversationID: UInt64] = [:]

    private init() {}

    func seed(conversationID: ConversationID, messageID: String?) {
        let message = messageID.flatMap { raw -> MessageID? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : MessageID(trimmed)
        }
        let nextRevision = (revisionByConversation[conversationID] ?? 0) + 1
        let intent = NavigationIntent(
            conversationID: conversationID,
            messageID: message,
            revision: nextRevision
        )
        intents[conversationID] = intent
        revisionByConversation[conversationID] = nextRevision
        NotificationCenter.default.post(
            name: .conversationNavigationFocusDidSeed,
            object: conversationID
        )
    }

    func intentRevision(for conversationID: ConversationID) -> UInt64 {
        revisionByConversation[conversationID] ?? 0
    }

    func pendingIntent(for conversationID: ConversationID) -> NavigationIntent? {
        intents[conversationID]
    }

    func acknowledgeIntent(for conversationID: ConversationID, revision: UInt64) {
        guard let intent = intents[conversationID], intent.revision == revision else { return }
        intents.removeValue(forKey: conversationID)
    }

    func cancelIntent(for conversationID: ConversationID) {
        intents.removeValue(forKey: conversationID)
    }
}

extension Notification.Name {
    static let conversationNavigationFocusDidSeed = Notification.Name("conversationNavigationFocusDidSeed")
}
