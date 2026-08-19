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
    }

    func testReportMailtoIncludesSupportAddressAndLink() {
        let url = DetailContentLink.post(PostID("abc")).reportMailtoURL
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "mailto")
        XCTAssertTrue(url?.absoluteString.contains("support@tradetraxs.com") == true)
        XCTAssertTrue(url?.absoluteString.contains("post") == true)
    }
}
