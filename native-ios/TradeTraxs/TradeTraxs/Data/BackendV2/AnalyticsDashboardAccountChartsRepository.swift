import Foundation

nonisolated struct AnalyticsDashboardAccountChartsRepository {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc, enforceKnownNames: false)
    }

    func load(accountID: TradingAccountID) async throws -> AnalyticsDashboardAccountChartsV3 {
        let data = try SupabaseJSONEncoding.encode(["p_account_id": accountID.rawValue])
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

nonisolated struct AnalyticsDashboardAggregateChartsRepository {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc, enforceKnownNames: false)
    }

    func load() async throws -> AnalyticsDashboardAccountChartsV3 {
        let value = try await client.call(
            BackendV2Versioning.RPCName.analyticsDashboardAggregateChartsV3.rawValue,
            argumentsJSON: Data("{}".utf8),
            as: AnalyticsDashboardAccountChartsV3.self,
            options: BackendV2RPCCallOptions(
                flagName: BackendV2FeatureFlag.dashboardAnalyticsV3.dottedName
            )
        )
        try value.validateContractVersion()
        return value
    }
}

enum DashboardAnalyticsAggregateChartsLoader {
    private static func flightKey(revision: Int64, viewerID: ProfileID?) -> String {
        let owner = DashboardSessionIsolation.normalizedOwner(viewerID?.rawValue ?? "")
        let scope = owner.isEmpty ? "unscoped" : owner
        return "dashboard.v3.aggregateCharts|\(scope)|rev:\(revision)"
    }

    @MainActor
    static func loadCoalesced(
        revision: Int64,
        rpc: any RPCClient,
        viewerID: ProfileID? = nil
    ) async throws -> [String: AnalyticsDashboardChartsPresetV1] {
        let store = DashboardAnalyticsAggregateChartsStore.shared
        if let cached = store.charts(revision: revision),
           store.availability(revision: revision).isLoaded,
           DashboardAnalyticsChartsSupport.chartsReadyForPresentation(cached)
        {
            return cached
        }
        if let cached = store.charts(revision: revision),
           DashboardAnalyticsChartsSupport.hasEquityPoints(cached),
           !DashboardAnalyticsChartsSupport.hasVisualExpansionContract(cached)
        {
            store.dropCharts(revision: revision)
        }

        let key = flightKey(revision: revision, viewerID: viewerID)
        let encoded = try await BackendV2SingleFlight.shared.coalesce(key: key) {
            let repo = AnalyticsDashboardAggregateChartsRepository(rpc: rpc)
            let response = try await repo.load()
            return try JSONEncoder().encode(response)
        }

        let response = try JSONDecoder().decode(AnalyticsDashboardAccountChartsV3.self, from: encoded)
        let presets = response.data.presets
        if let viewerID {
            guard SessionViewerGate.shared.allowsDisplay(owner: viewerID.rawValue) else {
                return presets
            }
            DashboardAnalyticsAggregateChartsStore.shared.markLoaded(
                revision: revision,
                presets: presets,
                viewerID: viewerID.rawValue
            )
            AnalyticsDashboardShadowWriter.ingestAggregateChartsIfNeeded(
                viewerID: viewerID,
                response: response,
                revision: revision
            )
        } else {
            DashboardAnalyticsAggregateChartsStore.shared.markLoaded(
                revision: revision,
                presets: presets
            )
        }
        return presets
    }
}

enum DashboardAnalyticsAccountChartsLoader {
    private static func flightKey(accountID: TradingAccountID, revision: Int64, viewerID: ProfileID?) -> String {
        let norm = DashboardAnalyticsAccountMetricsLookup.normalizedAccountID(accountID.rawValue)
        let owner = DashboardSessionIsolation.normalizedOwner(viewerID?.rawValue ?? "")
        let scope = owner.isEmpty ? "unscoped" : owner
        return "dashboard.v3.accountCharts|\(scope)|\(norm)|rev:\(revision)"
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
           store.availability(accountID: accountID, revision: revision).isLoaded,
           DashboardAnalyticsChartsSupport.chartsReadyForPresentation(cached)
        {
            return cached
        }
        if let cached = store.charts(accountID: accountID, revision: revision),
           DashboardAnalyticsChartsSupport.hasEquityPoints(cached),
           !DashboardAnalyticsChartsSupport.hasVisualExpansionContract(cached)
        {
            store.dropCharts(accountID: accountID, revision: revision)
        }

        let key = flightKey(accountID: accountID, revision: revision, viewerID: viewerID)
        let encoded = try await BackendV2SingleFlight.shared.coalesce(key: key) {
            let repo = AnalyticsDashboardAccountChartsRepository(rpc: rpc)
            let response = try await repo.load(accountID: accountID)
            return try JSONEncoder().encode(response)
        }

        let response = try JSONDecoder().decode(AnalyticsDashboardAccountChartsV3.self, from: encoded)
        let presets = response.data.presets
        if let viewerID {
            guard SessionViewerGate.shared.allowsDisplay(owner: viewerID.rawValue) else {
                return presets
            }
            DashboardAnalyticsAccountChartsStore.shared.markLoaded(
                accountID: accountID,
                revision: revision,
                presets: presets,
                viewerID: viewerID.rawValue
            )
            AnalyticsDashboardShadowWriter.ingestAccountChartsIfNeeded(
                viewerID: viewerID,
                response: response,
                accountID: accountID,
                revision: revision
            )
        } else {
            DashboardAnalyticsAccountChartsStore.shared.markLoaded(
                accountID: accountID,
                revision: revision,
                presets: presets
            )
        }
        return presets
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
