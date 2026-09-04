import XCTest
@testable import TradeTraxs

@MainActor
final class ExploreProfileHydrationTests: XCTestCase {
    func testMergingCachedPresentationPreservesExistingAvatar() {
        let rich = makeProfile(id: "user-rich", avatarURL: "https://cdn.example/avatar.jpg")
        let partial = makeProfile(id: "user-rich", avatarURL: nil)

        let merged = rich.mergingCachedPresentation(with: partial)
        XCTAssertEqual(merged.avatar?.id, "https://cdn.example/avatar.jpg")
    }

    func testMergingCachedPresentationUpgradesMissingAvatar() {
        let partial = makeProfile(id: "user-partial", avatarURL: nil)
        let rich = makeProfile(id: "user-partial", avatarURL: "https://cdn.example/new.jpg")

        let merged = partial.mergingCachedPresentation(with: rich)
        XCTAssertEqual(merged.avatar?.id, "https://cdn.example/new.jpg")
    }

    func testDetailCacheSeedDoesNotDropAvatar() {
        let cache = DetailPresentationCache()
        cache.seed(makeProfile(id: "user-1", avatarURL: "https://cdn.example/a.jpg"))
        cache.seed(makeProfile(id: "user-1", avatarURL: nil))

        XCTAssertEqual(cache.profile(id: ProfileID("user-1"))?.avatar?.id, "https://cdn.example/a.jpg")
    }

    func testHydrationQueuesBatchWhenEmbeddedAuthoritativeOmitsAvatar() async {
        let cache = DetailPresentationCache()
        let profileID = ProfileID("00000000-0000-4000-8000-000000000201")
        let suggestion = ExploreTraderSuggestion(
            profile: makeProfile(id: profileID.rawValue, avatarURL: nil),
            followerCount: 10,
            score: 5,
            identityLine: nil
        )
        let authoritative = makeProfile(id: profileID.rawValue, avatarURL: nil)
        let repository = AvatarBatchProfileRepository(
            profilesByID: [
                profileID: makeProfile(id: profileID.rawValue, avatarURL: "https://cdn.example/batch.jpg"),
            ]
        )

        var confirmedAbsent: Set<ProfileID> = [profileID]
        let (hydrated, metrics) = await ExploreProfileHydration.hydrateTraders(
            [suggestion],
            authoritativeProfiles: [profileID: authoritative],
            detailCache: cache,
            repository: repository,
            confirmedAbsent: &confirmedAbsent
        )

        XCTAssertEqual(metrics.batchRequestCount, 1)
        XCTAssertEqual(repository.batchCallCount, 1)
        XCTAssertEqual(hydrated.first?.profile.avatar?.id, "https://cdn.example/batch.jpg")
        XCTAssertFalse(confirmedAbsent.contains(profileID))
    }

    func testHydrationUsesCacheWithoutBatchWhenAvatarAlreadyKnown() async {
        let cache = DetailPresentationCache()
        let profileID = ProfileID("00000000-0000-4000-8000-000000000202")
        cache.seed(makeProfile(id: profileID.rawValue, avatarURL: "https://cdn.example/cached.jpg"))
        let suggestion = ExploreTraderSuggestion(
            profile: makeProfile(id: profileID.rawValue, avatarURL: nil),
            followerCount: 3,
            score: 4,
            identityLine: nil
        )
        let repository = AvatarBatchProfileRepository(profilesByID: [:])

        var confirmedAbsent: Set<ProfileID> = []
        let (hydrated, metrics) = await ExploreProfileHydration.hydrateTraders(
            [suggestion],
            authoritativeProfiles: [profileID: makeProfile(id: profileID.rawValue, avatarURL: nil)],
            detailCache: cache,
            repository: repository,
            confirmedAbsent: &confirmedAbsent
        )

        XCTAssertEqual(metrics.batchRequestCount, 0)
        XCTAssertEqual(repository.batchCallCount, 0)
        XCTAssertEqual(hydrated.first?.profile.avatar?.id, "https://cdn.example/cached.jpg")
    }

    func testResolvedProfilePrefersCacheAvatarOverEmbeddedRow() {
        let cache = DetailPresentationCache()
        let profileID = ProfileID("00000000-0000-4000-8000-000000000203")
        cache.seed(makeProfile(id: profileID.rawValue, avatarURL: "https://cdn.example/ui.jpg"))
        let trader = ExploreTraderSuggestion(
            profile: makeProfile(id: profileID.rawValue, avatarURL: nil),
            followerCount: 1,
            score: 1,
            identityLine: nil
        )
        let viewModel = ExploreViewModel(
            explore: ExploreProfileHydrationStubExploreRepository(),
            search: ExploreProfileHydrationStubSearchRepository(),
            profiles: AvatarBatchProfileRepository(profilesByID: [:]),
            session: ExploreProfileHydrationStubSession(userID: "viewer"),
            detailCache: cache,
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )

        XCTAssertEqual(viewModel.resolvedProfile(for: trader).avatar?.id, "https://cdn.example/ui.jpg")
    }

    private func makeProfile(id: String, avatarURL: String?) -> Profile {
        Profile(
            id: ProfileID(id),
            userID: UserID(id),
            username: "user-\(id.suffix(4))",
            displayName: "User \(id.suffix(4))",
            bio: nil,
            avatar: avatarURL.map { MediaReference(id: $0, kind: .image, altText: nil) },
            traderType: nil,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: .now
        )
    }
}

private final class AvatarBatchProfileRepository: ProfileRepository, @unchecked Sendable {
    private(set) var batchCallCount = 0
    private let profilesByID: [ProfileID: Profile]

    init(profilesByID: [ProfileID: Profile]) {
        self.profilesByID = profilesByID
    }

    func currentUser() async throws -> User {
        User(id: UserID("viewer"), email: nil, createdAt: .now)
    }

    func profile(id: ProfileID) async throws -> Profile {
        profilesByID[id] ?? makeEmpty(id)
    }

    func profile(username: String) async throws -> Profile {
        try await profile(id: ProfileID(username))
    }

    func profiles(ids: [ProfileID]) async throws -> [Profile] {
        batchCallCount += 1
        return ids.compactMap { profilesByID[$0] }
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
    func follow(from viewer: ProfileID, to target: ProfileID) async throws {}
    func unfollow(from viewer: ProfileID, to target: ProfileID) async throws {}
    func followers(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }

    func following(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }

    func creator(for profileID: ProfileID) async throws -> Creator? { nil }

    private func makeEmpty(_ id: ProfileID) -> Profile {
        Profile(
            id: id,
            userID: UserID(id.rawValue),
            username: id.rawValue,
            displayName: id.rawValue,
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
}

private struct ExploreProfileHydrationStubSession: SessionProviding {
    let userID: String
    var currentUserID: UserID? {
        get async { UserID(userID) }
    }

    var accessToken: String? {
        get async { "token" }
    }
}

private struct ExploreProfileHydrationStubExploreRepository: ExploreRepository {
    func discoverableProfiles(page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }

    func socialCounts(for profileIDs: [ProfileID]) async throws -> ExploreSocialCounts { .empty }
    func tradeActivitySummaries(limit: Int) async throws -> [ProfileID: ExploreTraderRanking.TradeSummary] { [:] }
    func popularRooms(limit: Int) async throws -> [ExploreRoomSuggestion] { [] }
    func searchRooms(query: String, limit: Int) async throws -> [ExploreRoomSuggestion] { [] }
}

private struct ExploreProfileHydrationStubSearchRepository: SearchRepository {
    func search(
        query: String,
        kinds: Set<SearchResultKind>,
        page: PageRequest,
        excludingProfileID: ProfileID?
    ) async throws -> CursorPage<SearchResult> {
        CursorPage(items: [], nextCursor: nil)
    }
}
