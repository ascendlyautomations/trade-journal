import XCTest
@testable import TradeTraxs

@MainActor
final class SocialEntityRealtimeTests: XCTestCase {
    func testParseEventBuildsPostPayload() {
        let event = SocialEntityRealtimeSemantics.parseEvent(
            table: .posts,
            mutation: .insert,
            record: [
                "id": "post-1",
                "user_id": "author-1",
                "content": "hello",
                "created_at": "2026-01-15T12:00:00Z",
            ],
            oldRecord: nil
        )
        XCTAssertEqual(event?.entityID, "post-1")
        XCTAssertEqual(event?.authorID, "author-1")
        XCTAssertEqual(event?.payload.caption, "hello")
        XCTAssertEqual(event?.mutation, .insert)
    }

    func testParseEventReturnsNilWhenEntityIDMissing() {
        let event = SocialEntityRealtimeSemantics.parseEvent(
            table: .posts,
            mutation: .delete,
            record: ["user_id": "author-1"],
            oldRecord: nil
        )
        XCTAssertNil(event)
    }

    func testBlockedAuthorMarkedInSessionFilter() {
        let blocked = ProfileID("blocked-author-10d")
        FeedBlockedAuthorsFilter.shared.noteBlock(peerID: blocked)
        defer { FeedBlockedAuthorsFilter.shared.noteUnblock(peerID: blocked) }
        XCTAssertTrue(FeedBlockedAuthorsFilter.shared.contains(blocked))
    }

    func testDeleteMutationUsesOldRecordWhenRecordNil() {
        let event = SocialEntityRealtimeSemantics.parseEvent(
            table: .posts,
            mutation: .delete,
            record: nil,
            oldRecord: [
                "id": "gone",
                "user_id": "author",
            ]
        )
        XCTAssertEqual(event?.entityID, "gone")
        XCTAssertEqual(event?.mutation, .delete)
    }
}
