import Foundation

/// Cross-route dedupe for DM + Trade Room message Realtime (inbox vs open thread).
@MainActor
enum MessagingRealtimeDeliveryCoordinator {
    private static var seenMessageKeys: Set<String> = []
    private static let maxSeenKeys = 4_096

    static func resetSession() {
        seenMessageKeys.removeAll()
    }

    /// Returns false when this conversation/message pair was already applied on any route.
    static func claimMessageInsert(domain: String, messageID: String, conversationID: String? = nil) -> Bool {
        let key = "\(conversationID ?? domain):\(messageID)"
        if seenMessageKeys.contains(key) {
#if DEBUG
            MessagingRealtimeDebugLog.duplicateDeliveryIgnored(domain: domain, messageID: messageID)
#endif
            return false
        }
        seenMessageKeys.insert(key)
        if seenMessageKeys.count > maxSeenKeys {
            for key in seenMessageKeys.prefix(maxSeenKeys / 4) {
                seenMessageKeys.remove(key)
            }
        }
        return true
    }
}
