import XCTest
@testable import TradeTraxs

@MainActor
final class ConversationExperienceTests: XCTestCase {
    override func setUp() async throws {
        MessagesInboxStore.shared.resetForTesting()
    }

    func testDaySeparatorLabels() {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()
        XCTAssertEqual(ConversationThreadSupport.daySeparator(today, calendar: calendar), "Today")
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        XCTAssertEqual(ConversationThreadSupport.daySeparator(yesterday, calendar: calendar), "Yesterday")
    }

    func testLocalConversationLoadsFixtureTimeline() async {
        MessagesInboxFixtures.seedStore(MessagesInboxStore.shared)
        let cache = DetailPresentationCache()
        for profile in MessagesInboxFixtures.profiles(
            for: MessagesInboxStore.shared.conversations,
            viewerID: MessagesInboxFixtures.viewerID
        ) {
            cache.seed(profile)
        }

        let viewModel = makeViewModel(
            conversationID: ConversationID("dev-dm-ada"),
            sessionUserID: MessagesInboxFixtures.viewerID.rawValue,
            detailCache: cache
        )
        viewModel.loadIfNeeded()
        try? await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertFalse(viewModel.messages.isEmpty)
        XCTAssertTrue(viewModel.timeline.contains { item in
            if case .daySeparator = item { return true }
            return false
        })
        XCTAssertTrue(viewModel.timeline.contains { item in
            if case .message(let bubble) = item { return bubble.isOutgoing || !bubble.isOutgoing }
            return false
        })
        XCTAssertEqual(viewModel.title, "Ada Lovelace")
        let outgoing = viewModel.timeline.compactMap { item -> ConversationBubbleItem? in
            if case .message(let bubble) = item { return bubble }
            return nil
        }
        XCTAssertTrue(outgoing.contains(where: \.isOutgoing))
        XCTAssertTrue(outgoing.contains(where: { !$0.isOutgoing }))
    }

    func testOptimisticSendAppendsOutgoingMessageAndUpdatesInbox() async {
        MessagesInboxFixtures.seedStore(MessagesInboxStore.shared)
        let cache = DetailPresentationCache()
        let viewModel = makeViewModel(
            conversationID: ConversationID("dev-dm-ada"),
            sessionUserID: MessagesInboxFixtures.viewerID.rawValue,
            detailCache: cache
        )
        viewModel.loadIfNeeded()
        try? await Task.sleep(nanoseconds: 80_000_000)

        let before = viewModel.messages.count
        viewModel.draft = "Locked in for London open."
        await viewModel.sendText()

        XCTAssertEqual(viewModel.messages.count, before + 1)
        XCTAssertEqual(viewModel.messages.last?.body, "Locked in for London open.")
        XCTAssertEqual(viewModel.messages.last?.senderProfileID, MessagesInboxFixtures.viewerID)
        XCTAssertEqual(viewModel.draft, "")
        XCTAssertEqual(
            MessagesInboxStore.shared.conversations.first { $0.id == ConversationID("dev-dm-ada") }?
                .lastMessagePreview,
            "Locked in for London open."
        )
    }

    func testTimelineGroupsOutgoingWithoutAvatar() async {
        MessagesInboxFixtures.seedStore(MessagesInboxStore.shared)
        let viewModel = makeViewModel(
            conversationID: ConversationID("dev-dm-ada"),
            sessionUserID: MessagesInboxFixtures.viewerID.rawValue
        )
        viewModel.loadIfNeeded()
        try? await Task.sleep(nanoseconds: 80_000_000)

        let bubbles = viewModel.timeline.compactMap { item -> ConversationBubbleItem? in
            if case .message(let bubble) = item { return bubble }
            return nil
        }
        for bubble in bubbles where bubble.isOutgoing {
            XCTAssertFalse(bubble.showsAvatar)
        }
        XCTAssertTrue(bubbles.contains { !$0.isOutgoing && $0.showsAvatar })
    }

    func testOpeningConversationClearsInboxUnread() async {
        MessagesInboxFixtures.seedStore(MessagesInboxStore.shared)
        let id = ConversationID("dev-dm-ada")
        let before = MessagesInboxStore.shared.conversations.first { $0.id == id }!
        XCTAssertEqual(MessagesInboxStore.shared.unreadCount(for: before), 2)

        let viewModel = makeViewModel(
            conversationID: id,
            sessionUserID: MessagesInboxFixtures.viewerID.rawValue
        )
        viewModel.loadIfNeeded()
        try? await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(viewModel.phase, .loaded)
        let after = MessagesInboxStore.shared.conversations.first { $0.id == id }!
        XCTAssertEqual(MessagesInboxStore.shared.unreadCount(for: after), 0)
    }

    // MARK: - Helpers

    private func makeViewModel(
        conversationID: ConversationID,
        sessionUserID: String,
        detailCache: DetailPresentationCache? = nil
    ) -> ConversationViewModel {
        ConversationViewModel(
            conversationID: conversationID,
            messages: ConversationStubMessageRepository(),
            profiles: ConversationStubProfileRepository(),
            session: ConversationStubSession(userID: sessionUserID),
            uploadService: ConversationStubUploadService(),
            objectStorage: ConversationStubObjectStorage(),
            detailCache: detailCache ?? DetailPresentationCache(),
            inboxStore: .shared
        )
    }
}

// MARK: - Stubs

private struct ConversationStubSession: SessionProviding {
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

private struct ConversationStubMessageRepository: MessageRepository {
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

    func send(_ message: Message) async throws -> Message {
        Message(
            id: MessageID(UUID().uuidString),
            conversationID: message.conversationID,
            senderProfileID: message.senderProfileID,
            kind: message.kind,
            body: message.body,
            attachments: message.attachments,
            replyToMessageID: message.replyToMessageID,
            createdAt: message.createdAt,
            isReadByViewer: true
        )
    }

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

    func deleteConversation(id: ConversationID) async throws {}
}

private struct ConversationStubProfileRepository: ProfileRepository {
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

private struct ConversationStubUploadService: UploadService {
    func upload(_ request: UploadRequest) async throws -> MediaReference {
        MediaReference(id: request.path, kind: .image, altText: nil)
    }
}

private struct ConversationStubObjectStorage: ObjectStorageProviding {
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
