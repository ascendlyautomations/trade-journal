import Foundation

/// Per-trader stats aggregated from public leaderboard trade rows (client-side, web parity).
nonisolated struct LeaderboardUserStats: Hashable, Sendable {
    var totalPnL: Decimal
    var tradeCount: Int
    var winRate: Decimal?
    var profitFactor: Decimal?
    var expectancy: Decimal?
    var averageRiskReward: Decimal?
    var winStreak: Int
    var profitPercent: Decimal?
    var consistency: Decimal?
}

nonisolated enum LeaderboardUserStatsAggregator {
    static func aggregate(trades: [LeaderboardTradeRow]) -> LeaderboardUserStats {
        let ordered = trades.sorted {
            LeaderboardTradeWindowFilter.createdAtTimestamp($0.createdAt)
                < LeaderboardTradeWindowFilter.createdAtTimestamp($1.createdAt)
        }

        var pnls: [Decimal] = []
        var rrSum = Decimal(0)
        var rrCount = 0
        var winStreak = 0
        var bestWinStreak = 0
        var dailyPnL: [String: Decimal] = [:]

        for trade in ordered {
            let pnl = trade.pnl ?? 0
            pnls.append(pnl)

            if let rr = validRR(trade.rr) {
                rrSum += rr
                rrCount += 1
            }

            if pnl > 0 {
                winStreak += 1
                bestWinStreak = max(bestWinStreak, winStreak)
            } else {
                winStreak = 0
            }

            let day = LeaderboardTradeWindowFilter.tradingDayKey(for: trade.createdAt)
            dailyPnL[day, default: 0] += pnl
        }

        let tradeCount = pnls.count
        let wins = pnls.filter { $0 > 0 }
        let losses = pnls.filter { $0 < 0 }
        let winCount = wins.count
        let lossCount = losses.count
        let grossWins = wins.reduce(0, +)
        let grossLosses = losses.reduce(0, +)
        let totalPnL = pnls.reduce(0, +)

        let winRate: Decimal? = tradeCount > 0 ? Decimal(winCount) / Decimal(tradeCount) : nil
        let avgWin = winCount > 0 ? grossWins / Decimal(winCount) : nil
        let avgLossAbs = lossCount > 0 ? abs(grossLosses) / Decimal(lossCount) : nil
        let lossRate = tradeCount > 0 ? Decimal(lossCount) / Decimal(tradeCount) : 0
        let winRateFrac = winRate ?? 0
        let expectancy: Decimal? = tradeCount > 0
            ? winRateFrac * (avgWin ?? 0) - lossRate * (avgLossAbs ?? 0)
            : nil
        let profitFactor: Decimal? = grossLosses < 0 ? grossWins / abs(grossLosses) : nil

        let profitableDays = dailyPnL.values.filter { $0 > 0 }.count
        let tradingDays = dailyPnL.count
        let profitPercent: Decimal? = tradingDays > 0
            ? Decimal(profitableDays) / Decimal(tradingDays) * 100
            : nil

        let biggestWin = wins.max() ?? 0
        let consistency: Decimal? = grossWins > 0
            ? max(0, min(100, (1 - biggestWin / grossWins) * 100))
            : nil

        return LeaderboardUserStats(
            totalPnL: totalPnL,
            tradeCount: tradeCount,
            winRate: winRate,
            profitFactor: profitFactor,
            expectancy: expectancy,
            averageRiskReward: rrCount > 0 ? rrSum / Decimal(rrCount) : nil,
            winStreak: bestWinStreak,
            profitPercent: profitPercent,
            consistency: consistency
        )
    }

    private static func validRR(_ raw: Decimal?) -> Decimal? {
        guard let raw else { return nil }
        return raw
    }
}
