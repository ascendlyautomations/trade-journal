import Foundation

nonisolated protocol AnalyticsReconciliationExecuting: Sendable {
    func reconcileDashboard(
        viewerID: ProfileID,
        hintRevision: Int64?,
        generation: UInt64
    ) async throws -> AnalyticsDashboardReconcileResult

    func reconcileCalendar(
        intent: AnalyticsCalendarRangeIntent,
        generation: UInt64
    ) async throws -> AnalyticsCalendarReconcileResult

    func reconcileAccountCharts(
        intent: AccountChartsReconcileIntent,
        generation: UInt64
    ) async throws
}

/// Fallback when production executor is not installed (tests / pre-bind).
nonisolated struct NoOpAnalyticsReconciliationExecutor: AnalyticsReconciliationExecuting {
    func reconcileDashboard(
        viewerID: ProfileID,
        hintRevision: Int64?,
        generation: UInt64
    ) async throws -> AnalyticsDashboardReconcileResult {
        _ = viewerID
        _ = hintRevision
        _ = generation
        return AnalyticsDashboardReconcileResult(serverRevision: hintRevision ?? 0, elapsedMs: 0)
    }

    func reconcileCalendar(
        intent: AnalyticsCalendarRangeIntent,
        generation: UInt64
    ) async throws -> AnalyticsCalendarReconcileResult {
        _ = generation
        return AnalyticsCalendarReconcileResult(
            serverRevision: intent.targetRevision ?? 0,
            rowsWritten: 0,
            elapsedMs: 0
        )
    }

    func reconcileAccountCharts(
        intent: AccountChartsReconcileIntent,
        generation: UInt64
    ) async throws {
        _ = intent
        _ = generation
    }
}
