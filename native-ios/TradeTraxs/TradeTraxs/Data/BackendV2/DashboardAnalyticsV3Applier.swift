import Foundation

nonisolated enum DashboardAnalyticsV3Applier {
    struct Applied: Sendable {
        var accounts: [TradingAccount]
        var payoutTotal: Decimal?
        var revision: Int64
        var bootstrap: AnalyticsDashboardBootstrapV3
    }

    @MainActor
    static func apply(
        _ bootstrap: AnalyticsDashboardBootstrapV3,
        expectedViewerID: String,
        detailCache: DetailPresentationCache
    ) throws -> Applied {
        let viewer = bootstrap.meta.viewer_id ?? expectedViewerID
        guard DashboardSessionIsolation.ownersMatch(viewer, expectedViewerID) else {
            throw BackendV2RPCError.decode("viewer_id mismatch")
        }

        let profileID = ProfileID(expectedViewerID)
        let accounts = mapAccounts(bootstrap.data.accounts, ownerID: profileID)
        SessionAccountsStore.shared.seed(
            accounts,
            for: profileID,
            detailCache: detailCache,
            kind: .rest
        )

        let payout: Decimal? = bootstrap.data.payout_total.flatMap { wire in
            guard let value = wire.value else { return nil }
            return Decimal(value)
        }
        #if DEBUG
        logAccountPresetMetricsSample(bootstrap)
        #endif
        return Applied(
            accounts: accounts,
            payoutTotal: payout,
            revision: bootstrap.data.revisionInt,
            bootstrap: bootstrap
        )
    }

    #if DEBUG
    private static func logAccountPresetMetricsSample(_ bootstrap: AnalyticsDashboardBootstrapV3) {
        let rows = bootstrap.data.account_preset_metrics ?? []
        guard !rows.isEmpty else {
            print("[DashboardV3][AccountMetricsSample] account_preset_metrics=empty")
            return
        }
        for row in rows.prefix(3) {
            let d30 = row.presets["d30"]?.metrics
            print(
                "[DashboardV3][AccountMetricsSample] accountID=\(row.account_id) " +
                    "d30.trade_count=\(d30?.trade_count ?? -1) d30.net_pnl=\(d30?.net_pnl.value ?? 0)"
            )
        }
        if let all = bootstrap.data.aggregatePresets["d30"]?.metrics {
            print(
                "[DashboardV3][AccountMetricsSample] aggregate d30.trade_count=\(all.trade_count) " +
                    "net_pnl=\(all.net_pnl.value ?? 0)"
            )
        }
    }
    #endif

    private static func mapAccounts(
        _ rows: [DashboardAccountWireV1],
        ownerID: ProfileID
    ) -> [TradingAccount] {
        rows.compactMap { row -> TradingAccount? in
            let dto = row.asAccountDTO(ownerID: ownerID.rawValue)
            return try? TradingAccountMapper.mapToDomain(dto)
        }
    }
}
