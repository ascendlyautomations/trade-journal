import XCTest
@testable import TradeTraxs

final class StoryInsightsMapperTests: XCTestCase {
    func testDecodeMapsViewersLikedFlagAndReplyCount() throws {
        let json = """
        {
          "meta": { "contract_version": "v1" },
          "data": {
            "story_id": "11111111-1111-1111-1111-111111111111",
            "view_count": 3,
            "like_count": 2,
            "reply_count": 1,
            "viewers": [
              {
                "id": "22222222-2222-2222-2222-222222222222",
                "username": "trader_a",
                "display_name": "Trader A",
                "avatar_url": "avatars/sample-a.jpg",
                "viewed_at": "2026-01-01T12:00:00Z",
                "liked": true,
                "replied": true
              }
            ],
            "likers": [],
            "repliers": []
          }
        }
        """
        let insights = try StoryInsightsMapper.decode(from: Data(json.utf8))
        XCTAssertEqual(insights.storyID.rawValue, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(insights.viewCount, 3)
        XCTAssertEqual(insights.likeCount, 2)
        XCTAssertEqual(insights.replyCount, 1)
        XCTAssertEqual(insights.viewers.count, 1)
        XCTAssertTrue(insights.viewers[0].liked)
        XCTAssertTrue(insights.viewers[0].replied)
        XCTAssertEqual(insights.viewers[0].username, "trader_a")
        XCTAssertEqual(insights.viewers[0].displayName, "Trader A")
    }

    func testDecodeMergesReplierNotInViewers() throws {
        let json = """
        {
          "meta": { "contract_version": "v1" },
          "data": {
            "story_id": "11111111-1111-1111-1111-111111111111",
            "view_count": 1,
            "like_count": 0,
            "reply_count": 1,
            "viewers": [],
            "likers": [],
            "repliers": [
              {
                "id": "33333333-3333-3333-3333-333333333333",
                "username": "replier_b",
                "display_name": "Replier B",
                "avatar_url": "avatars/sample-b.jpg",
                "replied_at": "2026-01-02T12:00:00Z",
                "replied": true
              }
            ]
          }
        }
        """
        let insights = try StoryInsightsMapper.decode(from: Data(json.utf8))
        XCTAssertEqual(insights.viewers.count, 1)
        XCTAssertTrue(insights.viewers[0].replied)
        XCTAssertEqual(insights.viewers[0].username, "replier_b")
    }
}