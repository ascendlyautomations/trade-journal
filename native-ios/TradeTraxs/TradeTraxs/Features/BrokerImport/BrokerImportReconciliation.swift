import Foundation

struct BrokerImportReconciliationResult: Sendable {
    var newTradeIDs: [TradeID]
    var hydratedTrades: [Trade]
    var authoritativeNewCount: Int

    var authoritativeNewImportCount: Int { authoritativeNewCount }
}

/// Apply authoritative broker import results into journal caches (no polling).
@MainActor
enum BrokerImportReconciliation {
    static func apply(
        owner: ProfileID,
        summary: TradovateSyncSummaryPayload,
        tradesRepository: any TradeRepository,
        detailCache: DetailPresentationCache
    ) async -> BrokerImportReconciliationResult {
        let ids = summary.resolvedNewTradeIDs.map { TradeID($0) }
        var hydrated: [Trade] = []
        if !ids.isEmpty {
            hydrated = (try? await tradesRepository.trades(ids: ids)) ?? []
        }
        TradeJournalMutationStore.shared.noteBulkImport(owner: owner, source: .tradovate)
        for trade in hydrated {
            detailCache.seedAuthoritativeDetail(trade, authority: .authoritativeNetwork)
            SessionOwnerTradesStore.shared.upsert(trade, detailCache: detailCache)
            TradeHistorySessionStore.shared.noteUpserted(trade)
            SocialEntityPersistedCacheCoordinator.saveTradeSummary(
                TradeSummaryMapper.summary(fromPartialListTrade: trade),
                viewerID: owner,
                source: .detail,
                mergeMode: .replace
            )
        }
        BrokerIntegrationMutationStore.shared.noteBrokerIntegrationChanged()
        BrokerImportEligibilityStore.shared.refresh(fromUserAction: false)
        return BrokerImportReconciliationResult(
            newTradeIDs: ids,
            hydratedTrades: hydrated,
            authoritativeNewCount: summary.authoritativeNewImportCount
        )
    }
}

extension TradovateSyncSummaryPayload {
    /// Prefer explicit IDs; fall back to server trade counts when IDs are omitted.
    var resolvedNewTradeIDs: [String] {
        if !newTradeIds.isEmpty { return newTradeIds }
        return []
    }

    var authoritativeNewImportCount: Int {
        if !newTradeIds.isEmpty { return newTradeIds.count }
        if tradesCreated > 0 { return tradesCreated }
        return 0
    }
}
