import Foundation

/// When the journal layer should read ``DemoCanonicalDataset`` instead of the signed-in owner store.
nonisolated enum JournalSampleDataPolicy {
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
}