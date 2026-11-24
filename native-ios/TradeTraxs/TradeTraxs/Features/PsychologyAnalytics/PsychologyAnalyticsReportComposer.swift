import Foundation

@MainActor
enum PsychologyAnalyticsReportComposer {
    static func publish(
        report: PsychologyAnalyticsReport,
        scopedTrades: [Trade],
        checkIns: [TraderDailyCheckIn],
        profileID: ProfileID,
        scope: PsychologyAnalyticsScopeResolver.Resolved,
        preferences: PreferenceRuleContext? = nil
    ) {
        let unlock = PsychologyInsightsUnlockProgress(
            tradingDayCheckInCount: PsychologyCheckInHistoryGate.countPsychologyCheckInHistoryDays(
                checkIns
            ),
            tradeCount: scopedTrades.count
        )
        let displayInsightCards = report.dashboardCards
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
            checkIns: checkIns,
            preferences: preferences
        )
        let summary = PsychologyCoachDeterministicCoach.buildSummary(from: facts)
        PsychologyCoachSessionStore.shared.update(facts: facts, summary: summary)
    }

    static func publish(
        scopedTrades: [Trade],
        checkIns: [TraderDailyCheckIn],
        profileID: ProfileID,
        scope: PsychologyAnalyticsScopeResolver.Resolved,
        preferences: PreferenceRuleContext? = nil
    ) {
        let report = TraderPsychologyAnalyticsEngine.buildReport(
            trades: scopedTrades,
            checkIns: checkIns,
            preferences: preferences
        )
        publish(
            report: report,
            scopedTrades: scopedTrades,
            checkIns: checkIns,
            profileID: profileID,
            scope: scope,
            preferences: preferences
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

nonisolated enum PsychologyAnalyticsTradeScope {
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

    /// Trading Rules compliance, Eastern entry-time windows aligned with rule day/week keys.
    static func complianceScopedTrades(
        ownerTrades: [Trade],
        accounts: [TradingAccount],
        scope: DashboardClientScopeFilter,
        now: Date = Date()
    ) -> [Trade] {
        var filter = scope
        filter.linkedAccountModes = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.mode) })
        let inputs = chartInputs(trades: ownerTrades, accounts: accounts)
        let withoutDate = DashboardChartMetrics.filteredTrades(
            from: inputs,
            scope: DashboardClientScopeFilter(
                accountFilter: filter.accountFilter,
                dateRange: .all,
                customInterval: nil,
                accountMode: filter.accountMode,
                showPublicOnly: filter.showPublicOnly,
                linkedAccountModes: filter.linkedAccountModes
            )
        )
        guard let window = TradingRulesDisciplineScopeInterval.currentInterval(scope: scope, now: now)
        else {
            return withoutDate
        }
        return withoutDate.filter { trade in
            let entry = DashboardScopeFilterSupport.dashboardTradeFilterDate(for: trade)
            return entry >= window.start && entry <= window.end
        }
    }
}
