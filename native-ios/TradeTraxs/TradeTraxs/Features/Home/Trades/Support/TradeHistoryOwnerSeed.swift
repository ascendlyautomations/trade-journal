import Foundation

/// Seeds Trade History page one from Dashboard/session owner trade cache when safe.
enum TradeHistoryOwnerSeed {
    struct Result: Sendable {
        var items: [Trade]
        var nextCursor: String?
        /// True when the owner cache may not represent full server history.
        var isPartial: Bool
    }

    /// Owner cache can satisfy filtered/search queries locally when fresh.
    static func canSeed(query: TradeHistoryQuery, hasLocalBrowseConstraints: Bool) -> Bool {
        guard !hasLocalBrowseConstraints else { return false }
        return true
    }

    static func page(
        from ownerTrades: [Trade],
        query: TradeHistoryQuery,
        limit: Int,
        context: TradeHistoryMatchContext = TradeHistoryMatchContext()
    ) -> Result {
        var rows = ownerTrades.filter { $0.mode != .backtest }
        rows = rows.filter { TradeHistoryLocalMatch.matches($0, query: query, context: context) }
        rows = TradeHistorySortSupport.sorted(rows, sort: query.filters.sort)

        let page = Array(rows.prefix(limit))
        let hasMore = rows.count > page.count
        let cursor: String? = {
            guard hasMore, let last = page.last else { return nil }
            return TradeHistorySortSupport.cursor(for: last, sort: query.filters.sort)
        }()
        return Result(
            items: page,
            nextCursor: cursor,
            isPartial: hasMore || ownerTrades.count >= 500
        )
    }
}
