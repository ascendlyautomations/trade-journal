import Foundation

/// Account-scoped Dashboard V3 chart bundle readiness (equity / distributions / insights).
nonisolated enum DashboardAnalyticsChartsAvailability: Equatable, Sendable {
    case notRequested
    case loading
    case loaded
    /// Transient failure — one deferred overlay retry may run.
    case failed
    /// Permission / auth failure — do not retry until pull refresh or revision change.
    case failedNonRetryable

    var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }

    var isTerminalFailure: Bool {
        switch self {
        case .failed, .failedNonRetryable:
            return true
        default:
            return false
        }
    }
}
