import Foundation

/// Financial impact aggregates, derived from compliance checks + scoped trades (not a second engine).
nonisolated enum TradingRulesRuleImpact {
    /// Cap retained trade samples per impact side (UI previews resolve details by trade ID).
    static let maxTradeSamplesPerSide = 24

    struct TradeSample: Identifiable, Sendable, Hashable {
        var id: String { tradeID }
        var tradeID: String
        var netPnl: Double
        var realizedRr: Double?
        var at: Date
    }

    struct ComparisonHighlight: Identifiable, Sendable {
        var id: String { ruleID.rawValue }
        var ruleID: TradingRulesComplianceAnalytics.RuleID
        var ruleLabel: String
        /// Followed avg − violated avg (correlation only).
        var avgPnlDelta: Double
        var winRateDeltaPoints: Double
    }

  /// Net P&L for impact metrics, `realizedPnL` when present (dashboard parity). Fees are not on `Trade` yet.
    static func netPnl(for trade: Trade) -> Double? {
        guard let realized = trade.realizedPnL else { return nil }
        return NSDecimalNumber(decimal: realized.amount).doubleValue
    }

    static func realizedRr(for trade: Trade) -> Double? {
        guard let rr = TradePointsAndRealizedRr.resolveRealizedRr(trade: trade) else { return nil }
        return NSDecimalNumber(decimal: rr).doubleValue
    }

    static func buildImpactRows(
        checks: [TradingRulesComplianceAnalytics.Check],
        tradesByID: [String: Trade]
    ) -> [TradingRulesComplianceAnalytics.ImpactRow] {
        var buckets: [TradingRulesComplianceAnalytics.RuleID: (
            followed: TradingRulesComplianceAnalytics.ImpactSide,
            violated: TradingRulesComplianceAnalytics.ImpactSide
        )] = [:]
        for rule in TradingRulesComplianceAnalytics.RuleID.allCases {
            buckets[rule] = (.empty, .empty)
        }

        var seen: [TradingRulesComplianceAnalytics.RuleID: [TradingRulesComplianceAnalytics.Outcome: Set<String>]] = [:]

        for check in checks {
            guard check.level == .trade else { continue }
            guard let tradeID = check.tradeID else { continue }
            var ruleSeen = seen[check.ruleID] ?? [.followed: [], .violated: []]
            var outcomeSet = ruleSeen[check.outcome] ?? []
            guard !outcomeSet.contains(tradeID) else { continue }
            outcomeSet.insert(tradeID)
            ruleSeen[check.outcome] = outcomeSet
            seen[check.ruleID] = ruleSeen

            guard let trade = tradesByID[tradeID], let net = netPnl(for: trade) else { continue }
            guard var bucket = buckets[check.ruleID] else { continue }

            let rr = realizedRr(for: trade)
            let sample = TradeSample(tradeID: tradeID, netPnl: net, realizedRr: rr, at: check.at)
            switch check.outcome {
            case .followed:
                accumulate(into: &bucket.followed, net: net, realizedRr: rr, sample: sample)
            case .violated:
                accumulate(into: &bucket.violated, net: net, realizedRr: rr, sample: sample)
            case .unevaluated, .notApplicable:
                break
            }
            buckets[check.ruleID] = bucket
        }

        return finalizeRows(buckets: buckets)
    }

    static func comparisonHighlights(
        from rows: [TradingRulesComplianceAnalytics.ImpactRow]
    ) -> [ComparisonHighlight] {
        rows
            .filter(\.sufficientSample)
            .compactMap { row in
                guard let avgDelta = row.avgPnlDelta, let winDelta = row.winRateDeltaPoints else { return nil }
                return ComparisonHighlight(
                    ruleID: row.ruleID,
                    ruleLabel: row.ruleLabel,
                    avgPnlDelta: avgDelta,
                    winRateDeltaPoints: winDelta
                )
            }
            .sorted { abs($0.avgPnlDelta) > abs($1.avgPnlDelta) }
    }

    private static func accumulate(
        into side: inout TradingRulesComplianceAnalytics.ImpactSide,
        net: Double,
        realizedRr: Double?,
        sample: TradeSample
    ) {
        side.priced += 1
        side.totalNetPnl += net
        if net > 0 {
            side.wins += 1
            side.grossWins += net
        } else if net < 0 {
            side.losses += 1
            side.grossLosses += net
        } else {
            side.breakeven += 1
        }
        if let realizedRr {
            side.realizedRrSum += realizedRr
            side.realizedRrCount += 1
        }
        if side.tradeSamples.count < maxTradeSamplesPerSide {
            side.tradeSamples.append(sample)
        }
    }

    private static func finalizeRows(
        buckets: [TradingRulesComplianceAnalytics.RuleID: (
            followed: TradingRulesComplianceAnalytics.ImpactSide,
            violated: TradingRulesComplianceAnalytics.ImpactSide
        )]
    ) -> [TradingRulesComplianceAnalytics.ImpactRow] {
        var rows: [TradingRulesComplianceAnalytics.ImpactRow] = []
        rows.reserveCapacity(TradingRulesComplianceAnalytics.RuleID.allCases.count)

        for rule in TradingRulesComplianceAnalytics.RuleID.allCases {
            guard let bucket = buckets[rule] else { continue }
            let pricedTotal = bucket.followed.priced + bucket.violated.priced
            guard pricedTotal > 0 else { continue }

            var followed = bucket.followed
            var violated = bucket.violated
            followed.finalizeMetrics()
            violated.finalizeMetrics()

            let sufficient =
                followed.priced >= PreferenceComplianceEngine.comparativeMinimum
                && violated.priced >= PreferenceComplianceEngine.comparativeMinimum

            var avgPnlDelta: Double?
            var winRateDeltaPoints: Double?
            var summary: String?
            if sufficient,
               let af = followed.avgNetPnl,
               let av = violated.avgNetPnl,
               let wf = followed.winRateFraction,
               let wv = violated.winRateFraction
            {
                avgPnlDelta = round((af - av) * 100) / 100
                winRateDeltaPoints = round((wf - wv) * 1000) / 10
                summary =
                    "When \(rule.label.lowercased()) was followed, win rate \(Int(wf * 100))% with avg realized P&L \(formatMoney(af)) (\(followed.priced) priced). When violated, win rate \(Int(wv * 100))% with avg realized P&L \(formatMoney(av)) (\(violated.priced) priced). Correlation only, not proof of causation."
            }

            rows.append(
                TradingRulesComplianceAnalytics.ImpactRow(
                    ruleID: rule,
                    ruleLabel: rule.label,
                    followed: followed,
                    violated: violated,
                    sufficientSample: sufficient,
                    summary: summary,
                    avgPnlDelta: avgPnlDelta,
                    winRateDeltaPoints: winRateDeltaPoints
                )
            )
        }
        return rows
    }

    private static func formatMoney(_ value: Double) -> String {
        let abs = Swift.abs(value)
        let text = String(format: "%.2f", abs)
        return value < 0 ? "-$\(text)" : "$\(text)"
    }
}

nonisolated extension TradingRulesComplianceAnalytics.ImpactSide {
    nonisolated static let empty = TradingRulesComplianceAnalytics.ImpactSide()

    nonisolated mutating func finalizeMetrics() {
        if priced > 0 {
            avgNetPnl = round((totalNetPnl / Double(priced)) * 100) / 100
            winRateFraction = Double(wins) / Double(priced)
        } else {
            avgNetPnl = nil
            winRateFraction = nil
        }

        if grossLosses < 0 {
            profitFactor = round((grossWins / abs(grossLosses)) * 100) / 100
        } else {
            profitFactor = nil
        }

        if priced > 0 {
            let winRate = winRateFraction ?? 0
            let lossRate = Double(losses) / Double(priced)
            let avgWin = wins > 0 ? grossWins / Double(wins) : 0
            let avgLossAbs = losses > 0 ? abs(grossLosses) / Double(losses) : 0
            expectancy = round((winRate * avgWin - lossRate * avgLossAbs) * 100) / 100
        } else {
            expectancy = nil
        }

        if realizedRrCount > 0 {
            avgRealizedRr = round((realizedRrSum / Double(realizedRrCount)) * 100) / 100
        } else {
            avgRealizedRr = nil
        }
    }
}
