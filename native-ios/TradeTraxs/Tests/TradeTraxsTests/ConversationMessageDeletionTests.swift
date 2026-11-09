import XCTest
@testable import TradeTraxs

@MainActor
final class ConversationMessageDeletionTests: XCTestCase {
    override func setUp() async throws {
        MessagesInboxStore.shared.resetForTesting()
    }

    func testMixedSelectionOffersDeleteForMeOnly() async {
        MessagesInboxFixtures.seedStore(MessagesInboxStore.shared)
        let viewModel = await loadedFixtureViewModel()
        let bubbles = fixtureBubbles(from: viewModel)
        let incoming = bubbles.first { !$0.isOutgoing }!
        let outgoing = bubbles.first { $0.isOutgoing && $0.sendState == .sent }!
        viewModel.enterSelectionMode()
        viewModel.toggleMessageSelection(incoming.id)
        viewModel.toggleMessageSelection(outgoing.id)
        XCTAssertEqual(viewModel.selectedEligibleMessages.count, 2)
        XCTAssertFalse(viewModel.offersDeleteForEveryoneInBatch)
    }

    func testAllOwnSentSelectionOffersDeleteForEveryone() async {
        MessagesInboxFixtures.seedStore(MessagesInboxStore.shared)
        let viewModel = await loadedFixtureViewModel()
        var outgoing = fixtureBubbles(from: viewModel).filter { $0.isOutgoing && $0.sendState == .sent }
        if outgoing.count < 2 {
            let extra = Message(
                id: MessageID("out-extra"),
                conversationID: viewModel.conversationID,
                senderProfileID: MessagesInboxFixtures.viewerID,
                kind: .text,
                body: "second",
                attachments: [],
                replyToMessageID: nil,
                createdAt: .now,
                isReadByViewer: true
            )
            viewModel.testing_seedMessages([extra], viewerID: MessagesInboxFixtures.viewerID)
            outgoing = fixtureBubbles(from: viewModel).filter { $0.isOutgoing && $0.sendState == .sent }
        }
        XCTAssertGreaterThanOrEqual(outgoing.count, 2)
        viewModel.enterSelectionMode()
        viewModel.toggleMessageSelection(outgoing[0].id)
        viewModel.toggleMessageSelection(outgoing[1].id)
        XCTAssertTrue(viewModel.offersDeleteForEveryoneInBatch)
    }

    func testDeleteForMeRemovesIncomingFromTimeline() async {
        let repo = RecordingDeleteMessageRepository()
        let conversationID = ConversationID("conv-delete-me")
        let viewerID = ProfileID("viewer-1")
        let viewModel = ConversationViewModel(
            conversationID: conversationID,
            messages: repo,
            profiles: DeletionTestProfileRepository(),
            session: DeletionTestSession(userID: viewerID.rawValue),
            uploadService: DeletionTestUploadService(),
            objectStorage: DeletionTestObjectStorage(),
            detailCache: DetailPresentationCache(),
            inboxStore: .shared
        )
        let incoming = Message(
            id: MessageID("peer-msg"),
            conversationID: conversationID,
            senderProfileID: ProfileID("peer"),
            kind: .text,
            body: "hello",
            attachments: [],
            replyToMessageID: nil,
            createdAt: .now,
            isReadByViewer: true
        )
        viewModel.testing_seedMessages([incoming], viewerID: viewerID)
        guard let bubble = viewModel.bubbleItem(for: incoming.id) else {
            return XCTFail("Expected bubble")
        }
        await viewModel.deleteMessageForMe(bubble)
        XCTAssertFalse(viewModel.messages.contains { $0.id == incoming.id })
        XCTAssertEqual(repo.deleteForMeCallCount, 1)
        XCTAssertEqual(repo.deleteForEveryoneCallCount, 0)
    }

    private func loadedFixtureViewModel() async -> ConversationViewModel {
        let viewModel = ConversationViewModel(
            conversationID: ConversationID("dev-dm-ada"),
            messages: DeletionTestMessageRepository(),
            profiles: DeletionTestProfileRepository(),
            session: DeletionTestSession(userID: MessagesInboxFixtures.viewerID.rawValue),
            uploadService: DeletionTestUploadService(),
            objectStorage: DeletionTestObjectStorage(),
            detailCache: DetailPresentationCache(),
            inboxStore: .shared
        )
        viewModel.loadIfNeeded()
        try? await Task.sleep(nanoseconds: 80_000_000)
        return viewModel
    }

    private func fixtureBubbles(from viewModel: ConversationViewModel) -> [ConversationBubbleItem] {
        viewModel.timeline.compactMap { item in
            guard case .message(let bubble) = item else { return nil }
            return bubble
        }
    }
}

private final class RecordingDeleteMessageRepository: MessageRepository, @unchecked Sendable {
    private(set) var deleteForMeCallCount = 0
    private(set) var deleteForEveryoneCallCount = 0

    func conversations(page: PageRequest) async throws -> ConversationListResult {
        ConversationListResult(items: [], nextCursor: nil, embeddedProfiles: [])
    }

    func conversation(id: ConversationID) async throws -> Conversation {
        Conversation(
            id: id,
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
        )
    }

    func messages(in conversationID: ConversationID, page: PageRequest) async throws -> CursorPage<Message> {
        CursorPage(items: [], nextCursor: nil)
    }

    func send(_ message: Message) async throws -> Message { message }
    func markRead(conversationID: ConversationID) async throws {}
    func markUnread(conversationID: ConversationID) async throws {}
    func createConversation(participantIDs: [ProfileID]) async throws -> Conversation {
        throw AppError.notImplemented(feature: "create")
    }
    func findExistingDirectConversationID(viewerID: ProfileID, recipientID: ProfileID) async throws -> ConversationID? {
        nil
    }
    func usersHaveActiveBlock(viewerID: ProfileID, otherID: ProfileID) async -> Bool { false }
    func createDirectConversation(viewerID: ProfileID, recipient: Profile) async throws -> Conversation {
        throw AppError.notImplemented(feature: "createDirect")
    }
    func createGroupConversation(
        viewerID: ProfileID,
        recipients: [Profile],
        name: String?
    ) async throws -> Conversation {
        throw AppError.notImplemented(feature: "createGroup")
    }
    func deleteConversation(id: ConversationID) async throws {}
    func deleteMessageForEveryone(_ messageID: MessageID, in conversationID: ConversationID) async throws {
        deleteForEveryoneCallCount += 1
    }
    func deleteMessageForMe(_ messageID: MessageID, in conversationID: ConversationID) async throws {
        deleteForMeCallCount += 1
    }
    func setConversationNotificationsEnabled(conversationID: ConversationID, enabled: Bool) async throws {}
}

private struct DeletionTestSession: SessionProviding {
    let userID: String?
    var currentUserID: UserID? {
        get async {
            guard let userID else { return nil }
            return UserID(userID)
        }
    }
    var accessToken: String? { get async { userID == nil ? nil : "test-token" } }
}

private struct DeletionTestProfileRepository: ProfileRepository {
    func currentUser() async throws -> User {
        User(id: UserID(MessagesInboxFixtures.viewerID.rawValue), email: nil, createdAt: .now)
    }

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
    func wallPost(id: PostID) async throws -> Post { throw AppError.unknown(message: "not found") }
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

private struct DeletionTestUploadService: UploadService {
    func upload(_ request: UploadRequest) async throws -> MediaReference {
        MediaReference(id: request.path, kind: .image, altText: nil)
    }
}

private struct DeletionTestObjectStorage: ObjectStorageProviding {
    func upload(bucket: String, path: String, data: Data, contentType: String, cacheControl: String? = nil) async throws -> String {
        path
    }
    func download(bucket: String, path: String) async throws -> Data { Data() }
    func delete(bucket: String, path: String) async throws {}
    func publicURL(bucket: String, path: String) -> URL? {
        URL(string: "https://example.com/\(bucket)/\(path)")
    }
}

private struct DeletionTestMessageRepository: MessageRepository {
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
        throw AppError.notImplemented(feature: "createConversation")
    }
    func findExistingDirectConversationID(viewerID: ProfileID, recipientID: ProfileID) async throws -> ConversationID? {
        nil
    }
    func usersHaveActiveBlock(viewerID: ProfileID, otherID: ProfileID) async -> Bool { false }
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
    func deleteMessageForMe(_ messageID: MessageID, in conversationID: ConversationID) async throws {}
    func setConversationNotificationsEnabled(conversationID: ConversationID, enabled: Bool) async throws {}
}
