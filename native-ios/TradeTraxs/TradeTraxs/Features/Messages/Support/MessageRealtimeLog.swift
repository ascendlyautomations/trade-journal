import Foundation
import os

#if DEBUG
enum MessageRealtimeLog {
    private static let logger = AppLog.realtime

    static func subscribed(conversationID: ConversationID, reason: String) {
        logger.debug(
            "[MessageRealtime] subscribed conversationID=\(conversationID.rawValue, privacy: .public) reason=\(reason, privacy: .public)"
        )
    }

    static func insertReceived(conversationID: ConversationID, messageID: MessageID) {
        logger.debug(
            "[MessageRealtime] insertReceived conversationID=\(conversationID.rawValue, privacy: .public) messageID=\(messageID.rawValue, privacy: .public)"
        )
    }

    static func persisted(messageID: MessageID) {
        logger.debug(
            "[MessageRealtime] persisted messageID=\(messageID.rawValue, privacy: .public)"
        )
    }

    static func visibleThreadUpdated(messageID: MessageID) {
        logger.debug(
            "[MessageRealtime] visibleThreadUpdated messageID=\(messageID.rawValue, privacy: .public)"
        )
    }

    static func dropped(reason: String, messageID: MessageID?) {
        logger.debug(
            "[MessageRealtime] dropped reason=\(reason, privacy: .public) messageID=\(messageID?.rawValue ?? "nil", privacy: .public)"
        )
    }

    static func unsubscribed(conversationID: ConversationID, reason: String) {
        logger.debug(
            "[MessageRealtime] unsubscribed conversationID=\(conversationID.rawValue, privacy: .public) reason=\(reason, privacy: .public)"
        )
    }
}
#else
enum MessageRealtimeLog {
    static func subscribed(conversationID: ConversationID, reason: String) {}
    static func insertReceived(conversationID: ConversationID, messageID: MessageID) {}
    static func persisted(messageID: MessageID) {}
    static func visibleThreadUpdated(messageID: MessageID) {}
    static func dropped(reason: String, messageID: MessageID?) {}
    static func unsubscribed(conversationID: ConversationID, reason: String) {}
}
#endif
