import Foundation
import Testing
@testable import TradeTraxs

struct AnalyticsShadowReadTests {
    private func makeStore() throws -> (URL, AnalyticsLocalStore) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("analytics-shadow-read-\(UUID().uuidString).sqlite")
        let db = AnalyticsDatabase(configuration: .testing(databaseURL: url))
        let store = AnalyticsLocalStore(database: db)
        return (url, store)
    }

    private func coverage(
        viewer: String,
        domain: String,
        accountScope: String,
        modeScope: String,
        start: String,
        end: String,
        revision: Int64
    ) -> AnalyticsRangeCoverageRecord {
        AnalyticsRangeCoverageRecord(
            viewer_id: viewer,
            domain: domain,
            account_scope: accountScope,
            mode_scope: modeScope,
            start_date: start,
            end_date: end,
            server_revision: revision,
            fetched_at: ISO8601DateFormatter().string(from: Date())
        )
    }

    // MARK: - Coverage union

    @Test("Adjacent intervals fully cover month")
    func adjacentCoverage() {
        let segments = [
            AnalyticsCalendarCoverageValidator.Segment(start: "2026-09-01", end: "2026-09-15", serverRevision: 20),
            AnalyticsCalendarCoverageValidator.Segment(start: "2026-09-16", end: "2026-09-30", serverRevision: 20),
        ]
        let state = AnalyticsCalendarCoverageValidator.evaluate(
            requestStart: "2026-09-01",
            requestEnd: "2026-09-30",
            requiredRevision: 20,
            segments: segments
        )
        #expect(state == .available)
    }

    @Test("Overlapping intervals fully cover month")
    func overlappingCoverage() {
        let segments = [
            AnalyticsCalendarCoverageValidator.Segment(start: "2026-09-01", end: "2026-09-20", serverRevision: 20),
            AnalyticsCalendarCoverageValidator.Segment(start: "2026-09-10", end: "2026-09-30", serverRevision: 20),
        ]
        let state = AnalyticsCalendarCoverageValidator.evaluate(
            requestStart: "2026-09-01",
            requestEnd: "2026-09-30",
            requiredRevision: 20,
            segments: segments
        )
        #expect(state == .available)
    }

    @Test("One-day gap yields partial")
    func gapCoverage() {
        let segments = [
            AnalyticsCalendarCoverageValidator.Segment(start: "2026-09-01", end: "2026-09-14", serverRevision: 20),
            AnalyticsCalendarCoverageValidator.Segment(start: "2026-09-16", end: "2026-09-30", serverRevision: 20),
        ]
        let state = AnalyticsCalendarCoverageValidator.evaluate(
            requestStart: "2026-09-01",
            requestEnd: "2026-09-30",
            requiredRevision: 20,
            segments: segments
        )
        #expect(state == .partial)
    }

    @Test("Mixed revision cannot satisfy required revision")
    func mixedRevisionCoverage() {
        let segments = [
            AnalyticsCalendarCoverageValidator.Segment(start: "2026-09-01", end: "2026-09-30", serverRevision: 20),
        ]
        let state = AnalyticsCalendarCoverageValidator.evaluate(
            requestStart: "2026-09-01",
            requestEnd: "2026-09-30",
            requiredRevision: 21,
            segments: segments
        )
        #expect(state == .stale(foundRevision: 20))
    }

    @Test("Partial month coverage for wider request")
    func partialWiderRange() {
        let segments = [
            AnalyticsCalendarCoverageValidator.Segment(start: "2026-09-01", end: "2026-09-30", serverRevision: 20),
        ]
        let state = AnalyticsCalendarCoverageValidator.evaluate(
            requestStart: "2026-08-01",
            requestEnd: "2026-09-30",
            requiredRevision: 20,
            segments: segments
        )
        #expect(state == .partial)
    }

    @Test("Zero-row covered calendar range is available")
    func zeroRowCoveredRange() async throws {
        let (url, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("viewer-zero")
        let payload = AnalyticsDailyRangeBootstrapV1(
            revision: PostgresFlexibleDouble(7),
            state_updated_at: "2026-09-21T12:00:00.000Z",
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
        let scope = AnalyticsLocalStore.IngestScope(
            startDate: "2026-09-01",
            endDate: "2026-09-30",
            accountScope: AnalyticsScopeKeys.allAccountsQuery,
            modeScope: AnalyticsScopeKeys.allModesQuery
        )
        try await store.ingestCalendarDailyRange(viewerID: viewer, payload: payload, scope: scope)
        let read = try await store.readCalendarRange(
            viewerID: viewer,
            startDate: "2026-09-01",
            endDate: "2026-09-30",
            queryAccountID: nil,
            queryMode: nil,
            requiredRevision: 7
        )
        #expect(read.state == .available)
        #expect(read.dailyRows.isEmpty)
    }

    @Test("Calendar typed reconstruction matches aggregator")
    func calendarReconstruction() async throws {
        let (url, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("viewer-recon")
        let day = AnalyticsDailyStatRowV1(
            calendar_day: "2026-09-10",
            account_id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            mode_effective: "live",
            trade_count: 2,
            win_count: 1,
            loss_count: 1,
            breakeven_count: 0,
            net_pnl: PostgresFlexibleDouble(50),
            gross_profit: PostgresFlexibleDouble(100),
            gross_loss: PostgresFlexibleDouble(50),
            long_count: 1,
            long_pnl: PostgresFlexibleDouble(50),
            short_count: 1,
            short_pnl: PostgresFlexibleDouble(0),
            sum_rr: PostgresFlexibleDouble(1),
            rr_count: 2,
            sum_hold_seconds: PostgresFlexibleDouble(3600),
            hold_count: 2,
            largest_win: PostgresFlexibleDouble(100),
            largest_loss: PostgresFlexibleDouble(50)
        )
        let payload = AnalyticsDailyRangeBootstrapV1(
            revision: PostgresFlexibleDouble(3),
            state_updated_at: "2026-09-21T12:00:00.000Z",
            start: "2026-09-01",
            end: "2026-09-30",
            account_id: nil,
            mode: nil,
            days: [day],
            summary: AnalyticsDailyRangeSummaryV1(
                trade_count: 2,
                win_count: 1,
                loss_count: 1,
                breakeven_count: 0,
                net_pnl: PostgresFlexibleDouble(50),
                gross_profit: PostgresFlexibleDouble(100),
                gross_loss: PostgresFlexibleDouble(50)
            )
        )
        let scope = AnalyticsLocalStore.IngestScope(
            startDate: "2026-09-01",
            endDate: "2026-09-30",
            accountScope: AnalyticsScopeKeys.allAccountsQuery,
            modeScope: AnalyticsScopeKeys.allModesQuery
        )
        try await store.ingestCalendarDailyRange(viewerID: viewer, payload: payload, scope: scope)
        let read = try await store.readCalendarRange(
            viewerID: viewer,
            startDate: "2026-09-01",
            endDate: "2026-09-30",
            queryAccountID: nil,
            queryMode: nil,
            requiredRevision: 3
        )
        #expect(read.state == .available)
        let fromGRDB = CalendarAnalyticsAggregator.buildMonth(
            year: 2026,
            month: 9,
            rows: read.wireRows,
            accountFilter: .all,
            modeFilter: nil
        )
        let fromRPC = CalendarAnalyticsAggregator.buildMonth(
            year: 2026,
            month: 9,
            rows: payload.days,
            accountFilter: .all,
            modeFilter: nil
        )
        #expect(fromGRDB.monthSummary.tradeCount == fromRPC.monthSummary.tradeCount)
        #expect(fromGRDB.days.count == fromRPC.days.count)
    }

    @Test("Incomplete dashboard snapshot is partial")
    func dashboardSnapshotIncomplete() async throws {
        let (url, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("dash-read")
        let bootstrap = try DashboardAnalyticsV3Tests().makeBootstrap()
        _ = try await store.ingestDashboardBootstrap(viewerID: viewer, bootstrap: bootstrap)
        let revision = bootstrap.data.revisionInt
        let read = try await store.readDashboardSnapshot(viewerID: viewer, requiredRevision: revision)
        #expect(read.state == .partial)
        #expect(read.snapshot == nil)
    }

    @Test("Dashboard complete snapshot reconstruction")
    func dashboardSnapshotComplete() async throws {
        let (url, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("dash-read-full")
        var bootstrap = try DashboardAnalyticsV3Tests().makeBootstrap()
        bootstrap.data.presets = fullAggregatePresets(from: bootstrap)
        _ = try await store.ingestDashboardBootstrap(viewerID: viewer, bootstrap: bootstrap)
        let revision = bootstrap.data.revisionInt
        let read = try await store.readDashboardSnapshot(viewerID: viewer, requiredRevision: revision)
        #expect(read.state == .available)
        #expect(read.snapshot?.aggregatePresets.count == AnalyticsLocalDashboardPolicy.aggregatePresetKeys.count)
    }

    @Test("Account chart stale revision is not available")
    func accountChartStaleRevision() async throws {
        let (url, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("acct-stale")
        let account = TradingAccountID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        let charts = makeAccountCharts(accountID: account.rawValue, emptyEquity: false)
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

    @Test("Legitimate empty account chart at required revision")
    func emptyAccountChartAvailable() async throws {
        let (url, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("acct-empty")
        let account = TradingAccountID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        let charts = makeAccountCharts(accountID: account.rawValue, emptyEquity: true)
        _ = try await store.ingestDashboardAccountCharts(
            viewerID: viewer,
            response: charts,
            accountID: account,
            knownRevision: 12
        )
        let read = try await store.readDashboardAccountCharts(
            viewerID: viewer,
            accountID: account,
            requiredRevision: 12
        )
        #expect(read.state == .available)
        #expect(read.presets["d30"]?.equity.points.isEmpty == true)
    }

    @Test("Viewer isolation on read APIs")
    func viewerIsolation() async throws {
        let (url, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewerA = ProfileID("viewer-a-read")
        let viewerB = ProfileID("viewer-b-read")
        let payload = AnalyticsDailyRangeBootstrapV1(
            revision: PostgresFlexibleDouble(1),
            state_updated_at: "2026-09-21T12:00:00.000Z",
            start: "2026-09-01",
            end: "2026-09-30",
            account_id: nil,
            mode: nil,
            days: [
                AnalyticsDailyStatRowV1(
                    calendar_day: "2026-09-01",
                    account_id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
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
                    largest_win: PostgresFlexibleDouble(10),
                    largest_loss: nil
                ),
            ],
            summary: AnalyticsDailyRangeSummaryV1(
                trade_count: 1,
                win_count: 1,
                loss_count: 0,
                breakeven_count: 0,
                net_pnl: PostgresFlexibleDouble(10),
                gross_profit: PostgresFlexibleDouble(10),
                gross_loss: PostgresFlexibleDouble(0)
            )
        )
        let scope = AnalyticsLocalStore.IngestScope(
            startDate: "2026-09-01",
            endDate: "2026-09-30",
            accountScope: AnalyticsScopeKeys.allAccountsQuery,
            modeScope: AnalyticsScopeKeys.allModesQuery
        )
        try await store.ingestCalendarDailyRange(viewerID: viewerA, payload: payload, scope: scope)
        let readB = try await store.readCalendarRange(
            viewerID: viewerB,
            startDate: "2026-09-01",
            endDate: "2026-09-30",
            queryAccountID: nil,
            queryMode: nil,
            requiredRevision: 1
        )
        #expect(readB.state == .missing)
    }

    @Test("DB reopen then shadow read")
    func reopenShadowRead() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("analytics-reopen-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("reopen-viewer")
        let db1 = AnalyticsDatabase(configuration: .testing(databaseURL: url))
        let store1 = AnalyticsLocalStore(database: db1)
        var bootstrap = try DashboardAnalyticsV3Tests().makeBootstrap()
        bootstrap.data.revision = PostgresFlexibleDouble(99)
        _ = try await store1.ingestDashboardBootstrap(viewerID: viewer, bootstrap: bootstrap)
        await db1.resetForTests()

        let db2 = AnalyticsDatabase(configuration: .testing(databaseURL: url))
        let store2 = AnalyticsLocalStore(database: db2)
        let read = try await store2.readDashboardSnapshot(viewerID: viewer, requiredRevision: 99)
        #expect(read.state == .partial)
    }
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

private func makeAccountCharts(accountID: String, emptyEquity: Bool) -> AnalyticsDashboardAccountChartsV3 {
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
