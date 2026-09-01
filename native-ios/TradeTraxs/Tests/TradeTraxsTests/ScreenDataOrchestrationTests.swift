import XCTest
@testable import TradeTraxs

@MainActor
final class ScreenDataOrchestrationTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        ProfileRequestFlight.shared.invalidate()
        SessionMemberRoomsStore.shared.invalidate()
        MessagesInboxStore.shared.resetForTesting()
        MessagingDomain.shared.invalidate()
        SessionNetworkProbe.resetForTesting()
    }

    override func tearDown() async throws {
        ProfileRequestFlight.shared.invalidate()
        SessionMemberRoomsStore.shared.invalidate()
        MessagesInboxStore.shared.resetForTesting()
        MessagingDomain.shared.invalidate()
        SessionNetworkProbe.resetForTesting()
        try await super.tearDown()
    }

    func testProfileRequestFlightCoalescesConcurrentProfileFetches() async throws {
        let id = ProfileID("00000000-0000-4000-8000-000000000501")
        var fetchCount = 0
        let profile = Profile(
            id: id,
            userID: UserID(id.rawValue),
            username: "coalesce",
            displayName: "Coalesce",
            bio: nil,
            avatar: nil,
            traderType: .futures,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        async let a = ProfileRequestFlight.shared.profile(id: id) {
            fetchCount += 1
            try await Task.sleep(nanoseconds: 40_000_000)
            return profile
        }
        async let b = ProfileRequestFlight.shared.profile(id: id) {
            fetchCount += 1
            try await Task.sleep(nanoseconds: 40_000_000)
            return profile
        }
        let (left, right) = try await (a, b)
        XCTAssertEqual(left.id, id)
        XCTAssertEqual(right.id, id)
        XCTAssertEqual(fetchCount, 1)
    }

    func testProfileRequestFlightCoalescesConcurrentStatsFetches() async throws {
        let id = ProfileID("00000000-0000-4000-8000-000000000502")
        var fetchCount = 0
        let stats = ProfileStats(
            profileID: id,
            followerCount: 1,
            followingCount: 2,
            postCount: 3,
            tradeCount: 4,
            publicTradeCount: 4
        )

        async let a = ProfileRequestFlight.shared.stats(for: id) {
            fetchCount += 1
            try await Task.sleep(nanoseconds: 40_000_000)
            return stats
        }
        async let b = ProfileRequestFlight.shared.stats(for: id) {
            fetchCount += 1
            try await Task.sleep(nanoseconds: 40_000_000)
            return stats
        }
        let (left, right) = try await (a, b)
        XCTAssertEqual(left.followerCount, 1)
        XCTAssertEqual(right.followingCount, 2)
        XCTAssertEqual(fetchCount, 1)
    }

    func testMemberRoomsStoreCoalescesConcurrentFetches() async throws {
        let viewer = ProfileID("00000000-0000-4000-8000-000000000503")
        let repo = CountingMemberRoomsRepository(
            rooms: [
                TradeRoom(
                    id: RoomID("room-1"),
                    ownerProfileID: viewer,
                    name: "Desk",
                    slug: "desk",
                    description: nil,
                    image: nil,
                    memberCount: 2,
                    showsOnProfile: true,
                    createdAt: Date(timeIntervalSince1970: 1_700_000_000)
                )
            ]
        )

        async let a = SessionMemberRoomsStore.shared.memberRooms(for: viewer, repository: repo)
        async let b = SessionMemberRoomsStore.shared.memberRooms(for: viewer, repository: repo)
        let (left, right) = try await (a, b)
        XCTAssertEqual(left.0.count, 1)
        XCTAssertEqual(right.0.count, 1)
        XCTAssertEqual(repo.memberRoomsCalls, 1)
        XCTAssertEqual(repo.unreadCalls, 1)

        let cached = try await SessionMemberRoomsStore.shared.memberRooms(for: viewer, repository: repo)
        XCTAssertEqual(cached.0.count, 1)
        XCTAssertEqual(repo.memberRoomsCalls, 1)
    }

    func testInboxHasLoadedRoomsPreventsTradeRoomsRefetch() async {
        let viewer = ProfileID("dev.messages.viewer")
        let inbox = MessagesInboxStore.shared
        XCTAssertFalse(inbox.hasLoadedRooms)
        TradeRoomsFixtures.seedInbox(inbox, viewerID: viewer)
        XCTAssertTrue(inbox.hasLoadedRooms)

        let environment = CompositionRoot.bootstrap()
        MessagingDomain.shared.invalidate()
        let viewModel = TradeRoomsHomeViewModel(
            messages: environment.data.messages,
            rooms: environment.data.rooms,
            profiles: environment.data.profiles,
            session: environment.data.session,
            detailCache: environment.data.detailCache,
            navigationCoordinator: environment.navigation.coordinator
        )
        viewModel.loadIfNeeded()
        // Allow the short-circuit path to finish.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertFalse(viewModel.items.isEmpty)
    }

    func testCurrentUserProfileStoreSeedsDetailCache() async {
        let environment = CompositionRoot.bootstrap()
        let cache = environment.data.detailCache
        let store = CurrentUserProfileStore(
            profiles: environment.data.profiles,
            session: environment.data.session,
            imagePipeline: environment.data.imagePipeline,
            detailCache: cache
        )
        // Development session yields a fixture without network.
        store.loadIfNeeded()
        try? await Task.sleep(nanoseconds: 200_000_000)
        if let profile = store.profile {
            XCTAssertEqual(cache.profile(id: profile.id)?.id, profile.id)
        }
        if let stats = store.stats {
            XCTAssertEqual(cache.stats(for: stats.profileID)?.postCount, stats.postCount)
        }
    }
}

// MARK: - Fixtures

private final class CountingMemberRoomsRepository: RoomRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _memberRoomsCalls = 0
    private var _unreadCalls = 0
    private let rooms: [TradeRoom]

    var memberRoomsCalls: Int {
        lock.lock(); defer { lock.unlock() }
        return _memberRoomsCalls
    }

    var unreadCalls: Int {
        lock.lock(); defer { lock.unlock() }
        return _unreadCalls
    }

    init(rooms: [TradeRoom]) {
        self.rooms = rooms
    }

    func room(id: RoomID) async throws -> TradeRoom {
        rooms.first(where: { $0.id == id }) ?? rooms[0]
    }

    func rooms(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<TradeRoom> {
        CursorPage(items: rooms, nextCursor: nil)
    }

    func memberRooms(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<TradeRoom> {
        lock.lock(); _memberRoomsCalls += 1; lock.unlock()
        try await Task.sleep(nanoseconds: 30_000_000)
        return CursorPage(items: rooms, nextCursor: nil)
    }

    func unreadCounts(for roomIDs: [RoomID]) async throws -> [RoomID: Int] {
        lock.lock(); _unreadCalls += 1; lock.unlock()
        return Dictionary(uniqueKeysWithValues: roomIDs.map { ($0, 0) })
    }

    func markRead(roomID: RoomID) async throws {}

    func channels(roomID: RoomID) async throws -> [RoomChannel] { [] }

    func membership(roomID: RoomID, profileID: ProfileID) async throws -> RoomMembership? {
        RoomMembership(
            roomID: roomID,
            profileID: profileID,
            role: .member,
            joinedAt: .now,
            notificationsEnabled: true
        )
    }

    func join(roomID: RoomID, profileID: ProfileID) async throws -> RoomMembership {
        try await membership(roomID: roomID, profileID: profileID)!
    }

    func leave(roomID: RoomID, profileID: ProfileID) async throws {}

    func messages(roomID: RoomID, page: PageRequest) async throws -> CursorPage<RoomMessage> {
        CursorPage(items: [], nextCursor: nil)
    }

    func messages(
        roomID: RoomID,
        channel: RoomChannel?,
        page: PageRequest
    ) async throws -> CursorPage<RoomMessage> {
        CursorPage(items: [], nextCursor: nil)
    }

    func send(_ message: RoomMessage) async throws -> RoomMessage { message }
    func insertMessageReaction(roomID: RoomID, messageID: RoomMessageID, userID: ProfileID, reaction: String) async throws -> RoomMessageReaction {
        RoomMessageReaction(id: "stub", messageID: messageID, userID: userID, reaction: reaction, createdAt: nil)
    }
    func deleteMessageReaction(id: String) async throws {}

    func moderate(
        roomID: RoomID,
        messageID: RoomMessageID?,
        targetProfileID: ProfileID?,
        action: RoomModerationAction
    ) async throws {}
}
