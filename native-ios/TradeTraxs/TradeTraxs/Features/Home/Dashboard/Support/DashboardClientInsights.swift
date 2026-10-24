import Foundation

/// Client-side dashboard insights — mirrors web `useDashboardAnalytics` narratives.
nonisolated enum DashboardClientInsights {
    struct CombinedSetup: Sendable, Equatable {
        var key: String
        var totalPnL: Decimal
        var trades: Int
        var wins: Int
        var avgPnL: Decimal
        var winRate: Double
    }

    static func performanceNarratives(from trades: [Trade]) -> [DashboardInsightItem] {
        guard !trades.isEmpty else { return [] }
        var items: [DashboardInsightItem] = []
        let groups = analyzeBestSetups(trades)

        if let bestSession = groups.first(where: { $0.type == "session" }),
           bestSession.value != "—"
        {
            items.append(
                DashboardInsightItem(
                    id: "client.performance.session",
                    title: "Strongest session",
                    body: "You perform best trading \(bestSession.value) session (\(money(bestSession.avgPnL)) avg, \(percent(bestSession.winRate)) win rate).",
                    kind: .session,
                    tone: .positive,
                    section: .performance
                )
            )
        }

        if let bestTicker = groups.first(where: { $0.type == "ticker" }),
           bestTicker.value != "—"
        {
            items.append(
                DashboardInsightItem(
                    id: "client.performance.ticker",
                    title: "Best market",
                    body: "\(bestTicker.value) is your most profitable market (\(money(bestTicker.avgPnL)) avg per trade).",
                    kind: .symbol,
                    tone: .positive,
                    section: .performance
                )
            )
        }

        if let bestDirection = groups.first(where: { $0.type == "direction" }),
           bestDirection.value != "—"
        {
            items.append(
                DashboardInsightItem(
                    id: "client.performance.direction",
                    title: "Direction edge",
                    body: "You are more profitable going \(bestDirection.value.lowercased()) (\(money(bestDirection.avgPnL)) avg).",
                    kind: .direction,
                    tone: .positive,
                    section: .performance
                )
            )
        }

        return items
    }

    /// Web `BestSetupCard` / `bestSetup` — first tagged strategy with ≥3 trades in the filtered set.
    static func bestPerformingStrategyInsight(
        from trades: [Trade],
        highlights: DashboardStrategyHighlights?
    ) -> DashboardInsightItem? {
        let best = qualifiedBestStrategy(from: trades, highlights: highlights)
        guard let best else { return nil }
        let winRateText: String
        if let winRate = best.winRate {
            winRateText = String(format: "%.0f", winRate)
        } else {
            winRateText = "—"
        }
        let pnl = money(Decimal(best.netPnL))
        return DashboardInsightItem(
            id: "client.advanced.best_strategy",
            title: "Best Performing Strategy",
            body: "\(best.strategy) is the strongest tagged strategy.",
            kind: .session,
            tone: best.netPnL >= 0 ? .positive : .negative,
            section: .advancedEdge,
            metric: "\(winRateText)% · \(pnl) · \(best.trades) trades"
        )
    }

    static func advancedEdge(from trades: [Trade]) -> [DashboardInsightItem] {
        let results = analyzeCombinedSetups(trades)
        let meaningful = results.filter { !$0.key.contains("—") }
        guard let best = meaningful.first else { return [] }
        return [
            DashboardInsightItem(
                id: "client.advanced.combo",
                title: "Combined edge",
                body: "Your strongest setup is trading \(formatCombo(best.key)) (\(money(best.avgPnL)) avg, \(percent(best.winRate)) win rate over \(best.trades) trades).",
                kind: .session,
                tone: .positive,
                section: .advancedEdge
            ),
        ]
    }

    static func worstCombinedSetup(from trades: [Trade]) -> DashboardInsightItem? {
        let results = analyzeCombinedSetups(trades)
            .filter { !$0.key.contains("—") && $0.trades >= 3 }
        guard let worst = results.min(by: { $0.avgPnL < $1.avgPnL }) else { return nil }
        return DashboardInsightItem(
            id: "client.risk.worst_combo",
            title: "Risk",
            body: "You struggle most trading \(formatCombo(worst.key)) (\(money(worst.avgPnL)) avg, \(percent(worst.winRate)) win rate over \(worst.trades) trades).",
            kind: .direction,
            tone: .negative,
            section: .riskBehavior
        )
    }

    static func behaviorWarnings(from trades: [Trade]) -> [DashboardInsightItem] {
        var items: [DashboardInsightItem] = []
        let chronological = trades.sorted { lhs, rhs in
            if lhs.entryAt != rhs.entryAt { return lhs.entryAt < rhs.entryAt }
            return lhs.id.rawValue < rhs.id.rawValue
        }

        if let lossStreakRate = detectLossStreak(chronological), lossStreakRate < 0.45 {
            items.append(
                DashboardInsightItem(
                    id: "client.risk.loss_streak",
                    title: "After losing streaks",
                    body: "After 3 consecutive losses, your win rate drops to \(percent(lossStreakRate)) in the next few trades.",
                    kind: .direction,
                    tone: .warning,
                    section: .riskBehavior
                )
            )
        }

        if let rr = detectRRThreshold(trades) {
            items.append(
                DashboardInsightItem(
                    id: "client.risk.rr_threshold",
                    title: "Behavior warning",
                    body: rr,
                    kind: .direction,
                    tone: .warning,
                    section: .riskBehavior
                )
            )
        }

        return items
    }

    // MARK: - Setup analytics

    private struct SetupGroup: Sendable {
        var type: String
        var value: String
        var totalPnL: Decimal
        var trades: Int
        var wins: Int
        var avgPnL: Decimal
        var winRate: Double
    }

    private static func analyzeBestSetups(_ trades: [Trade]) -> [SetupGroup] {
        var groupStats: [String: (type: String, value: String, totalPnL: Decimal, trades: Int, wins: Int)] = [:]

        for trade in trades {
            let pnl = trade.realizedPnL?.amount ?? 0
            let session = normalizedSession(trade.sessionLabel) ?? "—"
            let ticker = trade.symbol.ticker.isEmpty ? "—" : trade.symbol.ticker
            let direction = trade.side == .long ? "Long" : "Short"

            for group in [
                ("session", session),
                ("ticker", ticker),
                ("direction", direction),
            ] {
                let key = "\(group.0):\(group.1)"
                var row = groupStats[key] ?? (group.0, group.1, 0, 0, 0)
                row.totalPnL += pnl
                row.trades += 1
                if pnl > 0 { row.wins += 1 }
                groupStats[key] = row
            }
        }

        return groupStats.values
            .map { row in
                SetupGroup(
                    type: row.type,
                    value: row.value,
                    totalPnL: row.totalPnL,
                    trades: row.trades,
                    wins: row.wins,
                    avgPnL: row.trades > 0 ? row.totalPnL / Decimal(row.trades) : 0,
                    winRate: row.trades > 0 ? Double(row.wins) / Double(row.trades) : 0
                )
            }
            .filter { $0.trades >= 3 }
            .sorted { $0.avgPnL > $1.avgPnL }
    }

    static func analyzeCombinedSetups(_ trades: [Trade]) -> [CombinedSetup] {
        var stats: [String: (key: String, totalPnL: Decimal, trades: Int, wins: Int)] = [:]

        for trade in trades {
            let pnl = trade.realizedPnL?.amount ?? 0
            let session = normalizedSession(trade.sessionLabel) ?? "—"
            let ticker = trade.symbol.ticker.isEmpty ? "—" : trade.symbol.ticker
            let direction = trade.side == .long ? "Long" : "Short"

            let combos = [
                "session:\(session)|ticker:\(ticker)",
                "session:\(session)|direction:\(direction)",
                "ticker:\(ticker)|direction:\(direction)",
                "session:\(session)|ticker:\(ticker)|direction:\(direction)",
            ]

            for key in combos {
                var row = stats[key] ?? (key, 0, 0, 0)
                row.totalPnL += pnl
                row.trades += 1
                if pnl > 0 { row.wins += 1 }
                stats[key] = row
            }
        }

        return stats.values
            .map { row in
                CombinedSetup(
                    key: row.key,
                    totalPnL: row.totalPnL,
                    trades: row.trades,
                    wins: row.wins,
                    avgPnL: row.trades > 0 ? row.totalPnL / Decimal(row.trades) : 0,
                    winRate: row.trades > 0 ? Double(row.wins) / Double(row.trades) : 0
                )
            }
            .filter { $0.trades >= 3 }
            .sorted { $0.avgPnL > $1.avgPnL }
    }

    private static func formatCombo(_ key: String) -> String {
        let parts = key.split(separator: "|").map { part -> String in
            guard let idx = part.firstIndex(of: ":") else { return String(part) }
            return String(part[part.index(after: idx)...])
        }
        if parts.count == 2 {
            return "\(parts[1]) during \(parts[0])"
        }
        if parts.count == 3 {
            return "\(parts[1]) during \(parts[0]) going \(parts[2].lowercased())"
        }
        return parts.joined(separator: " ")
    }

    private static func detectLossStreak(_ trades: [Trade]) -> Double? {
        guard trades.count >= 4 else { return nil }
        for index in 0...(trades.count - 4) {
            let a = trades[index].realizedPnL?.amount ?? 0
            let b = trades[index + 1].realizedPnL?.amount ?? 0
            let c = trades[index + 2].realizedPnL?.amount ?? 0
            if a < 0, b < 0, c < 0 {
                let next = Array(trades[(index + 3)..<min(index + 8, trades.count)])
                guard !next.isEmpty else { return nil }
                let wins = next.filter { ($0.realizedPnL?.amount ?? 0) > 0 }.count
                return Double(wins) / Double(next.count)
            }
        }
        return nil
    }

    private static func detectRRThreshold(_ trades: [Trade]) -> String? {
        let lowRR = trades.filter { trade in
            guard let rr = trade.riskReward else { return false }
            return rr < 1
        }
        let highRR = trades.filter { trade in
            guard let rr = trade.riskReward else { return false }
            return rr >= 1
        }
        guard lowRR.count >= 3, highRR.count >= 3 else { return nil }

        let lowWin = Double(lowRR.filter { ($0.realizedPnL?.amount ?? 0) > 0 }.count) / Double(lowRR.count)
        let highWin = Double(highRR.filter { ($0.realizedPnL?.amount ?? 0) > 0 }.count) / Double(highRR.count)
        if highWin > lowWin + 0.2 {
            return "You perform significantly better when RR ≥ 1"
        }
        return nil
    }

    private static func qualifiedBestStrategy(
        from trades: [Trade],
        highlights: DashboardStrategyHighlights?
    ) -> DashboardStrategyHighlight? {
        if let best = highlights?.best, best.trades >= 3 {
            return best
        }
        return bestStrategyHighlight(from: trades)
    }

    private static func bestStrategyHighlight(from trades: [Trade]) -> DashboardStrategyHighlight? {
        var map: [String: (pnl: Decimal, trades: Int, wins: Int)] = [:]
        for trade in trades {
            let key = (trade.strategy ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            var row = map[key] ?? (0, 0, 0)
            let pnl = trade.realizedPnL?.amount ?? 0
            row.pnl += pnl
            row.trades += 1
            if pnl > 0 { row.wins += 1 }
            map[key] = row
        }
        guard let best = map.filter({ $0.value.trades >= 3 }).max(by: { $0.value.pnl < $1.value.pnl })
        else { return nil }
        return DashboardStrategyHighlight(
            strategy: best.key,
            trades: best.value.trades,
            netPnL: NSDecimalNumber(decimal: best.value.pnl).doubleValue,
            winRate: Double(best.value.wins) / Double(best.value.trades) * 100
        )
    }

    private static func normalizedSession(_ raw: String?) -> String? {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let lower = value.lowercased()
        if lower.contains("ny") || lower.contains("new york") { return "NY" }
        if lower.contains("london") || lower.contains("ldn") { return "London" }
        if lower.contains("asia") || lower.contains("tokyo") { return "Asia" }
        return value
    }

    private static func money(_ value: Decimal) -> String {
        NumberDisplay.currency(value, minimumFractionDigits: 2, maximumFractionDigits: 2)
    }

    private static func percent(_ value: Double) -> String {
        "\(Int(value * 100))"
    }
}
