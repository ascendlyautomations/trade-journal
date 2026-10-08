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
        let wins = pnls.filter { $0 > 0 }.count
        let losses = pnls.filter { $0 < 0 }.count
        let total = pnls.reduce(0, +)
        let count = trades.count
        let winRate = count > 0 ? (Double(wins) / Double(count)) * 100 : 0
        return Snapshot(
            tradeCount: count,
            winCount: wins,
            lossCount: losses,
            winRatePercent: winRate,
            totalPnL: total,
            averageRR: averageRR(trades)
        )
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
