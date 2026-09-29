import Foundation

#if DEBUG
/// End-to-end Eval / single-account balance audit for Dashboard Account Value.
nonisolated enum DashboardAccountBalanceAudit {
    struct Context: Sendable {
        var accountID: TradingAccountID
        var accountMode: TradingAccountMode
        var accountCategory: TradingAccountCategory
        var startingBalance: Decimal
        var lifetimeRealizedPnL: Decimal
        var lifetimeSource: String
        var propFirmReplayBalance: Decimal?
        var propFirmTradeReplayCount: Int
        var tradeInputCountForAccount: Int
        var expectedBalance: Decimal
        var displayedBalance: Decimal
        var usesAnalyticsV3: Bool
    }

    static func log(_ context: Context) {
        let divergence = context.expectedBalance != context.displayedBalance
        guard divergence || context.accountMode == .evaluation else { return }
        print(
            """
            [DashboardAccountBalance]
            accountID=\(context.accountID.rawValue)
            mode=\(context.accountMode.rawValue)
            category=\(context.accountCategory.rawValue)
            startingBalance=\(format(context.startingBalance))
            lifetimeRealizedPnL=\(format(context.lifetimeRealizedPnL)) source=\(context.lifetimeSource)
            propReplayBalance=\(context.propFirmReplayBalance.map { format($0) } ?? "nil")
            propTradeReplayCount=\(context.propFirmTradeReplayCount)
            tradeInputsForAccount=\(context.tradeInputCountForAccount)
            expectedBalance=\(format(context.expectedBalance))
            displayedBalance=\(format(context.displayedBalance))
            analyticsV3=\(context.usesAnalyticsV3)
            diverged=\(divergence)
            """
        )
    }

    private static func format(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
#endif
