import Foundation

#if DEBUG
enum ConversationOpenTrace {
    private static var tapStartedAt: [String: Date] = [:]
    private static var openStartedAt: [String: Date] = [:]

    static func tap(conversationID: String) {
        let now = Date()
        tapStartedAt[conversationID] = now
        openStartedAt[conversationID] = now
        print("[ConversationOpenTrace] tap conversation=\(conversationID)")
    }

    static func navigationCommitted(conversationID: String) {
        let ms = elapsedMs(since: tapStartedAt[conversationID])
        print("[ConversationOpenTrace] navigationCommitted elapsedMs=\(ms) conversation=\(conversationID)")
    }

    static func viewAppeared(conversationID: String) {
        let ms = elapsedMs(since: tapStartedAt[conversationID])
        print("[ConversationOpenTrace] viewAppeared elapsedMs=\(ms) conversation=\(conversationID)")
    }

    static func diskStart(conversationID: String) {
        print("[ConversationOpenTrace] diskStart conversation=\(conversationID)")
    }

    static func diskEnd(conversationID: String, count: Int) {
        let ms = elapsedMs(since: openStartedAt[conversationID])
        print("[ConversationOpenTrace] diskEnd elapsedMs=\(ms) count=\(count) conversation=\(conversationID)")
    }

    static func firstRender(conversationID: String, source: String) {
        let ms = elapsedMs(since: tapStartedAt[conversationID])
        print("[ConversationOpenTrace] firstRender elapsedMs=\(ms) source=\(source) conversation=\(conversationID)")
    }

    static func networkStart(conversationID: String) {
        print("[ConversationOpenTrace] networkStart conversation=\(conversationID)")
    }

    static func networkEnd(conversationID: String, count: Int) {
        let ms = elapsedMs(since: openStartedAt[conversationID])
        print("[ConversationOpenTrace] networkEnd elapsedMs=\(ms) count=\(count) conversation=\(conversationID)")
    }

    static func realtimeRetain(conversationID: String) {
        print("[ConversationOpenTrace] realtimeRetain conversation=\(conversationID)")
    }

    static func realtimeJoined(conversationID: String) {
        let ms = elapsedMs(since: tapStartedAt[conversationID])
        print("[ConversationOpenTrace] realtimeJoined elapsedMs=\(ms) conversation=\(conversationID)")
    }

    static func blocked(conversationID: String, reason: String) {
        print("[ConversationOpenTrace] blocked reason=\(reason) conversation=\(conversationID)")
    }

    private static func elapsedMs(since: Date?) -> Int {
        guard let since else { return -1 }
        return Int(Date().timeIntervalSince(since) * 1000)
    }
}
#else
enum ConversationOpenTrace {
    static func tap(conversationID: String) {}
    static func navigationCommitted(conversationID: String) {}
    static func viewAppeared(conversationID: String) {}
    static func diskStart(conversationID: String) {}
    static func diskEnd(conversationID: String, count: Int) {}
    static func firstRender(conversationID: String, source: String) {}
    static func networkStart(conversationID: String) {}
    static func networkEnd(conversationID: String, count: Int) {}
    static func realtimeRetain(conversationID: String) {}
    static func realtimeJoined(conversationID: String) {}
    static func blocked(conversationID: String, reason: String) {}
}
#endif
