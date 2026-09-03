import Foundation

/// Compares recent window vs prior history using the same deterministic metrics engine.
nonisolated enum PsychologyTrendAnalyzer {
    static let recentTradeWindow = 30
    static let minimumPriorTrades = 20

    static func analyze(
        trades: [Trade],
        checkIns: [TraderDailyCheckIn]
    ) -> [PsychologyCoachTrendFact] {
        let sorted = trades.sorted { $0.entryAt < $1.entryAt }
        guard sorted.count >= recentTradeWindow + minimumPriorTrades else { return [] }

        let recent = Array(sorted.suffix(recentTradeWindow))
        let prior = Array(sorted.dropLast(recentTradeWindow))

        var facts: [PsychologyCoachTrendFact] = []
        facts.append(contentsOf: disciplineTrend(recent: recent, prior: prior))
        facts.append(contentsOf: emotionTrend(recent: recent, prior: prior))
        facts.append(contentsOf: afterLossTrend(recent: recent, prior: prior, checkIns: checkIns))
        return facts
    }

    private static func disciplineTrend(recent: [Trade], prior: [Trade]) -> [PsychologyCoachTrendFact] {
        let recentRate = followedPlanRate(recent)
        let priorRate = followedPlanRate(prior)
        guard recent.count >= 15, prior.count >= minimumPriorTrades else { return [] }
        guard abs(recentRate - priorRate) >= 0.08 else { return [] }

        let improved = recentRate > priorRate
        return [
            PsychologyCoachTrendFact(
                id: "trend.discipline",
                headline: improved ? "Plan adherence has improved recently" : "Plan adherence has slipped recently",
                detail: String(
                    format: "Recent %d trades: %.0f%% followed plan vs prior history: %.0f%%",
                    recent.count,
                    recentRate * 100,
                    priorRate * 100
                ),
                recentSampleSize: recent.count,
                priorSampleSize: prior.count,
                reliability: recent.count >= 25 ? PsychologySampleReliability.developing.rawValue : PsychologySampleReliability.earlySignal.rawValue
            ),
        ]
    }

    private static func emotionTrend(recent: [Trade], prior: [Trade]) -> [PsychologyCoachTrendFact] {
        let recentFOMO = emotionShare(recent, emotion: "FOMO")
        let priorFOMO = emotionShare(prior, emotion: "FOMO")
        guard recent.count >= 15, prior.count >= minimumPriorTrades else { return [] }
        guard abs(recentFOMO - priorFOMO) >= 0.08 else { return [] }

        let decreased = recentFOMO < priorFOMO
        return [
            PsychologyCoachTrendFact(
                id: "trend.fomo",
                headline: decreased ? "FOMO-tagged trades decreased recently" : "FOMO-tagged trades increased recently",
                detail: String(
                    format: "Recent: %.0f%% FOMO vs prior: %.0f%% of tagged trades",
                    recentFOMO * 100,
                    priorFOMO * 100
                ),
                recentSampleSize: recent.count,
                priorSampleSize: prior.count,
                reliability: PsychologySampleReliability.developing.rawValue
            ),
        ]
    }

    private static func afterLossTrend(
        recent: [Trade],
        prior: [Trade],
        checkIns: [TraderDailyCheckIn]
    ) -> [PsychologyCoachTrendFact] {
        let recentEnriched = TraderPsychologyAnalyticsEngine.enrich(trades: recent, checkIns: checkIns)
        let priorEnriched = TraderPsychologyAnalyticsEngine.enrich(trades: prior, checkIns: checkIns)

        let recentAfterTwo = recentEnriched.filter { $0.consecutiveLossesBefore >= 2 }
        let priorAfterTwo = priorEnriched.filter { $0.consecutiveLossesBefore >= 2 }
        guard recentAfterTwo.count >= 8, priorAfterTwo.count >= 8 else { return [] }

        let recentM = TraderPsychologyAnalyticsEngine.metrics(for: recentAfterTwo.map(\.trade))
        let priorM = TraderPsychologyAnalyticsEngine.metrics(for: priorAfterTwo.map(\.trade))
        guard recentM.reliability.qualifiesForDashboardCard,
              priorM.reliability.qualifiesForDashboardCard
        else { return [] }

        let recentExp = recentM.expectancy ?? recentM.averagePnL ?? 0
        let priorExp = priorM.expectancy ?? priorM.averagePnL ?? 0
        let delta = NSDecimalNumber(decimal: recentExp - priorExp).doubleValue
        guard abs(delta) >= 10 else { return [] }

        let improved = delta > 0
        return [
            PsychologyCoachTrendFact(
                id: "trend.afterLosses",
                headline: improved
                    ? "Performance after consecutive losses has improved"
                    : "Performance after consecutive losses has weakened",
                detail: String(
                    format: "Recent after 2+ losses avg $%.0f vs prior $%.0f expectancy",
                    NSDecimalNumber(decimal: recentExp).doubleValue,
                    NSDecimalNumber(decimal: priorExp).doubleValue
                ),
                recentSampleSize: recentAfterTwo.count,
                priorSampleSize: priorAfterTwo.count,
                reliability: PsychologySampleReliability.developing.rawValue
            ),
        ]
    }

    private static func followedPlanRate(_ trades: [Trade]) -> Double {
        let tagged = trades.filter { $0.followedPlan != nil }
        guard !tagged.isEmpty else { return 0 }
        let yes = tagged.filter { $0.followedPlan == true }.count
        return Double(yes) / Double(tagged.count)
    }

    private static func emotionShare(_ trades: [Trade], emotion: String) -> Double {
        let tagged = trades.compactMap { trade -> String? in
            let raw = trade.emotion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !raw.isEmpty else { return nil }
            return raw
        }
        guard !tagged.isEmpty else { return 0 }
        let matches = tagged.filter { $0.caseInsensitiveCompare(emotion) == .orderedSame }.count
        return Double(matches) / Double(tagged.count)
    }
}
