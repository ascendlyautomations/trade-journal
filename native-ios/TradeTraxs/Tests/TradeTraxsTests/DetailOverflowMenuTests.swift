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
