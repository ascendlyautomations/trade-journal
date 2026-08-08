import Foundation

/// Soft guidance for list loading — implementations live in Data later.
nonisolated enum PaginationPolicy {
    static let defaultPageSize = 30
    static let maximumPageSize = 100
}

/// Free-tier capability caps (business rules, not billing transport).
nonisolated enum FreeTierPolicy {
    static let dailyTradeLimit = 3
    static let dailyPostLimit = 3
    static let dailyReelLimit = 3
    static let dailyDirectMessageLimit = 25
    static let maxTradeEntryAccounts = 3
}
