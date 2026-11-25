import Foundation

/// Account / strategy context for Backtest Calendar → day detail (mirrors calendar session store).
@MainActor
final class BacktestCalendarSessionStore {
    static let shared = BacktestCalendarSessionStore()

    private(set) var accountFilter: DashboardAccountFilter = .all
    private(set) var selectedStrategy = BacktestLabMetrics.allStrategiesToken
    private(set) var backtestModeAccountIDs: Set<TradingAccountID> = []

    private init() {}

    func publish(
        accountFilter: DashboardAccountFilter,
        selectedStrategy: String,
        backtestModeAccountIDs: Set<TradingAccountID>
    ) {
        self.accountFilter = accountFilter
        self.selectedStrategy = selectedStrategy
        self.backtestModeAccountIDs = backtestModeAccountIDs
    }

    func filteredTrades(from all: [Trade], accounts: [TradingAccount] = []) -> [Trade] {
        let scope = backtestModeAccountIDs.isEmpty
            ? BacktestLabFilters.backtestModeAccountIDs(from: accounts)
            : backtestModeAccountIDs
        return BacktestLabFilters.apply(
            all,
            accountFilter: accountFilter,
            strategy: selectedStrategy,
            timeFilter: .allTime,
            customInterval: nil,
            backtestModeAccountIDs: scope
        )
    }
}