import XCTest
@testable import TradeTraxs

// MARK: - Conversation thread contract

@MainActor
final class ConversationThreadBootstrapN3Tests: XCTestCase {
    override func setUp() async throws {
        BackendV2FeatureFlags.resetFlagsForTests()
        ConversationThreadSessionStore.shared.invalidate()
        MessagesInboxStore.shared.resetForTesting()
        await BackendV2SingleFlight.shared.clear()
        await BackendV2RpcAvailability.shared.clear()
    }

    override func tearDown() {
        BackendV2FeatureFlags.resetFlagsForTests()
        ConversationThreadSessionStore.shared.invalidate()
        MessagesInboxStore.shared.resetForTesting()
        Task {
            await BackendV2SingleFlight.shared.clear()
            await BackendV2RpcAvailability.shared.clear()
        }
        super.tearDown()
    }

    func testDirectOpenFixtureDecodesAndValidates() throws {
        let value: ConversationThreadBootstrapV1 = try decode(
            ConversationThreadContractFixtures.directOpen
        )
        try value.validateContractVersion()
        try value.validateRequiredFields()
        XCTAssertEqual(value.data.conversation.id, "convo-1")
        XCTAssertEqual(value.data.messages.count, 1)
        XCTAssertTrue(value.data.mark_read.applied.value ?? false)
    }

    func testPaginationFixtureHasCursorAndNoMarkRead() throws {
        let value: ConversationThreadBootstrapV1 = try decode(
            ConversationThreadContractFixtures.groupPagination
        )
        XCTAssertFalse(value.data.mark_read.applied.value ?? true)
        XCTAssertEqual(value.data.next_message_cursor, "2026-08-20T10:00:00.000Z|msg-old")
        XCTAssertTrue(value.data.has_more_messages.value ?? false)
    }

    func testEmptyConversationDecodes() throws {
        let value: ConversationThreadBootstrapV1 = try decode(
            ConversationThreadContractFixtures.emptyConversation
        )
        XCTAssertTrue(value.data.messages.isEmpty)
        try value.validateRequiredFields()
    }

    func testUnknownAdditiveFieldIgnored() throws {
        let json = ConversationThreadContractFixtures.directOpen.replacingOccurrences(
            of: "\"page_meta\"",
            with: "\"future_field\":{\"enabled\":true},\"page_meta\""
        )
        XCTAssertNoThrow(try decode(json) as ConversationThreadBootstrapV1)
    }

    func testMissingMessagesKeyFailsDecode() {
        let json = """
        {"meta":{"contract_version":"v1","server_time":"t","viewer_id":"v1"},"data":{"conversation":{"id":"c1","is_group":false,"is_pinned":false},"membership":{"is_participant":true},"participants":[],"notifications_enabled":true,"has_more_messages":false,"unread_count":0,"mark_read":{"applied":false},"notifications_marked_read":0,"page_meta":{"limit":50,"returned":0,"has_more":false}}}
        """
        XCTAssertThrowsError(try decode(json) as ConversationThreadBootstrapV1)
    }

    func testMissingConversationIdFailsValidation() throws {
        let json = ConversationThreadContractFixtures.directOpen.replacingOccurrences(
            of: "\"conversation\":{\"id\":\"convo-1\"",
            with: "\"conversation\":{\"id\":\"\""
        )
        let value: ConversationThreadBootstrapV1 = try decode(json)
        XCTAssertThrowsError(try value.validateRequiredFields()) { error in
            XCTAssertEqual(error as? ConversationThreadContractError, .missingField("conversation.id"))
        }
    }

    @MainActor
    func testApplierMapsMessagesAndConversation() throws {
        let bootstrap: ConversationThreadBootstrapV1 = try decode(
            ConversationThreadContractFixtures.directOpen
        )
        let viewer = ProfileID("viewer-1")
        let applied = try ConversationThreadBootstrapApplier.apply(
            bootstrap,
            conversationID: ConversationID("convo-1"),
            viewerID: viewer,
            detailCache: DetailPresentationCache()
        )
        XCTAssertEqual(applied.conversation.id.rawValue, "convo-1")
        XCTAssertEqual(applied.messages.count, 1)
        XCTAssertEqual(applied.messages.first?.body, "Hello")
        XCTAssertTrue(applied.markReadApplied)
    }

    @MainActor
    func testSoftStaleRevalidationDoesNotMarkRead() async throws {
        BackendV2FeatureFlags.setFlagForTests(.messageThreads, enabled: true)
        let viewer = ProfileID("viewer-1")
        let convo = ConversationID("convo-1")
        let key = ConversationThreadSessionStore.cacheKey(viewerID: viewer, conversationID: convo)
        ConversationThreadSessionStore.shared.save(
            ConversationThreadSessionStore.Snapshot(
                cacheKey: key,
                conversation: Conversation(
                    id: convo,
                    participantProfileIDs: [viewer],
                    title: nil,
                    peerUsername: "peer",
                    avatar: nil,
                    isGroup: false,
                    isPinned: false,
                    lastMessagePreview: nil,
                    lastMessageAt: nil,
                    unreadCount: 0,
                    isMuted: false,
                    updatedAt: .now.addingTimeInterval(-7200)
                ),
                messages: [],
                nextCursor: nil,
                hasMoreMessages: false,
                loadedAt: Date().addingTimeInterval(-7200),
                contentGeneration: 0
            )
        )

        let rpc = CapturingThreadRPCClient(json: ConversationThreadContractFixtures.directOpen)
        _ = try await ConversationThreadBootstrapLoader.load(
            viewerID: viewer,
            conversationID: convo,
            cursor: nil,
            markRead: false,
            intent: .cacheRevalidation,
            rpc: rpc,
            detailCache: DetailPresentationCache(),
            inboxStore: MessagesInboxStore.shared,
            loadGeneration: 1,
            currentGeneration: { 1 },
            forceNetwork: true
        )
        XCTAssertEqual(rpc.lastMarkRead, false)
    }

    @MainActor
    func testColdOpenUsesMarkReadTrueInRPCArguments() async throws {
        BackendV2FeatureFlags.setFlagForTests(.messageThreads, enabled: true)
        let rpc = CapturingThreadRPCClient(json: ConversationThreadContractFixtures.directOpen)
        let viewer = ProfileID("viewer-1")
        _ = try await ConversationThreadBootstrapLoader.load(
            viewerID: viewer,
            conversationID: ConversationID("convo-1"),
            cursor: nil,
            markRead: true,
            intent: .coldOpen,
            rpc: rpc,
            detailCache: DetailPresentationCache(),
            inboxStore: MessagesInboxStore.shared,
            loadGeneration: 1,
            currentGeneration: { 1 },
            forceNetwork: true
        )
        XCTAssertEqual(rpc.lastMarkRead, true)
        XCTAssertEqual(rpc.callCount, 1)
    }

    @MainActor
    func testPaginationUsesMarkReadFalse() async throws {
        BackendV2FeatureFlags.setFlagForTests(.messageThreads, enabled: true)
        let rpc = CapturingThreadRPCClient(json: ConversationThreadContractFixtures.groupPagination)
        let viewer = ProfileID("viewer-1")
        _ = try await ConversationThreadBootstrapLoader.load(
            viewerID: viewer,
            conversationID: ConversationID("group-1"),
            cursor: "2026-08-20T10:00:00.000Z|msg-old",
            markRead: false,
            intent: .pagination,
            rpc: rpc,
            detailCache: DetailPresentationCache(),
            inboxStore: MessagesInboxStore.shared,
            loadGeneration: 1,
            currentGeneration: { 1 },
            forceNetwork: true
        )
        XCTAssertEqual(rpc.lastMarkRead, false)
    }

    @MainActor
    func testCacheHitSkipsSecondNetworkCall() async throws {
        BackendV2FeatureFlags.setFlagForTests(.messageThreads, enabled: true)
        let viewer = ProfileID("viewer-1")
        let conversationID = ConversationID("convo-1")
        let cacheKey = ConversationThreadSessionStore.cacheKey(
            viewerID: viewer,
            conversationID: conversationID
        )
        ConversationThreadSessionStore.shared.save(
            ConversationThreadSessionStore.Snapshot(
                cacheKey: cacheKey,
                conversation: Conversation(
                    id: conversationID,
                    participantProfileIDs: [viewer],
                    title: nil,
                    peerUsername: "peer",
                    avatar: nil,
                    isGroup: false,
                    isPinned: false,
                    lastMessagePreview: "Hello",
                    lastMessageAt: .now,
                    unreadCount: 0,
                    isMuted: false,
                    updatedAt: .now
                ),
                messages: [],
                nextCursor: nil,
                hasMoreMessages: false,
                loadedAt: Date(),
                contentGeneration: 0
            )
        )
        let rpc = CapturingThreadRPCClient(json: ConversationThreadContractFixtures.directOpen)
        let result = try await ConversationThreadBootstrapLoader.load(
            viewerID: viewer,
            conversationID: conversationID,
            cursor: nil,
            markRead: false,
            intent: .cacheRevalidation,
            rpc: rpc,
            detailCache: DetailPresentationCache(),
            inboxStore: MessagesInboxStore.shared,
            loadGeneration: 1,
            currentGeneration: { 1 },
            forceNetwork: false
        )
        XCTAssertTrue(result.cacheHit)
        XCTAssertEqual(rpc.callCount, 0)
    }

    @MainActor
    func testMissingRpcMarksUnavailableAndThrows() async {
        BackendV2FeatureFlags.setFlagForTests(.messageThreads, enabled: true)
        let rpc = FailingThreadRPCClient(errorText: "PGRST202 could not find rpc_v1_conversation_thread_bootstrap")
        let viewer = ProfileID("viewer-1")
        do {
            _ = try await ConversationThreadBootstrapLoader.load(
                viewerID: viewer,
                conversationID: ConversationID("convo-1"),
                cursor: nil,
                markRead: true,
                intent: .coldOpen,
                rpc: rpc,
                detailCache: DetailPresentationCache(),
                inboxStore: MessagesInboxStore.shared,
                loadGeneration: 1,
                currentGeneration: { 1 },
                forceNetwork: true
            )
            XCTFail("Expected rpcUnavailable")
        } catch ConversationThreadBootstrapLoader.LoaderError.rpcUnavailable {
            let unavailable = await BackendV2RpcAvailability.shared.isUnavailable(
                rpcName: BackendV2Versioning.RPCName.conversationThread.rawValue,
                viewerID: viewer.rawValue
            )
            XCTAssertTrue(unavailable)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    @MainActor
    func testStaleGenerationRejected() async throws {
        BackendV2FeatureFlags.setFlagForTests(.messageThreads, enabled: true)
        let rpc = CapturingThreadRPCClient(json: ConversationThreadContractFixtures.directOpen)
        let viewer = ProfileID("viewer-1")
        do {
            _ = try await ConversationThreadBootstrapLoader.load(
                viewerID: viewer,
                conversationID: ConversationID("convo-1"),
                cursor: nil,
                markRead: true,
                intent: .coldOpen,
                rpc: rpc,
                detailCache: DetailPresentationCache(),
                inboxStore: MessagesInboxStore.shared,
                loadGeneration: 1,
                currentGeneration: { 2 },
                forceNetwork: true
            )
            XCTFail("Expected staleResponse")
        } catch ConversationThreadBootstrapLoader.LoaderError.staleResponse {
            XCTAssertEqual(rpc.callCount, 1)
        }
    }

    @MainActor
    func testLogoutClearsThreadCache() {
        let viewer = ProfileID("viewer-1")
        let key = ConversationThreadSessionStore.cacheKey(
            viewerID: viewer,
            conversationID: ConversationID("convo-1")
        )
        ConversationThreadSessionStore.shared.save(
            ConversationThreadSessionStore.Snapshot(
                cacheKey: key,
                conversation: Conversation(
                    id: ConversationID("convo-1"),
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
                contentGeneration: 0
            )
        )
        ConversationThreadSessionStore.shared.invalidate()
        XCTAssertNil(ConversationThreadSessionStore.shared.restore(key: key))
    }

    @MainActor
    func testCoordinatorSkipsMarkReadWhenV2ThreadsFlagOn() async {
        BackendV2FeatureFlags.setFlagForTests(.messageThreads, enabled: true)
        let repo = CountingMessageRepository()
        InboxMarkReadCoordinator.shared.configure(
            messages: repo,
            rooms: N3StubRoomRepository(),
            session: N3StubSession(userID: "viewer-1")
        )
        InboxMarkReadCoordinator.shared.prepareOpenConversation(ConversationID("convo-1"))
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(repo.markReadCallCount, 0)
    }

    @MainActor
    func testCoordinatorMarksReadWhenLegacyPath() async {
        BackendV2FeatureFlags.resetFlagsForTests()
        BackendV2FeatureFlags.setFlagForTests(.messageThreads, enabled: false)
        let repo = CountingMessageRepository()
        InboxMarkReadCoordinator.shared.configure(
            messages: repo,
            rooms: N3StubRoomRepository(),
            session: N3StubSession(userID: "11111111-1111-1111-1111-111111111111")
        )
        InboxMarkReadCoordinator.shared.prepareOpenConversation(
            ConversationID("c1111111-1111-1111-1111-111111111111")
        )
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(repo.markReadCallCount, 1)
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}

// MARK: - Loader test double (shared with reload persistence tests)

final class CapturingThreadRPCClient: RPCClient, @unchecked Sendable {
    let json: String
    private(set) var callCount = 0
    private(set) var lastMarkRead: Bool?

    init(json: String) {
        self.json = json
    }

    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        callCount += 1
        return Data(json.utf8)
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        callCount += 1
        if let args = try? JSONDecoder().decode(MarkReadProbe.self, from: jsonBody) {
            lastMarkRead = args.p_mark_read
        }
        return Data(json.utf8)
    }

    private struct MarkReadProbe: Decodable {
        var p_mark_read: Bool
    }
}

enum ConversationThreadContractFixtures {
    static let directOpen = """
    {"meta":{"contract_version":"v1","server_time":"2026-08-21T12:00:00.000Z","viewer_id":"viewer-1"},"data":{"conversation":{"id":"convo-1","is_group":false,"name":null,"avatar_url":null,"is_pinned":false},"membership":{"is_participant":true},"participants":[{"user_id":"viewer-1","profiles":{"id":"viewer-1","username":"me","avatar_url":null}},{"user_id":"peer-1","profiles":{"id":"peer-1","username":"peer","avatar_url":null}}],"notifications_enabled":true,"block_status":{"other_user_id":"peer-1","blocked_by_me":false,"blocked_by_other":false},"messages":[{"id":"msg-1","conversation_id":"convo-1","sender_id":"peer-1","sender_anonymized":false,"content":"Hello","created_at":"2026-08-21T11:59:00.000Z","seen_by":[],"type":"text","trade_id":null,"post_id":null,"profile_post_id":null,"achievement_post_id":null,"reel_id":null,"parent_message_id":null,"deleted_for_everyone":false,"image_url":null,"is_system":false,"profiles":{"username":"peer","avatar_url":null}}],"has_more_messages":false,"next_message_cursor":null,"unread_count":0,"mark_read":{"applied":true},"notifications_marked_read":1,"page_meta":{"limit":50,"returned":1,"has_more":false}}}
    """

    static let groupPagination = """
    {"meta":{"contract_version":"v1","server_time":"2026-08-21T12:00:00.000Z","viewer_id":"viewer-1"},"data":{"conversation":{"id":"group-1","is_group":true,"name":"Team","avatar_url":null,"is_pinned":true},"membership":{"is_participant":true},"participants":[],"notifications_enabled":false,"block_status":null,"messages":[],"has_more_messages":true,"next_message_cursor":"2026-08-20T10:00:00.000Z|msg-old","unread_count":3,"mark_read":{"applied":false},"notifications_marked_read":0,"page_meta":{"limit":50,"returned":0,"has_more":true}}}
    """

    static let emptyConversation = """
    {"meta":{"contract_version":"v1","server_time":"2026-08-21T12:00:00.000Z","viewer_id":"viewer-1"},"data":{"conversation":{"id":"convo-empty","is_group":false,"name":null,"avatar_url":null,"is_pinned":false},"membership":{"is_participant":true},"participants":[],"notifications_enabled":true,"block_status":null,"messages":[],"has_more_messages":false,"next_message_cursor":null,"unread_count":0,"mark_read":{"applied":false},"notifications_marked_read":0,"page_meta":{"limit":50,"returned":0,"has_more":false}}}
    """
}

// MARK: - Feed bootstrap contract

@MainActor
final class FeedBootstrapN3Tests: XCTestCase {
    override func tearDown() {
        BackendV2FeatureFlags.resetFlagsForTests()
        FeedSessionStore.shared.invalidate()
        Task {
            await BackendV2SingleFlight.shared.clear()
            await BackendV2RpcAvailability.shared.clear()
        }
        super.tearDown()
    }

    func testFollowingAllFixtureDecodesWithEngagement() throws {
        let value: FeedBootstrapV1 = try decode(BackendV2ContractFixtures.feed)
        try value.validateContractVersion()
        XCTAssertEqual(value.data.scope, "following")
        XCTAssertEqual(value.data.engagement["p1"]?.like_count, 3)
    }

    func testGlobalTradesVariantDecodes() throws {
        let value: FeedBootstrapV1 = try decode(FeedBootstrapN3Fixtures.globalTrades)
        XCTAssertEqual(value.data.scope, "global")
        XCTAssertEqual(value.data.content_filter, "trades")
    }

    func testMissingRequiredItemsFailsDecode() {
        let json = """
        {"meta":{"contract_version":"v1","server_time":"t","viewer_id":"v1"},"data":{"scope":"following","content_filter":"all","authors":{},"engagement":{},"stories":[],"story_authors":{},"page_meta":{"limit":8,"returned":0,"has_more":false},"following_ids_echo":[]}}
        """
        XCTAssertThrowsError(try decode(json) as FeedBootstrapV1)
    }

    @MainActor
    func testFeedLoaderCacheHit() async throws {
        BackendV2FeatureFlags.setFlagForTests(.feed, enabled: true)
        let viewer = ProfileID("11111111-1111-1111-1111-111111111111")
        let key = FeedSessionStore.cacheKey(
            viewerID: viewer,
            scope: .following,
            contentFilter: .all,
            cursor: nil
        )
        FeedSessionStore.shared.save(
            FeedSessionStore.Snapshot(
                cacheKey: key,
                entries: [],
                stories: [],
                nextCursor: nil,
                loadedAt: Date()
            )
        )
        let restored = FeedSessionStore.shared.restore(key: key)
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.cacheKey, key)
    }

    @MainActor
    func testFeedLogoutClearsCache() {
        FeedSessionStore.shared.save(
            FeedSessionStore.Snapshot(
                cacheKey: "user|following|all|-",
                entries: [],
                stories: [],
                nextCursor: nil,
                loadedAt: Date()
            )
        )
        FeedSessionStore.shared.invalidate()
        XCTAssertNil(FeedSessionStore.shared.restore(key: "user|following|all|-"))
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}

enum FeedBootstrapN3Fixtures {
    static let globalTrades = """
    {"meta":{"contract_version":"v1","server_time":"2026-08-19T20:00:00.000Z","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"scope":"global","content_filter":"trades","items":[{"kind":"trade","id":"t1","created_at":"2026-08-19T20:00:00.000Z","author_id":"22222222-2222-2222-2222-222222222222","payload":{"ticker":"ES"}}],"authors":{"22222222-2222-2222-2222-222222222222":{"id":"22222222-2222-2222-2222-222222222222","username":"trader_a","display_name":"Trader A","avatar_url":null}},"engagement":{"t1":{"like_count":1,"comment_count":0,"liked_by_viewer":true}},"stories":[],"story_authors":{},"next_cursor":null,"page_meta":{"limit":8,"returned":1,"has_more":false},"following_ids_echo":[]}}
    """
}

// MARK: - Messaging inbox contract

@MainActor
final class MessagingBootstrapN3Tests: XCTestCase {
    override func tearDown() {
        BackendV2FeatureFlags.resetFlagsForTests()
        MessagesInboxStore.shared.resetForTesting()
        Task {
            await BackendV2SingleFlight.shared.clear()
            await BackendV2RpcAvailability.shared.clear()
        }
        super.tearDown()
    }

    func testDirectConversationFixtureDecodes() throws {
        let value: MessagesBootstrapV1 = try decode(BackendV2ContractFixtures.messages)
        try value.validateContractVersion()
        XCTAssertEqual(value.data.conversations.count, 1)
        XCTAssertFalse(value.data.conversations[0].is_group)
        XCTAssertEqual(value.data.dm_unread_total, 1)
    }

    func testGroupConversationFixtureDecodes() throws {
        let value: MessagesBootstrapV1 = try decode(MessagingBootstrapN3Fixtures.groupConversation)
        XCTAssertTrue(value.data.conversations[0].is_group)
    }

    func testEmptyInboxDecodes() throws {
        let value: MessagesBootstrapV1 = try decode(MessagingBootstrapN3Fixtures.emptyInbox)
        XCTAssertTrue(value.data.conversations.isEmpty)
    }

    @MainActor
    func testApplierSeedsInboxStore() throws {
        let bootstrap: MessagesBootstrapV1 = try decode(BackendV2ContractFixtures.messages)
        try MessagingBootstrapApplier.apply(
            bootstrap,
            inboxStore: MessagesInboxStore.shared,
            detailCache: DetailPresentationCache()
        )
        XCTAssertEqual(MessagesInboxStore.shared.conversations.count, 1)
        XCTAssertEqual(MessagesInboxStore.shared.conversations[0].unreadCount, 1)
    }

    @MainActor
    func testMessagingLoaderSingleRpc() async throws {
        BackendV2FeatureFlags.setFlagForTests(.messages, enabled: true)
        let rpc = CapturingMessagingRPCClient(json: BackendV2ContractFixtures.messages)
        let viewer = ProfileID("11111111-1111-1111-1111-111111111111")
        _ = try await MessagingBootstrapLoader.loadInbox(
            viewerID: viewer,
            rpc: rpc,
            inboxStore: MessagesInboxStore.shared,
            detailCache: DetailPresentationCache(),
            forceNetwork: true,
            loadGeneration: 1,
            currentGeneration: { 1 }
        )
        XCTAssertEqual(rpc.callCount, 1)
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}

enum MessagingBootstrapN3Fixtures {
    static let groupConversation = """
    {"meta":{"contract_version":"v1","server_time":"2026-08-19T20:00:00.000Z","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"conversations":[{"id":"g1","is_group":true,"is_pinned":false,"name":"Team","avatar_url":null,"last_message":"hi","last_message_at":"2026-08-19T19:00:00.000Z","unread_count":0,"muted":false,"participants":[{"user_id":"11111111-1111-1111-1111-111111111111","username":"viewer","display_name":"Viewer","avatar_url":null}]}],"peers":{},"dm_unread_total":0,"muted_ids":[],"next_cursor":null,"page_meta":{"limit":40,"returned":1,"has_more":false}}}
    """

    static let emptyInbox = """
    {"meta":{"contract_version":"v1","server_time":"2026-08-19T20:00:00.000Z","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"conversations":[],"peers":{},"dm_unread_total":0,"muted_ids":[],"next_cursor":null,"page_meta":{"limit":40,"returned":0,"has_more":false}}}
    """
}

// MARK: - Test doubles

private struct FailingThreadRPCClient: RPCClient, Sendable {
    let errorText: String

    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        throw BackendV2RPCError.transport(errorText)
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        throw BackendV2RPCError.transport(errorText)
    }
}

private final class CapturingFeedRPCClient: RPCClient, @unchecked Sendable {
    let json: String
    private(set) var callCount = 0

    init(json: String) { self.json = json }

    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        callCount += 1
        return Data(json.utf8)
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        callCount += 1
        return Data(json.utf8)
    }
}

private final class CapturingMessagingRPCClient: RPCClient, @unchecked Sendable {
    let json: String
    private(set) var callCount = 0

    init(json: String) { self.json = json }

    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        callCount += 1
        return Data(json.utf8)
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        callCount += 1
        return Data(json.utf8)
    }
}

private final class CountingMessageRepository: MessageRepository, @unchecked Sendable {
    private(set) var markReadCallCount = 0

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

    func markRead(conversationID: ConversationID) async throws {
        markReadCallCount += 1
    }

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
        try await createConversation(participantIDs: [viewerID, recipient.id])
    }

    func createGroupConversation(
        viewerID: ProfileID,
        recipients: [Profile],
        name: String?
    ) async throws -> Conversation {
        try await createConversation(participantIDs: [viewerID] + recipients.map(\.id))
    }

    func deleteConversation(id: ConversationID) async throws {}

    func deleteMessageForEveryone(_ messageID: MessageID, in conversationID: ConversationID) async throws {}

    func setConversationNotificationsEnabled(
        conversationID: ConversationID,
        enabled: Bool
    ) async throws {}
}

private struct N3StubRoomRepository: RoomRepository {
    func room(id: RoomID) async throws -> TradeRoom {
        TradeRoom(
            id: id,
            ownerProfileID: ProfileID("o"),
            name: "Room",
            slug: "room",
            description: nil,
            image: nil,
            memberCount: 0,
            showsOnProfile: false,
            createdAt: .now
        )
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

private struct N3StubSession: SessionProviding {
    let userID: String

    var currentUserID: UserID? {
        get async { UserID(userID) }
    }

    var accessToken: String? {
        get async { "test-token" }
    }
}
