import Foundation

#if DEBUG
import os.log

/// DEBUG-only Realtime lifecycle tracing. Search Xcode console for `[RT-Lifecycle]`.
enum RealtimeLifecycleDebugLog {
    static let prefix = "[RT-Lifecycle]"

    private static let logger = Logger(
        subsystem: "com.tradetraxs.TradeTraxs",
        category: "RT-Lifecycle"
    )

    static func log(_ message: String) {
        let line = "\(prefix) \(message)"
        logger.debug("\(line, privacy: .public)")
        print(line)
    }

    static func connect() {
        log("CONNECT socket")
    }

    static func disconnect(activeRoutes: Int) {
        log("DISCONNECT activeRoutes=\(activeRoutes)")
    }

    static func foregroundResume(connected: Bool, activeRoutes: Int) {
        log("FOREGROUND-RESUME connected=\(connected) activeRoutes=\(activeRoutes)")
    }

    static func socketDropped(activeRoutes: Int) {
        log("SOCKET-DROPPED scheduling-reconnect activeRoutes=\(activeRoutes)")
    }

    static func reconnectBegin(activeRoutes: Int, attempt: Int) {
        log("RECONNECT-BEGIN activeRoutes=\(activeRoutes) attempt=\(attempt)")
    }

    static func reconnectEnd(activeRoutes: Int, joinedTopics: Int) {
        log("RECONNECT-END activeRoutes=\(activeRoutes) joinedTopics=\(joinedTopics)")
    }

    static func start(
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

    static func stop(
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

    static func join(topic: String, routeKey: String, activeRoutes: Int, joinedTopics: Int) {
        log(
            "JOIN phx_join route=\(routeKey) topic=\(topic) "
                + "activeRoutes=\(activeRoutes) joinedTopics=\(joinedTopics)"
        )
    }

    static func leave(topic: String, routeKey: String?, activeRoutes: Int, joinedTopics: Int) {
        let routePart = routeKey.map { " route=\($0)" } ?? ""
        log(
            "LEAVE phx_leave\(routePart) topic=\(topic) "
                + "activeRoutes=\(activeRoutes) joinedTopics=\(joinedTopics)"
        )
    }

    static func rejoin(
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

    static func registrySubscribe(kind: String, topic: String, refcount: Int, registered: Int) {
        log(
            "REGISTRY-SUBSCRIBE kind=\(kind) topic=\(topic) refcount=\(refcount) registered=\(registered)"
        )
    }

    static func registryUnsubscribe(kind: String, topic: String, refcount: Int, registered: Int) {
        log(
            "REGISTRY-UNSUBSCRIBE kind=\(kind) topic=\(topic) refcount=\(refcount) registered=\(registered)"
        )
    }

    static func hubStart() {
        log("HUB-START")
    }

    static func hubStop() {
        log("HUB-STOP")
    }

    static func hubResumeIfNeeded() {
        log("HUB-RESUME-IF-NEEDED")
    }
}
#else
enum RealtimeLifecycleDebugLog {
    static func connect() {}
    static func disconnect(activeRoutes: Int) {}
    static func foregroundResume(connected: Bool, activeRoutes: Int) {}
    static func socketDropped(activeRoutes: Int) {}
    static func reconnectBegin(activeRoutes: Int, attempt: Int) {}
    static func reconnectEnd(activeRoutes: Int, joinedTopics: Int) {}
    static func start(
        routeKey: String,
        topic: String,
        consumers: Int,
        activeRoutes: Int,
        joinedTopics: Int,
        newJoin: Bool
    ) {}
    static func stop(
        routeKey: String,
        topic: String?,
        consumersRemoved: Int,
        activeRoutes: Int,
        joinedTopics: Int,
        willLeave: Bool
    ) {}
    static func join(topic: String, routeKey: String, activeRoutes: Int, joinedTopics: Int) {}
    static func leave(topic: String, routeKey: String?, activeRoutes: Int, joinedTopics: Int) {}
    static func rejoin(
        routeKey: String,
        topic: String,
        skipped: Bool,
        activeRoutes: Int,
        joinedTopics: Int
    ) {}
    static func registrySubscribe(kind: String, topic: String, refcount: Int, registered: Int) {}
    static func registryUnsubscribe(kind: String, topic: String, refcount: Int, registered: Int) {}
    static func hubStart() {}
    static func hubStop() {}
    static func hubResumeIfNeeded() {}
}
#endif
