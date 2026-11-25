import Foundation

/// Broadcasts shared-entity deletions to open threads and cached DM snapshots.
@MainActor
final class MessagingSharedContentDeletionCoordinator {
    static let shared = MessagingSharedContentDeletionCoordinator()

    private var handlers: [UUID: (Set<String>) -> Void] = [:]

    private init() {}

    @discardableResult
    func addHandler(_ handler: @escaping (Set<String>) -> Void) -> UUID {
        let token = UUID()
        handlers[token] = handler
        return token
    }

    func removeHandler(_ token: UUID) {
        handlers.removeValue(forKey: token)
    }

    func noteUnavailableKeys(_ keys: Set<String>) {
        guard !keys.isEmpty else { return }
        for handler in handlers.values {
            handler(keys)
        }
        if let viewerID = MessagesInboxStore.shared.persistedViewerID {
            ConversationThreadSessionStore.shared.reconcileUnavailableSharedContent(
                viewerID: viewerID,
                unavailableKeys: keys
            )
        }
    }

    func noteTradeDeleted(_ tradeID: TradeID) {
        noteUnavailableKeys(SharedContentMessageReconciliation.stableKeys(forDeletedTradeID: tradeID))
    }

    func notePostDeleted(_ postID: PostID) {
        noteUnavailableKeys(SharedContentMessageReconciliation.stableKeys(forDeletedPostID: postID))
    }

    func noteReelDeleted(_ reelID: ReelID) {
        noteUnavailableKeys(SharedContentMessageReconciliation.stableKeys(forDeletedReelID: reelID))
    }

    private(set) var latestDeletedAchievementID: AchievementID?

    func noteAchievementDeleted(_ achievementID: AchievementID) {
        latestDeletedAchievementID = achievementID
        for handler in handlers.values {
            handler([])
        }
    }
}