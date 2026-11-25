import Foundation

/// When the journal layer should read ``DemoCanonicalDataset`` instead of the signed-in owner store.
nonisolated enum JournalSampleDataPolicy {
    /// Bundled TraxsPro preview / Explore journal accounts (not Supabase UUIDs).
    static var canonicalAccountIDs: Set<TradingAccountID> {
        [
            DemoCanonicalDataset.evaluationAccountID,
            DemoCanonicalDataset.fundedAccountID,
            DemoCanonicalDataset.liveAccountID,
        ]
    }

    /// Local Explore demo identity (bundled guest journal).
    static func usesCanonicalJournalData(for profileID: ProfileID) -> Bool {
        if profileID == DemoExperienceSupport.profileID {
            return true
        }
        return TraxsProPreviewRuntimeFlag.usesCanonicalJournalSampleData
    }

    static var canonicalTradeIDs: Set<TradeID> {
        Set(DemoCanonicalDataset.trades().map(\.id))
    }

    static func isCanonicalTrade(id: TradeID) -> Bool {
        canonicalTradeIDs.contains(id)
    }

    static func isCanonicalAccount(id: TradingAccountID) -> Bool {
        canonicalAccountIDs.contains(id)
    }
}