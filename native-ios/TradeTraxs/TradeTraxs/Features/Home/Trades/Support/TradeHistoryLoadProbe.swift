import Foundation
import OSLog

#if DEBUG
/// DEBUG instrumentation for Trade History open / filter / pagination.
enum TradeHistoryLoadProbe {
    struct Operation: Sendable {
        var name: String
        var kind: Kind
        var durationMs: Double
        var blocksFirstUsefulRender: Bool
    }

    enum Kind: String, Sendable {
        case network
        case local
        case cache
    }

    private static var sessionStartedAt: CFAbsoluteTime?
    private static var operations: [Operation] = []
    private static var firstUsefulRenderMs: Double?
    private static var requestCount = 0
    private static var cacheHits = 0
    private static var cancelledRequests = 0
    private static var lastPageSize = 0
    private static var serverSideFilters: [String] = []
    private static var localFilters: [String] = []

    static func beginSession() {
        sessionStartedAt = CFAbsoluteTimeGetCurrent()
        operations = []
        firstUsefulRenderMs = nil
        requestCount = 0
        cacheHits = 0
        cancelledRequests = 0
        lastPageSize = 0
        serverSideFilters = []
        localFilters = []
        AppLog.networking.info("TradeHistory probe session begin")
    }

    static func markRequest() {
        requestCount += 1
    }

    static func markCacheHit() {
        cacheHits += 1
    }

    static func markCancelled() {
        cancelledRequests += 1
    }

    static func markPageSize(_ size: Int) {
        lastPageSize = size
    }

    static func markFilterStrategy(server: [String], local: [String]) {
        serverSideFilters = server
        localFilters = local
    }

    static func markFirstUsefulRender() {
        guard firstUsefulRenderMs == nil, let start = sessionStartedAt else { return }
        firstUsefulRenderMs = (CFAbsoluteTimeGetCurrent() - start) * 1_000
        AppLog.networking.info(
            "TradeHistory first useful render ms=\(firstUsefulRenderMs ?? -1, privacy: .public) requests=\(requestCount, privacy: .public) pageSize=\(lastPageSize, privacy: .public)"
        )
    }

    static func measure(
        _ name: String,
        kind: Kind,
        blocksFirstUsefulRender: Bool,
        work: () async throws -> Void
    ) async rethrows {
        let started = CFAbsoluteTimeGetCurrent()
        try await work()
        let ms = (CFAbsoluteTimeGetCurrent() - started) * 1_000
        operations.append(
            Operation(
                name: name,
                kind: kind,
                durationMs: ms,
                blocksFirstUsefulRender: blocksFirstUsefulRender
            )
        )
    }

    static func snapshot() -> (
        requestCount: Int,
        cacheHits: Int,
        cancelled: Int,
        pageSize: Int,
        firstUsefulRenderMs: Double?,
        serverFilters: [String],
        localFilters: [String],
        operations: [Operation]
    ) {
        (
            requestCount,
            cacheHits,
            cancelledRequests,
            lastPageSize,
            firstUsefulRenderMs,
            serverSideFilters,
            localFilters,
            operations
        )
    }

    static func resetForTesting() {
        beginSession()
    }
}
#endif
