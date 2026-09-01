import Foundation

/// Seeds Trade History page one from Dashboard/session owner trade cache when safe.
enum TradeHistoryOwnerSeed {
    struct Result: Sendable {
        var items: [Trade]
        var nextCursor: String?
        /// True when the owner cache may not represent full server history.
        var isPartial: Bool
    }

    /// Default journal query with no local Dashboard browse constraints.
    static func canSeed(query: TradeHistoryQuery, hasLocalBrowseConstraints: Bool) -> Bool {
        guard !hasLocalBrowseConstraints else { return false }
        guard query.trimmedSearch.isEmpty else { return false }
        guard !query.filters.hasActiveConstraints else { return false }
        return true
    }

    static func page(
        from ownerTrades: [Trade],
        query: TradeHistoryQuery,
        limit: Int
    ) -> Result? {
        var rows = ownerTrades.filter { $0.mode != .backtest }
        rows = rows.filter { TradeHistoryLocalMatch.matches($0, query: query) }
        rows = sorted(rows, sort: query.filters.sort)
        guard !rows.isEmpty else { return nil }

        let page = Array(rows.prefix(limit))
        let hasMore = rows.count > page.count
        let cursor: String? = {
            guard hasMore, let last = page.last else { return nil }
            switch query.filters.sort {
            case .newest, .oldest:
                return ISO8601.string(from: last.createdAt)
            case .highestPnL, .lowestPnL:
                if let pnl = last.realizedPnL?.amount {
                    return NSDecimalNumber(decimal: pnl).stringValue
                }
                return ISO8601.string(from: last.createdAt)
            }
        }()
        return Result(items: page, nextCursor: cursor, isPartial: hasMore || ownerTrades.count >= 500)
    }

    private static func sorted(_ rows: [Trade], sort: TradeHistorySort) -> [Trade] {
        switch sort {
        case .newest:
            return rows.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return rows.sorted { $0.createdAt < $1.createdAt }
        case .highestPnL:
            return rows.sorted {
                ($0.realizedPnL?.amount ?? 0) > ($1.realizedPnL?.amount ?? 0)
            }
        case .lowestPnL:
            return rows.sorted {
                ($0.realizedPnL?.amount ?? 0) < ($1.realizedPnL?.amount ?? 0)
            }
        }
    }
}
