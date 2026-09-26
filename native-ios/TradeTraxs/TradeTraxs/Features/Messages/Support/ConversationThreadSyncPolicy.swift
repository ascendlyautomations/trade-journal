import Foundation
import os

/// Inbox preview vs open-thread consistency — detect when summary is ahead of local rows.
nonisolated enum ConversationThreadSyncPolicy {
    /// Inbox row references a message not present in the local thread window.
    static func isInboxAheadOfThread(inbox: Conversation?, threadMessages: [Message]) -> Bool {
        guard let inbox else { return false }
        if let headID = inbox.lastMessageID {
            if threadMessages.contains(where: { $0.id == headID }) {
                return false
            }
            return true
        }
        guard let inboxAt = inbox.lastMessageAt else { return false }
        guard let newest = ConversationMessageMerge.sortByCreatedAt(threadMessages).last else {
            return true
        }
        return inboxAt > newest.createdAt
    }

    static func localNewestMessageID(in threadMessages: [Message]) -> MessageID? {
        ConversationMessageMerge.sortByCreatedAt(threadMessages).last?.id
    }
}

#if DEBUG
enum MessageSyncLog {
    private static let logger = AppLog.realtime

    static func inboxPreviewUpdated(conversationID: ConversationID, messageID: MessageID) {
        logger.debug(
            "[MessageSync] inboxPreviewUpdated conversationID=\(conversationID.rawValue, privacy: .public) messageID=\(messageID.rawValue, privacy: .public)"
        )
    }

    static func conversationOpened(conversationID: ConversationID, localNewestID: MessageID?) {
        logger.debug(
            "[MessageSync] conversationOpened conversationID=\(conversationID.rawValue, privacy: .public) localNewestID=\(localNewestID?.rawValue ?? "nil", privacy: .public)"
        )
    }

    static func reconcileStarted(conversationID: ConversationID, after: MessageID?) {
        logger.debug(
            "[MessageSync] reconcileStarted conversationID=\(conversationID.rawValue, privacy: .public) after=\(after?.rawValue ?? "nil", privacy: .public)"
        )
    }

    static func missingMessageReceived(conversationID: ConversationID, messageID: MessageID) {
        logger.debug(
            "[MessageSync] missingMessageReceived conversationID=\(conversationID.rawValue, privacy: .public) messageID=\(messageID.rawValue, privacy: .public)"
        )
    }

    static func persisted(conversationID: ConversationID, messageID: MessageID) {
        logger.debug(
            "[MessageSync] persisted conversationID=\(conversationID.rawValue, privacy: .public) messageID=\(messageID.rawValue, privacy: .public)"
        )
    }

    static func visibleThreadUpdated(conversationID: ConversationID, messageID: MessageID) {
        logger.debug(
            "[MessageSync] visibleThreadUpdated conversationID=\(conversationID.rawValue, privacy: .public) messageID=\(messageID.rawValue, privacy: .public)"
        )
    }

    static func realtimeApplied(conversationID: ConversationID, messageID: MessageID) {
        logger.debug(
            "[MessageSync] realtimeApplied conversationID=\(conversationID.rawValue, privacy: .public) messageID=\(messageID.rawValue, privacy: .public)"
        )
    }
}
#else
enum MessageSyncLog {
    static func inboxPreviewUpdated(conversationID: ConversationID, messageID: MessageID) {}
    static func conversationOpened(conversationID: ConversationID, localNewestID: MessageID?) {}
    static func reconcileStarted(conversationID: ConversationID, after: MessageID?) {}
    static func missingMessageReceived(conversationID: ConversationID, messageID: MessageID) {}
    static func persisted(conversationID: ConversationID, messageID: MessageID) {}
    static func visibleThreadUpdated(conversationID: ConversationID, messageID: MessageID) {}
    static func realtimeApplied(conversationID: ConversationID, messageID: MessageID) {}
}
#endif
