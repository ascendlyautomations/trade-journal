import Foundation

nonisolated enum TradesListBootstrapV2Applier {
    @MainActor
    static func apply(
        _ bootstrap: TradesListBootstrapV2,
        ownerID: ProfileID,
        detailCache: DetailPresentationCache
    ) -> TradesListBootstrapApplier.Applied {
        let accounts = mapAccounts(bootstrap.data.accounts, ownerID: ownerID)
        let mapped = mapSummaries(bootstrap.data.trades)

        SessionAccountsStore.shared.seed(
            accounts,
            for: ownerID,
            detailCache: detailCache,
            kind: .rest
        )
        detailCache.seed(journalSummaries: mapped.summaries)

        #if DEBUG
        TradeSummaryJournalTelemetry.recordDecode(
            path: "v2.rpc",
            tradeCount: mapped.summaries.count,
            skipped: mapped.skipped
        )
        #endif

        return TradesListBootstrapApplier.Applied(
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

    private static func mapSummaries(
        _ rows: [TradeOwnerJournalSummaryWireV1]
    ) -> (summaries: [TradeOwnerJournalSummary], skipped: Int) {
        var summaries: [TradeOwnerJournalSummary] = []
        var skipped = 0
        for row in rows {
            do {
                try row.validateSchema()
                summaries.append(try TradeSummaryMapper.mapOwnerJournal(from: row))
            } catch {
                skipped += 1
                TradeMappingTelemetry.recordSkippedTrade()
            }
        }
        return (summaries, skipped)
    }
}
