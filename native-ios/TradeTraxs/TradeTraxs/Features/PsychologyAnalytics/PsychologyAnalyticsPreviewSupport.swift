import Foundation

/// In-memory sample psychology analytics for the Free History preview (no Supabase writes).
@MainActor
enum PsychologyAnalyticsPreviewSupport {
    private(set) static var ephemeralHistoryPreviewActive = false

    static let inlineHistoryPreviewCount = 5

    static var usesSampleCheckInHistory: Bool {
        TraxsProPreviewSession.shared.isDashboardPreviewActive || ephemeralHistoryPreviewActive
    }

    static func beginEphemeralHistoryPreview() {
        guard !TraxsProPreviewSession.shared.isDashboardPreviewActive else { return }
        ephemeralHistoryPreviewActive = true
        seedCheckInHistorySessionIfNeeded()
    }

    static func endEphemeralHistoryPreview() {
        guard ephemeralHistoryPreviewActive else { return }
        ephemeralHistoryPreviewActive = false
        if !TraxsProPreviewSession.shared.isDashboardPreviewActive {
            CheckInHistorySessionStore.shared.invalidate()
        }
    }

    static func seedCheckInHistorySessionIfNeeded() {
        guard CheckInHistorySessionStore.shared.summaries.isEmpty else { return }
        let trades = eligibleSampleTrades()
        let checkIns = DemoCanonicalDataset.checkIns()
        CheckInHistorySessionStore.shared.update(
            summaries: CheckInHistoryAggregator.buildSummaries(checkIns: checkIns, trades: trades),
            checkIns: checkIns,
            trades: trades
        )
    }

    struct SamplePresentation {
        let report: PsychologyAnalyticsReport
        let unlockProgress: PsychologyInsightsUnlockProgress
        let historySummaries: [CheckInHistoryDaySummary]
    }

    static func buildSamplePresentation() -> SamplePresentation {
        let trades = eligibleSampleTrades()
        let checkIns = DemoCanonicalDataset.checkIns()
        let report = TraderPsychologyAnalyticsEngine.buildReport(trades: trades, checkIns: checkIns)
        let unlock = PsychologyInsightsUnlockProgress(
            tradingDayCheckInCount: PsychologyCheckInHistoryGate.countPsychologyCheckInHistoryDays(checkIns),
            tradeCount: trades.count
        )
        let summaries = CheckInHistoryAggregator.buildSummaries(checkIns: checkIns, trades: trades)
            .filter { $0.matches(contentFilter: .psychology) }
        return SamplePresentation(
            report: report,
            unlockProgress: unlock,
            historySummaries: summaries
        )
    }

    static func resolvedPresentation(
        fallbackReport: PsychologyAnalyticsReport?,
        fallbackUnlock: PsychologyInsightsUnlockProgress
    ) -> SamplePresentation {
        if let fallbackReport {
            let summaries = CheckInHistorySessionStore.shared.summaries
                .filter { $0.matches(contentFilter: .psychology) }
            return SamplePresentation(
                report: fallbackReport,
                unlockProgress: fallbackUnlock,
                historySummaries: summaries.isEmpty
                    ? buildSamplePresentation().historySummaries
                    : summaries
            )
        }
        return buildSamplePresentation()
    }

    private static func eligibleSampleTrades() -> [Trade] {
        DemoCanonicalDataset.trades().filter { $0.mode != .backtest }
    }
}