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

    /// Trades whose entry window falls in any month of `year` (same bounds as 12× month seed).
    static func tradesForYear(from ownerTrades: [Trade], year: Int) -> [Trade]? {
        var merged: [TradeID: Trade] = [:]
        for month in 1...12 {
            guard let monthTrades = trades(from: ownerTrades, year: year, month: month) else {
                continue
            }
            for trade in monthTrades {
                merged[trade.id] = trade
            }
        }
        return Array(merged.values)
    }
}
