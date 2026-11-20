import Foundation

/// HTTP fallback when Supabase Realtime is unavailable, stale, or not configured.
enum BroadcastSessionSyncPolicy {
    /// Authoritative interactive snapshot while Realtime is delivering events.
    static let fallbackInteractiveHealthySeconds: TimeInterval = 60
    /// Tighter fallback when Realtime is down or stale.
    static let fallbackInteractiveUnhealthySeconds: TimeInterval = 15
    /// Full broadcast status while watching with healthy Realtime.
    static let fallbackStatusWatchingHealthySeconds: TimeInterval = 45
    /// Full broadcast status while watching without healthy Realtime.
    static let fallbackStatusWatchingUnhealthySeconds: TimeInterval = 15
    /// No postgres event for this long → treat Realtime as unhealthy for fallback cadence.
    static let realtimeStalenessSeconds: TimeInterval = 90
    /// Debounce bursty postgres events before one BFF interactive snapshot.
    static let realtimeEventDebounceNanoseconds: UInt64 = 300_000_000

    static func fallbackInteractiveInterval(healthy: Bool) -> TimeInterval {
        healthy ? fallbackInteractiveHealthySeconds : fallbackInteractiveUnhealthySeconds
    }

    static func fallbackStatusInterval(healthy: Bool) -> TimeInterval {
        healthy ? fallbackStatusWatchingHealthySeconds : fallbackStatusWatchingUnhealthySeconds
    }

    static func isRealtimeHealthy(lastSignalAt: Date?, now: Date = Date()) -> Bool {
        guard let lastSignalAt else { return false }
        return now.timeIntervalSince(lastSignalAt) < realtimeStalenessSeconds
    }
}