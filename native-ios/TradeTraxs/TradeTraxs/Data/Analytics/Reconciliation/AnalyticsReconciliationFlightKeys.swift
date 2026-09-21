import Foundation

/// Stable Backend V2 single-flight keys for future analytics RPC reconciliation (Phase 6C+).
nonisolated enum AnalyticsReconciliationFlightKeys {
    static func dashboardV3(viewerID: String) -> String {
        "analytics.dashboard.v3|viewer:\(viewerID)"
    }

    static func calendarRange(
        viewerID: String,
        start: String,
        end: String,
        accountScope: String,
        modeScope: String
    ) -> String {
        "analytics.calendar.range|viewer:\(viewerID)|start:\(start)|end:\(end)|account:\(accountScope)|mode:\(modeScope)"
    }

    static func accountCharts(viewerID: String, accountID: String) -> String {
        "analytics.accountCharts|viewer:\(viewerID)|account:\(accountID)"
    }
}
