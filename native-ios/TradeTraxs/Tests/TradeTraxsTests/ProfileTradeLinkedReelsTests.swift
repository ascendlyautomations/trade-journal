import XCTest
@testable import TradeTraxs

@MainActor
final class ProfileTradeLinkedReelsTests: XCTestCase {
    func testLinkedReelThumbnailAvailableWithoutOpeningClipsTab() async {
        let owner = ProfileID("owner-trade-clip")
        let tradeID = TradeID("trade-with-clip")
        let reel = makeLinkedReel(owner: owner, tradeID: tradeID)

        let cache = DetailPresentationCache()
        let feed = TradeLinkedReelsStubFeed(reelsByTradeID: [tradeID: reel])
        let store = NavigationStore()
        let viewModel = TradesContainerViewModel(
            profileID: owner,
            trades: CompositionRoot.bootstrapAppEnvironment().data.trades,
            session: ClipsLinkStubSession(userID: owner.rawValue),
            navigationCoordinator: NavigationCoordinator(store: store),
            detailCache: cache,
            tradeDetailRepository: CompositionRoot.bootstrapAppEnvironment().data.tradeDetailRepository,
            feed: feed
        )

        viewModel.installAuthoritativeV2JournalForTests([journalRow(owner: owner, tradeID: tradeID)])
        XCTAssertNil(FeedLinkedContentResolver.visibleLinkedReel(
            for: tradeID,
            cache: cache,
            viewerID: owner
        ))

        viewModel.scheduleLinkedReelsHydrationIfNeeded()
        try? await Task.sleep(for: .milliseconds(80))

        let resolved = FeedLinkedContentResolver.visibleLinkedReel(
            for: tradeID,
            cache: cache,
            viewerID: owner
        )
        XCTAssertEqual(resolved?.id, reel.id)
        XCTAssertEqual(resolved?.thumbnail?.id, "thumb.jpg")
        XCTAssertEqual(feed.fetchCount, 1)
    }

    func testApplyReelLinkMutationImmediatelyShowsLinkedThumbnail() {
        let owner = ProfileID("owner-link-sync")
        let tradeID = TradeID("trade-link-sync")
        let cache = DetailPresentationCache()
        let reel = makeLinkedReel(owner: owner, tradeID: tradeID)
        var unlinked = reel
        unlinked.linkedTradeID = nil

        let store = NavigationStore()
        let viewModel = TradesContainerViewModel(
            profileID: owner,
            trades: CompositionRoot.bootstrapAppEnvironment().data.trades,
            session: ClipsLinkStubSession(userID: owner.rawValue),
            navigationCoordinator: NavigationCoordinator(store: store),
            detailCache: cache,
            tradeDetailRepository: CompositionRoot.bootstrapAppEnvironment().data.tradeDetailRepository,
            feed: TradeLinkedReelsStubFeed(reelsByTradeID: [tradeID: reel])
        )
        viewModel.installAuthoritativeV2JournalForTests([journalRow(owner: owner, tradeID: tradeID)])

        cache.seed(unlinked)
        viewModel.applyReelLinkMutation(reel)

        XCTAssertEqual(
            FeedLinkedContentResolver.visibleLinkedReel(for: tradeID, cache: cache, viewerID: owner)?.id,
            reel.id
        )
        XCTAssertGreaterThan(viewModel.linkedReelPresentationToken(for: tradeID), 0)
    }

    func testApplyReelLinkMutationUnlinkClearsThumbnail() {
        let owner = ProfileID("owner-unlink-sync")
        let tradeID = TradeID("trade-unlink-sync")
        let cache = DetailPresentationCache()
        let reel = makeLinkedReel(owner: owner, tradeID: tradeID)
        cache.seed(reel)

        let store = NavigationStore()
        let viewModel = TradesContainerViewModel(
            profileID: owner,
            trades: CompositionRoot.bootstrapAppEnvironment().data.trades,
            session: ClipsLinkStubSession(userID: owner.rawValue),
            navigationCoordinator: NavigationCoordinator(store: store),
            detailCache: cache,
            tradeDetailRepository: CompositionRoot.bootstrapAppEnvironment().data.tradeDetailRepository
        )
        viewModel.installAuthoritativeV2JournalForTests([journalRow(owner: owner, tradeID: tradeID)])

        var unlinked = reel
        unlinked.linkedTradeID = nil
        let tokenBefore = viewModel.linkedReelPresentationToken(for: tradeID)
        viewModel.applyReelLinkMutation(unlinked)

        XCTAssertNil(FeedLinkedContentResolver.visibleLinkedReel(for: tradeID, cache: cache, viewerID: owner))
        XCTAssertGreaterThan(viewModel.linkedReelPresentationToken(for: tradeID), tokenBefore)
    }

    func testStaleHydrationDoesNotRestoreAfterUnlink() async {
        let owner = ProfileID("owner-stale-hydrate")
        let tradeID = TradeID("trade-stale")
        let cache = DetailPresentationCache()
        let reel = makeLinkedReel(owner: owner, tradeID: tradeID)

        let store = NavigationStore()
        let slowFeed = SlowTradeLinkedReelsStubFeed(reelsByTradeID: [tradeID: reel], delayMs: 120)
        let viewModel = TradesContainerViewModel(
            profileID: owner,
            trades: CompositionRoot.bootstrapAppEnvironment().data.trades,
            session: ClipsLinkStubSession(userID: owner.rawValue),
            navigationCoordinator: NavigationCoordinator(store: store),
            detailCache: cache,
            tradeDetailRepository: CompositionRoot.bootstrapAppEnvironment().data.tradeDetailRepository,
            feed: slowFeed
        )
        viewModel.installAuthoritativeV2JournalForTests([journalRow(owner: owner, tradeID: tradeID)])

        viewModel.scheduleLinkedReelsHydrationIfNeeded()
        try? await Task.sleep(for: .milliseconds(20))

        var unlinked = reel
        unlinked.linkedTradeID = nil
        viewModel.applyReelLinkMutation(unlinked)
        XCTAssertNil(cache.reel(linkedTo: tradeID))

        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(cache.reel(linkedTo: tradeID))
    }

    func testApplyLinkedReelDeletedClearsTradeThumbnail() {
        let owner = ProfileID("owner-delete-sync")
        let tradeID = TradeID("trade-delete-sync")
        let cache = DetailPresentationCache()
        let reel = makeLinkedReel(owner: owner, tradeID: tradeID)
        cache.seed(reel)

        let store = NavigationStore()
        let viewModel = TradesContainerViewModel(
            profileID: owner,
            trades: CompositionRoot.bootstrapAppEnvironment().data.trades,
            session: ClipsLinkStubSession(userID: owner.rawValue),
            navigationCoordinator: NavigationCoordinator(store: store),
            detailCache: cache,
            tradeDetailRepository: CompositionRoot.bootstrapAppEnvironment().data.tradeDetailRepository
        )
        viewModel.installAuthoritativeV2JournalForTests([journalRow(owner: owner, tradeID: tradeID)])

        viewModel.applyLinkedReelDeleted(reel.id)
        XCTAssertNil(cache.reel(linkedTo: tradeID))
        XCTAssertGreaterThan(viewModel.linkedReelPresentationToken(for: tradeID), 0)
    }

    func testHydratorSkipsTradesAlreadyIndexedInCache() async {
        let owner = ProfileID("owner-skip")
        let tradeID = TradeID("trade-cached")
        let reel = makeLinkedReel(owner: owner, tradeID: tradeID)
        let cache = DetailPresentationCache()
        cache.seed(reel)
        let feed = TradeLinkedReelsStubFeed(reelsByTradeID: [tradeID: reel])

        await ProfileTradeLinkedReelsHydrator.hydrateMissing(
            tradeIDs: [tradeID],
            profileID: owner,
            feed: feed,
            detailCache: cache
        )

        XCTAssertEqual(feed.fetchCount, 0)
        XCTAssertEqual(cache.reel(linkedTo: tradeID)?.id, reel.id)
    }

    private func makeLinkedReel(owner: ProfileID, tradeID: TradeID) -> Reel {
        Reel(
            id: ReelID("reel-thumb"),
            authorProfileID: owner,
            video: MediaReference(id: "video.mp4", kind: .video, altText: nil),
            thumbnail: MediaReference(id: "thumb.jpg", kind: .image, altText: nil),
            caption: "Chart replay",
            visibility: .public,
            linkedTradeID: tradeID,
            durationSeconds: 12,
            createdAt: .now
        )
    }

    private func journalRow(owner: ProfileID, tradeID: TradeID) -> TradeOwnerJournalSummary {
        TradeOwnerJournalSummary(
            summary: TradeSummary(
                id: tradeID,
                ownerProfileID: owner,
                symbol: Symbol(ticker: "ES"),
                side: .long,
                realizedPnL: Money(amount: 100, currencyCode: "USD"),
                riskReward: 2,
                points: 4,
                quantity: 1,
                entryAt: .now,
                exitAt: nil,
                createdAt: .now,
                visibility: .public,
                publicCaption: nil,
                notePreview: nil,
                thumbnail: nil,
                imageDisplayMode: .fit,
                mode: .live,
                accountMode: nil,
                publicAccountBadge: nil,
                durationSeconds: nil,
                durationText: nil
            ),
            accountID: nil,
            copyTrade: nil
        )
    }
}

private final class SlowTradeLinkedReelsStubFeed: FeedRepository, @unchecked Sendable {
    var reelsByTradeID: [TradeID: Reel]
    let delayMs: UInt64

    init(reelsByTradeID: [TradeID: Reel], delayMs: UInt64) {
        self.reelsByTradeID = reelsByTradeID
        self.delayMs = delayMs
    }

    func feed(scope: FeedScope, contentFilter: FeedContentFilter, page: PageRequest) async throws -> FeedPageResult {
        FeedPageResult(items: [], nextCursor: nil, embeddedTrades: [])
    }
    func post(id: PostID) async throws -> Post { throw AppError.unknown(message: "stub") }
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
    func createStory(userID: ProfileID, imageURL: String) async throws -> Story {
        Story(
            id: StoryID("s"),
            authorProfileID: userID,
            media: MediaReference(id: imageURL, kind: .image, altText: nil),
            expiresAt: .now,
            createdAt: .now,
            viewerHasSeen: false
        )
    }
    func reel(id: ReelID) async throws -> ReelLoadResult { throw AppError.unknown(message: "stub") }
    func reels(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Reel> {
        CursorPage(items: [], nextCursor: nil)
    }
    func profileReels(for profileID: ProfileID) async throws -> ProfileReelsResult {
        ProfileReelsResult(reels: [], embeddedTrades: [])
    }
    func createReel(_ reel: Reel) async throws -> Reel { reel }
    func unattachedReels(
        for profileID: ProfileID,
        limit: Int,
        includingReelID: ReelID?
    ) async throws -> [Reel] { [] }
    func tradeIDsWithAttachedReels(owner: ProfileID) async throws -> Set<TradeID> { [] }
    func attachReel(id: ReelID, to tradeID: TradeID) async throws {}
    func tradeHasAttachedReel(_ tradeID: TradeID) async throws -> Bool { false }

    func reels(linkedToTradeIDs tradeIDs: [TradeID], ownerID: ProfileID) async throws -> [Reel] {
        try await Task.sleep(for: .milliseconds(delayMs))
        return tradeIDs.compactMap { reelsByTradeID[$0] }
    }
}

private final class TradeLinkedReelsStubFeed: FeedRepository, @unchecked Sendable {
    var reelsByTradeID: [TradeID: Reel]
    private(set) var fetchCount = 0

    init(reelsByTradeID: [TradeID: Reel]) {
        self.reelsByTradeID = reelsByTradeID
    }

    func feed(scope: FeedScope, contentFilter: FeedContentFilter, page: PageRequest) async throws -> FeedPageResult {
        FeedPageResult(items: [], nextCursor: nil, embeddedTrades: [])
    }
    func post(id: PostID) async throws -> Post { throw AppError.unknown(message: "stub") }
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
    func createStory(userID: ProfileID, imageURL: String) async throws -> Story {
        Story(
            id: StoryID("s"),
            authorProfileID: userID,
            media: MediaReference(id: imageURL, kind: .image, altText: nil),
            expiresAt: .now,
            createdAt: .now,
            viewerHasSeen: false
        )
    }
    func reel(id: ReelID) async throws -> ReelLoadResult { throw AppError.unknown(message: "stub") }
    func reels(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Reel> {
        CursorPage(items: [], nextCursor: nil)
    }
    func profileReels(for profileID: ProfileID) async throws -> ProfileReelsResult {
        ProfileReelsResult(reels: [], embeddedTrades: [])
    }
    func createReel(_ reel: Reel) async throws -> Reel { reel }
    func unattachedReels(
        for profileID: ProfileID,
        limit: Int,
        includingReelID: ReelID?
    ) async throws -> [Reel] { [] }
    func tradeIDsWithAttachedReels(owner: ProfileID) async throws -> Set<TradeID> { [] }
    func attachReel(id: ReelID, to tradeID: TradeID) async throws {}
    func tradeHasAttachedReel(_ tradeID: TradeID) async throws -> Bool { false }

    func reels(linkedToTradeIDs tradeIDs: [TradeID], ownerID: ProfileID) async throws -> [Reel] {
        fetchCount += 1
        return tradeIDs.compactMap { reelsByTradeID[$0] }
    }
}

private struct ClipsLinkStubSession: SessionProviding {
    let userID: String?
    var currentUserID: UserID? { get async { userID.map { UserID($0) } } }
    var accessToken: String? { get async { userID == nil ? nil : "token" } }
}