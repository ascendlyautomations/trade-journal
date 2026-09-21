import Foundation
import Observation

/// Session-scoped owner trade list used by Dashboard, Trade History, and legacy Calendar month fallback.
///
/// **Analytical / list window only** — not authoritative ``TradeDetail``. Detail/edit uses
/// ``TradeDetailRepository``. Journal list uses ``TradeOwnerJournalSummary`` (Phase 8C).
///
/// Single in-memory + disk source — bounded to dashboard trade window (≤500).
@Observable
@MainActor
final class SessionOwnerTradesStore {
    static let shared = SessionOwnerTradesStore()

    struct HydrateResult: Sendable {
        var hydrated: Bool
        var complete: Bool
        var tradeCount: Int
    }

    private var tradesByOwner: [ProfileID: [Trade]] = [:]
    private var loadedAt: [ProfileID: Date] = [:]
    private var metadataByOwner: [ProfileID: OwnerTradeCacheCompleteness.Metadata] = [:]
    private var inFlight: [ProfileID: Task<[Trade], Error>] = [:]

    /// Analytics window — Realtime / local mutations keep this coherent longer.
    private let freshTTL: TimeInterval = 10 * 60

    private init() {}

    func cached(for profileID: ProfileID) -> [Trade]? {
        tradesByOwner[profileID]
    }

    /// Hydrates memory from dashboard disk (authoritative window) or session owner-trades blob.
    @discardableResult
    func hydrateFromDiskIfNeeded(
        for profileID: ProfileID,
        detailCache: DetailPresentationCache
    ) -> HydrateResult {
        if tradesByOwner[profileID] != nil {
            return HydrateResult(
                hydrated: true,
                complete: isCompleteSnapshot(for: profileID),
                tradeCount: tradesByOwner[profileID]?.count ?? 0
            )
        }

        if hydrateFromDashboardDisk(for: profileID, detailCache: detailCache) {
            #if DEBUG
            ColdLaunchSummaryProbe.markPersistentRead()
            #endif
            return HydrateResult(
                hydrated: true,
                complete: isCompleteSnapshot(for: profileID),
                tradeCount: tradesByOwner[profileID]?.count ?? 0
            )
        }

        guard let blob = SessionDiskCache.loadOwnerTrades(for: profileID) else {
            return HydrateResult(hydrated: false, complete: false, tradeCount: 0)
        }
        #if DEBUG
        ColdLaunchSummaryProbe.markPersistentRead()
        #endif
        seed(
            blob.trades,
            for: profileID,
            detailCache: detailCache,
            historyComplete: blob.historyComplete,
            totalTradeCount: blob.totalTradeCount
        )
        return HydrateResult(
            hydrated: true,
            complete: isCompleteSnapshot(for: profileID),
            tradeCount: blob.trades.count
        )
    }

    func isFresh(for profileID: ProfileID, now: Date = Date()) -> Bool {
        guard let loaded = loadedAt[profileID], tradesByOwner[profileID] != nil else { return false }
        return now.timeIntervalSince(loaded) < freshTTL
    }

    func snapshotMetadata(for profileID: ProfileID) -> OwnerTradeCacheCompleteness.Metadata? {
        metadataByOwner[profileID]
    }

    func isCompleteSnapshot(for profileID: ProfileID) -> Bool {
        OwnerTradeCacheCompleteness.isCompleteSnapshot(metadataByOwner[profileID])
    }

    func noteBootstrapMetadata(
        for profileID: ProfileID,
        historyComplete: Bool,
        totalTradeCount: Int
    ) {
        let cachedTrades = tradesByOwner[profileID] ?? []
        metadataByOwner[profileID] = OwnerTradeCacheCompleteness.metadata(
            historyComplete: historyComplete,
            totalTradeCount: totalTradeCount,
            cachedTrades: cachedTrades
        )
        persistMetadata(for: profileID)
    }

    func trades(
        for profileID: ProfileID,
        detailCache: DetailPresentationCache,
        repository: any TradeRepository,
        limit: Int = 500,
        forceNetwork: Bool = false
    ) async throws -> [Trade] {
        if !forceNetwork, let cached = tradesByOwner[profileID], isFresh(for: profileID) {
            SessionNetworkProbe.record(
                .cacheHit,
                resource: "ownerTrades",
                detail: "count=\(cached.count)"
            )
            return cached
        }

        if let existing = inFlight[profileID] {
            SessionNetworkProbe.record(.requestCoalesced, resource: "ownerTrades", detail: profileID.rawValue)
            return try await existing.value
        }

        SessionNetworkProbe.record(.cacheMiss, resource: "ownerTrades", detail: profileID.rawValue)
        SessionNetworkProbe.record(.networkFetch, resource: "ownerTrades", detail: profileID.rawValue)

        let task = Task {
            try await repository.trades(
                ownedBy: profileID,
                accountID: nil,
                page: PageRequest(limit: limit),
                publicOnly: false
            ).items
        }
        inFlight[profileID] = task
        defer { inFlight[profileID] = nil }

        let loaded = try await task.value
        seed(loaded, for: profileID, detailCache: detailCache)
        return loaded
    }

    func seed(
        _ trades: [Trade],
        for profileID: ProfileID,
        detailCache: DetailPresentationCache,
        historyComplete: Bool? = nil,
        totalTradeCount: Int? = nil
    ) {
        tradesByOwner[profileID] = trades
        loadedAt[profileID] = Date()
        detailCache.seedListPreviews(trades)
        if let historyComplete, let totalTradeCount {
            noteBootstrapMetadata(
                for: profileID,
                historyComplete: historyComplete,
                totalTradeCount: totalTradeCount
            )
        } else {
            persistTrades(trades, for: profileID)
        }
    }

    func upsert(_ trade: Trade, detailCache: DetailPresentationCache) {
        let owner = trade.ownerProfileID
        var list = tradesByOwner[owner] ?? []
        let existed = list.contains { $0.id == trade.id }
        list.removeAll { $0.id == trade.id }
        list.insert(trade, at: 0)
        tradesByOwner[owner] = list
        loadedAt[owner] = Date()
        detailCache.seedAuthoritativeDetail(trade, authority: .authoritativeMutation)
        if var meta = metadataByOwner[owner] {
            if !existed {
                meta.totalTradeCount += 1
            }
            meta.cachedTradeCount = list.count
            metadataByOwner[owner] = meta
            persistTrades(list, for: owner, metadata: meta)
        } else {
            persistTrades(list, for: owner)
        }
        SessionNetworkProbe.record(.localMutation, resource: "ownerTrades", detail: trade.id.rawValue)
    }

    func remove(id: TradeID, owner: ProfileID) {
        guard var list = tradesByOwner[owner] else { return }
        let removed = list.contains { $0.id == id }
        list.removeAll { $0.id == id }
        tradesByOwner[owner] = list
        loadedAt[owner] = Date()
        if var meta = metadataByOwner[owner], removed {
            meta.totalTradeCount = max(0, meta.totalTradeCount - 1)
            meta.cachedTradeCount = list.count
            metadataByOwner[owner] = meta
            persistTrades(list, for: owner, metadata: meta)
        } else {
            persistTrades(list, for: owner)
        }
        SessionNetworkProbe.record(.localMutation, resource: "ownerTrades.remove", detail: id.rawValue)
    }

    func invalidate(profileID: ProfileID? = nil) {
        if let profileID {
            tradesByOwner[profileID] = nil
            loadedAt[profileID] = nil
            metadataByOwner[profileID] = nil
            inFlight[profileID]?.cancel()
            inFlight[profileID] = nil
        } else {
            inFlight.values.forEach { $0.cancel() }
            tradesByOwner = [:]
            loadedAt = [:]
            metadataByOwner = [:]
            inFlight = [:]
        }
        SessionNetworkProbe.record(.cacheInvalidated, resource: "ownerTrades", detail: profileID?.rawValue ?? "all")
    }

    // MARK: - Private

    private func hydrateFromDashboardDisk(
        for profileID: ProfileID,
        detailCache: DetailPresentationCache
    ) -> Bool {
        guard let loaded = BackendV2BootstrapDiskCache.loadDashboard(viewerID: profileID.rawValue) else {
            return false
        }
        let bootstrap = loaded.bootstrap
        var trades: [Trade] = []
        for row in bootstrap.data.trade_window {
            let dto = row.asTradeDTO(ownerID: profileID.rawValue)
            if let trade = try? TradeMapper.mapToDomain(dto) {
                trades.append(trade)
            }
        }
        seed(
            trades,
            for: profileID,
            detailCache: detailCache,
            historyComplete: bootstrap.data.trade_window_meta.history_complete,
            totalTradeCount: bootstrap.data.trade_window_meta.total_trade_count
        )
        return true
    }

    private func persistTrades(
        _ trades: [Trade],
        for profileID: ProfileID,
        metadata: OwnerTradeCacheCompleteness.Metadata? = nil
    ) {
        let meta = metadata ?? metadataByOwner[profileID]
        SessionDiskCache.saveOwnerTrades(
            trades,
            for: profileID,
            historyComplete: meta?.historyComplete,
            totalTradeCount: meta?.totalTradeCount
        )
    }

    private func persistMetadata(for profileID: ProfileID) {
        guard let trades = tradesByOwner[profileID] else { return }
        persistTrades(trades, for: profileID, metadata: metadataByOwner[profileID])
    }
}
