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

    func testContentLikeRouteSharedUntilFinalRelease() async {
        let provider = makeProvider()
        let table = ContentLikeTable.reelLikes
        let ids = ["reel-a"]
        let routeKey = "content-likes:\(ContentLikeSemantics.stableRouteSuffix(table: table, contentIDs: ids))"

        let watchA = provider.watchContentLikes(table: table, contentIDs: ids, accessToken: nil, debugOwner: "A")
        await settle()
        let watchB = provider.watchContentLikes(table: table, contentIDs: ids, accessToken: nil, debugOwner: "B")
        await settle()

        XCTAssertEqual(provider.testing_routeSnapshot(routeKey: routeKey).consumerCount, 2)

        await provider.releaseWatch(watchA.consumer)
        await settle()
        XCTAssertEqual(provider.testing_routeSnapshot(routeKey: routeKey).consumerCount, 1)

        await provider.releaseWatch(watchB.consumer)
        await settle()
        XCTAssertEqual(provider.testing_routeSnapshot(routeKey: routeKey).consumerCount, 0)
        _ = watchA
        _ = watchB
    }

    func testRepeatedRetentionDoesNotDuplicateRoutes() async {
        EngagementRealtimeSession.shared.invalidate()
        let provider = makeProvider()
        let hub = RealtimeHub(realtime: provider)
        let store = EngagementStore(repository: RealtimeStubInteractionRepository())
        EngagementRealtimeSession.shared.configure(
            realtimeHub: hub,
            session: FixedViewerSession(viewerID: "viewer-retain"),
            database: StubDatabaseExecutor(),
            engagementStore: store
        )
        let target = InteractionTarget.reel(ReelID("reel-retain-1"))
        store.seed(baseSnapshot(count: 2), for: target)

        EngagementRealtimeSession.shared.updateRetention(ownerKey: "test", targets: [target])
        await settle()
        let first = EngagementRealtimeSession.shared.testing_activeRouteCount()

        EngagementRealtimeSession.shared.updateRetention(ownerKey: "test", targets: [target])
        await settle()
        let second = EngagementRealtimeSession.shared.testing_activeRouteCount()

        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 1)
        EngagementRealtimeSession.shared.invalidate()
    }

    func testLogoutClearsEngagementRoutes() async {
        let provider = makeProvider()
        let hub = RealtimeHub(realtime: provider)
        let store = EngagementStore(repository: RealtimeStubInteractionRepository())
        EngagementRealtimeSession.shared.configure(
            realtimeHub: hub,
            session: FixedViewerSession(viewerID: "viewer-logout"),
            database: StubDatabaseExecutor(),
            engagementStore: store
        )
        let target = InteractionTarget.profilePost(PostID("post-1"))
        store.seed(baseSnapshot(count: 1), for: target)
        EngagementRealtimeSession.shared.updateRetention(ownerKey: "test", targets: [target])
        await settle()
        XCTAssertGreaterThan(EngagementRealtimeSession.shared.testing_activeRouteCount(), 0)

        EngagementRealtimeSession.shared.invalidate()
        await settle()
        XCTAssertEqual(EngagementRealtimeSession.shared.testing_activeRouteCount(), 0)
    }

    // MARK: - Helpers

    private func makeProvider() -> LiveSupabaseRealtimeProvider {
        LiveSupabaseRealtimeProvider(
            configuration: AppConfiguration(
                buildConfiguration: .debug,
                apiBaseURL: nil,
                supabaseURL: URL(string: "https://example.supabase.co"),
                supabaseAnonKey: "anon",
                appDisplayName: "TradeTraxs"
            )
        )
    }

    private func settle() async {
        try? await Task.sleep(nanoseconds: 120_000_000)
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

private struct StubDatabaseExecutor: SupabaseDatabaseExecuting {
    var isConfigured: Bool { false }

    func select<T>(
        _: T.Type,
        from _: String,
        query _: [URLQueryItem],
        headers _: [String: String]
    ) async throws -> [T] where T: Decodable {
        []
    }

    func selectOne<T>(_: T.Type, from _: String, query _: [URLQueryItem]) async throws -> T where T: Decodable {
        throw AppError.unknown(message: "stub")
    }

    func count(from _: String, query _: [URLQueryItem]) async throws -> Int { 0 }

    func insert<Body, T>(
        _: Body,
        into _: String,
        query _: [URLQueryItem],
        returning _: T.Type
    ) async throws -> T where Body: Encodable, T: Decodable {
        throw AppError.unknown(message: "stub")
    }

    func insert<Body>(_: Body, into _: String) async throws where Body: Encodable {}

    func update<Body, T>(
        _: Body,
        table _: String,
        query _: [URLQueryItem],
        returning _: T.Type
    ) async throws -> T where Body: Encodable, T: Decodable {
        throw AppError.unknown(message: "stub")
    }

    func update<Body>(_: Body, table _: String, query _: [URLQueryItem]) async throws where Body: Encodable {}

    func upsert<Body, T>(
        _: Body,
        into _: String,
        onConflict _: String,
        returning _: T.Type,
        select _: String
    ) async throws -> T where Body: Encodable, T: Decodable {
        throw AppError.unknown(message: "stub")
    }

    func delete(from _: String, query _: [URLQueryItem]) async throws {}
    func rpcData(functionName _: String, parametersJSON _: Data?) async throws -> Data {
        throw AppError.unknown(message: "stub")
    }
}
