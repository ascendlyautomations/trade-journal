import XCTest
@testable import TradeTraxs

@MainActor
final class ExploreExperienceTests: XCTestCase {
    override func tearDown() {
        ExploreSessionStore.shared.invalidate()
        super.tearDown()
    }

    func testTraderRankingScoresCompletenessAndActivity() {
        let rich = ExploreFixtures.traders()[0].profile
        let bare = Profile(
            id: ProfileID("bare"),
            userID: UserID("bare"),
            username: "bare",
            displayName: "Bare",
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
        let richScore = ExploreTraderRanking.score(
            profile: rich,
            trades: .init(tradeCount: 12, lastTradeAt: .now)
        )
        let bareScore = ExploreTraderRanking.score(profile: bare)
        XCTAssertGreaterThan(richScore, bareScore)
    }

    func testRankingExcludesPrivateSelfAndLowScore() {
        let viewer = ExploreFixtures.viewerID
        let privateProfile = Profile(
            id: ProfileID("private"),
            userID: UserID("private"),
            username: "secret",
            displayName: "Secret",
            bio: "Hidden",
            avatar: MediaReference(id: "a", kind: .image, altText: nil),
            traderType: .futures,
            tradingStyle: "Scalper",
            primaryMarket: "ES",
            startedTradingAt: .now,
            isPrivate: true,
            isCreator: false,
            createdAt: .now
        )
        let ranked = ExploreTraderRanking.rank(
            profiles: ExploreFixtures.traders().map(\.profile) + [privateProfile],
            excluding: [viewer],
            limit: 10,
            minScore: 3
        )
        XCTAssertFalse(ranked.contains { $0.id == viewer })
        XCTAssertFalse(ranked.contains { $0.id == privateProfile.id })
        XCTAssertFalse(ranked.isEmpty)
    }

    func testFeedExploreNavigationPushesAndPops() async {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: store)
        coordinator.open(.feed(.explore))
        XCTAssertEqual(store.paths.feed.last, .explore)
        coordinator.pop()
        XCTAssertTrue(store.paths.feed.isEmpty)
    }

    func testViewModelBootstrapsFixturesAndCachesState() async {
        let sessionStore = ExploreSessionStore.shared
        sessionStore.invalidate()
        let cache = DetailPresentationCache()
        let navigationStore = NavigationStore()
        navigationStore.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: navigationStore)
        let viewModel = ExploreViewModel(
            explore: ExploreStubRepository(),
            search: ExploreStubSearchRepository(),
            profiles: ExploreStubProfileRepository(),
            session: ExploreStubSession(userID: ExploreFixtures.viewerID.rawValue),
            detailCache: cache,
            navigationCoordinator: coordinator,
            store: sessionStore
        )

        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }

        XCTAssertFalse(viewModel.suggestedTraders.isEmpty)
        XCTAssertFalse(viewModel.popularRooms.isEmpty)
        XCTAssertTrue(sessionStore.hasBootstrapped)

        // Second load should reuse session store — no blank flash / no re-bootstrap.
        let counting = ExploreCountingRepository()
        let again = ExploreViewModel(
            explore: counting,
            search: ExploreStubSearchRepository(),
            profiles: ExploreStubProfileRepository(),
            session: ExploreStubSession(userID: ExploreFixtures.viewerID.rawValue),
            detailCache: cache,
            navigationCoordinator: coordinator,
            store: sessionStore
        )
        again.loadIfNeeded()
        XCTAssertEqual(again.phase, .loaded)
        XCTAssertFalse(again.suggestedTraders.isEmpty)
        XCTAssertEqual(counting.discoverCalls, 0)
    }

    func testSearchDebounceCancellationAndGrouping() async {
        let sessionStore = ExploreSessionStore.shared
        sessionStore.invalidate()
        let search = ExploreStubSearchRepository()
        let explore = ExploreStubRepository()
        let cache = DetailPresentationCache()
        let navigationStore = NavigationStore()
        navigationStore.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: navigationStore)
        let viewModel = ExploreViewModel(
            explore: explore,
            search: search,
            profiles: ExploreStubProfileRepository(),
            session: ExploreStubSession(userID: "user.real"),
            detailCache: cache,
            navigationCoordinator: coordinator,
            store: sessionStore
        )

        viewModel.searchText = "n"
        viewModel.searchChanged()
        XCTAssertTrue(viewModel.searchPeople.isEmpty)

        viewModel.searchText = "ni"
        viewModel.searchChanged()
        viewModel.searchText = "nick"
        viewModel.searchChanged()
        await waitFor { viewModel.searchPhase == .idle && !viewModel.searchPeople.isEmpty }

        XCTAssertEqual(search.calls, 1, "Stale searches should cancel; only final query runs")
        XCTAssertFalse(viewModel.searchPeople.isEmpty)
        XCTAssertFalse(viewModel.searchRooms.isEmpty)
    }

    func testOpenTraderAndRoomUseFeedRoutes() async {
        let sessionStore = ExploreSessionStore.shared
        sessionStore.invalidate()
        let cache = DetailPresentationCache()
        let navigationStore = NavigationStore()
        navigationStore.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: navigationStore)
        let viewModel = ExploreViewModel(
            explore: ExploreStubRepository(),
            search: ExploreStubSearchRepository(),
            profiles: ExploreStubProfileRepository(),
            session: ExploreStubSession(userID: ExploreFixtures.viewerID.rawValue),
            detailCache: cache,
            navigationCoordinator: coordinator,
            store: sessionStore
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }

        let trader = viewModel.suggestedTraders[0]
        viewModel.openTrader(trader)
        XCTAssertEqual(navigationStore.paths.feed.last, .profile(trader.id))

        navigationStore.paths.feed = [.explore]
        let room = viewModel.popularRooms[0]
        viewModel.openRoom(room)
        XCTAssertEqual(navigationStore.paths.feed.last, .room(room.id))
    }

    func testFollowToggleUsesProfileRepository() async throws {
        let sessionStore = ExploreSessionStore.shared
        sessionStore.invalidate()
        let profiles = ExploreStubProfileRepository()
        let cache = DetailPresentationCache()
        let navigationStore = NavigationStore()
        navigationStore.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: navigationStore)
        let viewModel = ExploreViewModel(
            explore: ExploreStubRepository(),
            search: ExploreStubSearchRepository(),
            profiles: profiles,
            session: ExploreStubSession(userID: ExploreFixtures.viewerID.rawValue),
            detailCache: cache,
            navigationCoordinator: coordinator,
            store: sessionStore
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }

        let trader = try XCTUnwrap(viewModel.suggestedTraders.first)
        XCTAssertFalse(viewModel.isFollowing(trader))
        viewModel.toggleFollow(trader)
        XCTAssertTrue(viewModel.isFollowing(trader), "Optimistic follow should update immediately")
        await waitFor { profiles.followCalls == 1 }
        viewModel.toggleFollow(trader)
        XCTAssertNotNil(viewModel.pendingUnfollow, "Unfollow should ask for confirmation")
        viewModel.confirmUnfollow()
        XCTAssertFalse(viewModel.isFollowing(trader), "Confirmed unfollow should update immediately")
        await waitFor { profiles.unfollowCalls == 1 }
    }

    func testPartialSectionFailureStillRendersRooms() async {
        let sessionStore = ExploreSessionStore.shared
        sessionStore.invalidate()
        let cache = DetailPresentationCache()
        let navigationStore = NavigationStore()
        navigationStore.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: navigationStore)
        let viewModel = ExploreViewModel(
            explore: ExplorePartialFailRepository(),
            search: ExploreStubSearchRepository(),
            profiles: ExploreStubProfileRepository(),
            session: ExploreStubSession(userID: "user.real"),
            detailCache: cache,
            navigationCoordinator: coordinator,
            store: sessionStore
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }
        XCTAssertTrue(viewModel.suggestedTraders.isEmpty)
        XCTAssertNotNil(viewModel.tradersFailedMessage)
        XCTAssertFalse(viewModel.popularRooms.isEmpty)
    }

    private func waitFor(
        timeout: TimeInterval = 2,
        _ condition: @escaping () -> Bool
    ) async {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Condition timed out")
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

// MARK: - Stubs

private struct ExploreStubSession: SessionProviding {
    let userID: String?
    var currentUserID: UserID? {
        get async { userID.map { UserID($0) } }
    }

    var accessToken: String? {
        get async { userID == nil ? nil : "test-token" }
    }
}

private struct ExploreStubRepository: ExploreRepository {
    func discoverableProfiles(page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: ExploreFixtures.traders().map(\.profile), nextCursor: nil)
    }

    func socialCounts(for profileIDs: [ProfileID]) async throws -> ExploreSocialCounts {
        .empty
    }

    func tradeActivitySummaries(limit: Int) async throws -> [ProfileID: ExploreTraderRanking.TradeSummary] {
        [:]
    }

    func popularRooms(limit: Int) async throws -> [ExploreRoomSuggestion] {
        ExploreFixtures.rooms()
    }

    func searchRooms(query: String, limit: Int) async throws -> [ExploreRoomSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return Array(ExploreFixtures.rooms().prefix(limit))
    }
}

private final class ExploreCountingRepository: ExploreRepository, @unchecked Sendable {
    private(set) var discoverCalls = 0

    func discoverableProfiles(page: PageRequest) async throws -> CursorPage<Profile> {
        discoverCalls += 1
        return CursorPage(items: [], nextCursor: nil)
    }

    func socialCounts(for profileIDs: [ProfileID]) async throws -> ExploreSocialCounts { .empty }
    func tradeActivitySummaries(limit: Int) async throws -> [ProfileID: ExploreTraderRanking.TradeSummary] { [:] }
    func popularRooms(limit: Int) async throws -> [ExploreRoomSuggestion] { [] }
    func searchRooms(query: String, limit: Int) async throws -> [ExploreRoomSuggestion] { [] }
}

private struct ExplorePartialFailRepository: ExploreRepository {
    func discoverableProfiles(page: PageRequest) async throws -> CursorPage<Profile> {
        throw AppError.unknown(message: "profiles unavailable")
    }

    func socialCounts(for profileIDs: [ProfileID]) async throws -> ExploreSocialCounts { .empty }
    func tradeActivitySummaries(limit: Int) async throws -> [ProfileID: ExploreTraderRanking.TradeSummary] { [:] }
    func popularRooms(limit: Int) async throws -> [ExploreRoomSuggestion] {
        ExploreFixtures.rooms()
    }

    func searchRooms(query: String, limit: Int) async throws -> [ExploreRoomSuggestion] { [] }
}

private final class ExploreStubSearchRepository: SearchRepository, @unchecked Sendable {
    private(set) var calls = 0
    private(set) var lastQuery: String?
    private(set) var lastExcluding: ProfileID?

    func search(
        query: String,
        kinds: Set<SearchResultKind>,
        page: PageRequest,
        excludingProfileID: ProfileID?
    ) async throws -> CursorPage<SearchResult> {
        try await Task.sleep(nanoseconds: 50_000_000)
        calls += 1
        lastQuery = query
        lastExcluding = excludingProfileID
        let trader = ExploreFixtures.traders()[0]
        return CursorPage(
            items: [
                SearchResult(
                    id: trader.id.rawValue,
                    kind: .profile,
                    title: trader.profile.username,
                    subtitle: trader.profile.displayName,
                    profileID: trader.id,
                    tradeID: nil,
                    roomID: nil,
                    postID: nil
                ),
            ],
            nextCursor: nil
        )
    }
}

private final class ExploreStubProfileRepository: ProfileRepository, @unchecked Sendable {
    private(set) var followCalls = 0
    private(set) var unfollowCalls = 0

    func currentUser() async throws -> User {
        User(id: UserID(ExploreFixtures.viewerID.rawValue), email: nil, createdAt: .now)
    }

    func profile(id: ProfileID) async throws -> Profile {
        ExploreFixtures.traders().first(where: { $0.id == id })?.profile
            ?? ExploreFixtures.traders()[0].profile
    }

    func profile(username: String) async throws -> Profile {
        try await profile(id: ProfileID(username))
    }

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

    func wallPost(id: PostID) async throws -> Post {
        throw AppError.unknown(message: "stub")
    }

    func followState(from viewer: ProfileID, to target: ProfileID) async throws -> FollowState { .none }
    func follow(from viewer: ProfileID, to target: ProfileID) async throws { followCalls += 1 }
    func unfollow(from viewer: ProfileID, to target: ProfileID) async throws { unfollowCalls += 1 }
    func followers(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }

    func following(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }

    func creator(for profileID: ProfileID) async throws -> Creator? { nil }
}
