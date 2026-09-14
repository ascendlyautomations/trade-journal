#if DEBUG
import Foundation

/// Concise DEBUG summaries for social disk cache + network catch-up.
@MainActor
enum SocialCacheProbe {
    private(set) static var inboxSource: String = "none"
    private(set) static var inboxConversations = 0
    private(set) static var dmThreadCacheHits = 0
    private(set) static var catchupRows = 0
    private(set) static var messagesFullBootstrapRPCs = 0

    private(set) static var activitySource: String = "none"
    private(set) static var activityCachedItems = 0
    private(set) static var activityCatchupItems = 0
    private(set) static var activityFullBootstrapRPCs = 0

    private(set) static var roomSource: String = "none"
    private(set) static var roomCount = 0
    private(set) static var roomThreadCacheHits = 0
    private(set) static var roomCatchupRows = 0

    private(set) static var realtimeSubscribed = false

    static func resetForTesting() {
        inboxSource = "none"
        inboxConversations = 0
        dmThreadCacheHits = 0
        catchupRows = 0
        messagesFullBootstrapRPCs = 0
        activitySource = "none"
        activityCachedItems = 0
        activityCatchupItems = 0
        activityFullBootstrapRPCs = 0
        roomSource = "none"
        roomCount = 0
        roomThreadCacheHits = 0
        roomCatchupRows = 0
        realtimeSubscribed = false
    }

    static func recordInboxDiskHit(conversations: Int, rooms: Int) {
        inboxSource = "disk"
        inboxConversations = conversations
        roomCount = rooms
        roomSource = rooms > 0 ? "disk" : roomSource
        logSummaryIfReady()
    }

    static func recordInboxNetworkCatchup(rows: Int, fullBootstrap: Bool) {
        if fullBootstrap {
            messagesFullBootstrapRPCs += 1
        } else {
            catchupRows += rows
        }
        logSummaryIfReady()
    }

    static func recordDMThreadDiskHit() {
        dmThreadCacheHits += 1
        logSummaryIfReady()
    }

    static func recordActivityDiskHit(items: Int) {
        activitySource = "disk"
        activityCachedItems = items
        logSummaryIfReady()
    }

    static func recordActivityCatchup(items: Int, fullBootstrap: Bool) {
        if fullBootstrap {
            activityFullBootstrapRPCs += 1
        } else {
            activityCatchupItems += items
        }
        logSummaryIfReady()
    }

    static func recordRoomListDiskHit(rooms: Int) {
        roomSource = "disk"
        roomCount = rooms
        logSummaryIfReady()
    }

    static func recordRoomThreadDiskHit() {
        roomThreadCacheHits += 1
        logSummaryIfReady()
    }

    static func recordRoomCatchup(rows: Int) {
        roomCatchupRows += rows
        logSummaryIfReady()
    }

    static func setRealtimeSubscribed(_ value: Bool) {
        realtimeSubscribed = value
        logSummaryIfReady()
    }

    private static func logSummaryIfReady() {
        print(
            """
            [MESSAGES CACHE] inboxSource=\(inboxSource) conversations=\(inboxConversations) threadCacheHits=\(dmThreadCacheHits) catchupRows=\(catchupRows) fullBootstrapRPCs=\(messagesFullBootstrapRPCs) realtimeSubscribed=\(realtimeSubscribed)
            [ACTIVITY CACHE] source=\(activitySource) cachedItems=\(activityCachedItems) catchupItems=\(activityCatchupItems) fullBootstrapRPCs=\(activityFullBootstrapRPCs)
            [ROOM CACHE] source=\(roomSource) rooms=\(roomCount) threadCacheHits=\(roomThreadCacheHits) catchupRows=\(roomCatchupRows)
            """
        )
    }
}
#else
@MainActor
enum SocialCacheProbe {
    static var inboxSource: String { "none" }
    static var inboxConversations: Int { 0 }
    static var dmThreadCacheHits: Int { 0 }
    static var catchupRows: Int { 0 }
    static var messagesFullBootstrapRPCs: Int { 0 }
    static var activitySource: String { "none" }
    static var activityCachedItems: Int { 0 }
    static var activityCatchupItems: Int { 0 }
    static var activityFullBootstrapRPCs: Int { 0 }
    static var roomSource: String { "none" }
    static var roomCount: Int { 0 }
    static var roomThreadCacheHits: Int { 0 }
    static var roomCatchupRows: Int { 0 }
    static var realtimeSubscribed: Bool { false }

    static func resetForTesting() {}
    static func recordInboxDiskHit(conversations: Int, rooms: Int) {}
    static func recordInboxNetworkCatchup(rows: Int, fullBootstrap: Bool) {}
    static func recordDMThreadDiskHit() {}
    static func recordActivityDiskHit(items: Int) {}
    static func recordActivityCatchup(items: Int, fullBootstrap: Bool) {}
    static func recordRoomListDiskHit(rooms: Int) {}
    static func recordRoomThreadDiskHit() {}
    static func recordRoomCatchup(rows: Int) {}
    static func setRealtimeSubscribed(_ value: Bool) {}
}
#endif
