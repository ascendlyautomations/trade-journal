import Foundation
import OSLog

#if DEBUG
/// DEBUG-only cache / network instrumentation for session data policy verification.
enum SessionNetworkProbe {
    enum Event: String, Sendable {
        case cacheHit = "CACHE HIT"
        case cacheMiss = "CACHE MISS"
        case cacheStale = "CACHE STALE"
        case cacheInvalidated = "CACHE INVALIDATED"
        case networkFetch = "NETWORK FETCH"
        case realtimeUpdate = "REALTIME UPDATE"
        case requestCoalesced = "REQUEST COALESCED"
        case localMutation = "LOCAL MUTATION"
    }

    private static var events: [(event: Event, resource: String, detail: String)] = []
    private static var networkCounts: [String: Int] = [:]

    static func record(
        _ event: Event,
        resource: String,
        detail: String = ""
    ) {
        events.append((event, resource, detail))
        if event == .networkFetch {
            networkCounts[resource, default: 0] += 1
        }
        if event == .cacheHit || event == .requestCoalesced {
            SupabaseSessionUsage.recordCacheHit(resource: resource)
        }
        if event == .realtimeUpdate {
            SupabaseSessionUsage.recordRealtimeEvent()
        }
        let suffix = detail.isEmpty ? "" : " — \(detail)"
        AppLog.networking.info(
            "\(event.rawValue, privacy: .public) \(resource, privacy: .public)\(suffix, privacy: .public)"
        )
    }

    static func networkCount(for resource: String) -> Int {
        networkCounts[resource, default: 0]
    }

    static func totalNetworkFetches() -> Int {
        networkCounts.values.reduce(0, +)
    }

    static func resetForTesting() {
        events = []
        networkCounts = [:]
    }

    static func snapshotEvents() -> [(String, String, String)] {
        events.map { ($0.event.rawValue, $0.resource, $0.detail) }
    }
}
#else
enum SessionNetworkProbe {
    enum Event: String, Sendable {
        case cacheHit, cacheMiss, cacheStale, cacheInvalidated
        case networkFetch, realtimeUpdate, requestCoalesced, localMutation
    }

    static func record(_ event: Event, resource: String, detail: String = "") {}
    static func networkCount(for resource: String) -> Int { 0 }
    static func totalNetworkFetches() -> Int { 0 }
    static func resetForTesting() {}
    static func snapshotEvents() -> [(String, String, String)] { [] }
}
#endif
