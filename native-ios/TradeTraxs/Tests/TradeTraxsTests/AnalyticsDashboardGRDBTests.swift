import Foundation
import GRDB
import Testing
@testable import TradeTraxs

struct AnalyticsDashboardGRDBTests {
    private func makeStore() throws -> (URL, AnalyticsLocalStore) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("analytics-dashboard-grdb-\(UUID().uuidString).sqlite")
        let db = AnalyticsDatabase(configuration: .testing(databaseURL: url))
        let store = AnalyticsLocalStore(database: db)
        return (url, store)
    }

    private func sampleBootstrap(revision: Int64 = 10) throws -> AnalyticsDashboardBootstrapV3 {
        var bootstrap = try DashboardAnalyticsV3Tests().makeBootstrap()
        bootstrap.data.revision = PostgresFlexibleDouble(Double(revision))
        return bootstrap
    }

    private func sampleBootstrapSingleAccount(revision: Int64) throws -> AnalyticsDashboardBootstrapV3 {
        var bootstrap = try sampleBootstrap(revision: revision)
        bootstrap.data.account_preset_metrics = bootstrap.data.account_preset_metrics?.filter {
            $0.account_id == "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        }
        return bootstrap
    }

    private func sampleAccountCharts(accountID: String, emptyEquity: Bool = false) -> AnalyticsDashboardAccountChartsV3 {
        let points: [AnalyticsDashboardEquityPointWireV1] = emptyEquity ? [] : [
            AnalyticsDashboardEquityPointWireV1(
                t: "2026-09-01T15:00:00.000Z",
                v: PostgresFlexibleDouble(50),
                i: 0
            ),
        ]
        let preset = AnalyticsDashboardChartsPresetV1(
            preset: "d30",
            start: "2026-08-23",
            end: "2026-09-21",
            equity: AnalyticsDashboardEquityWireV1(
                points: points,
                max_drawdown: PostgresFlexibleDouble(0),
                current_equity: PostgresFlexibleDouble(emptyEquity ? 0 : 50)
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

    @Test("Migration v2 creates dashboard tables")
    func migrationV2Tables() async throws {
        let (url, _) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let db = AnalyticsDatabase(configuration: .testing(databaseURL: url))
        let queue = try await db.databaseQueue()
        try await queue.read { db in
            let tables = try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type='table'"
            )
            #expect(tables.contains("dashboard_preset_metrics"))
            #expect(tables.contains("dashboard_chart_bundle"))
        }
    }

    @Test("Aggregate and account preset persistence")
    func presetPersistence() async throws {
        let (url, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("dash-viewer")
        let bootstrap = try sampleBootstrap()
        _ = try await store.ingestDashboardBootstrap(viewerID: viewer, bootstrap: bootstrap)
        let metrics = try await store.dashboardPresetMetrics(viewerID: viewer)
        #expect(!metrics.filter { $0.scope == AnalyticsLocalSchema.scopeAggregate }.isEmpty)
        #expect(!metrics.filter { $0.scope == AnalyticsLocalSchema.scopeAccount }.isEmpty)
    }

    @Test("Bootstrap replacement removes stale account presets")
    func bootstrapReplacement() async throws {
        let (url, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("dash-replace")
        try await store.ingestDashboardBootstrap(
            viewerID: viewer,
            bootstrap: try sampleBootstrap(revision: 1)
        )
        try await store.ingestDashboardBootstrap(
            viewerID: viewer,
            bootstrap: try sampleBootstrapSingleAccount(revision: 2)
        )
        let metrics = try await store.dashboardPresetMetrics(viewerID: viewer)
        #expect(metrics.filter { $0.scope == AnalyticsLocalSchema.scopeAccount }.count == 1)
        #expect(metrics.allSatisfy { $0.ingested_revision == 2 })
    }

    @Test("Account chart persistence and replacement isolation")
    func accountChartScope() async throws {
        let (url, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("dash-charts")
        let accountA = TradingAccountID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        let accountB = TradingAccountID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
        _ = try await store.ingestDashboardAccountCharts(
            viewerID: viewer,
            response: sampleAccountCharts(accountID: accountA.rawValue),
            accountID: accountA,
            knownRevision: 5
        )
        _ = try await store.ingestDashboardAccountCharts(
            viewerID: viewer,
            response: sampleAccountCharts(accountID: accountB.rawValue, emptyEquity: true),
            accountID: accountB,
            knownRevision: 5
        )
        let aBundles = try await store.dashboardChartBundles(
            viewerID: viewer,
            accountScopeKey: AnalyticsScopeKeys.accountScopeKey(forQueryAccountID: accountA.rawValue)
        )
        let bBundles = try await store.dashboardChartBundles(
            viewerID: viewer,
            accountScopeKey: AnalyticsScopeKeys.accountScopeKey(forQueryAccountID: accountB.rawValue)
        )
        #expect(aBundles.count == 1)
        #expect(bBundles.count == 1)
        let aCharts = try aBundles.first!.decodedCharts()
        let bCharts = try bBundles.first!.decodedCharts()
        #expect(aCharts.equity.points.count == 1)
        #expect(bCharts.equity.points.isEmpty)
    }

    @Test("Stale revision cannot regress analytics_sync_state")
    func monotonicRevision() async throws {
        let (url, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("dash-rev")
        try await store.ingestDashboardBootstrap(
            viewerID: viewer,
            bootstrap: try sampleBootstrap(revision: 15)
        )
        let calendarPayload = AnalyticsDailyRangeBootstrapV1(
            revision: PostgresFlexibleDouble(14),
            state_updated_at: nil,
            start: "2026-09-01",
            end: "2026-09-30",
            account_id: nil,
            mode: nil,
            days: [],
            summary: AnalyticsDailyRangeSummaryV1(
                trade_count: 0,
                win_count: 0,
                loss_count: 0,
                breakeven_count: 0,
                net_pnl: PostgresFlexibleDouble(0),
                gross_profit: PostgresFlexibleDouble(0),
                gross_loss: PostgresFlexibleDouble(0)
            )
        )
        try await store.ingestCalendarDailyRange(
            viewerID: viewer,
            payload: calendarPayload,
            scope: AnalyticsLocalStore.IngestScope(
                startDate: "2026-09-01",
                endDate: "2026-09-30",
                accountScope: AnalyticsScopeKeys.allAccountsQuery,
                modeScope: AnalyticsScopeKeys.allModesQuery
            )
        )
        let sync = try await store.syncState(viewerID: viewer)
        #expect(sync?.server_revision == 15)
        let coverage = try await store.coverage(
            viewerID: viewer,
            domain: AnalyticsLocalSchema.domainCalendar,
            accountScope: AnalyticsScopeKeys.allAccountsQuery,
            modeScope: AnalyticsScopeKeys.allModesQuery,
            startDate: "2026-09-01",
            endDate: "2026-09-30"
        )
        #expect(coverage?.server_revision == 14)
    }

    @Test("Calendar and Dashboard coexist in one database")
    func crossDomainCoexistence() async throws {
        let (url, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("coexist")
        try await store.ingestDashboardBootstrap(
            viewerID: viewer,
            bootstrap: try sampleBootstrap(revision: 3)
        )
        let day = AnalyticsDailyStatRowV1(
            calendar_day: "2026-09-04",
            account_id: nil,
            mode_effective: "live",
            trade_count: 1,
            win_count: 1,
            loss_count: 0,
            breakeven_count: 0,
            net_pnl: PostgresFlexibleDouble(10),
            gross_profit: PostgresFlexibleDouble(10),
            gross_loss: PostgresFlexibleDouble(0),
            long_count: 0,
            long_pnl: PostgresFlexibleDouble(0),
            short_count: 0,
            short_pnl: PostgresFlexibleDouble(0),
            sum_rr: PostgresFlexibleDouble(0),
            rr_count: 0,
            sum_hold_seconds: PostgresFlexibleDouble(0),
            hold_count: 0,
            largest_win: nil,
            largest_loss: nil
        )
        try await store.ingestCalendarDailyRange(
            viewerID: viewer,
            payload: AnalyticsDailyRangeBootstrapV1(
                revision: PostgresFlexibleDouble(3),
                state_updated_at: nil,
                start: "2026-09-01",
                end: "2026-09-30",
                account_id: nil,
                mode: nil,
                days: [day],
                summary: AnalyticsDailyRangeSummaryV1(
                    trade_count: 1,
                    win_count: 1,
                    loss_count: 0,
                    breakeven_count: 0,
                    net_pnl: PostgresFlexibleDouble(10),
                    gross_profit: PostgresFlexibleDouble(10),
                    gross_loss: PostgresFlexibleDouble(0)
                )
            ),
            scope: AnalyticsLocalStore.IngestScope(
                startDate: "2026-09-01",
                endDate: "2026-09-30",
                accountScope: AnalyticsScopeKeys.allAccountsQuery,
                modeScope: AnalyticsScopeKeys.allModesQuery
            )
        )
        let metrics = try await store.dashboardPresetMetrics(viewerID: viewer)
        let daily = try await store.dailyStats(
            viewerID: viewer,
            startDate: "2026-09-01",
            endDate: "2026-09-30",
            accountScope: AnalyticsScopeKeys.allAccountsQuery,
            modeScope: AnalyticsScopeKeys.allModesQuery
        )
        #expect(!metrics.isEmpty)
        #expect(daily.count == 1)
    }

    @Test("Codable chart round-trip")
    func chartRoundTrip() throws {
        let charts = sampleAccountCharts(accountID: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa").data.presets["d30"]!
        let record = try DashboardChartBundleRecord.from(
            charts: charts,
            viewerID: "v",
            accountScopeKey: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            revision: 1
        )
        let decoded = try record.decodedCharts()
        #expect(decoded.equity.points.count == charts.equity.points.count)
    }
}
