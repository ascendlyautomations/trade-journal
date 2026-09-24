import Foundation
import Testing
@testable import TradeTraxs

struct DashboardAnalyticsGRDBCutoverTests {
    private func makeStore() throws -> (URL, AnalyticsLocalStore) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dashboard-grdb-cutover-\(UUID().uuidString).sqlite")
        let db = AnalyticsDatabase(configuration: .testing(databaseURL: url))
        return (url, AnalyticsLocalStore(database: db))
    }

    private func fullBootstrap(revision: Int64) throws -> AnalyticsDashboardBootstrapV3 {
        var bootstrap = try DashboardAnalyticsV3Tests().makeBootstrap()
        bootstrap.data.revision = PostgresFlexibleDouble(Double(revision))
        bootstrap.data.presets = fullAggregatePresets(from: bootstrap).mapValues {
            AnalyticsDashboardAggregatePresetV1(full: $0)
        }
        return bootstrap
    }

    @Test("Complete GRDB snapshot presentation read")
    func grdbPresentationComplete() async throws {
        let (url, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("dash-grdb-present")
        let bootstrap = try fullBootstrap(revision: 44)
        _ = try await store.ingestDashboardBootstrap(viewerID: viewer, bootstrap: bootstrap)
        try await ingestAggregateCharts(from: bootstrap, viewer: viewer, store: store, revision: 44)
        let read = try await store.readDashboardSnapshotForPresentation(viewerID: viewer)
        #expect(read.canRenderLocally)
        #expect(read.effectiveRevision == 44)
        #expect(read.snapshot?.aggregatePresets.count == 5)
    }

    @Test("GRDB mapper builds bootstrap with five presets")
    func mapperBootstrap() async throws {
        let (url, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("dash-grdb-map")
        let bootstrap = try fullBootstrap(revision: 7)
        _ = try await store.ingestDashboardBootstrap(viewerID: viewer, bootstrap: bootstrap)
        try await ingestAggregateCharts(from: bootstrap, viewer: viewer, store: store, revision: 7)
        let read = try await store.readDashboardSnapshotForPresentation(viewerID: viewer)
        guard let snapshot = read.snapshot else {
            Issue.record("expected snapshot")
            return
        }
        let mapped = DashboardAnalyticsGRDBMapper.bootstrap(
            snapshot: snapshot,
            viewerID: viewer,
            diskEnvelope: bootstrap,
            sessionAccounts: []
        )
        #expect(mapped.data.aggregatePresets.count == 5)
        #expect(mapped.data.revisionInt == 7)
    }

    @Test("Stale account charts are not available at newer dashboard revision")
    func accountChartsStaleAtNewRevision() async throws {
        let (url, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("dash-grdb-stale-charts")
        let account = TradingAccountID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        let charts = makeAccountCharts(accountID: account.rawValue)
        _ = try await store.ingestDashboardAccountCharts(
            viewerID: viewer,
            response: charts,
            accountID: account,
            knownRevision: 20
        )
        let read = try await store.readDashboardAccountCharts(
            viewerID: viewer,
            accountID: account,
            requiredRevision: 21
        )
        #expect(read.state == .stale(foundRevision: 20))
        #expect(read.presets.isEmpty)
    }

    @Test("dashboardAnalyticsGRDB flag OFF when disabled")
    func grdbFlagRollback() {
        BackendV2FeatureFlags.resetFlagsForTests()
        BackendV2FeatureFlags.setFlagForTests(.dashboardAnalyticsV3, enabled: true)
        BackendV2FeatureFlags.setFlagForTests(.dashboardAnalyticsGRDB, enabled: false)
        #expect(!BackendV2FeatureFlags.isEnabled(.dashboardAnalyticsGRDB))
        BackendV2FeatureFlags.resetFlagsForTests()
    }
}

private func ingestAggregateCharts(
    from bootstrap: AnalyticsDashboardBootstrapV3,
    viewer: ProfileID,
    store: AnalyticsLocalStore,
    revision: Int64
) async throws {
    var presets: [String: AnalyticsDashboardChartsPresetV1] = [:]
    for (key, bundle) in bootstrap.data.aggregatePresets {
        presets[key] = AnalyticsDashboardChartsPresetV1(
            preset: bundle.preset,
            start: bundle.start,
            end: bundle.end,
            equity: bundle.equity,
            distributions: bundle.distributions,
            insights: bundle.insights
        )
    }
    let response = AnalyticsDashboardAccountChartsV3(
        meta: bootstrap.meta,
        data: .init(
            account_id: nil,
            as_of_et: bootstrap.data.as_of_et,
            presets: presets
        )
    )
    _ = try await store.ingestDashboardAggregateCharts(
        viewerID: viewer,
        response: response,
        knownRevision: revision
    )
}

private func fullAggregatePresets(
    from bootstrap: AnalyticsDashboardBootstrapV3
) -> [String: AnalyticsDashboardPresetBundleV1] {
    guard let template = bootstrap.data.aggregatePresets["d30"] else { return [:] }
    var presets: [String: AnalyticsDashboardPresetBundleV1] = [:]
    for key in AnalyticsLocalDashboardPolicy.aggregatePresetKeys {
        presets[key] = AnalyticsDashboardPresetBundleV1(
            preset: key,
            start: template.start,
            end: template.end,
            metrics: template.metrics,
            equity: template.equity,
            distributions: template.distributions,
            insights: template.insights
        )
    }
    return presets
}

private func makeAccountCharts(accountID: String) -> AnalyticsDashboardAccountChartsV3 {
    let preset = AnalyticsDashboardChartsPresetV1(
        preset: "d30",
        start: "2026-08-23",
        end: "2026-09-21",
        equity: AnalyticsDashboardEquityWireV1(
            points: [],
            max_drawdown: PostgresFlexibleDouble(0),
            current_equity: PostgresFlexibleDouble(0)
        ),
        distributions: AnalyticsDashboardDistributionsWireV1(
            sessions: [],
            weekday_bars: [],
            weekday_heatmap: [],
            hour_bars: [],
            hour_heatmap: [],
            avg_hold_seconds: nil,
            avg_winner_hold_seconds: nil,
            avg_loser_hold_seconds: nil,
            hold_histogram: [],
            long_short: [],
            long_trade_count: 0,
            short_trade_count: 0
        ),
        insights: []
    )
    return AnalyticsDashboardAccountChartsV3(
        meta: BootstrapMetaV1(
            contract_version: "v1",
            server_time: "2026-09-21T12:00:00.000Z",
            viewer_id: "u"
        ),
        data: .init(
            account_id: accountID,
            as_of_et: "2026-09-21",
            presets: ["d30": preset]
        )
    )
}
