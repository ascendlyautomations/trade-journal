import XCTest
@testable import TradeTraxs

@MainActor
final class SocialEntityRealtimeTests: XCTestCase {
    func testDuplicateInsertEventIsIgnored() async {
        SocialEntityRealtimeProcessor.shared.resetSession()
        var deleteCount = 0
        let viewer = ProfileID("viewer-dup")
        SocialEntityRealtimeProcessor.shared.bindFeed(
            SocialEntityRealtimeProcessor.FeedContext(
                viewerID: viewer,
                scope: .global,
                contentFilter: .all,
                trackedEntityIDsByTable: [.posts: ["post-dup"]],
                onInsert: { _ in },
                onUpdate: { _ in },
                onDelete: { _ in deleteCount += 1 },
                persistFirstPage: {}
            )
        )
        let event = SocialEntityRealtimeEvent(
            table: .posts,
            mutation: .delete,
            entityID: "post-dup",
            authorID: "author",
            eventRowID: "post-dup",
            payload: .init()
        )
        await SocialEntityRealtimeProcessor.shared.handle(event, viewerUserID: viewer.rawValue)
        await SocialEntityRealtimeProcessor.shared.handle(event, viewerUserID: viewer.rawValue)
        XCTAssertEqual(deleteCount, 1)
    }

    func testDeleteIsIdempotent() async {
        SocialEntityRealtimeProcessor.shared.resetSession()
        var deleteCount = 0
        let viewer = ProfileID("viewer-del")
        SocialEntityRealtimeProcessor.shared.bindFeed(
            SocialEntityRealtimeProcessor.FeedContext(
                viewerID: viewer,
                scope: .global,
                contentFilter: .all,
                trackedEntityIDsByTable: [.posts: ["p1"]],
                onInsert: { _ in },
                onUpdate: { _ in },
                onDelete: { _ in deleteCount += 1 },
                persistFirstPage: {}
            )
        )
        let event = SocialEntityRealtimeEvent(
            table: .posts,
            mutation: .delete,
            entityID: "p1",
            authorID: "author",
            eventRowID: "p1",
            payload: .init()
        )
        await SocialEntityRealtimeProcessor.shared.handle(event, viewerUserID: viewer.rawValue)
        await SocialEntityRealtimeProcessor.shared.handle(event, viewerUserID: viewer.rawValue)
        XCTAssertEqual(deleteCount, 1)
    }

    func testBlockedAuthorInsertIgnored() async {
        SocialEntityRealtimeProcessor.shared.resetSession()
        let blocked = ProfileID("blocked-author-10d")
        FeedBlockedAuthorsFilter.shared.noteBlock(peerID: blocked)
        defer { FeedBlockedAuthorsFilter.shared.noteUnblock(peerID: blocked) }

        var insertCount = 0
        let viewer = ProfileID("viewer-block")
        SocialEntityRealtimeProcessor.shared.bindFeed(
            SocialEntityRealtimeProcessor.FeedContext(
                viewerID: viewer,
                scope: .following,
                contentFilter: .all,
                trackedEntityIDsByTable: [:],
                onInsert: { _ in insertCount += 1 },
                onUpdate: { _ in },
                onDelete: { _ in },
                persistFirstPage: {}
            )
        )
        let event = SocialEntityRealtimeEvent(
            table: .posts,
            mutation: .insert,
            entityID: "blocked-post",
            authorID: blocked.rawValue,
            eventRowID: "blocked-post",
            payload: .init()
        )
        await SocialEntityRealtimeProcessor.shared.handle(event, viewerUserID: viewer.rawValue)
        XCTAssertEqual(insertCount, 0)
    }

    func testStaleHydrationCannotResurrectAfterDelete() async {
        SocialEntityRealtimeProcessor.shared.resetSession()
        let viewer = ProfileID("viewer-tomb")
        var entries: [String] = ["alive"]
        SocialEntityRealtimeProcessor.shared.bindFeed(
            SocialEntityRealtimeProcessor.FeedContext(
                viewerID: viewer,
                scope: .global,
                contentFilter: .all,
                trackedEntityIDsByTable: [.posts: ["alive"]],
                onInsert: { _ in entries.append("inserted") },
                onUpdate: { _ in },
                onDelete: { id in entries.removeAll { $0 == id } },
                persistFirstPage: {}
            )
        )
        let delete = SocialEntityRealtimeEvent(
            table: .posts,
            mutation: .delete,
            entityID: "alive",
            authorID: "a",
            eventRowID: "alive",
            payload: .init()
        )
        await SocialEntityRealtimeProcessor.shared.handle(delete, viewerUserID: viewer.rawValue)
        XCTAssertTrue(entries.isEmpty)
    }
}
