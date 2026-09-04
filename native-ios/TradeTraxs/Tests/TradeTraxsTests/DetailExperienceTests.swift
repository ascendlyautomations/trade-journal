import XCTest
@testable import TradeTraxs

@MainActor
final class DetailExperienceTests: XCTestCase {
    func testDetailCacheSeedsAvoidRefetchPathForTrade() async {
        let environment = CompositionRoot.bootstrap()
        let cache = environment.data.detailCache
        let profileID = ProfileID("dev.detail-trade")
        let trade = ProfileTradeFixtures.samples(owner: profileID)[0]
        cache.seed(trade)
        cache.seed(accounts: PropFirmFixtures.accounts(owner: profileID), for: profileID)

        let viewModel = TradeDetailViewModel(
            tradeID: trade.id,
            trades: environment.data.trades,
            profiles: environment.data.profiles,
            session: environment.data.session,
            imagePipeline: environment.data.imagePipeline,
            cache: cache,
            navigationCoordinator: environment.navigation.coordinator,
            rpc: environment.data.rpc
        )
        viewModel.loadIfNeeded()
        for _ in 0..<20 {
            if viewModel.phase == .loaded { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertEqual(viewModel.trade?.id, trade.id)
        XCTAssertEqual(viewModel.trade?.symbol.ticker, "NQ")
        XCTAssertEqual(viewModel.accountName, "Alpha Futures")
        // Public audience when session user ≠ trade owner.
        XCTAssertEqual(viewModel.accountIdentityLine, "Alpha Futures")
        XCTAssertFalse(viewModel.notes.isEmpty)
    }

    func testOpenTradePushesProfileTradeRoute() {
        let environment = CompositionRoot.bootstrap()
        environment.navigation.coordinator.markAuthenticated()
        let profileID = ProfileID("dev.detail-nav")
        let viewModel = TradesContainerViewModel(
            profileID: profileID,
            trades: environment.data.trades,
            navigationCoordinator: environment.navigation.coordinator,
            detailCache: environment.data.detailCache,
            isOwner: true
        )
        viewModel.loadIfNeeded()
        let trade = ProfileTradeFixtures.samples(owner: profileID)[0]
        viewModel.openTrade(trade)

        XCTAssertEqual(environment.navigation.store.selectedTab, .profile)
        XCTAssertEqual(
            environment.navigation.store.paths.profile.last,
            .trade(trade.id)
        )
        XCTAssertEqual(environment.data.detailCache.trade(id: trade.id)?.id, trade.id)
    }

    func testOpenPostAndClipPushDetailRoutes() {
        let environment = CompositionRoot.bootstrap()
        environment.navigation.coordinator.markAuthenticated()
        let profileID = ProfileID("dev.detail-social")

        let posts = PostsContainerViewModel(
            profileID: profileID,
            profiles: environment.data.profiles,
            navigationCoordinator: environment.navigation.coordinator,
            detailCache: environment.data.detailCache
        )
        posts.loadIfNeeded()
        let post = ProfilePostFixtures.samples(owner: profileID)[0]
        posts.openPost(post)
        XCTAssertEqual(environment.navigation.store.paths.profile.last, .post(post.id))

        let clips = ClipsContainerViewModel(
            profileID: profileID,
            feed: environment.data.feed,
            navigationCoordinator: environment.navigation.coordinator,
            detailCache: environment.data.detailCache
        )
        clips.loadIfNeeded()
        let reel = ProfileClipFixtures.samples(owner: profileID)[0]
        clips.openClip(reel)
        XCTAssertEqual(environment.navigation.store.paths.profile.last, .reel(reel.id))
        XCTAssertEqual(environment.data.detailCache.reel(id: reel.id)?.id, reel.id)
    }

    func testPostDetailLoadsFromCache() async {
        let environment = CompositionRoot.bootstrap()
        let profileID = ProfileID("dev.detail-post")
        let post = ProfilePostFixtures.samples(owner: profileID)[0]
        environment.data.detailCache.seed(post)

        let viewModel = PostDetailViewModel(
            postID: post.id,
            profiles: environment.data.profiles,
            session: environment.data.session,
            imagePipeline: environment.data.imagePipeline,
            cache: environment.data.detailCache,
            navigationCoordinator: environment.navigation.coordinator
        )
        viewModel.loadIfNeeded()
        for _ in 0..<20 {
            if viewModel.phase == .loaded { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertEqual(viewModel.post?.body, post.body)
    }

    func testAchievementDetailLoadsFromCacheAndOpensRoute() async {
        let environment = CompositionRoot.bootstrap()
        environment.navigation.coordinator.markAuthenticated()
        let profileID = ProfileID("dev.detail-achievement")
        let achievement = ProfileAchievementFixtures.samples(owner: profileID)[0]
        environment.data.detailCache.seed(achievement)

        let list = AchievementsContainerViewModel(
            profileID: profileID,
            achievements: environment.data.achievements,
            navigationCoordinator: environment.navigation.coordinator,
            detailCache: environment.data.detailCache
        )
        list.loadIfNeeded()
        for _ in 0..<20 {
            if case .loaded = list.state { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        list.openAchievement(achievement)
        XCTAssertEqual(
            environment.navigation.store.paths.profile.last,
            .achievement(achievement.id)
        )

        let viewModel = AchievementDetailViewModel(
            achievementID: achievement.id,
            achievements: environment.data.achievements,
            profiles: environment.data.profiles,
            session: environment.data.session,
            imagePipeline: environment.data.imagePipeline,
            cache: environment.data.detailCache
        )
        viewModel.loadIfNeeded()
        for _ in 0..<20 {
            if viewModel.phase == .loaded { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertEqual(viewModel.achievement?.title, achievement.title)
    }

    func testMediaURLResolverKeepsAbsoluteHTTPS() {
        let reference = MediaReference(
            id: "https://example.com/clip.mp4",
            kind: .video,
            altText: nil
        )
        let url = MediaURLResolver.url(
            for: reference,
            bucket: .reels,
            storage: StubObjectStorage()
        )
        XCTAssertEqual(url?.absoluteString, "https://example.com/clip.mp4")
    }
}

private struct StubObjectStorage: ObjectStorageProviding {
    func upload(bucket: String, path: String, data: Data, contentType: String) async throws -> String {
        path
    }

    func download(bucket: String, path: String) async throws -> Data { Data() }
    func delete(bucket: String, path: String) async throws {}
    func publicURL(bucket: String, path: String) -> URL? {
        URL(string: "https://storage.test/\(bucket)/\(path)")
    }
}
