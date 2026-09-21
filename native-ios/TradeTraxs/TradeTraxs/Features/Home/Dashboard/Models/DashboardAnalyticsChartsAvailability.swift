import Foundation

/// Account-scoped Dashboard V3 chart bundle readiness (equity / distributions / insights).
nonisolated enum DashboardAnalyticsChartsAvailability: Equatable, Sendable {
    case notRequested
    case loading
    case loaded
    case failed

    var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }
}
