import Foundation

nonisolated enum AnalyticsReconciliationUIApply {
    static let dashboardCommittedNotification = Notification.Name("AnalyticsReconciliation.dashboardCommitted")
    static let calendarCommittedNotification = Notification.Name("AnalyticsReconciliation.calendarCommitted")

    static func postDashboardCommitted(
        viewerID: ProfileID,
        serverRevision: Int64,
        viewerGeneration: UInt64
    ) async {
        await MainActor.run {
            NotificationCenter.default.post(
                name: dashboardCommittedNotification,
                object: nil,
                userInfo: [
                    "viewerID": viewerID.rawValue,
                    "serverRevision": serverRevision,
                    "viewerGeneration": viewerGeneration,
                ]
            )
            AnalyticsReconciliationProbe.uiApplied(
                domain: "dashboard",
                revision: serverRevision,
                elapsedMs: 0
            )
        }
    }

    static func postCalendarCommitted(
        viewerID: ProfileID,
        intent: AnalyticsCalendarRangeIntent,
        serverRevision: Int64,
        viewerGeneration: UInt64
    ) async {
        await MainActor.run {
            NotificationCenter.default.post(
                name: calendarCommittedNotification,
                object: nil,
                userInfo: [
                    "viewerID": viewerID.rawValue,
                    "serverRevision": serverRevision,
                    "viewerGeneration": viewerGeneration,
                    "startDate": intent.startDate,
                    "endDate": intent.endDate,
                    "accountScope": intent.accountScope,
                    "modeScope": intent.modeScope,
                ]
            )
            AnalyticsReconciliationProbe.uiApplied(
                domain: "calendar",
                revision: serverRevision,
                elapsedMs: 0
            )
        }
    }
}
