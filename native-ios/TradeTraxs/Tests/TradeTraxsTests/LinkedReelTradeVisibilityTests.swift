import XCTest
@testable import TradeTraxs

@MainActor
final class LinkedReelTradeVisibilityTests: XCTestCase {
    func testOrphanedLinkClearsLocalReelReference() {
        let owner = ProfileID("owner-unlink")
        let tradeID = TradeID("trade-gone")
        let cache = DetailPresentationCache()
        let reel = Reel(
            id: ReelID("reel-orphan"),
            authorProfileID: owner,
            video: MediaReference(id: "v.mp4", kind: .video, altText: nil),
            thumbnail: nil,
            caption: "Clip",
            visibility: .public,
            linkedTradeID: tradeID,
            durationSeconds: 8,
            createdAt: .now
        )
        cache.seed(reel)
        cache.seed(trades: [ProfileTradeFixtures.samples(owner: owner)[0]])

        let reconciled = LinkedReelTradeVisibility.reconcileOrphanedReelLink(
            reel: reel,
            cache: cache,
            serverTradeLinkRemoved: true
        )

        XCTAssertNil(reconciled.linkedTradeID)
        XCTAssertNil(cache.reel(id: reel.id)?.linkedTradeID)
    }

    func testResolvedTradeRequiresEmbeddedOrAuthoritativeCache() {
        let owner = ProfileID("owner-resolved")
        let trade = ProfileTradeFixtures.samples(owner: owner)[0]
        let cache = DetailPresentationCache()
        cache.seedAuthoritativeDetail(trade, authority: .authoritativeMutation)

        let reel = Reel(
            id: ReelID("reel-link"),
            authorProfileID: owner,
            video: MediaReference(id: "v.mp4", kind: .video, altText: nil),
            thumbnail: nil,
            caption: "Clip",
            visibility: .public,
            linkedTradeID: trade.id,
            durationSeconds: 8,
            createdAt: .now
        )

        XCTAssertNotNil(
            LinkedReelTradeVisibility.resolvedTrade(
                reel: reel,
                embeddedTrade: nil,
                cache: cache,
                viewerID: owner
            )
        )

        XCTAssertNil(
            LinkedReelTradeVisibility.resolvedTrade(
                reel: reel,
                embeddedTrade: nil,
                cache: cache,
                viewerID: ProfileID("stranger")
            )
        )
    }

    func testPrivateTradeHiddenFromNonOwnerEvenWithEmbed() {
        let owner = ProfileID("owner-private")
        var trade = ProfileTradeFixtures.samples(owner: owner)[0]
        trade.visibility = .private
        let reel = Reel(
            id: ReelID("reel-private-link"),
            authorProfileID: owner,
            video: MediaReference(id: "v.mp4", kind: .video, altText: nil),
            thumbnail: nil,
            caption: "Clip",
            visibility: .public,
            linkedTradeID: trade.id,
            durationSeconds: 8,
            createdAt: .now
        )

        XCTAssertNotNil(
            LinkedReelTradeVisibility.resolvedTrade(
                reel: reel,
                embeddedTrade: trade,
                cache: DetailPresentationCache(),
                viewerID: owner
            )
        )
        XCTAssertNil(
            LinkedReelTradeVisibility.resolvedTrade(
                reel: reel,
                embeddedTrade: trade,
                cache: DetailPresentationCache(),
                viewerID: ProfileID("stranger")
            )
        )
    }

    func testPrivateTradeDoesNotClearReelLinkLocally() {
        let owner = ProfileID("owner-keep-link")
        let tradeID = TradeID("trade-private")
        let cache = DetailPresentationCache()
        let reel = Reel(
            id: ReelID("reel-keep"),
            authorProfileID: owner,
            video: MediaReference(id: "v.mp4", kind: .video, altText: nil),
            thumbnail: nil,
            caption: "Clip",
            visibility: .public,
            linkedTradeID: tradeID,
            durationSeconds: 8,
            createdAt: .now
        )
        cache.seed(reel)

        let reconciled = LinkedReelTradeVisibility.reconcileOrphanedReelLink(
            reel: reel,
            cache: cache,
            serverTradeLinkRemoved: false
        )

        XCTAssertEqual(reconciled.linkedTradeID, tradeID)
    }
}
