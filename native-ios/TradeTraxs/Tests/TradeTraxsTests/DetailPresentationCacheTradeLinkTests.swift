import XCTest
@testable import TradeTraxs

@MainActor
final class DetailPresentationCacheTradeLinkTests: XCTestCase {
    func testApplyReelTradeLinkIndexesReelForProfileCards() {
        let cache = DetailPresentationCache()
        let tradeID = TradeID("trade-link-1")
        let reel = Reel(
            id: ReelID("reel-unattached"),
            authorProfileID: ProfileID("owner-1"),
            video: MediaReference(id: "v.mp4", kind: .video, altText: nil),
            thumbnail: MediaReference(id: "t.jpg", kind: .image, altText: nil),
            caption: "Caption",
            visibility: .public,
            linkedTradeID: nil,
            durationSeconds: 10,
            createdAt: .now
        )
        cache.seed(reel)

        cache.applyReelTradeLink(reel: reel, tradeID: tradeID)

        XCTAssertEqual(cache.reel(linkedTo: tradeID)?.id, reel.id)
        XCTAssertEqual(cache.reel(id: reel.id)?.linkedTradeID, tradeID)
    }

    func testSeedClearsTradeLinkWhenReelUnlinked() {
        let cache = DetailPresentationCache()
        let tradeID = TradeID("trade-unlink-1")
        var reel = Reel(
            id: ReelID("reel-was-linked"),
            authorProfileID: ProfileID("owner-1"),
            video: MediaReference(id: "v.mp4", kind: .video, altText: nil),
            thumbnail: nil,
            caption: nil,
            visibility: .public,
            linkedTradeID: tradeID,
            durationSeconds: 5,
            createdAt: .now
        )
        cache.seed(reel)
        XCTAssertNotNil(cache.reel(linkedTo: tradeID))

        reel.linkedTradeID = nil
        cache.seed(reel)

        XCTAssertNil(cache.reel(linkedTo: tradeID))
        XCTAssertNil(cache.reel(id: reel.id)?.linkedTradeID)
    }

    func testVisibleLinkedReelResolvesFromCacheAfterApply() {
        let cache = DetailPresentationCache()
        let owner = ProfileID("owner-visible")
        let tradeID = TradeID("trade-visible")
        let reel = Reel(
            id: ReelID("reel-visible"),
            authorProfileID: owner,
            video: MediaReference(id: "v.mp4", kind: .video, altText: nil),
            thumbnail: MediaReference(id: "t.jpg", kind: .image, altText: nil),
            caption: "Linked",
            visibility: .public,
            linkedTradeID: nil,
            durationSeconds: 12,
            createdAt: .now
        )
        cache.applyReelTradeLink(reel: reel, tradeID: tradeID)

        let resolved = FeedLinkedContentResolver.visibleLinkedReel(
            for: tradeID,
            cache: cache,
            viewerID: owner
        )
        XCTAssertEqual(resolved?.id, reel.id)
    }

    func testClearReelTradeLinkClearsBothDirections() {
        let cache = DetailPresentationCache()
        let tradeID = TradeID("trade-bidir")
        let reel = Reel(
            id: ReelID("reel-bidir"),
            authorProfileID: ProfileID("owner-bidir"),
            video: MediaReference(id: "v.mp4", kind: .video, altText: nil),
            thumbnail: nil,
            caption: "Clip",
            visibility: .public,
            linkedTradeID: nil,
            durationSeconds: 8,
            createdAt: .now
        )
        cache.applyReelTradeLink(reel: reel, tradeID: tradeID)
        XCTAssertNotNil(cache.reel(linkedTo: tradeID))

        cache.clearReelTradeLink(reel: cache.reel(id: reel.id)!)

        XCTAssertNil(cache.reel(linkedTo: tradeID))
        XCTAssertNil(cache.reel(id: reel.id)?.linkedTradeID)
    }
}
