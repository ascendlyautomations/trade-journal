import Foundation

/// Restores the live Home tab after TraxsPro preview ends using authoritative production sources.
@MainActor
enum TraxsProProductionRecovery {
    static func recoverAfterPreview(
        production: DataEnvironment,
        viewer: ProfileID
    ) {
        SessionOwnerTradesStore.shared.invalidate(profileID: viewer)
        SessionAccountsStore.shared.invalidate(profileID: viewer)
        SessionPayoutEntriesStore.shared.invalidate(profileID: viewer)
        SessionPayoutCyclesStore.shared.invalidate(profileID: viewer)
        WithdrawalsHistoryStore.shared.invalidate()
        TradingRulesCompliancePreferencesCache.invalidate(profileID: viewer)
        TradingRulesComplianceRecomputeCoordinator.resetForSessionBoundary()

        for accountID in JournalSampleDataPolicy.canonicalAccountIDs {
            SessionPayoutCyclesStore.shared.invalidate(accountID: accountID, profileID: viewer)
        }
        for tradeID in JournalSampleDataPolicy.canonicalTradeIDs {
            production.detailCache.removeTrade(id: tradeID)
        }
        SessionDailyCheckInsStore.shared.invalidate()
        CheckInHistorySessionStore.shared.invalidate()

        DashboardTabModelStore.recoverProductionDashboardAfterPreview(
            production: production,
            viewer: viewer
        )
    }
}