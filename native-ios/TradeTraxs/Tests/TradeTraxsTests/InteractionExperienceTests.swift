import XCTest
@testable import TradeTraxs

@MainActor
final class InteractionExperienceTests: XCTestCase {
    func testEngagementSnapshotTogglesLikeCounts() {
        let liked = EngagementSnapshot(likeCount: 2, commentCount: 1, viewerHasLiked: false)
            .togglingLike()
        XCTAssertTrue(liked.viewerHasLiked)
        XCTAssertEqual(liked.likeCount, 3)

        let unliked = liked.togglingLike()
        XCTAssertFalse(unliked.viewerHasLiked)
        XCTAssertEqual(unliked.likeCount, 2)
        XCTAssertEqual(unliked.commentCount, 1)
    }

    func testInteractionTargetsAreContentAgnostic() {
        let trade = InteractionTarget.trade(TradeID("t1"))
        let post = InteractionTarget.profilePost(PostID("p1"))
        let reel = InteractionTarget.reel(ReelID("r1"))
        let feed = InteractionTarget.feedPost(PostID("f1"))
        let achievement = InteractionTarget.achievement(AchievementID("a1"))

        XCTAssertEqual(trade.kind, .trade)
        XCTAssertEqual(post.kind, .profilePost)
        XCTAssertEqual(reel.kind, .reel)
        XCTAssertEqual(feed.kind, .feedPost)
        XCTAssertEqual(achievement.kind, .achievement)
        XCTAssertNotEqual(trade, post)
        XCTAssertNotEqual(achievement, feed)
    }

    func testCommentMappingPreservesAuthorAvatarURLFromProfilesJoin() {
        var row = InteractionDTO.CommentRow()
        row.id = "c-avatar-1"
        row.user_id = "author-1"
        row.trade_id = "t-1"
        row.content = "Nice trade"
        row.created_at = "2026-01-01T00:00:00Z"
        row.profiles = .init(
            username: "scalper",
            name: "Alex",
            avatar_url: "https://cdn.example.com/avatars/alex.png"
        )

        let mapped = DefaultInteractionRepository.mapComment(
            row,
            target: .trade(TradeID("t-1"))
        )

        XCTAssertEqual(mapped?.authorUsername, "scalper")
        XCTAssertEqual(mapped?.authorDisplayName, "Alex")
        XCTAssertEqual(mapped?.authorAvatarURL, "https://cdn.example.com/avatars/alex.png")
        XCTAssertEqual(
            mapped?.authorAvatarReference?.id,
            "https://cdn.example.com/avatars/alex.png"
        )
    }

    func testCommentMappingDropsBlankAvatarURL() {
        var row = InteractionDTO.CommentRow()
        row.id = "c-blank"
        row.user_id = "author-2"
        row.content = "Hi"
        row.profiles = .init(username: "no-pic", name: nil, avatar_url: "   ")

        let mapped = DefaultInteractionRepository.mapComment(
            row,
            target: .profilePost(PostID("p-1"))
        )

        XCTAssertNil(mapped?.authorAvatarURL)
        XCTAssertNil(mapped?.authorAvatarReference)
        XCTAssertEqual(mapped?.authorUsername, "no-pic")
    }

    func testOptimisticLikeUpdatesAndDedupesInFlight() async {
        let repository = InMemoryInteractionRepository()
        repository.likeDelayNanoseconds = 150_000_000
        let store = EngagementStore(repository: repository)
        let target = InteractionTarget.trade(TradeID("live-trade-1"))

        repository.engagementMap[target] = EngagementSnapshot(
            likeCount: 1,
            commentCount: 0,
            viewerHasLiked: false
        )
        store.prefetch([target])
        for _ in 0..<20 {
            if store.snapshot(for: target).likeCount == 1 { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let first = Task { await store.toggleLike(on: target) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        let second = Task { await store.toggleLike(on: target) }
        await first.value
        await second.value

        XCTAssertEqual(store.snapshot(for: target).likeCount, 2)
        XCTAssertTrue(store.snapshot(for: target).viewerHasLiked)
        XCTAssertEqual(repository.setLikedCalls.count, 1)
    }

    func testLikeRollbackOnFailure() async {
        let repository = InMemoryInteractionRepository()
        repository.shouldFailLike = true
        let store = EngagementStore(repository: repository)
        let target = InteractionTarget.profilePost(PostID("live-post-1"))
        repository.engagementMap[target] = .empty
        store.prefetch([target])
        try? await Task.sleep(nanoseconds: 20_000_000)

        await store.toggleLike(on: target)

        XCTAssertEqual(store.snapshot(for: target).likeCount, 0)
        XCTAssertFalse(store.snapshot(for: target).viewerHasLiked)
    }

    func testDevFixtureLikeSkipsNetwork() async {
        let repository = InMemoryInteractionRepository()
        let store = EngagementStore(repository: repository)
        let target = InteractionTarget.reel(ReelID("dev-reel-1"))

        await store.toggleLike(on: target)

        XCTAssertTrue(store.snapshot(for: target).viewerHasLiked)
        XCTAssertEqual(store.snapshot(for: target).likeCount, 1)
        XCTAssertTrue(repository.setLikedCalls.isEmpty)
    }

    func testEnsureLikedDoesNotUnlikeAndDedupes() async {
        let repository = InMemoryInteractionRepository()
        repository.likeDelayNanoseconds = 80_000_000
        let store = EngagementStore(repository: repository)
        let target = InteractionTarget.trade(TradeID("live-trade-ensure"))
        store.seed(
            EngagementSnapshot(likeCount: 4, commentCount: 1, viewerHasLiked: false),
            for: target
        )

        let first = Task { await store.ensureLiked(on: target) }
        try? await Task.sleep(nanoseconds: 15_000_000)
        let second = Task { await store.ensureLiked(on: target) }
        await first.value
        await second.value

        XCTAssertTrue(store.snapshot(for: target).viewerHasLiked)
        XCTAssertEqual(store.snapshot(for: target).likeCount, 5)
        XCTAssertEqual(repository.setLikedCalls.count, 1)
        XCTAssertEqual(repository.setLikedCalls.first?.0, true)

        await store.ensureLiked(on: target)
        XCTAssertEqual(store.snapshot(for: target).likeCount, 5)
        XCTAssertEqual(repository.setLikedCalls.count, 1)
        XCTAssertTrue(store.snapshot(for: target).viewerHasLiked)
    }

    func testEnsureLikedNoopsWhenAlreadyLiked() async {
        let repository = InMemoryInteractionRepository()
        let store = EngagementStore(repository: repository)
        let target = InteractionTarget.profilePost(PostID("live-post-liked"))
        store.seed(
            EngagementSnapshot(likeCount: 9, commentCount: 0, viewerHasLiked: true),
            for: target
        )

        await store.ensureLiked(on: target)

        XCTAssertTrue(store.snapshot(for: target).viewerHasLiked)
        XCTAssertEqual(store.snapshot(for: target).likeCount, 9)
        XCTAssertTrue(repository.setLikedCalls.isEmpty)
    }

    func testCommentsLoadPostDeleteAndSort() async {
        let repository = InMemoryInteractionRepository()
        let session = InteractionStubSession(userID: UserID("user-1"))
        let store = EngagementStore(repository: repository)
        let target = InteractionTarget.trade(TradeID("live-trade-comments"))
        let older = InteractionComment(
            id: CommentID("c1"),
            target: target,
            authorProfileID: ProfileID("user-2"),
            authorUsername: "peer",
            body: "Older",
            parentCommentID: nil,
            createdAt: Date(timeIntervalSince1970: 100),
            isPinned: false
        )
        let newer = InteractionComment(
            id: CommentID("c2"),
            target: target,
            authorProfileID: ProfileID("user-1"),
            authorUsername: "me",
            body: "Newer",
            parentCommentID: nil,
            createdAt: Date(timeIntervalSince1970: 200),
            isPinned: false
        )
        repository.commentsByTarget[target] = [older, newer]

        let viewModel = CommentsViewModel(
            target: target,
            repository: repository,
            engagementStore: store,
            session: session
        )
        await viewModel.refresh()
        XCTAssertEqual(viewModel.comments.map(\.id), [older.id, newer.id])

        viewModel.setSort(.newest)
        for _ in 0..<20 {
            if viewModel.comments.first?.id == newer.id { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(viewModel.comments.first?.id, newer.id)

        viewModel.draft = "Hello"
        await viewModel.submit()
        XCTAssertEqual(viewModel.comments.count, 3)
        XCTAssertEqual(store.snapshot(for: target).commentCount, 3)
        XCTAssertTrue(viewModel.draft.isEmpty)

        let own = viewModel.comments.first { $0.body == "Hello" }
        XCTAssertNotNil(own)
        await viewModel.delete(own!)
        XCTAssertEqual(viewModel.comments.count, 2)
        XCTAssertEqual(store.snapshot(for: target).commentCount, 2)
    }

    func testCommentOptimisticRollback() async {
        let repository = InMemoryInteractionRepository()
        repository.shouldFailAddComment = true
        let session = InteractionStubSession(userID: UserID("user-1"))
        let store = EngagementStore(repository: repository)
        let target = InteractionTarget.feedPost(PostID("live-feed-1"))
        repository.commentsByTarget[target] = []

        let viewModel = CommentsViewModel(
            target: target,
            repository: repository,
            engagementStore: store,
            session: session
        )
        await viewModel.refresh()
        viewModel.draft = "Will fail"
        await viewModel.submit()

        XCTAssertTrue(viewModel.comments.isEmpty)
        XCTAssertEqual(viewModel.draft, "Will fail")
        XCTAssertEqual(store.snapshot(for: target).commentCount, 0)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testNestedReplyArchitecture() async {
        let repository = InMemoryInteractionRepository()
        let session = InteractionStubSession(userID: UserID("user-1"))
        let store = EngagementStore(repository: repository)
        let target = InteractionTarget.trade(TradeID("live-nested"))
        let parent = InteractionComment(
            id: CommentID("parent"),
            target: target,
            authorProfileID: ProfileID("user-2"),
            authorUsername: "peer",
            body: "Parent",
            parentCommentID: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            isPinned: false
        )
        let reply = InteractionComment(
            id: CommentID("reply"),
            target: target,
            authorProfileID: ProfileID("user-1"),
            authorUsername: "me",
            body: "Reply",
            parentCommentID: parent.id,
            createdAt: Date(timeIntervalSince1970: 2),
            isPinned: false
        )
        repository.commentsByTarget[target] = [parent, reply]

        let viewModel = CommentsViewModel(
            target: target,
            repository: repository,
            engagementStore: store,
            session: session
        )
        await viewModel.refresh()
        XCTAssertEqual(viewModel.topLevelComments.count, 1)
        XCTAssertEqual(viewModel.replies(to: parent.id).count, 1)
    }

    func testDataEnvironmentExposesSharedEngagementStore() {
        let environment = CompositionRoot.bootstrap()
        XCTAssertTrue(environment.data.engagementStore === environment.data.engagementStore)
        let trade = InteractionTarget.trade(TradeID("dev-trade-1"))
        XCTAssertEqual(environment.data.engagementStore.snapshot(for: trade), .empty)
    }

    func testPrefetchCoalescesDuplicateTargetsIntoOneRepositoryCall() async {
        let repository = CountingInteractionRepository()
        repository.delayNanoseconds = 80_000_000
        let store = EngagementStore(repository: repository)

        let targets = (0..<8).map { InteractionTarget.trade(TradeID("live-trade-\($0)")) }
        // Simulate list batch + per-card / onAppear storms without cancelling work.
        store.prefetch(targets)
        store.prefetch(Array(targets.prefix(3)))
        for target in targets {
            store.prefetch([target])
        }

        let deadline = Date().addingTimeInterval(2)
        while store.snapshot(for: targets[0]).likeCount == 0, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(repository.engagementCallCount, 1)
        XCTAssertEqual(repository.lastEngagementBatchSize, 8)
        XCTAssertEqual(store.snapshot(for: targets[7]).likeCount, 1)
    }
}

// MARK: - Test doubles

private final class CountingInteractionRepository: InteractionRepository, @unchecked Sendable {
    var engagementCallCount = 0
    var lastEngagementBatchSize = 0
    var delayNanoseconds: UInt64 = 0
    private let lock = NSLock()

    func engagement(
        for targets: [InteractionTarget]
    ) async throws -> [InteractionTarget: EngagementSnapshot] {
        lock.lock()
        engagementCallCount += 1
        lastEngagementBatchSize = targets.count
        lock.unlock()
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        var result: [InteractionTarget: EngagementSnapshot] = [:]
        for target in targets {
            result[target] = EngagementSnapshot(likeCount: 1, commentCount: 0, viewerHasLiked: false)
        }
        return result
    }

    func setLiked(_ liked: Bool, on target: InteractionTarget) async throws {}

    func comments(
        for target: InteractionTarget,
        order: CommentSortOrder
    ) async throws -> [InteractionComment] {
        []
    }

    func addComment(
        body: String,
        parentID: CommentID?,
        on target: InteractionTarget
    ) async throws -> InteractionComment {
        InteractionComment(
            id: CommentID(UUID().uuidString),
            target: target,
            authorProfileID: ProfileID("user-1"),
            authorUsername: "me",
            body: body,
            parentCommentID: parentID,
            createdAt: Date(),
            isPinned: false
        )
    }

    func deleteComment(id: CommentID, on target: InteractionTarget) async throws {}
}

private final class InMemoryInteractionRepository: InteractionRepository, @unchecked Sendable {
    var engagementMap: [InteractionTarget: EngagementSnapshot] = [:]
    var commentsByTarget: [InteractionTarget: [InteractionComment]] = [:]
    var setLikedCalls: [(Bool, InteractionTarget)] = []
    var shouldFailLike = false
    var shouldFailAddComment = false
    var likeDelayNanoseconds: UInt64 = 0
    private let lock = NSLock()

    func engagement(
        for targets: [InteractionTarget]
    ) async throws -> [InteractionTarget: EngagementSnapshot] {
        var result: [InteractionTarget: EngagementSnapshot] = [:]
        for target in targets {
            result[target] = engagementMap[target] ?? .empty
        }
        return result
    }

    func setLiked(_ liked: Bool, on target: InteractionTarget) async throws {
        lock.lock()
        setLikedCalls.append((liked, target))
        lock.unlock()
        if likeDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: likeDelayNanoseconds)
        }
        if shouldFailLike {
            throw AppError.unknown(message: "like failed")
        }
        var snap = engagementMap[target] ?? .empty
        snap.viewerHasLiked = liked
        snap.likeCount = max(0, snap.likeCount + (liked ? 1 : -1))
        engagementMap[target] = snap
    }

    func comments(
        for target: InteractionTarget,
        order: CommentSortOrder
    ) async throws -> [InteractionComment] {
        let items = commentsByTarget[target] ?? []
        switch order {
        case .oldest: return items.sorted { $0.createdAt < $1.createdAt }
        case .newest: return items.sorted { $0.createdAt > $1.createdAt }
        }
    }

    func addComment(
        body: String,
        parentID: CommentID?,
        on target: InteractionTarget
    ) async throws -> InteractionComment {
        if shouldFailAddComment {
            throw AppError.unknown(message: "comment failed")
        }
        let comment = InteractionComment(
            id: CommentID(UUID().uuidString),
            target: target,
            authorProfileID: ProfileID("user-1"),
            authorUsername: "me",
            body: body,
            parentCommentID: parentID,
            createdAt: Date(),
            isPinned: false
        )
        commentsByTarget[target, default: []].append(comment)
        return comment
    }

    func deleteComment(id: CommentID, on target: InteractionTarget) async throws {
        commentsByTarget[target]?.removeAll { $0.id == id || $0.parentCommentID == id }
    }
}

private struct InteractionStubSession: SessionProviding {
    let userID: UserID?

    var currentUserID: UserID? {
        get async { userID }
    }

    var accessToken: String? {
        get async { userID == nil ? nil : "test-token" }
    }
}
