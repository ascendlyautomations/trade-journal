import XCTest
@testable import TradeTraxs

@MainActor
final class SocialPresentationWriteThroughTests: XCTestCase {
    private let viewerA = ProfileID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private let viewerB = ProfileID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
    private let author = ProfileID("cccccccc-cccc-cccc-cccc-cccccccccccc")

    override func setUp() {
        super.setUp()
        FeedPersistedCacheTestHooks.forceSynchronousDiskWrites = true
        SocialPresentationWriteThroughGeneration.resetForTesting()
        SocialPresentationWriteThroughCoordinator.shared.configure(
            session: WriteThroughTestSession(viewerID: viewerA)
        )
        #if DEBUG
        SocialPresentationWriteThroughProbe.resetForTesting()
        #endif
    }

    override func tearDown() {
        FeedPersistedCacheCoordinator.flushPendingDiskWritesForTesting()
        FeedPersistedCacheTestHooks.forceSynchronousDiskWrites = false
        FeedPersistedCacheCoordinator.clearAll()
        FeedSessionStore.shared.invalidate()
        ProfilePersistedCacheCoordinator.clearAll()
        SocialPresentationWriteThroughGeneration.resetForTesting()
        super.tearDown()
    }

    func testLikeFromDetailPatchesFeedDiskAndHydratesWithoutPrefetch() async {
        let target = InteractionTarget.feedPost(PostID("feed-post-1"))
        seedFeed(viewer: viewerA, entryID: "feed-post-1", filter: .all)
        let liked = EngagementSnapshot(likeCount: 1, commentCount: 0, viewerHasLiked: true)
        let generation = SocialPresentationWriteThroughGeneration.bump(viewerID: viewerA, target: target)
        _ = FeedPersistedCacheCoordinator.patchEngagement(
            viewerID: viewerA,
            target: target,
            snapshot: liked,
            writeGeneration: generation
        )
        FeedSessionStore.shared.dropMemorySnapshots(viewerID: viewerA)
        XCTAssertNotNil(
            FeedPersistedCacheCoordinator.hydratePage(
                viewerID: viewerA,
                scope: .following,
                contentFilter: .all
            )
        )
        let key = FeedSessionStore.cacheKey(
            viewerID: viewerA,
            scope: .following,
            contentFilter: .all,
            cursor: nil
        )
        let restored = FeedSessionStore.shared.restore(key: key)?.entries.first
        XCTAssertEqual(restored?.item.likeCount, 1)
        XCTAssertTrue(restored?.item.viewerHasLiked == true)
        let freshStore = EngagementStore(repository: WriteThroughStubInteractionRepository())
        _ = FeedEngagementCacheRestore.seedEngagementStore(
            from: FeedSessionStore.shared.restore(key: key)?.entries ?? [],
            into: freshStore
        )
        XCTAssertTrue(freshStore.snapshot(for: target).viewerHasLiked)
    }

    func testEngagementStoreToggleLikePatchesFeedDisk() async {
        let target = InteractionTarget.feedPost(PostID("feed-toggle-like"))
        seedFeed(viewer: viewerA, entryID: "feed-toggle-like", filter: .all)
        let store = EngagementStore(repository: WriteThroughStubInteractionRepository())
        store.configurePresentationWriteThrough(SocialPresentationWriteThroughCoordinator.shared)
        await store.toggleLike(on: target)
        FeedPersistedCacheCoordinator.flushPendingDiskWritesForTesting()
        let disk = FeedDiskCache.loadPage(viewerID: viewerA, scope: .following, contentFilter: .all)
        XCTAssertEqual(disk?.entries.first?.item.likeCount, 1)
    }

    func testUnlikeFromProfilePatchesFeedDisk() async throws {
        let postID = PostID("profile-post-1")
        let target = InteractionTarget.profilePost(postID)
        var entry = makePostEntry(id: postID.rawValue, author: author)
        entry = entry.patchingEngagement(
            EngagementSnapshot(likeCount: 2, commentCount: 0, viewerHasLiked: true)
        )
        FeedPersistedCacheCoordinator.persistFirstPage(
            viewerID: viewerA,
            scope: .following,
            contentFilter: .posts,
            entries: [entry],
            stories: [],
            nextCursor: nil
        )

        let repository = WriteThroughStubInteractionRepository()
        let store = EngagementStore(repository: repository)
        store.configurePresentationWriteThrough(SocialPresentationWriteThroughCoordinator.shared)
        store.seed(EngagementSnapshot(likeCount: 2, commentCount: 0, viewerHasLiked: true), for: target)

        await store.toggleLike(on: target)

        let disk = FeedDiskCache.loadPage(viewerID: viewerA, scope: .following, contentFilter: .posts)
        XCTAssertEqual(disk?.entries.first?.item.likeCount, 1)
        XCTAssertFalse(disk?.entries.first?.item.viewerHasLiked == true)
    }

    func testLikeFailureRollsBackDisk() async throws {
        let target = InteractionTarget.feedPost(PostID("feed-rollback"))
        seedFeed(viewer: viewerA, entryID: "feed-rollback", filter: .all)

        let repository = WriteThroughStubInteractionRepository(failLikes: true)
        let store = EngagementStore(repository: repository)
        store.configurePresentationWriteThrough(SocialPresentationWriteThroughCoordinator.shared)
        store.seed(EngagementSnapshot(likeCount: 0, commentCount: 0, viewerHasLiked: false), for: target)

        await store.toggleLike(on: target)

        let disk = FeedDiskCache.loadPage(viewerID: viewerA, scope: .following, contentFilter: .all)
        XCTAssertEqual(disk?.entries.first?.item.likeCount, 0)
        XCTAssertFalse(disk?.entries.first?.item.viewerHasLiked == true)
    }

    func testCommentCountDeltaPatchesFeedAndProfileOverlay() async {
        let target = InteractionTarget.profilePost(PostID("post-count-1"))
        seedFeed(viewer: viewerA, entryID: "post-count-1", filter: .posts)

        var profileState = ProfileState()
        profileState.phase = .loaded
        profileState.profileID = author
        profileState.profile = makeMinimalProfile(id: author)
        profileState.posts = [makePost(id: PostID("post-count-1"))]
        profileState.didLoadPosts = true
        ProfilePersistedCacheCoordinator.persist(
            viewerID: viewerA,
            targetProfileID: author,
            state: profileState
        )

        let store = EngagementStore(repository: WriteThroughStubInteractionRepository())
        store.configurePresentationWriteThrough(SocialPresentationWriteThroughCoordinator.shared)
        store.seed(EngagementSnapshot(likeCount: 0, commentCount: 1, viewerHasLiked: false), for: target)
        store.applyCommentCountDelta(1, on: target)
        await Task.yield()
        await Task.yield()
        FeedPersistedCacheCoordinator.flushPendingDiskWritesForTesting()

        let diskFeed = FeedDiskCache.loadPage(viewerID: viewerA, scope: .following, contentFilter: .posts)
        XCTAssertEqual(diskFeed?.entries.first?.item.commentCount, 2)

        let profileBlob = ProfileDiskCache.loadSnapshot(viewerID: viewerA, targetProfileID: author)
        XCTAssertEqual(
            profileBlob?.engagementPresentation[target.presentationStorageKey]?.commentCount,
            2
        )
    }

    func testAbsentTargetDoesNotCreateFeedEntity() {
        let target = InteractionTarget.reel(ReelID("missing-reel"))
        let snapshot = EngagementSnapshot(likeCount: 1, commentCount: 0, viewerHasLiked: true)
        let patched = FeedPersistedCacheCoordinator.patchEngagement(
            viewerID: viewerA,
            target: target,
            snapshot: snapshot,
            writeGeneration: SocialPresentationWriteThroughGeneration.bump(viewerID: viewerA, target: target)
        )
        XCTAssertEqual(patched, 0)
        XCTAssertNil(FeedDiskCache.loadPage(viewerID: viewerA, scope: .following, contentFilter: .all))
    }

    func testMultipleFeedFilterVariantsPatchSameViewer() {
        let target = InteractionTarget.feedPost(PostID("multi-filter"))
        seedFeed(viewer: viewerA, entryID: "multi-filter", filter: .all)
        seedFeed(viewer: viewerA, entryID: "multi-filter", filter: .trades)

        let snapshot = EngagementSnapshot(likeCount: 3, commentCount: 1, viewerHasLiked: true)
        let generation = SocialPresentationWriteThroughGeneration.bump(viewerID: viewerA, target: target)
        let copies = FeedPersistedCacheCoordinator.patchEngagement(
            viewerID: viewerA,
            target: target,
            snapshot: snapshot,
            writeGeneration: generation
        )
        XCTAssertEqual(copies, 2)

        for filter in [FeedContentFilter.all, FeedContentFilter.trades] {
            let blob = FeedDiskCache.loadPage(viewerID: viewerA, scope: .following, contentFilter: filter)
            XCTAssertEqual(blob?.entries.first?.item.likeCount, 3)
        }
    }

    func testViewerIsolation() {
        let target = InteractionTarget.feedPost(PostID("iso-post"))
        seedFeed(viewer: viewerA, entryID: "iso-post", filter: .all)
        seedFeed(viewer: viewerB, entryID: "iso-post", filter: .all)

        let snapshot = EngagementSnapshot(likeCount: 9, commentCount: 0, viewerHasLiked: true)
        _ = FeedPersistedCacheCoordinator.patchEngagement(
            viewerID: viewerA,
            target: target,
            snapshot: snapshot,
            writeGeneration: SocialPresentationWriteThroughGeneration.bump(viewerID: viewerA, target: target)
        )

        let viewerBFeed = FeedDiskCache.loadPage(viewerID: viewerB, scope: .following, contentFilter: .all)
        XCTAssertEqual(viewerBFeed?.entries.first?.item.likeCount, 0)
    }

    func testRapidLikeUnlikeNewestGenerationWins() {
        let target = InteractionTarget.feedPost(PostID("race-post"))
        seedFeed(viewer: viewerA, entryID: "race-post", filter: .all)

        let liked = EngagementSnapshot(likeCount: 1, commentCount: 0, viewerHasLiked: true)
        let unliked = EngagementSnapshot(likeCount: 0, commentCount: 0, viewerHasLiked: false)

        let staleGeneration = SocialPresentationWriteThroughGeneration.bump(viewerID: viewerA, target: target)
        _ = FeedPersistedCacheCoordinator.patchEngagement(
            viewerID: viewerA,
            target: target,
            snapshot: liked,
            writeGeneration: staleGeneration
        )

        let latestGeneration = SocialPresentationWriteThroughGeneration.bump(viewerID: viewerA, target: target)
        _ = FeedPersistedCacheCoordinator.patchEngagement(
            viewerID: viewerA,
            target: target,
            snapshot: unliked,
            writeGeneration: latestGeneration
        )

        let disk = FeedDiskCache.loadPage(viewerID: viewerA, scope: .following, contentFilter: .all)
        XCTAssertEqual(disk?.entries.first?.item.likeCount, 0)
        XCTAssertFalse(disk?.entries.first?.item.viewerHasLiked == true)
    }

    func testTradeEngagementPatchDoesNotTouchSocialEntityTradeSummary() {
        let tradeID = TradeID("trade-only-eng")
        let summary = makeSummary(id: tradeID.rawValue)
        SocialEntityPersistedCacheCoordinator.saveTradeSummary(
            summary,
            viewerID: viewerA,
            source: .feed,
            mergeMode: .replace
        )

        let target = InteractionTarget.trade(tradeID)
        _ = ProfilePersistedCacheCoordinator.patchEngagementPresentation(
            viewerID: viewerA,
            target: target,
            snapshot: EngagementSnapshot(likeCount: 5, commentCount: 2, viewerHasLiked: true),
            writeGeneration: SocialPresentationWriteThroughGeneration.bump(viewerID: viewerA, target: target)
        )

        let loaded = SocialEntityDiskCache.loadTradeSummary(id: tradeID, viewerID: viewerA)
        XCTAssertEqual(loaded?.symbol.ticker, summary.symbol.ticker)
        XCTAssertNil(SocialEntityDiskCache.loadTrade(id: tradeID, viewerID: viewerA)?.psychologyNotes)
    }

    // MARK: - Helpers

    private func seedFeed(viewer: ProfileID, entryID: String, filter: FeedContentFilter) {
        FeedPersistedCacheCoordinator.persistFirstPage(
            viewerID: viewer,
            scope: .following,
            contentFilter: filter,
            entries: [makeTradeEntry(id: entryID, author: author)],
            stories: [],
            nextCursor: nil
        )
    }

    private func makeTradeEntry(id: String, author: ProfileID) -> FeedTimelineEntry {
        let createdAt = Date(timeIntervalSinceNow: -60)
        let tradeID = TradeID("trade-\(id)")
        let trade = Trade(
            id: tradeID,
            ownerProfileID: author,
            accountID: nil,
            symbol: Symbol(ticker: "AAPL"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 100,
            exitPrice: 110,
            entryAt: createdAt,
            exitAt: createdAt.addingTimeInterval(3600),
            realizedPnL: Money(amount: 10),
            riskReward: nil,
            points: nil,
            sessionLabel: nil,
            visibility: .public,
            publicCaption: "caption",
            thumbnail: nil,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let item = FeedItem(
            id: id,
            kind: .trade,
            authorProfileID: author,
            createdAt: createdAt,
            tradeID: tradeID,
            postID: PostID(id),
            reelID: nil,
            storyID: nil,
            achievementID: nil,
            caption: "caption",
            likeCount: 0,
            commentCount: 0,
            viewerHasLiked: false,
            engagementStateCached: true
        )
        return .trade(item, TradeSummaryMapper.summary(fromPartialListTrade: trade))
    }

    private func makePostEntry(id: String, author: ProfileID) -> FeedTimelineEntry {
        let createdAt = Date(timeIntervalSinceNow: -60)
        let post = makePost(id: PostID(id))
        let item = FeedItem(
            id: id,
            kind: .post,
            authorProfileID: author,
            createdAt: createdAt,
            tradeID: nil,
            postID: PostID(id),
            reelID: nil,
            storyID: nil,
            achievementID: nil,
            caption: post.body,
            likeCount: 0,
            commentCount: 0,
            viewerHasLiked: false,
            engagementStateCached: true
        )
        return .post(item, post)
    }

    private func makePost(id: PostID) -> Post {
        Post(
            id: id,
            authorProfileID: author,
            body: "hello",
            media: [],
            visibility: .public,
            linkedTradeID: nil,
            isPinned: false,
            createdAt: .now,
            updatedAt: .now
        )
    }

    private func makeMinimalProfile(id: ProfileID) -> Profile {
        Profile(
            id: id,
            userID: UserID(id.rawValue),
            username: "user",
            displayName: "User",
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

    private func makeSummary(id: String) -> TradeSummary {
        TradeSummary(
            id: TradeID(id),
            ownerProfileID: author,
            symbol: Symbol(ticker: "ES"),
            side: .long,
            realizedPnL: Money(amount: 10),
            riskReward: nil,
            points: nil,
            quantity: 1,
            entryAt: .now,
            exitAt: .now,
            createdAt: .now,
            visibility: .public,
            publicCaption: nil,
            notePreview: nil,
            thumbnail: nil,
            imageDisplayMode: .fit,
            mode: .live,
            publicAccountBadge: nil,
            durationSeconds: nil,
            durationText: nil
        )
    }
}

private struct WriteThroughTestSession: SessionProviding {
    let viewerID: ProfileID
    var currentUserID: UserID? {
        get async { UserID(viewerID.rawValue) }
    }
    var accessToken: String? {
        get async { "test-token" }
    }
}

private final class WriteThroughStubInteractionRepository: InteractionRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _engagementFetchCount = 0
    var engagementFetchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _engagementFetchCount
    }

    var failLikes = false

    init(failLikes: Bool = false) {
        self.failLikes = failLikes
    }

    func engagement(for targets: [InteractionTarget]) async throws -> [InteractionTarget: EngagementSnapshot] {
        lock.lock()
        _engagementFetchCount += 1
        lock.unlock()
        return Dictionary(uniqueKeysWithValues: targets.map { ($0, .empty) })
    }

    func setLiked(_ liked: Bool, on target: InteractionTarget) async throws {
        if failLikes { throw AppError.unknown(message: "like failed") }
    }

    func comments(for target: InteractionTarget, order: CommentSortOrder) async throws -> [InteractionComment] {
        []
    }

    func addComment(
        body: String,
        parentID: CommentID?,
        on target: InteractionTarget
    ) async throws -> InteractionComment {
        throw AppError.unknown(message: "unused")
    }

    func deleteComment(id: CommentID, on target: InteractionTarget) async throws {}

    func commentLikeMeta(
        for commentIDs: [CommentID],
        source: CommentLikeSource
    ) async throws -> [CommentID: CommentLikeSnapshot] {
        [:]
    }

    func setCommentLiked(
        _ liked: Bool,
        commentID: CommentID,
        source: CommentLikeSource
    ) async throws {}

    func setCommentPinned(
        _ pinned: Bool,
        commentID: CommentID,
        on target: InteractionTarget
    ) async throws {}
}
