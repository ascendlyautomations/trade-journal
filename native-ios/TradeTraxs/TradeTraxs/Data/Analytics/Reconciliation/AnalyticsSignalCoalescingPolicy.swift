import Foundation

/// Future bulk Realtime debounce — production analytical Realtime is not enabled in Phase 6B.
nonisolated struct AnalyticsSignalCoalescingPolicy: Sendable, Equatable {
    var debounce: Duration
    var maxDebounce: Duration

    static let immediate = AnalyticsSignalCoalescingPolicy(
        debounce: .zero,
        maxDebounce: .zero
    )

    /// Phase 6A design default for future bulk import coalescing (not active without Realtime).
    static let futureBulkImportDefault = AnalyticsSignalCoalescingPolicy(
        debounce: .milliseconds(400),
        maxDebounce: .seconds(2)
    )

    var debounceSeconds: TimeInterval {
        Self.seconds(from: debounce)
    }

    var maxDebounceSeconds: TimeInterval {
        Self.seconds(from: maxDebounce)
    }

    private static func seconds(from duration: Duration) -> TimeInterval {
        if duration == .zero { return 0 }
        return TimeInterval(duration.components.seconds)
            + TimeInterval(duration.components.attoseconds) / 1e18
    }
}
