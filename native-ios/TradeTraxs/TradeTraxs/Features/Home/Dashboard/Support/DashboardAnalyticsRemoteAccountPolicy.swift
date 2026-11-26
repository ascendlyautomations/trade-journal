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

/// Client TraxPro gate for premium V3 chart bundle RPCs (matches server `premium_analytics` enforcement).
@MainActor
enum DashboardPremiumChartsRemotePolicy {
    static func mayFetchPremiumChartsRemotely(profileID: ProfileID) -> Bool {
        ProMonetizationPolicy.includesPremiumDashboardAnalytics(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: profileID
        )
    }
}