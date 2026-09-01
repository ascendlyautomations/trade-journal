import Foundation
import OSLog

#if DEBUG
/// DEBUG-only Supabase REST/RPC request budget for an authenticated session.
///
/// Counts transport hits to `/rest/v1/` and `/rest/v1/rpc/` — not Realtime frames.
nonisolated enum SupabaseSessionUsage {
    private static let logger = Logger(subsystem: "com.tradetraxs.TradeTraxs", category: "SupabaseUsage")
    private static let lock = NSLock()

    private static var startedAt: Date?
    private static var restByTable: [String: Int] = [:]
    private static var rpcByName: [String: Int] = [:]
    private static var featureHints: [String: Int] = [:]
    private static var cacheHits = 0
    private static var requestsAvoided = 0
    private static var realtimeEvents = 0
    private static var bytesTransferred: Int = 0

    static func beginSession() {
        lock.lock()
        defer { lock.unlock() }
        startedAt = Date()
        restByTable = [:]
        rpcByName = [:]
        featureHints = [:]
        cacheHits = 0
        requestsAvoided = 0
        realtimeEvents = 0
        bytesTransferred = 0
        logger.debug("SUPABASE SESSION USAGE — begin")
    }

    static func resetForTesting() {
        beginSession()
    }

    /// Call from transport for every REST/RPC round trip.
    static func recordREST(path: String, method: String, bytes: Int?) {
        lock.lock()
        defer { lock.unlock() }
        if startedAt == nil { startedAt = Date() }

        if path.contains("/rpc/") {
            let name = path.split(separator: "/").last.map(String.init) ?? path
            rpcByName[name, default: 0] += 1
        } else if let table = restTable(from: path) {
            restByTable[table, default: 0] += 1
        } else {
            restByTable["_other", default: 0] += 1
        }
        if let bytes { bytesTransferred += max(0, bytes) }
    }

    static func recordCacheHit(resource: String) {
        lock.lock()
        defer { lock.unlock() }
        cacheHits += 1
        requestsAvoided += 1
        featureHints[resource, default: 0] += 0
    }

    static func recordRealtimeEvent() {
        lock.lock()
        defer { lock.unlock() }
        realtimeEvents += 1
    }

    static func totalDatabaseRequests() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return restByTable.values.reduce(0, +) + rpcByName.values.reduce(0, +)
    }

    static func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            startedAt: startedAt,
            restByTable: restByTable,
            rpcByName: rpcByName,
            cacheHits: cacheHits,
            requestsAvoided: requestsAvoided,
            realtimeEvents: realtimeEvents,
            bytesTransferred: bytesTransferred,
            totalDatabaseRequests: restByTable.values.reduce(0, +) + rpcByName.values.reduce(0, +)
        )
    }

    /// Compact multiline summary for console / acceptance runs.
    static func reportSummary() -> String {
        let snap = snapshot()
        var lines: [String] = ["SUPABASE SESSION USAGE"]
        let restSorted = snap.restByTable.sorted { $0.key < $1.key }
        for (table, count) in restSorted {
            lines.append("  REST \(table): \(count)")
        }
        let rpcSorted = snap.rpcByName.sorted { $0.key < $1.key }
        for (name, count) in rpcSorted {
            lines.append("  RPC \(name): \(count)")
        }
        lines.append("Total database requests: \(snap.totalDatabaseRequests)")
        lines.append("Realtime events: \(snap.realtimeEvents)")
        lines.append("Cache hits: \(snap.cacheHits)")
        lines.append("Requests avoided: \(snap.requestsAvoided)")
        if snap.bytesTransferred > 0 {
            lines.append("Approx response bytes: \(snap.bytesTransferred)")
        }
        let text = lines.joined(separator: "\n")
        logger.debug("\(text, privacy: .public)")
        return text
    }

    struct Snapshot: Sendable, Equatable {
        var startedAt: Date?
        var restByTable: [String: Int]
        var rpcByName: [String: Int]
        var cacheHits: Int
        var requestsAvoided: Int
        var realtimeEvents: Int
        var bytesTransferred: Int
        var totalDatabaseRequests: Int

        var profilesRequests: Int { restByTable["profiles"] ?? 0 }
        var tradesRequests: Int { restByTable["trades"] ?? 0 }
        var followersRequests: Int { restByTable["followers"] ?? 0 }
        var engagementRequests: Int {
            let keys = [
                "trade_likes", "trade_comments",
                "profile_post_likes", "profile_post_comments",
                "reel_likes", "reel_comments",
                "likes", "comments",
                "achievement_post_likes", "achievement_post_comments",
            ]
            return keys.reduce(0) { $0 + (restByTable[$1] ?? 0) }
        }
    }

    private static func restTable(from path: String) -> String? {
        // /rest/v1/profiles or /rest/v1/trades?...
        guard let range = path.range(of: "/rest/v1/") else { return nil }
        let rest = path[range.upperBound...]
        let table = rest.split(separator: "/", maxSplits: 1).first.map(String.init)
        if table == "rpc" { return nil }
        return table?.split(separator: "?").first.map(String.init)
    }
}
#else
nonisolated enum SupabaseSessionUsage {
    static func beginSession() {}
    static func resetForTesting() {}
    static func recordREST(path: String, method: String, bytes: Int?) {}
    static func recordCacheHit(resource: String) {}
    static func recordRealtimeEvent() {}
    static func totalDatabaseRequests() -> Int { 0 }
    static func reportSummary() -> String { "" }

    struct Snapshot: Sendable, Equatable {
        var startedAt: Date?
        var restByTable: [String: Int] = [:]
        var rpcByName: [String: Int] = [:]
        var cacheHits: Int = 0
        var requestsAvoided: Int = 0
        var realtimeEvents: Int = 0
        var bytesTransferred: Int = 0
        var totalDatabaseRequests: Int = 0
        var profilesRequests: Int { 0 }
        var tradesRequests: Int { 0 }
        var followersRequests: Int { 0 }
        var engagementRequests: Int { 0 }
    }

    static func snapshot() -> Snapshot { Snapshot() }
}
#endif
