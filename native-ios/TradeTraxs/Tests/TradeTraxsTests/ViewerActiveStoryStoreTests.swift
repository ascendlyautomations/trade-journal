import XCTest
@testable import TradeTraxs

@MainActor
final class ViewerActiveStoryStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ViewerActiveStoryStore.shared.invalidate()
        FeedSessionStore.shared.invalidate()
    }

    override func tearDown() {
        ViewerActiveStoryStore.shared.invalidate()
        FeedSessionStore.shared.invalidate()
        super.tearDown()
    }

    func testResolveActiveViewerStoryRequiresNonExpiredStory() {
        let viewerID = ProfileID("viewer-1")
        let active = makeStory(id: "s1", author: viewerID, age: 60 * 60)
        let expired = makeStory(id: "s2", author: viewerID, age: 25 * 60 * 60)

        XCTAssertEqual(
            ViewerActiveStoryStore.resolveActiveViewerStory(from: [active, expired], viewerID: viewerID)?.id,
            active.id
        )
        XCTAssertNil(
            ViewerActiveStoryStore.resolveActiveViewerStory(from: [expired], viewerID: viewerID)
        )
    }

    func testApplyStoryCreatedAndDeletedUpdatesIndicator() {
        let viewerID = ProfileID("viewer-1")
        let store = ViewerActiveStoryStore.shared
        let story = makeStory(id: "s1", author: viewerID, age: 30)

        store.applyStoryCreated(story, viewerID: viewerID)
        XCTAssertEqual(store.activeStory?.id, story.id)

        store.applyStoryDeleted(story.id)
        XCTAssertNil(store.activeStory)
    }

    func testReconcileFromFeedCacheUsesFollowingSnapshot() {
        let viewerID = ProfileID("viewer-1")
        let story = makeStory(id: "s1", author: viewerID, age: 120)
        let key = FeedSessionStore.cacheKey(
            viewerID: viewerID,
            scope: .following,
            contentFilter: .all,
            cursor: nil
        )
        FeedSessionStore.shared.save(
            FeedSessionStore.Snapshot(
                cacheKey: key,
                entries: [],
                stories: [story],
                nextCursor: nil,
                loadedAt: Date()
            )
        )

        ViewerActiveStoryStore.shared.reconcileFromFeedCache(viewerID: viewerID)
        XCTAssertEqual(ViewerActiveStoryStore.shared.activeStory?.id, story.id)
    }

    func testReconcileExpiredClearsStaleStory() {
        let viewerID = ProfileID("viewer-1")
        let store = ViewerActiveStoryStore.shared
        let createdAt = Date()
        let story = Story(
            id: StoryID("s1"),
            authorProfileID: viewerID,
            media: MediaReference(id: "https://example.com/s1.jpg", kind: .image, altText: nil),
            expiresAt: createdAt.addingTimeInterval(ActiveStorySemantics.window),
            createdAt: createdAt,
            viewerHasSeen: false
        )
        store.applyStoryCreated(story, viewerID: viewerID, now: createdAt)
        XCTAssertNotNil(store.activeStory)

        store.reconcileExpired(now: createdAt.addingTimeInterval(25 * 60 * 60))
        XCTAssertNil(store.activeStory)
    }

    private func makeStory(id: String, author: ProfileID, age: TimeInterval) -> Story {
        let createdAt = Date().addingTimeInterval(-age)
        return Story(
            id: StoryID(id),
            authorProfileID: author,
            media: MediaReference(id: "https://example.com/\(id).jpg", kind: .image, altText: nil),
            expiresAt: createdAt.addingTimeInterval(ActiveStorySemantics.window),
            createdAt: createdAt,
            viewerHasSeen: false
        )
    }
}
