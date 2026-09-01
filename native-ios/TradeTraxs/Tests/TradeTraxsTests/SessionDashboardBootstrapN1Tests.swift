import XCTest
@testable import TradeTraxs

final class SessionDashboardBootstrapN1Tests: XCTestCase {
    override func tearDown() {
        BackendV2FeatureFlags.resetFlagsForTests()
        BackendV2BootstrapDiskCache.clearAll()
        Task {
            await BackendV2SingleFlight.shared.clear()
            await BackendV2RpcAvailability.shared.clear()
        }
        super.tearDown()
    }

    @MainActor
    func testSessionV2SuccessDoesNotUseLegacyREST() async throws {
        BackendV2FeatureFlags.setFlagForTests(.session, enabled: true)
        let viewer = ProfileID("11111111-1111-1111-1111-111111111111")
        let profiles = CountingProfileRepository()
        let rpc = FixtureRPCClient(json: BackendV2ContractFixtures.session)

        let result = try await SessionBootstrapLoader.load(
            viewerID: viewer,
            rpc: rpc,
            profiles: profiles,
            detailCache: nil,
            forceNetwork: true,
            loadGeneration: 1,
            currentGeneration: { 1 }
        )

        XCTAssertEqual(result.path, .v2_rpc)
        XCTAssertFalse(result.usedLegacyREST)
        XCTAssertEqual(profiles.profileCallCount, 0)
        XCTAssertEqual(profiles.statsCallCount, 1)
        XCTAssertEqual(rpc.callCount, 1)
    }

    @MainActor
    func testSessionFlagOffUsesLegacyRESTOnly() async throws {
        BackendV2FeatureFlags.setFlagForTests(.session, enabled: false)
        let viewer = ProfileID("viewer-1")
        let profiles = CountingProfileRepository()

        let result = try await SessionBootstrapLoader.load(
            viewerID: viewer,
            rpc: FixtureRPCClient(json: "{}"),
            profiles: profiles,
            detailCache: nil,
            forceNetwork: true,
            loadGeneration: 1,
            currentGeneration: { 1 }
        )

        XCTAssertEqual(result.path, .legacy_flag_off)
        XCTAssertTrue(result.usedLegacyREST)
        XCTAssertEqual(profiles.profileCallCount, 1)
        XCTAssertEqual(profiles.statsCallCount, 1)
        XCTAssertEqual(profiles.onboardingSnapshotCallCount, 1)
    }

    @MainActor
    func testSessionMissingRpcMarksUnavailableAndFallsBackOnce() async throws {
        BackendV2FeatureFlags.setFlagForTests(.session, enabled: true)
        let viewer = ProfileID("11111111-1111-1111-1111-111111111111")
        let profiles = CountingProfileRepository()
        let rpc = FailingRPCClient(message: "PGRST202 Could not find rpc_v1_session_bootstrap")

        let first = try await SessionBootstrapLoader.load(
            viewerID: viewer,
            rpc: rpc,
            profiles: profiles,
            detailCache: nil,
            forceNetwork: true,
            loadGeneration: 1,
            currentGeneration: { 1 }
        )
        XCTAssertEqual(first.path, .legacy_missing_rpc)

        profiles.resetCounts()
        let second = try await SessionBootstrapLoader.load(
            viewerID: viewer,
            rpc: rpc,
            profiles: profiles,
            detailCache: nil,
            forceNetwork: true,
            loadGeneration: 2,
            currentGeneration: { 2 }
        )
        XCTAssertEqual(second.path, .legacy_missing_rpc)
        XCTAssertEqual(rpc.callCount, 1, "Unavailable RPC must not repeat network call")
    }

    @MainActor
    func testSessionConcurrentCallersShareOneRPC() async throws {
        BackendV2FeatureFlags.setFlagForTests(.session, enabled: true)
        let viewer = ProfileID("11111111-1111-1111-1111-111111111111")
        let profiles = CountingProfileRepository()
        let rpc = FixtureRPCClient(json: BackendV2ContractFixtures.session)

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
    }

    @MainActor
    func testDashboardV2DecodeAndApplySeedsStores() async throws {
        BackendV2FeatureFlags.setFlagForTests(.dashboard, enabled: true)
        let viewer = ProfileID("11111111-1111-1111-1111-111111111111")
        let detailCache = DetailPresentationCache()
        SessionAccountsStore.shared.invalidate()
        SessionOwnerTradesStore.shared.invalidate()

        let bootstrap: DashboardBootstrapV1 = try decodeFixture(BackendV2ContractFixtures.dashboard)
        let applied = try await DashboardBootstrapApplier.apply(
            bootstrap,
            expectedViewerID: viewer.rawValue,
            detailCache: detailCache
        )

        XCTAssertEqual(applied.accounts.count, 1)
        XCTAssertFalse(applied.trades.isEmpty)
        XCTAssertNotNil(SessionAccountsStore.shared.cached(for: viewer))
        XCTAssertNotNil(SessionOwnerTradesStore.shared.cached(for: viewer))
    }

    func testRpcCompatDetectsMissingFunction() {
        let err = BackendV2RPCError.transport("PGRST202 Could not find rpc_v1_dashboard_bootstrap")
        XCTAssertTrue(BackendV2RpcCompat.isRpcUnavailable(err, rpcName: "rpc_v1_dashboard_bootstrap"))
        XCTAssertFalse(BackendV2RpcCompat.isTransientFailure(err, rpcName: "rpc_v1_dashboard_bootstrap"))
    }

    func testContractVersionMismatchIsUnavailable() {
        let err = BackendV2RPCError.contractVersionMismatch(expected: "v1", got: "v0")
        XCTAssertTrue(BackendV2RpcCompat.isRpcUnavailable(err, rpcName: "rpc_v1_session_bootstrap"))
    }

    private func decodeFixture<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}

private final class CountingProfileRepository: ProfileRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _profileCallCount = 0
    private var _statsCallCount = 0
    private var _onboardingSnapshotCallCount = 0

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

    var onboardingSnapshotCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _onboardingSnapshotCallCount
    }

    func resetCounts() {
        lock.lock()
        _profileCallCount = 0
        _statsCallCount = 0
        _onboardingSnapshotCallCount = 0
        lock.unlock()
    }

    private func incrementProfile() {
        lock.lock()
        _profileCallCount += 1
        lock.unlock()
    }

    private func incrementStats() {
        lock.lock()
        _statsCallCount += 1
        lock.unlock()
    }

    private func incrementOnboardingSnapshot() {
        lock.lock()
        _onboardingSnapshotCallCount += 1
        lock.unlock()
    }

    func currentUser() async throws -> User {
        User(id: UserID("viewer-1"), email: nil, createdAt: .now)
    }

    func profile(id: ProfileID) async throws -> Profile {
        incrementProfile()
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
        incrementStats()
        return ProfileStats(
            profileID: profileID,
            followerCount: 0,
            followingCount: 0,
            postCount: 0,
            tradeCount: 0,
            publicTradeCount: 0
        )
    }

    func onboardingSnapshot(for profileID: ProfileID) async throws -> ProfileOnboardingSnapshot {
        incrementOnboardingSnapshot()
        return ProfileOnboardingSnapshot(
            profileID: profileID,
            username: "viewer",
            onboardingCompleted: true
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

private final class FixtureRPCClient: RPCClient, @unchecked Sendable {
    let json: String
    private(set) var callCount = 0

    init(json: String) {
        self.json = json
    }

    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        callCount += 1
        return Data(json.utf8)
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        callCount += 1
        return Data(json.utf8)
    }
}

private final class FailingRPCClient: RPCClient, @unchecked Sendable {
    let message: String
    private(set) var callCount = 0

    init(message: String) {
        self.message = message
    }

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
        result.reserveCapacity(count)
        for element in self {
            result.append(try await transform(element))
        }
        return result
    }
}
