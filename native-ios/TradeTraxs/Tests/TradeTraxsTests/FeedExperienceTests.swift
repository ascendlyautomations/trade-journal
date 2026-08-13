import XCTest
@testable import TradeTraxs

@MainActor
final class FeedExperienceTests: XCTestCase {
    func testFixturesIncludeAllContentKindsSortedDescending() {
        let entries = FeedFixtures.timeline()
        XCTAssertFalse(entries.isEmpty)
        XCTAssertTrue(entries.contains { if case .trade = $0 { return true }; return false })
        XCTAssertTrue(entries.contains { if case .post = $0 { return true }; return false })
        XCTAssertTrue(entries.contains { if case .clip = $0 { return true }; return false })
        XCTAssertTrue(entries.contains { if case .achievement = $0 { return true }; return false })

        let dates = entries.map(\.createdAt)
        XCTAssertEqual(dates, dates.sorted(by: >))
    }

    func testContentFilterMatchesKinds() {
        let entries = FeedFixtures.timeline()
        XCTAssertEqual(entries.filter { $0.matches(filter: .all) }.count, entries.count)
        XCTAssertFalse(entries.filter { $0.matches(filter: .trades) }.isEmpty)
        XCTAssertFalse(entries.filter { $0.matches(filter: .posts) }.isEmpty)
        XCTAssertFalse(entries.filter { $0.matches(filter: .clips) }.isEmpty)
        XCTAssertFalse(entries.filter { $0.matches(filter: .achievements) }.isEmpty)
        XCTAssertTrue(entries.filter { $0.matches(filter: .trades) }.allSatisfy {
            if case .trade = $0 { return true }
            return false
        })
    }

    func testContentFilterUsesCompactSFSymbols() {
        XCTAssertEqual(FeedContentFilter.all.icon.systemName, "circle.grid.2x2.fill")
        XCTAssertEqual(FeedContentFilter.trades.icon.systemName, "chart.line.uptrend.xyaxis")
        XCTAssertEqual(FeedContentFilter.posts.icon.systemName, "text.bubble")
        XCTAssertEqual(FeedContentFilter.clips.icon.systemName, "play.rectangle")
        XCTAssertEqual(FeedContentFilter.achievements.icon.systemName, "trophy")
    }

    func testFeedRowsSplitMediaVersusTextLayouts() {
        let entries = FeedFixtures.timeline()
        XCTAssertTrue(entries.contains { $0.hasDisplayMedia })
        XCTAssertTrue(entries.contains { !$0.hasDisplayMedia })
        XCTAssertTrue(entries.contains {
            guard case .post(_, let post) = $0 else { return false }
            return post.media.isEmpty && !$0.hasDisplayMedia
        })
    }

    func testViewModelLoadsLocalFixturesAndFilters() async {
        let cache = DetailPresentationCache()
        let engagement = EngagementStore(repository: FeedStubInteractionRepository())
        let navigationStore = NavigationStore()
        let coordinator = NavigationCoordinator(store: navigationStore)
        let viewModel = FeedViewModel(
            feed: FeedStubFeedRepository(),
            trades: FeedStubTradeRepository(),
            profiles: FeedStubProfileRepository(),
            achievements: FeedStubAchievementRepository(),
            session: FeedStubSession(userID: FeedFixtures.viewerID.rawValue),
            detailCache: cache,
            engagementStore: engagement,
            navigationCoordinator: coordinator
        )

        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }

        XCTAssertFalse(viewModel.entries.isEmpty)
        XCTAssertFalse(viewModel.visibleEntries.isEmpty)
        XCTAssertFalse(viewModel.stories.isEmpty)

        viewModel.setContentFilter(.clips)
        XCTAssertTrue(viewModel.visibleEntries.allSatisfy {
            if case .clip = $0 { return true }
            return false
        })

        viewModel.setContentFilter(.trades)
        XCTAssertFalse(viewModel.visibleEntries.isEmpty)
        // Authenticate so NavigationCoordinator will accept feed pushes.
        navigationStore.sessionPhase = .authenticated
        viewModel.open(viewModel.visibleEntries[0])
        XCTAssertFalse(navigationStore.paths.feed.isEmpty)
    }

    func testAuthorsResolvedFromCacheWithoutProfileRepository() async {
        let cache = DetailPresentationCache()
        let engagement = EngagementStore(repository: FeedStubInteractionRepository())
        let navigationStore = NavigationStore()
        let coordinator = NavigationCoordinator(store: navigationStore)
        let profiles = FeedCountingProfileRepository()
        let viewModel = FeedViewModel(
            feed: FeedStubFeedRepository(),
            trades: FeedStubTradeRepository(),
            profiles: profiles,
            achievements: FeedStubAchievementRepository(),
            session: FeedStubSession(userID: FeedFixtures.viewerID.rawValue),
            detailCache: cache,
            engagementStore: engagement,
            navigationCoordinator: coordinator
        )

        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }

        XCTAssertEqual(profiles.profileCallCount, 0)
        for entry in viewModel.entries {
            let author = viewModel.author(for: entry.authorProfileID)
            XCTAssertNotNil(author)
            XCTAssertNotNil(author?.avatar)
        }
    }

    func testOpenStoryPresentsFullScreenViewer() async throws {
        let cache = DetailPresentationCache()
        let engagement = EngagementStore(repository: FeedStubInteractionRepository())
        let navigationStore = NavigationStore()
        let coordinator = NavigationCoordinator(store: navigationStore)
        let viewModel = FeedViewModel(
            feed: FeedStubFeedRepository(),
            trades: FeedStubTradeRepository(),
            profiles: FeedStubProfileRepository(),
            achievements: FeedStubAchievementRepository(),
            session: FeedStubSession(userID: FeedFixtures.viewerID.rawValue),
            detailCache: cache,
            engagementStore: engagement,
            navigationCoordinator: coordinator
        )

        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }
        navigationStore.sessionPhase = .authenticated

        let story = try XCTUnwrap(viewModel.stories.first)
        viewModel.openStory(story)
        XCTAssertEqual(navigationStore.presentedFullScreen, .storyViewer(story.id))
        XCTAssertNotNil(cache.story(id: story.id))
    }

    func testStoryFixturesIncludeUnreadRingState() {
        let stories = FeedFixtures.stories()
        XCTAssertGreaterThanOrEqual(stories.count, 3)
        XCTAssertTrue(stories.contains { !$0.viewerHasSeen })
        XCTAssertTrue(stories.contains { $0.viewerHasSeen })
    }

    func testActiveStorySemanticsMatchesWeb24HourWindow() {
        let now = Date()
        let fresh = Story(
            id: StoryID("s1"),
            authorProfileID: ProfileID("a"),
            media: MediaReference(id: "https://example.com/a.jpg", kind: .image, altText: nil),
            expiresAt: now.addingTimeInterval(3_600),
            createdAt: now.addingTimeInterval(-3_600),
            viewerHasSeen: false
        )
        let expired = Story(
            id: StoryID("s2"),
            authorProfileID: ProfileID("b"),
            media: MediaReference(id: "https://example.com/b.jpg", kind: .image, altText: nil),
            expiresAt: now,
            createdAt: now.addingTimeInterval(-86_400),
            viewerHasSeen: false
        )
        XCTAssertTrue(ActiveStorySemantics.isActive(createdAt: fresh.createdAt, now: now))
        XCTAssertFalse(ActiveStorySemantics.isActive(createdAt: expired.createdAt, now: now))
        let active = ActiveStorySemantics.filterActive([fresh, expired], now: now)
        XCTAssertEqual(active.map(\.id), [fresh.id])
    }

    func testActiveStoryStripGroupsByAuthorNewestFirst() {
        let now = Date()
        let viewer = ProfileID("viewer")
        let olderMine = Story(
            id: StoryID("mine-old"),
            authorProfileID: viewer,
            media: MediaReference(id: "m1", kind: .image, altText: nil),
            expiresAt: now.addingTimeInterval(86_400),
            createdAt: now.addingTimeInterval(-2_000),
            viewerHasSeen: false
        )
        let newerMine = Story(
            id: StoryID("mine-new"),
            authorProfileID: viewer,
            media: MediaReference(id: "m2", kind: .image, altText: nil),
            expiresAt: now.addingTimeInterval(86_400),
            createdAt: now.addingTimeInterval(-100),
            viewerHasSeen: false
        )
        let other = Story(
            id: StoryID("other"),
            authorProfileID: ProfileID("other"),
            media: MediaReference(id: "o1", kind: .image, altText: nil),
            expiresAt: now.addingTimeInterval(86_400),
            createdAt: now.addingTimeInterval(-500),
            viewerHasSeen: false
        )
        let strip = ActiveStorySemantics.stripStories(
            from: [olderMine, other, newerMine],
            viewerID: viewer
        )
        XCTAssertEqual(strip.map(\.id.rawValue), ["mine-new", "other"])
    }

    func testScopeAndContentFilterRemainIndependent() async {
        let cache = DetailPresentationCache()
        let engagement = EngagementStore(repository: FeedStubInteractionRepository())
        let navigationStore = NavigationStore()
        let coordinator = NavigationCoordinator(store: navigationStore)
        let viewModel = FeedViewModel(
            feed: FeedStubFeedRepository(),
            trades: FeedStubTradeRepository(),
            profiles: FeedStubProfileRepository(),
            achievements: FeedStubAchievementRepository(),
            session: FeedStubSession(userID: FeedFixtures.viewerID.rawValue),
            detailCache: cache,
            engagementStore: engagement,
            navigationCoordinator: coordinator
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }
        XCTAssertEqual(viewModel.scope, .following)
        viewModel.setScope(.global)
        XCTAssertEqual(viewModel.scope, .global)
        viewModel.setContentFilter(.posts)
        XCTAssertEqual(viewModel.contentFilter, .posts)
        XCTAssertTrue(viewModel.visibleEntries.allSatisfy {
            if case .post = $0 { return true }
            return false
        })
    }

    /// Production path (non-`dev.` session) — hydrate from web-shaped FeedItems with profiles embed.
    func testProductionFeedHydratesAuthorsAndAllContentKindsWithoutProfileNPlusOne() async throws {
        let cache = DetailPresentationCache()
        let engagement = EngagementStore(repository: FeedStubInteractionRepository())
        let navigationStore = NavigationStore()
        let coordinator = NavigationCoordinator(store: navigationStore)
        let profiles = FeedCountingProfileRepository()
        let viewerUUID = "e432738b-47bd-439b-9c2a-0a7236a3feed"
        let viewModel = FeedViewModel(
            feed: FeedWebShapedStubFeedRepository(),
            trades: FeedStubTradeRepository(),
            profiles: profiles,
            achievements: FeedStubAchievementRepository(),
            session: FeedStubSession(userID: viewerUUID),
            detailCache: cache,
            engagementStore: engagement,
            navigationCoordinator: coordinator
        )

        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }

        XCTAssertEqual(profiles.profileCallCount, 0)
        XCTAssertFalse(viewModel.entries.filter { if case .trade = $0 { return true }; return false }.isEmpty)
        XCTAssertFalse(viewModel.entries.filter { if case .post = $0 { return true }; return false }.isEmpty)
        XCTAssertFalse(viewModel.entries.filter { if case .clip = $0 { return true }; return false }.isEmpty)
        XCTAssertFalse(viewModel.entries.filter { if case .achievement = $0 { return true }; return false }.isEmpty)

        viewModel.setContentFilter(.posts)
        XCTAssertFalse(viewModel.visibleEntries.isEmpty)
        viewModel.setContentFilter(.clips)
        XCTAssertFalse(viewModel.visibleEntries.isEmpty)
        viewModel.setContentFilter(.achievements)
        XCTAssertFalse(viewModel.visibleEntries.isEmpty)

        for entry in viewModel.entries {
            let author = try XCTUnwrap(viewModel.author(for: entry.authorProfileID))
            XCTAssertNotEqual(author.displayName, entry.authorProfileID.rawValue)
            XCTAssertFalse(author.username.isEmpty)
            XCTAssertNotNil(author.avatar)
        }
    }

    // MARK: - Feed Bootstrap V1 (screen ownership)

    func testBootstrapLoadsTimelineAndStoriesIntoFeedState() async throws {
        let cache = DetailPresentationCache()
        let page = try await FeedBootstrap.loadInitial(
            .init(
                feed: FeedStubFeedRepository(),
                trades: FeedStubTradeRepository(),
                profiles: FeedStubProfileRepository(),
                achievements: FeedStubAchievementRepository(),
                session: FeedStubSession(userID: FeedFixtures.viewerID.rawValue),
                detailCache: cache,
                scope: .following
            )
        )

        XCTAssertTrue(page.usedDevelopmentFixtures)
        XCTAssertFalse(page.entries.isEmpty)
        XCTAssertFalse(page.stories.isEmpty)
        XCTAssertNil(page.nextCursor)
    }

    func testScreenViewModelBootstrapPublishesFeedStateOnce() async {
        let viewModel = FeedScreenViewModel(
            feed: FeedStubFeedRepository(),
            trades: FeedStubTradeRepository(),
            profiles: FeedStubProfileRepository(),
            achievements: FeedStubAchievementRepository(),
            session: FeedStubSession(userID: FeedFixtures.viewerID.rawValue),
            detailCache: DetailPresentationCache(),
            engagementStore: EngagementStore(repository: FeedStubInteractionRepository()),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )

        viewModel.loadIfNeeded()
        await waitFor { viewModel.state.didBootstrap && viewModel.phase == .loaded }

        XCTAssertTrue(viewModel.state.didBootstrap)
        XCTAssertEqual(viewModel.entries.count, viewModel.state.entries.count)
        XCTAssertFalse(viewModel.stories.isEmpty)

        let entryCount = viewModel.entries.count
        viewModel.loadIfNeeded()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(viewModel.entries.count, entryCount)
    }

    func testGlobalScopeBootstrapClearsStories() async {
        let viewModel = FeedScreenViewModel(
            feed: FeedStubFeedRepository(),
            trades: FeedStubTradeRepository(),
            profiles: FeedStubProfileRepository(),
            achievements: FeedStubAchievementRepository(),
            session: FeedStubSession(userID: FeedFixtures.viewerID.rawValue),
            detailCache: DetailPresentationCache(),
            engagementStore: EngagementStore(repository: FeedStubInteractionRepository()),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )

        viewModel.loadIfNeeded()
        await waitFor { viewModel.state.didBootstrap && !viewModel.stories.isEmpty }

        viewModel.setScope(.global)
        await waitFor {
            viewModel.scope == .global
                && viewModel.phase == .loaded
                && !viewModel.isRefreshing
                && viewModel.stories.isEmpty
        }
        XCTAssertTrue(viewModel.stories.isEmpty)
    }

    func testFeedViewModelAliasIsFeedScreenViewModel() {
        let screen: FeedScreenViewModel = FeedViewModel(
            feed: FeedStubFeedRepository(),
            trades: FeedStubTradeRepository(),
            profiles: FeedStubProfileRepository(),
            achievements: FeedStubAchievementRepository(),
            session: FeedStubSession(userID: FeedFixtures.viewerID.rawValue),
            detailCache: DetailPresentationCache(),
            engagementStore: EngagementStore(repository: FeedStubInteractionRepository()),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )
        XCTAssertTrue(type(of: screen) == FeedScreenViewModel.self)
    }

    private func waitFor(
        timeout: TimeInterval = 1.0,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Condition not met before timeout")
    }
}

// MARK: - Stubs

private struct FeedStubSession: SessionProviding {
    let userID: String?
    var currentUserID: UserID? {
        get async {
            guard let userID else { return nil }
            return UserID(userID)
        }
    }

    var accessToken: String? {
        get async { userID == nil ? nil : "test-token" }
    }
}

/// Returns web-parity mixed kinds with `profiles(...)` author fields already on each item.
private struct FeedWebShapedStubFeedRepository: FeedRepository {
    func feed(scope: FeedScope, page: PageRequest) async throws -> FeedPageResult {
        _ = scope
        _ = page
        let peer = ProfileID("dev.follower.ada")
        let trade = ProfileTradeFixtures.samples(owner: peer)[0]
        let post = ProfilePostFixtures.samples(owner: peer)[0]
        let clip = ProfileClipFixtures.samples(owner: peer)[0]
        let achievement = ProfileAchievementFixtures.samples(owner: peer)[0]
        let items = [
            FeedFixtures.feedItem(
                id: "web-trade-\(trade.id.rawValue)",
                kind: .trade,
                authorProfileID: trade.ownerProfileID,
                createdAt: trade.createdAt,
                tradeID: trade.id,
                caption: trade.publicCaption,
                mediaURL: trade.thumbnail?.id
            ),
            FeedFixtures.feedItem(
                id: "web-post-\(post.id.rawValue)",
                kind: .post,
                authorProfileID: post.authorProfileID,
                createdAt: post.createdAt,
                postID: post.id,
                caption: post.body,
                mediaURL: post.media.first?.id
            ),
            FeedFixtures.feedItem(
                id: "web-reel-\(clip.id.rawValue)",
                kind: .reel,
                authorProfileID: clip.authorProfileID,
                createdAt: clip.createdAt,
                reelID: clip.id,
                caption: clip.caption,
                mediaURL: clip.thumbnail?.id ?? clip.video.id
            ),
            FeedFixtures.feedItem(
                id: "web-ach-\(achievement.id.rawValue)",
                kind: .achievement,
                authorProfileID: achievement.ownerProfileID,
                createdAt: achievement.achievedAt,
                achievementID: achievement.id,
                caption: achievement.title,
                mediaURL: achievement.image?.id
            ),
        ]
        return FeedPageResult(items: items, nextCursor: nil, embeddedTrades: [])
    }

    func post(id: PostID) async throws -> Post {
        ProfilePostFixtures.samples(owner: FeedFixtures.viewerID)[0]
    }

    func posts(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        CursorPage(items: [], nextCursor: nil)
    }

    func createPost(_ post: Post) async throws -> Post { post }
    func deletePost(id: PostID) async throws {}
    func comments(for postID: PostID, page: PageRequest) async throws -> CursorPage<Comment> {
        CursorPage(items: [], nextCursor: nil)
    }

    func addComment(_ comment: Comment) async throws -> Comment { comment }
    func setReaction(on item: FeedItem, kind: ReactionKind, isActive: Bool) async throws {}
    func stories(for viewer: ProfileID) async throws -> [Story] { [] }
    func reel(id: ReelID) async throws -> Reel {
        ProfileClipFixtures.samples(owner: FeedFixtures.viewerID)[0]
    }

    func reels(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Reel> {
        CursorPage(items: [], nextCursor: nil)
    }

    func profileReels(for profileID: ProfileID) async throws -> [Reel] { [] }
    func createReel(_ reel: Reel) async throws -> Reel { reel }
}

private struct FeedStubFeedRepository: FeedRepository {
    func feed(scope: FeedScope, page: PageRequest) async throws -> FeedPageResult {
        FeedPageResult(items: [], nextCursor: nil, embeddedTrades: [])
    }

    func post(id: PostID) async throws -> Post {
        ProfilePostFixtures.samples(owner: FeedFixtures.viewerID)[0]
    }

    func posts(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        CursorPage(items: [], nextCursor: nil)
    }

    func createPost(_ post: Post) async throws -> Post { post }
    func deletePost(id: PostID) async throws {}
    func comments(for postID: PostID, page: PageRequest) async throws -> CursorPage<Comment> {
        CursorPage(items: [], nextCursor: nil)
    }

    func addComment(_ comment: Comment) async throws -> Comment { comment }
    func setReaction(on item: FeedItem, kind: ReactionKind, isActive: Bool) async throws {}
    func stories(for viewer: ProfileID) async throws -> [Story] { [] }
    func reel(id: ReelID) async throws -> Reel {
        ProfileClipFixtures.samples(owner: FeedFixtures.viewerID)[0]
    }

    func reels(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Reel> {
        CursorPage(items: [], nextCursor: nil)
    }

    func profileReels(for profileID: ProfileID) async throws -> [Reel] { [] }
    func createReel(_ reel: Reel) async throws -> Reel { reel }
}

private struct FeedStubTradeRepository: TradeRepository {
    func trade(id: TradeID) async throws -> Trade {
        ProfileTradeFixtures.samples(owner: FeedFixtures.viewerID)[0]
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
        ProfileTradeFixtures.samples(owner: FeedFixtures.viewerID)[0]
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

/// Counts `profile(id:)` calls so tests can assert the feed never N+1 fetches authors.
private final class FeedCountingProfileRepository: ProfileRepository, @unchecked Sendable {
    private(set) var profileCallCount = 0
    private let base = FeedStubProfileRepository()

    func currentUser() async throws -> User { try await base.currentUser() }

    func profile(id: ProfileID) async throws -> Profile {
        profileCallCount += 1
        return try await base.profile(id: id)
    }

    func profile(username: String) async throws -> Profile { try await base.profile(username: username) }
    func updateProfile(_ profile: Profile) async throws -> Profile { try await base.updateProfile(profile) }
    func stats(for profileID: ProfileID) async throws -> ProfileStats { try await base.stats(for: profileID) }
    func wallPosts(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        try await base.wallPosts(for: profileID, page: page)
    }
    func wallPost(id: PostID) async throws -> Post { try await base.wallPost(id: id) }
    func followState(from viewer: ProfileID, to target: ProfileID) async throws -> FollowState {
        try await base.followState(from: viewer, to: target)
    }
    func follow(from viewer: ProfileID, to target: ProfileID) async throws {
        try await base.follow(from: viewer, to: target)
    }
    func unfollow(from viewer: ProfileID, to target: ProfileID) async throws {
        try await base.unfollow(from: viewer, to: target)
    }
    func followers(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        try await base.followers(of: profileID, page: page)
    }
    func following(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        try await base.following(of: profileID, page: page)
    }
    func creator(for profileID: ProfileID) async throws -> Creator? {
        try await base.creator(for: profileID)
    }
}

private struct FeedStubProfileRepository: ProfileRepository {
    func currentUser() async throws -> User {
        User(id: UserID(FeedFixtures.viewerID.rawValue), email: nil, createdAt: .now)
    }

    func profile(id: ProfileID) async throws -> Profile {
        FollowListFixtures.profile(id: id) ?? Profile(
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
        ProfilePostFixtures.samples(owner: FeedFixtures.viewerID)[0]
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

private struct FeedStubAchievementRepository: AchievementRepository {
    func achievements(
        for profileID: ProfileID,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Achievement> {
        CursorPage(items: [], nextCursor: nil)
    }

    func achievement(id: AchievementID) async throws -> Achievement {
        ProfileAchievementFixtures.samples(owner: FeedFixtures.viewerID)[0]
    }

    func save(_ achievement: Achievement) async throws -> Achievement { achievement }
}

private struct FeedStubInteractionRepository: InteractionRepository {
    func engagement(for targets: [InteractionTarget]) async throws -> [InteractionTarget: EngagementSnapshot] {
        Dictionary(uniqueKeysWithValues: targets.map { ($0, .empty) })
    }

    func setLiked(_ liked: Bool, on target: InteractionTarget) async throws {}
    func comments(
        for target: InteractionTarget,
        order: CommentSortOrder
    ) async throws -> [InteractionComment] { [] }

    func addComment(
        body: String,
        parentID: CommentID?,
        on target: InteractionTarget
    ) async throws -> InteractionComment {
        InteractionComment(
            id: CommentID(UUID().uuidString),
            target: target,
            authorProfileID: FeedFixtures.viewerID,
            authorUsername: nil,
            body: body,
            parentCommentID: parentID,
            createdAt: .now,
            isPinned: false
        )
    }

    func deleteComment(id: CommentID, on target: InteractionTarget) async throws {}
}
