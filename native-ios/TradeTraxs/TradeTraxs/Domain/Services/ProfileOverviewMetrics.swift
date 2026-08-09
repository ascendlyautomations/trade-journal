import Foundation

/// Mirrors web `useProfileStatistics` overview / profit-factor formulas.
///
/// Source universe: public trades already filtered with `is_public = true`.
/// Backtest rows (`mode` or `account_type` == "backtest") are excluded — same as web.
nonisolated enum ProfileOverviewMetrics {
    struct TradeInput: Sendable, Equatable {
        var pnl: Decimal?
        var rr: Decimal?
        var mode: String?
        var accountType: String?
    }

    struct Result: Sendable, Equatable {
        var publicTradeCount: Int
        /// Fraction `0...1` (web overview multiplies by 100 for display).
        var winRate: Decimal
        var netPnL: Decimal
        var averageRR: Decimal?
        /// `nil` when there are no losses — same as web `profitFactor`.
        var profitFactor: Decimal?
        /// Not shown on web Profile — always `nil` for parity.
        var expectancy: Decimal?
    }

    static func excludingBacktest(_ trades: [TradeInput]) -> [TradeInput] {
        trades.filter { trade in
            let mode = (trade.mode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let accountType = (trade.accountType ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return mode != "backtest" && accountType != "backtest"
        }
    }

    static func compute(from publicTrades: [TradeInput]) -> Result {
        let trades = excludingBacktest(publicTrades)
        let total = trades.count
        let wins = trades.filter { ($0.pnl ?? 0) > 0 }.count
        let winRate: Decimal = total > 0 ? Decimal(wins) / Decimal(total) : 0
        let netPnL = trades.reduce(Decimal(0)) { $0 + ($1.pnl ?? 0) }

        var rrSum = Decimal(0)
        var rrCount = 0
        for trade in trades {
            guard let rr = trade.rr else { continue }
            rrSum += rr
            rrCount += 1
        }
        let averageRR: Decimal? = rrCount > 0 ? rrSum / Decimal(rrCount) : nil

        let grossWins = trades.reduce(Decimal(0)) { sum, trade in
            let pnl = trade.pnl ?? 0
            return pnl > 0 ? sum + pnl : sum
        }
        let grossLosses = trades.reduce(Decimal(0)) { sum, trade in
            let pnl = trade.pnl ?? 0
            return pnl < 0 ? sum + pnl : sum
        }
        let profitFactor: Decimal? = grossLosses < 0
            ? grossWins / abs(grossLosses)
            : nil

        return Result(
            publicTradeCount: total,
            winRate: winRate,
            netPnL: netPnL,
            averageRR: averageRR,
            profitFactor: profitFactor,
            expectancy: nil
        )
    }
}
