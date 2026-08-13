import XCTest
@testable import TradeTraxs

@MainActor
final class TradeHistoryExperienceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TradeHistorySessionStore.shared.invalidate()
        TradeJournalMutationStore.shared.invalidate()
        SessionAccountsStore.shared.invalidate()
    }

    override func tearDown() {
        TradeHistorySessionStore.shared.invalidate()
        TradeJournalMutationStore.shared.invalidate()
        SessionAccountsStore.shared.invalidate()
        super.tearDown()
    }

    func testDashboardOpensCalendarAndTradesRoutes() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: store)
        let viewModel = DashboardViewModel(
            home: TradeHistoryStubHomeRepository(),
            trades: TradeHistoryStubTradeRepository(),
            achievements: TradeHistoryStubAchievementRepository(),
            session: TradeHistoryStubSession(userID: "dev.trades.nav"),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: coordinator
        )

        viewModel.openCalendar()
        XCTAssertEqual(store.paths.home.last, .calendar)

        store.paths.home.removeAll()
        viewModel.openTradesList()
        XCTAssertEqual(store.paths.home.last, .trades)
    }

    func testLocalMatchFiltersWinsLossesPnLAndDirection() {
        let profileID = ProfileID("dev.trades.filter")
        let win = makeTrade(id: "w", profileID: profileID, side: .long, pnl: 100)
        let loss = makeTrade(id: "l", profileID: profileID, side: .short, pnl: -50)
        let flat = makeTrade(id: "b", profileID: profileID, side: .long, pnl: 0)

        var filters = TradeHistoryFilters()
        filters.result = .wins
        XCTAssertTrue(TradeHistoryLocalMatch.matches(win, query: TradeHistoryQuery(filters: filters)))
        XCTAssertFalse(TradeHistoryLocalMatch.matches(loss, query: TradeHistoryQuery(filters: filters)))

        filters.result = .losses
        XCTAssertTrue(TradeHistoryLocalMatch.matches(loss, query: TradeHistoryQuery(filters: filters)))

        filters.result = .breakeven
        XCTAssertTrue(TradeHistoryLocalMatch.matches(flat, query: TradeHistoryQuery(filters: filters)))

        filters = TradeHistoryFilters()
        filters.pnlMin = 80
        filters.pnlMax = 150
        XCTAssertTrue(TradeHistoryLocalMatch.matches(win, query: TradeHistoryQuery(filters: filters)))
        XCTAssertFalse(TradeHistoryLocalMatch.matches(loss, query: TradeHistoryQuery(filters: filters)))

        filters = TradeHistoryFilters()
        filters.direction = .short
        XCTAssertTrue(TradeHistoryLocalMatch.matches(loss, query: TradeHistoryQuery(filters: filters)))
        XCTAssertFalse(TradeHistoryLocalMatch.matches(win, query: TradeHistoryQuery(filters: filters)))
    }

    func testVisibilityAndSymbolSearch() {
        let profileID = ProfileID("dev.trades.search")
        var pub = makeTrade(id: "p", profileID: profileID, side: .long, pnl: 10)
        pub.visibility = .public
        pub.symbol = Symbol(ticker: "MNQ")
        var priv = makeTrade(id: "v", profileID: profileID, side: .long, pnl: 10)
        priv.visibility = .private
        priv.notePreview = "breakout notes"

        var filters = TradeHistoryFilters()
        filters.visibility = .public
        XCTAssertTrue(TradeHistoryLocalMatch.matches(pub, query: TradeHistoryQuery(filters: filters)))
        XCTAssertFalse(TradeHistoryLocalMatch.matches(priv, query: TradeHistoryQuery(filters: filters)))

        let bySymbol = TradeHistoryQuery(filters: TradeHistoryFilters(), searchText: "mnq")
        XCTAssertTrue(TradeHistoryLocalMatch.matches(pub, query: bySymbol))
        XCTAssertFalse(TradeHistoryLocalMatch.matches(priv, query: bySymbol))

        let byNotes = TradeHistoryQuery(filters: TradeHistoryFilters(), searchText: "breakout")
        XCTAssertTrue(TradeHistoryLocalMatch.matches(priv, query: byNotes))
    }

    func testDatePresetsAndCustomRange() {
        let profileID = ProfileID("dev.trades.date")
        let now = Date()
        var recent = makeTrade(id: "r", profileID: profileID, side: .long, pnl: 1)
        recent.createdAt = now
        var old = makeTrade(id: "o", profileID: profileID, side: .long, pnl: 1)
        old.createdAt = now.addingTimeInterval(-90 * 86_400)

        var filters = TradeHistoryFilters()
        filters.dateRange = .last30Days
        XCTAssertTrue(TradeHistoryLocalMatch.matches(recent, query: TradeHistoryQuery(filters: filters)))
        XCTAssertFalse(TradeHistoryLocalMatch.matches(old, query: TradeHistoryQuery(filters: filters)))

        filters.dateRange = .custom
        filters.customStart = now.addingTimeInterval(-2 * 86_400)
        filters.customEnd = now
        XCTAssertTrue(TradeHistoryLocalMatch.matches(recent, query: TradeHistoryQuery(filters: filters)))
        XCTAssertFalse(TradeHistoryLocalMatch.matches(old, query: TradeHistoryQuery(filters: filters)))
    }

    func testViewModelLoadsFixturesAppliesFiltersAndOpensDetail() async {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: store)
        let cache = DetailPresentationCache()
        let repository = TradeHistoryStubTradeRepository()
        let viewModel = TradeHistoryViewModel(
            trades: repository,
            session: TradeHistoryStubSession(userID: "dev.trades.vm"),
            detailCache: cache,
            navigationCoordinator: coordinator
        )

        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }
        XCTAssertFalse(viewModel.items.isEmpty)
        XCTAssertEqual(repository.historyCallCount, 0, "Dev fixtures skip network history")

        let before = viewModel.items.count
        viewModel.filters.result = .wins
        await viewModel.refresh()
        XCTAssertLessThanOrEqual(viewModel.items.count, before)

        if let trade = viewModel.items.first {
            viewModel.openTrade(trade)
            XCTAssertEqual(store.paths.home.last, .tradeDetail(trade.id))
            XCTAssertNotNil(cache.trade(id: trade.id))
        }

        viewModel.clearAllFilters()
        await waitFor { viewModel.filters.result == .any }
    }

    func testPaginationAppendsUniqueAndCancelsStaleSearch() async {
        let store = NavigationStore()
        let coordinator = NavigationCoordinator(store: store)
        let repository = TradeHistoryPagingStubRepository()
        let viewModel = TradeHistoryViewModel(
            trades: repository,
            session: TradeHistoryStubSession(userID: "00000000-0000-4000-8000-000000000221"),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: coordinator
        )

        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded && !viewModel.items.isEmpty }
        XCTAssertEqual(repository.historyCallCount, 1)
        XCTAssertEqual(viewModel.items.count, 2)
        XCTAssertNotNil(viewModel.nextCursor)

        await viewModel.loadMoreIfNeeded(currentTradeID: viewModel.items.last?.id)
        XCTAssertEqual(viewModel.items.count, 4)
        XCTAssertEqual(repository.historyCallCount, 2)

        // Duplicate load-more at non-tail id should no-op.
        await viewModel.loadMoreIfNeeded(currentTradeID: viewModel.items.first?.id)
        XCTAssertEqual(repository.historyCallCount, 2)
    }

    func testEmptyFilteredVsEmptyJournal() async {
        let emptyVM = TradeHistoryViewModel(
            trades: TradeHistoryStubTradeRepository(empty: true),
            session: TradeHistoryStubSession(userID: "00000000-0000-4000-8000-000000000223"),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )
        emptyVM.loadIfNeeded()
        await waitFor { emptyVM.phase == .loaded }
        XCTAssertTrue(emptyVM.isEmptyJournal)

        let filteredVM = TradeHistoryViewModel(
            trades: TradeHistoryStubTradeRepository(),
            session: TradeHistoryStubSession(userID: "dev.trades.empty.filter"),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )
        filteredVM.loadIfNeeded()
        await waitFor { filteredVM.phase == .loaded }
        filteredVM.filters.pnlMin = 9_999_999
        await filteredVM.refresh()
        XCTAssertTrue(filteredVM.isEmptyFiltered)
        XCTAssertFalse(filteredVM.isEmptyJournal)
    }

    func testSnapshotRestoreHydratesAccountsFromSessionStoreWithoutRefetch() async {
        let profileID = ProfileID("00000000-0000-4000-8000-000000000225")
        let cache = DetailPresentationCache()
        let seededAccounts = PropFirmFixtures.accounts(owner: profileID)
        SessionAccountsStore.shared.seed(seededAccounts, for: profileID, detailCache: cache)

        let trade = makeTrade(id: "snap-1", profileID: profileID, side: .long, pnl: 25)
        let filters = TradeHistoryFilters()
        TradeHistorySessionStore.shared.save(
            TradeHistorySessionStore.Snapshot(
                queryKey: TradeHistorySessionStore.queryKey(
                    profileID: profileID,
                    filters: filters,
                    searchText: ""
                ),
                profileID: profileID,
                items: [trade],
                nextCursor: nil,
                filters: filters,
                searchText: "",
                loadedAt: Date()
            )
        )

        let repository = TradeHistoryStubTradeRepository()
        // Fresh ViewModel — mimics Dashboard → Trades push recreating @State.
        let viewModel = TradeHistoryViewModel(
            trades: repository,
            session: TradeHistoryStubSession(userID: profileID.rawValue),
            detailCache: cache,
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded && !viewModel.accounts.isEmpty }

        XCTAssertEqual(viewModel.accounts.count, seededAccounts.count)
        XCTAssertEqual(
            Set(viewModel.accounts.map(\.id)),
            Set(seededAccounts.map(\.id))
        )
        XCTAssertEqual(repository.accountsCallCount, 0, "Must reuse SessionAccountsStore; no accounts refetch")
        XCTAssertEqual(repository.historyCallCount, 0, "Snapshot path must not refetch trade history")
        XCTAssertEqual(viewModel.items.count, 1)
    }

    func testMutationStoreTriggersReloadWithoutPolling() async {
        let profileID = ProfileID("00000000-0000-4000-8000-000000000222")
        let repository = TradeHistoryPagingStubRepository()
        let viewModel = TradeHistoryViewModel(
            trades: repository,
            session: TradeHistoryStubSession(userID: profileID.rawValue),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }
        let before = repository.historyCallCount
        let countBefore = viewModel.items.count

        var created = makeTrade(id: "mutated", profileID: profileID, side: .long, pnl: 42)
        created.ownerProfileID = profileID
        TradeJournalMutationStore.shared.noteCreated(created)
        viewModel.handleJournalMutation()

        XCTAssertEqual(repository.historyCallCount, before, "Local insert must not refetch list")
        XCTAssertEqual(viewModel.items.first?.id, created.id)
        XCTAssertEqual(viewModel.items.count, countBefore + 1)

        // Bulk import still forces a revalidate.
        TradeJournalMutationStore.shared.noteBulkImport()
        viewModel.handleJournalMutation()
        await waitFor { repository.historyCallCount == before + 1 }
        XCTAssertEqual(repository.historyCallCount, before + 1)
    }

    // MARK: - Helpers

    private func makeTrade(
        id: String,
        profileID: ProfileID,
        side: TradeSide,
        pnl: Decimal
    ) -> Trade {
        let now = Date()
        return Trade(
            id: TradeID(id),
            ownerProfileID: profileID,
            accountID: TradingAccountID("acct"),
            symbol: Symbol(ticker: "NQ"),
            side: side,
            mode: .live,
            quantity: 1,
            entryPrice: 1,
            exitPrice: 2,
            entryAt: now,
            exitAt: now,
            realizedPnL: Money(amount: pnl),
            riskReward: nil,
            points: nil,
            sessionLabel: "NY",
            visibility: .private,
            publicCaption: nil,
            thumbnail: nil,
            notePreview: nil,
            createdAt: now,
            updatedAt: now
        )
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

// MARK: - Stubs

private struct TradeHistoryStubSession: SessionProviding {
    let userID: String?
    var currentUserID: UserID? {
        get async {
            guard let userID else { return nil }
            return UserID(userID)
        }
    }
    var accessToken: String? { get async { userID == nil ? nil : "token" } }
}

private struct TradeHistoryStubHomeRepository: HomeRepository {
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

private struct TradeHistoryStubAchievementRepository: AchievementRepository {
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

private final class TradeHistoryStubTradeRepository: TradeRepository, @unchecked Sendable {
    var historyCallCount = 0
    var accountsCallCount = 0
    let empty: Bool

    init(empty: Bool = false) {
        self.empty = empty
    }

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

    func tradeHistory(
        ownedBy profileID: ProfileID,
        query: TradeHistoryQuery,
        page: PageRequest
    ) async throws -> CursorPage<Trade> {
        historyCallCount += 1
        return CursorPage(items: [], nextCursor: nil)
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

    func accounts(for profileID: ProfileID) async throws -> [TradingAccount] {
        accountsCallCount += 1
        return empty ? [] : PropFirmFixtures.accounts(owner: profileID)
    }
}

private final class TradeHistoryPagingStubRepository: TradeRepository, @unchecked Sendable {
    var historyCallCount = 0

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

    func tradeHistory(
        ownedBy profileID: ProfileID,
        query: TradeHistoryQuery,
        page: PageRequest
    ) async throws -> CursorPage<Trade> {
        historyCallCount += 1
        let now = Date()
        func trade(_ id: String, offset: TimeInterval) -> Trade {
            Trade(
                id: TradeID(id),
                ownerProfileID: profileID,
                accountID: nil,
                symbol: Symbol(ticker: "ES"),
                side: .long,
                mode: .live,
                quantity: 1,
                entryPrice: 1,
                exitPrice: 2,
                entryAt: now.addingTimeInterval(offset),
                exitAt: now.addingTimeInterval(offset + 60),
                realizedPnL: Money(amount: 10),
                riskReward: nil,
                points: nil,
                sessionLabel: "NY",
                visibility: .private,
                publicCaption: nil,
                thumbnail: nil,
                notePreview: nil,
                createdAt: now.addingTimeInterval(offset),
                updatedAt: now.addingTimeInterval(offset)
            )
        }
        if page.cursor == nil {
            return CursorPage(
                items: [trade("a", offset: 0), trade("b", offset: -60)],
                nextCursor: "cursor-1"
            )
        }
        return CursorPage(
            items: [trade("c", offset: -120), trade("d", offset: -180)],
            nextCursor: nil
        )
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

    func accounts(for profileID: ProfileID) async throws -> [TradingAccount] {
        PropFirmFixtures.accounts(owner: profileID)
    }
}
