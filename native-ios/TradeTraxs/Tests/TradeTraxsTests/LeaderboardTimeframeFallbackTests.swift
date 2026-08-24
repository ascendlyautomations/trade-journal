import XCTest
@testable import TradeTraxs

final class LeaderboardTimeframeFallbackTests: XCTestCase {
    private let now = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return calendar.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 15))!
    }()

    func testPresetOrderMatchesCrossPlatformMapping() {
        XCTAssertEqual(
            LeaderboardTimeframeFallback.presetOrder.map(\.rawValue),
            ["today", "week", "month", "year", "allTime"]
        )
        XCTAssertEqual(LeaderboardTimeframeFallback.webViewID(for: .week), "7D")
        XCTAssertEqual(LeaderboardTimeframeFallback.webViewID(for: .month), "30D")
        XCTAssertEqual(LeaderboardTimeframeFallback.webViewID(for: .year), "YTD")
        XCTAssertEqual(LeaderboardTimeframeFallback.webViewID(for: .allTime), "ALL")
    }

    func testNextLargerNeverMovesSmallerOrLoops() {
        XCTAssertEqual(LeaderboardTimeframeFallback.nextLarger(.today), .week)
        XCTAssertEqual(LeaderboardTimeframeFallback.nextLarger(.week), .month)
        XCTAssertEqual(LeaderboardTimeframeFallback.nextLarger(.month), .year)
        XCTAssertEqual(LeaderboardTimeframeFallback.nextLarger(.year), .allTime)
        XCTAssertNil(LeaderboardTimeframeFallback.nextLarger(.allTime))
    }

    func testSelectedTimeframeWithDataStaysPut() {
        let trades = sampleTrades()
        let resolved = LeaderboardTimeframeFallback.resolveWindow(
            trades: trades,
            requested: .week,
            now: now
        )
        XCTAssertEqual(resolved.resolution.effective, .week)
        XCTAssertFalse(resolved.resolution.usedFallback)
        XCTAssertFalse(resolved.entries.isEmpty)
    }

    func testEmptyTodayFallsForwardToAllTime() {
        let onlyOld = [
            makeTrade(userID: "u-old", pnl: 50_000, daysAgo: 400),
        ]
        let resolved = LeaderboardTimeframeFallback.resolveWindow(
            trades: onlyOld,
            requested: .today,
            now: now
        )
        XCTAssertEqual(resolved.resolution.effective, .allTime)
        XCTAssertTrue(resolved.resolution.usedFallback)
    }

    func testAllTimeEmptyIsGenuineEmpty() {
        let resolved = LeaderboardTimeframeFallback.resolveWindow(
            trades: [],
            requested: .allTime,
            now: now
        )
        XCTAssertEqual(resolved.resolution.effective, .allTime)
        XCTAssertTrue(resolved.entries.isEmpty)
        XCTAssertFalse(resolved.resolution.usedFallback)
    }

    @MainActor
    override func tearDown() async throws {
        LeaderboardSessionStore.shared.invalidate()
        await LeaderboardTradeRowsCache.shared.invalidate()
        try await super.tearDown()
    }

    @MainActor
    func testViewModelFallbackDoesNotRefetchTrades() async {
        LeaderboardSessionStore.shared.invalidate()
        let repo = MockFallbackLeaderboardRepository(trades: [
            makeTrade(userID: "u-old", pnl: 50_000, daysAgo: 400),
        ])
        let vm = makeViewModel(leaderboard: repo)
        await vm.bootstrapIfNeeded()
        let afterBootstrap = repo.tradeRowsCallCount

        vm.setTimeframe(.today)
        await vm.awaitPendingWork()

        XCTAssertEqual(repo.tradeRowsCallCount, afterBootstrap)
        XCTAssertEqual(vm.timeframe, .allTime)
        XCTAssertNotNil(vm.timeframeFallbackMessage)
        XCTAssertFalse(vm.rows.isEmpty)
    }

    @MainActor
    func testNetworkFailureDoesNotApplyFallback() async {
        LeaderboardSessionStore.shared.invalidate()
        let repo = MockFallbackLeaderboardRepository(trades: [], shouldFail: true)
        let vm = makeViewModel(leaderboard: repo)
        await vm.bootstrapIfNeeded()
        if case .failed = vm.phase {
            // expected
        } else {
            XCTFail("Expected failed phase")
        }
        XCTAssertTrue(vm.rows.isEmpty)
    }

    // MARK: - Helpers

    private func sampleTrades() -> [LeaderboardTradeRow] {
        [
            makeTrade(userID: "u-mia", pnl: 9_000, daysAgo: 0),
            makeTrade(userID: "u-alex", pnl: 1_000, daysAgo: 2),
            makeTrade(userID: "u-old", pnl: 50_000, daysAgo: 400),
        ]
    }

    private func makeTrade(userID: String, pnl: Decimal, daysAgo: Int) -> LeaderboardTradeRow {
        let fmt = ISO8601DateFormatter()
        let created = now.addingTimeInterval(TimeInterval(-daysAgo * 86_400))
        return LeaderboardTradeRow(
            userID: userID,
            pnl: pnl,
            rr: 1,
            createdAt: fmt.string(from: created),
            accountType: nil,
            mode: nil
        )
    }

    @MainActor
    private func makeViewModel(leaderboard: MockFallbackLeaderboardRepository) -> LeaderboardScreenViewModel {
        LeaderboardScreenViewModel(
            leaderboard: leaderboard,
            profiles: MockFallbackProfileRepository(),
            explore: MockFallbackExploreRepository(),
            session: MockFallbackSession(userID: UserID("viewer")),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )
    }
}

private final class MockFallbackLeaderboardRepository: LeaderboardRepository, @unchecked Sendable {
    var trades: [LeaderboardTradeRow]
    var shouldFail: Bool
    private(set) var tradeRowsCallCount = 0

    init(trades: [LeaderboardTradeRow], shouldFail: Bool = false) {
        self.trades = trades
        self.shouldFail = shouldFail
    }

    func tradeRows(forceNetwork: Bool) async throws -> [LeaderboardTradeRow] {
        tradeRowsCallCount += 1
        if shouldFail { throw NetworkError.connectivity }
        return trades
    }

    func entries(
        window: LeaderboardWindow,
        interval: DateIntervalValue?,
        page: PageRequest
    ) async throws -> CursorPage<LeaderboardEntry> {
        let rows = try await tradeRows(forceNetwork: false)
        return LeaderboardTradeWindowFilter.entries(
            from: rows,
            window: window,
            interval: interval,
            page: page
        )
    }
}

private struct MockFallbackProfileRepository: ProfileRepository {
    func currentUser() async throws -> User { User(id: UserID("viewer"), email: nil, createdAt: .now) }
    func profile(id: ProfileID) async throws -> Profile {
        Profile(
            id: id,
            userID: UserID(id.rawValue),
            username: id.rawValue,
            displayName: id.rawValue,
            bio: nil,
            avatar: nil,
            traderType: nil,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: .now
        )
    }
    func profiles(ids: [ProfileID]) async throws -> [Profile] { try await ids.asyncMap { try await profile(id: $0) } }
    func profile(username: String) async throws -> Profile { try await profile(id: ProfileID(username)) }
    func updateProfile(_ profile: Profile) async throws -> Profile { profile }
    func stats(for profileID: ProfileID) async throws -> ProfileStats {
        ProfileStats(profileID: profileID, followerCount: 0, followingCount: 0, postCount: 0, tradeCount: 0, publicTradeCount: 0)
    }
    func wallPosts(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        CursorPage(items: [], nextCursor: nil)
    }
    func wallPost(id: PostID) async throws -> Post { throw AppError.notImplemented(feature: "wallPost") }
    func followState(from viewer: ProfileID, to target: ProfileID) async throws -> FollowState { .none }
    func follow(from viewer: ProfileID, to target: ProfileID) async throws {}
    func unfollow(from viewer: ProfileID, to target: ProfileID) async throws {}
    func followers(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }
    func following(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }
    func creator(for profileID: ProfileID) async throws -> Creator? { nil }
}

private struct MockFallbackExploreRepository: ExploreRepository {
    func discoverableProfiles(page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }
    func socialCounts(for profileIDs: [ProfileID]) async throws -> ExploreSocialCounts { .empty }
    func tradeActivitySummaries(limit: Int) async throws -> [ProfileID: ExploreTraderRanking.TradeSummary] { [:] }
    func popularRooms(limit: Int) async throws -> [ExploreRoomSuggestion] { [] }
    func searchRooms(query: String, limit: Int) async throws -> [ExploreRoomSuggestion] { [] }
}

private struct MockFallbackSession: SessionProviding {
    let userID: UserID?
    var currentUserID: UserID? { get async { userID } }
    var accessToken: String? { get async { nil } }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        result.reserveCapacity(count)
        for element in self {
            result.append(try await transform(element))
        }
        return result
    }
}
