import XCTest
@testable import TradeTraxs

@MainActor
final class PropFirmExperienceTests: XCTestCase {
    func testTrailingDrawdownMatchesWebPeakAndBreach() {
        let trades = [
            PropFirmMetrics.TradeInput(
                id: "1",
                pnl: 1_000,
                createdAt: date("2024-01-01T10:00:00Z")
            ),
            PropFirmMetrics.TradeInput(
                id: "2",
                pnl: -2_500,
                createdAt: date("2024-01-02T10:00:00Z")
            ),
        ]
        let result = PropFirmMetrics.computeTrailingDrawdown(
            trades: trades,
            startingBalance: 50_000,
            maxDrawdown: 2_000
        )
        XCTAssertEqual(result.peakBalance, 51_000)
        XCTAssertEqual(result.currentBalance, 48_500)
        XCTAssertEqual(result.maxDrawdownUsed, 2_500)
        XCTAssertTrue(result.breachedTrailingDD)
    }

    func testTrailingDrawdownRaisesFloorOnNewPeak() {
        let trades = [
            PropFirmMetrics.TradeInput(id: "1", pnl: 500, createdAt: date("2024-01-01T10:00:00Z")),
            PropFirmMetrics.TradeInput(id: "2", pnl: 300, createdAt: date("2024-01-02T10:00:00Z")),
        ]
        let result = PropFirmMetrics.computeTrailingDrawdown(
            trades: trades,
            startingBalance: 50_000,
            maxDrawdown: 2_000
        )
        XCTAssertEqual(result.peakBalance, 50_800)
        XCTAssertEqual(result.drawdownFloor, 48_800)
        XCTAssertFalse(result.breachedTrailingDD)
    }

    func testConsistencyFailsWhenBiggestWinExceedsPercent() {
        let trades = [
            PropFirmMetrics.TradeInput(id: "1", pnl: 1_000, createdAt: Date()),
            PropFirmMetrics.TradeInput(id: "2", pnl: 100, createdAt: Date()),
        ]
        let result = PropFirmMetrics.computeConsistency(trades: trades, consistencyPercent: 40)
        XCTAssertTrue(result.ruleActive)
        XCTAssertFalse(result.isConsistent)
        XCTAssertEqual(result.biggestWin, 1_000)
        XCTAssertEqual(result.allowedMax, 440) // 1100 * 0.4
    }

    func testPropStatusHiddenForAllAccountsAndPersonal() {
        let profileID = ProfileID("dev.propfirm")
        let accounts = PropFirmFixtures.accounts(owner: profileID)
        let prop = accounts.first(where: \.isPropFirmAccount)!
        let personal = accounts.first(where: { !$0.isPropFirmAccount })!

        XCTAssertNotNil(
            PropFirmStatusSnapshot.build(
                account: prop,
                trades: PropFirmFixtures.trades(owner: profileID, accountID: prop.id)
            )
        )
        XCTAssertNil(
            PropFirmStatusSnapshot.build(
                account: personal,
                trades: PropFirmFixtures.trades(owner: profileID, accountID: personal.id)
            )
        )
    }

    func testDashboardShowsPropStatusOnlyForSelectedPropAccount() async {
        let cache = DetailPresentationCache()
        let store = NavigationStore()
        let coordinator = NavigationCoordinator(store: store)
        let viewModel = DashboardViewModel(
            home: PropFirmStubHomeRepository(),
            trades: PropFirmStubTradeRepository(),
            achievements: PropFirmStubAchievementRepository(),
            dailyCheckIns: EmptyTraderDailyCheckInRepository(),
            session: PropFirmStubSession(userID: "dev.propfirm.user"),
            detailCache: cache,
            navigationCoordinator: coordinator
        )

        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }

        XCTAssertNil(viewModel.propFirmStatus, "All Accounts hides prop status")

        if let personal = viewModel.accounts.first(where: { !$0.isPropFirmAccount }) {
            viewModel.setAccountFilter(.account(personal.id))
            XCTAssertNil(viewModel.propFirmStatus)
        }

        if let prop = viewModel.accounts.first(where: \.isPropFirmAccount) {
            viewModel.setAccountFilter(.account(prop.id))
            XCTAssertNotNil(viewModel.propFirmStatus)
            XCTAssertEqual(
                viewModel.accountMenuTitle(for: prop),
                TradingAccountDisplay.title(for: prop, audience: .owner)
            )
            XCTAssertTrue(viewModel.accountMenuTitle(for: prop).contains("•"))

            store.sessionPhase = .authenticated
            viewModel.openPropFirmDetails()
            XCTAssertTrue(
                store.paths.home.contains {
                    if case .propFirm(let id) = $0 { return id == prop.id }
                    return false
                }
            )
        } else {
            XCTFail("Expected prop fixture account")
        }
    }

    func testCategoryMapperRecognizesPropFirmSnakeCase() throws {
        let dto = TradeDTO.Account(
            id: "a1",
            user_id: "u1",
            name: "Alpha",
            account_name: nil,
            account_type: nil,
            category: "prop_firm",
            mode: "Eval",
            account_size: FlexibleNumber(Decimal(50_000)),
            size: nil,
            is_active: true,
            can_add_trades: true,
            consistency: FlexibleNumber(Decimal(35)),
            max_drawdown: FlexibleNumber(Decimal(2_000)),
            daily_drawdown: FlexibleNumber(Decimal(1_000)),
            profit_target: FlexibleNumber(Decimal(3_000)),
            winning_days: FlexibleNumber(Decimal(5)),
            winning_day_threshold: nil,
            payout_drawdown_behavior: "keep_trailing"
        )
        let account = try TradingAccountMapper.mapToDomain(dto)
        XCTAssertEqual(account.category, .propFirm)
        XCTAssertEqual(account.mode, .evaluation)
        XCTAssertNotNil(account.propFirmRules?.maxDrawdown)
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso) ?? Date()
    }

    private func waitFor(timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out")
    }
}

// MARK: - Stubs

private struct PropFirmStubSession: SessionProviding {
    let userID: String?
    var currentUserID: UserID? {
        get async {
            guard let userID else { return nil }
            return UserID(userID)
        }
    }
    var accessToken: String? { get async { nil } }
}

private struct PropFirmStubHomeRepository: HomeRepository {
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

private struct PropFirmStubTradeRepository: TradeRepository {
    func trade(id: TradeID) async throws -> Trade { throw AppError.unknown(message: "stub") }
    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Trade> {
        CursorPage(items: [], nextCursor: nil)
    }
    func save(_ draft: TradeDraft) async throws -> Trade { throw AppError.unknown(message: "stub") }
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

private struct PropFirmStubAchievementRepository: AchievementRepository {
    func achievement(id: AchievementID) async throws -> Achievement {
        throw AppError.unknown(message: "stub")
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
