import Foundation

nonisolated enum ScorecardTradeMapper {
    static func mapChronological(trades: [Trade]) -> [ScorecardTrade] {
        let sorted = trades.sorted { lhs, rhs in
            if lhs.entryAt != rhs.entryAt { return lhs.entryAt < rhs.entryAt }
            return lhs.id.rawValue < rhs.id.rawValue
        }
        return sorted.compactMap(map(trade:))
    }

    static func map(trade: Trade) -> ScorecardTrade? {
        let entryMs = Int64(trade.entryAt.timeIntervalSince1970 * 1000)
        let pnl = NSDecimalNumber(decimal: trade.realizedPnL?.amount ?? 0).doubleValue

        let rr: Double? = {
            guard let value = trade.riskReward else { return nil }
            let n = NSDecimalNumber(decimal: value).doubleValue
            return n.isFinite ? n : nil
        }()

        let maxRr: Double? = {
            guard let value = trade.maxRrReached else { return nil }
            let n = NSDecimalNumber(decimal: value).doubleValue
            return n.isFinite ? n : nil
        }()

        let realized: Double? = {
            guard let resolved = TradePointsAndRealizedRr.resolveRealizedRr(trade: trade) else { return nil }
            let n = NSDecimalNumber(decimal: resolved).doubleValue
            return n.isFinite ? n : nil
        }()

        return ScorecardTrade(
            id: trade.id.rawValue,
            pnl: pnl,
            rr: positiveStoredRr(rr),
            maxRrReached: positiveStoredRr(maxRr),
            realizedRr: realized,
            followedPlan: trade.followedPlan,
            mistakeType: trade.mistakeType,
            confidence: trade.confidence.map(Double.init),
            executionRating: trade.executionRating.map(Double.init),
            entryTimeMs: entryMs,
            tradingDayKey: DashboardTradingDayKey.key(for: trade),
            psychologyDayKey: TraderPsychologyAnalyticsFoundation.tradeDateKey(for: trade)
        )
    }

    static func postTripleLossWinRate(trades: [ScorecardTrade]) -> Double? {
        guard trades.count >= 4 else { return nil }
        for i in 0...(trades.count - 4) {
            if trades[i].pnl < 0, trades[i + 1].pnl < 0, trades[i + 2].pnl < 0 {
                let next = Array(trades[(i + 3)..<min(i + 8, trades.count)])
                guard !next.isEmpty else { return nil }
                let wins = next.filter { $0.pnl > 0 }.count
                return Double(wins) / Double(next.count)
            }
        }
        return nil
    }

    static func periodTradingDayCount(from trades: [ScorecardTrade]) -> Int {
        Set(trades.compactMap(\.tradingDayKey)).count
    }

    private static func positiveStoredRr(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }
}
