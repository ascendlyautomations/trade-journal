import Foundation

nonisolated enum BacktestLabTimeFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case allTime
    case today
    case yesterday
    case last7Days
    case last30Days
    case thisMonth
    case lastMonth
    case custom

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .allTime: return "All Time"
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .last7Days: return "Last 7 Days"
        case .last30Days: return "Last 30 Days"
        case .thisMonth: return "This Month"
        case .lastMonth: return "Last Month"
        case .custom: return "Custom Range"
        }
    }

    var compactTitle: String {
        switch self {
        case .allTime: return "All Time"
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .last7Days: return "7 Days"
        case .last30Days: return "30 Days"
        case .thisMonth: return "This Month"
        case .lastMonth: return "Last Month"
        case .custom: return "Custom"
        }
    }
}

nonisolated enum BacktestLabFilters {
    /// Accounts created in **Backtest** mode (`accounts.mode`), not name or category alone.
    static func eligibleBacktestAccounts(_ accounts: [TradingAccount]) -> [TradingAccount] {
        accounts.filter { $0.mode == .backtest }
    }

    static func backtestModeAccountIDs(from accounts: [TradingAccount]) -> Set<TradingAccountID> {
        Set(eligibleBacktestAccounts(accounts).map(\.id))
    }

    /// Keeps `.all` or a selected id only when that id is a Backtest-mode account.
    static func sanitizedAccountFilter(
        _ filter: DashboardAccountFilter,
        eligibleAccounts: [TradingAccount]
    ) -> DashboardAccountFilter {
        switch filter {
        case .copyTradingAll, .copyTradingGroup:
            return .all
        case .all:
            return .all
        case .account(let id):
            guard eligibleAccounts.contains(where: { $0.id == id }) else { return .all }
            return filter
        }
    }

    static func apply(
        _ trades: [Trade],
        accountFilter: DashboardAccountFilter,
        strategy: String,
        timeFilter: BacktestLabTimeFilter,
        customInterval: DateInterval?,
        backtestModeAccountIDs: Set<TradingAccountID> = [],
        copyTradingGroups: [CopyTradingGroup] = [],
        now: Date = Date()
    ) -> [Trade] {
        var result = trades
        if !backtestModeAccountIDs.isEmpty {
            result = result.filter { trade in
                guard let accountID = trade.accountID else { return false }
                return backtestModeAccountIDs.contains(accountID)
            }
        }
        result = result.filter {
            DashboardAccountFilterCopyTradingSupport.matchesTrade(
                $0,
                filter: accountFilter,
                copyGroups: copyTradingGroups
            )
        }
        if DashboardAccountFilterCopyTradingSupport.shouldDedupeCopyMetrics(for: accountFilter) {
            result = DashboardAccountFilterCopyTradingSupport.dedupeCopyTradedTradesForMetrics(result)
        }
        result = BacktestLabMetrics.filter(result, strategy: strategy)
        result = filterByTime(result, timeFilter: timeFilter, customInterval: customInterval, now: now)
        return result
    }

    static func compactTimeLabel(
        timeFilter: BacktestLabTimeFilter,
        customInterval: DateInterval?
    ) -> String {
        if timeFilter == .custom, let customInterval {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "M/d/yy"
            let start = formatter.string(from: customInterval.start)
            let end = formatter.string(from: customInterval.end)
            return "\(start) – \(end)"
        }
        return timeFilter.compactTitle
    }

    /// Applies account, strategy, and backtest account scope without time filtering (equity / drawdown lifetime).
    static func lifetimeScopedTrades(
        _ trades: [Trade],
        accountFilter: DashboardAccountFilter,
        strategy: String,
        backtestModeAccountIDs: Set<TradingAccountID>,
        copyTradingGroups: [CopyTradingGroup] = [],
        now: Date = Date()
    ) -> [Trade] {
        apply(
            trades,
            accountFilter: accountFilter,
            strategy: strategy,
            timeFilter: .allTime,
            customInterval: nil,
            backtestModeAccountIDs: backtestModeAccountIDs,
            copyTradingGroups: copyTradingGroups,
            now: now
        )
    }

    /// Chart / drawdown period window; `nil` = all time (still uses lifetime trades for opening balance).
    static func resolvedChartInterval(
        timeFilter: BacktestLabTimeFilter,
        customInterval: DateInterval?,
        now: Date = Date()
    ) -> DateInterval? {
        switch timeFilter {
        case .allTime:
            return nil
        case .custom:
            guard let customInterval else { return nil }
            return DashboardScopeFilterSupport.normalizedCustomInterval(
                start: customInterval.start,
                end: customInterval.end
            )
        default:
            guard let bounds = dayKeyBounds(for: timeFilter, customInterval: nil, now: now),
                  let startKey = bounds.start,
                  let endKey = bounds.end
            else { return nil }
            return civilDayInterval(startKey: startKey, endKey: endKey)
        }
    }

    private static func civilDayInterval(startKey: String, endKey: String) -> DateInterval? {
        guard let startComps = TradingCalendarDay.components(from: startKey),
              let endComps = TradingCalendarDay.components(from: endKey)
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TradingCalendarDay.timeZone
        guard
            let startDay = calendar.date(from: DateComponents(
                year: startComps.year,
                month: startComps.month,
                day: startComps.day,
                hour: 0,
                minute: 0
            )),
            let endDay = calendar.date(from: DateComponents(
                year: endComps.year,
                month: endComps.month,
                day: endComps.day,
                hour: 23,
                minute: 59,
                second: 59
            ))
        else { return nil }
        return DateInterval(start: startDay, end: endDay)
    }

    static func filterByTime(
        _ trades: [Trade],
        timeFilter: BacktestLabTimeFilter,
        customInterval: DateInterval?,
        now: Date = Date()
    ) -> [Trade] {
        guard let bounds = dayKeyBounds(for: timeFilter, customInterval: customInterval, now: now) else {
            return trades
        }
        return trades.filter { trade in
            guard let key = TradingCalendarDay.key(for: trade) else { return false }
            if let start = bounds.start, key < start { return false }
            if let end = bounds.end, key > end { return false }
            return true
        }
    }

    private static func dayKeyBounds(
        for filter: BacktestLabTimeFilter,
        customInterval: DateInterval?,
        now: Date
    ) -> (start: String?, end: String?)? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TradingCalendarDay.timeZone

        switch filter {
        case .allTime:
            return nil
        case .today:
            guard let end = TradingCalendarDay.key(for: now) else { return nil }
            return (end, end)
        case .yesterday:
            let todayStart = calendar.startOfDay(for: now)
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart),
                  let key = TradingCalendarDay.key(for: yesterday)
            else { return nil }
            return (key, key)
        case .last7Days:
            guard let end = TradingCalendarDay.key(for: now),
                  let startDate = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)),
                  let start = TradingCalendarDay.key(for: startDate)
            else { return nil }
            return (start, end)
        case .last30Days:
            guard let end = TradingCalendarDay.key(for: now),
                  let startDate = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)),
                  let start = TradingCalendarDay.key(for: startDate)
            else { return nil }
            return (start, end)
        case .thisMonth:
            guard let interval = calendar.dateInterval(of: .month, for: now),
                  let start = TradingCalendarDay.key(for: interval.start),
                  let endDay = calendar.date(byAdding: .day, value: -1, to: interval.end),
                  let end = TradingCalendarDay.key(for: endDay)
            else { return nil }
            return (start, end)
        case .lastMonth:
            let thisMonthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
            guard let previousMonthEnd = calendar.date(byAdding: .day, value: -1, to: thisMonthStart),
                  let previousInterval = calendar.dateInterval(of: .month, for: previousMonthEnd),
                  let start = TradingCalendarDay.key(for: previousInterval.start),
                  let end = TradingCalendarDay.key(for: previousMonthEnd)
            else { return nil }
            return (start, end)
        case .custom:
            guard let customInterval else { return nil }
            let normalized = DashboardScopeFilterSupport.normalizedCustomInterval(
                start: customInterval.start,
                end: customInterval.end,
                calendar: calendar
            )
            guard let start = TradingCalendarDay.key(for: normalized.start),
                  let end = TradingCalendarDay.key(for: normalized.end)
            else { return nil }
            return (start, end)
        }
    }
}