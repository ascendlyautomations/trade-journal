import Foundation

/// Presentation-only hero overlay for a single prop-firm account.
///
/// Analytics (`DashboardChartMetrics`) stay realized-performance based.
/// Only the hero title, hero number, and displayed equity series receive
/// a starting-balance offset — sourced from ``TradingAccount.size`` via
/// ``PropFirmMetrics.parseAccountSize`` (same SoT as Prop Firm Mode).
nonisolated enum DashboardEquityHeroPresentation {
    /// `nil` for All Accounts / live / non-prop selection.
    /// Non-`nil` (including `0`) means a single prop account is selected.
    static func propStartingBalance(forSelectedAccount account: TradingAccount?) -> Decimal? {
        guard let account, account.isPropFirmAccount else { return nil }
        return PropFirmMetrics.parseAccountSize(account.size)
    }

    static func title(propStartingBalance: Decimal?) -> String {
        propStartingBalance == nil ? "Equity" : "Account Value"
    }

    static func displayEquity(
        currentEquity: Decimal,
        propStartingBalance: Decimal?
    ) -> Decimal {
        currentEquity + (propStartingBalance ?? 0)
    }

    static func chartPoints(
        _ points: [ProfileStatisticsMetrics.EquityPoint],
        propStartingBalance: Decimal?
    ) -> [ProfileStatisticsMetrics.EquityPoint] {
        guard let balance = propStartingBalance else { return points }
        return points.map {
            ProfileStatisticsMetrics.EquityPoint(
                index: $0.index,
                equity: $0.equity + balance,
                date: $0.date
            )
        }
    }
}
