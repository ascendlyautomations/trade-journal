import XCTest
@testable import TradeTraxs

private struct EquityCurveExplodingRPC: RPCClient {
    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        throw AppError.unknown(message: "equity overlay should already be resolved")
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        throw AppError.unknown(message: "equity overlay should already be resolved")
    }
}

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

    func testResolvedEmptyEquityChartsAreReady() {
        let empty = chartsWithEquity(pointCount: 0)
        let oneTrade = chartsWithEquity(pointCount: 1)
        XCTAssertTrue(DashboardAnalyticsChartsSupport.chartsReadyForPresentation(empty))
        XCTAssertTrue(DashboardAnalyticsChartsSupport.chartsReadyForPresentation(oneTrade))
        XCTAssertFalse(DashboardAnalyticsChartsSupport.chartsReadyForPresentation([:]))

        DashboardAnalyticsAccountChartsStore.shared.markLoaded(
            accountID: accountB,
            revision: revision,
            presets: empty
        )
        XCTAssertEqual(
            DashboardAnalyticsAccountChartsStore.shared.availability(accountID: accountB, revision: revision),
            .loaded
        )
    }

    func testAccountSwitchResolvedEmptyDoesNotStayLoading() async {
        DashboardAnalyticsAccountChartsStore.shared.markLoading(accountID: accountA, revision: revision)
        let empty = chartsWithEquity(pointCount: 0)
        DashboardAnalyticsAccountChartsStore.shared.markLoaded(
            accountID: accountB,
            revision: revision,
            presets: empty
        )
        DashboardAnalyticsAccountChartsStore.shared.markLoaded(
            accountID: accountA,
            revision: revision,
            presets: empty
        )

        let store = DashboardAnalyticsAccountChartsStore.shared
        XCTAssertEqual(store.availability(accountID: accountB, revision: revision), .loaded)
        XCTAssertTrue(DashboardAnalyticsChartsSupport.chartsReadyForPresentation(store.charts(accountID: accountB, revision: revision) ?? [:]))
        XCTAssertNotEqual(store.availability(accountID: accountB, revision: revision), .loading)

        let token = DashboardAnalyticsAccountChartsCoordinator.bumpSelection()
        let applied = await DashboardAnalyticsAccountChartsCoordinator.loadIfNeeded(
            selectedAccountID: accountB,
            selectionToken: token,
            revision: revision,
            viewerID: ProfileID("equity-viewer"),
            rpc: EquityCurveExplodingRPC()
        )
        XCTAssertTrue(applied)
        XCTAssertEqual(store.availability(accountID: accountB, revision: revision), .loaded)
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
