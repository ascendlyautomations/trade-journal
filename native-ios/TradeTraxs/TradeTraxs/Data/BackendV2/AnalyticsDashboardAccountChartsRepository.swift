import Foundation

nonisolated struct AnalyticsDashboardAccountChartsRepository {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc, enforceKnownNames: false)
    }

    func load(accountID: TradingAccountID) async throws -> AnalyticsDashboardAccountChartsV3 {
        let args = ["p_account_id": accountID.rawValue]
        let data = try JSONSerialization.data(withJSONObject: args)
        let value = try await client.call(
            BackendV2Versioning.RPCName.analyticsDashboardAccountChartsV3.rawValue,
            argumentsJSON: data,
            as: AnalyticsDashboardAccountChartsV3.self,
            options: BackendV2RPCCallOptions(
                flagName: BackendV2FeatureFlag.dashboardAnalyticsV3.dottedName
            )
        )
        try value.validateContractVersion()
        return value
    }
}

enum DashboardAnalyticsAccountChartsLoader {
    private static func flightKey(accountID: TradingAccountID, revision: Int64) -> String {
        let norm = DashboardAnalyticsAccountMetricsLookup.normalizedAccountID(accountID.rawValue)
        return "dashboard.v3.accountCharts|\(norm)|rev:\(revision)"
    }

    @MainActor
    static func loadCoalesced(
        accountID: TradingAccountID,
        revision: Int64,
        rpc: any RPCClient,
        viewerID: ProfileID? = nil
    ) async throws -> [String: AnalyticsDashboardChartsPresetV1] {
        let store = DashboardAnalyticsAccountChartsStore.shared
        if let cached = store.charts(accountID: accountID, revision: revision),
           store.availability(accountID: accountID, revision: revision).isLoaded
        {
            return cached
        }

        let key = flightKey(accountID: accountID, revision: revision)
        let encoded = try await BackendV2SingleFlight.shared.coalesce(key: key) {
            let repo = AnalyticsDashboardAccountChartsRepository(rpc: rpc)
            let response = try await repo.load(accountID: accountID)
            return try JSONEncoder().encode(response)
        }

        let response = try JSONDecoder().decode(AnalyticsDashboardAccountChartsV3.self, from: encoded)
        await MainActor.run {
            DashboardAnalyticsAccountChartsStore.shared.markLoaded(
                accountID: accountID,
                revision: revision,
                presets: response.data.presets
            )
        }
        if let viewerID {
            AnalyticsDashboardShadowWriter.ingestAccountChartsIfNeeded(
                viewerID: viewerID,
                response: response,
                accountID: accountID,
                revision: revision
            )
        }
        return response.data.presets
    }

    @MainActor
    static func loadIfNeeded(
        accountID: TradingAccountID,
        revision: Int64,
        rpc: any RPCClient,
        viewerID: ProfileID? = nil
    ) async throws -> [String: AnalyticsDashboardChartsPresetV1] {
        try await loadCoalesced(
            accountID: accountID,
            revision: revision,
            rpc: rpc,
            viewerID: viewerID
        )
    }
}
