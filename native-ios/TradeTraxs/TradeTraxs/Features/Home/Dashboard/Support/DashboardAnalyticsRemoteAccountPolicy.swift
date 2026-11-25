import Foundation

/// Guards Dashboard V3 account-chart RPCs from bundled sample IDs and non-UUID keys.
nonisolated enum DashboardAnalyticsRemoteAccountPolicy {
    static func shouldFetchAccountChartsRemotely(
        accountID: TradingAccountID,
        profileID: ProfileID
    ) -> Bool {
        if JournalSampleDataPolicy.usesCanonicalJournalData(for: profileID) {
            return false
        }
        if JournalSampleDataPolicy.isCanonicalAccount(id: accountID) {
            return false
        }
        return UUID(uuidString: accountID.rawValue) != nil
    }
}