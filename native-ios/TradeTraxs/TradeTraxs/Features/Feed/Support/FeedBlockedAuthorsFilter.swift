import Foundation

/// Session-scoped blocked-author set for Feed filtering (bidirectional block semantics).
///
/// Populated once per bootstrap via ``get_active_block_peer_ids`` and updated immediately on block/unblock.
@MainActor
final class FeedBlockedAuthorsFilter {
    static let shared = FeedBlockedAuthorsFilter()

    private(set) var blockedPeerIDs: Set<ProfileID> = []
    private(set) var hasSyncedFromServer = false

    private init() {}

    func replaceAll(_ peers: Set<ProfileID>) {
        blockedPeerIDs = peers
    }

    /// Loads bidirectional block peers once per session unless ``force`` (pull-to-refresh).
    func syncFromServer(messages: any MessageRepository, force: Bool) async {
        if hasSyncedFromServer, !force { return }
        guard let peers = try? await messages.fetchActiveBlockPeerIDs() else { return }
        replaceAll(peers)
        hasSyncedFromServer = true
    }

    func noteBlock(peerID: ProfileID) {
        blockedPeerIDs.insert(peerID)
    }

    func noteUnblock(peerID: ProfileID) {
        blockedPeerIDs.remove(peerID)
    }

    func clear() {
        blockedPeerIDs = []
        hasSyncedFromServer = false
    }

    func contains(_ profileID: ProfileID) -> Bool {
        blockedPeerIDs.contains(profileID)
    }

    func filterEntries(_ entries: [FeedTimelineEntry]) -> [FeedTimelineEntry] {
        guard !blockedPeerIDs.isEmpty else { return entries }
        return entries.filter { !contains($0.authorProfileID) }
    }

    func filterStories(_ stories: [Story], viewerID: ProfileID) -> [Story] {
        guard !blockedPeerIDs.isEmpty else { return stories }
        return stories.filter {
            $0.authorProfileID == viewerID || !contains($0.authorProfileID)
        }
    }

    func filterConversationMessages(_ messages: [Message], viewerID: ProfileID?) -> [Message] {
        guard !blockedPeerIDs.isEmpty else { return messages }
        return messages.filter { message in
            if message.senderProfileID == viewerID { return true }
            return !contains(message.senderProfileID)
        }
    }

#if DEBUG
    func resetForTesting() {
        blockedPeerIDs = []
    }
#endif
}
