import XCTest
@testable import TradeTraxs

@MainActor
final class ConversationCreationTests: XCTestCase {
    private let viewer = ProfileID("viewer-1")
    private let peerA = ProfileID("peer-a")
    private let peerB = ProfileID("peer-b")

    override func setUp() async throws {
        MessagesInboxStore.shared.resetForTesting()
        DirectConversationPairIndex.shared.invalidate()
        ConversationThreadSessionStore.shared.invalidate()
        ConversationCreationCoordinator.shared.invalidate()
    }

    override func tearDown() {
        MessagesInboxStore.shared.resetForTesting()
        DirectConversationPairIndex.shared.invalidate()
        ConversationThreadSessionStore.shared.invalidate()
        ConversationCreationCoordinator.shared.invalidate()
        super.tearDown()
    }

    func testExistingDirectConversationReusedFromInbox() async throws {
        let recipient = makeProfile(id: peerA, name: "Peer A")
        let existing = ConversationCreationSupport.buildDirectConversation(
            id: ConversationID("existing-dm"),
            viewerID: viewer,
            recipient: recipient
        )
        MessagesInboxStore.shared.upsertConversation(existing)

        let repo = TrackingMessageRepository()
        let result = try await ConversationCreationCoordinator.shared.openDirectConversation(
            viewerID: viewer,
            recipient: recipient,
            messages: repo,
            detailCache: DetailPresentationCache(),
            inboxStore: MessagesInboxStore.shared
        )

        XCTAssertTrue(result.wasExisting)
        XCTAssertEqual(result.conversation.id, existing.id)
        XCTAssertEqual(repo.createDirectCallCount, 0)
        XCTAssertEqual(repo.duplicateLookupCallCount, 0)
    }

    func testNewDirectConversationUsesOptimizedRepositoryPath() async throws {
        let recipient = makeProfile(id: peerA, name: "Peer A")
        let repo = TrackingMessageRepository()

        let result = try await ConversationCreationCoordinator.shared.openDirectConversation(
            viewerID: viewer,
            recipient: recipient,
            messages: repo,
            detailCache: DetailPresentationCache(),
            inboxStore: MessagesInboxStore.shared
        )

        XCTAssertFalse(result.wasExisting)
        XCTAssertEqual(repo.createDirectCallCount, 1)
        XCTAssertEqual(repo.conversationRefetchCallCount, 0)
        XCTAssertEqual(result.conversation.participantProfileIDs.count, 2)
        XCTAssertNotNil(
            DirectConversationPairIndex.shared.conversationID(viewerID: viewer, recipientID: peerA)
        )
    }

    func testExistingDirectOutsideLoadedInboxUsesAuthoritativeLookup() async throws {
        let recipient = makeProfile(id: peerA, name: "Peer A")
        let existingID = ConversationID("off-page-dm")
        let repo = TrackingMessageRepository(existingDirectID: existingID)

        let result = try await ConversationCreationCoordinator.shared.openDirectConversation(
            viewerID: viewer,
            recipient: recipient,
            messages: repo,
            detailCache: DetailPresentationCache(),
            inboxStore: MessagesInboxStore.shared
        )

        XCTAssertTrue(result.wasExisting)
        XCTAssertEqual(result.conversation.id, existingID)
        XCTAssertEqual(repo.duplicateLookupCallCount, 1)
        XCTAssertEqual(repo.createDirectCallCount, 0)
        XCTAssertEqual(
            DirectConversationPairIndex.shared.conversationID(viewerID: viewer, recipientID: peerA),
            existingID
        )
    }

    func testReversedRecipientSelectionUsesSamePairKey() {
        let keyA = ConversationCreationSupport.directPairKey(viewer, peerA)
        let keyB = ConversationCreationSupport.directPairKey(peerA, viewer)
        XCTAssertEqual(keyA, keyB)
    }

    func testGroupConversationDoesNotSatisfyDirectLookup() {
        let group = ConversationCreationSupport.buildGroupConversation(
            id: ConversationID("group-with-peer"),
            viewerID: viewer,
            recipients: [makeProfile(id: peerA, name: "Peer A"), makeProfile(id: peerB, name: "Peer B")],
            name: "Team"
        )
        MessagesInboxStore.shared.upsertConversation(group)

        let match = ConversationCreationSupport.findExistingDirectInInbox(
            viewerID: viewer,
            recipientID: peerA,
            inboxStore: MessagesInboxStore.shared
        )
        XCTAssertNil(match)
    }

    func testDuplicateExistingDataDoesNotCreateThirdConversation() async throws {
        let recipient = makeProfile(id: peerA, name: "Peer A")
        let firstID = ConversationID("aaa-duplicate")
        let repo = TrackingMessageRepository(existingDirectID: firstID)

        let result = try await ConversationCreationCoordinator.shared.openDirectConversation(
            viewerID: viewer,
            recipient: recipient,
            messages: repo,
            detailCache: DetailPresentationCache(),
            inboxStore: MessagesInboxStore.shared
        )

        XCTAssertTrue(result.wasExisting)
        XCTAssertEqual(result.conversation.id, firstID)
        XCTAssertEqual(repo.createDirectCallCount, 0)
    }

    func testRapidDoubleTapCreatesOneDirectConversation() async throws {
        let recipient = makeProfile(id: peerA, name: "Peer A")
        let repo = TrackingMessageRepository()

        _ = try await ConversationCreationCoordinator.shared.openDirectConversation(
            viewerID: viewer,
            recipient: recipient,
            messages: repo,
            detailCache: DetailPresentationCache(),
            inboxStore: MessagesInboxStore.shared
        )
        let second = try await ConversationCreationCoordinator.shared.openDirectConversation(
            viewerID: viewer,
            recipient: recipient,
            messages: repo,
            detailCache: DetailPresentationCache(),
            inboxStore: MessagesInboxStore.shared
        )

        XCTAssertTrue(second.wasExisting)
        XCTAssertEqual(repo.createDirectCallCount, 1)
    }

    func testBlockedRecipientProducesRecoverableError() async {
        let recipient = makeProfile(id: peerA, name: "Peer A")
        let repo = TrackingMessageRepository(blockedIDs: [peerA])

        do {
            _ = try await ConversationCreationCoordinator.shared.openDirectConversation(
                viewerID: viewer,
                recipient: recipient,
                messages: repo,
                detailCache: DetailPresentationCache(),
                inboxStore: MessagesInboxStore.shared
            )
            XCTFail("Expected blockedRecipient")
        } catch ConversationCreationCoordinator.CreationError.blockedRecipient {
            XCTAssertEqual(repo.createDirectCallCount, 0)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testCreationSeedsEmptyThreadCacheAndInbox() async throws {
        let recipient = makeProfile(id: peerA, name: "Peer A")
        let repo = TrackingMessageRepository()
        let cache = DetailPresentationCache()

        let result = try await ConversationCreationCoordinator.shared.openDirectConversation(
            viewerID: viewer,
            recipient: recipient,
            messages: repo,
            detailCache: cache,
            inboxStore: MessagesInboxStore.shared
        )

        let key = ConversationThreadSessionStore.cacheKey(
            viewerID: viewer,
            conversationID: result.conversation.id
        )
        let snapshot = ConversationThreadSessionStore.shared.restore(key: key)
        XCTAssertNotNil(snapshot)
        XCTAssertTrue(snapshot?.messages.isEmpty == true)
        XCTAssertEqual(snapshot?.conversation.unreadCount, 0)
        XCTAssertTrue(MessagesInboxStore.shared.conversations.contains { $0.id == result.conversation.id })
    }

    func testGroupCreationRequiresTwoOtherParticipants() async {
        let repo = TrackingMessageRepository()
        do {
            _ = try await ConversationCreationCoordinator.shared.createGroupConversation(
                viewerID: viewer,
                recipients: [makeProfile(id: peerA, name: "A")],
                name: nil,
                messages: repo,
                detailCache: DetailPresentationCache(),
                inboxStore: MessagesInboxStore.shared
            )
            XCTFail("Expected invalidRecipients")
        } catch ConversationCreationCoordinator.CreationError.invalidRecipients {
            XCTAssertEqual(repo.createGroupCallCount, 0)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testGroupCreationBuildsMembershipOnce() async throws {
        let recipients = [
            makeProfile(id: peerA, name: "Alice"),
            makeProfile(id: peerB, name: "Bob"),
        ]
        let repo = TrackingMessageRepository()

        let result = try await ConversationCreationCoordinator.shared.createGroupConversation(
            viewerID: viewer,
            recipients: recipients,
            name: "Team Alpha",
            messages: repo,
            detailCache: DetailPresentationCache(),
            inboxStore: MessagesInboxStore.shared
        )

        XCTAssertTrue(result.conversation.isGroup)
        XCTAssertEqual(result.conversation.title, "Team Alpha")
        XCTAssertEqual(Set(result.conversation.participantProfileIDs), Set([viewer, peerA, peerB]))
        XCTAssertEqual(repo.createGroupCallCount, 1)
    }

    func testFallbackGroupTitleMatchesParticipantNames() {
        let four = [
            makeProfile(id: peerA, name: "Alice"),
            makeProfile(id: peerB, name: "Bob"),
            makeProfile(id: ProfileID("peer-c"), name: "Carol"),
            makeProfile(id: ProfileID("peer-d"), name: "Dan"),
        ]
        XCTAssertEqual(ConversationCreationSupport.fallbackGroupTitle(recipients: four), "Alice, Bob + 2")
    }

    @MainActor
    func testNewChatViewModelGroupSelectionRules() {
        let viewModel = NewChatViewModel(
            messages: TrackingMessageRepository(),
            search: EmptySearchRepository(),
            profiles: EmptyProfileRepository(),
            explore: EmptyExploreRepository(),
            session: StubSession(userID: viewer.rawValue),
            detailCache: DetailPresentationCache()
        )
        viewModel.presentGroupChat()
        XCTAssertEqual(viewModel.mode, .group)
        XCTAssertFalse(viewModel.canCreateGroup)
        viewModel.toggleGroupMember(makeProfile(id: peerA, name: "A"))
        viewModel.toggleGroupMember(makeProfile(id: peerB, name: "B"))
        XCTAssertTrue(viewModel.canCreateGroup)
        viewModel.toggleGroupMember(makeProfile(id: peerA, name: "A"))
        XCTAssertFalse(viewModel.canCreateGroup)
    }

    func testLogoutClearsPendingCreationState() {
        ConversationCreationCoordinator.shared.invalidate()
        ConversationThreadSessionStore.shared.save(
            ConversationThreadSessionStore.Snapshot(
                cacheKey: "viewer|convo",
                conversation: Conversation(
                    id: ConversationID("convo"),
                    participantProfileIDs: [],
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
                ),
                messages: [],
                nextCursor: nil,
                hasMoreMessages: false,
                loadedAt: Date(),
                contentGeneration: 1
            )
        )
        ConversationCreationCoordinator.shared.invalidate()
        ConversationThreadSessionStore.shared.invalidate()
        XCTAssertNil(ConversationThreadSessionStore.shared.restore(key: "viewer|convo"))
    }

    // MARK: - Helpers

    private func makeProfile(id: ProfileID, name: String) -> Profile {
        Profile(
            id: id,
            userID: UserID(id.rawValue),
            username: id.rawValue,
            displayName: name,
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

// MARK: - Test doubles

private final class TrackingMessageRepository: MessageRepository, @unchecked Sendable {
    private(set) var createDirectCallCount = 0
    private(set) var createGroupCallCount = 0
    private(set) var duplicateLookupCallCount = 0
    private(set) var conversationRefetchCallCount = 0
    private var blockedIDs: Set<ProfileID>
    private var existingDirectID: ConversationID?

    init(blockedIDs: Set<ProfileID> = [], existingDirectID: ConversationID? = nil) {
        self.blockedIDs = blockedIDs
        self.existingDirectID = existingDirectID
    }

    func conversations(page: PageRequest) async throws -> ConversationListResult {
        ConversationListResult(items: [], nextCursor: nil, embeddedProfiles: [])
    }

    func conversation(id: ConversationID) async throws -> Conversation {
        conversationRefetchCallCount += 1
        throw AppError.domain(.notFound(entity: "conversation", id: id.rawValue))
    }

    func messages(in conversationID: ConversationID, page: PageRequest) async throws -> CursorPage<Message> {
        CursorPage(items: [], nextCursor: nil)
    }

    func send(_ message: Message) async throws -> Message { message }
    func markRead(conversationID: ConversationID) async throws {}
    func markUnread(conversationID: ConversationID) async throws {}
    func deleteConversation(id: ConversationID) async throws {}

    func createConversation(participantIDs: [ProfileID]) async throws -> Conversation {
        throw AppError.notImplemented(feature: "createConversation")
    }

    func findExistingDirectConversationID(
        viewerID: ProfileID,
        recipientID: ProfileID
    ) async throws -> ConversationID? {
        duplicateLookupCallCount += 1
        return existingDirectID
    }

    func usersHaveActiveBlock(viewerID: ProfileID, otherID: ProfileID) async -> Bool {
        blockedIDs.contains(otherID)
    }

    func createDirectConversation(viewerID: ProfileID, recipient: Profile) async throws -> Conversation {
        createDirectCallCount += 1
        return ConversationCreationSupport.buildDirectConversation(
            id: ConversationID("new-dm"),
            viewerID: viewerID,
            recipient: recipient
        )
    }

    func createGroupConversation(
        viewerID: ProfileID,
        recipients: [Profile],
        name: String?
    ) async throws -> Conversation {
        createGroupCallCount += 1
        return ConversationCreationSupport.buildGroupConversation(
            id: ConversationID("new-group"),
            viewerID: viewerID,
            recipients: recipients,
            name: name
        )
    }
}

private struct EmptySearchRepository: SearchRepository {
    func search(
        query: String,
        kinds: Set<SearchResultKind>,
        page: PageRequest,
        excludingProfileID: ProfileID?
    ) async throws -> CursorPage<SearchResult> {
        CursorPage(items: [], nextCursor: nil)
    }
}

private struct EmptyProfileRepository: ProfileRepository {
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

private struct EmptyExploreRepository: ExploreRepository {
    func discoverableProfiles(page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }
    func socialCounts(for: [ProfileID]) async throws -> ExploreSocialCounts { .empty }
    func tradeActivitySummaries(limit: Int) async throws -> [ProfileID: ExploreTraderRanking.TradeSummary] {
        [:]
    }
    func popularRooms(limit: Int) async throws -> [ExploreRoomSuggestion] { [] }
    func searchRooms(query: String, limit: Int) async throws -> [ExploreRoomSuggestion] { [] }
}

private struct StubSession: SessionProviding {
    let userID: String
    var currentUserID: UserID? { get async { UserID(userID) } }
    var accessToken: String? { get async { "token" } }
}
