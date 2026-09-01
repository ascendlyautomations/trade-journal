import XCTest
@testable import TradeTraxs

final class BootstrapRpcHangTests: XCTestCase {
    override func tearDown() {
        BackendV2FeatureFlags.resetFlagsForTests()
        BackendV2BootstrapDiskCache.clearAll()
        #if DEBUG
        BootstrapTransportTimeout.overrideNanoseconds = nil
        #endif
        let group = DispatchGroup()
        group.enter()
        Task {
            await BackendV2SingleFlight.shared.clear()
            await BackendV2RpcAvailability.shared.clear()
            await AppIconBadgeRefreshFlight.shared.resetForTests()
            group.leave()
        }
        group.wait()
        super.tearDown()
    }

    @MainActor
    func testSessionRpcSuccessExitsLoading() async throws {
        BackendV2FeatureFlags.setFlagForTests(.session, enabled: true)
        let viewer = ProfileID("11111111-1111-1111-1111-111111111111")
        let rpc = HangFixtureRPCClient(json: BackendV2ContractFixtures.session)

        let result = try await SessionBootstrapLoader.load(
            viewerID: viewer,
            rpc: rpc,
            profiles: HangCountingProfileRepository(),
            detailCache: nil,
            forceNetwork: true,
            loadGeneration: 1,
            currentGeneration: { 1 }
        )

        XCTAssertEqual(result.path, .v2_rpc)
        XCTAssertEqual(rpc.callCount, 1)
    }

    @MainActor
    func testDashboardRpcSuccessExitsLoading() async throws {
        BackendV2FeatureFlags.setFlagForTests(.dashboard, enabled: true)
        let viewer = ProfileID("11111111-1111-1111-1111-111111111111")
        let rpc = HangFixtureRPCClient(json: BackendV2ContractFixtures.dashboard)
        let detailCache = DetailPresentationCache()

        let result = try await DashboardBootstrapLoader.load(
            viewerID: viewer,
            rpc: rpc,
            detailCache: detailCache,
            forceNetwork: true,
            loadGeneration: 1,
            currentGeneration: { 1 }
        )

        XCTAssertEqual(result.path, .v2_rpc)
        XCTAssertEqual(rpc.callCount, 1)
        XCTAssertFalse(result.applied.trades.isEmpty)
    }

    @MainActor
    func testSingleFlightClearsAfterSuccess() async throws {
        BackendV2FeatureFlags.setFlagForTests(.session, enabled: true)
        let viewer = ProfileID("11111111-1111-1111-1111-111111111111")
        let rpc = HangFixtureRPCClient(json: BackendV2ContractFixtures.session)
        let profiles = HangCountingProfileRepository()

        async let a = SessionBootstrapLoader.load(
            viewerID: viewer,
            rpc: rpc,
            profiles: profiles,
            detailCache: nil,
            forceNetwork: true,
            loadGeneration: 1,
            currentGeneration: { 1 }
        )
        async let b = SessionBootstrapLoader.load(
            viewerID: viewer,
            rpc: rpc,
            profiles: profiles,
            detailCache: nil,
            forceNetwork: true,
            loadGeneration: 1,
            currentGeneration: { 1 }
        )
        _ = try await (a, b)
        XCTAssertEqual(rpc.callCount, 1)

        _ = try await SessionBootstrapLoader.load(
            viewerID: viewer,
            rpc: rpc,
            profiles: profiles,
            detailCache: nil,
            forceNetwork: true,
            loadGeneration: 2,
            currentGeneration: { 2 }
        )
        XCTAssertEqual(rpc.callCount, 2)
    }

    @MainActor
    func testSingleFlightClearsAfterFailure() async throws {
        BackendV2FeatureFlags.setFlagForTests(.session, enabled: true)
        let viewer = ProfileID("11111111-1111-1111-1111-111111111111")
        let rpc = HangFailingRPCClient(message: "503 upstream unavailable")
        let profiles = HangCountingProfileRepository()

        do {
            _ = try await SessionBootstrapLoader.load(
                viewerID: viewer,
                rpc: rpc,
                profiles: profiles,
                detailCache: nil,
                forceNetwork: true,
                loadGeneration: 1,
                currentGeneration: { 1 }
            )
            XCTFail("Expected transport failure")
        } catch {
            XCTAssertTrue(String(describing: error).contains("503"))
        }

        _ = try await SessionBootstrapLoader.load(
            viewerID: viewer,
            rpc: HangFixtureRPCClient(json: BackendV2ContractFixtures.session),
            profiles: profiles,
            detailCache: nil,
            forceNetwork: true,
            loadGeneration: 2,
            currentGeneration: { 2 }
        )
    }

    @MainActor
    func testHangingTransportTimesOutAndProfileStoreExitsLoading() async throws {
        BackendV2FeatureFlags.setFlagForTests(.session, enabled: true)
        #if DEBUG
        BootstrapTransportTimeout.overrideNanoseconds = 200_000_000
        defer { BootstrapTransportTimeout.overrideNanoseconds = nil }
        #endif
        let store = CurrentUserProfileStore(
            profiles: HangCountingProfileRepository(),
            session: HangFixedSessionProvider(userID: UserID("11111111-1111-1111-1111-111111111111")),
            imagePipeline: HangNoOpImagePipeline(),
            rpc: HangNeverRespondsRPCClient()
        )
        await SessionNetworkGate.shared.markReady()
        store.loadIfNeeded(force: true)

        for _ in 0..<40 where store.phase == .loading || store.phase == .idle {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertNotEqual(store.phase, .loading)
        XCTAssertEqual(store.phase, .failed)
    }

    @MainActor
    func testCancellationExitsProfileLoading() async throws {
        BackendV2FeatureFlags.setFlagForTests(.session, enabled: true)
        let store = CurrentUserProfileStore(
            profiles: HangCountingProfileRepository(),
            session: HangFixedSessionProvider(userID: UserID("11111111-1111-1111-1111-111111111111")),
            imagePipeline: HangNoOpImagePipeline(),
            rpc: HangSlowRPCClient(delayNanoseconds: 500_000_000)
        )
        await SessionNetworkGate.shared.markReady()
        store.loadIfNeeded(force: true)
        try await Task.sleep(nanoseconds: 50_000_000)
        store.clear()
        XCTAssertNotEqual(store.phase, .loading)
    }

    @MainActor
    func testHttpNon2xxSurfacesTypedFailure() async {
        BackendV2FeatureFlags.setFlagForTests(.session, enabled: true)
        let viewer = ProfileID("11111111-1111-1111-1111-111111111111")
        let rpc = HangFailingRPCClient(message: "HTTP 503 Service Unavailable")

        do {
            _ = try await SessionBootstrapLoader.load(
                viewerID: viewer,
                rpc: rpc,
                profiles: HangCountingProfileRepository(),
                detailCache: nil,
                forceNetwork: true,
                loadGeneration: 1,
                currentGeneration: { 1 }
            )
            XCTFail("Expected failure")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
    }

    @MainActor
    func testDecoderFailureIsNotEmptySuccess() async {
        BackendV2FeatureFlags.setFlagForTests(.session, enabled: true)
        let viewer = ProfileID("11111111-1111-1111-1111-111111111111")
        let rpc = HangFixtureRPCClient(json: "{}")

        do {
            _ = try await SessionBootstrapLoader.load(
                viewerID: viewer,
                rpc: rpc,
                profiles: HangCountingProfileRepository(),
                detailCache: nil,
                forceNetwork: true,
                loadGeneration: 1,
                currentGeneration: { 1 }
            )
            XCTFail("Expected decode failure")
        } catch {
            XCTAssertTrue(String(describing: error).contains("decode") || String(describing: error).contains("Decoding"))
        }
    }

    @MainActor
    func testSingleFlightWaiterCancelDoesNotCancelSharedTransport() async throws {
        await BackendV2SingleFlight.shared.clear()
        let key = BackendV2FlightKeys.messaging(viewerID: "viewer-1", cursor: nil)
        final class Counter: @unchecked Sendable {
            var value = 0
        }
        let counter = Counter()

        let cancelled = Task {
            _ = try await BackendV2SingleFlight.shared.coalesce(key: key) {
                counter.value += 1
                try await Task.sleep(nanoseconds: 300_000_000)
                return Data("{}".utf8)
            }
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        cancelled.cancel()
        _ = await cancelled.result

        let data = try await BackendV2SingleFlight.shared.coalesce(key: key) {
            counter.value += 1
            return Data("{}".utf8)
        }
        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(counter.value, 1)
        let waiters = await BackendV2SingleFlight.shared.inFlightWaiterCount(key: key)
        XCTAssertEqual(waiters, 0)
    }

    @MainActor
    func testMessagingSlowResponseWithinDefaultTimeout() async throws {
        BackendV2FeatureFlags.setFlagForTests(.messages, enabled: true)
        await SessionNetworkGate.shared.markReady()
        let viewer = ProfileID("11111111-1111-1111-1111-111111111111")
        let rpc = HangSlowRPCClient(delayNanoseconds: 2_700_000_000, json: BackendV2ContractFixtures.messages)
        let result = try await MessagingBootstrapLoader.loadInbox(
            viewerID: viewer,
            rpc: rpc,
            inboxStore: MessagesInboxStore.shared,
            detailCache: DetailPresentationCache(),
            forceNetwork: true,
            loadGeneration: 1,
            currentGeneration: { 1 }
        )
        XCTAssertFalse(result.bootstrap.data.conversations.isEmpty)
    }

    @MainActor
    func testLateGenerationRejectedWithoutOverwriting() async throws {
        BackendV2FeatureFlags.setFlagForTests(.session, enabled: true)
        let viewer = ProfileID("11111111-1111-1111-1111-111111111111")
        let rpc = HangSlowRPCClient(delayNanoseconds: 300_000_000, json: BackendV2ContractFixtures.session)
        let profiles = HangCountingProfileRepository()
        let store = CurrentUserProfileStore(
            profiles: profiles,
            session: HangFixedSessionProvider(userID: UserID(viewer.rawValue)),
            imagePipeline: HangNoOpImagePipeline(),
            rpc: rpc
        )
        await SessionNetworkGate.shared.markReady()
        store.loadIfNeeded(force: true)
        store.clear()
        store.loadIfNeeded(force: true)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertNotEqual(store.phase, .loading)
    }

    @MainActor
    func testSessionAndDashboardRunIndependently() async throws {
        BackendV2FeatureFlags.setFlagForTests(.session, enabled: true)
        BackendV2FeatureFlags.setFlagForTests(.dashboard, enabled: true)
        let viewer = ProfileID("11111111-1111-1111-1111-111111111111")

        let sessionResult = try await SessionBootstrapLoader.load(
            viewerID: viewer,
            rpc: HangFixtureRPCClient(json: BackendV2ContractFixtures.session),
            profiles: HangCountingProfileRepository(),
            detailCache: nil,
            forceNetwork: true,
            loadGeneration: 1,
            currentGeneration: { 1 }
        )
        let dashboardResult = try await DashboardBootstrapLoader.load(
            viewerID: viewer,
            rpc: HangFixtureRPCClient(json: BackendV2ContractFixtures.dashboard),
            detailCache: DetailPresentationCache(),
            forceNetwork: true,
            loadGeneration: 1,
            currentGeneration: { 1 }
        )

        XCTAssertEqual(sessionResult.path, .v2_rpc)
        XCTAssertEqual(dashboardResult.path, .v2_rpc)
    }

    @MainActor
    func testLegacyFlagsOffPreservesRESTPath() async throws {
        BackendV2FeatureFlags.setFlagForTests(.session, enabled: false)
        BackendV2FeatureFlags.setFlagForTests(.dashboard, enabled: false)
        let viewer = ProfileID("viewer-legacy")
        let profiles = HangCountingProfileRepository()

        let session = try await SessionBootstrapLoader.load(
            viewerID: viewer,
            rpc: HangFixtureRPCClient(json: "{}"),
            profiles: profiles,
            detailCache: nil,
            forceNetwork: true,
            loadGeneration: 1,
            currentGeneration: { 1 }
        )

        XCTAssertEqual(session.path, .legacy_flag_off)
        XCTAssertEqual(profiles.profileCallCount, 1)
    }

    func testBadgeRefreshCoalescesConcurrentCalls() async {
        await AppIconBadgeRefreshFlight.shared.resetForTests()
        let counter = HangBadgeCallCounter()
        async let first: Void = AppIconBadgeRefreshFlight.shared.run {
            await counter.increment()
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        async let second: Void = AppIconBadgeRefreshFlight.shared.run {
            await counter.increment()
        }
        await first
        await second
        let callCount = await counter.value
        XCTAssertEqual(callCount, 1)
    }

    @MainActor
    func testMainActorBootstrapDoesNotDeadlockSingleFlight() async throws {
        BackendV2FeatureFlags.setFlagForTests(.session, enabled: true)
        let viewer = ProfileID("11111111-1111-1111-1111-111111111111")
        let rpc = HangFixtureRPCClient(json: BackendV2ContractFixtures.session)

        try await withThrowingTaskGroup(of: SessionBootstrapLoadResult.self) { group in
            for _ in 0..<4 {
                group.addTask { @MainActor in
                    try await SessionBootstrapLoader.load(
                        viewerID: viewer,
                        rpc: rpc,
                        profiles: HangCountingProfileRepository(),
                        detailCache: nil,
                        forceNetwork: true,
                        loadGeneration: 1,
                        currentGeneration: { 1 }
                    )
                }
            }
            var count = 0
            while let result = try await group.next() {
                XCTAssertEqual(result.path, .v2_rpc)
                count += 1
            }
            XCTAssertEqual(count, 4)
        }
        XCTAssertEqual(rpc.callCount, 1)
    }
}

// MARK: - Test doubles (prefixed to avoid clashing with N1 tests)

private final class HangCountingProfileRepository: ProfileRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _profileCallCount = 0
    private var _statsCallCount = 0

    var profileCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _profileCallCount
    }

    var statsCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _statsCallCount
    }

    func currentUser() async throws -> User {
        User(id: UserID("viewer-1"), email: nil, createdAt: .now)
    }

    func profile(id: ProfileID) async throws -> Profile {
        lock.lock()
        _profileCallCount += 1
        lock.unlock()
        return Profile(
            id: id,
            userID: UserID(id.rawValue),
            username: "viewer",
            displayName: "Viewer",
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

    func profiles(ids: [ProfileID]) async throws -> [Profile] {
        try await ids.asyncMap { try await profile(id: $0) }
    }

    func profile(username: String) async throws -> Profile {
        try await profile(id: ProfileID(username))
    }

    func updateProfile(_ profile: Profile) async throws -> Profile { profile }

    func stats(for profileID: ProfileID) async throws -> ProfileStats {
        lock.lock()
        _statsCallCount += 1
        lock.unlock()
        return ProfileStats(
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
        throw AppError.notImplemented(feature: "wallPost")
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

private struct HangFixedSessionProvider: SessionProviding {
    let userID: UserID
    var currentUserID: UserID? { get async { userID } }
    var accessToken: String? { get async { "token" } }
}

private struct HangNoOpImagePipeline: ImagePipeline {
    func data(for request: ImageRequest) async throws -> Data { Data() }
    func prefetch(_ requests: [ImageRequest]) async {}
    func invalidate(reference: MediaReference) async {}
}

private actor HangBadgeCallCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private final class HangNeverRespondsRPCClient: RPCClient, @unchecked Sendable {
    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        try await Task.sleep(nanoseconds: 120_000_000_000)
        return Data()
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        try await call(functionName: functionName, parameters: [:])
    }
}

private final class HangSlowRPCClient: RPCClient, @unchecked Sendable {
    let delayNanoseconds: UInt64
    let json: String

    init(delayNanoseconds: UInt64, json: String = "{}") {
        self.delayNanoseconds = delayNanoseconds
        self.json = json
    }

    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return Data(json.utf8)
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        try await call(functionName: functionName, parameters: [:])
    }
}

private final class HangFixtureRPCClient: RPCClient, @unchecked Sendable {
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

private final class HangFailingRPCClient: RPCClient, @unchecked Sendable {
    let message: String
    private(set) var callCount = 0

    init(message: String) { self.message = message }

    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        callCount += 1
        throw BackendV2RPCError.transport(message)
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        callCount += 1
        throw BackendV2RPCError.transport(message)
    }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        for element in self {
            result.append(try await transform(element))
        }
        return result
    }
}
