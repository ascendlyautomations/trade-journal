import XCTest
@testable import TradeTraxs

@MainActor
final class Phase10ERealtimeConsolidationTests: XCTestCase {
    private let viewer = ProfileID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private let target = ProfileID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
    private let other = ProfileID("cccccccc-cccc-cccc-cccc-cccccccccccc")

    override func setUp() {
        super.setUp()
        SessionDiskCache.clearAll()
        RelationshipWriteGeneration.resetForTesting()
        FollowMutationCoordinator.shared.invalidate()
        MessagingRealtimeDeliveryCoordinator.resetSession()
    }

    override func tearDown() async throws {
        await SessionFollowingStore.shared.invalidate()
        MessagingRealtimeDeliveryCoordinator.resetSession()
        ActivityInboxStore.shared.invalidate()
        try await super.tearDown()
    }

    func testFollowingCompleteSetDeltaIncludesNewAuthor() async {
        await SessionFollowingStore.shared.seedComplete(viewerID: viewer.rawValue, ids: [target.rawValue])
        await SessionFollowingStore.shared.setFollowing(
            viewerID: viewer.rawValue,
            targetID: other.rawValue,
            isFollowing: true
        )
        let cached = await SessionFollowingStore.shared.cached(viewerID: viewer.rawValue)
        XCTAssertTrue(cached?.contains(other.rawValue) == true)
        XCTAssertTrue(cached?.contains(target.rawValue) == true)
    }

    func testNotificationInsertFromPayloadWithoutBootstrap() async {
        let store = ActivityInboxStore.shared
        store.invalidate()
        let record: [String: Any] = [
            "id": "notif-1",
            "user_id": viewer.rawValue,
            "sender_id": other.rawValue,
            "type": "like",
            "content": "{\"title\":\"Like\",\"body\":\"liked your post\"}",
            "read": false,
            "created_at": ISO8601DateFormatter().string(from: Date()),
        ]
        let payload = PostgresChangeRecordCodec.encode(record)!
        let signal = MessageRealtimeSignal(kind: .insert, messageID: "notif-1", recordPayload: payload)

        let repo = StubNotificationRepository()
        await store.testing_applyRealtime(signal: signal, notifications: repo)

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.unreadCount, 1)
        XCTAssertEqual(repo.notificationFetchCount, 0)
    }

    func testDmDedupeBetweenInboxAndThread() {
        let convo = "convo-1"
        XCTAssertTrue(
            MessagingRealtimeDeliveryCoordinator.claimMessageInsert(
                domain: "dm-thread",
                messageID: "m1",
                conversationID: convo
            )
        )
        XCTAssertFalse(
            MessagingRealtimeDeliveryCoordinator.claimMessageInsert(
                domain: "inbox-dm",
                messageID: "m1",
                conversationID: convo
            )
        )
    }

    func testRoomMemberCountDeltaNeverNegative() {
        let store = MessagesInboxStore.shared
        let roomID = RoomID("11111111-1111-1111-1111-111111111111")
        store.testing_seedRoom(id: roomID, memberCount: 0)
        store.applyMemberCountDelta(roomID: roomID, delta: -1)
        XCTAssertEqual(store.rooms.first(where: { $0.id == roomID })?.memberCount, 0)
    }
}

private final class StubNotificationRepository: NotificationRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _notificationFetchCount = 0
    var notificationFetchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _notificationFetchCount
    }

    func notifications(page: PageRequest) async throws -> CursorPage<ActivityNotification> {
        CursorPage(items: [], nextCursor: nil)
    }

    func notification(id: NotificationID) async throws -> ActivityNotification? {
        TestLock.withLock(lock) {
            _notificationFetchCount += 1
        }
        return nil
    }

    func unreadCount() async throws -> Int { 0 }
    func markRead(id: NotificationID) async throws {}
    func markRead(ids: [NotificationID]) async throws -> Int { 0 }
    func markMessageNotificationsRead() async throws -> Int { 0 }
    func markRoomNotificationsRead(roomID: RoomID, slug: String?) async throws -> Int { 0 }
    func markAllRead() async throws {}
    func delete(id: NotificationID) async throws {}
    func delete(ids: [NotificationID]) async throws -> Int { 0 }
    func profiles(ids: [ProfileID]) async throws -> [Profile] { [] }
}

extension MessagesInboxStore {
    fileprivate func testing_seedRoom(id: RoomID, memberCount: Int) {
        let room = TradeRoom(
            id: id,
            ownerProfileID: ProfileID("22222222-2222-2222-2222-222222222222"),
            name: "Room",
            slug: "room",
            description: nil,
            image: nil,
            memberCount: memberCount,
            showsOnProfile: true,
            createdAt: .now
        )
        replaceRooms([room], activityAt: [:], unread: [:])
    }
}
