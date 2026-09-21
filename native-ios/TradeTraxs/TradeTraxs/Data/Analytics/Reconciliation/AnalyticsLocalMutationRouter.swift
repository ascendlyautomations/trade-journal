import Foundation

nonisolated enum AnalyticsLocalMutationRouter {
    static func submit(
        kind: AnalyticsLocalMutationKind,
        scope: AnalyticalMutationScope,
        bulkSource: AnalyticsBulkImportSource? = nil
    ) {
        guard AnalyticsReconciliationGate.isEnabled else { return }
        AnalyticsReconciliationProbe.signal(
            source: "localMutation",
            viewer: scope.viewerID.rawValue,
            revision: -1
        )
        AnalyticsReconciliationProbe.localScope(
            kind: bulkSource?.rawValue ?? kind.rawValue,
            viewer: scope.viewerID.rawValue,
            oldDay: scope.oldCalendarDay,
            newDay: scope.newCalendarDay,
            oldAccount: scope.oldAccountID,
            newAccount: scope.newAccountID,
            oldMode: scope.oldMode,
            newMode: scope.newMode
        )
        Task {
            await MainActor.run {
                if scope.requestsDashboardBootstrap || !scope.accountChartAccountIDs.isEmpty {
                    DashboardAnalyticsAccountChartsStore.shared.invalidate()
                }
                if kind == .bulk {
                    CalendarAnalyticsSessionStore.shared.invalidate()
                }
            }
            await AnalyticsReconciliationCoordinator.shared.receive(.localMutation(scope))
        }
    }

    @MainActor
    static func visibleMonthBoundsForBulk() -> (start: String, end: String)? {
        AnalyticsCalendarReconciliationContext.shared.visibleMonthBounds
    }
}

@MainActor
final class AnalyticsCalendarReconciliationContext {
    static let shared = AnalyticsCalendarReconciliationContext()
    var visibleMonthBounds: (start: String, end: String)?

    private init() {}
}
