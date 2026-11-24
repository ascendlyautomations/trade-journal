import Foundation

/// Cache-first owner account list refresh after ``AccountMutationStore`` broadcasts (no network).
@MainActor
enum OwnerAccountMutationSync {
    static func sessionAccounts(
        profileID: ProfileID?,
        detailCache: DetailPresentationCache?
    ) -> [TradingAccount]? {
        guard let profileID else { return nil }
        let cached = SessionAccountsStore.shared.cached(for: profileID)
            ?? detailCache?.accounts(for: profileID)
        guard let cached, !cached.isEmpty else { return nil }
        return cached.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func seedDetailCacheIfNeeded(
        _ accounts: [TradingAccount],
        profileID: ProfileID,
        detailCache: DetailPresentationCache?
    ) {
        detailCache?.seed(accounts: accounts, for: profileID)
    }

    static func reconciledAccountFilter(
        _ filter: DashboardAccountFilter,
        accounts: [TradingAccount]
    ) -> DashboardAccountFilter {
        DashboardAccountScopePolicy.sanitizedFilter(filter, accounts: accounts)
    }

    static func accountNamesMap(from accounts: [TradingAccount]) -> [TradingAccountID: String] {
        Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
    }
}