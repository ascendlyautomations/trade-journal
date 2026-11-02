import XCTest
@testable import TradeTraxs

@MainActor
final class VaultContentNavigationTests: XCTestCase {
    func testVaultFeedPostMapsToSharedFeedPostReference() {
        let ref = VaultContentRef(contentType: .feedPost, contentID: "post-feed-1")
        XCTAssertEqual(ref.sharedContentReference, .feedPost(PostID("post-feed-1")))
    }

    func testVaultProfilePostMapsToSharedProfilePostReference() {
        let ref = VaultContentRef(contentType: .profilePost, contentID: "post-wall-1")
        XCTAssertEqual(ref.sharedContentReference, .profilePost(PostID("post-wall-1")))
    }

    func testPushPostDetailRecordsFeedPostLoadSource() {
        let store = NavigationStore()
        store.selectedTab = .profile
        let coordinator = NavigationCoordinator(store: store)
        coordinator.markAuthenticated()
        let postID = PostID("feed-post-nav")
        coordinator.pushPostDetail(postID, loadSource: .feedPost)
        XCTAssertEqual(coordinator.postDetailLoadSource(for: postID), .feedPost)
    }

    func testFeedDeepLinkDefaultsFeedPostLoadSource() {
        let store = NavigationStore()
        store.selectedTab = .feed
        let coordinator = NavigationCoordinator(store: store)
        coordinator.markAuthenticated()
        let postID = PostID("deep-link-post")
        coordinator.pushFeed(.post(postID))
        XCTAssertEqual(coordinator.postDetailLoadSource(for: postID), .feedPost)
    }

    func testFeedTimelineProfilePostUsesProfileLoadSource() {
        let store = NavigationStore()
        store.selectedTab = .feed
        let coordinator = NavigationCoordinator(store: store)
        coordinator.markAuthenticated()
        let postID = PostID("profile-on-feed")
        coordinator.pushFeedProfilePost(postID)
        XCTAssertEqual(coordinator.postDetailLoadSource(for: postID), .profilePost)
    }

    func testFeedPostDetailLoadsFromFeedRepositoryCold() async {
        let post = ProfilePostFixtures.samples(owner: ProfileID("vault-feed-owner"))[0]
        let feed = VaultFeedPostStubRepository(post: post)
        let profiles = VaultStubProfileRepository()
        let cache = DetailPresentationCache()
        let coordinator = NavigationCoordinator(store: NavigationStore())

        let viewModel = PostDetailViewModel(
            postID: post.id,
            loadSource: .feedPost,
            profiles: profiles,
            feed: feed,
            session: PlaceholderSessionProvider(),
            imagePipeline: VaultTestImagePipeline(),
            cache: cache,
            navigationCoordinator: coordinator
        )
        viewModel.loadIfNeeded()
        for _ in 0..<30 {
            if case .loaded = viewModel.phase { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        if case .loaded = viewModel.phase {
            XCTAssertEqual(viewModel.post?.id, post.id)
        } else {
            XCTFail("Expected loaded phase, got \(viewModel.phase)")
        }
        XCTAssertEqual(feed.postFetchCount, 1)
    }

    func testProfilePostDetailLoadsFromWallPostCold() async {
        let post = ProfilePostFixtures.samples(owner: ProfileID("vault-wall-owner"))[0]
        let feed = VaultFeedPostStubRepository(post: nil)
        let profiles = VaultStubProfileRepository(wallPost: post)
        let cache = DetailPresentationCache()
        let coordinator = NavigationCoordinator(store: NavigationStore())

        let viewModel = PostDetailViewModel(
            postID: post.id,
            loadSource: .profilePost,
            profiles: profiles,
            feed: feed,
            session: PlaceholderSessionProvider(),
            imagePipeline: VaultTestImagePipeline(),
            cache: cache,
            navigationCoordinator: coordinator
        )
        viewModel.loadIfNeeded()
        for _ in 0..<30 {
            if case .loaded = viewModel.phase { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        if case .loaded = viewModel.phase {
            XCTAssertEqual(viewModel.post?.id, post.id)
        } else {
            XCTFail("Expected loaded phase, got \(viewModel.phase)")
        }
        XCTAssertEqual(profiles.wallPostFetchCount, 1)
        XCTAssertEqual(feed.postFetchCount, 0)
    }

    func testFeedPostNotFoundShowsUnavailableNotRetryPresentation() async {
        let feed = VaultFeedPostStubRepository(post: nil)
        let viewModel = PostDetailViewModel(
            postID: PostID("missing-feed-post"),
            loadSource: .feedPost,
            profiles: VaultStubProfileRepository(),
            feed: feed,
            session: PlaceholderSessionProvider(),
            imagePipeline: VaultTestImagePipeline(),
            cache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )
        viewModel.loadIfNeeded()
        for _ in 0..<30 {
            if case .failed = viewModel.phase { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        guard case .failed(let failure) = viewModel.phase else {
            return XCTFail("Expected failure")
        }
        XCTAssertEqual(failure.message, "This content is unavailable.")
        XCTAssertFalse(failure.isRetryable)
    }
}

// MARK: - Stubs

private final class VaultFeedPostStubRepository: FeedRepository, @unchecked Sendable {
    var post: Post?
    private(set) var postFetchCount = 0

    init(post: Post?) {
        self.post = post
    }

    func post(id: PostID) async throws -> Post {
        postFetchCount += 1
        guard let post, post.id == id else {
            throw AppError.domain(.notFound(entity: "posts", id: id.rawValue))
        }
        return post
    }

    func feed(scope: FeedScope, contentFilter: FeedContentFilter, page: PageRequest) async throws -> FeedPageResult {
        FeedPageResult(items: [], nextCursor: nil, embeddedTrades: [])
    }

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
            id: StoryID("stub"),
            authorProfileID: userID,
            media: MediaReference(id: imageURL, kind: .image, altText: nil),
            expiresAt: Date().addingTimeInterval(ActiveStorySemantics.window),
            createdAt: Date(),
            viewerHasSeen: false
        )
    }

    func deleteStory(id: StoryID) async throws {}
    func reel(id: ReelID) async throws -> ReelLoadResult {
        throw AppError.notImplemented(feature: "reel")
    }

    func reels(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Reel> {
        CursorPage(items: [], nextCursor: nil)
    }

    func profileReels(for profileID: ProfileID) async throws -> ProfileReelsResult {
        ProfileReelsResult(reels: [], embeddedTrades: [])
    }

    func createReel(_ reel: Reel) async throws -> Reel { reel }
}

private final class VaultStubProfileRepository: ProfileRepository, @unchecked Sendable {
    var wallPostResult: Post?
    private(set) var wallPostFetchCount = 0

    init(wallPost: Post? = nil) {
        self.wallPostResult = wallPost
    }

    func currentUser() async throws -> User { throw AppError.notImplemented(feature: "user") }
    func profile(id: ProfileID) async throws -> Profile { throw AppError.notImplemented(feature: "profile") }
    func profile(username: String) async throws -> Profile { throw AppError.notImplemented(feature: "profile") }
    func updateProfile(_ profile: Profile) async throws -> Profile { profile }
    func stats(for profileID: ProfileID) async throws -> ProfileStats { throw AppError.notImplemented(feature: "stats") }
    func wallPosts(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        CursorPage(items: [], nextCursor: nil)
    }

    func wallPost(id: PostID) async throws -> Post {
        wallPostFetchCount += 1
        guard let wallPostResult, wallPostResult.id == id else {
            throw AppError.domain(.notFound(entity: "profile_posts", id: id.rawValue))
        }
        return wallPostResult
    }

    func followState(from viewer: ProfileID, to target: ProfileID) async throws -> FollowState { .none }
    func follow(from viewer: ProfileID, to target: ProfileID) async throws {}
    func unfollow(from viewer: ProfileID, to target: ProfileID) async throws {}
    func followers(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }

    func following(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }

    func creator(for profileID: ProfileID) async throws -> Creator? { nil }
}

private struct VaultTestImagePipeline: ImagePipeline {
    func data(for request: ImageRequest) async throws -> Data { Data() }
    func prefetch(_ requests: [ImageRequest]) async {}
    func invalidate(reference: MediaReference) async {}
}
