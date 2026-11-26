import Foundation

/// Web `handleLeaveConversation` system line copy.
nonisolated enum GroupLeaveSystemMessage {
    static func sanitizedActorName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Someone" : trimmed
    }

    static func body(displayName: String) -> String {
        "\(sanitizedActorName(displayName)) left the group"
    }
}

/// Local conversation + inbox merges for group metadata (no UI).
@MainActor
enum GroupConversationLocalMetadata {
    static func apply(saved: Conversation, to conversation: inout Conversation?) {
        conversation = saved
    }

    static func publish(saved: Conversation, inboxStore: MessagesInboxStore) {
        inboxStore.applyConversationUpdate(saved)
    }

    static func leaverDisplayName(viewerID: ProfileID, detailCache: DetailPresentationCache) -> String {
        guard let profile = detailCache.profile(id: viewerID) else { return "Someone" }
        let username = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        return username.isEmpty ? "Someone" : username
    }
}