import Foundation

/// Client-side Backtest Lab aggregates — mirrors web `/backtest` metrics.
nonisolated enum BacktestLabMetrics {
    static let allStrategiesToken = "all"

    struct Snapshot: Equatable, Sendable {
        var tradeCount: Int
        var winCount: Int
        var lossCount: Int
        var winRatePercent: Double
        var totalPnL: Decimal
        var averageRR: Double?
        /// Gross profit / gross loss — nil when undefined (e.g. no losing trades).
        var profitFactor: Decimal?
        var averageWin: Decimal?
        /// Positive loss magnitude per losing trade.
        var averageLoss: Decimal?
    }

    struct StrategyBreakdown: Identifiable, Equatable, Sendable {
        var id: String { name }
        var name: String
        var tradeCount: Int
        var winRatePercent: Double
        var totalPnL: Decimal
        var averageRR: Double?
    }

    static func snapshot(for trades: [Trade]) -> Snapshot {
        let pnls = trades.map { $0.realizedPnL?.amount ?? 0 }
        let winPnls = pnls.filter { $0 > 0 }
        let lossPnls = pnls.filter { $0 < 0 }
        let wins = winPnls.count
        let losses = lossPnls.count
        let total = pnls.reduce(0, +)
        let count = trades.count
        let winRate = count > 0 ? (Double(wins) / Double(count)) * 100 : 0
        let grossProfit = winPnls.reduce(0, +)
        let grossLoss = abs(lossPnls.reduce(0, +))
        let profitFactor: Decimal? = {
            guard grossLoss > 0 else { return nil }
            guard grossProfit > 0 else { return 0 }
            return grossProfit / grossLoss
        }()
        let averageWin: Decimal? = wins > 0 ? grossProfit / Decimal(wins) : nil
        let averageLoss: Decimal? = losses > 0 ? grossLoss / Decimal(losses) : nil
        return Snapshot(
            tradeCount: count,
            winCount: wins,
            lossCount: losses,
            winRatePercent: winRate,
            totalPnL: total,
            averageRR: averageRR(trades),
            profitFactor: profitFactor,
            averageWin: averageWin,
            averageLoss: averageLoss
        )
    }

    static func formatProfitFactor(_ value: Decimal?) -> String {
        NumberDisplay.factor(value)
    }

    static func formatAverageWin(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return TradeDisplay.pnlText(Money(amount: value))
    }

    static func formatAverageLoss(_ value: Decimal?) -> String {
        guard let value, value > 0 else { return "—" }
        return TradeDisplay.pnlText(Money(amount: -value))
    }

    static func strategyBreakdown(from trades: [Trade]) -> [StrategyBreakdown] {
        var buckets: [String: [Trade]] = [:]
        for trade in trades {
            let raw = trade.strategy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !raw.isEmpty else { continue }
            buckets[raw, default: []].append(trade)
        }
        return buckets.keys.sorted().map { name in
            let group = buckets[name] ?? []
            let snap = snapshot(for: group)
            return StrategyBreakdown(
                name: name,
                tradeCount: snap.tradeCount,
                winRatePercent: snap.winRatePercent,
                totalPnL: snap.totalPnL,
                averageRR: snap.averageRR
            )
        }
    }

    static func distinctStrategies(in trades: [Trade]) -> [String] {
        Array(
            Set(
                trades.compactMap { trade -> String? in
                    let raw = trade.strategy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return raw.isEmpty ? nil : raw
                }
            )
        ).sorted()
    }

    static func filter(_ trades: [Trade], strategy: String?) -> [Trade] {
        guard let strategy, strategy != allStrategiesToken else { return trades }
        return trades.filter { ($0.strategy ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == strategy }
    }

    private static func averageRR(_ trades: [Trade]) -> Double? {
        let values = trades.compactMap { trade -> Double? in
            guard let rr = trade.riskReward else { return nil }
            return NSDecimalNumber(decimal: rr).doubleValue
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
