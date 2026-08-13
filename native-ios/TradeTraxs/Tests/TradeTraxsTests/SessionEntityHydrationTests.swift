import XCTest
@testable import TradeTraxs

@MainActor
final class SessionEntityHydrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SessionProfileStore.shared.invalidate()
        SessionTradeEntityStore.shared.invalidate()
        SessionNetworkProbe.resetForTesting()
    }

    override func tearDown() {
        SessionProfileStore.shared.invalidate()
        SessionTradeEntityStore.shared.invalidate()
        SessionNetworkProbe.resetForTesting()
        super.tearDown()
    }

    func testProfileBatchFetchesOnlyMissingIDsOnce() async throws {
        let cache = DetailPresentationCache()
        let a = makeProfile("00000000-0000-4000-8000-000000000201")
        let b = makeProfile("00000000-0000-4000-8000-000000000202")
        let c = makeProfile("00000000-0000-4000-8000-000000000203")
        cache.seed(a)
        let repo = CountingProfileRepository(profiles: [a, b, c])

        let first = try await SessionProfileStore.shared.profiles(
            ids: [a.id, b.id],
            detailCache: cache,
            repository: repo
        )
        XCTAssertEqual(Set(first.map(\.id)), Set([a.id, b.id]))
        XCTAssertEqual(repo.batchCallCount, 1)
        XCTAssertEqual(Set(repo.lastBatchIDs), Set([b.id]))

        SessionNetworkProbe.resetForTesting()
        let second = try await SessionProfileStore.shared.profiles(
            ids: [a.id, b.id, c.id],
            detailCache: cache,
            repository: repo
        )
        XCTAssertEqual(Set(second.map(\.id)), Set([a.id, b.id, c.id]))
        XCTAssertEqual(repo.batchCallCount, 2)
        XCTAssertEqual(Set(repo.lastBatchIDs), Set([c.id]))
    }

    func testConcurrentProfileBatchesCoalesce() async throws {
        let cache = DetailPresentationCache()
        let profiles = (1...4).map {
            makeProfile(String(format: "00000000-0000-4000-8000-%012d", $0))
        }
        let repo = CountingProfileRepository(
            profiles: profiles,
            delayNanoseconds: 60_000_000
        )

        async let x = SessionProfileStore.shared.profiles(
            ids: [profiles[0].id, profiles[1].id, profiles[2].id],
            detailCache: cache,
            repository: repo
        )
        async let y = SessionProfileStore.shared.profiles(
            ids: [profiles[0].id, profiles[1].id, profiles[2].id],
            detailCache: cache,
            repository: repo
        )
        _ = try await x
        _ = try await y
        XCTAssertEqual(repo.batchCallCount, 1)
    }

    func testTradeBatchHydrationSkipsCached() async throws {
        let cache = DetailPresentationCache()
        let owner = ProfileID("00000000-0000-4000-8000-000000000301")
        let t1 = makeTrade("t1", owner: owner)
        let t2 = makeTrade("t2", owner: owner)
        cache.seed(t1)
        let repo = CountingTradeRepository(trades: [t1, t2])

        let result = try await SessionTradeEntityStore.shared.trades(
            ids: [t1.id, t2.id],
            detailCache: cache,
            repository: repo
        )
        XCTAssertEqual(Set(result.map(\.id)), Set([t1.id, t2.id]))
        XCTAssertEqual(repo.batchCallCount, 1)
        XCTAssertEqual(repo.lastBatchIDs, [t2.id])
    }

    func testStoryFilterDropsUnparseableCreatedAtNotDistantPastInvention() {
        let now = Date()
        // Simulated: decoder must not invent distantPast — filter only real timestamps.
        let fresh = Story(
            id: StoryID("fresh"),
            authorProfileID: ProfileID("a"),
            media: MediaReference(id: "m", kind: .image, altText: nil),
            expiresAt: now.addingTimeInterval(3_600),
            createdAt: now.addingTimeInterval(-1_800),
            viewerHasSeen: false
        )
        let garbageAge = Story(
            id: StoryID("old"),
            authorProfileID: ProfileID("b"),
            media: MediaReference(id: "m2", kind: .image, altText: nil),
            expiresAt: now,
            createdAt: .distantPast,
            viewerHasSeen: false
        )
        let active = ActiveStorySemantics.filterActive([fresh, garbageAge], now: now)
        XCTAssertEqual(active.map(\.id), [fresh.id])
    }

    func testISO8601ParsesPostgresFractionalAndSpaceSeparated() {
        let samples = [
            "2026-08-11T23:10:00.123456+00:00",
            "2026-08-11 23:10:00.123456+00",
            "2026-08-11T23:10:00Z",
            "2026-08-11 23:10:00.123+00:00",
            // Variable fractional width — previous parser invented distantPast → Stories empty.
            "2026-08-11T23:10:00.123456789+00:00",
            "2026-08-11T23:10:00.12+00:00",
            "2026-08-11T23:10:00.1+00:00",
        ]
        for sample in samples {
            XCTAssertNotNil(ISO8601.date(from: sample), "Failed to parse \(sample)")
            let created = ISO8601.date(from: sample)!
            XCTAssertTrue(
                ActiveStorySemantics.isActive(createdAt: created, now: created.addingTimeInterval(60)),
                "Parsed \(sample) should be active shortly after create"
            )
        }
    }

    func testSequentialProfileBatchesSkipAlreadyCachedIDs() async throws {
        let cache = DetailPresentationCache()
        let profiles = (1...4).map {
            makeProfile(String(format: "00000000-0000-4000-8000-%012d", $0))
        }
        let repo = CountingProfileRepository(profiles: profiles)

        _ = try await SessionProfileStore.shared.profiles(
            ids: [profiles[0].id, profiles[1].id, profiles[2].id],
            detailCache: cache,
            repository: repo
        )
        _ = try await SessionProfileStore.shared.profiles(
            ids: [profiles[1].id, profiles[2].id, profiles[3].id],
            detailCache: cache,
            repository: repo
        )
        XCTAssertEqual(repo.batchCallCount, 2)
        XCTAssertEqual(Set(repo.batchHistory[0]), Set(profiles[0...2].map(\.id)))
        XCTAssertEqual(Set(repo.batchHistory[1]), Set([profiles[3].id]))
    }

    // MARK: - Helpers

    private func makeProfile(_ id: String) -> Profile {
        Profile(
            id: ProfileID(id),
            userID: UserID(id),
            username: "u\(id.suffix(4))",
            displayName: "User \(id.suffix(4))",
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

    private func makeTrade(_ id: String, owner: ProfileID) -> Trade {
        let now = Date()
        return Trade(
            id: TradeID(id),
            ownerProfileID: owner,
            accountID: nil,
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 1,
            exitPrice: 2,
            entryAt: now,
            exitAt: now,
            realizedPnL: Money(amount: 10),
            riskReward: nil,
            points: nil,
            sessionLabel: nil,
            visibility: .public,
            publicCaption: nil,
            thumbnail: nil,
            notePreview: nil,
            createdAt: now,
            updatedAt: now
        )
    }
}

private final class CountingProfileRepository: ProfileRepository, @unchecked Sendable {
    private let profiles: [Profile]
    private let delayNanoseconds: UInt64
    private(set) var batchCallCount = 0
    private(set) var lastBatchIDs: [ProfileID] = []
    private(set) var batchHistory: [[ProfileID]] = []
    var allBatchIDs: [ProfileID] { batchHistory.flatMap { $0 } }

    init(profiles: [Profile], delayNanoseconds: UInt64 = 0) {
        self.profiles = profiles
        self.delayNanoseconds = delayNanoseconds
    }

    func currentUser() async throws -> User {
        User(id: UserID("u"), email: nil, createdAt: .now)
    }

    func profile(id: ProfileID) async throws -> Profile {
        profiles.first { $0.id == id }!
    }

    func profiles(ids: [ProfileID]) async throws -> [Profile] {
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        batchCallCount += 1
        lastBatchIDs = ids
        batchHistory.append(ids)
        return profiles.filter { ids.contains($0.id) }
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
        throw AppError.unknown(message: "not found")
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

private final class CountingTradeRepository: TradeRepository, @unchecked Sendable {
    private let trades: [Trade]
    private(set) var batchCallCount = 0
    private(set) var lastBatchIDs: [TradeID] = []

    init(trades: [Trade]) {
        self.trades = trades
    }

    func trade(id: TradeID) async throws -> Trade {
        trades.first { $0.id == id }!
    }

    func trades(ids: [TradeID]) async throws -> [Trade] {
        batchCallCount += 1
        lastBatchIDs = ids
        return trades.filter { ids.contains($0.id) }
    }

    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Trade> {
        CursorPage(items: [], nextCursor: nil)
    }

    func save(_ draft: TradeDraft) async throws -> Trade {
        throw AppError.unknown(message: "stub")
    }

    func update(_ trade: Trade) async throws -> Trade { trade }
    func delete(id: TradeID) async throws {}
    func images(for tradeID: TradeID) async throws -> [TradeImage] { [] }
    func notes(for tradeID: TradeID) async throws -> [TradeNote] { [] }
    func statistics(
        for profileID: ProfileID,
        interval: DateIntervalValue
    ) async throws -> TradeStatistics {
        TradeStatistics(
            tradeCount: 0,
            winCount: 0,
            lossCount: 0,
            totalPnL: Money(amount: 0),
            averagePnL: Money(amount: 0),
            averageRiskReward: nil,
            winRate: 0
        )
    }
    func accounts(for profileID: ProfileID) async throws -> [TradingAccount] { [] }
}
