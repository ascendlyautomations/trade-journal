import Foundation
import Testing
@testable import TradeTraxs

@Suite(.serialized)
@MainActor
struct DashboardSlowNetworkReliabilityTests {
    private let viewerID = "22222222-2222-4222-8222-222222222222"

    @Test("Failed cold loads retry up to the cap, then stop until pull refresh")
    func failedColdLoadRetriesAreCapped() async throws {
        SessionViewerGate.shared.resetForTesting()
        DashboardHomeSurfaceGate.resetForTesting()
        BackendV2FeatureFlags.resetFlagsForTests()
        BackendV2FeatureFlags.setFlagForTests(.dashboard, enabled: true)
        BackendV2FeatureFlags.setFlagForTests(.dashboardAnalyticsV3, enabled: true)
        BackendV2FeatureFlags.setFlagForTests(.dashboardAnalyticsGRDB, enabled: false)
        DashboardAnalyticsDiskCache.clearAll()
        BackendV2BootstrapDiskCache.clearAll()
        defer {
            DashboardAnalyticsDiskCache.clearAll()
            BackendV2BootstrapDiskCache.clearAll()
            SessionViewerGate.shared.resetForTesting()
            DashboardHomeSurfaceGate.resetForTesting()
            BackendV2FeatureFlags.resetFlagsForTests()
        }

        await SessionNetworkGate.shared.markReady()
        let rpc = CountingFailingBootstrapRPCClient()
        let session = FixedSlowNetworkSession(userID: viewerID)
        SessionViewerGate.shared.bind(viewerID)
        let viewModel = DashboardViewModel(
            home: SlowNetworkHomeRepository(),
            trades: SlowNetworkTradeRepository(),
            achievements: SlowNetworkAchievementRepository(),
            dailyCheckIns: EmptyTraderDailyCheckInRepository(),
            session: session,
            detailCache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore()),
            rpc: rpc
        )

        var expectedAttempts = 0
        for _ in 0 ..< 3 {
            expectedAttempts += 1
            viewModel.loadIfNeeded()
            try await waitUntil(timeout: 4) { viewModel.coldLoadAttemptCount >= expectedAttempts }
        }
        #expect(viewModel.coldLoadAttemptCount == 3)
        #expect(viewModel.summary == nil)

        let callsBeforeBlockedRetry = rpc.bootstrapCallCount
        viewModel.loadIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(rpc.bootstrapCallCount == callsBeforeBlockedRetry)

        await viewModel.refresh()
        try await waitUntil(timeout: 4) { rpc.bootstrapCallCount > callsBeforeBlockedRetry }
    }

    @Test("Authoritative dashboard refresh defers while Home is off-screen")
    func authoritativeRefreshDefersUntilHomeIsActive() async throws {
        SessionViewerGate.shared.resetForTesting()
        DashboardHomeSurfaceGate.resetForTesting()
        BackendV2FeatureFlags.resetFlagsForTests()
        BackendV2FeatureFlags.setFlagForTests(.dashboard, enabled: true)
        BackendV2FeatureFlags.setFlagForTests(.dashboardAnalyticsV3, enabled: true)
        BackendV2FeatureFlags.setFlagForTests(.dashboardAnalyticsGRDB, enabled: false)
        DashboardAnalyticsDiskCache.clearAll()
        defer {
            DashboardAnalyticsDiskCache.clearAll()
            SessionViewerGate.shared.resetForTesting()
            DashboardHomeSurfaceGate.resetForTesting()
            BackendV2FeatureFlags.resetFlagsForTests()
        }

        let bootstrap = try makeBootstrap(viewerID: viewerID, revision: 1)
        DashboardAnalyticsDiskCache.save(
            DashboardAnalyticsDiskCache.Blob(
                viewerID: viewerID,
                contractVersion: BackendV2Versioning.contractVersion,
                schemaVersion: DashboardAnalyticsDiskCache.schemaVersion,
                revision: 99,
                savedAt: Date(),
                payload: bootstrap
            )
        )

        let rpc = CountingFailingBootstrapRPCClient()
        let session = FixedSlowNetworkSession(userID: viewerID)
        SessionViewerGate.shared.bind(viewerID)
        let viewModel = DashboardViewModel(
            home: SlowNetworkHomeRepository(),
            trades: SlowNetworkTradeRepository(),
            achievements: SlowNetworkAchievementRepository(),
            dailyCheckIns: EmptyTraderDailyCheckInRepository(),
            session: session,
            detailCache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore()),
            rpc: rpc
        )
        viewModel.setHomeTabActive(false)
        viewModel.loadIfNeeded()
        try await waitUntil(timeout: 4) { viewModel.summary != nil }
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(rpc.bootstrapCallCount == 0)

        viewModel.setHomeTabActive(true)
        try await waitUntil(timeout: 4) { rpc.bootstrapCallCount >= 1 }
    }

    @Test("Equity chart keeps last displayed points during overlay loading")
    func equityChartRetainsLastDisplayedPointsWhileOverlayLoading() async throws {
        SessionViewerGate.shared.resetForTesting()
        DashboardHomeSurfaceGate.resetForTesting()
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
            DashboardHomeSurfaceGate.resetForTesting()
            BackendV2FeatureFlags.resetFlagsForTests()
        }

        let bootstrap = try makeBootstrap(viewerID: viewerID, revision: 2)
        DashboardAnalyticsDiskCache.save(
            DashboardAnalyticsDiskCache.Blob(
                viewerID: viewerID,
                contractVersion: BackendV2Versioning.contractVersion,
                schemaVersion: DashboardAnalyticsDiskCache.schemaVersion,
                revision: 2,
                savedAt: Date(),
                payload: bootstrap
            )
        )

        let rpc = CountingFailingBootstrapRPCClient()
        let session = FixedSlowNetworkSession(userID: viewerID)
        SessionViewerGate.shared.bind(viewerID)
        let viewModel = DashboardViewModel(
            home: SlowNetworkHomeRepository(),
            trades: SlowNetworkTradeRepository(),
            achievements: SlowNetworkAchievementRepository(),
            dailyCheckIns: EmptyTraderDailyCheckInRepository(),
            session: session,
            detailCache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore()),
            rpc: rpc
        )
        viewModel.loadIfNeeded()
        try await waitUntil(timeout: 4) { viewModel.summary != nil }

        let seeded = viewModel.equityHeroChartPoints
        #expect(!seeded.isEmpty)
        #expect(!viewModel.lastDisplayedEquityHeroChartPoints.isEmpty)

        DashboardAnalyticsAggregateChartsStore.shared.markLoading(revision: 2)
        let duringOverlay = viewModel.equityHeroChartPoints
        #expect(!duringOverlay.isEmpty)
        #expect(duringOverlay.count == seeded.count)

        viewModel.setHomeTabActive(false)
        viewModel.setHomeTabActive(true)
        #expect(!viewModel.equityHeroChartPoints.isEmpty)
    }

    @Test("Home bootstrap RPCs prefer visible scheduling when Home tab is active")
    func homeScreenRaisesBootstrapPriority() {
        DashboardHomeSurfaceGate.resetForTesting()
        defer { DashboardHomeSurfaceGate.resetForTesting() }

        DashboardHomeSurfaceGate.setHomeTabActive(false)
        #expect(
            ActiveScreenBootstrapPriorityGate.prefersVisibleBootstrap(
                rpcName: BackendV2Versioning.RPCName.analyticsDashboardBootstrapV3.rawValue
            ) == false
        )

        DashboardHomeSurfaceGate.setHomeTabActive(true)
        #expect(
            ActiveScreenBootstrapPriorityGate.prefersVisibleBootstrap(
                rpcName: BackendV2Versioning.RPCName.analyticsDashboardBootstrapV3.rawValue
            )
        )
    }

    private func makeBootstrap(viewerID: String, revision: Int) throws -> AnalyticsDashboardBootstrapV3 {
        let json = """
        {
          "meta": {"contract_version":"v1","server_time":"2026-09-24T12:00:00.000Z","viewer_id":"\(viewerID)"},
          "data": {
            "revision": \(revision),
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
                },
                "equity": {
                  "points": [
                    {"t":"2026-09-01","v":1000},
                    {"t":"2026-09-02","v":1100}
                  ],
                  "max_drawdown": 0,
                  "current_equity": 1100
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

private final class CountingFailingBootstrapRPCClient: RPCClient, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var bootstrapCallCount = 0

    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        _ = functionName
        _ = parameters
        throw BackendV2RPCError.transport("slow-network-test")
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        _ = jsonBody
        if functionName == BackendV2Versioning.RPCName.analyticsDashboardBootstrapV3.rawValue
            || functionName == BackendV2Versioning.RPCName.dashboard.rawValue
        {
            lock.lock()
            bootstrapCallCount += 1
            lock.unlock()
        }
        throw BackendV2RPCError.transport("slow-network-test")
    }
}

private final class FixedSlowNetworkSession: SessionProviding, @unchecked Sendable {
    let userID: String
    init(userID: String) { self.userID = userID }
    var currentUserID: UserID? {
        get async { UserID(userID) }
    }
    var accessToken: String? { get async { "token" } }
}

private struct SlowNetworkHomeRepository: HomeRepository {
    func dashboard(for profileID: ProfileID) async throws -> HomeDashboard {
        throw AppError.notImplemented(feature: "slow-network.home")
    }
    func performance(for profileID: ProfileID, interval: DateIntervalValue) async throws -> PerformanceSummary {
        throw AppError.notImplemented(feature: "slow-network.home")
    }
}

private struct SlowNetworkAchievementRepository: AchievementRepository {
    func achievement(id: AchievementID) async throws -> Achievement {
        throw AppError.notImplemented(feature: "slow-network.achievements")
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

private struct SlowNetworkTradeRepository: TradeRepository {
    func trade(id: TradeID) async throws -> Trade {
        throw AppError.notImplemented(feature: "slow-network.trades")
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
        throw AppError.notImplemented(feature: "slow-network.trades")
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
