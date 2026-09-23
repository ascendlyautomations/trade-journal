import Foundation

#if DEBUG
import os.log

/// DEBUG-only Realtime lifecycle tracing. Search Xcode console for `[RT-Lifecycle]`.
enum RealtimeLifecycleDebugLog {
    nonisolated static let prefix = "[RT-Lifecycle]"

    nonisolated private static let logger = Logger(
        subsystem: "com.tradetraxs.TradeTraxs",
        category: "RT-Lifecycle"
    )

    nonisolated static func log(_ message: String) {
        let line = "\(prefix) \(message)"
        print(line)
    }

    nonisolated static func connect() {
        log("CONNECT socket")
    }

    nonisolated static func disconnect(activeRoutes: Int) {
        log("DISCONNECT activeRoutes=\(activeRoutes)")
    }

    nonisolated static func foregroundResume(connected: Bool, activeRoutes: Int) {
        log("FOREGROUND-RESUME connected=\(connected) activeRoutes=\(activeRoutes)")
    }

    nonisolated static func socketDropped(activeRoutes: Int) {
        log("SOCKET-DROPPED scheduling-reconnect activeRoutes=\(activeRoutes)")
    }

    nonisolated static func reconnectBegin(activeRoutes: Int, attempt: Int) {
        log("RECONNECT-BEGIN activeRoutes=\(activeRoutes) attempt=\(attempt)")
    }

    nonisolated static func reconnectEnd(activeRoutes: Int, joinedTopics: Int) {
        log("RECONNECT-END activeRoutes=\(activeRoutes) joinedTopics=\(joinedTopics)")
    }

    nonisolated static func start(
        routeKey: String,
        topic: String,
        consumers: Int,
        activeRoutes: Int,
        joinedTopics: Int,
        newJoin: Bool
    ) {
        log(
            "START route=\(routeKey) topic=\(topic) consumers=\(consumers) "
                + "activeRoutes=\(activeRoutes) joinedTopics=\(joinedTopics) newJoin=\(newJoin)"
        )
        if consumers > 1 {
            log(
                "WARN duplicate-consumer route=\(routeKey) consumers=\(consumers) "
                    + "(same route, multiple AsyncStream consumers)"
            )
        }
    }

    nonisolated static func stop(
        routeKey: String,
        topic: String?,
        consumersRemoved: Int,
        activeRoutes: Int,
        joinedTopics: Int,
        willLeave: Bool
    ) {
        let topicPart = topic.map { " topic=\($0)" } ?? ""
        log(
            "STOP route=\(routeKey)\(topicPart) consumersRemoved=\(consumersRemoved) "
                + "activeRoutes=\(activeRoutes) joinedTopics=\(joinedTopics) willLeave=\(willLeave)"
        )
    }

    nonisolated static func join(topic: String, routeKey: String, activeRoutes: Int, joinedTopics: Int) {
        log(
            "JOIN phx_join route=\(routeKey) topic=\(topic) "
                + "activeRoutes=\(activeRoutes) joinedTopics=\(joinedTopics)"
        )
    }

    nonisolated static func leave(topic: String, routeKey: String?, activeRoutes: Int, joinedTopics: Int) {
        let routePart = routeKey.map { " route=\($0)" } ?? ""
        log(
            "LEAVE phx_leave\(routePart) topic=\(topic) "
                + "activeRoutes=\(activeRoutes) joinedTopics=\(joinedTopics)"
        )
    }

    nonisolated static func rejoin(
        routeKey: String,
        topic: String,
        skipped: Bool,
        activeRoutes: Int,
        joinedTopics: Int
    ) {
        log(
            "REJOIN route=\(routeKey) topic=\(topic) skipped=\(skipped) "
                + "activeRoutes=\(activeRoutes) joinedTopics=\(joinedTopics)"
        )
    }

    nonisolated static func registrySubscribe(kind: String, topic: String, refcount: Int, registered: Int) {
        log(
            "REGISTRY-SUBSCRIBE kind=\(kind) topic=\(topic) refcount=\(refcount) registered=\(registered)"
        )
    }

    nonisolated static func registryUnsubscribe(kind: String, topic: String, refcount: Int, registered: Int) {
        log(
            "REGISTRY-UNSUBSCRIBE kind=\(kind) topic=\(topic) refcount=\(refcount) registered=\(registered)"
        )
    }

    nonisolated static func hubStart() {
        log("HUB-START")
    }

    nonisolated static func hubStop() {
        log("HUB-STOP")
    }

    nonisolated static func hubResumeIfNeeded() {
        log("HUB-RESUME-IF-NEEDED")
    }

    // MARK: - Phase 10B consumer-safe route lifecycle (`[RealtimeLifecycle]`)

    nonisolated private static let lifecyclePrefix = "[RealtimeLifecycle]"

    nonisolated private static func lifecycleLog(_ message: String) {
        let line = "\(lifecyclePrefix) \(message)"
        print(line)
    }

    nonisolated static func consumerRetain(
        routeKey: String,
        consumerID: UUID,
        owner: String?,
        consumerCount: Int,
        joined: Bool,
        sessionGeneration: UInt64
    ) {
        let ownerPart = owner.map { " owner=\($0)" } ?? ""
        lifecycleLog(
            "consumerRetain route=\(routeKey) consumer=\(consumerID.uuidString.prefix(8))\(ownerPart) "
                + "consumers=\(consumerCount) joined=\(joined) sessionGen=\(sessionGeneration)"
        )
    }

    nonisolated static func duplicateRetainIgnored(
        routeKey: String,
        consumerID: UUID,
        owner: String?,
        consumerCount: Int,
        sessionGeneration: UInt64
    ) {
        let ownerPart = owner.map { " owner=\($0)" } ?? ""
        lifecycleLog(
            "duplicateRetainIgnored route=\(routeKey) consumer=\(consumerID.uuidString.prefix(8))\(ownerPart) "
                + "consumers=\(consumerCount) sessionGen=\(sessionGeneration)"
        )
    }

    nonisolated static func consumerRelease(
        routeKey: String,
        consumerID: UUID,
        owner: String?,
        consumerCount: Int,
        joined: Bool,
        willLeave: Bool
    ) {
        let ownerPart = owner.map { " owner=\($0)" } ?? ""
        lifecycleLog(
            "consumerRelease route=\(routeKey) consumer=\(consumerID.uuidString.prefix(8))\(ownerPart) "
                + "consumers=\(consumerCount) joined=\(joined) willLeave=\(willLeave)"
        )
    }

    nonisolated static func duplicateReleaseIgnored(
        routeKey: String,
        consumerID: UUID,
        owner: String?,
        consumerCount: Int
    ) {
        let ownerPart = owner.map { " owner=\($0)" } ?? ""
        lifecycleLog(
            "duplicateReleaseIgnored route=\(routeKey) consumer=\(consumerID.uuidString.prefix(8))\(ownerPart) "
                + "consumers=\(consumerCount)"
        )
    }

    nonisolated static func consumerStreamDetach(
        routeKey: String,
        consumerID: UUID,
        owner: String?,
        consumerCount: Int,
        streamsRemaining: Int
    ) {
        let ownerPart = owner.map { " owner=\($0)" } ?? ""
        lifecycleLog(
            "consumerStreamDetach route=\(routeKey) consumer=\(consumerID.uuidString.prefix(8))\(ownerPart) "
                + "consumers=\(consumerCount) streamsRemaining=\(streamsRemaining)"
        )
    }

    nonisolated static func routeJoin(routeKey: String, topic: String) {
        lifecycleLog("routeJoin route=\(routeKey) topic=\(topic)")
    }

    nonisolated static func routeReuse(routeKey: String, topic: String) {
        lifecycleLog("routeReuse route=\(routeKey) topic=\(topic)")
    }

    nonisolated static func routeLeave(routeKey: String, topic: String) {
        lifecycleLog("routeLeave route=\(routeKey) topic=\(topic)")
    }

    nonisolated static func routeRejoin(routeKey: String, topic: String) {
        lifecycleLog("routeRejoin route=\(routeKey) topic=\(topic)")
    }

    nonisolated static func forceSessionClear(reason: String, sessionGeneration: UInt64) {
        lifecycleLog("forceSessionClear reason=\(reason) sessionGen=\(sessionGeneration)")
    }
}
#else
enum RealtimeLifecycleDebugLog {
    nonisolated static func connect() {}
    nonisolated static func disconnect(activeRoutes: Int) {}
    nonisolated static func foregroundResume(connected: Bool, activeRoutes: Int) {}
    nonisolated static func socketDropped(activeRoutes: Int) {}
    nonisolated static func reconnectBegin(activeRoutes: Int, attempt: Int) {}
    nonisolated static func reconnectEnd(activeRoutes: Int, joinedTopics: Int) {}
    nonisolated static func start(
        routeKey: String,
        topic: String,
        consumers: Int,
        activeRoutes: Int,
        joinedTopics: Int,
        newJoin: Bool
    ) {}
    nonisolated static func stop(
        routeKey: String,
        topic: String?,
        consumersRemoved: Int,
        activeRoutes: Int,
        joinedTopics: Int,
        willLeave: Bool
    ) {}
    nonisolated static func join(topic: String, routeKey: String, activeRoutes: Int, joinedTopics: Int) {}
    nonisolated static func leave(topic: String, routeKey: String?, activeRoutes: Int, joinedTopics: Int) {}
    nonisolated static func rejoin(
        routeKey: String,
        topic: String,
        skipped: Bool,
        activeRoutes: Int,
        joinedTopics: Int
    ) {}
    nonisolated static func registrySubscribe(kind: String, topic: String, refcount: Int, registered: Int) {}
    nonisolated static func registryUnsubscribe(kind: String, topic: String, refcount: Int, registered: Int) {}
    nonisolated static func hubStart() {}
    nonisolated static func hubStop() {}
    nonisolated static func hubResumeIfNeeded() {}
    nonisolated static func consumerRetain(
        routeKey: String,
        consumerID: UUID,
        owner: String?,
        consumerCount: Int,
        joined: Bool,
        sessionGeneration: UInt64
    ) {}
    nonisolated static func duplicateRetainIgnored(
        routeKey: String,
        consumerID: UUID,
        owner: String?,
        consumerCount: Int,
        sessionGeneration: UInt64
    ) {}
    nonisolated static func consumerRelease(
        routeKey: String,
        consumerID: UUID,
        owner: String?,
        consumerCount: Int,
        joined: Bool,
        willLeave: Bool
    ) {}
    nonisolated static func duplicateReleaseIgnored(
        routeKey: String,
        consumerID: UUID,
        owner: String?,
        consumerCount: Int
    ) {}
    nonisolated static func consumerStreamDetach(
        routeKey: String,
        consumerID: UUID,
        owner: String?,
        consumerCount: Int,
        streamsRemaining: Int
    ) {}
    nonisolated static func routeJoin(routeKey: String, topic: String) {}
    nonisolated static func routeReuse(routeKey: String, topic: String) {}
    nonisolated static func routeLeave(routeKey: String, topic: String) {}
    nonisolated static func routeRejoin(routeKey: String, topic: String) {}
    nonisolated static func forceSessionClear(reason: String, sessionGeneration: UInt64) {}
}
#endif
