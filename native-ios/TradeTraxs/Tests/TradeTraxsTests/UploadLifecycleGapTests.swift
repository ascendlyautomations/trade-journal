import XCTest
@testable import TradeTraxs

@MainActor
final class UploadLifecycleGapTests: XCTestCase {
    override func setUp() {
        super.setUp()
        GlobalUploadCoordinator.shared.resetForTesting()
    }

    override func tearDown() {
        GlobalUploadCoordinator.shared.resetForTesting()
        super.tearDown()
    }

    func testFailedPostDismissDeletesUploadedImageAndRetryKeepsIt() async {
        let profiles = LifecycleWallPostRepository()
        let storage = LifecycleObjectStorage()
        let uploads = LifecycleUploadService()
        profiles.failCreates = true
        let services = lifecycleServices(profiles: profiles, storage: storage, uploads: uploads)

        GlobalUploadCoordinator.shared.enqueuePost(
            spec: PostUploadSpec(
                authorID: ProfileID("user-lifecycle"),
                bodyText: "checkpoint",
                imageData: Data([0x01])
            ),
            services: services
        )
        await waitUntil {
            GlobalUploadCoordinator.shared.jobs.contains { $0.phase == .failed }
        }
        XCTAssertEqual(uploads.dataUploads, 1)
        XCTAssertTrue(storage.deleted.isEmpty)

        profiles.failCreates = false
        GlobalUploadCoordinator.shared.retry(jobID: GlobalUploadCoordinator.shared.jobs[0].id)
        await waitUntil {
            GlobalUploadCoordinator.shared.jobs.contains { $0.phase == .completed }
        }
        XCTAssertEqual(uploads.dataUploads, 1)
        XCTAssertEqual(profiles.createCalls, 2)
        XCTAssertTrue(storage.deleted.isEmpty)

        let completedID = GlobalUploadCoordinator.shared.jobs[0].id
        GlobalUploadCoordinator.shared.remove(jobID: completedID)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(storage.deleted.isEmpty)

        profiles.failCreates = true
        GlobalUploadCoordinator.shared.enqueuePost(
            spec: PostUploadSpec(
                authorID: ProfileID("user-lifecycle"),
                bodyText: "dismiss me",
                imageData: Data([0x02])
            ),
            services: services
        )
        await waitUntil {
            GlobalUploadCoordinator.shared.jobs.contains { $0.phase == .failed }
        }
        guard let failedID = GlobalUploadCoordinator.shared.jobs.first(where: { $0.phase == .failed })?.id else {
            XCTFail("Expected a failed post job")
            return
        }
        let uploadsBeforeDismiss = uploads.dataUploads
        GlobalUploadCoordinator.shared.remove(jobID: failedID)
        XCTAssertFalse(GlobalUploadCoordinator.shared.jobs.contains { $0.id == failedID })
        await waitUntil { !storage.deleted.isEmpty }
        XCTAssertEqual(uploads.dataUploads, uploadsBeforeDismiss)
        XCTAssertEqual(storage.deleted.count, 1)
        XCTAssertEqual(storage.deleted[0].bucket, StorageBucket.profilePosts.rawValue)
        XCTAssertTrue(storage.deleted[0].path.hasPrefix("user-lifecycle/opt/"))
    }

    func testFailedClipPreparationRetryDoesNotReplayCachedFailure() async throws {
        let ownedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lifecycle-prep-source-\(UUID().uuidString).mp4")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: ownedURL)
        defer { try? FileManager.default.removeItem(at: ownedURL) }

        struct CachedPrepFailure: Error {}
        let preparationTaskID = "prep-retry-\(UUID().uuidString)"
        await ReelBackgroundPreparationRegistry.shared.testingSeedCachedFailure(
            preparationTaskID: preparationTaskID,
            selectionID: preparationTaskID,
            ownedSourceURL: ownedURL,
            error: CachedPrepFailure()
        )

        do {
            _ = try await ReelBackgroundPreparationRegistry.shared.awaitPrepared(
                preparationTaskID: preparationTaskID
            )
            XCTFail("Expected cached failure")
        } catch is CachedPrepFailure {
            // expected
        }

        await ReelBackgroundPreparationRegistry.shared.prepareForRetryIfFailed(
            preparationTaskID: preparationTaskID,
            selectionID: preparationTaskID,
            ownedSourceURL: ownedURL,
            contentType: "video/mp4"
        )

        let taskRunning = await ReelBackgroundPreparationRegistry.shared.testingPreparationTaskIsRunning(
            preparationTaskID: preparationTaskID
        )
        XCTAssertTrue(taskRunning, "Retry should start a new preparation task")

        do {
            _ = try await ReelBackgroundPreparationRegistry.shared.awaitPrepared(
                preparationTaskID: preparationTaskID
            )
        } catch is CachedPrepFailure {
            XCTFail("Retry replayed the cached preparation failure")
        } catch {
            // Encoder may fail on stub bytes — still not the cached failure type.
        }
    }

    func testAmbiguousTransportFailureClassification() {
        XCTAssertTrue(UploadRetryRecovery.isAmbiguousTransportFailure(CancellationError()))
        XCTAssertTrue(UploadRetryRecovery.isAmbiguousTransportFailure(NetworkError.cancelled))
        XCTAssertTrue(
            UploadRetryRecovery.isAmbiguousTransportFailure(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
            )
        )
        XCTAssertFalse(
            UploadRetryRecovery.isAmbiguousTransportFailure(
                AppError.domain(.conflict(message: "duplicate"))
            )
        )
    }

    func testClipRetryAfterVerificationFailureDoesNotInsertAgain() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lifecycle-clip-\(UUID().uuidString).mp4")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let feed = LifecycleClipFeed()
        let storage = LifecycleObjectStorage()
        let uploads = LifecycleUploadService()
        let author = ProfileID("user-lifecycle")
        let services = lifecycleServices(feed: feed, storage: storage, uploads: uploads)
        let snapshot = ReelDraftSnapshot(
            selectionID: "clip-1",
            ownedSourceURL: nil,
            localVideoURL: fileURL,
            contentType: "video/mp4",
            byteCount: 4,
            durationSeconds: 1,
            thumbnailJPEG: nil,
            caption: "clip",
            linkedTradeID: nil,
            videoAssetState: .preparedDelivery
        )

        GlobalUploadCoordinator.shared.enqueueReel(
            spec: ReelUploadSpec(
                publishID: "clip-job-1",
                snapshot: snapshot,
                authorID: author,
                tradeIsPublic: nil,
                preparationTaskID: nil
            ),
            services: services
        )
        await waitUntil {
            GlobalUploadCoordinator.shared.jobs.contains { $0.id == "clip-job-1" && $0.phase == .failed }
        }
        XCTAssertEqual(feed.createCalls, 1)
        XCTAssertEqual(uploads.fileUploads, 1)
        XCTAssertTrue(storage.deleted.isEmpty)

        GlobalUploadCoordinator.shared.retry(jobID: "clip-job-1")
        await waitUntil {
            GlobalUploadCoordinator.shared.jobs.contains { $0.id == "clip-job-1" && $0.phase == .completed }
        }
        XCTAssertEqual(feed.createCalls, 1)
        XCTAssertEqual(feed.verifyCalls, 2)
        XCTAssertEqual(uploads.fileUploads, 1)
        XCTAssertTrue(storage.deleted.isEmpty)
    }

    func testDismissalKeepsMediaReferencedBySavedContent() {
        let imagePath = "user-lifecycle/opt/1.jpg"
        let referencedAchievement = FailedUploadDismissalCleanup.orphanedObjects(
            post: nil,
            achievement: AchievementUploadCheckpoint(
                uploadedImagePublicURL: "https://cdn.example/screenshots/\(imagePath)",
                uploadedImageStoragePath: imagePath,
                savedAchievementID: AchievementID("ach-1")
            ),
            trade: nil
        )
        XCTAssertTrue(referencedAchievement.isEmpty)

        let unreferencedAchievement = FailedUploadDismissalCleanup.orphanedObjects(
            post: nil,
            achievement: AchievementUploadCheckpoint(
                uploadedImagePublicURL: "https://cdn.example/screenshots/\(imagePath)",
                uploadedImageStoragePath: imagePath,
                savedAchievementID: nil
            ),
            trade: nil
        )
        XCTAssertEqual(
            unreferencedAchievement,
            [FailedUploadDismissalCleanup.Object(bucket: StorageBucket.screenshots.rawValue, path: imagePath)]
        )

        var savedTrade = emptyTradeCheckpoint()
        savedTrade.savedTradeID = TradeID("trade-1")
        savedTrade.uploadedScreenshotPublicURL = "https://cdn.example/screenshots/\(imagePath)"
        savedTrade.uploadedScreenshotStoragePath = imagePath
        savedTrade.reelVideoPublicURL = "https://cdn.example/reels/clip.mp4"
        savedTrade.reelVideoStoragePath = "user-lifecycle/videos/clip.mp4"
        XCTAssertTrue(
            FailedUploadDismissalCleanup.orphanedObjects(post: nil, achievement: nil, trade: savedTrade).isEmpty
        )

        var unsavedTrade = savedTrade
        unsavedTrade.savedTradeID = nil
        let orphans = FailedUploadDismissalCleanup.orphanedObjects(
            post: nil,
            achievement: nil,
            trade: unsavedTrade
        )
        XCTAssertEqual(
            Set(orphans.map(\.path)),
            Set([imagePath, "user-lifecycle/videos/clip.mp4"])
        )
    }

    func testNormalStoryCreationInsertsOnce() async {
        let feed = StoryRetryFeed()
        let storage = LifecycleObjectStorage()
        let uploads = LifecycleUploadService()
        let services = lifecycleServices(feed: feed, storage: storage, uploads: uploads)
        GlobalUploadCoordinator.shared.enqueueStory(
            spec: storySpec(),
            services: services
        )
        await waitUntil {
            GlobalUploadCoordinator.shared.jobs.contains { $0.phase == .completed }
        }
        XCTAssertEqual(feed.createCalls, 1)
        XCTAssertEqual(uploads.dataUploads, 1)
        XCTAssertTrue(storage.deleted.isEmpty)
    }

    func testLostStoryResponseDoesNotInsertAgain() async {
        let feed = StoryRetryFeed()
        feed.insertResult = .lostResponse
        let storage = LifecycleObjectStorage()
        let uploads = LifecycleUploadService()
        let services = lifecycleServices(feed: feed, storage: storage, uploads: uploads)
        GlobalUploadCoordinator.shared.enqueueStory(
            spec: storySpec(),
            services: services
        )
        await waitUntil {
            GlobalUploadCoordinator.shared.jobs.contains { $0.phase == .completed }
        }
        XCTAssertEqual(feed.createCalls, 1)
        XCTAssertEqual(feed.storedCount, 1)
        XCTAssertTrue(storage.deleted.isEmpty)
    }

    func testConfirmedStoryFailureRetriesTheSameMediaOnce() async {
        let feed = StoryRetryFeed()
        feed.insertResult = .rejected
        let storage = LifecycleObjectStorage()
        let uploads = LifecycleUploadService()
        let services = lifecycleServices(feed: feed, storage: storage, uploads: uploads)
        GlobalUploadCoordinator.shared.enqueueStory(
            spec: storySpec(),
            services: services
        )
        await waitUntil {
            GlobalUploadCoordinator.shared.jobs.contains { $0.phase == .failed }
        }
        XCTAssertEqual(feed.createCalls, 1)
        XCTAssertEqual(uploads.dataUploads, 1)
        XCTAssertTrue(storage.deleted.isEmpty)

        feed.insertResult = .success
        GlobalUploadCoordinator.shared.retry(jobID: GlobalUploadCoordinator.shared.jobs[0].id)
        await waitUntil {
            GlobalUploadCoordinator.shared.jobs.contains { $0.phase == .completed }
        }
        XCTAssertEqual(feed.createCalls, 2)
        XCTAssertEqual(uploads.dataUploads, 1)
        XCTAssertEqual(Set(uploads.paths).count, 1)
        XCTAssertEqual(feed.storedCount, 1)
        XCTAssertTrue(storage.deleted.isEmpty)
    }

    func testStoryLookupFailureDoesNotInsertAgain() async {
        let feed = StoryRetryFeed()
        feed.insertResult = .lostResponse
        feed.lookupFails = true
        let storage = LifecycleObjectStorage()
        let uploads = LifecycleUploadService()
        let services = lifecycleServices(feed: feed, storage: storage, uploads: uploads)
        GlobalUploadCoordinator.shared.enqueueStory(
            spec: storySpec(),
            services: services
        )
        await waitUntil {
            GlobalUploadCoordinator.shared.jobs.contains { $0.phase == .failed }
        }
        XCTAssertEqual(feed.createCalls, 1)
        XCTAssertEqual(feed.storedCount, 1)
        XCTAssertTrue(storage.deleted.isEmpty)

        GlobalUploadCoordinator.shared.retry(jobID: GlobalUploadCoordinator.shared.jobs[0].id)
        await waitUntil {
            GlobalUploadCoordinator.shared.jobs.contains { $0.phase == .failed }
        }
        XCTAssertEqual(feed.createCalls, 1)
        XCTAssertEqual(feed.storedCount, 1)
        XCTAssertTrue(storage.deleted.isEmpty)
    }

    private func storySpec() -> StoryUploadSpec {
        StoryUploadSpec(
            authorID: ProfileID("user-lifecycle"),
            imageData: Data([0x01]),
            contentType: "image/jpeg",
            originalFileName: "story.jpg"
        )
    }

    private func emptyTradeCheckpoint() -> TradeSaveUploadCheckpoint {
        TradeSaveUploadCheckpoint(
            uploadedScreenshotPublicURL: nil,
            uploadedScreenshotStoragePath: nil,
            savedTradeID: nil,
            clipAttached: false,
            reelLinked: false,
            publicFeedPostCompleted: false,
            reelVideoPublicURL: nil,
            reelVideoStoragePath: nil,
            reelThumbnailPublicURL: nil,
            reelThumbnailStoragePath: nil,
            linkedExistingReelID: nil
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) async {
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

@MainActor
private func lifecycleServices(
    profiles: any ProfileRepository = LifecycleWallPostRepository(),
    feed: any FeedRepository = LifecycleClipFeed(),
    storage: LifecycleObjectStorage = LifecycleObjectStorage(),
    uploads: LifecycleUploadService = LifecycleUploadService()
) -> GlobalUploadServices {
    GlobalUploadServices(
        feed: feed,
        profiles: profiles,
        trades: nil,
        achievements: nil,
        uploadService: uploads,
        objectStorage: storage,
        detailCache: DetailPresentationCache()
    )
}

private final class LifecycleUploadService: UploadService, @unchecked Sendable {
    private(set) var dataUploads = 0
    private(set) var fileUploads = 0
    private(set) var paths: [String] = []

    func upload(_ request: UploadRequest) async throws -> MediaReference {
        dataUploads += 1
        paths.append(request.path)
        return MediaReference(id: request.path, kind: .image, altText: nil)
    }

    func uploadFile(_ request: UploadFileRequest) async throws -> MediaReference {
        fileUploads += 1
        return MediaReference(id: request.path, kind: .video, altText: nil)
    }
}

private final class LifecycleObjectStorage: ObjectStorageProviding, @unchecked Sendable {
    private(set) var deleted: [(bucket: String, path: String)] = []

    func upload(
        bucket: String,
        path: String,
        data: Data,
        contentType: String,
        cacheControl: String?
    ) async throws -> String { path }

    func download(bucket: String, path: String) async throws -> Data { Data() }

    func delete(bucket: String, path: String) async throws {
        deleted.append((bucket, path))
    }

    func publicURL(bucket: String, path: String) -> URL? {
        URL(string: "https://cdn.example/\(bucket)/\(path)")
    }
}

private final class LifecycleWallPostRepository: ProfileRepository, @unchecked Sendable {
    var failCreates = false
    private(set) var createCalls = 0

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
        createCalls += 1
        if failCreates {
            throw AppError.unknown(message: "insert failed")
        }
        return Post(
            id: PostID("wall-1"),
            authorProfileID: authorID,
            body: content,
            media: [],
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

private final class LifecycleClipFeed: FeedRepository, @unchecked Sendable {
    private(set) var createCalls = 0
    private(set) var verifyCalls = 0
    private var saved: Reel?

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
        verifyCalls += 1
        if verifyCalls == 1 {
            throw AppError.unknown(message: "verify failed")
        }
        guard let saved, saved.id == id else {
            throw AppError.domain(.notFound(entity: "reel", id: id.rawValue))
        }
        return ReelLoadResult(reel: saved, embeddedTrade: nil)
    }
    func reels(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Reel> {
        CursorPage(items: [], nextCursor: nil)
    }
    func profileReels(for profileID: ProfileID) async throws -> ProfileReelsResult {
        ProfileReelsResult(reels: [], embeddedTrades: [])
    }
    func createReel(_ reel: Reel) async throws -> Reel {
        createCalls += 1
        saved = reel
        return reel
    }
    func unattachedReels(for profileID: ProfileID, limit: Int) async throws -> [Reel] { [] }
    func attachReel(id: ReelID, to tradeID: TradeID) async throws {}
    func tradeHasAttachedReel(_ tradeID: TradeID) async throws -> Bool { false }
}

private final class StoryRetryFeed: FeedRepository, @unchecked Sendable {
    enum InsertResult {
        case success
        case lostResponse
        case rejected
    }

    var insertResult: InsertResult = .success
    var lookupFails = false
    private(set) var createCalls = 0
    private(set) var storedCount = 0
    private var stored: [Story] = []

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
    func stories(for viewer: ProfileID) async throws -> [Story] {
        if lookupFails {
            throw AppError.unknown(message: "lookup failed")
        }
        return stored.filter { $0.authorProfileID == viewer }
    }
    func createStory(userID: ProfileID, imageURL: String) async throws -> Story {
        createCalls += 1
        let story = Story(
            id: StoryID("story-\(createCalls)"),
            authorProfileID: userID,
            media: MediaReference(id: imageURL, kind: .image, altText: nil),
            expiresAt: Date().addingTimeInterval(ActiveStorySemantics.window),
            createdAt: Date(),
            viewerHasSeen: false
        )
        switch insertResult {
        case .success:
            stored.append(story)
            storedCount = stored.count
            return story
        case .lostResponse:
            stored.append(story)
            storedCount = stored.count
            throw AppError.unknown(message: "lost response")
        case .rejected:
            throw AppError.unknown(message: "insert rejected")
        }
    }
    func reel(id: ReelID) async throws -> ReelLoadResult {
        throw AppError.unknown(message: "stub")
    }
    func reels(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Reel> {
        CursorPage(items: [], nextCursor: nil)
    }
    func profileReels(for profileID: ProfileID) async throws -> ProfileReelsResult {
        ProfileReelsResult(reels: [], embeddedTrades: [])
    }
    func createReel(_ reel: Reel) async throws -> Reel { reel }
    func tradeHasAttachedReel(_ tradeID: TradeID) async throws -> Bool { false }
}
