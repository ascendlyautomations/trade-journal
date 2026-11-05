import Foundation

nonisolated enum ScorecardPsychology {
    static func countEasternCalendarTradingDays(trades: [ScorecardTrade]) -> Int {
        Set(
            trades.compactMap { trade -> String? in
                if let key = trade.psychologyDayKey, !key.isEmpty { return key }
                return TraderPsychologyAnalyticsFoundation.tradeDateKey(
                    for: Date(timeIntervalSince1970: TimeInterval(trade.entryTimeMs) / 1000)
                )
            }
        ).count
    }

    static func score(
        trades: [ScorecardTrade],
        checkIns: [TraderDailyCheckIn],
        domainTrades: [Trade]
    ) -> ScorecardCategoryResult {
        let weight = ScorecardConstants.categoryWeights[.psychology] ?? 0.3
        var subMetrics: [ScorecardSubMetric] = []
        var strengths: [String] = []
        var weaknesses: [String] = []
        var dataGaps: [String] = []

        let easternTradingDays = countEasternCalendarTradingDays(trades: trades)
        let matchedDays = EarlyPsychologyInsightsBuilder.buildMatchedTradingDays(
            trades: domainTrades,
            checkIns: checkIns
        )
        let matchedDayCount = matchedDays.count
        let checkInDayCount = Set(checkIns.map(\.checkInDate).filter { !$0.isEmpty }).count

        subMetrics.append(
            ScorecardSubMetric(
                id: "psych.phase1_mode",
                label: "Psychology score (Phase 1)",
                value: "Insights only",
                explanation:
                    "No 0–100 psychology score in Phase 1, avoids double-counting plan adherence from Discipline. Patterns and coverage appear below.",
                sampleSize: matchedDayCount,
                sampleLabel: "matched days"
            )
        )

        subMetrics.append(
            ScorecardSubMetric(
                id: "psych.matched_days",
                label: "Matched check-in + trade days",
                value: String(matchedDayCount),
                explanation:
                    "Eastern calendar days with a complete check-in and at least one trade on the same calendar day.",
                sampleSize: matchedDayCount,
                sampleLabel: "matched days"
            )
        )

        if easternTradingDays > 0 {
            let checkInCoverage = min(Double(checkInDayCount) / Double(easternTradingDays), 1)
            subMetrics.append(
                ScorecardSubMetric(
                    id: "psych.checkin_coverage",
                    label: "Check-in days vs Eastern trade days (coverage)",
                    value: ScorecardReliabilitySupport.formatPercent(checkInCoverage),
                    explanation: "Check-in habit relative to days you traded, coverage only.",
                    sampleSize: checkInDayCount,
                    sampleLabel: "check-in days"
                )
            )
            if checkInCoverage < 0.2, easternTradingDays >= 5 {
                dataGaps.append("Complete daily check-ins on days you trade to improve psychology coverage.")
            }
        }

        let totalMatchedTrades = matchedDays.reduce(0) { $0 + $1.tradeCount }
        let dayReliability = EarlyPsychologyInsightsBuilder.resolveMatchedDayReliability(
            dayCount: matchedDayCount,
            tradeCount: totalMatchedTrades
        )

        if matchedDayCount >= 1 {
            let cards = EarlyPsychologyInsightsBuilder.build(trades: domainTrades, checkIns: checkIns)
            for card in cards.filter({ $0.id.contains(".compare") }).prefix(2) {
                strengths.append(
                    "\(card.headline) (\(card.reliability.label), association, not causation)."
                )
            }
            for card in cards.filter({ $0.id.contains(".poor") }).prefix(1) {
                let detailPart = card.detail.split(separator: "·").first.map(String.init) ?? card.detail
                weaknesses.append("\(card.headline): \(detailPart.trimmingCharacters(in: .whitespaces)) (exploratory).")
            }
            if cards.contains(where: { $0.id == "matchedDays.overview" }), strengths.isEmpty {
                strengths.append(
                    "You have matched check-in days to explore lifestyle inputs alongside trading (associations only)."
                )
            }
        } else {
            dataGaps.append(
                "Log a complete daily check-in on the same Eastern calendar day as a trade to match psychology data."
            )
        }

        let coveragePercent = ScorecardReliabilitySupport.clampScore(
            easternTradingDays > 0
                ? Double(matchedDayCount) / Double(easternTradingDays) * 100
                : 0
        )

        let reliability: ScorecardReliability =
            matchedDayCount >= 1 && dayReliability != .insufficient
            ? dayReliability
            : ScorecardReliabilitySupport.resolve(sampleSize: checkInDayCount)

        return ScorecardCategoryResult(
            id: .psychology,
            title: "Psychology",
            weight: weight,
            score: nil,
            coveragePercent: coveragePercent,
            reliability: reliability,
            eligible: false,
            subMetrics: subMetrics,
            strengths: strengths,
            weaknesses: weaknesses,
            dataGaps: dataGaps
        )
    }
}
