import XCTest
@testable import TradeTraxs

final class StoryViewerContinuationTests: XCTestCase {
    func testDeletingTheLastSlideOfAnAuthorMovesToTheNextAuthor() {
        var sequence = StoryViewerContinuation()
        let viewer = ProfileID("viewer")
        let firstAuthor = ProfileID("author-a")
        let nextAuthor = ProfileID("author-b")
        sequence.install(
            catalog: [
                slide("a1", author: firstAuthor, age: -300),
                slide("a2", author: firstAuthor, age: -10),
                slide("b1", author: nextAuthor, age: -60),
            ],
            viewerID: viewer
        )
        let lastOfAuthor = sequence.position(of: StoryID("a2"))
        let destination = sequence.remove(
            storyIDs: [StoryID("a2")],
            viewingAuthorIndex: lastOfAuthor?.authorIndex ?? 0,
            viewingSlideIndex: lastOfAuthor?.slideIndex ?? 0
        )
        guard case .showing(let authorIndex, let slideIndex) = destination else {
            return XCTFail("Expected the next author")
        }
        XCTAssertEqual(sequence.slides(at: authorIndex)[slideIndex].id.rawValue, "b1")
    }

    func testDeletingTheFinalAuthorDismissesEvenWhenEarlierAuthorsRemain() {
        var sequence = StoryViewerContinuation()
        let viewer = ProfileID("viewer")
        let earlier = ProfileID("author-a")
        let last = ProfileID("author-b")
        sequence.install(
            catalog: [
                slide("a1", author: earlier, age: -30),
                slide("b1", author: last, age: -120),
            ],
            viewerID: viewer
        )
        let position = sequence.position(of: StoryID("b1"))
        let destination = sequence.remove(
            storyIDs: [StoryID("b1")],
            viewingAuthorIndex: position?.authorIndex ?? 0,
            viewingSlideIndex: position?.slideIndex ?? 0
        )
        XCTAssertEqual(destination, .dismiss)
    }

    func testExpiredSlidesLeaveTheSequence() {
        var sequence = StoryViewerContinuation()
        let viewer = ProfileID("viewer")
        let author = ProfileID("author-a")
        let fresh = slide("fresh", author: author, age: -30)
        var expired = slide("stale", author: author, age: -60)
        expired.createdAt = Date().addingTimeInterval(-(25 * 60 * 60))
        sequence.install(catalog: [expired, fresh], viewerID: viewer, now: Date())
        XCTAssertNil(sequence.position(of: expired.id))
        XCTAssertEqual(sequence.position(of: fresh.id)?.slideIndex, 0)
    }

    private func slide(_ id: String, author: ProfileID, age: TimeInterval) -> Story {
        let created = Date().addingTimeInterval(age)
        return Story(
            id: StoryID(id),
            authorProfileID: author,
            media: MediaReference(id: id, kind: .image, altText: nil),
            expiresAt: created.addingTimeInterval(ActiveStorySemantics.window),
            createdAt: created,
            viewerHasSeen: false
        )
    }
}
