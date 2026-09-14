import Foundation

/// Derives a calendar month from a complete owner trade snapshot.
enum OwnerTradeCalendarSeed {
    static func trades(
        from ownerTrades: [Trade],
        year: Int,
        month: Int
    ) -> [Trade]? {
        guard let window = TradingCalendarDay.fetchWindow(year: year, month: month) else {
            return nil
        }
        let filtered = ownerTrades.filter { trade in
            trade.mode != .backtest
                && trade.entryAt >= window.start
                && trade.entryAt < window.end
        }
        return filtered
    }
}
