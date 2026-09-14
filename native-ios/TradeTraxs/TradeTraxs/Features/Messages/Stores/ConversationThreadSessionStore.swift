import Foundation

/// Session memory for personal conversation thread first pages.
@MainActor
final class ConversationThreadSessionStore {
    static let shared = ConversationThreadSessionStore()

    static let messageLimit = 50
    static let softStaleInterval: TimeInterval = 60

    struct Snapshot: Sendable {
        var cacheKey: String
        var conversation: Conversation
        var messages: [Message]
        var nextCursor: String?
        var hasMoreMessages: Bool
        var loadedAt: Date
        /// Monotonic per-conversation generation — bumped on every local patch.
        var contentGeneration: UInt64

        var isSoftStale: Bool {
            Date().timeIntervalSince(loadedAt) > ConversationThreadSessionStore.softStaleInterval
        }
    }

    private var snapshots: [String: Snapshot] = [:]

    private init() {}

    static func cacheKey(viewerID: ProfileID, conversationID: ConversationID) -> String {
        "\(viewerID.rawValue)|\(conversationID.rawValue)"
    }

    func restore(key: String) -> Snapshot? {
        if let cached = snapshots[key] {
            return cached
        }
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let viewerID = ProfileID(parts[0])
        let conversationID = ConversationID(parts[1])
        guard let disk = SocialPersistedCacheCoordinator.restoreDMThread(
            viewerID: viewerID,
            conversationID: conversationID
        ) else {
            return nil
        }
        snapshots[key] = disk
        return disk
    }

    func save(_ snapshot: Snapshot) {
        snapshots[snapshot.cacheKey] = snapshot
        persistSnapshot(snapshot)
    }

    /// Merge canonical server/local rows into the cached first page (web `patchConversationThreadMessages`).
    func patchMessages(
        viewerID: ProfileID,
        conversationID: ConversationID,
        incoming: [Message],
        conversation: Conversation? = nil
    ) {
        guard !incoming.isEmpty else { return }
        let key = Self.cacheKey(viewerID: viewerID, conversationID: conversationID)
        if var snapshot = snapshots[key] {
            let merged = ConversationMessageMerge.reconcileServerFirstPage(
                existing: snapshot.messages,
                incoming: incoming
            )
            snapshot.messages = Self.newestPage(from: merged, limit: Self.messageLimit)
            if let conversation {
                snapshot.conversation = conversation
            }
            snapshot.loadedAt = Date()
            snapshot.contentGeneration &+= 1
            snapshots[key] = snapshot
            persistSnapshot(snapshot)
            return
        }
        guard let conversation else { return }
        let created = Snapshot(
            cacheKey: key,
            conversation: conversation,
            messages: Self.newestPage(from: incoming, limit: Self.messageLimit),
            nextCursor: nil,
            hasMoreMessages: false,
            loadedAt: Date(),
            contentGeneration: 1
        )
        snapshots[key] = created
        persistSnapshot(created)
    }

    /// Persist RPC/bootstrap first page without dropping newer locally patched rows.
    func saveMergedFirstPage(
        cacheKey: String,
        conversation: Conversation,
        incoming: [Message],
        nextCursor: String?,
        hasMoreMessages: Bool
    ) {
        let existing = snapshots[cacheKey]?.messages ?? []
        let merged = ConversationMessageMerge.reconcileServerFirstPage(
            existing: existing,
            incoming: incoming
        )
        let priorGeneration = snapshots[cacheKey]?.contentGeneration ?? 0
        let snapshot = Snapshot(
            cacheKey: cacheKey,
            conversation: conversation,
            messages: Self.cacheMessages(from: merged, existingCount: existing.count),
            nextCursor: nextCursor,
            hasMoreMessages: hasMoreMessages,
            loadedAt: Date(),
            contentGeneration: priorGeneration
        )
        save(snapshot)
    }

    /// Persist the full in-memory thread (including paginated history) for warm reopen.
    func syncOpenThreadState(
        viewerID: ProfileID,
        conversationID: ConversationID,
        conversation: Conversation,
        messages: [Message],
        nextCursor: String?,
        hasMoreMessages: Bool
    ) {
        let key = Self.cacheKey(viewerID: viewerID, conversationID: conversationID)
        let priorGeneration = snapshots[key]?.contentGeneration ?? 0
        save(
            Snapshot(
                cacheKey: key,
                conversation: conversation,
                messages: ConversationMessageMerge.sortByCreatedAt(messages),
                nextCursor: nextCursor,
                hasMoreMessages: hasMoreMessages,
                loadedAt: Date(),
                contentGeneration: priorGeneration &+ 1
            )
        )
    }

    private func persistSnapshot(_ snapshot: Snapshot) {
        let parts = snapshot.cacheKey.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        SocialPersistedCacheCoordinator.persistDMThread(
            viewerID: ProfileID(parts[0]),
            conversationID: ConversationID(parts[1]),
            snapshot: snapshot
        )
    }

    /// Keep paginated open-thread history; only truncate cold bootstrap pages.
    static func cacheMessages(from merged: [Message], existingCount: Int) -> [Message] {
        let sorted = ConversationMessageMerge.sortByCreatedAt(merged)
        if existingCount > messageLimit || sorted.count > messageLimit {
            return sorted
        }
        return newestPage(from: sorted, limit: messageLimit)
    }

    static func newestPage(from messages: [Message], limit: Int) -> [Message] {
        let sorted = ConversationMessageMerge.sortByCreatedAt(messages)
        guard sorted.count > limit else { return sorted }
        return Array(sorted.suffix(limit))
    }

    func removeMessage(
        viewerID: ProfileID,
        conversationID: ConversationID,
        messageID: MessageID
    ) {
        let key = Self.cacheKey(viewerID: viewerID, conversationID: conversationID)
        guard var snapshot = snapshots[key] else { return }
        snapshot.messages.removeAll { $0.id == messageID }
        snapshot.contentGeneration &+= 1
        snapshots[key] = snapshot
        persistSnapshot(snapshot)
    }

    func invalidate(viewerID: ProfileID? = nil, conversationID: ConversationID? = nil) {
        if let viewerID, let conversationID {
            snapshots.removeValue(forKey: Self.cacheKey(viewerID: viewerID, conversationID: conversationID))
            SocialPersistedCacheCoordinator.removeDMThread(viewerID: viewerID, conversationID: conversationID)
            return
        }
        if let viewerID {
            let prefix = viewerID.rawValue + "|"
            for key in snapshots.keys where key.hasPrefix(prefix) {
                let conversationID = ConversationID(String(key.dropFirst(prefix.count)))
                SocialPersistedCacheCoordinator.removeDMThread(viewerID: viewerID, conversationID: conversationID)
            }
            snapshots = snapshots.filter { !$0.key.hasPrefix(prefix) }
        } else {
            snapshots = [:]
        }
    }
}
