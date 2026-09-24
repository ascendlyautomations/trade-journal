import Foundation

/// Shadow-write Dashboard V3 RPC payloads to GRDB (failures must not affect UI).
enum AnalyticsDashboardShadowWriter {
    static func ingestBootstrapIfNeeded(
        viewerID: ProfileID,
        bootstrap: AnalyticsDashboardBootstrapV3
    ) {
        Task(priority: .utility) {
            await ingestBootstrap(viewerID: viewerID, bootstrap: bootstrap)
        }
    }

    static func ingestBootstrap(
        viewerID: ProfileID,
        bootstrap: AnalyticsDashboardBootstrapV3
    ) async {
        let store = AnalyticsLocalStore.sharedStore()
        do {
            _ = try await store.ingestDashboardBootstrap(viewerID: viewerID, bootstrap: bootstrap)
            #if DEBUG
            let metrics = try await store.dashboardPresetMetrics(viewerID: viewerID)
            let charts = try await store.dashboardChartBundles(
                viewerID: viewerID,
                accountScopeKey: AnalyticsScopeKeys.allAccountsQuery
            )
            _ = AnalyticsDashboardShadowParity.validateBootstrap(
                viewerID: viewerID,
                bootstrap: bootstrap,
                localMetrics: metrics,
                localAggregateCharts: charts
            )
            await AnalyticsShadowReadParity.validateDashboardSnapshot(
                viewerID: viewerID,
                bootstrap: bootstrap
            )
            _ = await AnalyticsDatabase.shared.storageByteEstimate()
            #endif
        } catch {
            AnalyticsGRDBProbe.logShadowIngestFailure("dashboardBootstrap \(error)")
        }
    }

    static func ingestAggregateChartsIfNeeded(
        viewerID: ProfileID,
        response: AnalyticsDashboardAccountChartsV3,
        revision: Int64
    ) {
        Task(priority: .utility) {
            await ingestAggregateCharts(viewerID: viewerID, response: response, revision: revision)
        }
    }

    static func ingestAggregateCharts(
        viewerID: ProfileID,
        response: AnalyticsDashboardAccountChartsV3,
        revision: Int64
    ) async {
        let store = AnalyticsLocalStore.sharedStore()
        do {
            _ = try await store.ingestDashboardAggregateCharts(
                viewerID: viewerID,
                response: response,
                knownRevision: revision
            )
        } catch {
            AnalyticsGRDBProbe.logShadowIngestFailure("aggregateCharts \(error)")
        }
    }

    static func ingestAccountChartsIfNeeded(
        viewerID: ProfileID,
        response: AnalyticsDashboardAccountChartsV3,
        accountID: TradingAccountID,
        revision: Int64
    ) {
        Task(priority: .utility) {
            await ingestAccountCharts(
                viewerID: viewerID,
                response: response,
                accountID: accountID,
                revision: revision
            )
        }
    }

    static func ingestAccountCharts(
        viewerID: ProfileID,
        response: AnalyticsDashboardAccountChartsV3,
        accountID: TradingAccountID,
        revision: Int64
    ) async {
        let store = AnalyticsLocalStore.sharedStore()
        let accountKey = AnalyticsScopeKeys.accountScopeKey(forQueryAccountID: accountID.rawValue)
        do {
            _ = try await store.ingestDashboardAccountCharts(
                viewerID: viewerID,
                response: response,
                accountID: accountID,
                knownRevision: revision
            )
            #if DEBUG
            let bundles = try await store.dashboardChartBundles(
                viewerID: viewerID,
                accountScopeKey: accountKey
            )
            _ = AnalyticsDashboardShadowParity.validateAccountCharts(
                viewerID: viewerID,
                accountID: accountID,
                revision: revision,
                response: response,
                localBundles: bundles
            )
            await AnalyticsShadowReadParity.validateAccountChartsRead(
                viewerID: viewerID,
                accountID: accountID,
                revision: revision,
                response: response
            )
            _ = await AnalyticsDatabase.shared.storageByteEstimate()
            #endif
        } catch {
            AnalyticsGRDBProbe.logShadowIngestFailure("accountCharts \(error)")
        }
    }
}
