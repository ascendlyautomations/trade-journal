import Foundation

/// In-memory sample psychology analytics for Free History preview (no Supabase writes).
@MainActor
enum PsychologyAnalyticsPreviewSupport {
    private(set) static var ephemeralHistoryPreviewActive = false

    static let inlineHistoryPreviewCount = 5

    static var usesSampleCheckInHistory: Bool {
        TraxsProPreviewSession.shared.activePreviewEnvironment != nil || ephemeralHistoryPreviewActive
    }

    static func beginEphemeralHistoryPreview() {
        guard TraxsProPreviewSession.shared.activePreviewEnvironment == nil else { return }
        ephemeralHistoryPreviewActive = true
    }

    static func endEphemeralHistoryPreview() {
        guard ephemeralHistoryPreviewActive else { return }
        ephemeralHistoryPreviewActive = false
    }

    static func sampleCheckInSummaries() -> [CheckInHistoryDaySummary] {
        if let preview = TraxsProPreviewSession.shared.activePreviewEnvironment {
            return preview.checkInHistorySummaries
        }
        let trades = eligibleSampleTrades()
        let checkIns = DemoCanonicalDataset.checkIns()
        return CheckInHistoryAggregator.buildSummaries(checkIns: checkIns, trades: trades)
    }

    struct SamplePresentation {
        let report: PsychologyAnalyticsReport
        let unlockProgress: PsychologyInsightsUnlockProgress
        let historySummaries: [CheckInHistoryDaySummary]
        let displayInsightCards: [PsychologyInsightCard]
        let postUnlockGapMessages: [String]
        let coachSummary: PsychologyCoachSummary
    }

    static func buildSamplePresentation() -> SamplePresentation {
        let trades = eligibleSampleTrades()
        let checkIns = DemoCanonicalDataset.checkIns()
        let owner = trades.first?.ownerProfileID ?? DemoExperienceSupport.profileID
        let preferences = DemoCanonicalDataset.previewPreferenceContext(for: owner)
        return buildSamplePresentation(
            trades: trades,
            checkIns: checkIns,
            historySummaries: nil,
            preferences: preferences
        )
    }

    static func buildSamplePresentation(
        trades: [Trade],
        checkIns: [TraderDailyCheckIn],
        historySummaries: [CheckInHistoryDaySummary]?,
        preferences: PreferenceRuleContext? = nil
    ) -> SamplePresentation {
        let report = TraderPsychologyAnalyticsEngine.buildReport(
            trades: trades,
            checkIns: checkIns,
            preferences: preferences
        )
        let unlock = PsychologyInsightsUnlockProgress(
            tradingDayCheckInCount: PsychologyCheckInHistoryGate.countPsychologyCheckInHistoryDays(checkIns),
            tradeCount: trades.count
        )
        let builtSummaries = historySummaries
            ?? CheckInHistoryAggregator.buildSummaries(checkIns: checkIns, trades: trades)
        let summaries = builtSummaries.filter { $0.matches(contentFilter: .psychology) }
        let displayInsightCards = report.dashboardCards
        let gapMessages = displayInsightCards.isEmpty
            ? PsychologyProgressMessaging.postUnlockInsightGapMessages(
                report: report,
                trades: trades,
                checkIns: checkIns
            )
            : []
        let facts = PsychologyCoachFactsBuilder.build(
            report: report,
            trades: trades,
            checkIns: checkIns,
            preferences: preferences
        )
        let coachSummary = PsychologyCoachDeterministicCoach.buildSummary(from: facts)
        return SamplePresentation(
            report: report,
            unlockProgress: unlock,
            historySummaries: summaries,
            displayInsightCards: displayInsightCards,
            postUnlockGapMessages: gapMessages,
            coachSummary: coachSummary
        )
    }

    static func resolvedPresentation(
        fallbackReport: PsychologyAnalyticsReport?,
        fallbackUnlock: PsychologyInsightsUnlockProgress
    ) -> SamplePresentation {
        if let preview = TraxsProPreviewSession.shared.activePreviewEnvironment {
            return preview.psychologySamplePresentation
        }
        if let fallbackReport {
            let trades = eligibleSampleTrades()
            let checkIns = DemoCanonicalDataset.checkIns()
            let summaries = sampleCheckInSummaries().filter { $0.matches(contentFilter: .psychology) }
            let preferences = DemoCanonicalDataset.previewPreferenceContext(
                for: trades.first?.ownerProfileID ?? DemoExperienceSupport.profileID
            )
            let displayInsightCards = fallbackReport.dashboardCards
            let gapMessages = displayInsightCards.isEmpty
                ? PsychologyProgressMessaging.postUnlockInsightGapMessages(
                    report: fallbackReport,
                    trades: trades,
                    checkIns: checkIns
                )
                : []
            let facts = PsychologyCoachFactsBuilder.build(
                report: fallbackReport,
                trades: trades,
                checkIns: checkIns,
                preferences: preferences
            )
            let coachSummary = PsychologyCoachDeterministicCoach.buildSummary(from: facts)
            return SamplePresentation(
                report: fallbackReport,
                unlockProgress: fallbackUnlock,
                historySummaries: summaries.isEmpty
                    ? buildSamplePresentation().historySummaries
                    : summaries,
                displayInsightCards: displayInsightCards,
                postUnlockGapMessages: gapMessages,
                coachSummary: coachSummary
            )
        }
        return buildSamplePresentation()
    }

    private static func eligibleSampleTrades() -> [Trade] {
        DemoCanonicalDataset.trades().filter { $0.mode != .backtest }
    }
}