import Foundation

/// Soft guidance for list loading — implementations live in Data later.
nonisolated enum PaginationPolicy {
    static let defaultPageSize = 30
    static let maximumPageSize = 100
}

/// Free-tier capability caps (business rules, not billing transport).
nonisolated enum FreeTierPolicy {
    /// Clips per UTC calendar day on Free (TraxPro unlimited). Internal `reels` table unchanged.
    static let dailyClipLimit = 4
    /// Legacy name — same as ``dailyClipLimit``.
    static let dailyReelLimit = dailyClipLimit
    static let maxTradeEntryAccounts = 3
}
