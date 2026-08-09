import XCTest
@testable import TradeTraxs

@MainActor
final class ProfileExperienceTests: XCTestCase {
    func testProfileDisplayInitials() {
        XCTAssertEqual(
            ProfileDisplay.initials(displayName: "Ada Lovelace", username: "ada"),
            "AL"
        )
        XCTAssertEqual(
            ProfileDisplay.initials(displayName: "Trader", username: "nq"),
            "TR"
        )
        XCTAssertEqual(
            ProfileDisplay.initials(displayName: "  ", username: "futures"),
            "FU"
        )
    }

    func testCompactCountFormatting() {
        XCTAssertEqual(ProfileDisplay.compactCount(12), "12")
        XCTAssertEqual(ProfileDisplay.compactCount(1_000), "1K")
        XCTAssertEqual(ProfileDisplay.compactCount(1_250), "1.3K")
        XCTAssertEqual(ProfileDisplay.compactCount(2_400_000), "2.4M")
    }

    func testHeaderMetricsUsePublicTradesAndPlaceholders() {
        let stats = ProfileStats(
            profileID: ProfileID("p1"),
            followerCount: 10,
            followingCount: 3,
            postCount: 4,
            tradeCount: 12,
            publicTradeCount: 8
        )
        let metrics = ProfileDisplay.headerMetrics(from: stats)
        XCTAssertEqual(
            metrics.map(\.id),
            ["posts", "publicTrades", "payouts", "winRate", "profitFactor"]
        )
        XCTAssertEqual(metrics.first(where: { $0.id == "posts" })?.value, "4")
        // Must use publicTradeCount (8), never private-inclusive tradeCount (12).
        XCTAssertEqual(metrics.first(where: { $0.id == "publicTrades" })?.value, "8")
        XCTAssertEqual(metrics.first(where: { $0.id == "payouts" })?.value, ProfileHeaderMetric.placeholderValue)
        XCTAssertEqual(metrics.first(where: { $0.id == "winRate" })?.value, ProfileHeaderMetric.placeholderValue)
        XCTAssertEqual(metrics.first(where: { $0.id == "profitFactor" })?.value, ProfileHeaderMetric.placeholderValue)
    }

    func testHeaderMetricsFormatCachedWinRateAndProfitFactor() {
        let stats = ProfileStats(
            profileID: ProfileID("p1"),
            followerCount: 1,
            followingCount: 1,
            postCount: 0,
            tradeCount: 10,
            publicTradeCount: 5,
            winRate: Decimal(string: "0.625"),
            profitFactor: Decimal(string: "1.85"),
            payoutTotal: Decimal(string: "2500")
        )
        let metrics = ProfileDisplay.headerMetrics(from: stats)
        XCTAssertEqual(metrics.first(where: { $0.id == "payouts" })?.value, "$2,500")
        XCTAssertEqual(metrics.first(where: { $0.id == "winRate" })?.value, "62.5%")
        XCTAssertEqual(metrics.first(where: { $0.id == "profitFactor" })?.value, "1.9")
    }

    func testSocialSummaryFormatting() {
        XCTAssertEqual(
            ProfileDisplay.socialSummary(followers: 128, following: 42),
            "128 Followers • 42 Following"
        )
        XCTAssertEqual(
            ProfileDisplay.socialSummary(followers: 1_250, following: 1_000),
            "1.3K Followers • 1K Following"
        )
    }

    func testTabBarAvatarIsCircularAlwaysOriginal() {
        let side: CGFloat = 28
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let source = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }

        let tab = CurrentUserProfileStore.makeTabBarAvatar(from: source, side: side)
        XCTAssertEqual(tab.renderingMode, .alwaysOriginal)
        XCTAssertEqual(tab.size.width, side, accuracy: 0.5)
        XCTAssertEqual(tab.size.height, side, accuracy: 0.5)
    }

    func testHeaderViewModelFollowRoutesNoOpWithoutProfile() {
        let environment = CompositionRoot.bootstrap()
        let content = ProfileContentStore(
            target: .profile(ProfileID("missing")),
            profiles: environment.data.profiles,
            rooms: environment.data.rooms,
            session: environment.data.session,
            imagePipeline: environment.data.imagePipeline,
            detailCache: environment.data.detailCache
        )
        let viewModel = ProfileHeaderViewModel(
            store: content,
            messages: environment.data.messages,
            session: environment.data.session,
            navigationCoordinator: environment.navigation.coordinator
        )
        viewModel.openFollowers()
        viewModel.openFollowing()
        XCTAssertTrue(environment.navigation.store.paths.profile.isEmpty)
    }

    func testUnifiedProfileContentStoreLoadsOtherUserWithoutOwnerChrome() async {
        let environment = CompositionRoot.bootstrap()
        let otherID = ProfileID("dev.follower.ada")
        let store = ProfileContentStore(
            target: .profile(otherID),
            profiles: environment.data.profiles,
            rooms: environment.data.rooms,
            session: environment.data.session,
            imagePipeline: environment.data.imagePipeline,
            detailCache: environment.data.detailCache
        )
        store.loadIfNeeded()
        let deadline = Date().addingTimeInterval(2)
        while store.phase != .loaded || !store.didResolveTradeRoom, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        guard case .loaded = store.phase else {
            return XCTFail("Expected other profile to load")
        }
        XCTAssertEqual(store.profile?.username, "ada")
        XCTAssertFalse(store.isOwner)
        XCTAssertNotNil(store.stats)
        XCTAssertTrue(store.hasTradeRoom)

        // Session cache hit — second store should not stay in loading.
        let cached = ProfileContentStore(
            target: .profile(otherID),
            profiles: environment.data.profiles,
            rooms: environment.data.rooms,
            session: environment.data.session,
            imagePipeline: environment.data.imagePipeline,
            detailCache: environment.data.detailCache
        )
        cached.loadIfNeeded()
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(cached.phase, .loaded)
        XCTAssertEqual(cached.profile?.id, otherID)
        XCTAssertTrue(cached.hasTradeRoom)
    }

    func testProfileActionModesHideTradeRoomWhenAbsent() async {
        let environment = CompositionRoot.bootstrap()
        let noRoomID = ProfileID("dev.follower.grace")
        let store = ProfileContentStore(
            target: .profile(noRoomID),
            profiles: environment.data.profiles,
            rooms: environment.data.rooms,
            session: environment.data.session,
            imagePipeline: environment.data.imagePipeline,
            detailCache: environment.data.detailCache
        )
        store.loadIfNeeded()
        let deadline = Date().addingTimeInterval(2)
        while store.phase != .loaded || !store.didResolveTradeRoom, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(store.hasTradeRoom)
        XCTAssertFalse(store.canShowVisitorTradeRoomCTA)
        let viewModel = ProfileHeaderViewModel(
            store: store,
            messages: environment.data.messages,
            session: environment.data.session,
            navigationCoordinator: environment.navigation.coordinator
        )
        XCTAssertEqual(
            viewModel.actionMode,
            .visitor(isFollowing: store.isFollowing, showsTradeRoom: false)
        )
    }

    func testVisitorTradeRoomCTAMatchesWebViewParity() async {
        let environment = CompositionRoot.bootstrap()
        let otherID = ProfileID("dev.follower.ada")
        let store = ProfileContentStore(
            target: .profile(otherID),
            profiles: environment.data.profiles,
            rooms: environment.data.rooms,
            session: environment.data.session,
            imagePipeline: environment.data.imagePipeline,
            detailCache: environment.data.detailCache
        )
        store.loadIfNeeded()
        let deadline = Date().addingTimeInterval(2)
        while store.phase != .loaded || !store.didResolveTradeRoom, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(store.hasTradeRoom)
        XCTAssertTrue(store.canShowVisitorTradeRoomCTA)
        let viewModel = ProfileHeaderViewModel(
            store: store,
            messages: environment.data.messages,
            session: environment.data.session,
            navigationCoordinator: environment.navigation.coordinator
        )
        XCTAssertEqual(
            viewModel.actionMode,
            .visitor(isFollowing: store.isFollowing, showsTradeRoom: true)
        )
    }

    func testFollowListViewModelFiltersLocallyAndCachesSession() async {
        let environment = CompositionRoot.bootstrap()
        let owner = ProfileID("dev.follow-list")
        let viewModel = FollowListViewModel(
            kind: .followers,
            listOwnerID: owner,
            profiles: environment.data.profiles,
            session: environment.data.session,
            detailCache: environment.data.detailCache,
            navigationCoordinator: environment.navigation.coordinator
        )

        viewModel.loadIfNeeded()
        let deadline = Date().addingTimeInterval(2)
        while viewModel.phase != .loaded, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        guard case .loaded = viewModel.phase else {
            return XCTFail("Expected loaded follow list")
        }
        XCTAssertFalse(viewModel.items.isEmpty)

        viewModel.searchText = "ada"
        XCTAssertEqual(viewModel.visibleItems.count, 1)
        XCTAssertEqual(viewModel.visibleItems.first?.username, "ada")

        // Second load uses session cache — no phase reset to loading.
        let cached = FollowListViewModel(
            kind: .followers,
            listOwnerID: owner,
            profiles: environment.data.profiles,
            session: environment.data.session,
            detailCache: environment.data.detailCache,
            navigationCoordinator: environment.navigation.coordinator
        )
        cached.loadIfNeeded()
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(cached.phase, .loaded)
        XCTAssertEqual(cached.items.count, viewModel.items.count)

        let target = viewModel.items.first { !$0.isCreator } ?? viewModel.items[0]
        let before = viewModel.isFollowing(target)
        if before {
            viewModel.pendingUnfollow = target
            await viewModel.confirmUnfollow()
            XCTAssertFalse(viewModel.isFollowing(target))
        } else {
            viewModel.toggleFollow(for: target)
            try? await Task.sleep(nanoseconds: 20_000_000)
            XCTAssertTrue(viewModel.isFollowing(target))
        }
    }

    func testProfileMetadataLineMatchesWebShapeAndOmitsEmpties() {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2023
        components.month = 3
        components.day = 1
        let started = calendar.date(from: components)!
        components.year = 2026
        components.month = 8
        let now = calendar.date(from: components)!

        let full = Profile(
            id: ProfileID("p1"),
            userID: UserID("p1"),
            username: "ada",
            displayName: "Ada",
            bio: nil,
            avatar: nil,
            traderType: .futures,
            tradingStyle: "ICT",
            primaryMarket: "NQ",
            startedTradingAt: started,
            isPrivate: false,
            isCreator: true,
            createdAt: now
        )
        XCTAssertEqual(
            ProfileDisplay.metadataLine(for: full, now: now),
            "ICT · Futures · NQ · 3y 5m"
        )

        let partial = Profile(
            id: ProfileID("p2"),
            userID: UserID("p2"),
            username: "bob",
            displayName: "Bob",
            bio: nil,
            avatar: nil,
            traderType: nil,
            tradingStyle: "Scalping",
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: now
        )
        XCTAssertEqual(ProfileDisplay.metadataLine(for: partial, now: now), "Scalping")
        XCTAssertNil(
            ProfileDisplay.metadataLine(
                for: Profile(
                    id: ProfileID("p3"),
                    userID: UserID("p3"),
                    username: "empty",
                    displayName: "Empty",
                    bio: nil,
                    avatar: nil,
                    traderType: nil,
                    tradingStyle: nil,
                    primaryMarket: nil,
                    startedTradingAt: nil,
                    isPrivate: false,
                    isCreator: false,
                    createdAt: now
                ),
                now: now
            )
        )
    }

    func testTraderTypeParsesWebTitleCase() {
        XCTAssertEqual(TraderType.parse("Futures"), .futures)
        XCTAssertEqual(TraderType.parse("Options"), .options)
        XCTAssertEqual(TraderType.parse("Investor"), .investor)
        XCTAssertEqual(TraderType.parse("futures"), .futures)
        XCTAssertNil(TraderType.parse("swing"))
        XCTAssertEqual(TraderType.futures.rawValue, "Futures")
    }

    func testCurrentUserProfileStoreLoadsOnce() async throws {
        let fixture = makeFixture()
        let store = CurrentUserProfileStore(
            profiles: fixture.repository,
            session: fixture.session,
            imagePipeline: fixture.imagePipeline
        )

        store.loadIfNeeded()
        await waitForLoaded(store)
        XCTAssertEqual(store.phase, .loaded)
        XCTAssertEqual(store.profile?.username, "tradetraxs")
        XCTAssertEqual(store.stats?.postCount, 4)
        XCTAssertEqual(store.stats?.followerCount, 10)
        XCTAssertEqual(fixture.repository.profileFetchCount, 1)
        XCTAssertEqual(fixture.repository.statsFetchCount, 1)

        store.loadIfNeeded()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(fixture.repository.profileFetchCount, 1)
        XCTAssertEqual(fixture.repository.statsFetchCount, 1)
    }

    func testCurrentUserProfileStoreClearsOnLogout() async throws {
        let fixture = makeFixture()
        let store = CurrentUserProfileStore(
            profiles: fixture.repository,
            session: fixture.session,
            imagePipeline: fixture.imagePipeline
        )
        store.loadIfNeeded()
        await waitForLoaded(store)
        XCTAssertNotNil(store.profile)

        store.clear()
        XCTAssertEqual(store.phase, .idle)
        XCTAssertNil(store.profile)
        XCTAssertNil(store.stats)
        XCTAssertNil(store.avatarImage)
    }

    func testAvatarFailureFallsBackToInitials() async throws {
        let fixture = makeFixture(avatarURL: "https://example.com/missing.png", imageFails: true)
        let store = CurrentUserProfileStore(
            profiles: fixture.repository,
            session: fixture.session,
            imagePipeline: fixture.imagePipeline
        )
        store.loadIfNeeded()
        await waitForLoaded(store)
        XCTAssertEqual(store.phase, .loaded)
        XCTAssertNil(store.avatarImage)
        XCTAssertEqual(store.initials, "TT")
    }

    func testThemePersistenceIndependentOfProfileClear() async throws {
        let environment = CompositionRoot.bootstrap()
        let before = environment.themeManager.selectedIdentifier
        environment.currentUserProfile.clear()
        XCTAssertEqual(environment.themeManager.selectedIdentifier, before)
    }

    func testProfileShellLazyLoadsOnlySelectedSection() async {
        let environment = CompositionRoot.bootstrap()
        let profileID = ProfileID("dev.shell-test")
        let shell = ProfileShellViewModel(
            profileID: profileID,
            data: environment.data,
            navigationCoordinator: environment.navigation.coordinator
        )

        XCTAssertNil(shell.trades)
        XCTAssertNil(shell.posts)

        shell.activateSelected()
        XCTAssertNotNil(shell.trades)
        XCTAssertNil(shell.posts)
        XCTAssertEqual(shell.selectedSection, .trades)

        shell.select(.posts)
        XCTAssertNotNil(shell.posts)
        XCTAssertNotNil(shell.trades)
        XCTAssertEqual(shell.selectedSection, .posts)

        // Switching back must not recreate the trades ViewModel.
        let tradesRef = ObjectIdentifier(shell.trades!)
        shell.select(.trades)
        XCTAssertEqual(ObjectIdentifier(shell.trades!), tradesRef)
    }

    func testStatsContainerLoadsDevFixturesAndFiltersByMode() async {
        let environment = CompositionRoot.bootstrap()
        let profileID = ProfileID("dev.stats-test")
        let viewModel = StatsContainerViewModel(
            profileID: profileID,
            trades: environment.data.trades,
            achievements: environment.data.achievements,
            detailCache: environment.data.detailCache
        )

        viewModel.loadIfNeeded()
        let deadline = Date().addingTimeInterval(2)
        while viewModel.state == .idle || viewModel.state.isLoading, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        guard case .loaded = viewModel.state else {
            return XCTFail("Expected loaded stats, got \(viewModel.state)")
        }
        XCTAssertNotNil(viewModel.metrics)
        XCTAssertGreaterThan(viewModel.metrics?.filteredTradeCount ?? 0, 0)
        // Web `sumPayoutAchievementTotals` over fixture payout achievements.
        XCTAssertEqual(viewModel.payoutTotal, 2_500)

        let allCount = viewModel.metrics?.filteredTradeCount ?? 0
        viewModel.setMode(.eval)
        XCTAssertLessThanOrEqual(viewModel.metrics?.filteredTradeCount ?? 0, allCount)
        XCTAssertEqual(viewModel.selectedMode, .eval)

        // Stats ViewModel must not be recreated when re-selecting the section.
        let shell = ProfileShellViewModel(
            profileID: profileID,
            data: environment.data,
            navigationCoordinator: environment.navigation.coordinator
        )
        shell.select(.stats)
        let statsRef = ObjectIdentifier(shell.stats!)
        shell.select(.trades)
        shell.select(.stats)
        XCTAssertEqual(ObjectIdentifier(shell.stats!), statsRef)
    }

    func testProfileSectionTitles() {
        XCTAssertEqual(ProfileSection.allCases.count, 5)
        XCTAssertEqual(ProfileSection.clips.title, "Clips")
        XCTAssertEqual(ProfileSection.achievements.title, "Achievements")
    }

    func testProfileSectionSystemImages() {
        XCTAssertEqual(ProfileSection.trades.systemImage, "chart.line.uptrend.xyaxis")
        XCTAssertEqual(ProfileSection.posts.systemImage, "square.grid.2x2")
        XCTAssertEqual(ProfileSection.clips.systemImage, "play.square")
        XCTAssertEqual(ProfileSection.stats.systemImage, "chart.bar.xaxis")
        XCTAssertEqual(ProfileSection.achievements.systemImage, "trophy")
    }

    func testProfileTradesFilterMatchesWebSemantics() {
        let win = makeTrade(pnl: 10)
        let breakEven = makeTrade(pnl: 0)
        let loss = makeTrade(pnl: -5)

        XCTAssertTrue(ProfileTradesFilter.all.matches(win))
        XCTAssertTrue(ProfileTradesFilter.wins.matches(win))
        XCTAssertTrue(ProfileTradesFilter.wins.matches(breakEven))
        XCTAssertFalse(ProfileTradesFilter.wins.matches(loss))
        XCTAssertTrue(ProfileTradesFilter.losses.matches(loss))
        XCTAssertFalse(ProfileTradesFilter.losses.matches(breakEven))
    }

    func testProfileTradesSortOrdersProfitAndRR() {
        let high = makeTrade(id: "h", pnl: 500, rr: 3, createdAtOffset: -100)
        let low = makeTrade(id: "l", pnl: -50, rr: 1, createdAtOffset: -50)
        let mid = makeTrade(id: "m", pnl: 100, rr: nil, createdAtOffset: 0)

        let byProfit = ProfileTradesSort.highestProfit.sorted([low, mid, high])
        XCTAssertEqual(byProfit.map(\.id.rawValue), ["h", "m", "l"])

        let byRR = ProfileTradesSort.highestRR.sorted([mid, low, high])
        XCTAssertEqual(byRR.first?.id.rawValue, "h")
        XCTAssertEqual(byRR.last?.id.rawValue, "m") // null RR last

        let newest = ProfileTradesSort.newest.sorted([high, low, mid])
        XCTAssertEqual(newest.first?.id.rawValue, "m")
    }

    func testTradesContainerLoadsFixturesForDevelopmentProfile() async {
        let environment = CompositionRoot.bootstrap()
        let profileID = ProfileID("dev.trades-test")
        let viewModel = TradesContainerViewModel(
            profileID: profileID,
            trades: environment.data.trades,
            navigationCoordinator: environment.navigation.coordinator,
            detailCache: environment.data.detailCache,
            isOwner: true
        )
        viewModel.loadIfNeeded()
        for _ in 0..<20 {
            if viewModel.state != .idle && viewModel.state != .loading { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(viewModel.items.count, 5)
        viewModel.setFilter(.losses)
        XCTAssertEqual(viewModel.visibleItems.count, 2)
        viewModel.setFilter(.wins)
        XCTAssertEqual(viewModel.visibleItems.count, 3)
    }

    private func makeTrade(
        id: String = "t",
        pnl: Decimal,
        rr: Decimal? = nil,
        createdAtOffset: TimeInterval = 0
    ) -> Trade {
        let date = Date(timeIntervalSince1970: 1_700_000_000 + createdAtOffset)
        return Trade(
            id: TradeID(id),
            ownerProfileID: ProfileID("p1"),
            accountID: nil,
            symbol: Symbol(ticker: "NQ"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 1,
            exitPrice: 2,
            entryAt: date,
            exitAt: date,
            realizedPnL: Money(amount: pnl),
            riskReward: rr,
            points: nil,
            sessionLabel: nil,
            visibility: .public,
            publicCaption: nil,
            thumbnail: nil,
            notePreview: nil,
            createdAt: date,
            updatedAt: date
        )
    }

    // MARK: - Helpers

    private struct Fixture {
        let repository: InMemoryProfileRepository
        let session: StubSessionProvider
        let imagePipeline: StubImagePipeline
    }

    private func makeFixture(
        avatarURL: String? = nil,
        imageFails: Bool = false
    ) -> Fixture {
        let profileID = ProfileID("11111111-1111-1111-1111-111111111111")
        let profile = Profile(
            id: profileID,
            userID: UserID(profileID.rawValue),
            username: "tradetraxs",
            displayName: "Trade Traxs",
            bio: "Journal every trade.",
            avatar: avatarURL.map { MediaReference(id: $0, kind: .image, altText: nil) },
            traderType: .futures,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: true,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let stats = ProfileStats(
            profileID: profileID,
            followerCount: 10,
            followingCount: 3,
            postCount: 4,
            tradeCount: 12,
            publicTradeCount: 8
        )
        return Fixture(
            repository: InMemoryProfileRepository(profile: profile, stats: stats),
            session: StubSessionProvider(userID: UserID(profileID.rawValue)),
            imagePipeline: StubImagePipeline(shouldFail: imageFails)
        )
    }

    private func waitForLoaded(_ store: CurrentUserProfileStore) async {
        for _ in 0..<40 {
            if store.phase == .loaded || store.phase == .failed {
                return
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }
}

// MARK: - Test doubles

private final class InMemoryProfileRepository: ProfileRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let profile: Profile
    private let statsValue: ProfileStats
    private var _profileFetchCount = 0
    private var _statsFetchCount = 0

    var profileFetchCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _profileFetchCount
    }

    var statsFetchCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _statsFetchCount
    }

    init(profile: Profile, stats: ProfileStats) {
        self.profile = profile
        self.statsValue = stats
    }

    func currentUser() async throws -> User {
        User(id: profile.userID, email: nil, createdAt: profile.createdAt)
    }

    func profile(id: ProfileID) async throws -> Profile {
        lock.lock(); _profileFetchCount += 1; lock.unlock()
        guard id == profile.id else {
            throw AppError.domain(.notFound(entity: "profile", id: id.rawValue))
        }
        return profile
    }

    func profile(username: String) async throws -> Profile {
        lock.lock(); _profileFetchCount += 1; lock.unlock()
        guard username == profile.username else {
            throw AppError.domain(.notFound(entity: "profile", id: username))
        }
        return profile
    }

    func updateProfile(_ profile: Profile) async throws -> Profile { profile }

    func stats(for profileID: ProfileID) async throws -> ProfileStats {
        lock.lock(); _statsFetchCount += 1; lock.unlock()
        return statsValue
    }

    func wallPosts(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        CursorPage(items: [], nextCursor: nil)
    }

    func wallPost(id: PostID) async throws -> Post {
        throw AppError.domain(.notFound(entity: "post", id: id.rawValue))
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

private struct StubSessionProvider: SessionProviding {
    let userID: UserID?

    var currentUserID: UserID? {
        get async { userID }
    }

    var accessToken: String? {
        get async { userID == nil ? nil : "test-token" }
    }
}

private struct StubImagePipeline: ImagePipeline {
    let shouldFail: Bool

    func data(for request: ImageRequest) async throws -> Data {
        if shouldFail {
            throw AppError.network(.connectivity)
        }
        // 1x1 PNG
        let pngBase64 =
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO5W7W0AAAAASUVORK5CYII="
        return Data(base64Encoded: pngBase64) ?? Data()
    }

    func prefetch(_ requests: [ImageRequest]) async {}
    func invalidate(reference: MediaReference) async {}
}
