import Foundation

/// Free-plan account creation vs trade-entry slot semantics (mirrors web `freePlanAccountSlots`).
nonisolated enum FreePlanTradeAccountPolicy {
    static let maxCreationAccounts = FreeTierPolicy.maxTradeEntryAccounts
    static let maxTradeEntrySlots = FreeTierPolicy.maxTradeEntryAccounts

    static func accountCanAddTrades(_ account: TradingAccount) -> Bool {
        account.canAddTrades
    }

    static func countTradeEntryEnabled(_ accounts: [TradingAccount]) -> Int {
        accounts.filter(accountCanAddTrades).count
    }

    static func countTotalAccounts(_ accounts: [TradingAccount]) -> Int {
        accounts.count
    }

    static func needsSlotSelection(
        accounts: [TradingAccount],
        viewerTier: TradeEntryViewerTier
    ) -> Bool {
        guard viewerTier == .free else { return false }
        return countTradeEntryEnabled(accounts) > maxTradeEntrySlots
    }

    static func canCreateAnotherAccount(
        accounts: [TradingAccount],
        viewerTier: TradeEntryViewerTier
    ) -> Bool {
        guard viewerTier == .free else { return true }
        return countTotalAccounts(accounts) < maxCreationAccounts
    }
}
