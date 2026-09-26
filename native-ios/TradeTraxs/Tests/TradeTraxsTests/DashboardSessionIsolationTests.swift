import Foundation
import Testing
@testable import TradeTraxs

@Suite(.serialized)
@MainActor
struct DashboardSessionIsolationTests {
    private let accountA = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private let accountB = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    private let accountANetPnL = Decimal(424242)

    @Test("Account B never renders Account A's cached dashboard, and A can reuse its own cache")
    func accountSwitchDoesNotEmitPreviousDashboard() async throws {
        SessionViewerGate.shared.resetForTesting()
        BackendV2FeatureFlags.resetFlagsForTests()
        BackendV2FeatureFlags.setFlagForTests(.dashboard, enabled: true)
        BackendV2FeatureFlags.setFlagForTests(.dashboardAnalyticsV3, enabled: true)
        BackendV2FeatureFlags.setFlagForTests(.dashboardAnalyticsGRDB, enabled: false)
        DashboardAnalyticsDiskCache.clearAll()
        SessionAccountsStore.shared.invalidate()
        defer {
            DashboardAnalyticsDiskCache.clearAll()
            SessionAccountsStore.shared.invalidate()
            DashboardAnalyticsAggregateChartsStore.shared.invalidate()
            DashboardAnalyticsAccountChartsStore.shared.invalidate()
            SessionViewerGate.shared.resetForTesting()
            BackendV2FeatureFlags.resetFlagsForTests()
        }

        let payload = try bootstrap(viewerID: accountA, netPnL: accountANetPnL)
        DashboardAnalyticsDiskCache.save(
            DashboardAnalyticsDiskCache.Blob(
                viewerID: accountA,
                contractVersion: BackendV2Versioning.contractVersion,
                schemaVersion: DashboardAnalyticsDiskCache.schemaVersion,
                revision: payload.data.revisionInt,
                savedAt: Date(),
                payload: payload
            )
        )

        let session = SwitchableDashboardSession(userID: accountA)
        SessionViewerGate.shared.bind(accountA)
        let viewModel = makeViewModel(session: session)
        viewModel.loadIfNeeded()
        try await waitUntil(timeout: 3) { viewModel.summary?.netPnL == accountANetPnL }
        #expect(viewModel.accounts.contains { $0.name == "Account A Eval" })

        DashboardSessionBoundary.resetInMemoryPresentation()
        #expect(viewModel.summary == nil)
        #expect(viewModel.accounts.isEmpty)
        #expect(DashboardAnalyticsDiskCache.load(viewerID: ProfileID(accountA)) != nil)

        session.userID = accountB
        SessionViewerGate.shared.bind(accountB)
        viewModel.loadIfNeeded()
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            #expect(viewModel.summary?.netPnL != accountANetPnL)
            #expect(viewModel.accounts.allSatisfy { $0.name != "Account A Eval" })
            if viewModel.phase == .loaded || isFailed(viewModel.phase) {
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(viewModel.summary?.netPnL != accountANetPnL)
        #expect(viewModel.accounts.allSatisfy { $0.name != "Account A Eval" })
        #expect(DashboardAnalyticsDiskCache.load(viewerID: ProfileID(accountB)) == nil)

        session.userID = accountA
        SessionViewerGate.shared.bind(accountA)
        viewModel.loadIfNeeded()
        try await waitUntil(timeout: 3) { viewModel.summary?.netPnL == accountANetPnL }
        #expect(viewModel.accounts.contains { $0.name == "Account A Eval" })
    }

    @Test("Disk load rejects a payload owned by a different viewer")
    func diskLoadRejectsMismatchedOwner() throws {
        DashboardAnalyticsDiskCache.clear(viewerID: ProfileID(accountA))
        defer { DashboardAnalyticsDiskCache.clear(viewerID: ProfileID(accountA)) }

        let payload = try bootstrap(viewerID: accountB, netPnL: accountANetPnL)
        DashboardAnalyticsDiskCache.save(
            DashboardAnalyticsDiskCache.Blob(
                viewerID: accountA,
                contractVersion: BackendV2Versioning.contractVersion,
                schemaVersion: DashboardAnalyticsDiskCache.schemaVersion,
                revision: 1,
                savedAt: Date(),
                payload: payload
            )
        )
        #expect(DashboardAnalyticsDiskCache.load(viewerID: ProfileID(accountA)) == nil)
        #expect(DashboardAnalyticsDiskCache.load(viewerID: ProfileID(accountB)) == nil)
    }

    @Test("Logout resets tour memory without erasing persisted dismissal")
    func logoutKeepsContextualTourDismissal() {
        let defaults = UserDefaults(suiteName: "DashboardSessionIsolationTests.tour")!
        defaults.removePersistentDomain(forName: "DashboardSessionIsolationTests.tour")
        defer { defaults.removePersistentDomain(forName: "DashboardSessionIsolationTests.tour") }

        let store = ContextualTourProgressStore(defaults: defaults)
        store.dismiss(.dashboard, version: 1, userID: accountA)
        ContextualTourCoordinator.shared.resetForSessionBoundary()
        SessionViewerGate.shared.endSession()
        defer { SessionViewerGate.shared.resetForTesting() }

        #expect(store.dismissedVersion(for: .dashboard, userID: accountA) == 1)
        #expect(defaults.data(forKey: ContextualTourProgressStore.storageKey(userID: accountA)) != nil)
    }

    private func makeViewModel(session: SwitchableDashboardSession) -> DashboardViewModel {
        DashboardViewModel(
            home: IsolationHomeRepository(),
            trades: IsolationTradeRepository(),
            achievements: IsolationAchievementRepository(),
            dailyCheckIns: EmptyTraderDailyCheckInRepository(),
            session: session,
            detailCache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore()),
            rpc: IsolationFailingRPCClient()
        )
    }

    private func bootstrap(viewerID: String, netPnL: Decimal) throws -> AnalyticsDashboardBootstrapV3 {
        let json = """
        {
          "meta": {"contract_version":"v1","server_time":"2026-09-24T12:00:00.000Z","viewer_id":"\(viewerID)"},
          "data": {
            "revision": 4,
            "as_of_et": "2026-09-24",
            "payout_total": 0,
            "accounts": [
              {"id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","name":"Account A Eval"}
            ],
            "presets": {
              "d30": {
                "preset":"d30","start":"2026-08-25","end":"2026-09-24",
                "metrics": {
                  "trade_count":11,"win_count":4,"loss_count":3,"breakeven_count":0,
                  "net_pnl":\(netPnL),"gross_profit":\(netPnL),"gross_loss":0,
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

    private func isFailed(_ phase: DashboardLoadPhase) -> Bool {
        if case .failed = phase { return true }
        return false
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

private final class SwitchableDashboardSession: SessionProviding, @unchecked Sendable {
    var userID: String?
    init(userID: String?) { self.userID = userID }
    var currentUserID: UserID? {
        get async {
            guard let userID else { return nil }
            return UserID(userID)
        }
    }
    var accessToken: String? { get async { "token" } }
}

private struct IsolationFailingRPCClient: RPCClient {
    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        throw BackendV2RPCError.transport("isolation")
    }
    func call(functionName: String, jsonBody: Data) async throws -> Data {
        throw BackendV2RPCError.transport("isolation")
    }
}

private struct IsolationHomeRepository: HomeRepository {
    func dashboard(for profileID: ProfileID) async throws -> HomeDashboard {
        throw AppError.notImplemented(feature: "isolation.home")
    }
    func performance(for profileID: ProfileID, interval: DateIntervalValue) async throws -> PerformanceSummary {
        throw AppError.notImplemented(feature: "isolation.home")
    }
}

private struct IsolationAchievementRepository: AchievementRepository {
    func achievement(id: AchievementID) async throws -> Achievement {
        throw AppError.notImplemented(feature: "isolation.achievements")
    }
    func achievements(
        for profileID: ProfileID,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Achievement> {
        CursorPage(items: [], nextCursor: nil)
    }
    func save(_ achievement: Achievement) async throws -> Achievement { achievement }
}

private struct IsolationTradeRepository: TradeRepository {
    func trade(id: TradeID) async throws -> Trade {
        throw AppError.notImplemented(feature: "isolation.trades")
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
        throw AppError.notImplemented(feature: "isolation.trades")
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
