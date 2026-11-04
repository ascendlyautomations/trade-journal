import Foundation

@MainActor
enum PsychologyAnalyticsReportComposer {
    static func publish(
        report: PsychologyAnalyticsReport,
        scopedTrades: [Trade],
        checkIns: [TraderDailyCheckIn],
        profileID: ProfileID,
        scope: PsychologyAnalyticsScopeResolver.Resolved
    ) {
        let unlock = PsychologyInsightsUnlockProgress(
            tradingDayCheckInCount: PsychologyCheckInHistoryGate.countPsychologyCheckInHistoryDays(
                checkIns
            ),
            tradeCount: scopedTrades.count
        )
        let early = EarlyPsychologyInsightsBuilder.build(trades: scopedTrades, checkIns: checkIns)
        let displayInsightCards = EarlyPsychologyInsightsBuilder.merge(
            early: early,
            reportCards: report.dashboardCards
        )
        let gapMessages = displayInsightCards.isEmpty
            ? PsychologyProgressMessaging.postUnlockInsightGapMessages(
                report: report,
                trades: scopedTrades,
                checkIns: checkIns
            )
            : []
        PsychologyAnalyticsSessionStore.shared.update(
            report: report,
            unlockProgress: unlock,
            postUnlockGapMessages: gapMessages,
            displayInsightCards: displayInsightCards,
            profileID: profileID,
            scopeFingerprint: scope.fingerprint,
            scopeLabel: scope.label
        )

        let facts = PsychologyCoachFactsBuilder.build(
            report: report,
            trades: scopedTrades,
            checkIns: checkIns
        )
        let summary = PsychologyCoachDeterministicCoach.buildSummary(from: facts)
        PsychologyCoachSessionStore.shared.update(facts: facts, summary: summary)
    }

    static func publish(
        scopedTrades: [Trade],
        checkIns: [TraderDailyCheckIn],
        profileID: ProfileID,
        scope: PsychologyAnalyticsScopeResolver.Resolved
    ) {
        let report = TraderPsychologyAnalyticsEngine.buildReport(
            trades: scopedTrades,
            checkIns: checkIns
        )
        publish(
            report: report,
            scopedTrades: scopedTrades,
            checkIns: checkIns,
            profileID: profileID,
            scope: scope
        )
    }
}

enum PsychologyAnalyticsCheckInGate {
    @MainActor
    static func mergedCheckIns(profileID: ProfileID) -> [TraderDailyCheckIn] {
        var merged = SessionDailyCheckInsStore.shared.checkIns
        let historyCheckIns = CheckInHistorySessionStore.shared.checkIns
        if !historyCheckIns.isEmpty {
            merged = TraderDailyCheckInMerge.preferNewer(primary: merged, secondary: historyCheckIns)
        }
        if let today = TraderDailyCheckInStore.shared.todayCheckIn,
           today.ownerProfileID == profileID
        {
            merged = TraderDailyCheckInMerge.preferNewer(primary: merged, secondary: [today])
        }
        return merged
    }
}

enum PsychologyAnalyticsTradeScope {
    static func chartInputs(
        trades: [Trade],
        accounts: [TradingAccount]
    ) -> [DashboardChartMetrics.Input] {
        let linkedModes = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.mode) })
        return trades.compactMap { trade in
            let accountMode = trade.accountID.flatMap { id in
                accounts.first(where: { $0.id == id })?.mode
            }
            guard DashboardAccountScopePolicy.includesTradeInDashboardStatistics(
                trade: trade,
                accountMode: accountMode
            ) else { return nil }
            let linkedType = trade.accountID.flatMap { linkedModes[$0] }.map {
                ProfileStatisticsMetrics.accountTypeString(for: $0)
            }
            return DashboardScopeFilterSupport.makeChartInput(
                trade: trade,
                linkedAccountType: linkedType
            )
        }
    }

    static func scopedTrades(
        ownerTrades: [Trade],
        accounts: [TradingAccount],
        scope: DashboardClientScopeFilter
    ) -> [Trade] {
        var filter = scope
        filter.linkedAccountModes = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.mode) })
        let inputs = chartInputs(trades: ownerTrades, accounts: accounts)
        return DashboardChartMetrics.filteredTrades(from: inputs, scope: filter)
    }
}
