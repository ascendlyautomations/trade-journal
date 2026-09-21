import Foundation

nonisolated enum TradesListBootstrapApplier {
    struct Applied: Sendable {
        var accounts: [TradingAccount]
        var summaries: [TradeOwnerJournalSummary]
        var nextCursor: String?
        var skippedTrades: Int
    }

    @MainActor
    static func apply(
        _ bootstrap: TradesListBootstrapV1,
        ownerID: ProfileID,
        detailCache: DetailPresentationCache
    ) -> Applied {
        let accounts = mapAccounts(bootstrap.data.accounts, ownerID: ownerID)
        let mapped = mapTrades(bootstrap.data.trades, ownerID: ownerID)

        SessionAccountsStore.shared.seed(
            accounts,
            for: ownerID,
            detailCache: detailCache,
            kind: .rest
        )
        detailCache.seed(journalSummaries: mapped.summaries)

        #if DEBUG
        TradeSummaryJournalTelemetry.recordDecode(
            path: "v1.rpc",
            tradeCount: mapped.summaries.count,
            skipped: mapped.skipped
        )
        #endif

        return Applied(
            accounts: accounts,
            summaries: mapped.summaries,
            nextCursor: bootstrap.data.page_meta.has_more ? bootstrap.data.next_cursor : nil,
            skippedTrades: mapped.skipped
        )
    }

    private static func mapAccounts(
        _ rows: [DashboardAccountWireV1],
        ownerID: ProfileID
    ) -> [TradingAccount] {
        rows.compactMap { row -> TradingAccount? in
            let dto = row.asAccountDTO(ownerID: ownerID.rawValue)
            return try? TradingAccountMapper.mapToDomain(dto)
        }
    }

    private static func mapTrades(
        _ rows: [DashboardTradeWireV1],
        ownerID: ProfileID
    ) -> (summaries: [TradeOwnerJournalSummary], skipped: Int) {
        var summaries: [TradeOwnerJournalSummary] = []
        var skipped = 0
        for row in rows {
            let dto = row.asTradeDTO(ownerID: ownerID.rawValue)
            do {
                let trade = try TradeMapper.mapToDomain(dto)
                summaries.append(TradeSummaryMapper.ownerJournal(fromListTrade: trade))
            } catch {
                skipped += 1
                TradeMappingTelemetry.recordSkippedTrade()
            }
        }
        return (summaries, skipped)
    }
}
