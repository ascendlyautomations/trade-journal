import Foundation
import Testing
@testable import TradeTraxs

@Suite(.serialized)
@MainActor
struct DashboardChartOverlayLoopTests {
    private let viewerID = "11111111-1111-4111-8111-111111111111"

    @Test("Offscreen Dashboard does not call aggregate charts RPC")
    func offscreenSkipsAggregateChartsRPC() async throws {
        try await runOverlayFetchScenario(homeTabActive: false, ensurePasses: 5) { count in
            #expect(count == 0)
        }
    }

    @Test("Repeated overlay ensure does not loop aggregate charts RPC")
    func settledSelectionPreventsRepeatedAggregateRPC() async throws {
        try await runOverlayFetchScenario(homeTabActive: true, ensurePasses: 8) { count in
            #expect(count <= 2, "Expected one fetch (+ optional single retry), got \(count)")
        }
    }

    private func runOverlayFetchScenario(
        homeTabActive: Bool,
        ensurePasses: Int,
        assertCount: (Int) -> Void
    ) async throws {
        SessionViewerGate.shared.resetForTesting()
        BackendV2FeatureFlags.resetFlagsForTests()
        BackendV2FeatureFlags.setFlagForTests(.dashboard, enabled: true)
        BackendV2FeatureFlags.setFlagForTests(.dashboardAnalyticsV3, enabled: true)
        BackendV2FeatureFlags.setFlagForTests(.dashboardAnalyticsGRDB, enabled: false)
        DashboardAnalyticsDiskCache.clearAll()
        DashboardAnalyticsAggregateChartsStore.shared.invalidate()
        defer {
            DashboardAnalyticsDiskCache.clearAll()
            DashboardAnalyticsAggregateChartsStore.shared.invalidate()
            SessionViewerGate.shared.resetForTesting()
            BackendV2FeatureFlags.resetFlagsForTests()
        }

        let bootstrap = try makeBootstrap(viewerID: viewerID)
        DashboardAnalyticsDiskCache.save(
            DashboardAnalyticsDiskCache.Blob(
                viewerID: viewerID,
                contractVersion: BackendV2Versioning.contractVersion,
                schemaVersion: DashboardAnalyticsDiskCache.schemaVersion,
                revision: bootstrap.data.revisionInt,
                savedAt: Date(),
                payload: bootstrap
            )
        )

        let rpc = CountingAggregateChartsRPCClient()
        let session = FixedDashboardSession(userID: viewerID)
        SessionViewerGate.shared.bind(viewerID)
        let viewModel = DashboardViewModel(
            home: LoopTestHomeRepository(),
            trades: LoopTestTradeRepository(),
            achievements: LoopTestAchievementRepository(),
            dailyCheckIns: EmptyTraderDailyCheckInRepository(),
            session: session,
            detailCache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore()),
            rpc: rpc
        )
        viewModel.setHomeTabActive(homeTabActive)
        viewModel.loadIfNeeded()
        try await waitUntil(timeout: 4) { viewModel.summary != nil }
        try await Task.sleep(nanoseconds: 800_000_000)

        for _ in 0 ..< ensurePasses {
            viewModel.ensureEquityChartOverlayIfNeeded()
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try await Task.sleep(nanoseconds: 400_000_000)

        assertCount(rpc.aggregateChartsCallCount)
    }

    private func makeBootstrap(viewerID: String) throws -> AnalyticsDashboardBootstrapV3 {
        let json = """
        {
          "meta": {"contract_version":"v1","server_time":"2026-09-24T12:00:00.000Z","viewer_id":"\(viewerID)"},
          "data": {
            "revision": 0,
            "as_of_et": "2026-09-24",
            "payout_total": 0,
            "accounts": [],
            "presets": {
              "all": {
                "preset":"all","start":"2020-01-01","end":"2026-09-24",
                "metrics": {
                  "trade_count":5,"win_count":2,"loss_count":1,"breakeven_count":0,
                  "net_pnl":100,"gross_profit":100,"gross_loss":0,
                  "long_count":0,"long_pnl":0,"short_count":0,"short_pnl":0,
                  "sum_rr":0,"rr_count":0,"sum_hold_seconds":0,"hold_count":0,
                  "largest_win":null,"largest_loss":null
                }
              }
            }
          }
        }
        """
        return try JSONDecoder().decode(AnalyticsDashboardBootstrapV3.self, from: Data(json.utf8))
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async throws {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                Issue.record("Timed out waiting for dashboard condition")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

private final class CountingAggregateChartsRPCClient: RPCClient, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var aggregateChartsCallCount = 0

    private let chartsJSON = """
    {
      "meta": {"contract_version":"v1","server_time":"2026-09-24T12:00:00.000Z","viewer_id":"11111111-1111-4111-8111-111111111111"},
      "data": {
        "presets": {
          "all": {
            "preset":"all","start":"2020-01-01","end":"2026-09-24",
            "equity": {"points":[],"max_drawdown":0,"current_equity":0},
            "distributions": {"sessions":[],"hours":[],"weekdays":[],"long_short":[]},
            "insights": []
          }
        }
      }
    }
    """

    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        _ = functionName
        _ = parameters
        throw AppError.notImplemented(feature: "parameters")
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        _ = jsonBody
        if functionName == BackendV2Versioning.RPCName.analyticsDashboardAggregateChartsV3.rawValue {
            lock.lock()
            aggregateChartsCallCount += 1
            lock.unlock()
            return Data(chartsJSON.utf8)
        }
        throw AppError.notImplemented(feature: functionName)
    }
}

private final class FixedDashboardSession: SessionProviding, @unchecked Sendable {
    let userID: String
    init(userID: String) { self.userID = userID }
    var currentUserID: UserID? {
        get async { UserID(userID) }
    }
    var accessToken: String? { get async { "token" } }
}

private struct LoopTestHomeRepository: HomeRepository {
    func dashboard(for profileID: ProfileID) async throws -> HomeDashboard {
        throw AppError.notImplemented(feature: "loop.home")
    }
    func performance(for profileID: ProfileID, interval: DateIntervalValue) async throws -> PerformanceSummary {
        throw AppError.notImplemented(feature: "loop.home")
    }
}

private struct LoopTestAchievementRepository: AchievementRepository {
    func achievement(id: AchievementID) async throws -> Achievement {
        throw AppError.notImplemented(feature: "loop.achievements")
    }
    func achievements(
        for profileID: ProfileID,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Achievement> {
        CursorPage(items: [], nextCursor: nil)
    }
    func save(_ achievement: Achievement, metadata: JSONValue?) async throws -> Achievement { achievement }
    func withdrawalAchievementLinks(for profileID: ProfileID) async throws -> [WithdrawalAchievementLinkRow] {
        []
    }
}

private struct LoopTestTradeRepository: TradeRepository {
    func trade(id: TradeID) async throws -> Trade {
        throw AppError.notImplemented(feature: "loop.trades")
    }
    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Trade> {
        CursorPage(items: [], nextCursor: nil)
    }
    func save(_ draft: TradeDraft) async throws -> Trade {
        throw AppError.notImplemented(feature: "loop.trades")
    }
    func update(_ trade: Trade) async throws -> Trade { trade }
    func delete(id: TradeID) async throws {}
    func images(for tradeID: TradeID) async throws -> [TradeImage] { [] }
    func notes(for tradeID: TradeID) async throws -> [TradeNote] { [] }
    func statistics(for profileID: ProfileID, interval: DateIntervalValue) async throws -> TradeStatistics {
        TradeStatistics(
            tradeCount: 0,
            winCount: 0,
            lossCount: 0,
            totalPnL: Money(amount: 0),
            averagePnL: Money(amount: 0),
            averageRiskReward: nil,
            winRate: 0
        )
    }
    func accounts(for profileID: ProfileID) async throws -> [TradingAccount] { [] }
}
