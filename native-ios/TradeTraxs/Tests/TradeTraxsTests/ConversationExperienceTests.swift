import XCTest
@testable import TradeTraxs

@MainActor
final class ConversationExperienceTests: XCTestCase {
    override func setUp() async throws {
        MessagesInboxStore.shared.resetForTesting()
        BackendV2FeatureFlags.resetFlagsForTests()
    }

    func testDaySeparatorLabels() {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()
        XCTAssertEqual(ConversationThreadSupport.daySeparator(today, calendar: calendar), "Today")
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        XCTAssertEqual(ConversationThreadSupport.daySeparator(yesterday, calendar: calendar), "Yesterday")
    }

    func testMessageTextLayoutWidthsIncreaseWithContentLength() {
        let maxWidth: CGFloat = 300
        let yo = ConversationMessageTextLayout.referenceTextWidth("yo", maxWidth: maxWidth)
        let hello = ConversationMessageTextLayout.referenceTextWidth("hello there", maxWidth: maxWidth)
        let medium = ConversationMessageTextLayout.referenceTextWidth(
            "A medium sentence for bubble sizing.",
            maxWidth: maxWidth
        )
        let long = ConversationMessageTextLayout.referenceTextWidth(
            String(repeating: "word ", count: 40),
            maxWidth: maxWidth
        )

        XCTAssertLessThan(yo, hello)
        XCTAssertLessThan(hello, medium)
        XCTAssertLessThan(yo, maxWidth / 2)
        XCTAssertGreaterThan(long, medium)
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

    func testCanDeleteMessageOnlyOwnSentMessages() async {
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
        let incoming = bubbles.first { !$0.isOutgoing }!
        let outgoing = bubbles.first { $0.isOutgoing && $0.sendState == .sent }!

        XCTAssertFalse(viewModel.canDeleteMessage(incoming))
        XCTAssertTrue(viewModel.canDeleteMessage(outgoing))
    }

    func testDeleteMessageRemovesOutgoingFromLocalTimeline() async {
        MessagesInboxFixtures.seedStore(MessagesInboxStore.shared)
        let viewModel = makeViewModel(
            conversationID: ConversationID("dev-dm-ada"),
            sessionUserID: MessagesInboxFixtures.viewerID.rawValue
        )
        viewModel.loadIfNeeded()
        try? await Task.sleep(nanoseconds: 80_000_000)

        guard let outgoing = viewModel.timeline.compactMap({ item -> ConversationBubbleItem? in
            if case .message(let bubble) = item, bubble.isOutgoing, bubble.sendState == .sent {
                return bubble
            }
            return nil
        }).first else {
            XCTFail("Expected an outgoing sent message")
            return
        }

        let messageID = outgoing.id
        let countBefore = viewModel.messages.count
        await viewModel.deleteMessage(outgoing)

        XCTAssertFalse(viewModel.messages.contains { $0.id == messageID })
        XCTAssertEqual(viewModel.messages.count, countBefore - 1)
        XCTAssertNil(viewModel.deleteErrorMessage)
    }

    func testLoadOlderIfNeededBlockedUntilInitialScrollConfirmed() async {
        MessagesInboxFixtures.seedStore(MessagesInboxStore.shared)
        let viewModel = makeViewModel(
            conversationID: ConversationID("dev-dm-ada"),
            sessionUserID: MessagesInboxFixtures.viewerID.rawValue
        )
        viewModel.loadIfNeeded()
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertFalse(viewModel.messages.isEmpty)

        await viewModel.loadOlderIfNeeded()

        XCTAssertEqual(viewModel.initialScrollPhase, .pending)
    }

    func testSettlingPhaseBlocksPaginationUntilConfirmed() async {
        MessagesInboxFixtures.seedStore(MessagesInboxStore.shared)
        let viewModel = makeViewModel(
            conversationID: ConversationID("dev-dm-ada"),
            sessionUserID: MessagesInboxFixtures.viewerID.rawValue
        )
        viewModel.loadIfNeeded()
        try? await Task.sleep(nanoseconds: 80_000_000)
        viewModel.beginInitialScrollPositioning()
        viewModel.beginInitialScrollSettling()

        XCTAssertEqual(viewModel.initialScrollPhase, .settling)
        XCTAssertFalse(viewModel.isInitialScrollConfirmed)

        viewModel.beginPagination(anchorMessageID: MessageID("any"))
        XCTAssertEqual(viewModel.scrollCoordinator.mode, .initialPositionPending)
    }

    func testDeleteMessageRestoresOnRepositoryFailure() async {
        BackendV2FeatureFlags.setFlagForTests(.messageThreads, enabled: false)

        let viewerID = ProfileID("user-viewer-1")
        let peerID = ProfileID("user-peer-1")
        let conversationID = ConversationID("remote-convo-1")
        let repo = FailingDeleteMessageRepository(
            viewerID: viewerID,
            peerID: peerID,
            conversationID: conversationID
        )

        MessagesInboxStore.shared.upsertConversation(
            Conversation(
                id: conversationID,
                participantProfileIDs: [viewerID, peerID],
                title: "Peer",
                peerUsername: "peer",
                avatar: nil,
                isGroup: false,
                isPinned: false,
                lastMessagePreview: "Yes — clean displacement off the FVG.",
                lastMessageAt: .now,
                unreadCount: 0,
                isMuted: false,
                updatedAt: .now
            )
        )

        let viewModel = ConversationViewModel(
            conversationID: conversationID,
            messages: repo,
            profiles: ConversationStubProfileRepository(),
            session: ConversationStubSession(userID: viewerID.rawValue),
            uploadService: ConversationStubUploadService(),
            objectStorage: ConversationStubObjectStorage(),
            detailCache: DetailPresentationCache(),
            inboxStore: .shared
        )
        viewModel.loadIfNeeded()
        try? await Task.sleep(nanoseconds: 100_000_000)

        guard let outgoing = viewModel.timeline.compactMap({ item -> ConversationBubbleItem? in
            if case .message(let bubble) = item, bubble.isOutgoing, bubble.sendState == .sent {
                return bubble
            }
            return nil
        }).first else {
            XCTFail("Expected an outgoing sent message")
            return
        }

        let messageID = outgoing.id
        let countBefore = viewModel.messages.count
        await viewModel.deleteMessage(outgoing)

        XCTAssertTrue(viewModel.messages.contains { $0.id == messageID })
        XCTAssertEqual(viewModel.messages.count, countBefore)
        XCTAssertNotNil(viewModel.deleteErrorMessage)
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

    func deleteMessageForEveryone(_ messageID: MessageID, in conversationID: ConversationID) async throws {}

    func setConversationNotificationsEnabled(
        conversationID: ConversationID,
        enabled: Bool
    ) async throws {}
}

private struct FailingDeleteMessageRepository: MessageRepository {
    let viewerID: ProfileID
    let peerID: ProfileID
    let conversationID: ConversationID

    func conversations(page: PageRequest) async throws -> ConversationListResult {
        ConversationListResult(items: [], nextCursor: nil, embeddedProfiles: [])
    }

    func conversation(id: ConversationID) async throws -> Conversation {
        Conversation(
            id: conversationID,
            participantProfileIDs: [viewerID, peerID],
            title: "Peer",
            peerUsername: "peer",
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
        CursorPage(
            items: ConversationThreadFixtures.messages(
                conversationID: self.conversationID,
                viewerID: viewerID,
                peerID: peerID
            ),
            nextCursor: nil
        )
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

    func deleteMessageForEveryone(_ messageID: MessageID, in conversationID: ConversationID) async throws {
        throw AppError.transport(.connectivity)
    }

    func setConversationNotificationsEnabled(
        conversationID: ConversationID,
        enabled: Bool
    ) async throws {}
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
