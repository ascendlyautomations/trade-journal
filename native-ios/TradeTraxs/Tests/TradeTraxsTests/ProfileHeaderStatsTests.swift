import XCTest
@testable import TradeTraxs

final class ProfileHeaderStatsTests: XCTestCase {
    func testSessionStubDoesNotCountAsLoadedHeaderMetrics() {
        let stub = ProfileStats(
            profileID: ProfileID("viewer"),
            followerCount: 0,
            followingCount: 5,
            postCount: 0,
            tradeCount: 0,
            publicTradeCount: 0
        )
        XCTAssertFalse(stub.hasLoadedHeaderMetrics)
        let metrics = ProfileDisplay.headerMetrics(from: stub)
        XCTAssertEqual(metrics.first(where: { $0.id == "payouts" })?.value, ProfileHeaderMetric.placeholderValue)
    }

    func testRestStatsWithZeroTradesShowsZeroWinRateNotDash() {
        let overview = ProfileOverviewMetrics.compute(from: [])
        let stats = ProfileStats(
            profileID: ProfileID("p1"),
            followerCount: 1,
            followingCount: 1,
            postCount: 0,
            tradeCount: overview.publicTradeCount,
            publicTradeCount: overview.publicTradeCount,
            winRate: overview.winRate,
            profitFactor: overview.profitFactor,
            payoutTotal: 0
        )
        XCTAssertTrue(stats.hasLoadedHeaderMetrics)
        let metrics = ProfileDisplay.headerMetrics(from: stats)
        XCTAssertEqual(metrics.first(where: { $0.id == "winRate" })?.value, "0%")
        XCTAssertEqual(metrics.first(where: { $0.id == "payouts" })?.value, "$0")
        XCTAssertEqual(metrics.first(where: { $0.id == "publicTrades" })?.value, "0")
    }

    func testLoadedStatsFormatWinRateAndProfitFactor() {
        let stats = ProfileStats(
            profileID: ProfileID("p1"),
            followerCount: 10,
            followingCount: 3,
            postCount: 2,
            tradeCount: 8,
            publicTradeCount: 8,
            winRate: Decimal(string: "0.625"),
            profitFactor: Decimal(string: "1.85"),
            payoutTotal: Decimal(string: "1200")
        )
        let metrics = ProfileDisplay.headerMetrics(from: stats)
        XCTAssertEqual(metrics.first(where: { $0.id == "publicTrades" })?.value, "8")
        XCTAssertEqual(metrics.first(where: { $0.id == "payouts" })?.value, "$1,200")
        XCTAssertEqual(metrics.first(where: { $0.id == "winRate" })?.value, "62.5%")
        XCTAssertEqual(metrics.first(where: { $0.id == "profitFactor" })?.value, "1.9")
    }

    func testTradeMutationAffectsOwnerHeaderMetricsForCreateAndPnLEdit() {
        let owner = ProfileID("owner-metrics-gate")
        var trade = ProfileTradeFixtures.samples(owner: owner)[0]
        XCTAssertTrue(ProfileAnalyticsOwnerInvalidation.affectsOwnerJournalHeaderMetrics(old: nil, new: trade))
        trade.visibility = .private
        XCTAssertTrue(ProfileAnalyticsOwnerInvalidation.affectsOwnerJournalHeaderMetrics(old: nil, new: trade))

        var edited = trade
        edited.realizedPnL = Money(amount: 999)
        XCTAssertTrue(ProfileAnalyticsOwnerInvalidation.affectsOwnerJournalHeaderMetrics(old: trade, new: edited))

        var noteOnly = trade
        noteOnly.notes = "notes-only"
        XCTAssertFalse(ProfileAnalyticsOwnerInvalidation.affectsOwnerJournalHeaderMetrics(old: trade, new: noteOnly))
    }

    @MainActor
    func testOwnerHeaderStatsCoordinatorReconcilesTradeCountWinRateAndProfitFactor() {
        let owner = ProfileID("owner-header-reconcile")
        let cache = DetailPresentationCache()
        defer { SessionOwnerTradesStore.shared.invalidate(profileID: owner) }

        func makeTrade(index: Int, pnl: Decimal) -> Trade {
            var trade = ProfileTradeFixtures.samples(owner: owner)[0]
            trade.id = TradeID("trade-\(index)")
            trade.visibility = .public
            trade.realizedPnL = Money(amount: pnl)
            return trade
        }

        let initial = (0 ..< 9).map { makeTrade(index: $0, pnl: $0 < 5 ? 100 : -50) }
        SessionOwnerTradesStore.shared.seed(initial, for: owner, detailCache: cache)

        let beforeOverview = ProfileOverviewMetrics.overview(fromPublicJournal: initial)
        cache.seed(
            stats: ProfileStats(
                profileID: owner,
                followerCount: 0,
                followingCount: 0,
                postCount: 0,
                tradeCount: beforeOverview.publicTradeCount,
                publicTradeCount: beforeOverview.publicTradeCount,
                winRate: beforeOverview.winRate,
                profitFactor: beforeOverview.profitFactor,
                payoutTotal: nil
            )
        )

        let userStore = CurrentUserProfileStore(
            profiles: ProfileHeaderStatsStubProfiles(),
            session: ProfileHeaderStatsSession(viewerID: owner),
            imagePipeline: PlaceholderImagePipeline(),
            detailCache: cache
        )
        userStore.applyBootstrapResult(
            profile: Profile(
                id: owner,
                userID: UserID(owner.rawValue),
                username: "owner",
                displayName: "Owner",
                bio: nil,
                avatar: nil,
                traderType: .futures,
                tradingStyle: nil,
                primaryMarket: nil,
                startedTradingAt: nil,
                isPrivate: false,
                isCreator: false,
                createdAt: .now
            ),
            stats: cache.stats(for: owner)
        )
        ProfileOwnerHeaderStatsCoordinator.shared.configure(
            detailCache: cache,
            currentUserProfile: userStore,
            profiles: ProfileHeaderStatsStubProfiles()
        )

        let tenth = makeTrade(index: 9, pnl: 200)
        SessionOwnerTradesStore.shared.upsert(tenth, detailCache: cache)
        var allTrades = initial
        allTrades.insert(tenth, at: 0)
        let expected = ProfileOverviewMetrics.overview(fromPublicJournal: allTrades)

        ProfileOwnerHeaderStatsCoordinator.shared.reconcile(ownerID: owner)

        let stats = cache.stats(for: owner)
        XCTAssertEqual(stats?.publicTradeCount, 10)
        XCTAssertEqual(stats?.winRate, expected.winRate)
        XCTAssertEqual(stats?.profitFactor, expected.profitFactor)
        XCTAssertEqual(userStore.stats?.publicTradeCount, 10)
        XCTAssertEqual(userStore.stats?.winRate, expected.winRate)
    }

    @MainActor
    func testPartialStubCannotOverwriteRicherCachedStats() {
        let cache = DetailPresentationCache()
        let profileID = ProfileID("viewer")
        let rich = ProfileStats(
            profileID: profileID,
            followerCount: 12,
            followingCount: 4,
            postCount: 3,
            tradeCount: 5,
            publicTradeCount: 5,
            winRate: Decimal(string: "0.6"),
            profitFactor: Decimal(string: "2.1"),
            payoutTotal: Decimal(string: "500")
        )
        cache.seed(stats: rich)

        let stub = ProfileStats(
            profileID: profileID,
            followerCount: 0,
            followingCount: 9,
            postCount: 0,
            tradeCount: 0,
            publicTradeCount: 0
        )
        cache.seed(stats: stub)

        let cached = cache.stats(for: profileID)
        XCTAssertEqual(cached?.publicTradeCount, 5)
        XCTAssertEqual(cached?.winRate, Decimal(string: "0.6"))
        XCTAssertEqual(cached?.followingCount, 9)
    }
}

private struct ProfileHeaderStatsStubProfiles: ProfileRepository {
    func currentUser() async throws -> User {
        User(id: UserID("owner-header-reconcile"), email: nil, createdAt: .now)
    }

    func profile(id: ProfileID) async throws -> Profile {
        Profile(
            id: id,
            userID: UserID(id.rawValue),
            username: "owner",
            displayName: "Owner",
            bio: nil,
            avatar: nil,
            traderType: .futures,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: .now
        )
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
        throw AppError.domain(.notFound(entity: "post", id: id.rawValue))
    }

    func followState(from viewer: ProfileID, to target: ProfileID) async throws -> FollowState {
        .none
    }

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

private struct ProfileHeaderStatsSession: SessionProviding {
    let viewerID: ProfileID
    var currentUserID: UserID? { get async { UserID(viewerID.rawValue) } }
    var accessToken: String? { get async { nil } }
}
