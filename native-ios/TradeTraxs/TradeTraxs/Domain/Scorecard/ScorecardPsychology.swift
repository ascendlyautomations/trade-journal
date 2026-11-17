import Foundation

nonisolated enum ScorecardPsychology {
    static func countEasternCalendarTradingDays(trades: [ScorecardTrade]) -> Int {
        Set(trades.compactMap(dayKey)).count
    }

    static func score(
        trades: [ScorecardTrade],
        checkIns: [TraderDailyCheckIn],
        domainTrades: [Trade]
    ) -> ScorecardCategoryResult {
        _ = domainTrades
        let easternTradingDays = countEasternCalendarTradingDays(trades: trades)
        let completeDates = Set(checkIns.filter(\.isComplete).map(\.checkInDate))
        var matchedDayCount = 0
        var seen = Set<String>()
        for trade in trades {
            guard let key = dayKey(trade), !seen.contains(key) else { continue }
            seen.insert(key)
            if completeDates.contains(key) {
                matchedDayCount += 1
            }
        }
        let coveragePercent = easternTradingDays > 0
            ? Int((Double(matchedDayCount) / Double(easternTradingDays) * 100).rounded())
            : 0
        let value = easternTradingDays > 0
            ? "\(matchedDayCount) of \(easternTradingDays) trading days"
            : "No trading days in this scope"

        return ScorecardCategoryResult(
            id: .psychology,
            title: "Psychology",
            weight: ScorecardConstants.categoryWeights[.psychology] ?? 0.3,
            score: nil,
            coveragePercent: coveragePercent,
            reliability: ScorecardReliabilitySupport.resolve(sampleSize: matchedDayCount),
            eligible: false,
            subMetrics: [
                ScorecardSubMetric(
                    id: "psych.checkin_coverage",
                    label: "Check-ins on trading days",
                    value: value,
                    explanation: "Eastern calendar days with a complete check-in and at least one trade.",
                    sampleSize: easternTradingDays,
                    sampleLabel: "trading days"
                ),
            ],
            strengths: [],
            weaknesses: [],
            dataGaps: []
        )
    }

    private static func dayKey(_ trade: ScorecardTrade) -> String? {
        if let key = trade.psychologyDayKey, !key.isEmpty { return key }
        let key = TraderPsychologyAnalyticsFoundation.tradeDateKey(
            for: Date(timeIntervalSince1970: TimeInterval(trade.entryTimeMs) / 1000)
        )
        return key.isEmpty ? nil : key
    }
}
