import Foundation

/// Shared account-filter menu wiring for dashboard, trades, calendar, reports, and analytics.
@MainActor
enum OwnerAccountFilterMenuSupport {
    static func menuTitle(
        filter: DashboardAccountFilter,
        accounts: [TradingAccount],
        profileID: ProfileID?
    ) -> String {
        OwnerAccountFilterDropdownCopyTradingBridge.menuTitle(
            filter: filter,
            accounts: accounts,
            profileID: profileID
        )
    }

    static func reconciledFilter(
        _ filter: DashboardAccountFilter,
        accounts: [TradingAccount],
        profileID: ProfileID?
    ) -> DashboardAccountFilter {
        OwnerAccountFilterDropdownCopyTradingBridge.reconciledFilter(
            filter,
            accounts: accounts,
            profileID: profileID
        )
    }

    static func copyGroups(for profileID: ProfileID?) -> [CopyTradingGroup] {
        OwnerAccountFilterDropdownCopyTradingBridge.groups(for: profileID)
    }

    static func isLoadingCopyGroups(for profileID: ProfileID?) -> Bool {
        OwnerAccountFilterDropdownCopyTradingBridge.isLoadingGroups(for: profileID)
    }

    static func requestCopyGroupsLoad(profileID: ProfileID?) {
        OwnerAccountFilterDropdownCopyTradingBridge.requestLoad(profileID: profileID)
    }
}