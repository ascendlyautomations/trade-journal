import XCTest
@testable import TradeTraxs

final class AnalyticsReconciliationCoordinatorTests: XCTestCase {
    private var viewerA: ProfileID { ProfileID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa") }
    private var viewerB: ProfileID { ProfileID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb") }

    // MARK: - Revision

    func testFirstRevisionAccepted() async {
        let harness = await makeHarness(seed: 0)
        await harness.coordinator.bindViewer(viewerA)
        await harness.coordinator.receive(.remoteRevision(serverRevision: 21))
        await harness.coordinator.awaitIdleForTesting()
        let snap = await harness.coordinator.snapshotForTesting()
        XCTAssertEqual(snap.lastAppliedRevision, 21)
    }

    func testLocalMutationAdoptsUnknownServerRevision() async {
        let harness = await makeHarness(seed: 20)
        await harness.coordinator.bindViewer(viewerA)
        await harness.coordinator.receive(
            .localMutation(
                AnalyticalMutationScope(
                    viewerID: viewerA,
                    requestsDashboardBootstrap: true
                )
            )
        )
        await harness.coordinator.awaitIdleForTesting()
        let snap = await harness.coordinator.snapshotForTesting()
        XCTAssertEqual(snap.lastAppliedRevision, 21)
    }

    func testLocalRevisionThenRemoteDuplicateSuppresses() async {
        let harness = await makeHarness(seed: 0)
        await harness.coordinator.bindViewer(viewerA)
        await harness.coordinator.receive(
            .localMutation(
                AnalyticalMutationScope(
                    viewerID: viewerA,
                    requestsDashboardBootstrap: true
                )
            )
        )
        await harness.coordinator.awaitIdleForTesting()
        await harness.coordinator.receive(.remoteRevision(serverRevision: 21))
        await harness.coordinator.awaitIdleForTesting()
        let snap = await harness.coordinator.snapshotForTesting()
        XCTAssertEqual(snap.lastAppliedRevision, 21)
        XCTAssertEqual(harness.executor.dashboardRevisions.count, 1)
    }

    func testDuplicateRevisionSuppressed() async {
        let harness = await makeHarness(seed: 0)
        await harness.coordinator.bindViewer(viewerA)
        await harness.coordinator.receive(.remoteRevision(serverRevision: 10))
        await harness.coordinator.awaitIdleForTesting()
        await harness.coordinator.receive(.remoteRevision(serverRevision: 10))
        await harness.coordinator.awaitIdleForTesting()
        let snap = await harness.coordinator.snapshotForTesting()
        XCTAssertEqual(snap.lastAppliedRevision, 10)
        XCTAssertEqual(harness.executor.dashboardRevisions, [10])
    }

    func testOlderRevisionSuppressed() async {
        let harness = await makeHarness(seed: 0)
        await harness.coordinator.bindViewer(viewerA)
        await harness.coordinator.receive(.remoteRevision(serverRevision: 20))
        await harness.coordinator.awaitIdleForTesting()
        await harness.coordinator.receive(.remoteRevision(serverRevision: 15))
        await harness.coordinator.awaitIdleForTesting()
        let snap = await harness.coordinator.snapshotForTesting()
        XCTAssertEqual(snap.lastAppliedRevision, 20)
        XCTAssertEqual(harness.executor.dashboardRevisions, [20])
    }

    func testMultiplePendingRevisionsCollapseToMax() async {
        let harness = await makeHarness(seed: 0)
        await harness.coordinator.bindViewer(viewerA)
        await harness.coordinator.receive(.remoteRevision(serverRevision: 21))
        await harness.coordinator.receive(.remoteRevision(serverRevision: 22))
        await harness.coordinator.receive(.remoteRevision(serverRevision: 21))
        await harness.coordinator.receive(.remoteRevision(serverRevision: 25))
        await harness.coordinator.receive(.remoteRevision(serverRevision: 23))
        await harness.coordinator.awaitIdleForTesting()
        let snap = await harness.coordinator.snapshotForTesting()
        XCTAssertEqual(snap.lastAppliedRevision, 25)
        XCTAssertEqual(harness.executor.dashboardRevisions.last, 25)
        XCTAssertLessThanOrEqual(harness.executor.dashboardRevisions.count, 2)
    }

    func testR20InFlightThenR21RunsAfterward() async {
        let harness = await makeHarness(seed: 0)
        await harness.coordinator.bindViewer(viewerA)
        harness.executor.blockNextDashboardCount = 1
        await harness.coordinator.receive(.remoteRevision(serverRevision: 20))
        try? await Task.sleep(for: .milliseconds(50))
        await harness.coordinator.receive(.remoteRevision(serverRevision: 21))
        harness.executor.releaseBlockedDashboard()
        await harness.coordinator.awaitIdleForTesting()
        XCTAssertEqual(harness.executor.dashboardRevisions, [20, 21])
        let snap = await harness.coordinator.snapshotForTesting()
        XCTAssertEqual(snap.lastAppliedRevision, 21)
    }

    func testR20InFlightPlusR21R22OnlyNewestFollowUp() async {
        let harness = await makeHarness(seed: 0)
        await harness.coordinator.bindViewer(viewerA)
        harness.executor.blockNextDashboardCount = 1
        await harness.coordinator.receive(.remoteRevision(serverRevision: 20))
        try? await Task.sleep(for: .milliseconds(50))
        await harness.coordinator.receive(.remoteRevision(serverRevision: 21))
        await harness.coordinator.receive(.remoteRevision(serverRevision: 22))
        harness.executor.releaseBlockedDashboard()
        await harness.coordinator.awaitIdleForTesting()
        XCTAssertEqual(harness.executor.dashboardRevisions, [20, 22])
        let snap = await harness.coordinator.snapshotForTesting()
        XCTAssertEqual(snap.lastAppliedRevision, 22)
    }

    func testCompletionNeverDecreasesRevision() async {
        let harness = await makeHarness(seed: 10)
        await harness.coordinator.bindViewer(viewerA)
        await harness.coordinator.receive(.remoteRevision(serverRevision: 12))
        await harness.coordinator.awaitIdleForTesting()
        await harness.coordinator.receive(.remoteRevision(serverRevision: 8))
        await harness.coordinator.awaitIdleForTesting()
        let snap = await harness.coordinator.snapshotForTesting()
        XCTAssertEqual(snap.lastAppliedRevision, 12)
    }

    func testFailureDoesNotAdvanceRevision() async {
        let harness = await makeHarness(seed: 0)
        await harness.coordinator.bindViewer(viewerA)
        harness.executor.failDashboardRevision = 30
        await harness.coordinator.receive(.remoteRevision(serverRevision: 30))
        await harness.coordinator.awaitIdleForTesting()
        let snap = await harness.coordinator.snapshotForTesting()
        XCTAssertEqual(snap.lastAppliedRevision, 0)
        XCTAssertEqual(snap.maxPendingRevision, 30)
    }

    func testNewerRevisionRetainedAfterFailure() async {
        let harness = await makeHarness(seed: 0)
        await harness.coordinator.bindViewer(viewerA)
        harness.executor.failDashboardRevision = 30
        await harness.coordinator.receive(.remoteRevision(serverRevision: 30))
        await harness.coordinator.awaitIdleForTesting()
        harness.executor.failDashboardRevision = nil
        await harness.coordinator.receive(.remoteRevision(serverRevision: 31))
        await harness.coordinator.awaitIdleForTesting()
        let snap = await harness.coordinator.snapshotForTesting()
        XCTAssertEqual(snap.lastAppliedRevision, 31)
    }

    // MARK: - Viewer

    func testLogoutInvalidatesInFlightToken() async {
        let harness = await makeHarness(seed: 0)
        await harness.coordinator.bindViewer(viewerA)
        harness.executor.blockNextDashboardCount = 1
        await harness.coordinator.receive(.remoteRevision(serverRevision: 40))
        try? await Task.sleep(for: .milliseconds(50))
        await harness.coordinator.reset()
        harness.executor.releaseBlockedDashboard()
        await harness.coordinator.awaitIdleForTesting()
        let snap = await harness.coordinator.snapshotForTesting()
        XCTAssertNil(snap.viewerID)
        XCTAssertEqual(snap.lastAppliedRevision, 0)
    }

    func testViewerACompletionCannotCommitToViewerB() async {
        let harness = await makeHarness(seed: 0)
        await harness.coordinator.bindViewer(viewerA)
        harness.executor.blockNextDashboardCount = 1
        await harness.coordinator.receive(.remoteRevision(serverRevision: 50))
        try? await Task.sleep(for: .milliseconds(50))
        await harness.coordinator.bindViewer(viewerB)
        harness.executor.releaseBlockedDashboard()
        await harness.coordinator.awaitIdleForTesting()
        let snap = await harness.coordinator.snapshotForTesting()
        XCTAssertEqual(snap.viewerID, viewerB)
        XCTAssertEqual(snap.lastAppliedRevision, 0)
    }

    func testPendingIntentsRemovedOnViewerSwitch() async {
        let harness = await makeHarness(seed: 0)
        await harness.coordinator.bindViewer(viewerA)
        await harness.coordinator.receive(
            .localMutation(
                AnalyticalMutationScope(
                    viewerID: viewerA,
                    calendarRanges: [
                        calendarIntent(viewer: viewerA, start: "2025-09-10", end: "2025-09-10")
                    ],
                    requestsDashboardBootstrap: true
                )
            )
        )
        await harness.coordinator.bindViewer(viewerB)
        let snap = await harness.coordinator.snapshotForTesting()
        XCTAssertTrue(snap.calendarIntents.isEmpty)
        XCTAssertNil(snap.dashboardIntent)
    }

    func testSameNumericRevisionIsolatedAcrossViewers() async {
        let harnessA = await makeHarness(seed: 0)
        await harnessA.coordinator.bindViewer(viewerA)
        await harnessA.coordinator.receive(.remoteRevision(serverRevision: 7))
        await harnessA.coordinator.awaitIdleForTesting()

        let harnessB = await makeHarness(seed: 0)
        await harnessB.coordinator.bindViewer(viewerB)
        await harnessB.coordinator.receive(.remoteRevision(serverRevision: 7))
        await harnessB.coordinator.awaitIdleForTesting()

        let snapA = await harnessA.coordinator.snapshotForTesting()
        let snapB = await harnessB.coordinator.snapshotForTesting()
        XCTAssertEqual(snapA.lastAppliedRevision, 7)
        XCTAssertEqual(snapB.lastAppliedRevision, 7)
        XCTAssertEqual(harnessA.executor.dashboardRevisions, [7])
        XCTAssertEqual(harnessB.executor.dashboardRevisions, [7])
    }

    // MARK: - Calendar coalescing

    func testOverlappingCalendarRangesMerge() {
        let viewer = viewerA
        let merged = AnalyticsCalendarRangeCoalescing.merge([
            calendarIntent(viewer: viewer, start: "2025-09-10", end: "2025-09-12"),
            calendarIntent(viewer: viewer, start: "2025-09-11", end: "2025-09-14")
        ])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].startDate, "2025-09-10")
        XCTAssertEqual(merged[0].endDate, "2025-09-14")
    }

    func testAdjacentCalendarRangesMerge() {
        let viewer = viewerA
        let merged = AnalyticsCalendarRangeCoalescing.merge([
            calendarIntent(viewer: viewer, start: "2025-09-10", end: "2025-09-10"),
            calendarIntent(viewer: viewer, start: "2025-09-11", end: "2025-09-11")
        ])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].startDate, "2025-09-10")
        XCTAssertEqual(merged[0].endDate, "2025-09-11")
    }

    func testDifferentAccountScopesDoNotMerge() {
        let viewer = viewerA
        let merged = AnalyticsCalendarRangeCoalescing.merge([
            calendarIntent(
                viewer: viewer,
                start: "2025-09-10",
                end: "2025-09-10",
                accountScope: "acct-a"
            ),
            calendarIntent(
                viewer: viewer,
                start: "2025-09-11",
                end: "2025-09-11",
                accountScope: "acct-b"
            )
        ])
        XCTAssertEqual(merged.count, 2)
    }

    func testDifferentModeScopesDoNotMerge() {
        let viewer = viewerA
        let merged = AnalyticsCalendarRangeCoalescing.merge([
            calendarIntent(
                viewer: viewer,
                start: "2025-09-10",
                end: "2025-09-10",
                modeScope: "eval"
            ),
            calendarIntent(
                viewer: viewer,
                start: "2025-09-11",
                end: "2025-09-11",
                modeScope: "funded"
            )
        ])
        XCTAssertEqual(merged.count, 2)
    }

    func testCrossMonthBoundedRangeSupported() {
        let viewer = viewerA
        let merged = AnalyticsCalendarRangeCoalescing.merge([
            calendarIntent(viewer: viewer, start: "2025-08-31", end: "2025-08-31"),
            calendarIntent(viewer: viewer, start: "2025-09-01", end: "2025-09-01")
        ])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].startDate, "2025-08-31")
        XCTAssertEqual(merged[0].endDate, "2025-09-01")
    }

    // MARK: - Dashboard / account charts

    func testDashboardRepeatedIntentsCollapseToNewestRevision() async {
        let harness = await makeHarness(seed: 0)
        await harness.coordinator.bindViewer(viewerA)
        await harness.coordinator.receive(.remoteRevision(serverRevision: 5))
        await harness.coordinator.receive(.remoteRevision(serverRevision: 9))
        await harness.coordinator.awaitIdleForTesting()
        let snap = await harness.coordinator.snapshotForTesting()
        XCTAssertEqual(snap.lastAppliedRevision, 9)
        XCTAssertEqual(harness.executor.dashboardRevisions, [9])
    }

    func testAccountChartsDedupeSameAccount() async {
        let harness = await makeHarness(seed: 0)
        await harness.coordinator.bindViewer(viewerA)
        await harness.coordinator.receive(
            .localMutation(
                AnalyticalMutationScope(
                    viewerID: viewerA,
                    accountChartAccountIDs: ["acct-a", "acct-a"]
                )
            )
        )
        await harness.coordinator.receive(.remoteRevision(serverRevision: 3))
        await harness.coordinator.awaitIdleForTesting()
        XCTAssertEqual(harness.executor.accountChartAccounts, ["acct-a"])
    }

    func testAccountChartsAAndBRemainDistinct() async {
        let harness = await makeHarness(seed: 0)
        await harness.coordinator.bindViewer(viewerA)
        await harness.coordinator.receive(
            .localMutation(
                AnalyticalMutationScope(
                    viewerID: viewerA,
                    accountChartAccountIDs: ["acct-a", "acct-b"]
                )
            )
        )
        await harness.coordinator.receive(.remoteRevision(serverRevision: 3))
        await harness.coordinator.awaitIdleForTesting()
        XCTAssertEqual(Set(harness.executor.accountChartAccounts), Set(["acct-a", "acct-b"]))
    }

    func testReassignmentScopeRepresentsBothAccounts() async {
        let harness = await makeHarness(seed: 0)
        await harness.coordinator.bindViewer(viewerA)
        await harness.coordinator.receive(
            .localMutation(
                AnalyticalMutationScope(
                    viewerID: viewerA,
                    oldAccountID: "acct-a",
                    newAccountID: "acct-b",
                    accountChartAccountIDs: ["acct-a", "acct-b"]
                )
            )
        )
        let snap = await harness.coordinator.snapshotForTesting()
        XCTAssertEqual(snap.accountChartIntents.count, 2)
    }

    // MARK: - Lifecycle

    func testBindResetCancelRepairIntent() async {
        let harness = await makeHarness(seed: 5)
        await harness.coordinator.bindViewer(viewerA)
        var snap = await harness.coordinator.snapshotForTesting()
        XCTAssertEqual(snap.lastAppliedRevision, 5)

        await harness.coordinator.requestRepair(reason: .foreground)
        await harness.coordinator.reset()
        snap = await harness.coordinator.snapshotForTesting()
        XCTAssertNil(snap.viewerID)
        XCTAssertEqual(snap.lastAppliedRevision, 0)
    }

    // MARK: - Helpers

    private func calendarIntent(
        viewer: ProfileID,
        start: String,
        end: String,
        accountScope: String = AnalyticsScopeKeys.allAccountsQuery,
        modeScope: String = AnalyticsScopeKeys.allModesQuery,
        revision: Int64 = 0
    ) -> AnalyticsCalendarRangeIntent {
        AnalyticsCalendarRangeIntent(
            viewerID: viewer,
            startDate: start,
            endDate: end,
            accountScope: accountScope,
            modeScope: modeScope,
            targetRevision: revision
        )
    }

    private func makeHarness(seed: Int64) async -> TestHarness {
        let executor = RecordingAnalyticsReconciliationExecutor()
        let seeder = FixedAnalyticsRevisionSeeder(revision: seed)
        let coordinator = AnalyticsReconciliationCoordinator(
            executor: executor,
            revisionSeeder: seeder,
            coalescingPolicy: .immediate,
            clock: ImmediateAnalyticsReconciliationClock()
        )
        return TestHarness(coordinator: coordinator, executor: executor)
    }
}

private struct TestHarness {
    var coordinator: AnalyticsReconciliationCoordinator
    var executor: RecordingAnalyticsReconciliationExecutor
}

private struct FixedAnalyticsRevisionSeeder: AnalyticsRevisionSeeding {
    var revision: Int64
    func seedHighWaterRevision(viewerID: ProfileID) async -> AnalyticsRevisionSeed {
        AnalyticsRevisionSeed(highWaterRevision: revision, source: "test_fixed")
    }
}

private final class RecordingAnalyticsReconciliationExecutor: AnalyticsReconciliationExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var dashboardRevisions: [Int64] = []
    private(set) var accountChartAccounts: [String] = []
    private var blockRemaining = 0
    private var blockedContinuations: [CheckedContinuation<Void, Error>] = []
    var failDashboardRevision: Int64?

    var blockNextDashboardCount: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return blockRemaining
        }
        set {
            lock.lock()
            blockRemaining = newValue
            lock.unlock()
        }
    }

    func releaseBlockedDashboard() {
        lock.lock()
        blockRemaining = 0
        let batch = blockedContinuations
        blockedContinuations = []
        lock.unlock()
        for continuation in batch {
            continuation.resume()
        }
    }

    func reconcileDashboard(
        viewerID: ProfileID,
        hintRevision: Int64?,
        generation: UInt64
    ) async throws -> AnalyticsDashboardReconcileResult {
        _ = viewerID
        _ = generation
        let revision = hintRevision ?? 0
        lock.lock()
        dashboardRevisions.append(revision)
        let shouldBlock = blockRemaining > 0
        if shouldBlock {
            blockRemaining -= 1
        }
        lock.unlock()

        if shouldBlock {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                blockedContinuations.append(continuation)
                lock.unlock()
            }
        }
        if failDashboardRevision == revision {
            throw NSError(domain: "AnalyticsReconciliationTests", code: 1)
        }
        let applied = revision > 0 ? revision : 21
        return AnalyticsDashboardReconcileResult(serverRevision: applied, elapsedMs: 0)
    }

    func reconcileCalendar(
        intent: AnalyticsCalendarRangeIntent,
        generation: UInt64
    ) async throws -> AnalyticsCalendarReconcileResult {
        _ = generation
        return AnalyticsCalendarReconcileResult(
            serverRevision: intent.targetRevision ?? 21,
            rowsWritten: 0,
            elapsedMs: 0
        )
    }

    func reconcileAccountCharts(intent: AccountChartsReconcileIntent, generation: UInt64) async throws {
        lock.lock()
        accountChartAccounts.append(intent.normalizedAccountID)
        lock.unlock()
    }
}
