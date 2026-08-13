import Foundation

/// Common state surface every screen snapshot should expose.
///
/// Domain-specific fields stay on the feature `*State` type. This protocol only
/// standardizes lifecycle / error / pagination observation for tooling and future screens.
///
/// Ownership rule:
/// ```
/// Screen → one bootstrap → one state → render-only children
/// ```
/// Children must never perform the initial repository load.
protocol ScreenStateModeling {
    /// Canonical phase (map from feature-local `Phase` if needed).
    var screenPhase: ScreenPhase { get }

    /// `true` after the first successful coordinated bootstrap this presentation / session.
    var didBootstrap: Bool { get }

    /// Pull-to-refresh / explicit refresh in flight.
    var isRefreshing: Bool { get }

    /// User-facing error from the last failed bootstrap / refresh, if any.
    var screenErrorMessage: String? { get }

    /// Wall-clock of the last successful bootstrap / refresh (optional).
    var lastUpdated: Date? { get }

    /// Pagination cursor state; use ``ScreenPaginationSnapshot/none`` when not paginated.
    var pagination: ScreenPaginationSnapshot { get }
}

extension ScreenStateModeling {
    var isRefreshing: Bool { false }
    var screenErrorMessage: String? { nil }
    var lastUpdated: Date? { nil }
    var pagination: ScreenPaginationSnapshot { .none }

    var isLoading: Bool {
        if case .loading = screenPhase { return true }
        return false
    }

    var hasFailed: Bool {
        if case .failed = screenPhase { return true }
        return false
    }
}
