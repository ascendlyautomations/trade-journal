import XCTest
@testable import TradeTraxs

final class StoryBootstrapMappingTests: XCTestCase {
    func testMapsActiveStoryPreview() {
        let created = Date()
        let preview = FeedStoryPreviewV1(
            id: "story-1",
            user_id: "user-1",
            image_url: "https://cdn.example/story.jpg",
            created_at: ISO8601.string(from: created)
        )
        let story = StoryBootstrapMapping.map(preview)
        XCTAssertEqual(story?.id.rawValue, "story-1")
        XCTAssertEqual(story?.authorProfileID.rawValue, "user-1")
        XCTAssertEqual(story?.media.id, "https://cdn.example/story.jpg")
    }

    func testRejectsExpiredStoryPreview() {
        let expired = Date().addingTimeInterval(-(ActiveStorySemantics.window + 60))
        let preview = FeedStoryPreviewV1(
            id: "story-old",
            user_id: "user-1",
            image_url: "https://cdn.example/story.jpg",
            created_at: ISO8601.string(from: expired)
        )
        XCTAssertNil(StoryBootstrapMapping.map(preview))
    }

    func testNewestActiveReturnsLatestCreated() {
        let now = Date()
        let older = Story(
            id: StoryID("s1"),
            authorProfileID: ProfileID("u1"),
            media: MediaReference(id: "a", kind: .image, altText: nil),
            expiresAt: now.addingTimeInterval(ActiveStorySemantics.window),
            createdAt: now.addingTimeInterval(-3600),
            viewerHasSeen: false
        )
        let newer = Story(
            id: StoryID("s2"),
            authorProfileID: ProfileID("u1"),
            media: MediaReference(id: "b", kind: .image, altText: nil),
            expiresAt: now.addingTimeInterval(ActiveStorySemantics.window),
            createdAt: now,
            viewerHasSeen: false
        )
        XCTAssertEqual(StoryBootstrapMapping.newestActive([older, newer])?.id, newer.id)
    }
}
