import Foundation

/// Target R:R (`rr`) vs max reached — mirrors web `dashboardRrTargetAnalysis.ts`.
nonisolated struct DashboardRrTargetAnalysis: Sendable, Equatable {
    static let minPairedDescriptive = 1
    static let minPairedRecommend = 5
    static let minBucket = 3

    var tradeCount: Int
    var pairedCount: Int
    var pairedNonPositiveCount: Int
    var pairedPositiveCount: Int
    var avgTargetRr: Decimal?
    var avgMaxRrReached: Decimal?
    /// Mean max÷target on paired trades; may exceed 1. Not realized P&L.
    var avgTargetAttainmentRatio: Decimal?
    var sampleSummary: String?
    var headline: String?
    var bullets: [String]

    /// Strict eligibility for the R:R Targeting panel only (not dashboard Avg Max R:R KPI).
    static func isEligible(_ trade: Trade) -> Bool {
        guard let target = trade.riskReward, trade.maxRrReached != nil, target > 0 else {
            return false
        }
        return true
    }

    static func compute(from trades: [Trade]) -> DashboardRrTargetAnalysis {
        let tradeCount = trades.count
        var paired: [(target: Decimal, maxRr: Decimal, pnl: Decimal)] = []
        for trade in trades where isEligible(trade) {
            paired.append((
                trade.riskReward!,
                trade.maxRrReached!,
                trade.realizedPnL?.amount ?? 0
            ))
        }

        var pairedNonPositive = 0
        var pairedPositive = 0
        for p in paired {
            if p.pnl > 0 { pairedPositive += 1 } else { pairedNonPositive += 1 }
        }

        var result = DashboardRrTargetAnalysis(
            tradeCount: tradeCount,
            pairedCount: paired.count,
            pairedNonPositiveCount: pairedNonPositive,
            pairedPositiveCount: pairedPositive,
            avgTargetRr: nil,
            avgMaxRrReached: nil,
            avgTargetAttainmentRatio: nil,
            sampleSummary: nil,
            headline: nil,
            bullets: []
        )

        if paired.count < minPairedDescriptive {
            result.headline = "Record both values to unlock R:R Targeting."
            result.bullets = [
                "Add both Targeted Risk/Reward and Max R:R Reached on the same trade.",
            ]
            if tradeCount > 0 {
                result.bullets.append(
                    "\(tradeCount) trade\(tradeCount == 1 ? "" : "s") match your current filters; none have both fields yet."
                )
            }
            return result
        }

        result.avgTargetRr = averageDecimal(paired.map(\.target))
        result.avgMaxRrReached = averageDecimal(paired.map(\.maxRr))
        result.avgTargetAttainmentRatio = averageAttainment(paired)
        result.sampleSummary = buildSampleSummary(pairedCount: paired.count, tradeCount: tradeCount)

        let attainment = result.avgTargetAttainmentRatio
        let canRecommend = paired.count >= minPairedRecommend
        let descriptiveOnly = !canRecommend

        if let attainment,
           let avgMax = result.avgMaxRrReached,
           let avgTarget = result.avgTargetRr
        {
            let pct = Int(truncating: NSDecimalNumber(decimal: attainment * 100))
            let prefix = descriptiveOnly ? "Early read (small sample):" : "In this paired sample,"
            result.bullets.append(
                "\(prefix) average target attainment is \(pct)% (\(formatR(avgMax))R max reached vs \(formatR(avgTarget))R targeted). Values above 100% mean price exceeded the target before exit."
            )
        }

        var bucketStats: [String: (trades: Int, wins: Int, targetSum: Decimal, maxSum: Decimal)] = [:]
        for p in paired {
            let label = bucketLabel(p.target)
            var b = bucketStats[label] ?? (0, 0, 0, 0)
            b.trades += 1
            b.targetSum += p.target
            b.maxSum += p.maxRr
            if p.pnl > 0 { b.wins += 1 }
            bucketStats[label] = b
        }

        if canRecommend,
           let attainment,
           attainment < Decimal(string: "0.85")!,
           let avgTarget = result.avgTargetRr
        {
            let suggested = Self.decimalMax(
                Decimal(string: "0.5")!,
                Self.rrRounded(avgTarget * attainment * 2, scale: 1)
            )
            result.bullets.append(
                "Among these \(paired.count) trades, price often reversed before the full target — exits planned nearer \(formatR(suggested))R may align with typical extension (not a profit guarantee)."
            )
        }

        if canRecommend, let avgTarget = result.avgTargetRr {
            var bestWin: (label: String, winRate: Decimal, avgTarget: Decimal, trades: Int)?
            for (label, b) in bucketStats where b.trades >= minBucket {
                let wr = Decimal(b.wins) / Decimal(b.trades)
                let avgT = b.targetSum / Decimal(b.trades)
                if bestWin == nil || wr > bestWin!.winRate {
                    bestWin = (label, wr, avgT, b.trades)
                }
            }
            if let bestWin,
               Self.decimalAbs(bestWin.avgTarget - avgTarget) > Decimal(string: "0.4")!,
               bestWin.winRate >= Decimal(string: "0.45")!
            {
                let wrPct = Int(truncating: NSDecimalNumber(decimal: bestWin.winRate * 100))
                result.bullets.append(
                    "Among paired trades, \(bestWin.label) targets (\(bestWin.trades) trades) show a \(wrPct)% win rate vs \(formatR(avgTarget))R average target in this sample — consider whether ~\(formatR(bestWin.avgTarget))R plans fit your edge."
                )
            }
        }

        if canRecommend {
            for (label, b) in bucketStats where b.trades >= minBucket {
                let avgMax = b.maxSum / Decimal(b.trades)
                let avgTarget = b.targetSum / Decimal(b.trades)
                if avgTarget >= 3, avgMax < avgTarget * Decimal(string: "0.7")! {
                    result.bullets.append(
                        "For \(label) targets (\(b.trades) paired trades), price peaked around \(formatR(avgMax))R before exit while targeting ~\(formatR(avgTarget))R — partials or trails may protect open heat."
                    )
                    break
                }
            }
        }

        if descriptiveOnly, result.bullets.count <= 2 {
            let need = minPairedRecommend - paired.count
            result.bullets.append(
                "Add \(need) more trade\(need == 1 ? "" : "s") with both values recorded for stronger recommendations."
            )
        }

        if let avgTarget = result.avgTargetRr,
           let avgMax = result.avgMaxRrReached
        {
            if canRecommend,
               avgTarget >= 4,
               avgMax <= avgTarget * Decimal(string: "0.6")!
            {
                result.headline = "High targets vs extension in paired sample"
            } else if let attainment, attainment >= Decimal(string: "0.9")! {
                result.headline = "Target attainment aligns with how far paired trades ran"
            } else {
                result.headline = "Target attainment (paired trades only)"
            }
        }

        return result
    }

    private static func averageAttainment(_ paired: [(target: Decimal, maxRr: Decimal, pnl: Decimal)]) -> Decimal? {
        guard !paired.isEmpty else { return nil }
        var sum = Decimal(0)
        for p in paired where p.target > 0 {
            sum += p.maxRr / p.target
        }
        return sum / Decimal(paired.count)
    }

    private static func buildSampleSummary(pairedCount: Int, tradeCount: Int) -> String {
        let label = pairedCount == 1
            ? "Based on 1 trade with both values recorded."
            : "Based on \(pairedCount) trades with both values recorded."
        guard tradeCount > pairedCount else { return label }
        let excluded = tradeCount - pairedCount
        return "\(label) (\(excluded) other filtered trade\(excluded == 1 ? "" : "s") excluded — missing target or max R:R.)"
    }

    private static func bucketLabel(_ target: Decimal) -> String {
        let t = NSDecimalNumber(decimal: target).doubleValue
        if t < 1 { return "Under 1R" }
        if t < 2 { return "1–2R" }
        if t < 3 { return "2–3R" }
        if t < 4 { return "3–4R" }
        if t < 5 { return "4–5R" }
        return "5R+"
    }

    private static func averageDecimal(_ values: [Decimal]) -> Decimal? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Decimal(values.count)
    }

    private static func formatR(_ value: Decimal) -> String {
        NumberDisplay.ratio(value, fractionDigits: 2)
    }

    private static func rrRounded(_ value: Decimal, scale: Int) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }

    private static func decimalMax(_ a: Decimal, _ b: Decimal) -> Decimal {
        a > b ? a : b
    }

    private static func decimalAbs(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
    }
}
