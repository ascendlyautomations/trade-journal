import Foundation

/// Shared copy-trading menu wiring for owner account filter dropdowns.
@MainActor
enum OwnerAccountFilterDropdownCopyTradingBridge {
    /// Wired from app launch with the live ``DataEnvironment`` (Supabase + session).
    static var repositoryFactory: (() -> (any CopyTradingGroupRepository)?)?

    static func requestLoad(profileID: ProfileID?) {
        guard let profileID, let repository = repositoryFactory?() else { return }
        Task {
            await loadGroupsIfNeeded(profileID: profileID, repository: repository)
        }
    }

    static func loadGroupsIfNeeded(
        profileID: ProfileID?,
        repository: (any CopyTradingGroupRepository)?
    ) async {
        guard let profileID, let repository else { return }
        await CopyTradingGroupsMenuCache.shared.loadIfNeeded(
            profileID: profileID,
            repository: repository
        )
    }

    static func groups(for profileID: ProfileID?) -> [CopyTradingGroup] {
        guard let profileID else { return [] }
        return CopyTradingGroupsMenuCache.shared.groups(for: profileID)
    }

    static func isLoadingGroups(for profileID: ProfileID?) -> Bool {
        CopyTradingGroupsMenuCache.shared.isLoading(profileID: profileID)
    }

    static func menuTitle(
        filter: DashboardAccountFilter,
        accounts: [TradingAccount],
        profileID: ProfileID?
    ) -> String {
        DashboardAccountFilterCopyTradingSupport.menuTitle(
            for: filter,
            accounts: accounts,
            copyGroups: groups(for: profileID)
        )
    }

    static func reconciledFilter(
        _ filter: DashboardAccountFilter,
        accounts: [TradingAccount],
        profileID: ProfileID?
    ) -> DashboardAccountFilter {
        DashboardAccountFilterCopyTradingSupport.sanitizedFilter(
            filter,
            accounts: accounts,
            copyGroups: groups(for: profileID)
        )
    }

    static func reloadGroupsAfterMutation(profileID: ProfileID) async {
        guard let repository = repositoryFactory?() else { return }
        await CopyTradingGroupsMenuCache.shared.reload(
            profileID: profileID,
            repository: repository
        )
    }
}