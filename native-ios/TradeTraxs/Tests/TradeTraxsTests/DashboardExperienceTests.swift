import XCTest
@testable import TradeTraxs

@MainActor
final class DashboardExperienceTests: XCTestCase {
    func testChartMetricsExcludeBacktestAndHonorDateRange() {
        let profileID = ProfileID("dev.dashboard")
        let now = Date()
        let live = ProfileTradeFixtures.samples(owner: profileID)[0]
        let old = Trade(
            id: TradeID("old"),
            ownerProfileID: profileID,
            accountID: TradingAccountID("dev-account"),
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 1,
            exitPrice: 2,
            entryAt: now.addingTimeInterval(-120 * 86_400),
            exitAt: now.addingTimeInterval(-120 * 86_400 + 3_600),
            realizedPnL: Money(amount: 100),
            riskReward: 1,
            points: nil,
            sessionLabel: "London",
            visibility: .public,
            publicCaption: nil,
            thumbnail: nil,
            notePreview: nil,
            createdAt: now.addingTimeInterval(-120 * 86_400),
            updatedAt: now.addingTimeInterval(-120 * 86_400)
        )
        var backtest = live
        backtest.id = TradeID("bt")
        backtest.mode = .backtest
        backtest.realizedPnL = Money(amount: 9_999)

        let inputs = [live, old, backtest].map {
            DashboardChartMetrics.Input(trade: $0, accountType: "eval")
        }
        let summary = DashboardChartMetrics.compute(
            from: inputs,
            accountFilter: .all,
            dateRange: .thirtyDays,
            payoutTotal: 500,
            now: now
        )

        XCTAssertEqual(summary.tradeCount, 1, "Only recent non-backtest trade in 30D")
        XCTAssertEqual(summary.payouts, 500)
        XCTAssertFalse(summary.equityData.isEmpty)
        XCTAssertEqual(summary.winLoss.map(\.count).reduce(0, +), 1)
    }

    func testMaxDrawdownMatchesPeakToTrough() {
        let profileID = ProfileID("dev.dashboard")
        let now = Date()
        func trade(_ id: String, pnl: Decimal, dayOffset: Int) -> Trade {
            Trade(
                id: TradeID(id),
                ownerProfileID: profileID,
                accountID: nil,
                symbol: Symbol(ticker: "NQ"),
                side: .long,
                mode: .live,
                quantity: 1,
                entryPrice: 1,
                exitPrice: 1,
                entryAt: now.addingTimeInterval(TimeInterval(dayOffset * 86_400)),
                exitAt: now.addingTimeInterval(TimeInterval(dayOffset * 86_400 + 60)),
                realizedPnL: Money(amount: pnl),
                riskReward: nil,
                points: nil,
                sessionLabel: "NY",
                visibility: .private,
                publicCaption: nil,
                thumbnail: nil,
                notePreview: nil,
                createdAt: now.addingTimeInterval(TimeInterval(dayOffset * 86_400)),
                updatedAt: now.addingTimeInterval(TimeInterval(dayOffset * 86_400))
            )
        }
        // +100 → peak 100; -40 → equity 60; drawdown 40; +10 → 70
        let inputs = [
            trade("a", pnl: 100, dayOffset: -3),
            trade("b", pnl: -40, dayOffset: -2),
            trade("c", pnl: 10, dayOffset: -1),
        ].map { DashboardChartMetrics.Input(trade: $0, accountType: nil) }

        let summary = DashboardChartMetrics.compute(
            from: inputs,
            accountFilter: .all,
            dateRange: .all,
            payoutTotal: nil,
            now: now
        )
        XCTAssertEqual(summary.maxDrawdown, 40)
        XCTAssertEqual(summary.currentEquity, 70)
    }

    func testViewModelLoadsFixturesAndFiltersLocally() async {
        let cache = DetailPresentationCache()
        let navigationStore = NavigationStore()
        let coordinator = NavigationCoordinator(store: navigationStore)
        let viewModel = DashboardViewModel(
            home: DashboardStubHomeRepository(),
            trades: DashboardStubTradeRepository(),
            achievements: DashboardStubAchievementRepository(),
            session: DashboardStubSession(userID: "dev.dashboard.user"),
            detailCache: cache,
            navigationCoordinator: coordinator
        )

        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }

        XCTAssertNotNil(viewModel.summary)
        XCTAssertFalse(viewModel.metricChips.isEmpty)
        XCTAssertFalse(viewModel.recentTrades.isEmpty)

        let before = viewModel.summary?.tradeCount
        viewModel.setDateRange(.sevenDays)
        XCTAssertEqual(viewModel.phase, .loaded)
        // Filter is local — still loaded, count may shrink.
        XCTAssertLessThanOrEqual(viewModel.summary?.tradeCount ?? 0, before ?? 0)

        navigationStore.sessionPhase = .authenticated
        if let trade = viewModel.recentTrades.first {
            viewModel.openTrade(trade)
            XCTAssertFalse(navigationStore.paths.home.isEmpty)
        }
    }

    private func waitFor(
        timeout: TimeInterval = 2,
        _ condition: @escaping () -> Bool
    ) async {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Timed out waiting for condition")
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

private struct DashboardStubSession: SessionProviding {
    let userID: String?
    var currentUserID: UserID? {
        get async {
            guard let userID else { return nil }
            return UserID(userID)
        }
    }
    var accessToken: String? { get async { nil } }
}

private struct DashboardStubHomeRepository: HomeRepository {
    func dashboard(for profileID: ProfileID) async throws -> HomeDashboard {
        HomeDashboard(
            summary: PerformanceSummary(
                interval: DateIntervalValue(start: Date(), end: Date()),
                statistics: TradeStatistics(
                    tradeCount: 0,
                    winCount: 0,
                    lossCount: 0,
                    totalPnL: Money(amount: 0),
                    averagePnL: Money(amount: 0),
                    averageRiskReward: nil,
                    winRate: 0
                ),
                bestTradeID: nil,
                worstTradeID: nil,
                currentStreakDays: 0
            ),
            widgets: [],
            insights: [],
            shortcutDestinations: [],
            refreshedAt: Date()
        )
    }

    func performance(
        for profileID: ProfileID,
        interval: DateIntervalValue
    ) async throws -> PerformanceSummary {
        try await dashboard(for: profileID).summary
    }
}

private struct DashboardStubTradeRepository: TradeRepository {
    func trade(id: TradeID) async throws -> Trade {
        throw AppError.unknown(message: "not found")
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
        throw AppError.unknown(message: "stub")
    }

    func update(_ trade: Trade) async throws -> Trade { trade }
    func delete(id: TradeID) async throws {}
    func images(for tradeID: TradeID) async throws -> [TradeImage] { [] }
    func notes(for tradeID: TradeID) async throws -> [TradeNote] { [] }

    func statistics(
        for profileID: ProfileID,
        interval: DateIntervalValue
    ) async throws -> TradeStatistics {
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

private struct DashboardStubAchievementRepository: AchievementRepository {
    func achievement(id: AchievementID) async throws -> Achievement {
        throw AppError.unknown(message: "not found")
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
