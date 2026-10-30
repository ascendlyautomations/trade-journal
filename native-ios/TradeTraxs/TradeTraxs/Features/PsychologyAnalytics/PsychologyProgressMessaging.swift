import Foundation

enum PsychologyProgressMessaging {
    static let unlockOverviewCopy =
        "5 check-in days and 5 trades unlock your analytics overview. Personalized comparison insights need more matched data and tagged trades."

    static func comparisonInsightGapMessage(report: PsychologyAnalyticsReport) -> String? {
        guard report.dashboardCards.isEmpty else { return nil }
        return "Comparison insights need at least 5 trades in each group we compare (often 10+ total with check-ins and psychology tags on the same days)."
    }

    static func postUnlockInsightGapMessages(
        report: PsychologyAnalyticsReport,
        trades: [Trade],
        checkIns: [TraderDailyCheckIn]
    ) -> [String] {
        var messages = PsychologyCoachFactsBuilder.dataGapMessages(
            report: report,
            trades: trades,
            checkIns: checkIns
        )
        if let comparison = comparisonInsightGapMessage(report: report) {
            messages.append(comparison)
        }
        return messages
    }
}
