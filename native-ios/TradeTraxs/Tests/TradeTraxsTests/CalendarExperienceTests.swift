import XCTest
@testable import TradeTraxs

@MainActor
final class CalendarExperienceTests: XCTestCase {
    func testTradingDayKeyUsesEasternSixPMRollover() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TradingCalendarDay.timeZone

        let beforeRollover = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 10, hour: 17, minute: 59
        ))!
        let afterRollover = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 10, hour: 18, minute: 0
        ))!

        XCTAssertEqual(TradingCalendarDay.key(for: beforeRollover), "2026-08-10")
        XCTAssertEqual(TradingCalendarDay.key(for: afterRollover), "2026-08-11")
    }

    func testTradingDayKeyPrefersEntryOverExit() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TradingCalendarDay.timeZone
        let entry = calendar.date(from: DateComponents(
            year: 2026, month: 3, day: 8, hour: 10
        ))!
        let exit = calendar.date(from: DateComponents(
            year: 2026, month: 3, day: 9, hour: 10
        ))!
        let trade = CalendarFixtures.trades(owner: CalendarFixtures.viewerID)[0]
        var copy = trade
        copy.entryAt = entry
        copy.exitAt = exit
        XCTAssertEqual(TradingCalendarDay.key(for: copy), "2026-03-08")
    }

    func testLeapYearFebruaryGridHas29Days() {
        let cells = TradingCalendarAggregator.makeGridCells(
            year: 2024,
            month: 2,
            days: [:],
            todayKey: nil
        )
        let current = cells.filter(\.isCurrentMonth)
        XCTAssertEqual(current.count, 29)
        XCTAssertEqual(cells.count % 7, 0)
    }

    func testMonthStartingOnSaturdayHasLeadingPads() {
        // 1 Aug 2026 is Saturday
        let cells = TradingCalendarAggregator.makeGridCells(
            year: 2026,
            month: 8,
            days: [:],
            todayKey: nil
        )
        XCTAssertFalse(cells[0].isCurrentMonth)
        XCTAssertEqual(cells.first(where: \.isCurrentMonth)?.dayNumber, 1)
        XCTAssertEqual(cells.count % 7, 0)
    }

    func testDailyPnLAndOutcomes() {
        let owner = CalendarFixtures.viewerID
        let trades = CalendarFixtures.trades(owner: owner)
        let days = TradingCalendarAggregator.daySummaries(from: trades, accountFilter: .all)

        // Day 3: +420 +180 = +600
        let day3 = days.first { $0.key.hasSuffix("-03") }?.value
        XCTAssertEqual(day3?.netPnL, 600)
        XCTAssertEqual(day3?.tradeCount, 2)
        XCTAssertEqual(day3?.outcome, .profit)

        // Day 12: breakeven 0
        let day12 = days.first { $0.key.hasSuffix("-12") }?.value
        XCTAssertEqual(day12?.netPnL, 0)
        XCTAssertEqual(day12?.outcome, .breakeven)

        // Day 5: loss
        let day5 = days.first { $0.key.hasSuffix("-05") }?.value
        XCTAssertEqual(day5?.outcome, .loss)
    }

    func testAccountFilterIsolatesPropAccount() {
        let owner = CalendarFixtures.viewerID
        let trades = CalendarFixtures.trades(owner: owner)
        let propID = TradingAccountID("dev.calendar.prop")
        let days = TradingCalendarAggregator.daySummaries(
            from: trades,
            accountFilter: .account(propID)
        )
        XCTAssertTrue(days.values.allSatisfy { $0.accountIDs.contains(propID) })
        XCTAssertNil(days.first { $0.key.hasSuffix("-03") }?.value)
        XCTAssertNotNil(days.first { $0.key.hasSuffix("-08") }?.value)
    }

    func testMonthSummaryAggregatesVisibleMonth() {
        let owner = CalendarFixtures.viewerID
        let trades = CalendarFixtures.trades(owner: owner)
        let monthID = CalendarMonthID.current()
        let month = TradingCalendarAggregator.buildMonth(
            year: monthID.year,
            month: monthID.month,
            trades: trades,
            accountFilter: .all,
            todayKey: nil
        )
        XCTAssertGreaterThan(month.monthSummary.tradeCount, 0)
        XCTAssertGreaterThan(month.monthSummary.tradingDayCount, 0)
        XCTAssertFalse(month.weekSummaries.isEmpty)
    }

    func testEmptyDayVersusBreakevenAreDistinct() {
        let cells = TradingCalendarAggregator.makeGridCells(
            year: 2026,
            month: 8,
            days: [
                "2026-08-12": TradingDaySummary(
                    dayKey: "2026-08-12",
                    netPnL: 0,
                    tradeCount: 1,
                    winCount: 0,
                    lossCount: 0,
                    breakevenCount: 1,
                    grossProfit: 0,
                    grossLoss: 0,
                    tradeIDs: [TradeID("be")],
                    accountIDs: []
                ),
            ],
            todayKey: nil
        )
        let be = cells.first { $0.dayKey == "2026-08-12" }
        let empty = cells.first { $0.dayKey == "2026-08-01" }
        XCTAssertEqual(be?.summary?.outcome, .breakeven)
        XCTAssertNil(empty?.summary)
    }

    func testCalendarNavigationStackHomeToDayToTrade() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: store)
        coordinator.open(.home(.calendar))
        coordinator.open(.home(.tradingDay("2026-08-08")))
        coordinator.open(.home(.tradeDetail(TradeID("c-4"))))
        XCTAssertEqual(store.paths.home.count, 3)
        if case .tradeDetail(let id) = store.paths.home.last {
            XCTAssertEqual(id, TradeID("c-4"))
        } else {
            XCTFail("Expected trade detail")
        }
        coordinator.pop()
        if case .tradingDay(let key) = store.paths.home.last {
            XCTAssertEqual(key, "2026-08-08")
        } else {
            XCTFail("Expected trading day")
        }
        coordinator.pop()
        XCTAssertEqual(store.paths.home.last, .calendar)
    }

    func testViewModelLoadsFixturesAndFiltersAccounts() async {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: store)
        let viewModel = CalendarViewModel(
            trades: CalendarStubTradeRepository(),
            session: CalendarStubSession(userID: "dev.calendar.user"),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: coordinator
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }
        XCTAssertNotNil(viewModel.month)
        XCTAssertFalse(viewModel.accounts.isEmpty)

        let before = viewModel.month?.monthSummary.tradeCount ?? 0
        viewModel.setAccountFilter(.account(TradingAccountID("dev.calendar.prop")))
        let after = viewModel.month?.monthSummary.tradeCount ?? 0
        XCTAssertLessThan(after, before)
    }

    func testRealtimeUpsertAndDeleteUpdateDaySummary() async {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let viewModel = CalendarViewModel(
            trades: CalendarStubTradeRepository(),
            session: CalendarStubSession(userID: "dev.calendar.user"),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: store)
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }

        var trade = CalendarFixtures.trades(owner: ProfileID("dev.calendar.user"))[0]
        trade.id = TradeID("rt-new")
        trade.realizedPnL = Money(amount: 999)
        viewModel.applyRealtimeUpsert(trade)
        XCTAssertTrue(
            viewModel.month?.days.values.contains { $0.tradeIDs.contains(TradeID("rt-new")) } == true
        )

        viewModel.applyRealtimeDelete(id: TradeID("rt-new"))
        XCTAssertFalse(
            viewModel.month?.days.values.contains { $0.tradeIDs.contains(TradeID("rt-new")) } == true
        )
    }

    func testCompactPnLFormatting() {
        XCTAssertEqual(CalendarFormatting.compactPnL(842), "+$842")
        XCTAssertEqual(CalendarFormatting.compactPnL(-215), "-$215")
        XCTAssertEqual(CalendarFormatting.compactPnL(12_400), "+$12.4K")
    }

    func testFetchWindowCoversSixPMRolloverPadding() {
        let window = TradingCalendarDay.fetchWindow(year: 2026, month: 8)
        XCTAssertNotNil(window)
        // Window should start on July 31 18:00 ET
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TradingCalendarDay.timeZone
        let startComps = calendar.dateComponents(
            [.year, .month, .day, .hour],
            from: window!.start
        )
        XCTAssertEqual(startComps.month, 7)
        XCTAssertEqual(startComps.day, 31)
        XCTAssertEqual(startComps.hour, 18)
    }

    func testDashboardOpenCalendarPushesHomeRoute() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: store)
        let viewModel = DashboardViewModel(
            home: CalendarStubHomeRepository(),
            trades: CalendarStubTradeRepository(),
            achievements: CalendarStubAchievementRepository(),
            session: CalendarStubSession(userID: "dev.calendar.user"),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: coordinator
        )
        viewModel.openCalendar()
        XCTAssertEqual(store.paths.home.last, .calendar)
    }

    private func waitFor(timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) async {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Timed out")
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

// MARK: - Stubs

private struct CalendarStubSession: SessionProviding {
    let userID: String?
    var currentUserID: UserID? {
        get async {
            guard let userID else { return nil }
            return UserID(userID)
        }
    }
    var accessToken: String? {
        get async { userID == nil ? nil : "test" }
    }
}

private struct CalendarStubTradeRepository: TradeRepository {
    func trade(id: TradeID) async throws -> Trade {
        throw AppError.domain(.notFound(entity: "trade", id: id.rawValue))
    }

    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Trade> {
        _ = (page, publicOnly)
        var items = CalendarFixtures.trades(owner: profileID)
        if let accountID {
            items = items.filter { $0.accountID == accountID }
        }
        return CursorPage(items: items, nextCursor: nil)
    }

    func save(_ draft: TradeDraft) async throws -> Trade {
        throw AppError.unknown(message: "unused")
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
    func accounts(for profileID: ProfileID) async throws -> [TradingAccount] {
        CalendarFixtures.accounts(owner: profileID)
    }
}

private struct CalendarStubHomeRepository: HomeRepository {
    func dashboard(for profileID: ProfileID) async throws -> HomeDashboard {
        _ = profileID
        return HomeDashboard(
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

    func performance(for profileID: ProfileID, interval: DateIntervalValue) async throws -> PerformanceSummary {
        _ = (profileID, interval)
        return PerformanceSummary(
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
        )
    }
}

private struct CalendarStubAchievementRepository: AchievementRepository {
    func achievements(
        for profileID: ProfileID,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Achievement> {
        _ = (profileID, page, publicOnly)
        return CursorPage(items: [], nextCursor: nil)
    }

    func achievement(id: AchievementID) async throws -> Achievement {
        throw AppError.domain(.notFound(entity: "achievement", id: id.rawValue))
    }

    func save(_ achievement: Achievement) async throws -> Achievement {
        achievement
    }
}
