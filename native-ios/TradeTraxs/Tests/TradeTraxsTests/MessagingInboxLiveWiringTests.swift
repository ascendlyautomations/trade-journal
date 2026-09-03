import XCTest
@testable import TradeTraxs

@MainActor
final class MessagingInboxLiveWiringTests: XCTestCase {
    private let viewer = ProfileID("viewer-1")
    private let peer = ProfileID("peer-a")

    override func setUp() async throws {
        MessagesInboxStore.shared.resetForTesting()
        MessagingDomain.shared.invalidate()
        DirectConversationPairIndex.shared.invalidate()
    }

    override func tearDown() {
        MessagesInboxStore.shared.resetForTesting()
        MessagingDomain.shared.invalidate()
        DirectConversationPairIndex.shared.invalidate()
        super.tearDown()
    }

    func testCompositionUsesOneCanonicalInboxStore() {
        let store = MessagesInboxStore.shared
        let cache = DetailPresentationCache()
        let navigation = NavigationCoordinator(store: NavigationStore())

        let home = MessagesHomeViewModel(
            messages: WiringStubMessageRepository(),
            rooms: WiringStubRoomRepository(),
            profiles: WiringStubProfileRepository(),
            session: WiringStubSession(userID: viewer.rawValue),
            detailCache: cache,
            navigationCoordinator: navigation,
            inboxStore: store,
            domain: MessagingDomain.shared
        )

        XCTAssertTrue(home.canonicalInboxStore === store)
        XCTAssertTrue(MessagingDomain.shared.inboxStoreForTesting === store)
        XCTAssertEqual(home.canonicalInboxStore.debugInstance, store.debugInstance)
    }

    func testConfirmedSendPatchesVisibleHomeStoreAndMovesRowToTop() {
        let store = MessagesInboxStore.shared
        let conversationID = ConversationID("lower-row")
        let older = makeConversation(id: "top", preview: "top", at: 500, messageID: "m-top")
        let lower = makeConversation(id: "lower-row", preview: "old", at: 100, messageID: "m-old")
        store.replaceConversations([older, lower])

        let cache = DetailPresentationCache()
        let saved = Message(
            id: MessageID("m-new"),
            conversationID: conversationID,
            senderProfileID: viewer,
            kind: .text,
            body: "Unique live patch",
            attachments: [],
            replyToMessageID: nil,
            createdAt: Date(timeIntervalSince1970: 600),
            isReadByViewer: true
        )

        store.patchFromMessage(
            saved,
            viewerID: viewer,
            conversationOpen: true,
            policy: .confirmedOutgoing,
            fallbackConversation: lower,
            source: "testConfirmedSend"
        )

        XCTAssertEqual(store.visibleConversations.first?.id, conversationID)
        XCTAssertEqual(store.visibleConversations.first?.lastMessagePreview, "Unique live patch")
        XCTAssertGreaterThan(store.activityRevision, 0)

        let navigation = NavigationCoordinator(store: NavigationStore())
        let home = MessagesHomeViewModel(
            messages: WiringStubMessageRepository(),
            rooms: WiringStubRoomRepository(),
            profiles: WiringStubProfileRepository(),
            session: WiringStubSession(userID: viewer.rawValue),
            detailCache: cache,
            navigationCoordinator: navigation,
            inboxStore: store
        )
        XCTAssertEqual(home.directMessageItems.first?.preview, "Unique live patch")
        XCTAssertEqual(home.directMessageItems.first?.id, conversationID)
    }

    func testConfirmedOutgoingOverridesEqualTimestampOlderID() {
        let conversationID = ConversationID("dm")
        var existing = makeConversation(id: "dm", preview: "B", at: 200, messageID: "m-z-last")
        existing.lastMessageID = MessageID("m-z-last")
        MessagesInboxStore.shared.replaceConversations([existing])

        let saved = Message(
            id: MessageID("m-a-new"),
            conversationID: conversationID,
            senderProfileID: viewer,
            kind: .text,
            body: "B",
            attachments: [],
            replyToMessageID: nil,
            createdAt: Date(timeIntervalSince1970: 200),
            isReadByViewer: true
        )

        MessagesInboxStore.shared.patchFromMessage(
            saved,
            viewerID: viewer,
            policy: .confirmedOutgoing,
            fallbackConversation: existing,
            source: "testEqualTimestamp"
        )

        let row = MessagesInboxStore.shared.conversations.first { $0.id == conversationID }!
        XCTAssertEqual(row.lastMessageID, MessageID("m-a-new"))
    }

    func testBootstrapMergeDoesNotRegressConfirmedSendActivity() {
        let store = MessagesInboxStore.shared
        let id = ConversationID("dm")
        let local = makeConversation(id: "dm", preview: "local-new", at: 400, messageID: "local-msg")
        store.replaceConversations([local])

        let stale = makeConversation(id: "dm", preview: "server-old", at: 100, messageID: "server-msg")
        store.mergeConversationsFromBootstrap([stale])

        let row = store.conversations.first { $0.id == id }!
        XCTAssertEqual(row.lastMessagePreview, "local-new")
        XCTAssertEqual(row.lastMessageAt, Date(timeIntervalSince1970: 400))
    }

    func testOutgoingRealtimeEchoDoesNotDowngradeConfirmedSend() {
        let store = MessagesInboxStore.shared
        let conversationID = ConversationID("dm")
        let row = makeConversation(id: "dm", preview: "old", at: 100, messageID: "m-old")
        store.replaceConversations([row])

        let confirmed = Message(
            id: MessageID("m-out"),
            conversationID: conversationID,
            senderProfileID: viewer,
            kind: .text,
            body: "Unique outgoing",
            attachments: [],
            replyToMessageID: nil,
            createdAt: Date(timeIntervalSince1970: 500),
            isReadByViewer: true
        )
        store.patchFromMessage(
            confirmed,
            viewerID: viewer,
            conversationOpen: true,
            policy: .confirmedOutgoing,
            fallbackConversation: row,
            source: "confirmedSend"
        )

        let echo = confirmed
        store.patchFromMessage(
            echo,
            viewerID: viewer,
            conversationOpen: true,
            policy: .confirmedOutgoing,
            source: "inboxRealtime"
        )

        let updated = store.conversations.first { $0.id == conversationID }!
        XCTAssertEqual(updated.lastMessagePreview, "Unique outgoing")
        XCTAssertEqual(updated.lastMessageID, MessageID("m-out"))
        XCTAssertEqual(store.visibleConversations.first?.id, conversationID)
        XCTAssertEqual(store.unreadCount(for: updated), 0)
    }

    func testBootstrapReloadPreservesViewerOutgoingPreview() {
        let store = MessagesInboxStore.shared
        let conversationID = ConversationID("dm")
        let local = makeConversation(id: "dm", preview: "local only", at: 100, messageID: "m-local")
        store.replaceConversations([local])

        let bootstrap = makeConversation(
            id: "dm",
            preview: "server outgoing",
            at: 500,
            messageID: "m-server-out"
        )
        store.mergeConversationsFromBootstrap([bootstrap])

        let updated = store.conversations.first { $0.id == conversationID }!
        XCTAssertEqual(updated.lastMessagePreview, "server outgoing")
        XCTAssertEqual(updated.lastMessageID, MessageID("m-server-out"))
        XCTAssertEqual(store.visibleConversations.first?.id, conversationID)
    }

    // MARK: - Helpers

    private func makeConversation(
        id: String,
        preview: String,
        at: TimeInterval,
        messageID: String
    ) -> Conversation {
        Conversation(
            id: ConversationID(id),
            participantProfileIDs: [viewer, peer],
            title: id,
            peerUsername: id,
            avatar: nil,
            isGroup: false,
            isPinned: false,
            lastMessagePreview: preview,
            lastMessageAt: Date(timeIntervalSince1970: at),
            lastMessageID: MessageID(messageID),
            unreadCount: 0,
            isMuted: false,
            updatedAt: Date(timeIntervalSince1970: at)
        )
    }
}

#if DEBUG
extension MessagingDomain {
    var inboxStoreForTesting: MessagesInboxStore {
        let mirror = Mirror(reflecting: self)
        return mirror.children.first { $0.label == "inboxStore" }!.value as! MessagesInboxStore
    }
}
#endif

private struct WiringStubMessageRepository: MessageRepository {
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
    func deleteConversation(id: ConversationID) async throws {}

    func deleteMessageForEveryone(_ messageID: MessageID, in conversationID: ConversationID) async throws {}

    func setConversationNotificationsEnabled(
        conversationID: ConversationID,
        enabled: Bool
    ) async throws {}

    func createConversation(participantIDs: [ProfileID]) async throws -> Conversation {
        throw AppError.notImplemented(feature: "createConversation")
    }

    func findExistingDirectConversationID(viewerID: ProfileID, recipientID: ProfileID) async throws -> ConversationID? {
        nil
    }

    func usersHaveActiveBlock(viewerID: ProfileID, otherID: ProfileID) async -> Bool { false }

    func createDirectConversation(viewerID: ProfileID, recipient: Profile) async throws -> Conversation {
        ConversationCreationSupport.buildDirectConversation(
            id: ConversationID("stub-dm"),
            viewerID: viewerID,
            recipient: recipient
        )
    }

    func createGroupConversation(
        viewerID: ProfileID,
        recipients: [Profile],
        name: String?
    ) async throws -> Conversation {
        throw AppError.notImplemented(feature: "group")
    }
}

private struct WiringStubRoomRepository: RoomRepository {
    func room(id: RoomID) async throws -> TradeRoom {
        throw AppError.domain(.notFound(entity: "room", id: id.rawValue))
    }

    func rooms(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<TradeRoom> {
        CursorPage(items: [], nextCursor: nil)
    }

    func memberRooms(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<TradeRoom> {
        CursorPage(items: [], nextCursor: nil)
    }

    func unreadCounts(for roomIDs: [RoomID]) async throws -> [RoomID: Int] { [:] }
    func markRead(roomID: RoomID) async throws {}
    func channels(roomID: RoomID) async throws -> [RoomChannel] { [] }
    func membership(roomID: RoomID, profileID: ProfileID) async throws -> RoomMembership? { nil }
    func join(roomID: RoomID, profileID: ProfileID) async throws -> RoomMembership {
        RoomMembership(
            roomID: roomID,
            profileID: profileID,
            role: .member,
            joinedAt: .now,
            notificationsEnabled: true
        )
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

private struct WiringStubProfileRepository: ProfileRepository {
    func currentUser() async throws -> User { User(id: UserID("viewer-1"), email: nil, createdAt: .now) }
    func profile(id: ProfileID) async throws -> Profile {
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

    func profile(username: String) async throws -> Profile { try await profile(id: ProfileID(username)) }
    func updateProfile(_ profile: Profile) async throws -> Profile { profile }
    func stats(for: ProfileID) async throws -> ProfileStats {
        ProfileStats(
            profileID: ProfileID("x"),
            followerCount: 0,
            followingCount: 0,
            postCount: 0,
            tradeCount: 0,
            publicTradeCount: 0,
            winRate: 0
        )
    }

    func wallPosts(for: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        CursorPage(items: [], nextCursor: nil)
    }

    func wallPost(id: PostID) async throws -> Post {
        throw AppError.domain(.notFound(entity: "post", id: id.rawValue))
    }

    func followState(from: ProfileID, to: ProfileID) async throws -> FollowState { .none }
    func follow(from: ProfileID, to: ProfileID) async throws {}
    func unfollow(from: ProfileID, to: ProfileID) async throws {}
    func followers(of: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }

    func following(of: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }

    func creator(for: ProfileID) async throws -> Creator? { nil }
}

private struct WiringStubSession: SessionProviding {
    let userID: String
    var currentUserID: UserID? { get async { UserID(userID) } }
    var accessToken: String? { get async { "token" } }
}
