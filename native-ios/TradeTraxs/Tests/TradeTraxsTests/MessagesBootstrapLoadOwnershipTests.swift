import XCTest
@testable import TradeTraxs

@MainActor
final class MessagesBootstrapLoadOwnershipTests: XCTestCase {
    override func setUp() async throws {
        BackendV2FeatureFlags.setFlagForTests(.messages, enabled: true)
        MessagesInboxStore.shared.resetForTesting()
        MessagingDomain.shared.invalidate()
        SessionMemberRoomsStore.shared.invalidate()
        await BackendV2SingleFlight.shared.clear()
        await BackendV2RpcAvailability.shared.clear()
        await SessionNetworkGate.shared.markReady()
    }

    override func tearDown() async throws {
        BackendV2FeatureFlags.resetFlagsForTests()
        MessagesInboxStore.shared.resetForTesting()
        MessagingDomain.shared.invalidate()
        await BackendV2SingleFlight.shared.clear()
        await SessionNetworkGate.shared.markUnauthenticated()
    }

    func testFirstAppearanceStartsOneBootstrapRequest() async throws {
        let rpc = CountingMessagingRPCClient(json: BackendV2ContractFixtures.messages)
        let domain = configuredDomain(rpc: rpc)
        await domain.bootstrapHomeIfNeeded(forceNetwork: false)
        XCTAssertEqual(rpc.callCount, 1)
        XCTAssertEqual(domain.state.phase, .loaded)
        XCTAssertTrue(MessagesInboxStore.shared.hasLoaded)
    }

    func testConcurrentBootstrapWaitersShareOneRequest() async throws {
        let rpc = SlowMessagingRPCClient(
            json: BackendV2ContractFixtures.messages,
            delayNanoseconds: 100_000_000
        )
        let domain = configuredDomain(rpc: rpc)
        async let first = domain.bootstrapHomeIfNeeded(forceNetwork: false)
        async let second = domain.bootstrapHomeIfNeeded(forceNetwork: false)
        await first
        await second
        XCTAssertEqual(rpc.callCount, 1)
    }

    func testCancelledWaiterDoesNotStartSecondRequest() async throws {
        let rpc = SlowMessagingRPCClient(
            json: BackendV2ContractFixtures.messages,
            delayNanoseconds: 200_000_000
        )
        let key = BackendV2FlightKeys.messaging(viewerID: "viewer-1", cursor: nil)
        let cancelled = Task {
            _ = try await BackendV2SingleFlight.shared.coalesce(key: key) {
                try await rpc.call(functionName: "rpc_v2_messaging_bootstrap", jsonBody: Data("{}".utf8))
            }
        }
        cancelled.cancel()
        try? await cancelled.value
        let data = try await BackendV2SingleFlight.shared.coalesce(key: key) {
            try await rpc.call(functionName: "rpc_v2_messaging_bootstrap", jsonBody: Data("{}".utf8))
        }
        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(rpc.callCount, 1)
    }

    func testAppErrorValidationPreservesTypedDiagnosticThroughRPCClient() async throws {
        let body = """
        {"code":"PGRST202","message":"Could not find the function","details":"rpc_v2_messaging_bootstrap","hint":null}
        """
        let transport = AppErrorValidationTransport(
            statusCode: 404,
            body: body
        )
        let client = BackendV2RPCClient(transport: transport)
        do {
            _ = try await client.call(
                .messaging,
                argumentsJSON: Data("{}".utf8),
                as: MessagesBootstrapV1.self
            )
            XCTFail("Expected validation failure")
        } catch let error as BackendV2RPCError {
            let diagnostic = MessagesBootstrapFailureDiagnostic.make(error: error)
            XCTAssertEqual(diagnostic.errorKind, .validation)
            XCTAssertEqual(diagnostic.httpStatus, 404)
            XCTAssertTrue(diagnostic.summary.contains("code=PGRST202"))
            XCTAssertTrue(diagnostic.summary.contains("message=Could not find the function"))
            XCTAssertFalse(diagnostic.summary.contains("transport"))
        }
    }

    func testFailedFlightRemovedSoRetryStartsNewRequest() async throws {
        let rpc = FlakyAfterFailMessagingRPCClient()
        let key = BackendV2FlightKeys.messaging(
            viewerID: "11111111-1111-1111-1111-111111111111",
            cursor: nil
        )
        do {
            _ = try await BackendV2SingleFlight.shared.coalesce(key: key) {
                try await rpc.call(functionName: "rpc_v2_messaging_bootstrap", jsonBody: Data("{}".utf8))
            }
            XCTFail("Expected validation failure")
        } catch {
            XCTAssertEqual(
                MessagesBootstrapFailureDiagnostic.make(error: error).errorKind,
                .validation
            )
        }
        let stillInFlight = await BackendV2SingleFlight.shared.hasInFlight(key: key)
        XCTAssertFalse(stillInFlight)
        let data = try await BackendV2SingleFlight.shared.coalesce(key: key) {
            try await rpc.call(functionName: "rpc_v2_messaging_bootstrap", jsonBody: Data("{}".utf8))
        }
        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(rpc.callCount, 2)
    }

    func testSlowResponseWithinTransportTimeoutSucceeds() async throws {
        BackendV2FeatureFlags.setFlagForTests(.messages, enabled: true)
        #if DEBUG
        let slowNs: UInt64 = 2_700_000_000
        try await BootstrapTransportTimeout.withTestTimeout(45_000_000_000) {
            let rpc = SlowMessagingRPCClient(
                json: BackendV2ContractFixtures.messages,
                delayNanoseconds: slowNs
            )
            let domain = configuredDomain(rpc: rpc)
            await domain.bootstrapHomeIfNeeded(forceNetwork: false)
            XCTAssertEqual(domain.state.phase, .loaded)
            XCTAssertEqual(rpc.callCount, 1)
        }
        #endif
    }

    func testIntentionalCancellationDoesNotSurfaceTerminalFailure() async throws {
        let domain = configuredDomain(rpc: CountingMessagingRPCClient(json: BackendV2ContractFixtures.messages))
        let load = Task {
            await domain.bootstrapHomeIfNeeded(forceNetwork: false)
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        load.cancel()
        _ = await load.result
        if case .failed = domain.state.phase {
            XCTFail("Cancelled bootstrap should not publish terminal failure")
        }
    }

    func testCachedInboxSurvivesTransientRevalidationFailure() async throws {
        let rpc = FlakyMessagingRPCClient(
            successJSON: BackendV2ContractFixtures.messages,
            failAfterSuccess: true
        )
        let domain = configuredDomain(rpc: rpc)
        await domain.bootstrapHomeIfNeeded(forceNetwork: false)
        XCTAssertTrue(MessagesInboxStore.shared.hasLoaded, "bootstrap should populate inbox")
        XCTAssertFalse(MessagesInboxStore.shared.conversations.isEmpty)
        let countBefore = MessagesInboxStore.shared.conversations.count
        MessagesInboxStore.shared.markStaleForTesting()
        domain.setHomeScreenVisible(true)
        await domain.refreshHome()
        XCTAssertEqual(MessagesInboxStore.shared.conversations.count, countBefore)
        XCTAssertEqual(domain.state.phase, .loaded)
    }

    func testFreshCacheDoesNotRevalidateOnReturn() async throws {
        let rpc = CountingMessagingRPCClient(json: BackendV2ContractFixtures.messages)
        let domain = configuredDomain(rpc: rpc)
        await domain.bootstrapHomeIfNeeded(forceNetwork: false)
        XCTAssertEqual(rpc.callCount, 1)
        await domain.bootstrapHomeIfNeeded(forceNetwork: false)
        XCTAssertEqual(rpc.callCount, 1)
    }

    func testStaleGenerationFailureCannotOverwriteLoadedState() async throws {
        let domain = configuredDomain(rpc: CountingMessagingRPCClient(json: BackendV2ContractFixtures.messages))
        await domain.bootstrapHomeIfNeeded(forceNetwork: false)
        XCTAssertEqual(domain.state.phase, .loaded)
        domain.invalidate()
        MessagesInboxStore.shared.resetForTesting()
        MessagesInboxStore.shared.seedForTesting(conversationCount: 2)
        domain.configure(
            messages: StubMessageRepository(),
            rooms: StubRoomRepository(),
            profiles: StubProfileRepository(),
            session: StubSession(userID: "11111111-1111-1111-1111-111111111111"),
            detailCache: DetailPresentationCache(),
            realtimeHub: nil,
            rpc: FailingMessagingRPCClient()
        )
        await domain.bootstrapHomeIfNeeded(forceNetwork: false)
        XCTAssertEqual(domain.state.phase, .loaded)
        XCTAssertEqual(domain.state.errorMessage, nil)
        XCTAssertGreaterThanOrEqual(MessagesInboxStore.shared.conversations.count, 2)
    }

    // MARK: - Helpers

    private func configuredDomain(rpc: any RPCClient) -> MessagingDomain {
        let domain = MessagingDomain.shared
        domain.configure(
            messages: StubMessageRepository(),
            rooms: StubRoomRepository(),
            profiles: StubProfileRepository(),
            session: StubSession(userID: "11111111-1111-1111-1111-111111111111"),
            detailCache: DetailPresentationCache(),
            realtimeHub: nil,
            rpc: rpc
        )
        return domain
    }
}

// MARK: - Test doubles

private final class CountingMessagingRPCClient: RPCClient, @unchecked Sendable {
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

private struct AppErrorValidationTransport: RPCClient, Sendable {
    let statusCode: Int
    let body: String

    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        try await call(functionName: functionName, jsonBody: Data())
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        throw AppError.transport(.validation(statusCode: statusCode, message: body))
    }
}

private final class FlakyAfterFailMessagingRPCClient: RPCClient, @unchecked Sendable {
    private(set) var callCount = 0

    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        try await call(functionName: functionName, jsonBody: Data())
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        callCount += 1
        if callCount == 1 {
            throw AppError.transport(.validation(statusCode: 400, message: "HTTP 400 rpc_v2_messaging_bootstrap unavailable"))
        }
        return Data(BackendV2ContractFixtures.messages.utf8)
    }
}

private final class SlowMessagingRPCClient: RPCClient, @unchecked Sendable {
    let json: String
    let delayNanoseconds: UInt64
    private(set) var callCount = 0

    init(json: String, delayNanoseconds: UInt64) {
        self.json = json
        self.delayNanoseconds = delayNanoseconds
    }

    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        try await call(functionName: functionName, jsonBody: Data())
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        callCount += 1
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return Data(json.utf8)
    }
}

private final class FlakyMessagingRPCClient: RPCClient, @unchecked Sendable {
    let successJSON: String
    var failAfterSuccess: Bool
    private(set) var callCount = 0

    init(successJSON: String, failAfterSuccess: Bool) {
        self.successJSON = successJSON
        self.failAfterSuccess = failAfterSuccess
    }

    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        try await call(functionName: functionName, jsonBody: Data())
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        callCount += 1
        if failAfterSuccess, callCount > 1 {
            throw URLError(.notConnectedToInternet)
        }
        return Data(successJSON.utf8)
    }
}

private struct FailingMessagingRPCClient: RPCClient, Sendable {
    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        throw URLError(.notConnectedToInternet)
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        throw URLError(.notConnectedToInternet)
    }
}

private struct StubSession: SessionProviding, Sendable {
    let userID: String
    var currentUserID: UserID? { get async { UserID(userID) } }
    var accessToken: String? { get async { "token" } }
}

private struct StubMessageRepository: MessageRepository {
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
        throw AppError.notImplemented(feature: "create")
    }
    func findExistingDirectConversationID(viewerID: ProfileID, recipientID: ProfileID) async throws -> ConversationID? { nil }
    func usersHaveActiveBlock(viewerID: ProfileID, otherID: ProfileID) async -> Bool { false }
    func createDirectConversation(viewerID: ProfileID, recipient: Profile) async throws -> Conversation {
        throw AppError.notImplemented(feature: "create")
    }
    func createGroupConversation(viewerID: ProfileID, recipients: [Profile], name: String?) async throws -> Conversation {
        throw AppError.notImplemented(feature: "group")
    }
}

private struct StubRoomRepository: RoomRepository {
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
        RoomMembership(roomID: roomID, profileID: profileID, role: .member, joinedAt: .now, notificationsEnabled: true)
    }
    func leave(roomID: RoomID, profileID: ProfileID) async throws {}
    func messages(roomID: RoomID, page: PageRequest) async throws -> CursorPage<RoomMessage> {
        CursorPage(items: [], nextCursor: nil)
    }
    func messages(roomID: RoomID, channel: RoomChannel?, page: PageRequest) async throws -> CursorPage<RoomMessage> {
        CursorPage(items: [], nextCursor: nil)
    }
    func send(_ message: RoomMessage) async throws -> RoomMessage { message }
    func insertMessageReaction(roomID: RoomID, messageID: RoomMessageID, userID: ProfileID, reaction: String) async throws -> RoomMessageReaction {
        RoomMessageReaction(id: "stub", messageID: messageID, userID: userID, reaction: reaction, createdAt: nil)
    }
    func deleteMessageReaction(id: String) async throws {}
    func moderate(roomID: RoomID, messageID: RoomMessageID?, targetProfileID: ProfileID?, action: RoomModerationAction) async throws {}
}

private struct StubProfileRepository: ProfileRepository {
    func currentUser() async throws -> User { User(id: UserID("viewer-1"), email: nil, createdAt: .now) }
    func profile(id: ProfileID) async throws -> Profile {
        Profile(
            id: id, userID: UserID(id.rawValue), username: id.rawValue, displayName: id.rawValue,
            bio: nil, avatar: nil, traderType: nil, tradingStyle: nil, primaryMarket: nil,
            startedTradingAt: nil, isPrivate: false, isCreator: false, createdAt: .now
        )
    }
    func profile(username: String) async throws -> Profile { try await profile(id: ProfileID(username)) }
    func updateProfile(_ profile: Profile) async throws -> Profile { profile }
    func stats(for: ProfileID) async throws -> ProfileStats {
        ProfileStats(profileID: ProfileID("x"), followerCount: 0, followingCount: 0, postCount: 0, tradeCount: 0, publicTradeCount: 0, winRate: 0)
    }
    func wallPosts(for: ProfileID, page: PageRequest) async throws -> CursorPage<Post> { CursorPage(items: [], nextCursor: nil) }
    func wallPost(id: PostID) async throws -> Post { throw AppError.domain(.notFound(entity: "post", id: id.rawValue)) }
    func followState(from: ProfileID, to: ProfileID) async throws -> FollowState { .none }
    func follow(from: ProfileID, to: ProfileID) async throws {}
    func unfollow(from: ProfileID, to: ProfileID) async throws {}
    func followers(of: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> { CursorPage(items: [], nextCursor: nil) }
    func following(of: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> { CursorPage(items: [], nextCursor: nil) }
    func creator(for: ProfileID) async throws -> Creator? { nil }
}
