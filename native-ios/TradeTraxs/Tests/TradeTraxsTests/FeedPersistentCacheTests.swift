import XCTest
@testable import TradeTraxs

@MainActor
final class FeedPersistentCacheTests: XCTestCase {
    private let viewerA = ProfileID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private let viewerB = ProfileID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
    private let blockedPeer = ProfileID("dddddddd-dddd-dddd-dddd-dddddddddddd")

    override func tearDown() {
        FeedPersistedCacheCoordinator.clearAll()
        FeedSessionStore.shared.invalidate()
        FeedBlockedAuthorsFilter.shared.clear()
        #if DEBUG
        FeedPersistentCacheProbe.resetForTesting()
        #endif
        super.tearDown()
    }

    func testPagePersistsAndHydratesAcrossRelaunch() {
        let entries = [makeTradeEntry(id: "feed-1", author: viewerA, age: 60)]
        FeedPersistedCacheCoordinator.persistFirstPage(
            viewerID: viewerA,
            scope: .following,
            contentFilter: .all,
            entries: entries,
            stories: [],
            nextCursor: "cursor-2"
        )

        FeedSessionStore.shared.invalidate()
        XCTAssertTrue(
            FeedPersistedCacheCoordinator.hydrateSessionStore(viewerID: viewerA)
        )
        let key = FeedSessionStore.cacheKey(
            viewerID: viewerA,
            scope: .following,
            contentFilter: .all,
            cursor: nil
        )
        let restored = FeedSessionStore.shared.restore(key: key)
        XCTAssertEqual(restored?.entries.count, 1)
        XCTAssertEqual(restored?.entries.first?.id, "feed-1")
        XCTAssertEqual(restored?.nextCursor, "cursor-2")
    }

    func testViewerIsolationDoesNotCrossHydrate() {
        FeedPersistedCacheCoordinator.persistFirstPage(
            viewerID: viewerA,
            scope: .following,
            contentFilter: .all,
            entries: [makeTradeEntry(id: "feed-secret", author: viewerA, age: 30)],
            stories: [],
            nextCursor: nil
        )

        FeedSessionStore.shared.invalidate()
        XCTAssertFalse(
            FeedPersistedCacheCoordinator.hydrateSessionStore(viewerID: viewerB)
        )
    }

    func testEncodeDecodeRoundTripPreservesOrdering() {
        let older = makeTradeEntry(id: "feed-old", author: viewerA, age: 3600)
        let newer = makeTradeEntry(id: "feed-new", author: viewerA, age: 60)
        let blob = FeedDiskCache.PageBlob(
            viewerID: viewerA.rawValue,
            scope: FeedScope.following.rawValue,
            contentFilter: FeedContentFilter.all.rpcValue,
            savedAt: Date(),
            lastAccessedAt: Date(),
            entries: [older, newer],
            stories: [],
            nextCursor: nil
        )
        FeedDiskCache.savePage(blob)
        let loaded = FeedDiskCache.loadPage(
            viewerID: viewerA,
            scope: .following,
            contentFilter: .all
        )
        XCTAssertEqual(loaded?.entries.map(\.id), ["feed-new", "feed-old"])
    }

    func testReconcileInsertsUpdatesAndRemovesStaleWindowRows() {
        let stale = makeTradeEntry(id: "feed-stale", author: viewerA, age: 120)
        let kept = makeTradeEntry(id: "feed-kept", author: viewerA, age: 300)
        let incoming = [
            makeTradeEntry(id: "feed-kept", author: viewerA, age: 300, caption: "updated"),
            makeTradeEntry(id: "feed-new", author: viewerA, age: 30)
        ]

        let result = FeedPersistentReconcile.reconcileFirstPage(
            existing: [stale, kept],
            incoming: incoming
        )

        XCTAssertEqual(result.inserted, 1)
        XCTAssertEqual(result.updated, 1)
        XCTAssertEqual(result.removed, 1)
        XCTAssertEqual(result.entries.map(\.id), ["feed-new", "feed-kept"])
        if case .trade(let item, _) = result.entries.first(where: { $0.id == "feed-kept" }) {
            XCTAssertEqual(item.caption, "updated")
        } else {
            XCTFail("Expected kept trade row")
        }
    }

    func testDedupeKeepsFirstOccurrence() {
        let first = makeTradeEntry(id: "feed-1", author: viewerA, age: 60)
        let duplicate = makeTradeEntry(id: "feed-1", author: viewerA, age: 30, caption: "dup")
        let deduped = FeedPersistentReconcile.dedupe([first, duplicate])
        XCTAssertEqual(deduped.count, 1)
        if case .trade(let item, _) = deduped[0] {
            XCTAssertEqual(item.caption, first.item.caption)
        } else {
            XCTFail("Expected trade row")
        }
    }

    func testBlockPruningRemovesAuthorFromDisk() {
        let blockedEntry = makeTradeEntry(id: "feed-blocked", author: blockedPeer, age: 60)
        let allowedEntry = makeTradeEntry(id: "feed-allowed", author: viewerA, age: 120)
        FeedDiskCache.savePage(
            FeedDiskCache.PageBlob(
                viewerID: viewerA.rawValue,
                scope: FeedScope.following.rawValue,
                contentFilter: FeedContentFilter.all.rpcValue,
                savedAt: Date(),
                lastAccessedAt: Date(),
                entries: [blockedEntry, allowedEntry],
                stories: [],
                nextCursor: nil
            )
        )

        _ = FeedDiskCache.pruneBlockedAuthorsOnDisk(
            viewerID: viewerA,
            blocked: [blockedPeer]
        )

        let loaded = FeedDiskCache.loadPage(
            viewerID: viewerA,
            scope: .following,
            contentFilter: .all
        )
        XCTAssertEqual(loaded?.entries.map(\.id), ["feed-allowed"])
    }

    func testRemoveEntryDeletesFromDiskAndSessionStore() {
        FeedPersistedCacheCoordinator.persistFirstPage(
            viewerID: viewerA,
            scope: .following,
            contentFilter: .all,
            entries: [
                makeTradeEntry(id: "feed-1", author: viewerA, age: 60),
                makeTradeEntry(id: "feed-2", author: viewerA, age: 120)
            ],
            stories: [],
            nextCursor: nil
        )
        FeedPersistedCacheCoordinator.removeEntry(viewerID: viewerA, entryID: "feed-1")

        let loaded = FeedDiskCache.loadPage(
            viewerID: viewerA,
            scope: .following,
            contentFilter: .all
        )
        XCTAssertEqual(loaded?.entries.map(\.id), ["feed-2"])
    }

    func testCorruptedCacheFallsBackToNil() {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            XCTFail("Missing caches directory")
            return
        }
        let folder = dir.appendingPathComponent(FeedDiskCache.folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(
            "feed-page-\(viewerA.rawValue)-\(FeedScope.following.rawValue)-all.json"
        )
        try? Data("{not-json".utf8).write(to: file)

        XCTAssertNil(
            FeedDiskCache.loadPage(
                viewerID: viewerA,
                scope: .following,
                contentFilter: .all
            )
        )
    }

    func testExpiredCacheIsDiscarded() {
        let blob = FeedDiskCache.PageBlob(
            viewerID: viewerA.rawValue,
            scope: FeedScope.following.rawValue,
            contentFilter: FeedContentFilter.all.rpcValue,
            savedAt: Date(timeIntervalSinceNow: -(FeedDiskCache.hardExpirySeconds + 60)),
            lastAccessedAt: Date(timeIntervalSinceNow: -(FeedDiskCache.hardExpirySeconds + 60)),
            entries: [makeTradeEntry(id: "feed-old", author: viewerA, age: 60)],
            stories: [],
            nextCursor: "cursor-more"
        )
        FeedDiskCache.savePage(blob)

        XCTAssertNil(
            FeedDiskCache.loadPage(
                viewerID: viewerA,
                scope: .following,
                contentFilter: .all
            )
        )
    }

    func testPaginationCursorPreservedOnFirstPagePersist() {
        FeedPersistedCacheCoordinator.persistFirstPage(
            viewerID: viewerA,
            scope: .following,
            contentFilter: .all,
            entries: [makeTradeEntry(id: "feed-1", author: viewerA, age: 60)],
            stories: [],
            nextCursor: "cursor-page-2"
        )
        let loaded = FeedDiskCache.loadPage(
            viewerID: viewerA,
            scope: .following,
            contentFilter: .all
        )
        XCTAssertEqual(loaded?.nextCursor, "cursor-page-2")
    }

    func testLogoutClearsViewerFeedDiskCache() {
        FeedPersistedCacheCoordinator.persistFirstPage(
            viewerID: viewerA,
            scope: .following,
            contentFilter: .all,
            entries: [makeTradeEntry(id: "feed-1", author: viewerA, age: 60)],
            stories: [],
            nextCursor: nil
        )
        FeedPersistedCacheCoordinator.clear(viewerID: viewerA)
        XCTAssertNil(
            FeedDiskCache.loadPage(
                viewerID: viewerA,
                scope: .following,
                contentFilter: .all
            )
        )
    }

    // MARK: - Helpers

    private func makeTradeEntry(
        id: String,
        author: ProfileID,
        age: TimeInterval,
        caption: String = "caption"
    ) -> FeedTimelineEntry {
        let createdAt = Date(timeIntervalSinceNow: -age)
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
            publicCaption: caption,
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
            caption: caption,
            likeCount: 0,
            commentCount: 0,
            viewerHasLiked: false
        )
        return .trade(item, trade)
    }
}
