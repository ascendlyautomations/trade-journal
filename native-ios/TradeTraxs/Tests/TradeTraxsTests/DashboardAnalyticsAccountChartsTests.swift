import Foundation
import Testing
@testable import TradeTraxs

@MainActor
struct DashboardAnalyticsAccountChartsTests {
    private let v3Harness = DashboardAnalyticsV3Tests()

    @Test("Charts absent — KPI bundle uses metrics-only path")
    func metricsOnlyWhenChartsNotLoaded() throws {
        let bootstrap = try v3Harness.makeBootstrap()
        let accountA = TradingAccountID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        DashboardAnalyticsAccountChartsStore.shared.invalidate()

        let bundle = DashboardAnalyticsMapper.bundle(
            in: bootstrap,
            accountFilter: .account(accountA),
            dateRange: .thirtyDays,
            accountCharts: nil
        )
        #expect(bundle?.metrics.trade_count == 1)
        #expect(bundle?.equity.points.isEmpty == true)
    }

    @Test("Loaded charts merge without changing KPI metrics")
    func chartsMergePreservesKpis() throws {
        let bootstrap = try v3Harness.makeBootstrap()
        let accountA = TradingAccountID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        let charts = Self.sampleCharts(currentEquity: 500)
        DashboardAnalyticsAccountChartsStore.shared.markLoaded(
            accountID: accountA,
            revision: 3,
            presets: charts
        )

        let bundle = DashboardAnalyticsMapper.bundle(
            in: bootstrap,
            accountFilter: .account(accountA),
            dateRange: .thirtyDays,
            accountCharts: charts
        )
        #expect(bundle?.metrics.trade_count == 1)
        #expect(bundle?.equity.current_equity.value == 500)
    }

    @Test("Availability distinguishes not loaded vs loaded zero points")
    func zeroPointsWhenLoaded() {
        DashboardAnalyticsAccountChartsStore.shared.invalidate()
        let account = TradingAccountID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
        #expect(
            DashboardAnalyticsAccountChartsStore.shared.availability(
                accountID: account,
                revision: 1
            ) == .notRequested
        )
        DashboardAnalyticsAccountChartsStore.shared.markLoaded(
            accountID: account,
            revision: 1,
            presets: Self.sampleCharts(currentEquity: 0, points: [])
        )
        #expect(
            DashboardAnalyticsAccountChartsStore.shared.availability(
                accountID: account,
                revision: 1
            ) == .loaded
        )
    }

    @Test("Preset switch uses cached chart bundle without new fetch key")
    func presetSwitchUsesCachedPresets() throws {
        let bootstrap = try v3Harness.makeBootstrap()
        let account = TradingAccountID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
        let charts: [String: AnalyticsDashboardChartsPresetV1] = [
            "d30": Self.sampleCharts(currentEquity: 10)["d30"]!,
            "d90": AnalyticsDashboardChartsPresetV1(
                preset: "d90",
                start: "2026-06-23",
                end: "2026-09-21",
                equity: AnalyticsDashboardEquityWireV1(
                    points: [],
                    max_drawdown: PostgresFlexibleDouble(5),
                    current_equity: PostgresFlexibleDouble(90)
                ),
                distributions: Self.emptyDistributions,
                insights: []
            ),
        ]
        DashboardAnalyticsAccountChartsStore.shared.markLoaded(
            accountID: account,
            revision: 3,
            presets: charts
        )
        let d30 = DashboardAnalyticsMapper.bundle(
            in: bootstrap,
            accountFilter: .account(account),
            dateRange: .thirtyDays,
            accountCharts: charts
        )
        let d90 = DashboardAnalyticsMapper.bundle(
            in: bootstrap,
            accountFilter: .account(account),
            dateRange: .ninetyDays,
            accountCharts: charts
        )
        #expect(d30?.equity.current_equity.value == 10)
        #expect(d90?.equity.current_equity.value == 90)
        #expect(d30?.metrics.trade_count == 7)
        #expect(d90?.metrics.trade_count == 7)
    }

    @Test("Cached charts reused for same account and revision")
    func cacheReuseOnReturn() {
        DashboardAnalyticsAccountChartsStore.shared.invalidate()
        let account = TradingAccountID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        let presets = Self.sampleCharts(currentEquity: 42)
        DashboardAnalyticsAccountChartsStore.shared.markLoaded(
            accountID: account,
            revision: 3,
            presets: presets
        )
        #expect(
            DashboardAnalyticsAccountChartsStore.shared.charts(
                accountID: account,
                revision: 3
            )?["d30"]?.equity.current_equity.value == 42
        )
        #expect(
            DashboardAnalyticsAccountChartsStore.shared.availability(
                accountID: account,
                revision: 3
            ).isLoaded
        )
    }

    @Test("Selection token bumps invalidate stale apply")
    func selectionTokenBump() {
        let first = DashboardAnalyticsAccountChartsCoordinator.bumpSelection()
        let second = DashboardAnalyticsAccountChartsCoordinator.bumpSelection()
        #expect(second > first)
    }

    #if DEBUG
    @Test("Parity skips chart metrics before charts load")
    func paritySkipsChartMetricsWhenLoading() throws {
        let bootstrap = try v3Harness.makeBootstrap()
        let account = TradingAccountID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        guard let bundle = DashboardAnalyticsMapper.bundle(
            in: bootstrap,
            accountFilter: .account(account),
            dateRange: .thirtyDays,
            accountCharts: nil
        ) else {
            Issue.record("Expected metrics-only bundle")
            return
        }
        var v3Summary = DashboardAnalyticsMapper.summary(from: bundle, payoutTotal: nil)
        var legacySummary = v3Summary
        legacySummary.currentEquity = 2150
        legacySummary.maxDrawdown = 36.5

        let whileLoading = DashboardAnalyticsV3Parity.compare(
            legacy: legacySummary,
            v3: v3Summary,
            preset: .thirtyDays,
            account: .account(account),
            historyComplete: false,
            v3Lookup: .account(bundle, metricsSource: .accountPresetMetrics),
            chartsAvailability: .loading
        )
        #expect(whileLoading.contains { $0.field == "current_equity" } == false)
        #expect(whileLoading.contains { $0.field == "max_drawdown" } == false)

        v3Summary.currentEquity = 2150
        v3Summary.maxDrawdown = 36.5
        let afterLoad = DashboardAnalyticsV3Parity.compare(
            legacy: legacySummary,
            v3: v3Summary,
            preset: .thirtyDays,
            account: .account(account),
            historyComplete: false,
            v3Lookup: .account(bundle, metricsSource: .accountPresetMetrics),
            chartsAvailability: .loaded
        )
        #expect(afterLoad.contains { $0.field == "current_equity" } == false)
        #expect(afterLoad.contains { $0.field == "max_drawdown" } == false)
    }
    #endif

    private static let emptyDistributions = AnalyticsDashboardDistributionsWireV1(
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
    )

    private static func sampleCharts(
        currentEquity: Double,
        points: [AnalyticsDashboardEquityPointWireV1]? = nil
    ) -> [String: AnalyticsDashboardChartsPresetV1] {
        let equityPoints = points ?? [
            AnalyticsDashboardEquityPointWireV1(
                t: "2026-09-01T15:00:00.000Z",
                v: PostgresFlexibleDouble(currentEquity),
                i: 0
            ),
        ]
        return [
            "d30": AnalyticsDashboardChartsPresetV1(
                preset: "d30",
                start: "2026-08-23",
                end: "2026-09-21",
                equity: AnalyticsDashboardEquityWireV1(
                    points: equityPoints,
                    max_drawdown: PostgresFlexibleDouble(0),
                    current_equity: PostgresFlexibleDouble(currentEquity)
                ),
                distributions: emptyDistributions,
                insights: []
            ),
        ]
    }
}
