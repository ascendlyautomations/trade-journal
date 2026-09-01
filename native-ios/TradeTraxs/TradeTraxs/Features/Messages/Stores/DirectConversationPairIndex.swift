import Foundation

/// Viewer-scoped canonical index: direct user pair → conversation ID.
///
/// Keys use sorted normalized profile IDs (`min|max`) so selection order is irrelevant.
@MainActor
final class DirectConversationPairIndex {
    static let shared = DirectConversationPairIndex()

    private var byPairKey: [String: ConversationID] = [:]

    private init() {}

    nonisolated static func pairKey(_ a: ProfileID, _ b: ProfileID) -> String {
        let normalized = [a.rawValue.lowercased(), b.rawValue.lowercased()].sorted()
        return "\(normalized[0])|\(normalized[1])"
    }

    nonisolated static func pairKey(viewerID: ProfileID, recipientID: ProfileID) -> String {
        pairKey(viewerID, recipientID)
    }

    func conversationID(viewerID: ProfileID, recipientID: ProfileID) -> ConversationID? {
        byPairKey[Self.pairKey(viewerID, recipientID)]
    }

    func register(conversation: Conversation) {
        guard !conversation.isGroup else { return }
        guard conversation.participantProfileIDs.count == 2 else { return }
        let ids = conversation.participantProfileIDs.map { $0.rawValue.lowercased() }.sorted()
        let key = "\(ids[0])|\(ids[1])"
        if let existing = byPairKey[key] {
            // Deterministic duplicate-data rule — keep lexicographically smallest ID.
            if conversation.id.rawValue < existing.rawValue {
                byPairKey[key] = conversation.id
            }
        } else {
            byPairKey[key] = conversation.id
        }
    }

    func rebuild(from conversations: [Conversation]) {
        byPairKey = [:]
        for conversation in conversations where !conversation.isGroup {
            register(conversation: conversation)
        }
    }

    func invalidate() {
        byPairKey = [:]
    }
}
