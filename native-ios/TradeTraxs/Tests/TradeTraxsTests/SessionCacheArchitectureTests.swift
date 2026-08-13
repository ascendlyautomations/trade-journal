import XCTest
@testable import TradeTraxs

@MainActor
final class SessionCacheArchitectureTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SessionAccountsStore.shared.invalidate()
        TradeHistorySessionStore.shared.invalidate()
        CalendarMonthSessionStore.shared.invalidate()
        TradeJournalMutationStore.shared.invalidate()
        AccountMutationStore.shared.invalidate()
        SessionNetworkProbe.resetForTesting()
    }

    override func tearDown() {
        SessionAccountsStore.shared.invalidate()
        TradeHistorySessionStore.shared.invalidate()
        CalendarMonthSessionStore.shared.invalidate()
        SessionNetworkProbe.resetForTesting()
        super.tearDown()
    }

    // MARK: - Accounts cache + coalescing

    func testAccountsCacheHitSkipsNetwork() async throws {
        let profileID = ProfileID("00000000-0000-4000-8000-000000000101")
        let repo = CountingTradeRepository(accounts: SettingsFixtures.accounts(owner: profileID))
        let cache = DetailPresentationCache()

        _ = try await SessionAccountsStore.shared.accounts(
            for: profileID,
            detailCache: cache,
            repository: repo
        )
        XCTAssertEqual(repo.accountsCallCount, 1)

        SessionNetworkProbe.resetForTesting()
        _ = try await SessionAccountsStore.shared.accounts(
            for: profileID,
            detailCache: cache,
            repository: repo
        )
        XCTAssertEqual(repo.accountsCallCount, 1)
        XCTAssertEqual(SessionNetworkProbe.networkCount(for: "accounts"), 0)
    }

    func testAccountsForceRefreshNetworks() async throws {
        let profileID = ProfileID("00000000-0000-4000-8000-000000000102")
        let repo = CountingTradeRepository(accounts: SettingsFixtures.accounts(owner: profileID))
        let cache = DetailPresentationCache()

        _ = try await SessionAccountsStore.shared.accounts(
            for: profileID,
            detailCache: cache,
            repository: repo
        )
        _ = try await SessionAccountsStore.shared.accounts(
            for: profileID,
            detailCache: cache,
            repository: repo,
            forceNetwork: true
        )
        XCTAssertEqual(repo.accountsCallCount, 2)
    }

    func testConcurrentAccountsRequestsCoalesce() async throws {
        let profileID = ProfileID("00000000-0000-4000-8000-000000000103")
        let repo = CountingTradeRepository(
            accounts: SettingsFixtures.accounts(owner: profileID),
            accountsDelayNanoseconds: 80_000_000
        )
        let cache = DetailPresentationCache()

        async let a = SessionAccountsStore.shared.accounts(
            for: profileID,
            detailCache: cache,
            repository: repo
        )
        async let b = SessionAccountsStore.shared.accounts(
            for: profileID,
            detailCache: cache,
            repository: repo
        )
        async let c = SessionAccountsStore.shared.accounts(
            for: profileID,
            detailCache: cache,
            repository: repo
        )
        let results = try await [a, b, c]
        XCTAssertEqual(results[0].count, results[1].count)
        XCTAssertEqual(repo.accountsCallCount, 1)
    }

    // MARK: - Trade history session

    func testTradeHistoryNavigationReturnDoesNotRefetch() async {
        let profileID = ProfileID("00000000-0000-4000-8000-000000000104")
        let trade = makeTrade(id: "t1", profileID: profileID)
        let repo = CountingTradeRepository(history: [trade])
        let cache = DetailPresentationCache()
        let coordinator = NavigationCoordinator(store: NavigationStore())

        let first = TradeHistoryViewModel(
            trades: repo,
            session: FixedSession(userID: profileID.rawValue),
            detailCache: cache,
            navigationCoordinator: coordinator
        )
        first.loadIfNeeded()
        await waitUntil { first.phase == .loaded }
        XCTAssertEqual(repo.historyCallCount, 1)
        XCTAssertEqual(first.items.count, 1)

        // Simulate push → pop ViewModel recreation.
        let second = TradeHistoryViewModel(
            trades: repo,
            session: FixedSession(userID: profileID.rawValue),
            detailCache: cache,
            navigationCoordinator: coordinator
        )
        SessionNetworkProbe.resetForTesting()
        second.loadIfNeeded()
        await waitUntil { second.phase == .loaded }
        XCTAssertEqual(second.items.count, 1)
        XCTAssertEqual(repo.historyCallCount, 1)
        XCTAssertEqual(SessionNetworkProbe.networkCount(for: "trades.history"), 0)
    }

    func testTradeHistoryFilterCacheIsolation() {
        let profileID = ProfileID("00000000-0000-4000-8000-000000000105")
        var filtersA = TradeHistoryFilters()
        filtersA.result = .wins
        var filtersB = TradeHistoryFilters()
        filtersB.result = .losses

        let trade = makeTrade(id: "win", profileID: profileID, pnl: 50)
        TradeHistorySessionStore.shared.save(
            .init(
                queryKey: TradeHistorySessionStore.queryKey(
                    profileID: profileID,
                    filters: filtersA,
                    searchText: ""
                ),
                profileID: profileID,
                items: [trade],
                nextCursor: nil,
                filters: filtersA,
                searchText: "",
                loadedAt: Date()
            )
        )

        XCTAssertNotNil(
            TradeHistorySessionStore.shared.restore(
                profileID: profileID,
                filters: filtersA,
                searchText: ""
            )
        )
        XCTAssertNil(
            TradeHistorySessionStore.shared.restore(
                profileID: profileID,
                filters: filtersB,
                searchText: ""
            )
        )
    }

    func testLocalMutationAndRealtimeDoNotDuplicate() {
        let profileID = ProfileID("00000000-0000-4000-8000-000000000106")
        let trade = makeTrade(id: "dup", profileID: profileID, pnl: 10)
        TradeHistorySessionStore.shared.save(
            .init(
                queryKey: TradeHistorySessionStore.queryKey(
                    profileID: profileID,
                    filters: TradeHistoryFilters(),
                    searchText: ""
                ),
                profileID: profileID,
                items: [],
                nextCursor: nil,
                filters: TradeHistoryFilters(),
                searchText: "",
                loadedAt: Date()
            )
        )
        TradeJournalMutationStore.shared.noteCreated(trade)
        TradeHistorySessionStore.shared.noteCreated(trade)

        let snap = TradeHistorySessionStore.shared.restore(
            profileID: profileID,
            filters: TradeHistoryFilters(),
            searchText: ""
        )
        XCTAssertEqual(snap?.items.filter { $0.id == trade.id }.count, 1)
    }

    // MARK: - Calendar month session

    func testCalendarMonthCacheHitSkipsNetworkSemantics() {
        let trade = makeTrade(id: "c1", profileID: ProfileID("00000000-0000-4000-8000-000000000107"), pnl: 5)
        CalendarMonthSessionStore.shared.store([trade], year: 2026, month: 8)
        SessionNetworkProbe.resetForTesting()
        let cached = CalendarMonthSessionStore.shared.trades(year: 2026, month: 8)
        XCTAssertEqual(cached?.count, 1)
        XCTAssertTrue(CalendarMonthSessionStore.shared.isFresh(year: 2026, month: 8))
    }

    func testCalendarNoteCreatedPatchesMonth() {
        let profileID = ProfileID("00000000-0000-4000-8000-000000000108")
        let existing = makeTrade(id: "old", profileID: profileID, pnl: 1)
        CalendarMonthSessionStore.shared.store([existing], year: 2026, month: 8)
        var created = makeTrade(id: "new", profileID: profileID, pnl: 9)
        // Align entry month with store key (August 2026).
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 8
        comps.day = 11
        created.entryAt = Calendar.current.date(from: comps) ?? created.entryAt
        CalendarMonthSessionStore.shared.noteCreated(created)
        let trades = CalendarMonthSessionStore.shared.trades(year: 2026, month: 8) ?? []
        XCTAssertEqual(Set(trades.map(\.id.rawValue)), Set(["old", "new"]))
    }

    // MARK: - Realtime subscription dedupe

    func testRealtimeChannelRetainCountsDeduplicate() async throws {
        let registry = InMemoryChannelRegistry()
        let manager = RegistrySubscriptionManager(registry: registry)
        let channel = RealtimeChannelID(kind: .profile, topic: "dashboard:test")

        try await manager.subscribe(channel)
        try await manager.subscribe(channel)
        XCTAssertEqual(registry.retainCount(for: channel), 2)
        XCTAssertEqual(registry.registeredChannels().count, 1)

        try await manager.unsubscribe(channel)
        XCTAssertEqual(registry.retainCount(for: channel), 1)
        XCTAssertEqual(registry.registeredChannels().count, 1)

        try await manager.unsubscribe(channel)
        XCTAssertEqual(registry.retainCount(for: channel), 0)
        XCTAssertTrue(registry.registeredChannels().isEmpty)
    }

    // MARK: - Logout clears session caches

    func testLogoutClearsSessionCaches() {
        let profileID = ProfileID("00000000-0000-4000-8000-000000000109")
        SessionAccountsStore.shared.seed(
            SettingsFixtures.accounts(owner: profileID),
            for: profileID
        )
        let historyKey = TradeHistorySessionStore.queryKey(
            profileID: profileID,
            filters: TradeHistoryFilters(),
            searchText: ""
        )
        TradeHistorySessionStore.shared.save(
            .init(
                queryKey: historyKey,
                profileID: profileID,
                items: [makeTrade(id: "x", profileID: profileID)],
                nextCursor: nil,
                filters: TradeHistoryFilters(),
                searchText: "",
                loadedAt: Date()
            )
        )
        CalendarMonthSessionStore.shared.store(
            [makeTrade(id: "y", profileID: profileID)],
            year: 2026,
            month: 8
        )

        // Mirror ``SessionScopedCaches.invalidate`` user-scoped clears.
        SessionAccountsStore.shared.invalidate()
        TradeHistorySessionStore.shared.invalidate()
        CalendarMonthSessionStore.shared.invalidate()
        TradeJournalMutationStore.shared.invalidate()
        AccountMutationStore.shared.invalidate()

        XCTAssertNil(SessionAccountsStore.shared.cached(for: profileID))
        XCTAssertNil(TradeHistorySessionStore.shared.snapshot(forKey: historyKey))
        XCTAssertNil(CalendarMonthSessionStore.shared.trades(year: 2026, month: 8))
    }

    // MARK: - Acceptance sequence (warm return = 0 network)

    func testWarmNavigationAcceptanceSequenceZeroDuplicateSelects() async throws {
        let profileID = ProfileID("00000000-0000-4000-8000-000000000110")
        let accounts = SettingsFixtures.accounts(owner: profileID)
        let trade = makeTrade(id: "accept", profileID: profileID, pnl: 12)
        let repo = CountingTradeRepository(accounts: accounts, history: [trade], monthTrades: [trade])
        let cache = DetailPresentationCache()
        let coordinator = NavigationCoordinator(store: NavigationStore())

        // --- First open: Dashboard accounts + Trades + Calendar month ---
        _ = try await SessionAccountsStore.shared.accounts(
            for: profileID,
            detailCache: cache,
            repository: repo
        )
        let tradesVM = TradeHistoryViewModel(
            trades: repo,
            session: FixedSession(userID: profileID.rawValue),
            detailCache: cache,
            navigationCoordinator: coordinator
        )
        tradesVM.loadIfNeeded()
        await waitUntil { tradesVM.phase == .loaded }

        CalendarMonthSessionStore.shared.store([trade], year: 2026, month: 8)

        let accountsAfterWarm = repo.accountsCallCount
        let historyAfterWarm = repo.historyCallCount
        SessionNetworkProbe.resetForTesting()

        // --- Warm returns ---
        // Dashboard accounts
        _ = try await SessionAccountsStore.shared.accounts(
            for: profileID,
            detailCache: cache,
            repository: repo
        )
        // Trades → Detail → Trades
        let tradesReturn = TradeHistoryViewModel(
            trades: repo,
            session: FixedSession(userID: profileID.rawValue),
            detailCache: cache,
            navigationCoordinator: coordinator
        )
        tradesReturn.loadIfNeeded()
        await waitUntil { tradesReturn.phase == .loaded }
        XCTAssertEqual(tradesReturn.items.count, 1)

        // Calendar month
        XCTAssertNotNil(CalendarMonthSessionStore.shared.trades(year: 2026, month: 8))
        XCTAssertTrue(CalendarMonthSessionStore.shared.isFresh(year: 2026, month: 8))

        XCTAssertEqual(repo.accountsCallCount, accountsAfterWarm, "Dashboard return must not re-SELECT accounts")
        XCTAssertEqual(repo.historyCallCount, historyAfterWarm, "Trades return must not re-SELECT history")
        XCTAssertEqual(SessionNetworkProbe.networkCount(for: "accounts"), 0)
        // Warm returns may log cache hits only — no NETWORK FETCH events.
        XCTAssertEqual(SessionNetworkProbe.totalNetworkFetches(), 0)
    }

    // MARK: - Helpers

    private func makeTrade(
        id: String,
        profileID: ProfileID,
        pnl: Decimal = 0
    ) -> Trade {
        let now = Date()
        return Trade(
            id: TradeID(id),
            ownerProfileID: profileID,
            accountID: TradingAccountID("dev.settings.personal"),
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 100,
            exitPrice: 101,
            entryAt: now,
            exitAt: now,
            realizedPnL: Money(amount: pnl),
            riskReward: nil,
            points: nil,
            sessionLabel: nil,
            visibility: .private,
            publicCaption: nil,
            thumbnail: nil,
            notePreview: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Condition not met before timeout")
    }
}

// MARK: - Test doubles

private struct FixedSession: SessionProviding {
    let userID: String
    var currentUserID: UserID? {
        get async { UserID(userID) }
    }
    var accessToken: String? { get async { nil } }
}

private final class CountingTradeRepository: TradeRepository, @unchecked Sendable {
    private(set) var accountsCallCount = 0
    private(set) var historyCallCount = 0
    private(set) var monthCallCount = 0
    private let accounts: [TradingAccount]
    private let history: [Trade]
    private let monthTrades: [Trade]
    private let accountsDelayNanoseconds: UInt64

    init(
        accounts: [TradingAccount] = [],
        history: [Trade] = [],
        monthTrades: [Trade] = [],
        accountsDelayNanoseconds: UInt64 = 0
    ) {
        self.accounts = accounts
        self.history = history
        self.monthTrades = monthTrades
        self.accountsDelayNanoseconds = accountsDelayNanoseconds
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
        CursorPage(items: history, nextCursor: nil)
    }

    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        entryFrom: Date,
        entryTo: Date,
        limit: Int
    ) async throws -> [Trade] {
        monthCallCount += 1
        return monthTrades
    }

    func tradeHistory(
        ownedBy profileID: ProfileID,
        query: TradeHistoryQuery,
        page: PageRequest
    ) async throws -> CursorPage<Trade> {
        historyCallCount += 1
        return CursorPage(items: history, nextCursor: nil)
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
        if accountsDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: accountsDelayNanoseconds)
        }
        accountsCallCount += 1
        return accounts.map { account in
            var copy = account
            copy.ownerProfileID = profileID
            return copy
        }
    }
}
