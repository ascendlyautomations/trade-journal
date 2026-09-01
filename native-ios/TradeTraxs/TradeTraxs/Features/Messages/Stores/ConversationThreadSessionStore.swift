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
        snapshots[key]
    }

    func save(_ snapshot: Snapshot) {
        snapshots[snapshot.cacheKey] = snapshot
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
            let merged = ConversationMessageMerge.mergeMessageLists(
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
            return
        }
        guard let conversation else { return }
        snapshots[key] = Snapshot(
            cacheKey: key,
            conversation: conversation,
            messages: Self.newestPage(from: incoming, limit: Self.messageLimit),
            nextCursor: nil,
            hasMoreMessages: false,
            loadedAt: Date(),
            contentGeneration: 1
        )
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
        let merged = ConversationMessageMerge.mergeMessageLists(existing: existing, incoming: incoming)
        let priorGeneration = snapshots[cacheKey]?.contentGeneration ?? 0
        save(
            Snapshot(
                cacheKey: cacheKey,
                conversation: conversation,
                messages: Self.newestPage(from: merged, limit: Self.messageLimit),
                nextCursor: nextCursor,
                hasMoreMessages: hasMoreMessages,
                loadedAt: Date(),
                contentGeneration: priorGeneration
            )
        )
    }

    static func newestPage(from messages: [Message], limit: Int) -> [Message] {
        let sorted = ConversationMessageMerge.sortByCreatedAt(messages)
        guard sorted.count > limit else { return sorted }
        return Array(sorted.suffix(limit))
    }

    func invalidate(viewerID: ProfileID? = nil) {
        if let viewerID {
            let prefix = viewerID.rawValue + "|"
            snapshots = snapshots.filter { !$0.key.hasPrefix(prefix) }
        } else {
            snapshots = [:]
        }
    }
}
