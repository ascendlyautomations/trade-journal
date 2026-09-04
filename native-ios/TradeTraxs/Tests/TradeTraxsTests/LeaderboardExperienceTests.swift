import XCTest
@testable import TradeTraxs

@MainActor
final class LeaderboardExperienceTests: XCTestCase {
    override func tearDown() async throws {
        LeaderboardSessionStore.shared.invalidate()
        SessionProfileStore.shared.invalidate()
        await LeaderboardTradeRowsCache.shared.invalidate()
        try await super.tearDown()
    }

    func testBootstrapIsSingleFlightAndDoesNotDuplicate() async {
        let repo = MockLeaderboardRepository(trades: sampleTrades())
        let vm = makeViewModel(leaderboard: repo)

        await vm.bootstrapIfNeeded()
        await vm.bootstrapIfNeeded()

        XCTAssertEqual(repo.tradeRowsCallCount, 1)
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.podium.count, 3)
        XCTAssertTrue(vm.state.didBootstrap)
    }

    func testTimeframeChangeDoesNotRefetchTradesButChangesRankings() async {
        let repo = MockLeaderboardRepository(trades: sampleTrades())
        let vm = makeViewModel(leaderboard: repo)
        await vm.bootstrapIfNeeded()
        let afterBootstrap = repo.tradeRowsCallCount

        vm.setTimeframe(.allTime)
        await vm.awaitPendingWork()
        let allTimeTop = vm.rows.first?.profileID

        vm.setTimeframe(.today)
        await vm.awaitPendingWork()

        XCTAssertEqual(repo.tradeRowsCallCount, afterBootstrap, "Timeframe must not refetch trades")
        let todayTop = vm.rows.first?.profileID
        XCTAssertEqual(todayTop, ProfileID("u-mia"))
        XCTAssertNotEqual(allTimeTop, todayTop)
        XCTAssertEqual(allTimeTop, ProfileID("u-old"))
    }

    func testWeekMonthYearAllTimeProduceDifferentFilteredSets() {
        // Mid-year clock so YTD ⊇ Month (web YTD uses NY calendar year start).
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 15))!
        let trades = sampleTrades(now: now)

        let today = LeaderboardTradeWindowFilter.filter(
            trades, window: .custom,
            interval: DateIntervalValue(
                start: Calendar.current.startOfDay(for: now),
                end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
            ),
            now: now
        )
        let week = LeaderboardTradeWindowFilter.filter(trades, window: .sevenDays, interval: nil, now: now)
        let month = LeaderboardTradeWindowFilter.filter(trades, window: .thirtyDays, interval: nil, now: now)
        let year = LeaderboardTradeWindowFilter.filter(trades, window: .yearToDate, interval: nil, now: now)
        let all = LeaderboardTradeWindowFilter.filter(trades, window: .allTime, interval: nil, now: now)

        XCTAssertLessThan(today.count, week.count)
        XCTAssertLessThanOrEqual(week.count, month.count)
        XCTAssertLessThanOrEqual(month.count, year.count)
        XCTAssertLessThanOrEqual(year.count, all.count)
        XCTAssertEqual(all.count, trades.count)

        let todayRank = LeaderboardTradeWindowFilter.buildRankings(from: today).entries
        let allRank = LeaderboardTradeWindowFilter.buildRankings(from: all).entries
        XCTAssertEqual(todayRank.first?.profileID, ProfileID("u-mia"))
        XCTAssertEqual(allRank.first?.profileID, ProfileID("u-old"))
    }

    func testWebViewMappingMatchesLeaderboardChart() {
        XCTAssertEqual(LeaderboardTradeWindowFilter.webView(for: .sevenDays), "7D")
        XCTAssertEqual(LeaderboardTradeWindowFilter.webView(for: .thirtyDays), "30D")
        XCTAssertEqual(LeaderboardTradeWindowFilter.webView(for: .ninetyDays), "90D")
        XCTAssertEqual(LeaderboardTradeWindowFilter.webView(for: .yearToDate), "YTD")
        XCTAssertEqual(LeaderboardTradeWindowFilter.webView(for: .allTime), "ALL")
        XCTAssertEqual(LeaderboardTradeWindowFilter.webView(for: .custom), "Custom")
    }

    func testAudienceFollowingFiltersRowsWithoutRefetch() async {
        let repo = MockLeaderboardRepository(trades: sampleTrades())
        let vm = makeViewModel(leaderboard: repo)
        await vm.bootstrapIfNeeded()
        let callsAfterBootstrap = repo.tradeRowsCallCount

        LeaderboardSessionStore.shared.setFollowing(ProfileID("u-alex"), isFollowing: true)
        LeaderboardSessionStore.shared.setFollowing(ProfileID("u-mia"), isFollowing: true)
        vm.setAudience(.following)

        XCTAssertEqual(repo.tradeRowsCallCount, callsAfterBootstrap)
        XCTAssertTrue(vm.rows.allSatisfy {
            $0.profileID == ProfileID("u-alex")
                || $0.profileID == ProfileID("u-mia")
                || $0.isCurrentUser
        })
    }

    func testRefreshForcesTradeRefetch() async {
        let repo = MockLeaderboardRepository(trades: sampleTrades())
        let vm = makeViewModel(leaderboard: repo)
        await vm.bootstrapIfNeeded()
        await vm.refresh()
        XCTAssertEqual(repo.tradeRowsCallCount, 2)
        XCTAssertEqual(repo.lastForceNetwork, true)
    }

    func testLeaderboardIdentityNeverSurfacesUUID() {
        let profileID = ProfileID("11111111-1111-1111-1111-111111111111")
        let entry = LeaderboardEntry(
            rank: 1,
            profileID: profileID,
            username: "",
            totalPnL: Money(amount: 1_000),
            tradeCount: 3,
            averageRiskReward: 1.2
        )

        let missingProfileState = LeaderboardPresentation.buildState(
            entries: [entry],
            profiles: [:],
            verified: [],
            followers: [:],
            following: [],
            friends: [],
            viewerID: nil,
            audience: .all,
            category: .pnl,
            nextCursor: nil
        )
        let missingRow = missingProfileState.rows.first
        XCTAssertEqual(missingRow?.profile.displayName, "Trader")
        XCTAssertEqual(missingRow?.profile.username, "")
        XCTAssertFalse(LeaderboardRowView.showsUsername(missingRow?.profile.username ?? ""))

        let poisonedProfile = Profile(
            id: profileID,
            userID: UserID(profileID.rawValue),
            username: profileID.rawValue,
            displayName: profileID.rawValue,
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
        let hydratedState = LeaderboardPresentation.buildState(
            entries: [entry],
            profiles: [profileID: poisonedProfile],
            verified: [],
            followers: [:],
            following: [],
            friends: [],
            viewerID: nil,
            audience: .all,
            category: .pnl,
            nextCursor: nil
        )
        let hydratedRow = hydratedState.rows.first
        XCTAssertEqual(hydratedRow?.profile.displayName, "Trader")
        XCTAssertEqual(
            ProfileDisplay.initials(
                displayName: hydratedRow?.profile.displayName ?? "",
                username: hydratedRow?.profile.username ?? ""
            ),
            "TR"
        )

        let namedProfile = Profile(
            id: profileID,
            userID: UserID(profileID.rawValue),
            username: "",
            displayName: "Ada Lovelace",
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
        let namedState = LeaderboardPresentation.buildState(
            entries: [entry],
            profiles: [profileID: namedProfile],
            verified: [],
            followers: [:],
            following: [],
            friends: [],
            viewerID: nil,
            audience: .all,
            category: .pnl,
            nextCursor: nil
        )
        XCTAssertEqual(namedState.rows.first?.profile.displayName, "Ada Lovelace")
    }

    func testPresentationBuildsPodiumAndPinnedViewer() {
        let viewer = ProfileID("viewer-low")
        let now = Date()
        let fmt = ISO8601DateFormatter()
        // Enough higher-ranked traders so viewer rank > 6 (pinned-bar threshold).
        var trades = sampleTrades(now: now)
        for index in 1 ... 8 {
            trades.append(
                LeaderboardTradeRow(
                    userID: "u-filler-\(index)",
                    pnl: Decimal(100 - index),
                    rr: 1,
                    createdAt: fmt.string(from: now.addingTimeInterval(-86_400)),
                    accountType: nil,
                    mode: nil
                )
            )
        }
        trades.append(
            LeaderboardTradeRow(
                userID: viewer.rawValue,
                pnl: 10,
                rr: 1,
                createdAt: fmt.string(from: now.addingTimeInterval(-86_400)),
                accountType: nil,
                mode: nil
            )
        )
        let entries = LeaderboardTradeWindowFilter.entries(
            from: trades,
            window: .allTime,
            interval: nil,
            page: PageRequest(limit: 50),
            now: now
        ).items
        let profiles = Dictionary(uniqueKeysWithValues: entries.map {
            (
                $0.profileID,
                Profile(
                    id: $0.profileID,
                    userID: UserID($0.profileID.rawValue),
                    username: $0.username,
                    displayName: $0.username,
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
            )
        })

        let state = LeaderboardPresentation.buildState(
            entries: entries,
            profiles: profiles,
            verified: [],
            followers: [:],
            following: [],
            friends: [],
            viewerID: viewer,
            audience: .all,
            category: .pnl,
            nextCursor: nil
        )

        XCTAssertEqual(state.podium.map(\.rank), [1, 2, 3])
        XCTAssertEqual(state.pinnedViewer?.profileID, viewer)
    }

    func testTimeframeChangeBatchFetchesNewlyVisibleProfiles() async {
        SessionProfileStore.shared.invalidate()
        LeaderboardSessionStore.shared.invalidate()
        let profiles = CountingBatchProfileRepository(includeAvatars: true)
        let vm = LeaderboardScreenViewModel(
            leaderboard: MockLeaderboardRepository(trades: sampleTrades()),
            profiles: profiles,
            explore: MockLeaderboardExploreRepository(),
            session: MockLeaderboardSession(userID: UserID("viewer")),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )
        await vm.bootstrapIfNeeded()
        let callsAfterBootstrap = profiles.profilesBatchCallCount

        vm.setTimeframe(.allTime)
        await vm.awaitPendingWork()

        XCTAssertEqual(profiles.profilesBatchCallCount, callsAfterBootstrap + 1)
        XCTAssertEqual(vm.rows.first?.profileID, ProfileID("u-old"))
        XCTAssertNotNil(vm.rows.first?.profile.avatar)
        XCTAssertNotNil(vm.podium.first?.profile.avatar)
    }

    func testCategoryResortsAndUpdatesPrimaryMetric() {
        let fmt = ISO8601DateFormatter()
        let now = Date()
        let trades: [LeaderboardTradeRow] = [
            .init(userID: "u-high-pnl", pnl: 10_000, rr: 1.0, createdAt: fmt.string(from: now), accountType: nil, mode: nil),
            .init(userID: "u-high-pnl", pnl: -4_000, rr: 1.0, createdAt: fmt.string(from: now.addingTimeInterval(-60)), accountType: nil, mode: nil),
            .init(userID: "u-high-win", pnl: 200, rr: 1.0, createdAt: fmt.string(from: now.addingTimeInterval(-120)), accountType: nil, mode: nil),
            .init(userID: "u-high-win", pnl: 150, rr: 1.0, createdAt: fmt.string(from: now.addingTimeInterval(-180)), accountType: nil, mode: nil),
            .init(userID: "u-high-win", pnl: 100, rr: 1.0, createdAt: fmt.string(from: now.addingTimeInterval(-240)), accountType: nil, mode: nil),
            .init(userID: "u-high-win", pnl: -50, rr: 1.0, createdAt: fmt.string(from: now.addingTimeInterval(-300)), accountType: nil, mode: nil),
            .init(userID: "u-high-rr", pnl: 500, rr: 4.0, createdAt: fmt.string(from: now.addingTimeInterval(-360)), accountType: nil, mode: nil),
            .init(userID: "u-high-rr", pnl: -100, rr: 3.5, createdAt: fmt.string(from: now.addingTimeInterval(-420)), accountType: nil, mode: nil),
            .init(userID: "u-high-rr", pnl: 500, rr: 3.5, createdAt: fmt.string(from: now.addingTimeInterval(-480)), accountType: nil, mode: nil),
        ]

        let entries = LeaderboardTradeWindowFilter.buildRankings(from: trades).entries
        let profiles = Dictionary(uniqueKeysWithValues: entries.map {
            (
                $0.profileID,
                Profile(
                    id: $0.profileID,
                    userID: UserID($0.profileID.rawValue),
                    username: $0.profileID.rawValue,
                    displayName: $0.profileID.rawValue,
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
            )
        })

        let pnlState = LeaderboardPresentation.buildState(
            entries: entries,
            profiles: profiles,
            verified: [],
            followers: [:],
            following: [],
            friends: [],
            viewerID: nil,
            audience: .all,
            category: .pnl,
            nextCursor: nil
        )
        XCTAssertEqual(pnlState.rows.first?.profileID, ProfileID("u-high-pnl"))
        XCTAssertTrue(pnlState.rows.first?.primaryMetricText.hasPrefix("+") == true)

        let winRateState = LeaderboardPresentation.buildState(
            entries: entries,
            profiles: profiles,
            verified: [],
            followers: [:],
            following: [],
            friends: [],
            viewerID: nil,
            audience: .all,
            category: .winRate,
            nextCursor: nil
        )
        XCTAssertEqual(winRateState.rows.first?.profileID, ProfileID("u-high-win"))
        XCTAssertEqual(winRateState.rows.first?.primaryMetricText, "75.0%")

        let rrState = LeaderboardPresentation.buildState(
            entries: entries,
            profiles: profiles,
            verified: [],
            followers: [:],
            following: [],
            friends: [],
            viewerID: nil,
            audience: .all,
            category: .rr,
            nextCursor: nil
        )
        XCTAssertEqual(rrState.rows.first?.profileID, ProfileID("u-high-rr"))
        XCTAssertEqual(rrState.rows.first?.primaryMetricText, "3.67")
    }

    func testProfitFactorSortsUnavailableBelowCalculableValues() {
        let entries: [LeaderboardEntry] = [
            LeaderboardEntry(
                rank: 1,
                profileID: ProfileID("u-no-losses"),
                username: "",
                totalPnL: Money(amount: 50_000),
                tradeCount: 5,
                averageRiskReward: 2,
                profitFactor: nil
            ),
            LeaderboardEntry(
                rank: 2,
                profileID: ProfileID("u-strong-pf"),
                username: "",
                totalPnL: Money(amount: 500),
                tradeCount: 4,
                averageRiskReward: 1.5,
                profitFactor: Decimal(string: "2.50")
            ),
            LeaderboardEntry(
                rank: 3,
                profileID: ProfileID("u-weak-pf"),
                username: "",
                totalPnL: Money(amount: 200),
                tradeCount: 3,
                averageRiskReward: 1.2,
                profitFactor: Decimal(string: "1.10")
            ),
        ]
        let profiles = Dictionary(uniqueKeysWithValues: entries.map {
            (
                $0.profileID,
                Profile(
                    id: $0.profileID,
                    userID: UserID($0.profileID.rawValue),
                    username: $0.profileID.rawValue,
                    displayName: $0.profileID.rawValue,
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
            )
        })

        let state = LeaderboardPresentation.buildState(
            entries: entries,
            profiles: profiles,
            verified: [],
            followers: [:],
            following: [],
            friends: [],
            viewerID: nil,
            audience: .all,
            category: .profitFactor,
            nextCursor: nil
        )

        XCTAssertEqual(state.rows.first?.profileID, ProfileID("u-strong-pf"))
        XCTAssertEqual(state.rows[1].profileID, ProfileID("u-weak-pf"))
        XCTAssertEqual(state.rows.last?.profileID, ProfileID("u-no-losses"))
        XCTAssertEqual(state.rows.last?.primaryMetricText, "—")
        XCTAssertEqual(state.podium.first?.profileID, ProfileID("u-strong-pf"))
        XCTAssertEqual(state.podium.last?.profileID, ProfileID("u-no-losses"))
        XCTAssertEqual(state.podium.last?.primaryMetricText, "—")
    }

    func testUserStatsAggregationComputesDerivedMetrics() {
        let fmt = ISO8601DateFormatter()
        let now = Date()
        let stats = LeaderboardUserStatsAggregator.aggregate(trades: [
            .init(userID: "u1", pnl: 100, rr: 2, createdAt: fmt.string(from: now.addingTimeInterval(-400)), accountType: nil, mode: nil),
            .init(userID: "u1", pnl: 200, rr: 2, createdAt: fmt.string(from: now.addingTimeInterval(-300)), accountType: nil, mode: nil),
            .init(userID: "u1", pnl: -50, rr: 1, createdAt: fmt.string(from: now.addingTimeInterval(-200)), accountType: nil, mode: nil),
            .init(userID: "u1", pnl: 300, rr: 3, createdAt: fmt.string(from: now.addingTimeInterval(-100)), accountType: nil, mode: nil),
        ])

        XCTAssertEqual(stats.tradeCount, 4)
        XCTAssertEqual(stats.totalPnL, 550)
        XCTAssertEqual(stats.winStreak, 2)
        XCTAssertEqual(stats.winRate, Decimal(3) / Decimal(4))
        XCTAssertEqual(stats.profitFactor, Decimal(12))
        XCTAssertEqual(stats.averageRiskReward, Decimal(2))
    }

    func testBootstrapUsesOneProfileBatchNotPerRow() async {
        SessionProfileStore.shared.invalidate()
        LeaderboardSessionStore.shared.invalidate()
        await LeaderboardTradeRowsCache.shared.invalidate()
        let repo = MockLeaderboardRepository(trades: sampleTrades())
        let profiles = CountingBatchProfileRepository()
        let cache = DetailPresentationCache()
        let vm = LeaderboardScreenViewModel(
            leaderboard: repo,
            profiles: profiles,
            explore: MockLeaderboardExploreRepository(),
            session: MockLeaderboardSession(userID: UserID("viewer")),
            detailCache: cache,
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )
        await vm.bootstrapIfNeeded()
        await vm.awaitPendingWork()
        XCTAssertGreaterThanOrEqual(profiles.profilesBatchCallCount, 1, "Profiles must batch-fetch, not loop per row")
        XCTAssertLessThanOrEqual(profiles.profilesBatchCallCount, 2, "Bootstrap + visible hydration may coalesce to at most two batches")
        XCTAssertEqual(profiles.profileSingleCallCount, 0)
    }

    func testBootstrapRefetchesWhenCacheHasIdentityWithoutAvatar() async {
        SessionProfileStore.shared.invalidate()
        LeaderboardSessionStore.shared.invalidate()
        let cache = DetailPresentationCache()
        let profileID = ProfileID("u-mia")
        cache.seed(
            Profile(
                id: profileID,
                userID: UserID(profileID.rawValue),
                username: "mia",
                displayName: "Mia",
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
        )

        let profiles = CountingBatchProfileRepository(includeAvatars: true)
        let vm = LeaderboardScreenViewModel(
            leaderboard: MockLeaderboardRepository(trades: sampleTrades()),
            profiles: profiles,
            explore: MockLeaderboardExploreRepository(),
            session: MockLeaderboardSession(userID: UserID("viewer")),
            detailCache: cache,
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )
        await vm.bootstrapIfNeeded()

        XCTAssertEqual(profiles.profilesBatchCallCount, 1)
        let row = vm.rows.first { $0.profileID == profileID }
        XCTAssertNotNil(row?.profile.avatar)
        XCTAssertEqual(
            ProfileAvatarSourceKind.classify(reference: row?.profile.avatar),
            .fullURL
        )
    }

    // MARK: - Helpers

    private func makeViewModel(leaderboard: MockLeaderboardRepository) -> LeaderboardScreenViewModel {
        LeaderboardScreenViewModel(
            leaderboard: leaderboard,
            profiles: MockLeaderboardProfileRepository(),
            explore: MockLeaderboardExploreRepository(),
            session: MockLeaderboardSession(userID: UserID("viewer")),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )
    }

    /// Mia wins today; u-old wins all-time.
    private func sampleTrades(now: Date = Date()) -> [LeaderboardTradeRow] {
        let fmt = ISO8601DateFormatter()
        return [
            .init(userID: "u-mia", pnl: 9_000, rr: 2, createdAt: fmt.string(from: now.addingTimeInterval(-3_600)), accountType: nil, mode: nil),
            .init(userID: "u-alex", pnl: 1_000, rr: 2, createdAt: fmt.string(from: now.addingTimeInterval(-86_400 * 2)), accountType: nil, mode: nil),
            .init(userID: "u-alex", pnl: 8_000, rr: 2, createdAt: fmt.string(from: now.addingTimeInterval(-86_400 * 20)), accountType: nil, mode: nil),
            .init(userID: "u-sam", pnl: 5_000, rr: 1.5, createdAt: fmt.string(from: now.addingTimeInterval(-86_400 * 10)), accountType: nil, mode: nil),
            .init(userID: "u-old", pnl: 50_000, rr: 3, createdAt: fmt.string(from: now.addingTimeInterval(-86_400 * 400)), accountType: nil, mode: nil),
        ]
    }
}

// MARK: - Mocks

private final class MockLeaderboardRepository: LeaderboardRepository, @unchecked Sendable {
    var trades: [LeaderboardTradeRow]
    private(set) var tradeRowsCallCount = 0
    private(set) var lastForceNetwork: Bool?

    init(trades: [LeaderboardTradeRow]) {
        self.trades = trades
    }

    func tradeRows(forceNetwork: Bool) async throws -> [LeaderboardTradeRow] {
        tradeRowsCallCount += 1
        lastForceNetwork = forceNetwork
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

private final class CountingBatchProfileRepository: ProfileRepository, @unchecked Sendable {
    private(set) var profilesBatchCallCount = 0
    private(set) var profileSingleCallCount = 0
    private let includeAvatars: Bool

    init(includeAvatars: Bool = false) {
        self.includeAvatars = includeAvatars
    }

    func currentUser() async throws -> User {
        User(id: UserID("viewer"), email: nil, createdAt: .now)
    }

    func profile(id: ProfileID) async throws -> Profile {
        profileSingleCallCount += 1
        return makeProfile(id: id)
    }

    func profiles(ids: [ProfileID]) async throws -> [Profile] {
        profilesBatchCallCount += 1
        return ids.map { makeProfile(id: $0) }
    }

    func profile(username: String) async throws -> Profile {
        try await profile(id: ProfileID(username))
    }

    func updateProfile(_ profile: Profile) async throws -> Profile { profile }

    func stats(for profileID: ProfileID) async throws -> ProfileStats {
        ProfileStats(
            profileID: profileID,
            followerCount: 0,
            followingCount: 0,
            postCount: 0,
            tradeCount: 0,
            publicTradeCount: 0
        )
    }

    func wallPosts(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        CursorPage(items: [], nextCursor: nil)
    }

    func wallPost(id: PostID) async throws -> Post {
        throw AppError.notImplemented(feature: "wallPost")
    }

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

    private func makeProfile(id: ProfileID) -> Profile {
        let avatar: MediaReference? = includeAvatars
            ? MediaReference(
                id: "https://cdn.example/avatars/\(id.rawValue).jpg",
                kind: .image,
                altText: nil
            )
            : nil
        return Profile(
            id: id,
            userID: UserID(id.rawValue),
            username: "trader_\(id.rawValue)",
            displayName: "Trader \(id.rawValue)",
            bio: nil,
            avatar: avatar,
            traderType: nil,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: .now
        )
    }
}

private struct MockLeaderboardProfileRepository: ProfileRepository {
    func currentUser() async throws -> User {
        User(id: UserID("viewer"), email: nil, createdAt: .now)
    }

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

    func profiles(ids: [ProfileID]) async throws -> [Profile] {
        try await ids.asyncMap { try await profile(id: $0) }
    }

    func profile(username: String) async throws -> Profile {
        try await profile(id: ProfileID(username))
    }

    func updateProfile(_ profile: Profile) async throws -> Profile { profile }

    func stats(for profileID: ProfileID) async throws -> ProfileStats {
        ProfileStats(
            profileID: profileID,
            followerCount: 0,
            followingCount: 0,
            postCount: 0,
            tradeCount: 0,
            publicTradeCount: 0
        )
    }

    func wallPosts(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        CursorPage(items: [], nextCursor: nil)
    }

    func wallPost(id: PostID) async throws -> Post {
        throw AppError.notImplemented(feature: "wallPost")
    }

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

private struct MockLeaderboardExploreRepository: ExploreRepository {
    func discoverableProfiles(page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }

    func socialCounts(for profileIDs: [ProfileID]) async throws -> ExploreSocialCounts { .empty }
    func tradeActivitySummaries(limit: Int) async throws -> [ProfileID: ExploreTraderRanking.TradeSummary] { [:] }
    func popularRooms(limit: Int) async throws -> [ExploreRoomSuggestion] { [] }
    func searchRooms(query: String, limit: Int) async throws -> [ExploreRoomSuggestion] { [] }
}

private struct MockLeaderboardSession: SessionProviding {
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
