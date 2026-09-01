import Foundation

nonisolated enum TradesListBootstrapApplier {
    struct Applied: Sendable {
        var accounts: [TradingAccount]
        var trades: [Trade]
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
        detailCache.seed(trades: mapped.trades)

        return Applied(
            accounts: accounts,
            trades: mapped.trades,
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
    ) -> (trades: [Trade], skipped: Int) {
        var trades: [Trade] = []
        var skipped = 0
        for row in rows {
            let dto = row.asTradeDTO(ownerID: ownerID.rawValue)
            do {
                trades.append(try TradeMapper.mapToDomain(dto))
            } catch {
                skipped += 1
                TradeMappingTelemetry.recordSkippedTrade()
            }
        }
        return (trades, skipped)
    }
}
