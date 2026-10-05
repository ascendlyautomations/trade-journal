import Foundation

/// Profile Trades tab — presentation-only copy-action grouping (mirrors owner Trades list).
nonisolated enum ProfileTradesDisplayGrouping {
    static func visibleSummaries(
        journalItems: [TradeOwnerJournalSummary],
        filter: ProfileTradesFilter,
        sort: ProfileTradesSort,
        accounts: [TradingAccount] = [],
        accountModesByID: [TradingAccountID: TradingAccountMode] = [:],
        deferCopyModeSummaryUntilAuthoritativeJournal: Bool = false
    ) -> [TradeSummary] {
        let filtered = journalItems.filter { filter.matches($0.summary) }
        let sorted = sort.sortedJournal(filtered)
        let grouped = CopyTradeJournalGrouping.group(sorted, accounts: accounts)
        let resolvedModes = CopyTradePresentation.mergedAccountModes(
            journalItems: journalItems,
            accountModesByID: accountModesByID
        )
        return grouped.map { item in
            switch item {
            case .single(let row):
                return row.summary
            case .copyGroup(let group):
                let participating = CopyTradePresentation.participatingAccountIDsForCopyGroup(
                    group.members
                )
                if deferCopyModeSummaryUntilAuthoritativeJournal, participating.isEmpty {
                    return group.representative.summary
                }
                let counts = CopyTradePresentation.modeCountsForParticipatingAccounts(
                    participatingAccountIDs: participating,
                    members: group.members,
                    accountModesByID: resolvedModes
                )
                let modeSummary = CopyTradePresentation.publicAcrossAccountsSummary(
                    participatingAccountCount: participating.count,
                    counts: counts
                )
                #if DEBUG
                ProfileCopySummaryDiagnostics.logGroupedCopyTrade(
                    siblingCount: group.members.count,
                    participatingCount: participating.count,
                    finalCounts: counts,
                    summary: modeSummary
                )
                #endif
                var summary = group.representative.summary
                summary.copyTradePublicModeSummary = modeSummary
                return summary
            }
        }
    }
}
