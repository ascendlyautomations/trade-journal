import Foundation

/// Equity hero + drawdown floor for Backtest Lab (isolated from Home Dashboard).
nonisolated enum BacktestLabEquitySupport {
    private static let drawdownEligibility = LivePersonalDrawdownAccountEligibility.backtestAccount

    static func chartPeriodContext(
        timeFilter: BacktestLabTimeFilter,
        customTimeInterval: DateInterval?,
        now: Date = Date()
    ) -> LivePersonalDrawdownEngine.PeriodContext {
        let custom = BacktestLabFilters.resolvedChartInterval(
            timeFilter: timeFilter,
            customInterval: customTimeInterval,
            now: now
        )
        return LivePersonalDrawdownEngine.PeriodContext(
            dateRange: .all,
            customInterval: custom,
            now: now
        )
    }

    static func accountEquityPeriodContext(
        timeFilter: BacktestLabTimeFilter,
        customTimeInterval: DateInterval?,
        now: Date = Date()
    ) -> DashboardAccountEquityChartEngine.PeriodContext {
        let custom = BacktestLabFilters.resolvedChartInterval(
            timeFilter: timeFilter,
            customInterval: customTimeInterval,
            now: now
        )
        return DashboardAccountEquityChartEngine.PeriodContext(
            dateRange: .all,
            customInterval: custom,
            now: now
        )
    }

    /// Equity curve points; lifetime trades include pre-period history for balance + trailing drawdown.
    static func resolveChartPoints(
        accountFilter: DashboardAccountFilter,
        selectedAccount: TradingAccount?,
        backtestAccounts: [TradingAccount],
        lifetimeTrades: [Trade],
        timeFilter: BacktestLabTimeFilter,
        customTimeInterval: DateInterval?,
        now: Date = Date()
    ) -> [ProfileStatisticsMetrics.EquityPoint] {
        let period = chartPeriodContext(
            timeFilter: timeFilter,
            customTimeInterval: customTimeInterval,
            now: now
        )
        let accountPeriod = accountEquityPeriodContext(
            timeFilter: timeFilter,
            customTimeInterval: customTimeInterval,
            now: now
        )

        if let account = selectedAccount,
           let config = LivePersonalDrawdownEngine.config(from: account, eligibility: drawdownEligibility),
           TradingAccountStartingBalancePolicy.resolvedStartingBalance(for: account) != nil
        {
            let samples = LivePersonalDrawdownEngine.computeEquitySeries(
                account: account,
                config: config,
                lifetimeTrades: lifetimeTrades,
                ledgerEntries: [],
                period: period,
                includesBacktestTrades: true
            )
            guard !samples.isEmpty else { return [] }
            return LivePersonalDrawdownEngine.mapToEquityPoints(samples)
        }

        if let account = selectedAccount,
           let starting = TradingAccountStartingBalancePolicy.resolvedStartingBalance(for: account)
        {
            let samples = DashboardAccountEquityChartEngine.computeEquitySeries(
                account: account,
                lifetimeTrades: lifetimeTrades,
                ledgerEntries: [],
                payoutCycles: [],
                period: accountPeriod,
                granularityOverride: .tradeLevel,
                includesBacktestTrades: true
            )
            let points = DashboardAccountEquityChartEngine.mapToEquityPoints(samples)
            return DashboardEquityHeroPresentation.chartPoints(points, propStartingBalance: starting)
        }

        let scopedAccounts: [TradingAccount]
        switch accountFilter {
        case .account(let id):
            scopedAccounts = backtestAccounts.filter { $0.id == id }
        default:
            scopedAccounts = backtestAccounts
        }

        if scopedAccounts.isEmpty {
            return cumulativePnLPoints(from: lifetimeTrades)
        }

        let hasAnyStartingBalance = scopedAccounts.contains {
            TradingAccountStartingBalancePolicy.resolvedStartingBalance(for: $0) != nil
        }

        if hasAnyStartingBalance, case .account = accountFilter {
            return cumulativePnLPoints(from: lifetimeTrades)
        }

        if !hasAnyStartingBalance || accountFilter == .all {
            return cumulativePnLPoints(from: lifetimeTrades)
        }

        let samples = DashboardAccountEquityChartEngine.computeAllAccountsEquitySeries(
            accounts: scopedAccounts,
            lifetimeTrades: lifetimeTrades,
            ledgerEntries: [],
            payoutCycles: [],
            period: accountPeriod,
            includesBacktestTrades: true
        )
        return DashboardAccountEquityChartEngine.mapToEquityPoints(samples)
    }

    static func cumulativePnLPoints(from trades: [Trade]) -> [ProfileStatisticsMetrics.EquityPoint] {
        let chronological = trades.sorted {
            DashboardScopeFilterSupport.dashboardTradeFilterDate(for: $0)
                < DashboardScopeFilterSupport.dashboardTradeFilterDate(for: $1)
        }
        var running = Decimal.zero
        var points: [ProfileStatisticsMetrics.EquityPoint] = []
        points.reserveCapacity(chronological.count)
        for (offset, trade) in chronological.enumerated() {
            running += trade.realizedPnL?.amount ?? 0
            let stamp = DashboardScopeFilterSupport.dashboardTradeFilterDate(for: trade)
            points.append(
                ProfileStatisticsMetrics.EquityPoint(
                    index: offset,
                    equity: running,
                    date: stamp,
                    drawdownFloor: nil
                )
            )
        }
        return ProfileStatisticsMetrics.chartOrderedEquityPoints(points)
    }

    static func headlinePresentation(
        accountFilter: DashboardAccountFilter,
        selectedAccount: TradingAccount?,
        periodSummary: DashboardChartMetrics.Summary,
        lifetimeTrades: [Trade],
        timeFilter: BacktestLabTimeFilter,
        customTimeInterval: DateInterval?,
        now: Date = Date()
    ) -> (title: String, displayEquity: Decimal, periodChangePercent: Decimal?) {
        let showsAccountValue = DashboardEquityHeroPresentation.showsAccountValue(forSelectedAccount: selectedAccount)
            && selectedAccount.flatMap { TradingAccountStartingBalancePolicy.resolvedStartingBalance(for: $0) } != nil

        let title = DashboardEquityHeroPresentation.title(showsAccountValue: showsAccountValue)

        if showsAccountValue, let account = selectedAccount {
            let starting = TradingAccountStartingBalancePolicy.resolvedStartingBalance(for: account) ?? 0
            let lifetimePnL = lifetimeRealizedPnL(trades: lifetimeTrades, accountID: account.id)
            let tracked = starting + lifetimePnL
            let periodStart = periodOpeningEquity(
                account: account,
                lifetimeTrades: lifetimeTrades,
                timeFilter: timeFilter,
                customTimeInterval: customTimeInterval,
                now: now
            )
            let percent: Decimal? = {
                guard let periodStart, periodStart > 0 else { return nil }
                return ((tracked - periodStart) / periodStart) * 100
            }()
            return (title, tracked, percent)
        }

        return ("Equity", periodSummary.currentEquity, nil)
    }

    private static func lifetimeRealizedPnL(trades: [Trade], accountID: TradingAccountID) -> Decimal {
        trades
            .filter { $0.accountID == accountID }
            .compactMap(\.realizedPnL?.amount)
            .reduce(0, +)
    }

    private static func periodOpeningEquity(
        account: TradingAccount,
        lifetimeTrades: [Trade],
        timeFilter: BacktestLabTimeFilter,
        customTimeInterval: DateInterval?,
        now: Date
    ) -> Decimal? {
        guard let interval = BacktestLabFilters.resolvedChartInterval(
            timeFilter: timeFilter,
            customInterval: customTimeInterval,
            now: now
        ) else { return nil }
        let starting = TradingAccountStartingBalancePolicy.resolvedStartingBalance(for: account) ?? 0
        var opening = starting
        for trade in lifetimeTrades where trade.accountID == account.id {
            let stamp = DashboardScopeFilterSupport.dashboardTradeFilterDate(for: trade)
            if stamp < interval.start {
                opening += trade.realizedPnL?.amount ?? 0
            }
        }
        return opening
    }
}