import XCTest
@testable import TradeTraxs

@MainActor
final class DashboardAccountChartSelectionTests: XCTestCase {
    private let accountA = TradingAccountID("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
    private let accountB = TradingAccountID("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
    private let revision: Int64 = 7

    override func setUp() {
        super.setUp()
        DashboardAnalyticsAccountChartsStore.shared.invalidate()
    }

    override func tearDown() {
        DashboardAnalyticsAccountChartsStore.shared.invalidate()
        super.tearDown()
    }

    func testAccountSwitchBumpsSelectionToken() {
        let tokenA = DashboardAnalyticsAccountChartsCoordinator.bumpSelection()
        let tokenB = DashboardAnalyticsAccountChartsCoordinator.bumpSelection()
        XCTAssertNotEqual(tokenA, tokenB)
        XCTAssertEqual(
            DashboardAnalyticsAccountChartsCoordinator.currentSelectionToken(),
            tokenB
        )
    }

    func testNonEmptyCacheNotOverwrittenByEmptyLoad() {
        DashboardAnalyticsAccountChartsStore.shared.markLoaded(
            accountID: accountA,
            revision: revision,
            presets: chartsWithEquity(pointCount: 3)
        )

        DashboardAnalyticsAccountChartsStore.shared.markLoaded(
            accountID: accountA,
            revision: revision,
            presets: chartsWithEquity(pointCount: 0)
        )

        let cached = DashboardAnalyticsAccountChartsStore.shared.charts(
            accountID: accountA,
            revision: revision
        )
        XCTAssertTrue(DashboardAnalyticsChartsSupport.hasEquityPoints(cached ?? [:]))
    }

    func testPerAccountCacheKeysDoNotCollide() {
        DashboardAnalyticsAccountChartsStore.shared.markLoaded(
            accountID: accountA,
            revision: revision,
            presets: chartsWithEquity(pointCount: 2)
        )
        DashboardAnalyticsAccountChartsStore.shared.markLoaded(
            accountID: accountB,
            revision: revision,
            presets: chartsWithEquity(pointCount: 4)
        )

        let a = DashboardAnalyticsAccountChartsStore.shared.charts(accountID: accountA, revision: revision)
        let b = DashboardAnalyticsAccountChartsStore.shared.charts(accountID: accountB, revision: revision)
        XCTAssertEqual(equityPointCount(a), 2)
        XCTAssertEqual(equityPointCount(b), 4)
    }

    // MARK: - Helpers

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

    private func equityPointCount(_ presets: [String: AnalyticsDashboardChartsPresetV1]?) -> Int {
        presets?["all"]?.equity.points.count ?? 0
    }

    private func chartsWithEquity(pointCount: Int) -> [String: AnalyticsDashboardChartsPresetV1] {
        let points = (0..<pointCount).map { index in
            AnalyticsDashboardEquityPointWireV1(
                t: "2026-01-\(String(format: "%02d", index + 1))T12:00:00.000Z",
                v: PostgresFlexibleDouble(Double(index + 1) * 100),
                i: index
            )
        }
        let preset = AnalyticsDashboardChartsPresetV1(
            preset: "all",
            start: "2026-01-01",
            end: "2026-12-31",
            equity: AnalyticsDashboardEquityWireV1(
                points: points,
                max_drawdown: PostgresFlexibleDouble(0),
                current_equity: PostgresFlexibleDouble(Double(pointCount) * 100)
            ),
            distributions: Self.emptyDistributions,
            insights: []
        )
        return ["all": preset]
    }
}
