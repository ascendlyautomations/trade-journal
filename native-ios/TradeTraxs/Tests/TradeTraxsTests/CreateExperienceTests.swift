import XCTest
@testable import TradeTraxs

@MainActor
final class CreateExperienceTests: XCTestCase {
    override func tearDown() {
        ContentMutationStore.shared.invalidate()
        super.tearDown()
    }

    func testCreatePostRequiresBodyOrImage() async {
        var dismissed = false
        let viewModel = CreatePostViewModel(
            profiles: CreateStubProfileRepository(),
            session: CreateStubSession(userID: CreatePostFixtures.viewerID.rawValue),
            uploadService: CreateStubUpload(),
            objectStorage: CreateStubStorage(),
            onDismiss: { dismissed = true }
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .ready }
        viewModel.publish()
        await waitFor { viewModel.formError != nil }
        XCTAssertFalse(dismissed)

        viewModel.bodyText = "Hello traders"
        viewModel.publish()
        await waitFor { dismissed }
        XCTAssertTrue(dismissed)
        XCTAssertEqual(ContentMutationStore.shared.revision, 1)
    }

    func testCreatePostFailedPublishPreservesDraft() async {
        var dismissed = false
        let viewModel = CreatePostViewModel(
            profiles: CreateFailingProfileRepository(),
            session: CreateStubSession(userID: "user.real"),
            uploadService: CreateStubUpload(),
            objectStorage: CreateStubStorage(),
            onDismiss: { dismissed = true }
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .ready }
        viewModel.bodyText = "Keep me"
        viewModel.publish()
        await waitFor { viewModel.formError != nil }
        XCTAssertEqual(viewModel.bodyText, "Keep me")
        XCTAssertFalse(dismissed)
    }

    func testAchievementRequiresImageAndPayoutForPayoutType() async {
        var dismissed = false
        let viewModel = CreateAchievementViewModel(
            achievements: CreateStubAchievementRepository(),
            trades: CreateStubTradeRepository(),
            session: CreateStubSession(userID: CreateAchievementFixtures.viewerID.rawValue),
            uploadService: CreateStubUpload(),
            objectStorage: CreateStubStorage(),
            onDismiss: { dismissed = true }
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .ready }
        viewModel.kind = .propFirmPayout
        viewModel.titleText = "First payout"
        viewModel.publish()
        await waitFor { viewModel.formError != nil }
        XCTAssertFalse(dismissed)

        #if DEBUG
        viewModel.applyScreenshotImageFixture()
        #endif
        viewModel.payoutAmountText = "2500"
        viewModel.publish()
        await waitFor { dismissed || viewModel.formError == nil }
        // Dev path should dismiss after valid publish when image fixture applied.
        if viewModel.finalImageData != nil {
            XCTAssertTrue(dismissed)
        }
    }

    func testOnlyUserCreatableAchievementKindsExposed() {
        let kinds = CreateAchievementViewModel.allKinds
        XCTAssertEqual(
            Set(kinds.map(\.rawValue)),
            Set(["prop_firm_payout", "live_trading_payout", "passed_eval", "milestone"])
        )
    }

    func testImageCropJSONEncodesNumericCoordinatesNotBooleans() throws {
        let presentation = ContentImagePresentation.make(
            aspectOption: .portrait,
            imagePixelSize: CGSize(width: 1206, height: 2622),
            viewportSize: CGSize(width: 390, height: 487.5),
            transform: .default
        )
        let jsonValue = try XCTUnwrap(ContentImagePresentationCodec.encodeJSONValue(presentation))
        let wire = try JSONEncoder().encode(jsonValue)
        let object = try JSONSerialization.jsonObject(with: wire) as? [String: Any]
        let crop = object?["normalized_crop"] as? [String: Any]
        XCTAssertEqual(crop?["x"] as? Double, 0, accuracy: 0.0001)
        XCTAssertEqual(crop?["y"] as? Double, 0, accuracy: 0.0001)
        XCTAssertEqual(crop?["width"] as? Double, 1, accuracy: 0.0001)
        XCTAssertEqual(crop?["height"] as? Double, 1, accuracy: 0.0001)

        let legacyCorrupt = """
        {"presentation_aspect_ratio":0.8,"normalized_crop":{"x":false,"y":false,"width":true,"height":true},"aspect_mode":"portrait"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ContentImagePresentation.self, from: legacyCorrupt)
        XCTAssertEqual(decoded.normalizedCrop?.x, 0, accuracy: 0.0001)
        XCTAssertEqual(decoded.normalizedCrop?.width, 1, accuracy: 0.0001)
    }

    func testCreateReelRequiresVideo() async {
        var dismissed = false
        let viewModel = CreateReelViewModel(
            feed: CreateStubFeedRepository(),
            trades: CreateStubTradeRepository(),
            session: CreateStubSession(userID: CreateReelFixtures.viewerID.rawValue),
            detailCache: DetailPresentationCache(),
            uploadService: CreateStubUpload(),
            objectStorage: CreateStubStorage(),
            onDismiss: { dismissed = true }
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .ready }
        viewModel.publish()
        await waitFor { viewModel.formError != nil }
        XCTAssertFalse(dismissed)
        XCTAssertEqual(viewModel.formError, "Choose a video to continue.")
    }

    func testCreateReelDraftPreservationAndLinkTrade() async throws {
        var dismissed = false
        let viewModel = CreateReelViewModel(
            feed: CreateStubFeedRepository(),
            trades: CreateStubTradeRepository(),
            session: CreateStubSession(userID: CreateReelFixtures.viewerID.rawValue),
            detailCache: DetailPresentationCache(),
            uploadService: CreateStubUpload(),
            objectStorage: CreateStubStorage(),
            onDismiss: { dismissed = true }
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .ready }
        viewModel.applyScreenshotFixture(filled: true)
        XCTAssertNotNil(viewModel.draft)
        XCTAssertFalse(viewModel.captionEnabled)
        XCTAssertNotNil(viewModel.linkedTradeSummary)
        let linked = try XCTUnwrap(viewModel.linkedTrade)
        XCTAssertNotNil(ProfileCardMediaPresence.tradeMedia(in: linked))
        viewModel.clearLinkedTrade()
        XCTAssertTrue(viewModel.captionEnabled)
        viewModel.captionText = "Standalone note"
        viewModel.publish()
        await waitFor { dismissed }
        XCTAssertEqual(ContentMutationStore.shared.latestReelID?.rawValue, "dev-reel-created")
    }

    func testStoryUploadValidationMatchesWebLimits() {
        XCTAssertEqual(StoryUploadValidation.maxBytes, 15 * 1024 * 1024)
        XCTAssertEqual(
            StoryUploadValidation.validate(data: Data(), contentType: "image/jpeg", fileName: "a.jpg"),
            "File is empty."
        )
        let oversized = Data(repeating: 0, count: StoryUploadValidation.maxBytes + 1)
        XCTAssertEqual(
            StoryUploadValidation.validate(data: oversized, contentType: "image/jpeg", fileName: "big.jpg"),
            "Image must be 15 MB or smaller."
        )
        XCTAssertEqual(
            StoryUploadValidation.validate(data: Data([0xFF]), contentType: "video/mp4", fileName: "clip.mp4"),
            "File must be an image (JPEG, PNG, WebP, or GIF)."
        )
        XCTAssertNil(
            StoryUploadValidation.validate(data: Data([0xFF]), contentType: "image/jpeg", fileName: "story.jpg")
        )
    }

    func testCreateReelDuplicatePublishPrevention() async {
        let feed = CreateCountingFeedRepository()
        var dismissed = false
        let viewModel = CreateReelViewModel(
            feed: feed,
            trades: CreateStubTradeRepository(),
            session: CreateStubSession(userID: "user.real"),
            detailCache: DetailPresentationCache(),
            uploadService: CreateStubUpload(),
            objectStorage: CreateStubStorage(),
            onDismiss: { dismissed = true }
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .ready }
        viewModel.draft = CreateReelFixtures.screenshotDraft()
        viewModel.publish()
        viewModel.publish()
        await waitFor { dismissed }
        XCTAssertEqual(feed.createCalls, 1)
        XCTAssertEqual(ContentMutationStore.shared.revision, 1)
    }

    func testCreateReelPreflightBlocksTradeWithExistingClip() async {
        let trade = CreateReelFixtures.sampleTrade()
        let feed = CreatePreflightBlockingFeedRepository(blockedTradeID: trade.id)
        var dismissed = false
        let viewModel = CreateReelViewModel(
            feed: feed,
            trades: CreateStubTradeRepository(),
            session: CreateStubSession(userID: "user.real"),
            detailCache: DetailPresentationCache(),
            uploadService: CreateStubUpload(),
            objectStorage: CreateStubStorage(),
            onDismiss: { dismissed = true }
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .ready }
        var draft = CreateReelFixtures.screenshotDraft(linkedTrade: trade)
        draft.linkedTradeID = trade.id
        viewModel.draft = draft
        viewModel.publish()
        await waitFor { viewModel.formError != nil }
        XCTAssertFalse(dismissed)
        XCTAssertEqual(feed.createCalls, 0)
        XCTAssertEqual(feed.preflightCalls, 1)
        XCTAssertEqual(
            viewModel.formError,
            "This trade already has a clip attached."
        )
    }

    func testMediaVideoDurationFormattingAndLimits() {
        XCTAssertEqual(MediaVideoPreparation.formatDuration(12), "0:12")
        XCTAssertEqual(MediaVideoPreparation.formatDuration(90), "1:30")
        XCTAssertEqual(MediaVideoPreparation.maxDurationSeconds, 90)
        XCTAssertEqual(MediaVideoPreparation.maxFileBytes, 100 * 1024 * 1024)
        XCTAssertEqual(MediaVideoPreparation.maxFinalUploadBytes, 100 * 1024 * 1024)
        XCTAssertEqual(MediaVideoPreparation.maxSourceFileBytes, 500 * 1024 * 1024)
        XCTAssertEqual(MediaVideoPreparation.maxCaptionLength, 2200)
    }

    private func waitFor(timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) async {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Timed out")
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

// MARK: - Stubs

private struct CreateStubSession: SessionProviding {
    let userID: String?
    var currentUserID: UserID? { get async { userID.map { UserID($0) } } }
    var accessToken: String? { get async { userID == nil ? nil : "token" } }
}

private struct CreateStubUpload: UploadService {
    func upload(_ request: UploadRequest) async throws -> MediaReference {
        MediaReference(id: request.path, kind: .image, altText: nil)
    }
}

private struct CreateStubStorage: ObjectStorageProviding {
    func upload(bucket: String, path: String, data: Data, contentType: String, cacheControl: String? = nil) async throws -> String { path }
    func download(bucket: String, path: String) async throws -> Data { Data() }
    func delete(bucket: String, path: String) async throws {}
    func publicURL(bucket: String, path: String) -> URL? {
        URL(string: "https://example.com/\(path)")
    }
}

private struct CreateStubProfileRepository: ProfileRepository {
    func currentUser() async throws -> User { User(id: UserID("u"), email: nil, createdAt: .now) }
    func profile(id: ProfileID) async throws -> Profile {
        Profile(
            id: id,
            userID: UserID(id.rawValue),
            username: "trader",
            displayName: "Trader",
            bio: nil,
            avatar: nil,
            traderType: nil,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: .now
        )
    }
    func profile(username: String) async throws -> Profile { try await profile(id: ProfileID(username)) }
    func updateProfile(_ profile: Profile) async throws -> Profile { profile }
    func stats(for profileID: ProfileID) async throws -> ProfileStats {
        ProfileStats(
            profileID: profileID,
            followerCount: 0,
            followingCount: 0,
            postCount: 0,
            tradeCount: 0,
            publicTradeCount: 0
        )
    }
    func wallPosts(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        CursorPage(items: [], nextCursor: nil)
    }
    func wallPost(id: PostID) async throws -> Post { throw AppError.unknown(message: "stub") }
    func createWallPost(
        authorID: ProfileID,
        content: String,
        imageURL: String?,
        imageCrop: ContentImagePresentation?
    ) async throws -> Post {
        Post(
            id: PostID("wall-1"),
            authorProfileID: authorID,
            body: content,
            media: ContentImagePresentation.mediaReference(url: imageURL, crop: imageCrop)
                .map { [$0] } ?? [],
            visibility: .public,
            linkedTradeID: nil,
            isPinned: false,
            createdAt: .now,
            updatedAt: .now
        )
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

private struct CreateFailingProfileRepository: ProfileRepository {
    func currentUser() async throws -> User { try await CreateStubProfileRepository().currentUser() }
    func profile(id: ProfileID) async throws -> Profile { try await CreateStubProfileRepository().profile(id: id) }
    func profile(username: String) async throws -> Profile { try await CreateStubProfileRepository().profile(username: username) }
    func updateProfile(_ profile: Profile) async throws -> Profile { profile }
    func stats(for profileID: ProfileID) async throws -> ProfileStats {
        try await CreateStubProfileRepository().stats(for: profileID)
    }
    func wallPosts(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        CursorPage(items: [], nextCursor: nil)
    }
    func wallPost(id: PostID) async throws -> Post { throw AppError.unknown(message: "stub") }
    func createWallPost(
        authorID: ProfileID,
        content: String,
        imageURL: String?,
        imageCrop: ContentImagePresentation?
    ) async throws -> Post {
        throw AppError.unknown(message: "network down")
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

private struct CreateStubAchievementRepository: AchievementRepository {
    func achievements(for profileID: ProfileID, page: PageRequest, publicOnly: Bool) async throws -> CursorPage<Achievement> {
        CursorPage(items: [], nextCursor: nil)
    }
    func achievement(id: AchievementID) async throws -> Achievement { throw AppError.unknown(message: "stub") }
    func save(_ achievement: Achievement) async throws -> Achievement {
        var copy = achievement
        copy.id = AchievementID("saved-ach")
        return copy
    }
}

private struct CreateStubTradeRepository: TradeRepository {
    func trade(id: TradeID) async throws -> Trade { throw AppError.unknown(message: "stub") }
    func trades(ownedBy: ProfileID, accountID: TradingAccountID?, page: PageRequest, publicOnly: Bool) async throws -> CursorPage<Trade> {
        CursorPage(items: CreateReelFixtures.sampleTrades(owner: ownedBy), nextCursor: nil)
    }
    func save(_ draft: TradeDraft) async throws -> Trade { throw AppError.unknown(message: "stub") }
    func update(_ trade: Trade) async throws -> Trade { trade }
    func delete(id: TradeID) async throws {}
    func images(for tradeID: TradeID) async throws -> [TradeImage] { [] }
    func notes(for tradeID: TradeID) async throws -> [TradeNote] { [] }
    func statistics(for profileID: ProfileID, interval: DateIntervalValue) async throws -> TradeStatistics {
        TradeStatistics(tradeCount: 0, winCount: 0, lossCount: 0, totalPnL: Money(amount: 0), averagePnL: Money(amount: 0), averageRiskReward: nil, winRate: 0)
    }
    func accounts(for profileID: ProfileID) async throws -> [TradingAccount] {
        CreateAchievementFixtures.accounts(owner: profileID)
    }
}

private struct CreateStubFeedRepository: FeedRepository {
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
            id: StoryID("stub-story"),
            authorProfileID: userID,
            media: MediaReference(id: imageURL, kind: .image, altText: nil),
            expiresAt: Date().addingTimeInterval(ActiveStorySemantics.window),
            createdAt: Date(),
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
    func unattachedReels(for profileID: ProfileID, limit: Int) async throws -> [Reel] { [] }
    func attachReel(id: ReelID, to tradeID: TradeID) async throws {}
    func tradeHasAttachedReel(_ tradeID: TradeID) async throws -> Bool { false }
}

private final class CreateCountingFeedRepository: FeedRepository, @unchecked Sendable {
    private(set) var createCalls = 0
    private var lastCreatedReel: Reel?

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
            id: StoryID("stub-story"),
            authorProfileID: userID,
            media: MediaReference(id: imageURL, kind: .image, altText: nil),
            expiresAt: Date().addingTimeInterval(ActiveStorySemantics.window),
            createdAt: Date(),
            viewerHasSeen: false
        )
    }
    func reel(id: ReelID) async throws -> ReelLoadResult {
        guard let lastCreatedReel, lastCreatedReel.id == id else {
            throw AppError.domain(.notFound(entity: "reel", id: id.rawValue))
        }
        return ReelLoadResult(reel: lastCreatedReel, embeddedTrade: nil)
    }
    func reels(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Reel> {
        CursorPage(items: [], nextCursor: nil)
    }
    func profileReels(for profileID: ProfileID) async throws -> ProfileReelsResult {
        ProfileReelsResult(reels: [], embeddedTrades: [])
    }
    func createReel(_ reel: Reel) async throws -> Reel {
        createCalls += 1
        try await Task.sleep(nanoseconds: 80_000_000)
        lastCreatedReel = reel
        return reel
    }
    func unattachedReels(for profileID: ProfileID, limit: Int) async throws -> [Reel] { [] }
    func attachReel(id: ReelID, to tradeID: TradeID) async throws {}
    func tradeHasAttachedReel(_ tradeID: TradeID) async throws -> Bool { false }
}

private final class CreatePreflightBlockingFeedRepository: FeedRepository, @unchecked Sendable {
    let blockedTradeID: TradeID
    private(set) var createCalls = 0
    private(set) var preflightCalls = 0

    init(blockedTradeID: TradeID) {
        self.blockedTradeID = blockedTradeID
    }

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
            id: StoryID("stub-story"),
            authorProfileID: userID,
            media: MediaReference(id: imageURL, kind: .image, altText: nil),
            expiresAt: Date().addingTimeInterval(ActiveStorySemantics.window),
            createdAt: Date(),
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
    func createReel(_ reel: Reel) async throws -> Reel {
        createCalls += 1
        return reel
    }
    func unattachedReels(for profileID: ProfileID, limit: Int) async throws -> [Reel] { [] }
    func attachReel(id: ReelID, to tradeID: TradeID) async throws {}
    func tradeHasAttachedReel(_ tradeID: TradeID) async throws -> Bool {
        preflightCalls += 1
        return tradeID == blockedTradeID
    }
}
