import XCTest
@testable import TradeTraxs

@MainActor
final class ProfileBootstrapV2Tests: XCTestCase {
    func testDevelopmentBootstrapFillsAllSectionsOnce() async {
        let environment = CompositionRoot.bootstrap()
        let state = await ProfileBootstrap.load(
            .init(
                target: .profile(ProfileID("dev.bootstrap-v2")),
                profiles: environment.data.profiles,
                trades: environment.data.trades,
                achievements: environment.data.achievements,
                feed: environment.data.feed,
                rooms: environment.data.rooms,
                session: environment.data.session,
                detailCache: environment.data.detailCache,
                rpc: nil,
                force: false
            )
        )

        XCTAssertTrue(state.didBootstrap)
        XCTAssertEqual(state.phase, .loaded)
        XCTAssertNotNil(state.profile)
        XCTAssertNotNil(state.stats)
        XCTAssertTrue(state.didLoadTrades)
        XCTAssertFalse(state.trades.isEmpty)
        XCTAssertFalse(state.posts.isEmpty)
        XCTAssertFalse(state.achievements.isEmpty)
        XCTAssertNotNil(state.stats?.profitFactor)
    }

    func testScreenViewModelBootstrapAppliesToSectionViewModelsWithoutAutonomousLoad() async {
        let environment = CompositionRoot.bootstrap()
        let screen = ProfileScreenViewModel(
            target: .profile(ProfileID("dev.bootstrap-screen")),
            currentUserProfile: environment.currentUserProfile,
            navigationCoordinator: environment.navigation.coordinator,
            authenticationCoordinator: nil,
            data: environment.data,
            showsOwnerChrome: false
        )

        screen.onAppear(currentUserProfile: environment.currentUserProfile)

        let deadline = Date().addingTimeInterval(3)
        while !screen.state.didBootstrap, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertTrue(screen.state.didBootstrap)
        XCTAssertEqual(screen.contentStore.phase, .loaded)
        XCTAssertTrue(screen.contentStore.isScreenOwned)

        // Follow must be usable after Stage 1 — viewerID resolved for toggle.
        await screen.contentStore.toggleFollow()

        screen.syncShellIfNeeded()
        screen.activateShellForLaunch()

        guard let trades = screen.shellViewModel?.trades else {
            return XCTFail("Expected trades section after bootstrap")
        }
        // Dev fixtures fill Stage 2 in bootstrap — section should apply without extra wait.
        let tradesDeadline = Date().addingTimeInterval(2)
        while trades.items.isEmpty, Date() < tradesDeadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(trades.items.count, screen.state.trades.count)
        XCTAssertNotEqual(trades.state, .idle)

        screen.shellViewModel?.select(.stats)
        guard let stats = screen.shellViewModel?.stats else {
            return XCTFail("Expected stats section")
        }
        XCTAssertNotNil(stats.metrics)
        XCTAssertNotNil(screen.state.stats?.profitFactor)

        screen.shellViewModel?.select(.achievements)
        XCTAssertEqual(
            screen.shellViewModel?.achievements?.items.count,
            screen.state.achievements.count
        )

        screen.shellViewModel?.select(.posts)
        XCTAssertEqual(screen.shellViewModel?.posts?.items.count, screen.state.posts.count)
    }

    func testSectionLoadIfNeededIsNoOpAfterBootstrapApply() async {
        let environment = CompositionRoot.bootstrap()
        let profileID = ProfileID("dev.bootstrap-noop")
        let snapshot = await ProfileBootstrap.load(
            .init(
                target: .profile(profileID),
                profiles: environment.data.profiles,
                trades: environment.data.trades,
                achievements: environment.data.achievements,
                feed: environment.data.feed,
                rooms: environment.data.rooms,
                session: environment.data.session,
                detailCache: environment.data.detailCache,
                rpc: nil,
                force: false
            )
        )

        let trades = TradesContainerViewModel(
            profileID: profileID,
            trades: environment.data.trades,
            navigationCoordinator: environment.navigation.coordinator,
            detailCache: environment.data.detailCache
        )
        trades.applyBootstrap(snapshot)
        let count = trades.items.count
        trades.loadIfNeeded()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(trades.items.count, count)
    }

    func testFollowEdgeCacheDoesNotPoisonIncompleteFollowingSet() {
        let cache = DetailPresentationCache()
        let a = ProfileID("user-a")
        let b = ProfileID("user-b")
        cache.setViewerFollows(a, isFollowing: true)
        XCTAssertEqual(cache.viewerFollowEdge(for: a), true)
        XCTAssertNil(cache.viewerFollowingIDs(), "Pairwise follow must not invent a complete following set")
        XCTAssertNil(cache.viewerFollowEdge(for: b))
        cache.seedViewerFollowingIDs([a, b])
        XCTAssertEqual(cache.viewerFollowingIDs()?.count, 2)
        cache.setViewerFollows(b, isFollowing: false)
        XCTAssertEqual(cache.viewerFollowEdge(for: b), false)
        XCTAssertFalse(cache.viewerFollowingIDs()?.contains(b) ?? true)
    }

    func testOptimisticMergePrefersOverlayAndDedupesByID() {
        let owner = ProfileID("dev.optimistic")
        var older = CreateReelFixtures.sampleReel(author: owner, tradeID: nil)
        older.id = ReelID("reel-a")
        var newer = older
        newer.caption = "fresh"
        var other = CreateReelFixtures.sampleReel(author: owner, tradeID: nil)
        other.id = ReelID("reel-b")
        let merged = OwnerProfileOptimisticStore.merging(overlay: [newer], into: [older, other])
        XCTAssertEqual(merged.first?.id, newer.id)
        XCTAssertEqual(merged.first?.caption, "fresh")
        XCTAssertEqual(merged.filter { $0.id == newer.id }.count, 1)
        XCTAssertEqual(merged.count, 2)
    }

    func testPrivateTradeLinkedReelIsNotListedOnOwnerProfile() {
        let owner = ProfileID("dev.optimistic")
        var reel = CreateReelFixtures.sampleReel(author: owner, tradeID: TradeID("t1"))
        reel.visibility = .private
        XCTAssertFalse(OwnerProfileOptimisticStore.isListedOnOwnerProfile(reel))
        reel.visibility = .public
        XCTAssertTrue(OwnerProfileOptimisticStore.isListedOnOwnerProfile(reel))
    }

    func testOwnerOptimisticReelLandsInScreenStateWithoutNetworkRefresh() {
        OwnerProfileOptimisticStore.shared.invalidate()
        let environment = CompositionRoot.bootstrap()
        let screen = ProfileScreenViewModel(
            target: .currentUser,
            currentUserProfile: environment.currentUserProfile,
            navigationCoordinator: environment.navigation.coordinator,
            authenticationCoordinator: nil,
            data: environment.data,
            showsOwnerChrome: true
        )
        OwnerProfileOptimisticStore.shared.registerOwnerScreen(screen)

        let reel = CreateReelFixtures.sampleReel(author: ProfileID("dev.viewer"), tradeID: nil)
        OwnerProfileOptimisticStore.shared.noteReelCreated(reel)

        XCTAssertEqual(screen.state.clips.filter { $0.id == reel.id }.count, 1)
        OwnerProfileOptimisticStore.shared.noteReelCreated(reel)
        XCTAssertEqual(screen.state.clips.filter { $0.id == reel.id }.count, 1)

        // Bootstrap merge must keep the optimistic clip (deduped).
        var snapshot = ProfileState()
        snapshot.phase = .loaded
        snapshot.didBootstrap = true
        snapshot.isOwner = true
        snapshot.profileID = ProfileID("dev.viewer")
        snapshot.clips = [CreateReelFixtures.sampleReel(author: ProfileID("dev.viewer"), tradeID: nil)]
        let merged = OwnerProfileOptimisticStore.shared.merging(into: snapshot)
        XCTAssertTrue(merged.clips.contains(where: { $0.id == reel.id }))
        XCTAssertEqual(merged.clips.filter { $0.id == reel.id }.count, 1)

        OwnerProfileOptimisticStore.shared.invalidate()
    }

    func testClipsSectionReconcilePreservesLoadedItemsOnOptimisticSnapshot() {
        let owner = ProfileID("dev.optimistic-clips")
        let environment = CompositionRoot.bootstrap()
        var existing = CreateReelFixtures.sampleReel(author: owner, tradeID: nil)
        existing.id = ReelID("reel-existing")
        let clipsVM = ClipsContainerViewModel(
            profileID: owner,
            feed: environment.data.feed,
            navigationCoordinator: environment.navigation.coordinator,
            detailCache: DetailPresentationCache(),
            isOwner: true
        )
        var loadedSnapshot = ProfileState()
        loadedSnapshot.profileID = owner
        loadedSnapshot.clips = [existing]
        loadedSnapshot.didLoadClips = true
        loadedSnapshot.didBootstrap = true
        loadedSnapshot.phase = .loaded
        clipsVM.applyBootstrap(loadedSnapshot)
        XCTAssertEqual(clipsVM.items.count, 1)

        let created = CreateReelFixtures.sampleReel(author: owner, tradeID: nil)
        clipsVM.notePublishSucceeded(created, preservingExisting: [existing])
        XCTAssertEqual(clipsVM.items.count, 2)
        XCTAssertEqual(clipsVM.items.first?.id, created.id)
        XCTAssertTrue(clipsVM.items.contains { $0.id == existing.id })
    }

    func testOwnerOptimisticPostAndAchievementLandWithoutNetworkRefresh() {
        OwnerProfileOptimisticStore.shared.invalidate()
        let environment = CompositionRoot.bootstrap()
        let screen = ProfileScreenViewModel(
            target: .currentUser,
            currentUserProfile: environment.currentUserProfile,
            navigationCoordinator: environment.navigation.coordinator,
            authenticationCoordinator: nil,
            data: environment.data,
            showsOwnerChrome: true
        )
        OwnerProfileOptimisticStore.shared.registerOwnerScreen(screen)

        let post = CreatePostFixtures.samplePost(author: ProfileID("dev.viewer"), body: "hello")
        OwnerProfileOptimisticStore.shared.notePostCreated(post)
        XCTAssertEqual(screen.state.posts.filter { $0.id == post.id }.count, 1)
        OwnerProfileOptimisticStore.shared.notePostCreated(post)
        XCTAssertEqual(screen.state.posts.filter { $0.id == post.id }.count, 1)

        let achievement = CreateAchievementFixtures.sampleAchievement(
            owner: ProfileID("dev.viewer"),
            kind: .milestone,
            title: "Funded"
        )
        OwnerProfileOptimisticStore.shared.noteAchievementCreated(achievement)
        XCTAssertEqual(screen.state.achievements.filter { $0.id == achievement.id }.count, 1)
        OwnerProfileOptimisticStore.shared.noteAchievementCreated(achievement)
        XCTAssertEqual(screen.state.achievements.filter { $0.id == achievement.id }.count, 1)

        OwnerProfileOptimisticStore.shared.invalidate()
    }

    func testPostsSectionReconcilePreservesLoadedItemsOnOptimisticSnapshot() {
        let owner = ProfileID("dev.optimistic-posts")
        let environment = CompositionRoot.bootstrap()
        var existing = CreatePostFixtures.samplePost(author: owner, body: "older")
        existing.id = PostID("post-existing")
        let postsVM = PostsContainerViewModel(
            profileID: owner,
            profiles: environment.data.profiles,
            navigationCoordinator: environment.navigation.coordinator,
            detailCache: DetailPresentationCache()
        )
        var loadedSnapshot = ProfileState()
        loadedSnapshot.profileID = owner
        loadedSnapshot.posts = [existing]
        loadedSnapshot.didLoadPosts = true
        loadedSnapshot.didBootstrap = true
        loadedSnapshot.phase = .loaded
        postsVM.applyBootstrap(loadedSnapshot)
        XCTAssertEqual(postsVM.items.count, 1)

        let created = CreatePostFixtures.samplePost(author: owner, body: "new")
        var optimisticSnapshot = ProfileState()
        optimisticSnapshot.profileID = owner
        optimisticSnapshot.posts = [created]
        optimisticSnapshot.didLoadPosts = false
        optimisticSnapshot.didBootstrap = true
        optimisticSnapshot.phase = .loaded
        postsVM.applyBootstrap(optimisticSnapshot)
        XCTAssertEqual(postsVM.items.count, 2)
        XCTAssertEqual(postsVM.items.first?.id, created.id)
        XCTAssertTrue(postsVM.items.contains { $0.id == existing.id })
    }

    func testPostsSectionNeverShrinksWhenAuthoritativeSnapshotIsPartial() {
        let owner = ProfileID("dev.partial-authoritative-posts")
        let environment = CompositionRoot.bootstrap()
        var existingPosts: [Post] = (0..<8).map { index in
            var post = CreatePostFixtures.samplePost(author: owner, body: "post-\(index)")
            post.id = PostID("post-\(index)")
            return post
        }
        let postsVM = PostsContainerViewModel(
            profileID: owner,
            profiles: environment.data.profiles,
            navigationCoordinator: environment.navigation.coordinator,
            detailCache: DetailPresentationCache()
        )
        var loadedSnapshot = ProfileState()
        loadedSnapshot.profileID = owner
        loadedSnapshot.posts = existingPosts
        loadedSnapshot.didLoadPosts = true
        loadedSnapshot.didBootstrap = true
        loadedSnapshot.phase = .loaded
        postsVM.applyBootstrap(loadedSnapshot)
        XCTAssertEqual(postsVM.items.count, 8)

        let created = CreatePostFixtures.samplePost(author: owner, body: "new")
        postsVM.notePublishSucceeded(created, preservingExisting: existingPosts)
        XCTAssertEqual(postsVM.items.count, 9)
        XCTAssertEqual(postsVM.items.first?.id, created.id)

        var partialAuthoritative = ProfileState()
        partialAuthoritative.profileID = owner
        partialAuthoritative.posts = [created]
        partialAuthoritative.didLoadPosts = true
        partialAuthoritative.didBootstrap = true
        partialAuthoritative.phase = .loaded
        postsVM.applyBootstrap(partialAuthoritative)
        XCTAssertEqual(postsVM.items.count, 9)
        XCTAssertTrue(postsVM.items.contains { $0.id == existingPosts[0].id })
    }

    func testAuthoritativeRefreshNeverShrinksVisiblePosts() async {
        let owner = ProfileID("dev.shrink-guard")
        let environment = CompositionRoot.bootstrap()
        var existingPosts: [Post] = (0..<8).map { index in
            var post = CreatePostFixtures.samplePost(author: owner, body: "post-\(index)")
            post.id = PostID("visible-\(index)")
            return post
        }
        let postsVM = PostsContainerViewModel(
            profileID: owner,
            profiles: environment.data.profiles,
            navigationCoordinator: environment.navigation.coordinator,
            detailCache: DetailPresentationCache()
        )
        postsVM.notePublishSucceeded(
            CreatePostFixtures.samplePost(author: owner, body: "new"),
            preservingExisting: existingPosts
        )
        XCTAssertEqual(postsVM.items.count, 9)

        var stalePage = ProfileState()
        stalePage.profileID = owner
        stalePage.posts = [CreatePostFixtures.samplePost(author: owner, body: "new")]
        stalePage.didLoadPosts = true
        stalePage.didBootstrap = true
        stalePage.phase = .loaded
        postsVM.applyBootstrap(stalePage)
        XCTAssertEqual(postsVM.items.count, 9)
    }
}
