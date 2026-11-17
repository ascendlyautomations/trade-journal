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
            wrText = "Historically your win rate drops to \(NumberDisplay.percent(wrAfter * 100, minimumFractionDigits: 0, maximumFractionDigits: 0)) after this point vs \(NumberDisplay.percent(wrBase * 100, minimumFractionDigits: 0, maximumFractionDigits: 0)) baseline."
        } else {
            wrText = "Historically your performance declines after this point."
        }

        let message = facts.guardrailFacts.personalLossPause
            ? "You've reached your pause of \(NumberDisplay.integer(checkpoint)) consecutive losses. \(wrText)"
            : "You've taken \(NumberDisplay.integer(checkpoint)) consecutive losses. \(wrText)"
        return PsychologyGuardrailNotice(
            id: "guardrail.consecutiveLoss.\(checkpoint)",
            title: "Psychology Check",
            message: message,
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
        guard let stress = checkIn?.stressLevel, TraderDailyCheckInStressScale.isElevated(stress) else { return nil }
        guard facts.guardrailFacts.highStressWeaker else { return nil }
        return PsychologyGuardrailNotice(
            id: "guardrail.highStress",
            title: "High Stress",
            message: "You logged \(TraderDailyCheckInStressScale.displayText(for: stress)) today. Your journal shows weaker results on high-stress days.",
            kind: .highStress
        )
    }

    private static func lowFocusNotice(
        facts: PsychologyCoachFacts,
        checkIn: TraderDailyCheckIn?
    ) -> PsychologyGuardrailNotice? {
        guard let focus = checkIn?.focusLevel, focus <= 2 else { return nil }
        guard facts.guardrailFacts.lowFocusWeaker else { return nil }
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

        let message = facts.guardrailFacts.personalTradeCap
            ? "You're on trade #\(last.tradeNumberInDay) today, past your daily cap of \(limit). Trades within that cap have been stronger in your history."
            : "You're on trade #\(last.tradeNumberInDay) today. Your first three trades have been stronger than later ones."
        return PsychologyGuardrailNotice(
            id: "guardrail.tradeCount.\(limit)",
            title: "Trade Count",
            message: message,
            kind: .tradeCount
        )
    }
}
