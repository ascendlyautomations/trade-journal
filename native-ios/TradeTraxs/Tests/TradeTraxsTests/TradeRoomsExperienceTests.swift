import XCTest
@testable import TradeTraxs

@MainActor
final class TradeRoomsExperienceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MessagesInboxStore.shared.resetForTesting()
        MessagingDomain.shared.invalidate()
    }

    func testHomeLoadsFixtureRoomsForDevelopmentViewer() async {
        let store = MessagesInboxStore.shared
        let viewer = TradeRoomsFixtures.viewerID
        TradeRoomsFixtures.seedInbox(store, viewerID: viewer)

        let viewModel = TradeRoomsHomeViewModel(
            messages: TradeRoomsStubMessageRepository(),
            rooms: TradeRoomsStubRoomRepository(),
            profiles: TradeRoomsStubProfileRepository(),
            session: TradeRoomsStubSession(userID: viewer.rawValue),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore()),
            inboxStore: store
        )

        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }

        XCTAssertFalse(viewModel.items.isEmpty)
        XCTAssertTrue(viewModel.items.contains { $0.id == TradeRoomsFixtures.deskRoomID })
        XCTAssertEqual(viewModel.items.first { $0.id == TradeRoomsFixtures.deskRoomID }?.unreadCount, 5)
    }

    func testHomeSearchFiltersRooms() async {
        let store = MessagesInboxStore.shared
        TradeRoomsFixtures.seedInbox(store)

        let viewModel = TradeRoomsHomeViewModel(
            messages: TradeRoomsStubMessageRepository(),
            rooms: TradeRoomsStubRoomRepository(),
            profiles: TradeRoomsStubProfileRepository(),
            session: TradeRoomsStubSession(userID: TradeRoomsFixtures.viewerID.rawValue),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore()),
            inboxStore: store
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }

        viewModel.searchText = "risk"
        XCTAssertEqual(viewModel.filteredItems.count, 1)
        XCTAssertEqual(viewModel.filteredItems.first?.room.name, "Risk First")
    }

    func testRoomMessageReactionSemanticsAggregateAndPatch() {
        let viewer = ProfileID("viewer")
        let peer = ProfileID("peer")
        let messageID = RoomMessageID("m1")
        let reactions = [
            RoomMessageReaction(id: "r1", messageID: messageID, userID: peer, reaction: "👍", createdAt: nil),
            RoomMessageReaction(id: "r2", messageID: messageID, userID: viewer, reaction: "👍", createdAt: nil),
            RoomMessageReaction(id: "r3", messageID: messageID, userID: peer, reaction: "🔥", createdAt: nil),
        ]
        let summaries = RoomMessageReactionSemantics.aggregate(reactions, viewerID: viewer)
        XCTAssertEqual(summaries.map(\.emoji), ["👍", "🔥"])
        XCTAssertEqual(summaries.first?.count, 2)
        XCTAssertTrue(summaries.first?.reactedByViewer == true)

        let optimistic = RoomMessageReaction(
            id: "optimistic-m1-😂",
            messageID: messageID,
            userID: viewer,
            reaction: "😂",
            createdAt: nil
        )
        let inserted = RoomMessageReactionSemantics.patch(reactions, next: optimistic, mode: .insert)
        XCTAssertEqual(inserted.count, reactions.count + 1)

        let duplicate = RoomMessageReactionSemantics.patch(
            inserted,
            next: RoomMessageReaction(id: "r1", messageID: messageID, userID: peer, reaction: "👍", createdAt: nil),
            mode: .insert
        )
        XCTAssertEqual(duplicate.count, inserted.count)
    }

    func testRoomPresenceSemanticsDedupesMultipleDevicesByUserID() {
        let now = ISO8601DateFormatter().string(from: Date())
        let earlier = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60))
        let state: [String: [RoomPresenceWireUser]] = [
            "device-a": [
                RoomPresenceWireUser(
                    userID: "user-1",
                    username: "alpha",
                    avatarURL: nil,
                    enteredAt: earlier
                ),
            ],
            "device-b": [
                RoomPresenceWireUser(
                    userID: "user-1",
                    username: "alpha",
                    avatarURL: "https://example.com/a.jpg",
                    enteredAt: now
                ),
            ],
            "device-c": [
                RoomPresenceWireUser(
                    userID: "user-2",
                    username: "beta",
                    avatarURL: nil,
                    enteredAt: now
                ),
            ],
        ]
        let deduped = RoomPresenceSemantics.dedupeByUserID(state)
        XCTAssertEqual(deduped.count, 2)
        let alpha = deduped.first { $0.userID == "user-1" }
        XCTAssertEqual(alpha?.enteredAt, now)
        XCTAssertEqual(alpha?.avatarURL, "https://example.com/a.jpg")
    }

    func testRoomConversationMapsMessagesOntoSharedTimeline() async {
        let store = MessagesInboxStore.shared
        TradeRoomsFixtures.seedInbox(store)

        let viewModel = RoomConversationViewModel(
            roomID: TradeRoomsFixtures.deskRoomID,
            rooms: TradeRoomsStubRoomRepository(),
            profiles: TradeRoomsStubProfileRepository(),
            session: TradeRoomsStubSession(userID: TradeRoomsFixtures.viewerID.rawValue),
            uploadService: TradeRoomsStubUploadService(),
            objectStorage: TradeRoomsStubObjectStorage(),
            detailCache: DetailPresentationCache(),
            inboxStore: store
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }

        XCTAssertFalse(viewModel.messages.isEmpty)
        XCTAssertFalse(viewModel.channels.isEmpty)
        XCTAssertEqual(viewModel.selectedChannel?.name.lowercased(), "general")
        XCTAssertTrue(viewModel.timeline.contains { item in
            if case .message = item { return true }
            return false
        })
        XCTAssertEqual(store.roomUnread[TradeRoomsFixtures.deskRoomID] ?? 0, 0)
    }

    func testOpenRoomClearsUnreadBadgeImmediately() async {
        let store = MessagesInboxStore.shared
        TradeRoomsFixtures.seedInbox(store)
        let desk = TradeRoomsFixtures.deskRoomID
        XCTAssertEqual(store.roomUnread[desk] ?? 0, 5)

        let navStore = NavigationStore()
        navStore.sessionPhase = .authenticated
        let viewModel = TradeRoomsHomeViewModel(
            messages: TradeRoomsStubMessageRepository(),
            rooms: TradeRoomsStubRoomRepository(),
            profiles: TradeRoomsStubProfileRepository(),
            session: TradeRoomsStubSession(userID: TradeRoomsFixtures.viewerID.rawValue),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: navStore),
            inboxStore: store
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }

        let item = viewModel.items.first { $0.id == desk }
        XCTAssertEqual(item?.unreadCount, 5)
        viewModel.openRoom(item!)
        XCTAssertEqual(store.roomUnread[desk] ?? 0, 0)
        XCTAssertEqual(viewModel.items.first { $0.id == desk }?.unreadCount, 0)
    }

    func testOpeningRoomConversationClearsInboxUnread() async {
        let store = MessagesInboxStore.shared
        TradeRoomsFixtures.seedInbox(store)
        let desk = TradeRoomsFixtures.deskRoomID
        XCTAssertEqual(store.roomUnread[desk] ?? 0, 5)

        let viewModel = RoomConversationViewModel(
            roomID: desk,
            rooms: TradeRoomsStubRoomRepository(),
            profiles: TradeRoomsStubProfileRepository(),
            session: TradeRoomsStubSession(userID: TradeRoomsFixtures.viewerID.rawValue),
            uploadService: TradeRoomsStubUploadService(),
            objectStorage: TradeRoomsStubObjectStorage(),
            detailCache: DetailPresentationCache(),
            inboxStore: store
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }
        XCTAssertEqual(store.roomUnread[desk] ?? 0, 0)
        XCTAssertEqual(store.activeRoomID, desk)

        viewModel.stopRealtime()
        XCTAssertNil(store.activeRoomID)
    }

    func testMarkRoomUnreadRestoresBadgeWhenRoomNotActive() {
        let store = MessagesInboxStore.shared
        TradeRoomsFixtures.seedInbox(store)
        let desk = TradeRoomsFixtures.deskRoomID
        store.markRoomRead(roomID: desk)
        XCTAssertEqual(store.roomUnread[desk] ?? 0, 0)
        store.markRoomUnread(roomID: desk)
        XCTAssertEqual(store.roomUnread[desk] ?? 0, 1)
        store.markRoomUnread(roomID: desk)
        XCTAssertEqual(store.roomUnread[desk] ?? 0, 2)
    }

    func testRoomMessageMappingDetectsImageURLContent() {
        let channelID = RoomChannelID("dev-room-desk-general")
        let roomMessage = RoomMessage(
            id: RoomMessageID("m1"),
            roomID: TradeRoomsFixtures.deskRoomID,
            senderProfileID: TradeRoomsFixtures.viewerID,
            body: "https://example.com/storage/v1/object/public/screenshots/a.jpg",
            attachedTradeID: nil,
            media: [],
            parentMessageID: nil,
            channelID: channelID,
            isPinned: false,
            createdAt: .now
        )
        let mapped = RoomMessageMapping.displayMessage(from: roomMessage)
        XCTAssertEqual(mapped.kind, .media)
        XCTAssertEqual(mapped.attachments.count, 1)
        XCTAssertEqual(mapped.conversationID, ConversationID(channelID.rawValue))
    }

    func testMembersFixtureIncludesOwnerAndRoles() {
        let room = TradeRoomsFixtures.room(id: TradeRoomsFixtures.deskRoomID)!
        let members = TradeRoomsFixtures.members(room: room, viewerID: TradeRoomsFixtures.viewerID)
        XCTAssertTrue(members.contains { $0.role == .owner })
        XCTAssertTrue(members.contains { $0.role == .admin })
    }

    func testSelectingTradesChannelLoadsOnlyThatChannelMessages() async {
        let store = MessagesInboxStore.shared
        TradeRoomsFixtures.seedInbox(store)

        let viewModel = RoomConversationViewModel(
            roomID: TradeRoomsFixtures.deskRoomID,
            rooms: TradeRoomsStubRoomRepository(),
            profiles: TradeRoomsStubProfileRepository(),
            session: TradeRoomsStubSession(userID: TradeRoomsFixtures.viewerID.rawValue),
            uploadService: TradeRoomsStubUploadService(),
            objectStorage: TradeRoomsStubObjectStorage(),
            detailCache: DetailPresentationCache(),
            inboxStore: store
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }

        let tradesChannel = viewModel.channels.first { $0.name.lowercased() == "trades" }
        XCTAssertNotNil(tradesChannel)
        viewModel.selectChannel(tradesChannel!.id)
        await waitFor {
            viewModel.selectedChannelID == tradesChannel!.id && !viewModel.messages.isEmpty
        }

        let tradeBubbles = viewModel.timeline.compactMap { item -> ConversationBubbleItem? in
            if case .message(let bubble) = item { return bubble }
            return nil
        }
        XCTAssertFalse(tradeBubbles.isEmpty)
        XCTAssertTrue(tradeBubbles.allSatisfy { $0.message.kind == .tradeShare })
        XCTAssertTrue(tradeBubbles.allSatisfy {
            $0.message.conversationID == ConversationID(tradesChannel!.id.rawValue)
        })
    }

    func testChannelSwitchPreservesCachedMessages() async {
        let store = MessagesInboxStore.shared
        TradeRoomsFixtures.seedInbox(store)

        let viewModel = RoomConversationViewModel(
            roomID: TradeRoomsFixtures.deskRoomID,
            rooms: TradeRoomsStubRoomRepository(),
            profiles: TradeRoomsStubProfileRepository(),
            session: TradeRoomsStubSession(userID: TradeRoomsFixtures.viewerID.rawValue),
            uploadService: TradeRoomsStubUploadService(),
            objectStorage: TradeRoomsStubObjectStorage(),
            detailCache: DetailPresentationCache(),
            inboxStore: store
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }

        let generalID = viewModel.selectedChannelID
        let generalCount = viewModel.messages.count
        XCTAssertNotNil(generalID)

        let trades = viewModel.channels.first { $0.name.lowercased() == "trades" }!
        viewModel.selectChannel(trades.id)
        await waitFor { viewModel.selectedChannelID == trades.id }

        viewModel.selectChannel(generalID!)
        await waitFor { viewModel.selectedChannelID == generalID }
        XCTAssertEqual(viewModel.messages.count, generalCount)
    }

    func testRoomMessageMappingPreservesTradeShare() {
        let channelID = RoomChannelID("dev-room-desk-trades")
        let roomMessage = RoomMessage(
            id: RoomMessageID("t1"),
            roomID: TradeRoomsFixtures.deskRoomID,
            senderProfileID: TradeRoomsFixtures.viewerID,
            body: "Shared a trade",
            attachedTradeID: TradeID("trade-1"),
            media: [],
            parentMessageID: nil,
            channelID: channelID,
            isPinned: false,
            createdAt: .now
        )
        let mapped = RoomMessageMapping.displayMessage(from: roomMessage)
        XCTAssertEqual(mapped.kind, .tradeShare)
        XCTAssertEqual(mapped.attachments.first?.tradeID, TradeID("trade-1"))
        XCTAssertEqual(mapped.conversationID, ConversationID(channelID.rawValue))
    }

    private func waitFor(
        timeout: TimeInterval = 2,
        _ condition: @escaping () -> Bool
    ) async {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Timed out waiting for condition")
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

private struct TradeRoomsStubSession: SessionProviding {
    let userID: String?
    var currentUserID: UserID? {
        get async {
            guard let userID else { return nil }
            return UserID(userID)
        }
    }

    var accessToken: String? {
        get async { userID == nil ? nil : "test-token" }
    }
}

private struct TradeRoomsStubProfileRepository: ProfileRepository {
    func currentUser() async throws -> User {
        User(id: UserID(TradeRoomsFixtures.viewerID.rawValue), email: nil, createdAt: .now)
    }

    func profile(id: ProfileID) async throws -> Profile {
        FollowListFixtures.profile(id: id) ?? Profile(
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

private struct TradeRoomsStubMessageRepository: MessageRepository {
    func conversations(page: PageRequest) async throws -> ConversationListResult {
        ConversationListResult(items: [], nextCursor: nil, embeddedProfiles: [])
    }

    func conversation(id: ConversationID) async throws -> Conversation {
        throw AppError.domain(.notFound(entity: "conversation", id: id.rawValue))
    }

    func messages(in conversationID: ConversationID, page: PageRequest) async throws -> CursorPage<Message> {
        CursorPage(items: [], nextCursor: nil)
    }

    func send(_ message: Message) async throws -> Message { message }
    func markRead(conversationID: ConversationID) async throws {}
    func markUnread(conversationID: ConversationID) async throws {}
    func createConversation(participantIDs: [ProfileID]) async throws -> Conversation {
        throw AppError.notImplemented(feature: "createConversation")
    }

    func findExistingDirectConversationID(
        viewerID: ProfileID,
        recipientID: ProfileID
    ) async throws -> ConversationID? {
        nil
    }

    func usersHaveActiveBlock(viewerID: ProfileID, otherID: ProfileID) async -> Bool {
        false
    }

    func createDirectConversation(viewerID: ProfileID, recipient: Profile) async throws -> Conversation {
        throw AppError.notImplemented(feature: "createDirectConversation")
    }

    func createGroupConversation(
        viewerID: ProfileID,
        recipients: [Profile],
        name: String?
    ) async throws -> Conversation {
        throw AppError.notImplemented(feature: "createGroupConversation")
    }

    func deleteConversation(id: ConversationID) async throws {}

    func deleteMessageForEveryone(_ messageID: MessageID, in conversationID: ConversationID) async throws {}

    func setConversationNotificationsEnabled(
        conversationID: ConversationID,
        enabled: Bool
    ) async throws {}
}

private struct TradeRoomsStubRoomRepository: RoomRepository {
    func room(id: RoomID) async throws -> TradeRoom {
        TradeRoomsFixtures.room(id: id) ?? TradeRoom(
            id: id,
            ownerProfileID: TradeRoomsFixtures.viewerID,
            name: "Room",
            slug: id.rawValue,
            description: nil,
            image: nil,
            memberCount: 0,
            showsOnProfile: true,
            createdAt: .now
        )
    }

    func rooms(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<TradeRoom> {
        CursorPage(items: TradeRoomsFixtures.rooms(ownerID: profileID), nextCursor: nil)
    }

    func memberRooms(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<TradeRoom> {
        CursorPage(items: TradeRoomsFixtures.rooms(ownerID: profileID), nextCursor: nil)
    }

    func unreadCounts(for roomIDs: [RoomID]) async throws -> [RoomID: Int] {
        MessagesInboxFixtures.roomUnread().filter { roomIDs.contains($0.key) }
    }

    func markRead(roomID: RoomID) async throws {}

    func channels(roomID: RoomID) async throws -> [RoomChannel] {
        TradeRoomsFixtures.channels(roomID: roomID)
    }

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
        try await messages(roomID: roomID, channel: nil, page: page)
    }

    func messages(
        roomID: RoomID,
        channel: RoomChannel?,
        page: PageRequest
    ) async throws -> CursorPage<RoomMessage> {
        CursorPage(
            items: TradeRoomsFixtures.messages(
                roomID: roomID,
                viewerID: TradeRoomsFixtures.viewerID,
                channelID: channel?.id
            ),
            nextCursor: nil
        )
    }

    func send(_ message: RoomMessage) async throws -> RoomMessage { message }

    func insertMessageReaction(
        roomID: RoomID,
        messageID: RoomMessageID,
        userID: ProfileID,
        reaction: String
    ) async throws -> RoomMessageReaction {
        RoomMessageReaction(
            id: "stub-\(messageID.rawValue)-\(reaction)",
            messageID: messageID,
            userID: userID,
            reaction: reaction,
            createdAt: Date()
        )
    }

    func deleteMessageReaction(id: String) async throws {}

    func moderate(
        roomID: RoomID,
        messageID: RoomMessageID?,
        targetProfileID: ProfileID?,
        action: RoomModerationAction
    ) async throws {}
}

private struct TradeRoomsStubUploadService: UploadService {
    func upload(_ request: UploadRequest) async throws -> MediaReference {
        MediaReference(id: request.path, kind: .image, altText: nil)
    }
}

private struct TradeRoomsStubObjectStorage: ObjectStorageProviding {
    func upload(bucket: String, path: String, data: Data, contentType: String) async throws -> String {
        path
    }

    func download(bucket: String, path: String) async throws -> Data {
        Data()
    }

    func delete(bucket: String, path: String) async throws {}

    func publicURL(bucket: String, path: String) -> URL? {
        URL(string: "https://example.com/\(bucket)/\(path)")
    }
}
