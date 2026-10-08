import Foundation

/// Dashboard-only account/trade scope — backtest data lives in Backtest Lab, not Home analytics.
nonisolated enum DashboardAccountScopePolicy {
    static func includesAccountInDashboard(_ account: TradingAccount) -> Bool {
        account.mode != .backtest
    }

    static func includesTradeInDashboardStatistics(
        trade: Trade,
        accountMode: TradingAccountMode?
    ) -> Bool {
        if trade.mode == .backtest { return false }
        if accountMode == .backtest { return false }
        return true
    }

    static func menuAccounts(
        from accounts: [TradingAccount],
        preservingSelection selectedID: TradingAccountID?
    ) -> [TradingAccount] {
        accounts
            .filter(includesAccountInDashboard)
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    static func sanitizedFilter(
        _ filter: DashboardAccountFilter,
        accounts: [TradingAccount]
    ) -> DashboardAccountFilter {
        guard case .account(let id) = filter else { return filter }
        guard let account = accounts.first(where: { $0.id == id }) else { return filter }
        return includesAccountInDashboard(account) ? filter : .all
    }
}
