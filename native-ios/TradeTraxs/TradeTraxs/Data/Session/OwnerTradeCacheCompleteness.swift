import Foundation

/// Shared rules for reusing persisted owner trades without treating partial windows as complete.
nonisolated enum OwnerTradeCacheCompleteness {
    struct Metadata: Sendable, Equatable {
        var historyComplete: Bool
        var totalTradeCount: Int
        var cachedTradeCount: Int
    }

    /// True when the cached owner snapshot represents the full server trade set.
    static func isCompleteSnapshot(_ metadata: Metadata?) -> Bool {
        guard let metadata else { return false }
        return metadata.historyComplete
            && metadata.cachedTradeCount == metadata.totalTradeCount
    }

    /// First Trade History page may render from owner cache only when the snapshot is complete.
    static func canSeedTradeHistoryFirstPage(
        metadata: Metadata?,
        seededItemCount: Int
    ) -> Bool {
        guard isCompleteSnapshot(metadata) else { return false }
        return seededItemCount > 0 || metadata?.totalTradeCount == 0
    }

    /// Owner-cache pagination may continue locally when the snapshot is complete.
    static func canPaginateFromOwnerCache(metadata: Metadata?) -> Bool {
        isCompleteSnapshot(metadata)
    }

    /// Calendar month may seed from owner trades when the owner snapshot is complete.
    static func canSeedCalendarMonth(metadata: Metadata?) -> Bool {
        isCompleteSnapshot(metadata)
    }

    static func metadata(
        historyComplete: Bool,
        totalTradeCount: Int,
        cachedTrades: [Trade]
    ) -> Metadata {
        Metadata(
            historyComplete: historyComplete,
            totalTradeCount: totalTradeCount,
            cachedTradeCount: cachedTrades.count
        )
    }
}
