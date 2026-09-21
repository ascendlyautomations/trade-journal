import Foundation

/// Viewer-scoped authoritative TradeDetail memory cache + single-flight coalescing.
actor TradeDetailSessionStore {
    static let shared = TradeDetailSessionStore()

    private struct SessionBucket {
        var details: [TradeID: TradeDetail] = [:]
        var authorities: [TradeID: TradeDetailAuthority] = [:]
        var inFlight: [String: Task<(TradeDetail, Int?), Error>] = [:]
        var lastPayloadBytes: [TradeID: Int] = [:]
    }

    private var bucketByViewer: [String: SessionBucket] = [:]

    private init() {}

    func resetAll() {
        bucketByViewer = [:]
    }

    func reset(viewerKey: String) {
        bucketByViewer[viewerKey] = nil
    }

    func cachedDetail(tradeID: TradeID, viewerKey: String) -> TradeDetail? {
        guard let bucket = bucketByViewer[viewerKey],
              let detail = bucket.details[tradeID],
              TradeDetailCompleteness.isAuthoritative(bucket.authorities[tradeID] ?? .listSeed)
        else { return nil }
        return detail
    }

    func lastPayloadBytes(tradeID: TradeID, viewerKey: String) -> Int? {
        bucketByViewer[viewerKey]?.lastPayloadBytes[tradeID]
    }

    func store(
        _ detail: TradeDetail,
        tradeID: TradeID,
        viewerKey: String,
        authority: TradeDetailAuthority,
        payloadBytes: Int?
    ) {
        var bucket = bucketByViewer[viewerKey] ?? SessionBucket()
        bucket.details[tradeID] = detail
        bucket.authorities[tradeID] = authority
        if let payloadBytes {
            bucket.lastPayloadBytes[tradeID] = payloadBytes
        }
        bucketByViewer[viewerKey] = bucket
    }

    func evict(tradeID: TradeID, viewerKey: String) {
        guard var bucket = bucketByViewer[viewerKey] else { return }
        bucket.details[tradeID] = nil
        bucket.authorities[tradeID] = nil
        bucket.lastPayloadBytes[tradeID] = nil
        bucketByViewer[viewerKey] = bucket
    }

    func loadCoalesced(
        tradeID: TradeID,
        viewerKey: String,
        fetch: @Sendable @escaping () async throws -> (TradeDetail, Int?)
    ) async throws -> TradeDetail {
        if let cached = cachedDetail(tradeID: tradeID, viewerKey: viewerKey) {
            return cached
        }

        let flightKey = Self.flightKey(viewerKey: viewerKey, tradeID: tradeID)
        if let existing = bucketByViewer[viewerKey]?.inFlight[flightKey] {
            #if DEBUG
            await MainActor.run {
                TradeDetailTelemetry.singleFlight(tradeID: tradeID, viewer: viewerKey)
            }
            #endif
            let pair = try await existing.value
            return pair.0
        }

        let task = Task {
            try await fetch()
        }

        var bucket = bucketByViewer[viewerKey] ?? SessionBucket()
        bucket.inFlight[flightKey] = task
        bucketByViewer[viewerKey] = bucket

        defer {
            var cleared = bucketByViewer[viewerKey] ?? SessionBucket()
            cleared.inFlight[flightKey] = nil
            bucketByViewer[viewerKey] = cleared
        }

        let started = ContinuousClock.now
        let (detail, bytes) = try await task.value
        store(
            detail,
            tradeID: tradeID,
            viewerKey: viewerKey,
            authority: .authoritativeNetwork,
            payloadBytes: bytes
        )
        #if DEBUG
        let ms = Double(started.duration(to: .now).components.attoseconds) / 1_000_000_000_000_000
        await MainActor.run {
            TradeDetailTelemetry.network(
                tradeID: tradeID,
                viewer: viewerKey,
                bytes: bytes,
                elapsedMs: ms
            )
            TradeDetailTelemetry.loaded(tradeID: tradeID, viewer: viewerKey, elapsedMs: ms)
        }
        #endif
        return detail
    }

    static func flightKey(viewerKey: String, tradeID: TradeID) -> String {
        "tradeDetail|\(viewerKey)|\(tradeID.rawValue)"
    }

    static func viewerKey(from session: any SessionProviding) async -> String {
        if let id = await session.currentUserID {
            return id.rawValue
        }
        return "anon"
    }
}
