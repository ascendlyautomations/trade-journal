import XCTest
@testable import TradeTraxs

@MainActor
final class ViewerSyncReconciliationTests: XCTestCase {
    private let viewerID = "11111111-1111-1111-1111-111111111111"

    override func tearDown() {
        BackendV2FeatureFlags.resetFlagsForTests()
        BackendV2BootstrapDiskCache.clearAll()
        ViewerSyncStateDiskCache.clear()
        SyncStateProbe.resetForTesting()
        ViewerSyncReconciliationCoordinator.shared.reset()
        let group = DispatchGroup()
        group.enter()
        Task {
            await BackendV2SingleFlight.shared.clear()
            await BackendV2RpcAvailability.shared.clear()
            group.leave()
        }
        group.wait()
        super.tearDown()
    }

    func testFingerprintComparisonDetectsTradeEdit() {
        let base = ViewerSyncStateV1.TradesDomain(count: 10, max_created_at: "2026-01-01T00:00:00.000Z", checksum: 100)
        let edited = ViewerSyncStateV1.TradesDomain(count: 10, max_created_at: "2026-01-01T00:00:00.000Z", checksum: 101)
        let local = ViewerSyncStateFingerprints(
            viewerID: viewerID,
            response: ViewerSyncStateV1(
                meta: BootstrapMetaV1(contract_version: "v1", server_time: "t", viewer_id: viewerID),
                data: .init(
                    trades: base,
                    accounts: .init(count: 1, max_created_at: nil, checksum: 1),
                    profile: .init(checksum: "p")
                )
            )
        )
        let server = ViewerSyncStateFingerprints(
            viewerID: viewerID,
            response: ViewerSyncStateV1(
                meta: BootstrapMetaV1(contract_version: "v1", server_time: "t", viewer_id: viewerID),
                data: .init(
                    trades: edited,
                    accounts: .init(count: 1, max_created_at: nil, checksum: 1),
                    profile: .init(checksum: "p")
                )
            )
        )
        XCTAssertEqual(local.changedDomains(comparedTo: server), [.trades])
    }

    func testFingerprintComparisonDetectsDelete() {
        let before = ViewerSyncStateV1.TradesDomain(count: 5, max_created_at: "2026-01-01T00:00:00.000Z", checksum: 50)
        let after = ViewerSyncStateV1.TradesDomain(count: 4, max_created_at: "2026-01-01T00:00:00.000Z", checksum: 40)
        let local = makeFingerprints(trades: before)
        let server = makeFingerprints(trades: after)
        XCTAssertEqual(local.changedDomains(comparedTo: server), [.trades])
    }

    func testSoftStaleMatchingSyncStateSkipsDashboardBootstrap() async throws {
        BackendV2FeatureFlags.setFlagForTests(.session, enabled: true)
        BackendV2FeatureFlags.setFlagForTests(.dashboard, enabled: true)
        BackendV2FeatureFlags.setFlagForTests(.viewerSyncState, enabled: true)

        let dashboard: DashboardBootstrapV1 = try JSONDecoder().decode(
            DashboardBootstrapV1.self,
            from: Data(ViewerSyncReconciliationFixtures.dashboard.utf8)
        )
        let staleDate = Date().addingTimeInterval(-(11 * 60))
        BackendV2BootstrapDiskCache.saveDashboardForTesting(
            dashboard,
            viewerID: viewerID,
            savedAt: staleDate
        )

        let fingerprints = ViewerSyncStateFingerprints(
            viewerID: viewerID,
            response: try JSONDecoder().decode(
                ViewerSyncStateV1.self,
                from: Data(ViewerSyncReconciliationFixtures.syncStateMatching.utf8)
            )
        )
        ViewerSyncStateDiskCache.save(fingerprints)

        let rpc = SyncStateRoutingRPCClient(
            syncStateJSON: ViewerSyncReconciliationFixtures.syncStateMatching,
            dashboardJSON: ViewerSyncReconciliationFixtures.dashboard,
            sessionJSON: BackendV2ContractFixtures.session
        )
        let detailCache = DetailPresentationCache()

        _ = try await DashboardBootstrapLoader.load(
            viewerID: ProfileID(viewerID),
            rpc: rpc,
            detailCache: detailCache,
            forceNetwork: false,
            loadGeneration: 1,
            currentGeneration: { 1 }
        )

        await ViewerSyncReconciliationCoordinator.shared.awaitIdleForTesting()

        XCTAssertEqual(rpc.count(for: BackendV2Versioning.RPCName.viewerSyncState.rawValue), 1)
        XCTAssertEqual(rpc.count(for: BackendV2Versioning.RPCName.dashboard.rawValue), 0)
        XCTAssertEqual(SyncStateProbe.lastReconcileResult(), "UNCHANGED")
        XCTAssertEqual(SyncStateProbe.dashboardSkipCount(), 1)
    }

    func testSoftStaleMismatchRefreshesDashboard() async throws {
        BackendV2FeatureFlags.setFlagForTests(.session, enabled: true)
        BackendV2FeatureFlags.setFlagForTests(.dashboard, enabled: true)
        BackendV2FeatureFlags.setFlagForTests(.viewerSyncState, enabled: true)

        let dashboard: DashboardBootstrapV1 = try JSONDecoder().decode(
            DashboardBootstrapV1.self,
            from: Data(ViewerSyncReconciliationFixtures.dashboard.utf8)
        )
        let staleDate = Date().addingTimeInterval(-(11 * 60))
        BackendV2BootstrapDiskCache.saveDashboardForTesting(
            dashboard,
            viewerID: viewerID,
            savedAt: staleDate
        )

        let localFingerprints = ViewerSyncStateFingerprints(
            viewerID: viewerID,
            response: try JSONDecoder().decode(
                ViewerSyncStateV1.self,
                from: Data(ViewerSyncReconciliationFixtures.syncStateMatching.utf8)
            )
        )
        ViewerSyncStateDiskCache.save(localFingerprints)

        let rpc = SyncStateRoutingRPCClient(
            syncStateJSON: ViewerSyncReconciliationFixtures.syncStateTradesChanged,
            dashboardJSON: ViewerSyncReconciliationFixtures.dashboard,
            sessionJSON: BackendV2ContractFixtures.session
        )
        let detailCache = DetailPresentationCache()

        _ = try await DashboardBootstrapLoader.load(
            viewerID: ProfileID(viewerID),
            rpc: rpc,
            detailCache: detailCache,
            forceNetwork: false,
            loadGeneration: 1,
            currentGeneration: { 1 }
        )

        await ViewerSyncReconciliationCoordinator.shared.awaitIdleForTesting()

        XCTAssertEqual(rpc.count(for: BackendV2Versioning.RPCName.viewerSyncState.rawValue), 2)
        XCTAssertEqual(rpc.count(for: BackendV2Versioning.RPCName.dashboard.rawValue), 1)
        XCTAssertEqual(SyncStateProbe.lastReconcileResult(), "CHANGED")
    }

    func testViewerSyncFlagOffSkipsSyncRPC() async throws {
        BackendV2FeatureFlags.setFlagForTests(.session, enabled: true)
        BackendV2FeatureFlags.setFlagForTests(.dashboard, enabled: true)
        BackendV2FeatureFlags.setFlagForTests(.viewerSyncState, enabled: false)

        let dashboard: DashboardBootstrapV1 = try JSONDecoder().decode(
            DashboardBootstrapV1.self,
            from: Data(ViewerSyncReconciliationFixtures.dashboard.utf8)
        )
        BackendV2BootstrapDiskCache.saveDashboardForTesting(
            dashboard,
            viewerID: viewerID,
            savedAt: Date().addingTimeInterval(-(11 * 60))
        )

        let rpc = SyncStateRoutingRPCClient(
            syncStateJSON: ViewerSyncReconciliationFixtures.syncStateMatching,
            dashboardJSON: ViewerSyncReconciliationFixtures.dashboard,
            sessionJSON: BackendV2ContractFixtures.session
        )
        let detailCache = DetailPresentationCache()

        _ = try await DashboardBootstrapLoader.load(
            viewerID: ProfileID(viewerID),
            rpc: rpc,
            detailCache: detailCache,
            forceNetwork: false,
            loadGeneration: 1,
            currentGeneration: { 1 }
        )

        await ViewerSyncReconciliationCoordinator.shared.awaitIdleForTesting()

        XCTAssertEqual(rpc.count(for: BackendV2Versioning.RPCName.viewerSyncState.rawValue), 0)
        XCTAssertEqual(rpc.count(for: BackendV2Versioning.RPCName.dashboard.rawValue), 0)
        XCTAssertEqual(SyncStateProbe.lastReconcileResult(), "UNCHANGED")
    }

    private func makeFingerprints(trades: ViewerSyncStateV1.TradesDomain) -> ViewerSyncStateFingerprints {
        ViewerSyncStateFingerprints(
            viewerID: viewerID,
            response: ViewerSyncStateV1(
                meta: BootstrapMetaV1(contract_version: "v1", server_time: "t", viewer_id: viewerID),
                data: .init(
                    trades: trades,
                    accounts: .init(count: 1, max_created_at: nil, checksum: 1),
                    profile: .init(checksum: "p")
                )
            )
        )
    }
}

private enum ViewerSyncReconciliationFixtures {
    static let dashboard = BackendV2ContractFixtures.dashboard

    static let syncStateMatching = """
    {"meta":{"contract_version":"v1","server_time":"2026-08-19T20:00:00.000Z","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"trades":{"count":1,"max_created_at":"2026-08-01T12:00:00.000Z","checksum":4242},"accounts":{"count":1,"max_created_at":null,"checksum":1313},"profile":{"checksum":"deadbeef"}}}
    """

    static let syncStateTradesChanged = """
    {"meta":{"contract_version":"v1","server_time":"2026-08-19T20:00:00.000Z","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"trades":{"count":2,"max_created_at":"2026-08-02T12:00:00.000Z","checksum":9999},"accounts":{"count":1,"max_created_at":null,"checksum":1313},"profile":{"checksum":"deadbeef"}}}
    """
}

private final class SyncStateRoutingRPCClient: RPCClient, @unchecked Sendable {
    let syncStateJSON: String
    let dashboardJSON: String
    let sessionJSON: String
    private var counts: [String: Int] = [:]
    private let lock = NSLock()

    init(syncStateJSON: String, dashboardJSON: String, sessionJSON: String) {
        self.syncStateJSON = syncStateJSON
        self.dashboardJSON = dashboardJSON
        self.sessionJSON = sessionJSON
    }

    func count(for rpcName: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[rpcName, default: 0]
    }

    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        try await call(functionName: functionName, jsonBody: Data("{}".utf8))
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        TestLock.withLock(lock) {
            counts[functionName, default: 0] += 1
        }
        switch functionName {
        case BackendV2Versioning.RPCName.viewerSyncState.rawValue:
            return Data(syncStateJSON.utf8)
        case BackendV2Versioning.RPCName.dashboard.rawValue:
            return Data(dashboardJSON.utf8)
        case BackendV2Versioning.RPCName.session.rawValue:
            return Data(sessionJSON.utf8)
        default:
            throw BackendV2RPCError.notImplemented(functionName)
        }
    }
}
