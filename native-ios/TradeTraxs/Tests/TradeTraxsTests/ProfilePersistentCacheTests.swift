import XCTest
@testable import TradeTraxs

@MainActor
final class ProfilePersistentCacheTests: XCTestCase {
    private let viewerA = ProfileID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private let viewerB = ProfileID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
    private let target = ProfileID("cccccccc-cccc-cccc-cccc-cccccccccccc")

    override func tearDown() {
        ProfilePersistedCacheCoordinator.clearAll()
        FeedPersistedCacheCoordinator.clearAll()
        ProfileSessionStore.shared.invalidate()
        FeedBlockedAuthorsFilter.shared.clear()
        #if DEBUG
        ProfilePersistentCacheProbe.resetForTesting()
        SocialEntityCacheProbe.resetForTesting()
        #endif
        super.tearDown()
    }

    func testProfileSnapshotPersistsAndHydrates() {
        let state = makeLoadedState(target: target, viewerIsOwner: false)
        ProfilePersistedCacheCoordinator.persist(
            viewerID: viewerA,
            targetProfileID: target,
            state: state
        )

        ProfileSessionStore.shared.invalidate()
        let detailCache = DetailPresentationCache()
        let hydrated = ProfilePersistedCacheCoordinator.hydrate(
            viewerID: viewerA,
            targetProfileID: target,
            detailCache: detailCache
        )

        XCTAssertNotNil(hydrated)
        XCTAssertEqual(hydrated?.profile?.username, "target-user")
        XCTAssertEqual(hydrated?.trades.count, 1)
        XCTAssertEqual(detailCache.profile(id: target)?.username, "target-user")
    }

    func testViewerIsolationDoesNotCrossHydrate() {
        ProfilePersistedCacheCoordinator.persist(
            viewerID: viewerA,
            targetProfileID: target,
            state: makeLoadedState(target: target, viewerIsOwner: false)
        )

        ProfileSessionStore.shared.invalidate()
        XCTAssertNil(
            ProfilePersistedCacheCoordinator.hydrate(
                viewerID: viewerB,
                targetProfileID: target,
                detailCache: DetailPresentationCache()
            )
        )
    }

    func testBlockedPeerSnapshotIsNotHydrated() {
        ProfilePersistedCacheCoordinator.persist(
            viewerID: viewerA,
            targetProfileID: target,
            state: makeLoadedState(target: target, viewerIsOwner: false)
        )

        let blocked = Set([target])
        XCTAssertNil(
            ProfilePersistedCacheCoordinator.hydrate(
                viewerID: viewerA,
                targetProfileID: target,
                detailCache: DetailPresentationCache(),
                blockedPeers: blocked
            )
        )
    }

    func testBlockPruningRemovesCachedProfile() {
        ProfilePersistedCacheCoordinator.persist(
            viewerID: viewerA,
            targetProfileID: target,
            state: makeLoadedState(target: target, viewerIsOwner: false)
        )
        ProfilePersistedCacheCoordinator.pruneBlockedPeer(target)
        XCTAssertNil(ProfileDiskCache.loadSnapshot(viewerID: viewerA, targetProfileID: target))
    }

    func testTradeMutationPatchesProfileAndFeedEntityCaches() {
        let trade = makeTrade(id: "trade-1", owner: target)
        ProfilePersistedCacheCoordinator.persist(
            viewerID: viewerA,
            targetProfileID: target,
            state: makeLoadedState(target: target, viewerIsOwner: false, trades: [trade])
        )
        FeedPersistedCacheCoordinator.persistFirstPage(
            viewerID: viewerA,
            scope: .following,
            contentFilter: .all,
            entries: [.trade(makeFeedItem(for: trade), trade)],
            stories: [],
            nextCursor: nil
        )

        var updated = trade
        updated.publicCaption = "updated caption"
        ProfilePersistedCacheCoordinator.patchTrade(updated, viewerID: viewerA)
        FeedPersistedCacheCoordinator.patchTrade(updated, viewerID: viewerA)

        let profileBlob = ProfileDiskCache.loadSnapshot(viewerID: viewerA, targetProfileID: target)
        XCTAssertEqual(profileBlob?.trades.first?.publicCaption, "updated caption")
        let feedBlob = FeedDiskCache.loadPage(viewerID: viewerA, scope: .following, contentFilter: .all)
        if case .trade(_, let cachedTrade) = feedBlob?.entries.first {
            XCTAssertEqual(cachedTrade.publicCaption, "updated caption")
        } else {
            XCTFail("Expected feed trade row")
        }
        XCTAssertNotNil(SocialEntityDiskCache.loadTrade(id: trade.id, viewerID: viewerA))
    }

    func testReconcileUpdatesTradesWithoutDuplicating() {
        let existing = makeTrade(id: "trade-1", owner: target, caption: "old")
        let incoming = makeTrade(id: "trade-1", owner: target, caption: "new")
        let result = ProfilePersistentReconcile.reconcileTrades(
            existing: [existing],
            incoming: [incoming]
        )
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.publicCaption, "new")
        XCTAssertEqual(result.counts.updated, 1)
    }

    func testCorruptedProfileCacheFallsBackToNil() {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            XCTFail("Missing caches directory")
            return
        }
        let folder = dir.appendingPathComponent(ProfileDiskCache.folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("profile-page-\(viewerA.rawValue)-\(target.rawValue).json")
        try? Data("{bad".utf8).write(to: file)

        XCTAssertNil(ProfileDiskCache.loadSnapshot(viewerID: viewerA, targetProfileID: target))
    }

    func testLogoutClearsProfileDiskCache() {
        ProfilePersistedCacheCoordinator.persist(
            viewerID: viewerA,
            targetProfileID: target,
            state: makeLoadedState(target: target, viewerIsOwner: false)
        )
        ProfilePersistedCacheCoordinator.clear(viewerID: viewerA)
        XCTAssertNil(ProfileDiskCache.loadSnapshot(viewerID: viewerA, targetProfileID: target))
    }

    func testPaginationCursorPreservedInProfileSnapshot() {
        var state = makeLoadedState(target: target, viewerIsOwner: false)
        state.tradesNextCursor = "cursor-page-2"
        ProfilePersistedCacheCoordinator.persist(
            viewerID: viewerA,
            targetProfileID: target,
            state: state
        )
        let loaded = ProfileDiskCache.loadSnapshot(viewerID: viewerA, targetProfileID: target)
        XCTAssertEqual(loaded?.tradesNextCursor, "cursor-page-2")
    }

    // MARK: - Helpers

    private func makeLoadedState(
        target: ProfileID,
        viewerIsOwner: Bool,
        trades: [Trade]? = nil
    ) -> ProfileState {
        var state = ProfileState()
        state.phase = .loaded
        state.profileID = target
        state.profile = Profile(
            id: target,
            userID: UserID(target.rawValue),
            username: "target-user",
            displayName: "Target User",
            bio: "bio",
            avatar: nil,
            traderType: .futures,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: .now
        )
        state.stats = ProfileStats(
            profileID: target,
            followerCount: 10,
            followingCount: 5,
            postCount: 2,
            tradeCount: 1,
            publicTradeCount: 1,
            winRate: 0.5,
            profitFactor: nil,
            netPnL: nil,
            averageRR: nil,
            payoutTotal: nil,
            expectancy: nil
        )
        state.isOwner = viewerIsOwner
        state.canViewTrades = true
        state.didBootstrap = true
        state.didLoadTrades = true
        state.trades = trades ?? [makeTrade(id: "trade-1", owner: target)]
        return state
    }

    private func makeTrade(id: String, owner: ProfileID, caption: String = "caption") -> Trade {
        let now = Date()
        return Trade(
            id: TradeID(id),
            ownerProfileID: owner,
            accountID: nil,
            symbol: Symbol(ticker: "AAPL"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 100,
            exitPrice: 110,
            entryAt: now,
            exitAt: now,
            realizedPnL: Money(amount: 10),
            riskReward: nil,
            points: nil,
            sessionLabel: nil,
            visibility: .public,
            publicCaption: caption,
            thumbnail: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    private func makeFeedItem(for trade: Trade) -> FeedItem {
        FeedItem(
            id: "feed-\(trade.id.rawValue)",
            kind: .trade,
            authorProfileID: trade.ownerProfileID,
            createdAt: trade.createdAt,
            tradeID: trade.id,
            postID: PostID("feed-\(trade.id.rawValue)"),
            reelID: nil,
            storyID: nil,
            achievementID: nil,
            caption: trade.publicCaption,
            likeCount: 0,
            commentCount: 0,
            viewerHasLiked: false
        )
    }
}
