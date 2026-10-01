import XCTest
@testable import TradeTraxs

final class DetailOverflowMenuTests: XCTestCase {
    func testContentLinksMatchDeepLinkPaths() {
        XCTAssertEqual(
            DetailContentLink.trade(TradeID("t1")).absoluteString,
            "https://www.tradetraxs.com/trade/t1"
        )
        XCTAssertEqual(
            DetailContentLink.post(PostID("p1")).absoluteString,
            "https://www.tradetraxs.com/post/p1"
        )
        XCTAssertEqual(
            DetailContentLink.reel(ReelID("r1")).absoluteString,
            "https://www.tradetraxs.com/reel/r1"
        )
        XCTAssertEqual(
            DetailContentLink.achievement(AchievementID("a1")).absoluteString,
            "https://www.tradetraxs.com/feed?achievement=a1"
        )
        XCTAssertEqual(
            DetailContentLink.story(StoryID("s1")).absoluteString,
            "https://www.tradetraxs.com/story/s1"
        )
    }

    func testFeedTradeShareUsesTradeURLNotFeedPostURL() {
        let summary = TradeSummary(
            id: TradeID("trade-1"),
            ownerProfileID: ProfileID("owner-1"),
            symbol: Symbol(ticker: "ES"),
            side: .long,
            realizedPnL: nil,
            riskReward: nil,
            points: nil,
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
            publicAccountBadge: nil,
            durationSeconds: nil,
            durationText: nil
        )
        let item = FeedItem(
            id: "feed-post-9",
            kind: .trade,
            authorProfileID: ProfileID("owner-1"),
            createdAt: .now,
            tradeID: summary.id,
            postID: PostID("feed-post-9"),
            reelID: nil,
            achievementID: nil,
            caption: nil,
            likeCount: 0,
            commentCount: 0,
            viewerHasLiked: false
        )
        let target = SharedContentShareTarget.from(entry: .trade(item, summary), author: nil)
        XCTAssertEqual(target.contentLink, .trade(TradeID("trade-1")))
        XCTAssertEqual(
            target.contentLink.absoluteString,
            "https://www.tradetraxs.com/trade/trade-1"
        )
        if case .feedPost(let postID) = target.reference {
            XCTAssertEqual(postID, PostID("feed-post-9"))
        } else {
            XCTFail("Internal share should keep the feed post id")
        }
    }

    func testReportTargetMappingForEachContentKind() {
        let owner = ProfileID("owner-1")
        XCTAssertEqual(
            DetailContentLink.trade(TradeID("t1")).reportTarget(ownerID: owner).type,
            .trade
        )
        XCTAssertEqual(
            DetailContentLink.reel(ReelID("r1")).reportSubjectTitle,
            "this clip"
        )
    }
}
