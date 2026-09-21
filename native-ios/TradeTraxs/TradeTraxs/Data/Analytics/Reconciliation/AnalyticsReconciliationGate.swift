import Foundation

/// Local coordinator routing — independent from Release GRDB cutover flags.
nonisolated enum AnalyticsReconciliationGate {
    static var isEnabled: Bool {
        BackendV2FeatureFlags.isEnabled(.dashboardAnalyticsV3)
            || BackendV2FeatureFlags.isEnabled(.calendarAnalyticsV2)
    }
}
