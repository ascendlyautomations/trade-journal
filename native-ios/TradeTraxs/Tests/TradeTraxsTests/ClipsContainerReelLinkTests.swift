import XCTest
@testable import TradeTraxs

@MainActor
final class ClipsContainerReelLinkTests: XCTestCase {
    func testApplyReelLinkMutationUpdatesVisibleClip() {
        let owner = ProfileID("owner-clips-link")
        let cache = DetailPresentationCache()
        let standalone = Reel(
            id: ReelID("reel-profile-list"),
            authorProfileID: owner,
            video: MediaReference(id: "v.mp4", kind: .video, altText: nil),
            thumbnail: MediaReference(id: "t.jpg", kind: .image, altText: nil),
            caption: "Before link",
            visibility: .public,
            linkedTradeID: nil,
            durationSeconds: 15,
            createdAt: .now
        )
        cache.seed(standalone)

        let store = NavigationStore()
        let viewModel = ClipsContainerViewModel(
            profileID: owner,
            feed: ClipsLinkStubFeed(),
            session: ClipsLinkStubSession(userID: owner.rawValue),
            navigationCoordinator: NavigationCoordinator(store: store),
            detailCache: cache,
            isOwner: true
        )
        var snapshot = ProfileState()
        snapshot.profileID = owner
        snapshot.clips = [standalone]
        snapshot.didLoadClips = true
        snapshot.didBootstrap = true
        snapshot.phase = .loaded
        viewModel.applyBootstrap(snapshot)
        XCTAssertNil(viewModel.items[0].linkedTradeID)

        let tradeID = TradeID("trade-for-clip")
        cache.applyReelTradeLink(reel: standalone, tradeID: tradeID)
        guard let linked = cache.reel(id: standalone.id) else {
            XCTFail("Missing linked reel in cache")
            return
        }

        viewModel.applyReelLinkMutation(linked)

        XCTAssertEqual(viewModel.items[0].linkedTradeID, tradeID)
        XCTAssertEqual(cache.reel(id: standalone.id)?.linkedTradeID, tradeID)
    }

    func testApplyReelLinkMutationRemovesLinkedTradeIndicator() {
        let owner = ProfileID("owner-clips-unlink")
        let cache = DetailPresentationCache()
        let tradeID = TradeID("trade-remove")
        let reel = Reel(
            id: ReelID("reel-profile-unlink"),
            authorProfileID: owner,
            video: MediaReference(id: "v.mp4", kind: .video, altText: nil),
            thumbnail: nil,
            caption: "Linked clip",
            visibility: .public,
            linkedTradeID: tradeID,
            durationSeconds: 9,
            createdAt: .now
        )
        cache.seed(reel)

        let store = NavigationStore()
        let viewModel = ClipsContainerViewModel(
            profileID: owner,
            feed: ClipsLinkStubFeed(),
            session: ClipsLinkStubSession(userID: owner.rawValue),
            navigationCoordinator: NavigationCoordinator(store: store),
            detailCache: cache,
            isOwner: true
        )
        var snapshot = ProfileState()
        snapshot.profileID = owner
        snapshot.clips = [reel]
        snapshot.didLoadClips = true
        snapshot.didBootstrap = true
        snapshot.phase = .loaded
        viewModel.applyBootstrap(snapshot)
        XCTAssertEqual(viewModel.items[0].linkedTradeID, tradeID)

        cache.clearReelTradeLink(reel: reel)
        guard let unlinked = cache.reel(id: reel.id) else {
            XCTFail("Missing unlinked reel in cache")
            return
        }
        viewModel.applyReelLinkMutation(unlinked)

        XCTAssertNil(viewModel.items[0].linkedTradeID)
    }
}

private struct ClipsLinkStubSession: SessionProviding {
    let userID: String?
    var currentUserID: UserID? { get async { userID.map { UserID($0) } } }
    var accessToken: String? { get async { userID == nil ? nil : "token" } }
}

private struct ClipsLinkStubFeed: FeedRepository {
    func feed(scope: FeedScope, contentFilter: FeedContentFilter, page: PageRequest) async throws -> FeedPageResult {
        FeedPageResult(items: [], nextCursor: nil, embeddedTrades: [])
    }
    func post(id: PostID) async throws -> Post { throw AppError.unknown(message: "stub") }
    func posts(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        CursorPage(items: [], nextCursor: nil)
    }
    func createPost(_ post: Post) async throws -> Post { post }
    func deletePost(id: PostID) async throws {}
    func comments(for postID: PostID, page: PageRequest) async throws -> CursorPage<Comment> {
        CursorPage(items: [], nextCursor: nil)
    }
    func addComment(_ comment: Comment) async throws -> Comment { comment }
    func setReaction(on item: FeedItem, kind: ReactionKind, isActive: Bool) async throws {}
    func stories(for viewer: ProfileID) async throws -> [Story] { [] }
    func createStory(userID: ProfileID, imageURL: String) async throws -> Story {
        Story(
            id: StoryID("s"),
            authorProfileID: userID,
            media: MediaReference(id: imageURL, kind: .image, altText: nil),
            expiresAt: .now,
            createdAt: .now,
            viewerHasSeen: false
        )
    }
    func reel(id: ReelID) async throws -> ReelLoadResult { throw AppError.unknown(message: "stub") }
    func reels(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Reel> {
        CursorPage(items: [], nextCursor: nil)
    }
    func profileReels(for profileID: ProfileID) async throws -> ProfileReelsResult {
        ProfileReelsResult(reels: [], embeddedTrades: [])
    }
    func createReel(_ reel: Reel) async throws -> Reel { reel }
    func unattachedReels(
        for profileID: ProfileID,
        limit: Int,
        includingReelID: ReelID?
    ) async throws -> [Reel] { [] }
    func tradeIDsWithAttachedReels(owner: ProfileID) async throws -> Set<TradeID> { [] }
    func attachReel(id: ReelID, to tradeID: TradeID) async throws {}
    func tradeHasAttachedReel(_ tradeID: TradeID) async throws -> Bool { false }
}
