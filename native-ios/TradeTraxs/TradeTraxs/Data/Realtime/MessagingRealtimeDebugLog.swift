import Foundation

#if DEBUG
enum MessagingRealtimeDebugLog {
    static func messageInsert(conversationID: String, messageID: String, source: String) {
        print(
            """
            [MessagingRealtime] messageInsert convo=\(conversationID) \
            message=\(messageID) source=\(source)
            """
        )
    }

    static func messageEchoIgnored(messageID: String, source: String) {
        print("[MessagingRealtime] messageEchoIgnored message=\(messageID) source=\(source)")
    }

    static func duplicateDeliveryIgnored(domain: String, messageID: String) {
        print("[MessagingRealtime] duplicateDeliveryIgnored domain=\(domain) message=\(messageID)")
    }

    static func inboxPatchSkipped(reason: String, conversationID: String) {
        print("[MessagingRealtime] inboxPatchSkipped reason=\(reason) convo=\(conversationID)")
    }

    static func threadPatch(conversationID: String, messageID: String) {
        print("[MessagingRealtime] threadPatch convo=\(conversationID) message=\(messageID)")
    }

    static func roomInsert(roomID: String, messageID: String, source: String) {
        print("[MessagingRealtime] roomInsert room=\(roomID) message=\(messageID) source=\(source)")
    }

    static func roomOpenSuppressUnread(roomID: String) {
        print("[MessagingRealtime] roomOpenSuppressUnread room=\(roomID)")
    }

    static func roomUnreadPatch(roomID: String, delta: Int) {
        print("[MessagingRealtime] roomUnreadPatch room=\(roomID) delta=\(delta)")
    }

    static func memberCountDelta(roomID: String, delta: Int, next: Int) {
        print("[MessagingRealtime] memberCountDelta room=\(roomID) delta=\(delta) next=\(next)")
    }

    static func readStatePatch(domain: String, id: String) {
        print("[MessagingRealtime] readStatePatch domain=\(domain) id=\(id)")
    }

    static func networkFallback(reason: String) {
        print("[MessagingRealtime] networkFallback reason=\(reason)")
    }
}
#endif
