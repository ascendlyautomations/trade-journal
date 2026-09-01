import XCTest
@testable import TradeTraxs

@MainActor
final class MessagesExperienceTests: XCTestCase {
    override func setUp() async throws {
        MessagesInboxStore.shared.resetForTesting()
        MessagingDomain.shared.invalidate()
    }

    func testRelativeTimestampBuckets() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(
            MessagesInboxSupport.relativeTimestamp(now.addingTimeInterval(-30), now: now),
            "Now"
        )
        XCTAssertEqual(
            MessagesInboxSupport.relativeTimestamp(now.addingTimeInterval(-120), now: now),
            "2m"
        )
        XCTAssertEqual(
            MessagesInboxSupport.relativeTimestamp(now.addingTimeInterval(-7_200), now: now),
            "2h"
        )
        XCTAssertEqual(
            MessagesInboxSupport.relativeTimestamp(now.addingTimeInterval(-200_000), now: now),
            "2d"
        )
    }

    func testFixtureInboxHasPinnedDirectMessagesAndRooms() {
        MessagesInboxFixtures.seedStore(MessagesInboxStore.shared)
        let store = MessagesInboxStore.shared

        XCTAssertTrue(store.hasLoaded)
        XCTAssertFalse(store.visibleConversations.isEmpty)
        XCTAssertTrue(store.isPinned(ConversationID("dev-dm-ada")))
        XCTAssertTrue(store.isMuted(ConversationID("dev-dm-nq")))
        XCTAssertTrue(store.isTyping(ConversationID("dev-dm-ict")))
        XCTAssertEqual(store.rooms.count, 2)
        XCTAssertTrue(store.isRoomMuted(RoomID("dev-room-risk")))
        XCTAssertEqual(store.roomUnread[RoomID("dev-room-desk")], 5)
    }

    func testLocalSearchFiltersDirectMessagesAndRoomsWithoutNetwork() async {
        let cache = DetailPresentationCache()
        for profile in MessagesInboxFixtures.profiles(
            for: MessagesInboxFixtures.conversations(viewerID: MessagesInboxFixtures.viewerID),
            viewerID: MessagesInboxFixtures.viewerID
        ) {
            cache.seed(profile)
        }

        let viewModel = MessagesHomeViewModel(
            messages: MessagesStubMessageRepository(),
            rooms: MessagesStubRoomRepository(),
            profiles: MessagesStubProfileRepository(),
            session: MessagesStubSession(userID: MessagesInboxFixtures.viewerID.rawValue),
            detailCache: cache,
            navigationCoordinator: NavigationCoordinator(store: NavigationStore()),
            inboxStore: .shared
        )

        viewModel.loadIfNeeded()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertFalse(viewModel.showsEmpty)

        viewModel.searchText = "nq"
        let hits = viewModel.pinnedItems + viewModel.directMessageItems
        let dmOrPinnedHit = hits.contains {
            $0.displayName.localizedCaseInsensitiveContains("NQ")
                || ($0.username?.localizedCaseInsensitiveContains("nq") ?? false)
                || $0.preview.localizedCaseInsensitiveContains("NQ")
        }
        let roomHit = viewModel.tradeRoomItems.contains {
            $0.room.name.localizedCaseInsensitiveContains("NQ")
        }
        XCTAssertTrue(dmOrPinnedHit || roomHit)

        viewModel.searchText = "zzzz-no-match"
        XCTAssertTrue(viewModel.showsFilteredEmpty)
    }

    func testMuteAndUnreadMutateSessionCache() {
        MessagesInboxFixtures.seedStore(MessagesInboxStore.shared)
        let store = MessagesInboxStore.shared
        let id = ConversationID("dev-dm-ada")
        let conversation = store.conversations.first { $0.id == id }!

        XCTAssertEqual(store.unreadCount(for: conversation), 2)
        store.markRead(conversationID: id)
        XCTAssertEqual(store.unreadCount(for: store.conversations.first { $0.id == id }!), 0)
        store.markUnread(conversationID: id)
        XCTAssertEqual(store.unreadCount(for: store.conversations.first { $0.id == id }!), 1)

        store.toggleMute(conversationID: id)
        XCTAssertTrue(store.isMuted(id))
        store.removeConversation(id: id)
        XCTAssertFalse(store.visibleConversations.contains { $0.id == id })
    }

    func testOpenConversationClearsUnreadBadgeImmediately() async {
        MessagesInboxFixtures.seedStore(MessagesInboxStore.shared)
        let cache = DetailPresentationCache()
        let navStore = NavigationStore()
        navStore.sessionPhase = .authenticated
        let viewModel = MessagesHomeViewModel(
            messages: MessagesStubMessageRepository(),
            rooms: MessagesStubRoomRepository(),
            profiles: MessagesStubProfileRepository(),
            session: MessagesStubSession(userID: MessagesInboxFixtures.viewerID.rawValue),
            detailCache: cache,
            navigationCoordinator: NavigationCoordinator(store: navStore),
            inboxStore: .shared
        )
        viewModel.loadIfNeeded()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let id = ConversationID("dev-dm-ada")
        let item = (viewModel.pinnedItems + viewModel.directMessageItems).first { $0.id == id }
        XCTAssertEqual(item?.unreadCount, 2)

        viewModel.openConversation(item!)

        let cleared = MessagesInboxStore.shared.conversations.first { $0.id == id }!
        XCTAssertEqual(MessagesInboxStore.shared.unreadCount(for: cleared), 0)
        let row = (viewModel.pinnedItems + viewModel.directMessageItems).first { $0.id == id }
        XCTAssertEqual(row?.unreadCount, 0)
    }

    func testReplaceConversationsPreservesOptimisticUnreadClear() {
        let id = ConversationID("race-dm")
        let unread = Conversation(
            id: id,
            participantProfileIDs: [],
            title: "Race",
            peerUsername: "race",
            avatar: nil,
            isGroup: false,
            isPinned: false,
            lastMessagePreview: "hi",
            lastMessageAt: Date(timeIntervalSince1970: 100),
            unreadCount: 5,
            isMuted: false,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        MessagesInboxStore.shared.replaceConversations([unread])
        XCTAssertEqual(MessagesInboxStore.shared.totalDirectMessageUnread, 5)

        MessagesInboxStore.shared.markRead(conversationID: id)
        XCTAssertEqual(MessagesInboxStore.shared.totalDirectMessageUnread, 0)

        // Bootstrap arrives with stale unread before mark_conversation_read finishes.
        var stale = unread
        stale.unreadCount = 5
        MessagesInboxStore.shared.replaceConversations([stale])

        let row = MessagesInboxStore.shared.conversations.first { $0.id == id }!
        XCTAssertEqual(MessagesInboxStore.shared.unreadCount(for: row), 0)
        XCTAssertEqual(MessagesInboxStore.shared.totalDirectMessageUnread, 0)

        // Backend confirms zero — override drops, count stays cleared.
        var confirmed = unread
        confirmed.unreadCount = 0
        MessagesInboxStore.shared.replaceConversations([confirmed])
        XCTAssertEqual(
            MessagesInboxStore.shared.unreadCount(for: MessagesInboxStore.shared.conversations.first { $0.id == id }!),
            0
        )
    }

    func testPushMessagesThreadClearsUnreadLikeInboxTap() {
        let id = ConversationID("push-dm")
        let unread = Conversation(
            id: id,
            participantProfileIDs: [],
            title: "Push",
            peerUsername: "push",
            avatar: nil,
            isGroup: false,
            isPinned: false,
            lastMessagePreview: "ping",
            lastMessageAt: Date(timeIntervalSince1970: 100),
            unreadCount: 3,
            isMuted: false,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        MessagesInboxStore.shared.replaceConversations([unread])

        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let navigation = NavigationCoordinator(store: store)
        navigation.open(.messages(.thread(id)))

        let row = MessagesInboxStore.shared.conversations.first { $0.id == id }!
        XCTAssertEqual(MessagesInboxStore.shared.unreadCount(for: row), 0)
        XCTAssertEqual(store.paths.messages.last, .thread(id))
    }

    func testNewChatReusesExistingConversation() async {
        MessagesInboxFixtures.seedStore(MessagesInboxStore.shared)
        let cache = DetailPresentationCache()
        let viewModel = NewChatViewModel(
            messages: MessagesStubMessageRepository(),
            search: MessagesStubSearchRepository(),
            profiles: MessagesStubProfileRepository(),
            explore: MessagesStubExploreRepository(),
            session: MessagesStubSession(userID: MessagesInboxFixtures.viewerID.rawValue),
            detailCache: cache,
            inboxStore: .shared
        )
        await viewModel.prepare()

        let ada = FollowListFixtures.profile(id: ProfileID("dev.follower.ada"))!
        let first = await viewModel.select(ada)
        let second = await viewModel.select(ada)
        XCTAssertEqual(first?.id, ConversationID("dev-dm-ada"))
        XCTAssertEqual(second?.id, first?.id)
        XCTAssertEqual(
            MessagesInboxStore.shared.conversations.filter {
                Set($0.participantProfileIDs) == Set([MessagesInboxFixtures.viewerID, ada.id])
            }.count,
            1
        )
    }

    func testUpsertConversationMutatesCacheWithoutFullReload() {
        MessagesInboxFixtures.seedStore(MessagesInboxStore.shared)
        let before = MessagesInboxStore.shared.conversations.count
        let created = Conversation(
            id: ConversationID("dev-dm-new"),
            participantProfileIDs: [MessagesInboxFixtures.viewerID, ProfileID("dev.follower.grace")],
            title: "Grace Hopper",
            peerUsername: "grace",
            avatar: nil,
            isGroup: false,
            isPinned: false,
            lastMessagePreview: "Hey",
            lastMessageAt: .now,
            unreadCount: 0,
            isMuted: false,
            updatedAt: .now
        )
        MessagesInboxStore.shared.upsertConversation(created)
        XCTAssertEqual(MessagesInboxStore.shared.conversations.count, before + 1)
        XCTAssertTrue(MessagesInboxStore.shared.conversations.contains { $0.id == created.id })
    }

    func testUpsertMovesConversationToTopByLastMessageAt() {
        let older = Conversation(
            id: ConversationID("older"),
            participantProfileIDs: [],
            title: "Older",
            peerUsername: "older",
            avatar: nil,
            isGroup: false,
            isPinned: false,
            lastMessagePreview: "old",
            lastMessageAt: Date(timeIntervalSince1970: 100),
            unreadCount: 0,
            isMuted: false,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = Conversation(
            id: ConversationID("newer"),
            participantProfileIDs: [],
            title: "Newer",
            peerUsername: "newer",
            avatar: nil,
            isGroup: false,
            isPinned: false,
            lastMessagePreview: "mid",
            lastMessageAt: Date(timeIntervalSince1970: 200),
            unreadCount: 0,
            isMuted: false,
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        MessagesInboxStore.shared.replaceConversations([older, newer])
        XCTAssertEqual(MessagesInboxStore.shared.visibleConversations.first?.id, newer.id)

        var bumped = older
        bumped.lastMessagePreview = "fresh"
        bumped.lastMessageAt = Date(timeIntervalSince1970: 300)
        bumped.updatedAt = Date(timeIntervalSince1970: 300)
        MessagesInboxStore.shared.upsertConversation(bumped)

        XCTAssertEqual(
            MessagesInboxStore.shared.visibleConversations.map(\.id.rawValue),
            ["older", "newer"]
        )
    }

    func testDeleteConversationRemovesFromInboxAfterConfirm() async {
        MessagesInboxFixtures.seedStore(MessagesInboxStore.shared)
        let cache = DetailPresentationCache()
        let viewModel = MessagesHomeViewModel(
            messages: MessagesStubMessageRepository(),
            rooms: MessagesStubRoomRepository(),
            profiles: MessagesStubProfileRepository(),
            session: MessagesStubSession(userID: MessagesInboxFixtures.viewerID.rawValue),
            detailCache: cache,
            navigationCoordinator: NavigationCoordinator(store: NavigationStore()),
            inboxStore: .shared
        )
        let id = ConversationID("dev-dm-ada")
        viewModel.requestDeleteConversation(id: id)
        XCTAssertTrue(viewModel.showsDeleteConfirmation)
        await viewModel.confirmDeleteConversation()
        XCTAssertFalse(MessagesInboxStore.shared.visibleConversations.contains { $0.id == id })
        XCTAssertFalse(viewModel.showsDeleteConfirmation)
    }

    func testInvalidateClearsLoadedInboxForNextSession() {
        MessagesInboxFixtures.seedStore(MessagesInboxStore.shared)
        XCTAssertTrue(MessagesInboxStore.shared.hasLoaded)
        XCTAssertFalse(MessagesInboxStore.shared.conversations.isEmpty)

        MessagesInboxStore.shared.invalidate()

        XCTAssertFalse(MessagesInboxStore.shared.hasLoaded)
        XCTAssertTrue(MessagesInboxStore.shared.conversations.isEmpty)
        XCTAssertTrue(MessagesInboxStore.shared.rooms.isEmpty)
    }

    func testConversationSortPinnedThenLastMessageAt() {
        let older = Conversation(
            id: ConversationID("a"),
            participantProfileIDs: [],
            title: "A",
            peerUsername: "a",
            avatar: nil,
            isGroup: false,
            isPinned: false,
            lastMessagePreview: "old",
            lastMessageAt: Date(timeIntervalSince1970: 100),
            unreadCount: 0,
            isMuted: false,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = Conversation(
            id: ConversationID("b"),
            participantProfileIDs: [],
            title: "B",
            peerUsername: "b",
            avatar: nil,
            isGroup: false,
            isPinned: false,
            lastMessagePreview: "new",
            lastMessageAt: Date(timeIntervalSince1970: 200),
            unreadCount: 0,
            isMuted: false,
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let pinned = Conversation(
            id: ConversationID("c"),
            participantProfileIDs: [],
            title: "C",
            peerUsername: "c",
            avatar: nil,
            isGroup: false,
            isPinned: true,
            lastMessagePreview: "pin",
            lastMessageAt: Date(timeIntervalSince1970: 50),
            unreadCount: 0,
            isMuted: false,
            updatedAt: Date(timeIntervalSince1970: 50)
        )
        MessagesInboxStore.shared.replaceConversations([older, newer, pinned])
        XCTAssertEqual(
            MessagesInboxStore.shared.visibleConversations.map(\.id.rawValue),
            ["c", "b", "a"]
        )
    }

    // MARK: - Messaging domain architecture

    func testMessagingDomainBootstrapSharedByMessagesAndTradeRooms() async {
        let cache = DetailPresentationCache()
        let navigation = NavigationCoordinator(store: NavigationStore())
        let messagesVM = MessagesHomeViewModel(
            messages: MessagesStubMessageRepository(),
            rooms: MessagesStubRoomRepository(),
            profiles: MessagesStubProfileRepository(),
            session: MessagesStubSession(userID: MessagesInboxFixtures.viewerID.rawValue),
            detailCache: cache,
            navigationCoordinator: navigation,
            inboxStore: MessagesInboxStore.shared
        )
        messagesVM.loadIfNeeded()
        let deadline = Date().addingTimeInterval(2)
        while messagesVM.phase != .loaded, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(messagesVM.phase, .loaded)
        XCTAssertTrue(MessagingDomain.shared.state.didBootstrap)
        XCTAssertTrue(MessagesInboxStore.shared.hasLoadedRooms)

        let roomsVM = TradeRoomsHomeViewModel(
            messages: MessagesStubMessageRepository(),
            rooms: MessagesStubRoomRepository(),
            profiles: MessagesStubProfileRepository(),
            session: MessagesStubSession(userID: MessagesInboxFixtures.viewerID.rawValue),
            detailCache: cache,
            navigationCoordinator: navigation,
            inboxStore: MessagesInboxStore.shared
        )
        roomsVM.loadIfNeeded()
        let roomsDeadline = Date().addingTimeInterval(2)
        while roomsVM.phase != .loaded, Date() < roomsDeadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(roomsVM.phase, .loaded)
        XCTAssertFalse(roomsVM.items.isEmpty)
    }

    func testScreenTypealiasesMatchCanonicalOwners() {
        XCTAssertTrue(MessagesScreenViewModel.self == MessagesHomeViewModel.self)
        XCTAssertTrue(TradeRoomsScreenViewModel.self == TradeRoomsHomeViewModel.self)
        XCTAssertTrue(ConversationScreenViewModel.self == ConversationViewModel.self)
        XCTAssertTrue(RoomConversationScreenViewModel.self == RoomConversationViewModel.self)
    }
}

// MARK: - Stubs

private struct MessagesStubSession: SessionProviding {
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

private struct MessagesStubMessageRepository: MessageRepository {
    func conversations(page: PageRequest) async throws -> ConversationListResult {
        await MainActor.run {
            ConversationListResult(
                items: MessagesInboxStore.shared.conversations,
                nextCursor: nil,
                embeddedProfiles: []
            )
        }
    }

    func conversation(id: ConversationID) async throws -> Conversation {
        await MainActor.run {
            MessagesInboxStore.shared.conversations.first { $0.id == id }!
        }
    }

    func messages(in conversationID: ConversationID, page: PageRequest) async throws -> CursorPage<Message> {
        CursorPage(items: [], nextCursor: nil)
    }

    func send(_ message: Message) async throws -> Message { message }

    func markRead(conversationID: ConversationID) async throws {}
    func markUnread(conversationID: ConversationID) async throws {}

    func createConversation(participantIDs: [ProfileID]) async throws -> Conversation {
        Conversation(
            id: ConversationID("created"),
            participantProfileIDs: participantIDs,
            title: nil,
            peerUsername: nil,
            avatar: nil,
            isGroup: false,
            isPinned: false,
            lastMessagePreview: nil,
            lastMessageAt: nil,
            unreadCount: 0,
            isMuted: false,
            updatedAt: .now
        )
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
        ConversationCreationSupport.buildDirectConversation(
            id: ConversationID("created"),
            viewerID: viewerID,
            recipient: recipient
        )
    }

    func createGroupConversation(
        viewerID: ProfileID,
        recipients: [Profile],
        name: String?
    ) async throws -> Conversation {
        ConversationCreationSupport.buildGroupConversation(
            id: ConversationID("group-created"),
            viewerID: viewerID,
            recipients: recipients,
            name: name
        )
    }

    func deleteConversation(id: ConversationID) async throws {
        await MainActor.run {
            MessagesInboxStore.shared.removeConversation(id: id)
        }
    }
}

private struct MessagesStubRoomRepository: RoomRepository {
    func room(id: RoomID) async throws -> TradeRoom {
        await MainActor.run {
            MessagesInboxStore.shared.rooms.first { $0.id == id }!
        }
    }

    func rooms(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<TradeRoom> {
        await MainActor.run {
            CursorPage(items: MessagesInboxStore.shared.rooms, nextCursor: nil)
        }
    }

    func memberRooms(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<TradeRoom> {
        try await rooms(for: profileID, page: page)
    }

    func unreadCounts(for roomIDs: [RoomID]) async throws -> [RoomID: Int] {
        [:]
    }

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

private struct MessagesStubProfileRepository: ProfileRepository {
    func currentUser() async throws -> User {
        User(id: UserID(MessagesInboxFixtures.viewerID.rawValue), email: nil, createdAt: .now)
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

    func followState(from viewer: ProfileID, to target: ProfileID) async throws -> FollowState {
        .none
    }

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

private struct MessagesStubExploreRepository: ExploreRepository {
    func discoverableProfiles(page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }

    func socialCounts(for profileIDs: [ProfileID]) async throws -> ExploreSocialCounts { .empty }

    func tradeActivitySummaries(limit: Int) async throws -> [ProfileID: ExploreTraderRanking.TradeSummary] {
        [:]
    }

    func popularRooms(limit: Int) async throws -> [ExploreRoomSuggestion] { [] }

    func searchRooms(query: String, limit: Int) async throws -> [ExploreRoomSuggestion] { [] }
}

private struct MessagesStubSearchRepository: SearchRepository {
    func search(
        query: String,
        kinds: Set<SearchResultKind>,
        page: PageRequest,
        excludingProfileID: ProfileID?
    ) async throws -> CursorPage<SearchResult> {
        CursorPage(items: [], nextCursor: nil)
    }
}
