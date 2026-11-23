import Foundation

/// Client-side trade-entry checks aligned with Postgres `trades_enforce_account_can_add_trades`.
@MainActor
enum TradeEntryEntitlementGate {
    typealias ViewerTier = TradeEntryViewerTier

    static func viewerTier(profileID: ProfileID) -> ViewerTier {
        switch TraxProEffectiveEntitlement.clientAccess(
            profileID: profileID,
            demoModeActive: ExploreModeSupport.isActive
        ) {
        case .pro, .unrestricted:
            return .pro
        case .free:
            return .free
        case .unknown:
            return .free
        }
    }

    static func viewerHasTraxProAccess(profileID: ProfileID) -> Bool {
        TraxProEffectiveEntitlement.hasVerifiedTraxProAccess(profileID: profileID)
    }

    static func accountAllowsNewTrade(_ account: TradingAccount, viewerTier: ViewerTier) -> Bool {
        guard IosSubscriptionReleaseConfiguration.appliesFreeTierUsageCaps else { return true }
        switch viewerTier {
        case .pro:
            return true
        case .free:
            return FreePlanTradeAccountPolicy.accountCanAddTrades(account)
        }
    }

    static func validateAccountsForNewTrades(
        _ accounts: [TradingAccount],
        profileID: ProfileID
    ) -> String? {
        guard IosSubscriptionReleaseConfiguration.appliesFreeTierUsageCaps else { return nil }
        let tier = viewerTier(profileID: profileID)
        guard tier == .free else { return nil }
        if FreePlanTradeAccountPolicy.needsSlotSelection(accounts: accounts, viewerTier: tier) {
            return "Choose up to \(FreeTierPolicy.maxTradeEntryAccounts) accounts to keep active for new trades."
        }
        return nil
    }
}