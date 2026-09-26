import XCTest
@testable import TradeTraxs

final class Phase6ERevisionRepairTests: XCTestCase {
    private var viewerA: ProfileID { ProfileID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa") }
    private var viewerB: ProfileID { ProfileID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb") }

    override func setUp() async throws {
        BackendV2FeatureFlags.setFlagForTests(.analyticsRevisionRepair, enabled: true)
        BackendV2FeatureFlags.setFlagForTests(.dashboardAnalyticsV3, enabled: true)
        await AnalyticsRevisionRepairCoordinator.shared.reset()
        await AnalyticsReconciliationCoordinator.shared.reset()
    }

    override func tearDown() async throws {
        await AnalyticsRevisionRepairCoordinator.shared.reset()
        await AnalyticsRevisionRepairCoordinator.shared.resetTestingOverrides()
        await AnalyticsReconciliationCoordinator.shared.reset()
        BackendV2FeatureFlags.resetFlagsForTests()
        BackendV2FeatureFlags.enableProductionDefaultsForTests()
    }

    func testCurrentLocalServerNoReconcile() async throws {
        let harness = await makeHarness(localSeed: 20, serverRevision: 20)
        await harness.repair.bindViewer(viewerA)
        await harness.repair.awaitIdleForTesting()
        let snap = await AnalyticsReconciliationCoordinator.shared.snapshotForTesting()
        XCTAssertEqual(snap.lastAppliedRevision, 20)
        XCTAssertTrue(harness.executor.dashboardRevisions.isEmpty)
    }

    func testStaleServerTriggersReconcile() async throws {
        let harness = await makeHarness(localSeed: 20, serverRevision: 21)
        await harness.repair.bindViewer(viewerA)
        await harness.repair.awaitIdleForTesting()
        let snap = await AnalyticsReconciliationCoordinator.shared.snapshotForTesting()
        XCTAssertEqual(snap.lastAppliedRevision, 21)
        XCTAssertEqual(harness.executor.dashboardRevisions, [21])
    }

    func testLargeJumpSingleTarget() async throws {
        let harness = await makeHarness(localSeed: 20, serverRevision: 500)
        await harness.repair.bindViewer(viewerA)
        await harness.repair.awaitIdleForTesting()
        let snap = await AnalyticsReconciliationCoordinator.shared.snapshotForTesting()
        XCTAssertEqual(snap.lastAppliedRevision, 500)
        XCTAssertEqual(harness.executor.dashboardRevisions, [500])
    }

    func testNoDowngradeWhenServerLower() async throws {
        let harness = await makeHarness(localSeed: 20, serverRevision: 19)
        await harness.repair.bindViewer(viewerA)
        await harness.repair.awaitIdleForTesting()
        let snap = await AnalyticsReconciliationCoordinator.shared.snapshotForTesting()
        XCTAssertEqual(snap.lastAppliedRevision, 20)
        XCTAssertTrue(harness.executor.dashboardRevisions.isEmpty)
    }

    func testUnknownLocalRoutesServerRevision() async throws {
        let harness = await makeHarness(localSeed: nil, serverRevision: 20)
        await harness.repair.bindViewer(viewerA)
        await harness.repair.awaitIdleForTesting()
        let snap = await AnalyticsReconciliationCoordinator.shared.snapshotForTesting()
        XCTAssertEqual(snap.lastAppliedRevision, 20)
    }

    func testRepairCoalescesConcurrentRequests() async throws {
        var rpcCalls = 0
        let harness = await makeHarness(localSeed: 10, serverRevision: 15) {
            rpcCalls += 1
            try await Task.sleep(for: .milliseconds(80))
            return AnalyticsRevisionV1(revision: 15, updated_at: "2026-01-01T00:00:00Z")
        }
        await harness.repair.bindViewer(viewerA)
        await harness.repair.awaitIdleForTesting()
        try await Task.sleep(for: .milliseconds(2100))
        rpcCalls = 0
        await harness.repair.requestRepair(.foreground)
        await harness.repair.requestRepair(.networkRegain)
        await harness.repair.requestRepair(.realtimeReconnect)
        await harness.repair.awaitIdleForTesting(timeout: .seconds(3))
        XCTAssertEqual(rpcCalls, 1)
    }

    func testRepairAndRealtimeDuplicateCoalesced() async throws {
        let harness = await makeHarness(localSeed: 20, serverRevision: 21)
        await harness.repair.bindViewer(viewerA)
        await AnalyticsReconciliationCoordinator.shared.receive(.remoteRevision(serverRevision: 21))
        await harness.repair.awaitIdleForTesting()
        let snap = await AnalyticsReconciliationCoordinator.shared.snapshotForTesting()
        XCTAssertEqual(snap.lastAppliedRevision, 21)
        XCTAssertLessThanOrEqual(harness.executor.dashboardRevisions.count, 2)
    }

    func testViewerSwitchDiscardsStaleRepair() async throws {
        let slowHarness = await makeHarness(localSeed: 10, serverRevision: 99) {
            try await Task.sleep(for: .milliseconds(200))
            return AnalyticsRevisionV1(revision: 99, updated_at: "2026-01-01T00:00:00Z")
        }
        await slowHarness.repair.bindViewer(viewerA)
        await slowHarness.repair.requestRepair(.foreground)
        await AnalyticsReconciliationCoordinator.shared.bindViewer(viewerB)
        await slowHarness.repair.bindViewer(viewerB)
        await slowHarness.repair.awaitIdleForTesting(timeout: .seconds(3))
        let snap = await AnalyticsReconciliationCoordinator.shared.snapshotForTesting()
        XCTAssertEqual(snap.viewerID, viewerB)
    }

    func testFreshSuppressionSkipsBackToBackChecks() async throws {
        var rpcCalls = 0
        let harness = await makeHarness(localSeed: 10, serverRevision: 10) {
            rpcCalls += 1
            return AnalyticsRevisionV1(revision: 10, updated_at: "2026-01-01T00:00:00Z")
        }
        await harness.repair.bindViewer(viewerA)
        await harness.repair.awaitIdleForTesting()
        let first = rpcCalls
        await harness.repair.requestRepair(.foreground)
        await harness.repair.awaitIdleForTesting()
        XCTAssertEqual(rpcCalls, first)
    }

    private func makeHarness(
        localSeed: Int64?,
        serverRevision: Int64,
        loader: (@Sendable () async throws -> AnalyticsRevisionV1)? = nil
    ) async -> RepairTestHarness {
        let executor = Phase6ERecordingAnalyticsExecutor()
        let seeder: any AnalyticsRevisionSeeding
        if let localSeed {
            seeder = Phase6EFixedAnalyticsRevisionSeeder(revision: localSeed)
        } else {
            seeder = Phase6EUnknownAnalyticsRevisionSeeder()
        }
        await AnalyticsReconciliationCoordinator.shared.configureForTesting(
            executor: executor,
            revisionSeeder: seeder,
            coalescingPolicy: .immediate,
            clock: ImmediateAnalyticsReconciliationClock()
        )
        await AnalyticsReconciliationCoordinator.shared.bindViewer(viewerA)
        let detailCache = await MainActor.run { DetailPresentationCache() }
        AnalyticsReconciliationRuntime.configure(
            rpc: StubAnalyticsRevisionRPCClient(revision: serverRevision),
            detailCache: detailCache
        )
        await AnalyticsRevisionRepairCoordinator.shared.reset()
        await AnalyticsRevisionRepairCoordinator.shared.configureForTesting(
            revisionSeeder: seeder,
            revisionLoader: loader ?? {
                AnalyticsRevisionV1(
                    revision: serverRevision,
                    updated_at: "2026-01-01T00:00:00Z"
                )
            }
        )
        return RepairTestHarness(
            executor: executor,
            repair: AnalyticsRevisionRepairCoordinator.shared
        )
    }
}

private struct RepairTestHarness {
    var executor: Phase6ERecordingAnalyticsExecutor
    var repair: AnalyticsRevisionRepairCoordinator
}

private final class Phase6ERecordingAnalyticsExecutor: AnalyticsReconciliationExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var dashboardRevisions: [Int64] = []

    func reconcileDashboard(
        viewerID: ProfileID,
        hintRevision: Int64?,
        generation: UInt64
    ) async throws -> AnalyticsDashboardReconcileResult {
        _ = viewerID
        _ = generation
        let revision = hintRevision ?? 21
        TestLock.withLock(lock) {
            dashboardRevisions.append(revision)
        }
        return AnalyticsDashboardReconcileResult(serverRevision: revision, elapsedMs: 0)
    }

    func reconcileCalendar(
        intent: AnalyticsCalendarRangeIntent,
        generation: UInt64
    ) async throws -> AnalyticsCalendarReconcileResult {
        _ = intent
        _ = generation
        return AnalyticsCalendarReconcileResult(serverRevision: 0, rowsWritten: 0, elapsedMs: 0)
    }

    func reconcileAccountCharts(
        intent: AccountChartsReconcileIntent,
        generation: UInt64
    ) async throws {
        _ = intent
        _ = generation
    }
}

private struct Phase6EFixedAnalyticsRevisionSeeder: AnalyticsRevisionSeeding {
    var revision: Int64
    func seedHighWaterRevision(viewerID: ProfileID) async -> AnalyticsRevisionSeed {
        AnalyticsRevisionSeed(highWaterRevision: revision, source: "phase6e_test")
    }
}

private struct Phase6EUnknownAnalyticsRevisionSeeder: AnalyticsRevisionSeeding {
    func seedHighWaterRevision(viewerID: ProfileID) async -> AnalyticsRevisionSeed {
        AnalyticsRevisionSeed(highWaterRevision: 0, source: "unknown_zero")
    }
}

private struct StubAnalyticsRevisionRPCClient: RPCClient {
    var revision: Int64
    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        _ = functionName
        _ = parameters
        let payload = AnalyticsRevisionV1(revision: revision, updated_at: "2026-01-01T00:00:00Z")
        return try JSONEncoder().encode(payload)
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        _ = functionName
        _ = jsonBody
        let payload = AnalyticsRevisionV1(revision: revision, updated_at: "2026-01-01T00:00:00Z")
        return try JSONEncoder().encode(payload)
    }
}
