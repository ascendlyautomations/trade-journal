import Foundation
import Observation

/// Session-scoped trade entity cache — batch-fetch missing TradeIDs (Feed hydration).
@Observable
@MainActor
final class SessionTradeEntityStore {
    static let shared = SessionTradeEntityStore()

    private var inFlight: [String: Task<[Trade], Error>] = [:]

    private init() {}

    func trades(
        ids: [TradeID],
        detailCache: DetailPresentationCache,
        repository: any TradeRepository,
        forceNetwork: Bool = false,
        viewerID: ProfileID? = nil
    ) async throws -> [Trade] {
        let unique = Array(Set(ids)).filter { !$0.rawValue.isEmpty }
        guard !unique.isEmpty else { return [] }

        var hit: [Trade] = []
        var missing: [TradeID] = []
        for id in unique {
            if !forceNetwork, let summary = detailCache.tradeSummary(id: id) {
                hit.append(TradeSummaryMapper.previewTrade(from: summary))
            } else if !forceNetwork,
                      let viewerID,
                      let summary = SocialEntityDiskCache.loadTradeSummary(id: id, viewerID: viewerID)
            {
                detailCache.seedPresentationSeed(summary)
                hit.append(TradeSummaryMapper.previewTrade(from: summary))
            } else {
                missing.append(id)
            }
        }

        if missing.isEmpty {
            SessionNetworkProbe.record(
                .cacheHit,
                resource: "trades.batch",
                detail: "count=\(hit.count)"
            )
            return hit
        }

        SessionNetworkProbe.record(
            .cacheMiss,
            resource: "trades.batch",
            detail: "missing=\(missing.count) hit=\(hit.count)"
        )

        let key = missing.map(\.rawValue).sorted().joined(separator: ",")
        if let existing = inFlight[key] {
            SessionNetworkProbe.record(.requestCoalesced, resource: "trades.batch", detail: key)
            let fetched = try await existing.value
            return merge(hit, fetched)
        }

        SessionNetworkProbe.record(
            .networkFetch,
            resource: "trades.batch",
            detail: "ids=\(missing.count)"
        )
        let cache = detailCache
        let task = Task {
            let fetched = try await repository.trades(ids: missing)
            cache.seedListPreviews(fetched)
            if let viewerID {
                for trade in fetched {
                    let summary = TradeSummaryMapper.summary(fromPartialListTrade: trade)
                    SocialEntityDiskCache.saveTradeSummary(summary, viewerID: viewerID)
                }
            }
            return fetched
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }

        let fetched = try await task.value
        return merge(hit, fetched)
    }

    func upsert(_ trade: Trade, detailCache: DetailPresentationCache, viewerID: ProfileID? = nil) {
        SessionNetworkProbe.record(.realtimeUpdate, resource: "trades.entity", detail: trade.id.rawValue)
        detailCache.seedAuthoritativeDetail(trade, authority: .authoritativeMutation)
        if let viewerID {
            SocialEntityDiskCache.saveTradeSummary(
                TradeSummaryMapper.summary(fromPartialListTrade: trade),
                viewerID: viewerID
            )
        }
    }

    func remove(id: TradeID) {
        SessionNetworkProbe.record(.localMutation, resource: "trades.entity.remove", detail: id.rawValue)
    }

    func invalidate() {
        inFlight.values.forEach { $0.cancel() }
        inFlight = [:]
        SessionNetworkProbe.record(.cacheInvalidated, resource: "trades.batch", detail: "all")
    }

    private func merge(_ a: [Trade], _ b: [Trade]) -> [Trade] {
        var map = Dictionary(uniqueKeysWithValues: a.map { ($0.id, $0) })
        for trade in b {
            map[trade.id] = trade
        }
        return Array(map.values)
    }
}
