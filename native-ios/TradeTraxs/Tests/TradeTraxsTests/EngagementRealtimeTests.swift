import XCTest
@testable import TradeTraxs

@MainActor
final class EngagementRealtimeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        #if DEBUG
        SocialPresentationWriteThroughProbe.resetForTesting()
        #endif
    }

    private func baseSnapshot(count: Int, liked: Bool = false) -> EngagementSnapshot {
        EngagementSnapshot(likeCount: count, commentCount: 0, viewerHasLiked: liked)
    }

    func testRemoteLikeIncrementsOnce() {
        let previous = baseSnapshot(count: 5)
        let next = ContentLikeSemantics.applyRealtimeEvent(
            previous,
            event: .insert,
            actorUserID: "peer-a",
            currentUserID: "viewer-a"
        )
        XCTAssertEqual(next.likeCount, 6)
        XCTAssertFalse(next.viewerHasLiked)
    }

    func testRemoteUnlikeDecrementsOnce() {
        let previous = baseSnapshot(count: 5)
        let next = ContentLikeSemantics.applyRealtimeEvent(
            previous,
            event: .delete,
            actorUserID: "peer-a",
            currentUserID: "viewer-a"
        )
        XCTAssertEqual(next.likeCount, 4)
    }

    func testViewerOptimisticLikeEchoDoesNotDoubleIncrement() {
        let previous = baseSnapshot(count: 5, liked: true)
        let optimistic = baseSnapshot(count: 6, liked: true)
        let echoed = ContentLikeSemantics.applyRealtimeEvent(
            optimistic,
            event: .insert,
            actorUserID: "viewer-a",
            currentUserID: "viewer-a"
        )
        XCTAssertEqual(previous.likeCount + 1, optimistic.likeCount)
        XCTAssertEqual(echoed.likeCount, 6)
        XCTAssertTrue(echoed.viewerHasLiked)
    }

    func testViewerOptimisticUnlikeEchoDoesNotDoubleDecrement() {
        let optimistic = baseSnapshot(count: 5, liked: false)
        let echoed = ContentLikeSemantics.applyRealtimeEvent(
            optimistic,
            event: .delete,
            actorUserID: "viewer-a",
            currentUserID: "viewer-a"
        )
        XCTAssertEqual(echoed.likeCount, 5)
        XCTAssertFalse(echoed.viewerHasLiked)
    }

    func testDuplicateInsertSemanticsStillIdempotentForViewerEcho() {
        let once = ContentLikeSemantics.applyRealtimeEvent(
            baseSnapshot(count: 5, liked: true),
            event: .insert,
            actorUserID: "viewer-a",
            currentUserID: "viewer-a"
        )
        let twice = ContentLikeSemantics.applyRealtimeEvent(
            once,
            event: .insert,
            actorUserID: "viewer-a",
            currentUserID: "viewer-a"
        )
        XCTAssertEqual(twice.likeCount, once.likeCount)
    }

    func testDuplicateDeleteSemanticsIdempotent() {
        let once = ContentLikeSemantics.applyRealtimeEvent(
            baseSnapshot(count: 1),
            event: .delete,
            actorUserID: "peer",
            currentUserID: "viewer"
        )
        let twice = ContentLikeSemantics.applyRealtimeEvent(
            once,
            event: .delete,
            actorUserID: "peer",
            currentUserID: "viewer"
        )
        XCTAssertEqual(twice.likeCount, once.likeCount)
    }

    func testNeverNegativeLikeCount() {
        let next = ContentLikeSemantics.applyRealtimeEvent(
            baseSnapshot(count: 0),
            event: .delete,
            actorUserID: "peer",
            currentUserID: "viewer"
        )
        XCTAssertEqual(next.likeCount, 0)
    }

    func testApplyContentLikeRealtimeWriteThrough() async {
        let viewer = ProfileID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        let target = InteractionTarget.feedPost(PostID("feed-realtime-like"))
        SocialPresentationWriteThroughCoordinator.shared.configure(
            session: FixedViewerSession(viewerID: viewer.rawValue)
        )

        let store = EngagementStore(repository: RealtimeStubInteractionRepository())
        store.configurePresentationWriteThrough(SocialPresentationWriteThroughCoordinator.shared)
        store.seed(baseSnapshot(count: 5), for: target)

        let generation = SocialPresentationWriteThroughGeneration.bump(viewerID: viewer, target: target)
        let copies = FeedPersistedCacheCoordinator.patchEngagement(
            viewerID: viewer,
            target: target,
            snapshot: baseSnapshot(count: 5),
            writeGeneration: generation
        )
        XCTAssertEqual(copies, 0)

        await store.applyContentLikeRealtime(
            on: target,
            signal: ContentLikeRealtimeSignal(
                table: .feedPostLikes,
                contentID: "feed-realtime-like",
                userID: "peer-9",
                kind: .insert,
                rowID: "like-row-1"
            ),
            viewerUserID: viewer.rawValue
        )

        XCTAssertEqual(store.snapshot(for: target).likeCount, 6)
        #if DEBUG
        XCTAssertGreaterThan(SocialPresentationWriteThroughProbe.propagationCount, 0)
        #endif
    }

    func testEngagementStorePrefetchDoesNotDuplicateInFlightWork() async {
        let store = EngagementStore(repository: RealtimeStubInteractionRepository())
        let target = InteractionTarget.reel(ReelID("reel-prefetch-1"))
        store.prefetch([target, target, target])
        store.prefetch([target])
        // No crash / duplicate task explosion — repository is stubbed empty.
        try? await Task.sleep(nanoseconds: 30_000_000)
    }
}

private struct FixedViewerSession: SessionProviding {
    let viewerID: String

    var currentUserID: UserID? {
        get async { UserID(viewerID) }
    }

    var accessToken: String? {
        get async { "token" }
    }
}

private final class RealtimeStubInteractionRepository: InteractionRepository, @unchecked Sendable {
    func engagement(for targets: [InteractionTarget]) async throws -> [InteractionTarget: EngagementSnapshot] {
        Dictionary(uniqueKeysWithValues: targets.map { ($0, .empty) })
    }

    func setLiked(_ liked: Bool, on target: InteractionTarget) async throws {}
    func comments(for target: InteractionTarget, order: CommentSortOrder) async throws -> [InteractionComment] {
        []
    }

    func addComment(
        body: String,
        parentID: CommentID?,
        on target: InteractionTarget
    ) async throws -> InteractionComment {
        throw AppError.unknown(message: "stub")
    }

    func deleteComment(id: CommentID, on target: InteractionTarget) async throws {}
    func commentLikeMeta(
        for commentIDs: [CommentID],
        source: CommentLikeSource
    ) async throws -> [CommentID: CommentLikeSnapshot] { [:] }
    func setCommentLiked(
        _ liked: Bool,
        commentID: CommentID,
        source: CommentLikeSource
    ) async throws {}
    func setCommentPinned(
        _ pinned: Bool,
        commentID: CommentID,
        on target: InteractionTarget
    ) async throws {}
}
