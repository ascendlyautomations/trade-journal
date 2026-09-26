import XCTest
@testable import TradeTraxs

final class Phase6DRealtimeAnalyticsTests: XCTestCase {
    private var viewerA: ProfileID { ProfileID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa") }

    @MainActor
    func testRemoteRevisionEnqueuesVisibleCalendarRange() async {
        AnalyticsCalendarReconciliationContext.shared.visibleMonthBounds = ("2025-09-01", "2025-09-30")
        defer { AnalyticsCalendarReconciliationContext.shared.visibleMonthBounds = nil }

        let harness = await makeHarness(seed: 0)
        await harness.coordinator.bindViewer(viewerA)
        await harness.coordinator.receive(.remoteRevision(serverRevision: 21))
        await harness.coordinator.awaitIdleForTesting()

        let snap = await harness.coordinator.snapshotForTesting()
        XCTAssertEqual(snap.lastAppliedRevision, 21)
        XCTAssertEqual(harness.executor.dashboardRevisions, [21])
        XCTAssertFalse(harness.executor.calendarIntents.isEmpty)
        XCTAssertEqual(harness.executor.calendarIntents.first?.startDate, "2025-09-01")
    }

    func testRemoteRevisionDoesNotEnqueuePerAccountChartRPCs() async {
        let harness = await makeHarness(seed: 0)
        await harness.coordinator.bindViewer(viewerA)
        await harness.coordinator.receive(.remoteRevision(serverRevision: 12))
        await harness.coordinator.awaitIdleForTesting()
        XCTAssertTrue(harness.executor.accountChartAccounts.isEmpty)
    }

    func testRemoteCalendarRepairDoesNotSweepWhenNoVisibleMonth() {
        let intents = AnalyticsRemoteCalendarRepair.intents(
            viewerID: viewerA,
            pendingRevision: 40,
            visibleMonth: nil,
            staleCoverages: [],
            maxStaleRanges: 3
        )
        XCTAssertTrue(intents.isEmpty)
    }

    func testRemoteCalendarRepairBoundsStaleCoverages() {
        let stale = [
            coverage(start: "2024-01-01", end: "2024-01-31", revision: 10),
            coverage(start: "2024-03-01", end: "2024-03-31", revision: 11),
            coverage(start: "2024-05-01", end: "2024-05-31", revision: 12),
            coverage(start: "2024-07-01", end: "2024-07-31", revision: 13),
        ]
        let intents = AnalyticsRemoteCalendarRepair.intents(
            viewerID: viewerA,
            pendingRevision: 40,
            visibleMonth: ("2025-09-01", "2025-09-30"),
            staleCoverages: stale,
            maxStaleRanges: 3
        )
        XCTAssertTrue(intents.contains { $0.startDate == "2025-09-01" })
        XCTAssertEqual(intents.count, 4, "Visible month plus three bounded stale ranges")
    }

    private func coverage(start: String, end: String, revision: Int64) -> AnalyticsRangeCoverageRecord {
        AnalyticsRangeCoverageRecord(
            viewer_id: viewerA.rawValue,
            domain: AnalyticsLocalSchema.domainCalendar,
            account_scope: AnalyticsScopeKeys.allAccountsQuery,
            mode_scope: AnalyticsScopeKeys.allModesQuery,
            start_date: start,
            end_date: end,
            server_revision: revision,
            fetched_at: "2025-01-01T00:00:00Z"
        )
    }

    private func makeHarness(seed: Int64) async -> RemoteTestHarness {
        let executor = RecordingRemoteAnalyticsExecutor()
        let seeder = Phase6DFixedAnalyticsRevisionSeeder(revision: seed)
        let coordinator = AnalyticsReconciliationCoordinator(
            executor: executor,
            revisionSeeder: seeder,
            coalescingPolicy: .immediate,
            clock: ImmediateAnalyticsReconciliationClock()
        )
        return RemoteTestHarness(coordinator: coordinator, executor: executor)
    }
}

private struct Phase6DFixedAnalyticsRevisionSeeder: AnalyticsRevisionSeeding {
    var revision: Int64
    func seedHighWaterRevision(viewerID: ProfileID) async -> AnalyticsRevisionSeed {
        AnalyticsRevisionSeed(highWaterRevision: revision, source: "phase6d_test")
    }
}

private struct RemoteTestHarness {
    var coordinator: AnalyticsReconciliationCoordinator
    var executor: RecordingRemoteAnalyticsExecutor
}

private final class RecordingRemoteAnalyticsExecutor: AnalyticsReconciliationExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var dashboardRevisions: [Int64] = []
    private(set) var calendarIntents: [AnalyticsCalendarRangeIntent] = []
    private(set) var accountChartAccounts: [String] = []

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
        _ = generation
        TestLock.withLock(lock) {
            calendarIntents.append(intent)
        }
        return AnalyticsCalendarReconcileResult(
            serverRevision: intent.targetRevision ?? 21,
            rowsWritten: 0,
            elapsedMs: 0
        )
    }

    func reconcileAccountCharts(intent: AccountChartsReconcileIntent, generation: UInt64) async throws {
        _ = generation
        TestLock.withLock(lock) {
            accountChartAccounts.append(intent.normalizedAccountID)
        }
    }
}
