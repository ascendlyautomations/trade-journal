import Foundation

/// Presentation-only hero overlay for a single selected trading account.
///
/// Analytics (`DashboardChartMetrics`) stay timeframe-based realized performance.
/// The hero title, headline value, and equity curve offset use tracked account
/// value when one account is selected; All Accounts keeps cumulative equity (P&L).
nonisolated enum DashboardEquityHeroPresentation {
    /// `nil` for All Accounts; non-`nil` (including `0`) for any single account.
    static func accountStartingBalance(forSelectedAccount account: TradingAccount?) -> Decimal? {
        guard let account else { return nil }
        return PropFirmMetrics.parseAccountSize(account.size)
    }

    @available(*, deprecated, renamed: "accountStartingBalance(forSelectedAccount:)")
    static func propStartingBalance(forSelectedAccount account: TradingAccount?) -> Decimal? {
        accountStartingBalance(forSelectedAccount: account)
    }

    static func showsAccountValue(forSelectedAccount account: TradingAccount?) -> Bool {
        account != nil
    }

    static func title(showsAccountValue: Bool) -> String {
        showsAccountValue ? "Account Value" : "Equity"
    }

    static func title(propStartingBalance: Decimal?) -> String {
        title(showsAccountValue: propStartingBalance != nil)
    }

    /// Tracked balance for one account — prefers payout-aware prop metrics when supplied.
    static func trackedAccountValue(
        authoritativeBalance: Decimal?,
        lifetimeRealizedPnL: Decimal,
        startingBalance: Decimal?,
        manualWithdrawalsTotal: Decimal = 0
    ) -> Decimal {
        if let authoritativeBalance { return authoritativeBalance }
        return (startingBalance ?? 0) + lifetimeRealizedPnL - manualWithdrawalsTotal
    }

    /// All Accounts: timeframe cumulative realized equity. Single account: tracked value.
    static func headlineValue(
        showsAccountValue: Bool,
        timeframeCurrentEquity: Decimal,
        authoritativeBalance: Decimal?,
        lifetimeRealizedPnL: Decimal,
        startingBalance: Decimal?
    ) -> Decimal {
        guard showsAccountValue else { return timeframeCurrentEquity }
        return trackedAccountValue(
            authoritativeBalance: authoritativeBalance,
            lifetimeRealizedPnL: lifetimeRealizedPnL,
            startingBalance: startingBalance,
            manualWithdrawalsTotal: 0
        )
    }

    static func displayEquity(
        currentEquity: Decimal,
        propStartingBalance: Decimal?
    ) -> Decimal {
        headlineValue(
            showsAccountValue: propStartingBalance != nil,
            timeframeCurrentEquity: currentEquity,
            authoritativeBalance: nil,
            lifetimeRealizedPnL: currentEquity,
            startingBalance: propStartingBalance
        )
    }

    static func chartPoints(
        _ points: [ProfileStatisticsMetrics.EquityPoint],
        propStartingBalance: Decimal?
    ) -> [ProfileStatisticsMetrics.EquityPoint] {
        let ordered = ProfileStatisticsMetrics.chartOrderedEquityPoints(points)
        guard let balance = propStartingBalance else { return ordered }
        return ordered.map {
            ProfileStatisticsMetrics.EquityPoint(
                index: $0.index,
                equity: $0.equity + balance,
                date: $0.date
            )
        }
    }
}
