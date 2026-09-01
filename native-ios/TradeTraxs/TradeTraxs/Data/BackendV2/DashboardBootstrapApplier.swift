import Foundation

/// Maps `DashboardBootstrapV1` into native Dashboard stores.
nonisolated enum DashboardBootstrapApplier {
    struct Applied: Sendable {
        var accounts: [TradingAccount]
        var trades: [Trade]
        var payoutTotal: Decimal?
        var skippedTrades: Int
    }

    @MainActor
    static func apply(
        _ bootstrap: DashboardBootstrapV1,
        expectedViewerID: String,
        detailCache: DetailPresentationCache
    ) async throws -> Applied {
        let viewer = bootstrap.meta.viewer_id ?? expectedViewerID
        guard viewer == expectedViewerID else {
            throw BackendV2RPCError.decode("viewer_id mismatch")
        }
        try bootstrap.validateContract()

        let profileID = ProfileID(expectedViewerID)
        TradeMappingTelemetry.beginLoad("dashboard.trade_window")
        defer { TradeMappingTelemetry.endLoad() }

        let accounts = mapAccounts(bootstrap.data.accounts, ownerID: profileID)
        let mapped = mapTrades(bootstrap.data.trade_window, ownerID: profileID)

        SessionAccountsStore.shared.seed(
            accounts,
            for: profileID,
            detailCache: detailCache,
            kind: .rest
        )
        SessionOwnerTradesStore.shared.seed(mapped.trades, for: profileID, detailCache: detailCache)
        detailCache.seed(trades: mapped.trades)

        let payout = bootstrap.data.payout_total?.decimal

        return Applied(
            accounts: accounts,
            trades: mapped.trades,
            payoutTotal: payout,
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
