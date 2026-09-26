import Foundation
import os

#if DEBUG
struct SupabasePressureRealtimeSnapshot: Sendable {
    var sessionGeneration: UInt64
    var activeRoutes: Int
    var joinedTopics: Int
    var logicalConsumers: Int
}

nonisolated enum SupabasePressureLog {
    private static let logger = AppLog.realtime

    nonisolated static func reconnectStarted(_ snapshot: SupabasePressureRealtimeSnapshot) {
        logger.debug(
            """
            [SupabasePressure] reconnectStarted sessionGeneration=\(snapshot.sessionGeneration, privacy: .public) \
            activeRoutes=\(snapshot.activeRoutes, privacy: .public) joinedTopics=\(snapshot.joinedTopics, privacy: .public) \
            logicalConsumers=\(snapshot.logicalConsumers, privacy: .public)
            """
        )
    }

    nonisolated static func rejoinCompleted(_ snapshot: SupabasePressureRealtimeSnapshot) {
        logger.debug(
            """
            [SupabasePressure] rejoinCompleted sessionGeneration=\(snapshot.sessionGeneration, privacy: .public) \
            activeRoutes=\(snapshot.activeRoutes, privacy: .public) joinedTopics=\(snapshot.joinedTopics, privacy: .public) \
            logicalConsumers=\(snapshot.logicalConsumers, privacy: .public)
            """
        )
    }

    nonisolated static func repairStarted(domains: String, snapshot: SupabasePressureRealtimeSnapshot) {
        logger.debug(
            """
            [SupabasePressure] repairStarted domains=\(domains, privacy: .public) \
            sessionGeneration=\(snapshot.sessionGeneration, privacy: .public) activeRoutes=\(snapshot.activeRoutes, privacy: .public) \
            joinedTopics=\(snapshot.joinedTopics, privacy: .public) logicalConsumers=\(snapshot.logicalConsumers, privacy: .public)
            """
        )
    }

    nonisolated static func repairCoalesced(domain: String, detail: String) {
        logger.debug(
            "[SupabasePressure] repairCoalesced domain=\(domain, privacy: .public) detail=\(detail, privacy: .public)"
        )
    }

    nonisolated static func repairCompleted(
        before: SupabasePressureRealtimeSnapshot,
        after: SupabasePressureRealtimeSnapshot
    ) {
        logger.debug(
            """
            [SupabasePressure] repairCompleted sessionGeneration=\(after.sessionGeneration, privacy: .public) \
            activeRoutesAfter=\(after.activeRoutes, privacy: .public) joinedTopicsAfter=\(after.joinedTopics, privacy: .public) \
            logicalConsumersAfter=\(after.logicalConsumers, privacy: .public) \
            activeRoutesBefore=\(before.activeRoutes, privacy: .public) joinedTopicsBefore=\(before.joinedTopics, privacy: .public)
            """
        )
    }

    nonisolated static func screenRealtimeTransition(screen: String, active: Bool, snapshot: SupabasePressureRealtimeSnapshot) {
        logger.debug(
            """
            [SupabasePressure] screen=\(screen, privacy: .public) realtimeActive=\(active, privacy: .public) \
            sessionGeneration=\(snapshot.sessionGeneration, privacy: .public) activeRoutes=\(snapshot.activeRoutes, privacy: .public) \
            joinedTopics=\(snapshot.joinedTopics, privacy: .public) logicalConsumers=\(snapshot.logicalConsumers, privacy: .public)
            """
        )
    }
}
#else
struct SupabasePressureRealtimeSnapshot: Sendable {
    var sessionGeneration: UInt64 = 0
    var activeRoutes: Int = 0
    var joinedTopics: Int = 0
    var logicalConsumers: Int = 0
}

nonisolated enum SupabasePressureLog {
    nonisolated static func reconnectStarted(_ snapshot: SupabasePressureRealtimeSnapshot) {}
    nonisolated static func rejoinCompleted(_ snapshot: SupabasePressureRealtimeSnapshot) {}
    nonisolated static func repairStarted(domains: String, snapshot: SupabasePressureRealtimeSnapshot) {}
    nonisolated static func repairCoalesced(domain: String, detail: String) {}
    nonisolated static func repairCompleted(
        before: SupabasePressureRealtimeSnapshot,
        after: SupabasePressureRealtimeSnapshot
    ) {}
    nonisolated static func screenRealtimeTransition(screen: String, active: Bool, snapshot: SupabasePressureRealtimeSnapshot) {}
}
#endif
