import Foundation

struct BacktestLabGroupRow: Identifiable, Equatable, Sendable {
    var id: String { key }
    var key: String
    var label: String
    var tradeCount: Int
    var winRatePercent: Double
    var netPnL: Decimal
    var profitFactor: Decimal?
    var averageRR: Double?
}

/// Strategy, setup-tag, and instrument leaderboards for Backtest Lab.
nonisolated enum BacktestLabGroupedPerformance {
    static func strategyRows(from trades: [Trade]) -> [BacktestLabGroupRow] {
        var buckets: [String: [Trade]] = [:]
        for trade in trades {
            let key = strategyGroupKey(trade.strategy)
            buckets[key, default: []].append(trade)
        }
        return buckets.map { key, bucket in
            row(key: key, label: strategyDisplayLabel(bucket, key: key), trades: bucket)
        }
        .sorted { $0.netPnL > $1.netPnL }
    }

    /// Splits `trades.strategy` on commas, slashes, and pipes for multi-setup tagging.
    static func setupTagRows(from trades: [Trade]) -> [BacktestLabGroupRow] {
        var buckets: [String: [Trade]] = [:]
        for trade in trades {
            let tags = setupTags(from: trade.strategy)
            guard !tags.isEmpty else { continue }
            for tag in tags {
                let key = tag.lowercased()
                buckets[key, default: []].append(trade)
            }
        }
        return buckets.map { key, bucket in
            row(key: key, label: setupTagDisplayLabel(bucket, key: key), trades: bucket)
        }
        .sorted { $0.netPnL > $1.netPnL }
    }

    static func instrumentRows(from trades: [Trade]) -> [BacktestLabGroupRow] {
        var buckets: [String: [Trade]] = [:]
        for trade in trades {
            let key = instrumentGroupKey(trade.symbol.ticker)
            guard !key.isEmpty else { continue }
            buckets[key, default: []].append(trade)
        }
        return buckets.map { key, bucket in
            row(key: key, label: instrumentDisplayLabel(bucket, key: key), trades: bucket)
        }
        .sorted { $0.netPnL > $1.netPnL }
    }

    private static func row(key: String, label: String, trades: [Trade]) -> BacktestLabGroupRow {
        let snapshot = BacktestLabMetrics.snapshot(for: trades)
        return BacktestLabGroupRow(
            key: key,
            label: label,
            tradeCount: snapshot.tradeCount,
            winRatePercent: snapshot.winRatePercent,
            netPnL: snapshot.totalPnL,
            profitFactor: snapshot.profitFactor,
            averageRR: snapshot.averageRR
        )
    }

    static func strategyGroupKey(_ strategy: String?) -> String {
        let raw = strategy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return "__no_strategy__" }
        return raw.lowercased()
    }

    static func setupTags(from strategy: String?) -> [String] {
        let raw = strategy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return [] }
        let parts = raw
            .split { $0 == "," || $0 == "/" || $0 == "|" || $0 == ";" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.isEmpty { return [raw] }
        return parts
    }

    private static func strategyDisplayLabel(_ trades: [Trade], key: String) -> String {
        if key == "__no_strategy__" { return "No Strategy" }
        var counts: [String: Int] = [:]
        for trade in trades {
            let label = trade.strategy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? key
            counts[label, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? key
    }

    private static func setupTagDisplayLabel(_ trades: [Trade], key: String) -> String {
        var counts: [String: Int] = [:]
        for trade in trades {
            for tag in setupTags(from: trade.strategy) where tag.lowercased() == key {
                counts[tag, default: 0] += 1
            }
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? key
    }

    private static func instrumentGroupKey(_ ticker: String) -> String {
        let raw = ticker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        return raw.uppercased()
    }

    private static func instrumentDisplayLabel(_ trades: [Trade], key: String) -> String {
        var counts: [String: Int] = [:]
        for trade in trades {
            let label = trade.symbol.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            counts[label, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? key
    }

    static func tradesMatchingStrategy(_ trades: [Trade], key: String) -> [Trade] {
        if key == "__no_strategy__" {
            return trades.filter {
                strategyGroupKey($0.strategy) == key
            }
        }
        return trades.filter { strategyGroupKey($0.strategy) == key }
    }

    static func tradesMatchingSetupTag(_ trades: [Trade], key: String) -> [Trade] {
        trades.filter { trade in
            setupTags(from: trade.strategy).contains { $0.lowercased() == key }
        }
    }

    static func tradesMatchingInstrument(_ trades: [Trade], key: String) -> [Trade] {
        trades.filter { instrumentGroupKey($0.symbol.ticker) == key }
    }
}