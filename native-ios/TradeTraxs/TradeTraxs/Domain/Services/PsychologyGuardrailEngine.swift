import Foundation

/// Evaluates informational guardrails from deterministic facts + live session state.
nonisolated enum PsychologyGuardrailEngine {
    static func activeNotices(
        facts: PsychologyCoachFacts,
        todayCheckIn: TraderDailyCheckIn?,
        enrichedTradesToday: [PsychologyEnrichedTrade],
        dismissedKeys: Set<String>,
        tradingDay: String
    ) -> [PsychologyGuardrailNotice] {
        var notices: [PsychologyGuardrailNotice] = []

        if let notice = consecutiveLossNotice(facts: facts, enriched: enrichedTradesToday) {
            notices.append(notice)
        }
        if let notice = lowSleepNotice(facts: facts, checkIn: todayCheckIn) {
            notices.append(notice)
        }
        if let notice = highStressNotice(facts: facts, checkIn: todayCheckIn) {
            notices.append(notice)
        }
        if let notice = lowFocusNotice(facts: facts, checkIn: todayCheckIn) {
            notices.append(notice)
        }
        if let notice = tradeCountNotice(facts: facts, enriched: enrichedTradesToday) {
            notices.append(notice)
        }

        return notices.filter { !dismissedKeys.contains(dedupeKey(for: $0, tradingDay: tradingDay)) }
    }

    static func dedupeKey(for notice: PsychologyGuardrailNotice, tradingDay: String) -> String {
        "\(notice.kind.rawValue).\(tradingDay)"
    }

    private static func consecutiveLossNotice(
        facts: PsychologyCoachFacts,
        enriched: [PsychologyEnrichedTrade]
    ) -> PsychologyGuardrailNotice? {
        guard let checkpoint = facts.guardrailFacts.consecutiveLossCheckpoint else { return nil }
        guard let last = enriched.last else { return nil }
        guard last.consecutiveLossesBefore >= checkpoint else { return nil }

        let wrAfter = facts.guardrailFacts.consecutiveLossWinRateAfter
        let wrBase = facts.guardrailFacts.consecutiveLossBaselineWinRate
        let wrText: String
        if let wrAfter, let wrBase {
            wrText = String(format: "Historically your win rate drops to %.0f%% after this point vs %.0f%% baseline.", wrAfter * 100, wrBase * 100)
        } else {
            wrText = "Historically your performance declines after this point."
        }

        return PsychologyGuardrailNotice(
            id: "guardrail.consecutiveLoss.\(checkpoint)",
            title: "Psychology Check",
            message: "You've taken \(checkpoint) consecutive losses. \(wrText)",
            kind: .consecutiveLosses
        )
    }

    private static func lowSleepNotice(
        facts: PsychologyCoachFacts,
        checkIn: TraderDailyCheckIn?
    ) -> PsychologyGuardrailNotice? {
        guard let threshold = facts.guardrailFacts.lowSleepHoursThreshold,
              let hours = checkIn?.sleepHours
        else { return nil }
        let value = NSDecimalNumber(decimal: hours).doubleValue
        guard value < threshold else { return nil }

        return PsychologyGuardrailNotice(
            id: "guardrail.lowSleep",
            title: "Low Sleep",
            message: String(
                format: "You logged %.1f hours of sleep today. Your historical performance has been weaker below %.0f hours.",
                value,
                threshold
            ),
            kind: .lowSleep
        )
    }

    private static func highStressNotice(
        facts: PsychologyCoachFacts,
        checkIn: TraderDailyCheckIn?
    ) -> PsychologyGuardrailNotice? {
        guard let stress = checkIn?.stressLevel, stress >= 4 else { return nil }
        guard facts.topInsights.contains(where: { $0.category == "mentalState" && $0.headline.localizedCaseInsensitiveContains("stress") }) else {
            return nil
        }
        return PsychologyGuardrailNotice(
            id: "guardrail.highStress",
            title: "High Stress",
            message: "You logged stress at \(stress)/5 today. Your journal shows weaker results on high-stress days.",
            kind: .highStress
        )
    }

    private static func lowFocusNotice(
        facts: PsychologyCoachFacts,
        checkIn: TraderDailyCheckIn?
    ) -> PsychologyGuardrailNotice? {
        guard let focus = checkIn?.focusLevel, focus <= 2 else { return nil }
        guard facts.topInsights.contains(where: { $0.category == "mentalState" && $0.headline.localizedCaseInsensitiveContains("focus") }) else {
            return nil
        }
        return PsychologyGuardrailNotice(
            id: "guardrail.lowFocus",
            title: "Low Focus",
            message: "Focus today: \(focus)/5. Your historical expectancy is lower on low-focus days.",
            kind: .lowFocus
        )
    }

    private static func tradeCountNotice(
        facts: PsychologyCoachFacts,
        enriched: [PsychologyEnrichedTrade]
    ) -> PsychologyGuardrailNotice? {
        guard let limit = facts.guardrailFacts.maxTradesDaySoftLimit else { return nil }
        guard let last = enriched.last, last.tradeNumberInDay > limit else { return nil }

        return PsychologyGuardrailNotice(
            id: "guardrail.tradeCount.\(limit)",
            title: "Trade Count",
            message: "You're on trade #\(last.tradeNumberInDay) today. Your first \(limit) trades historically outperform later ones in your journal.",
            kind: .tradeCount
        )
    }
}
