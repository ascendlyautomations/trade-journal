import XCTest
@testable import TradeTraxs

final class ActivityNotificationClientTests: XCTestCase {
    func testFollowBodyMatchesWebFollowingId() throws {
        let data = try JSONEncoder().encode(
            ActivityNotificationJSON.Follow(followingId: "user-2")
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["followingId"] as? String, "user-2")
        XCTAssertEqual(json.keys.count, 1)
    }

    func testFollowRequestBodyMatchesWebTargetId() throws {
        let data = try JSONEncoder().encode(
            ActivityNotificationJSON.FollowRequest(targetId: "user-2")
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["targetId"] as? String, "user-2")
        XCTAssertEqual(json.keys.count, 1)
    }

    func testCommentBodyMatchesWebCommentId() throws {
        let data = try JSONEncoder().encode(
            ActivityNotificationJSON.Comment(commentId: "comment-1")
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["commentId"] as? String, "comment-1")
        XCTAssertEqual(json.keys.count, 1)
    }

    func testLikeTargetsMatchWebKindPayloads() throws {
        let encoder = JSONEncoder()

        let trade = try jsonObject(
            encoder.encode(ActivityNotificationJSON.LikeEnvelope(target: .trade(tradeId: "t1")))
        )
        XCTAssertEqual(trade.kind, "trade")
        XCTAssertEqual(trade.body["tradeId"] as? String, "t1")

        let post = try jsonObject(
            encoder.encode(
                ActivityNotificationJSON.LikeEnvelope(
                    target: .post(postId: "p1", tradeId: "t2")
                )
            )
        )
        XCTAssertEqual(post.kind, "post")
        XCTAssertEqual(post.body["postId"] as? String, "p1")
        XCTAssertEqual(post.body["tradeId"] as? String, "t2")

        let profilePost = try jsonObject(
            encoder.encode(
                ActivityNotificationJSON.LikeEnvelope(
                    target: .profilePost(profilePostId: "pp1")
                )
            )
        )
        XCTAssertEqual(profilePost.kind, "profile_post")
        XCTAssertEqual(profilePost.body["profilePostId"] as? String, "pp1")

        let achievement = try jsonObject(
            encoder.encode(
                ActivityNotificationJSON.LikeEnvelope(
                    target: .achievementPost(achievementPostId: "ap1")
                )
            )
        )
        XCTAssertEqual(achievement.kind, "achievement_post")
        XCTAssertEqual(achievement.body["achievementPostId"] as? String, "ap1")

        let reel = try jsonObject(
            encoder.encode(ActivityNotificationJSON.LikeEnvelope(target: .reel(reelId: "r1")))
        )
        XCTAssertEqual(reel.kind, "reel")
        XCTAssertEqual(reel.body["reelId"] as? String, "r1")

        let comment = try jsonObject(
            encoder.encode(
                ActivityNotificationJSON.LikeEnvelope(
                    target: .commentLike(
                        commentID: "c1",
                        source: .tradeComments,
                        parent: .trade(TradeID("t1"))
                    )
                )
            )
        )
        XCTAssertEqual(comment.kind, "comment")
        XCTAssertEqual(comment.body["commentId"] as? String, "c1")
        XCTAssertEqual(comment.body["commentSource"] as? String, "trade_comments")
        XCTAssertEqual(comment.body["tradeId"] as? String, "t1")
        XCTAssertFalse(comment.body.keys.contains("postId"))
    }

    func testContentLikeTargetRouting() {
        XCTAssertEqual(
            encodedKind(.content(.trade(TradeID("t1")), contentID: "t1")),
            "trade"
        )
        XCTAssertEqual(
            encodedKind(.content(.feedPost(PostID("p1")), contentID: "p1")),
            "post"
        )
        XCTAssertEqual(
            encodedKind(.content(.profilePost(PostID("pp1")), contentID: "pp1")),
            "profile_post"
        )
        XCTAssertEqual(
            encodedKind(.content(.achievement(AchievementID("a1")), contentID: "ap1")),
            "achievement_post"
        )
        XCTAssertEqual(
            encodedKind(.content(.reel(ReelID("r1")), contentID: "r1")),
            "reel"
        )
    }

    private func encodedKind(_ target: ActivityNotificationJSON.LikeTarget) -> String {
        let data = try! JSONEncoder().encode(ActivityNotificationJSON.LikeEnvelope(target: target))
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let nested = json["target"] as! [String: Any]
        return nested["kind"] as! String
    }

    private func jsonObject(_ data: Data) throws -> (kind: String, body: [String: Any]) {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let target = try XCTUnwrap(json["target"] as? [String: Any])
        let kind = try XCTUnwrap(target["kind"] as? String)
        return (kind, target)
    }
}
