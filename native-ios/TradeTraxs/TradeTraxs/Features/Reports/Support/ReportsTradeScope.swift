import Foundation

/// Shared Performance + Psychology Reports trade/check-in scoping from ``TradingReportSessionStore``.
nonisolated enum ReportsTradeScope {
    static func filtersFromSession() async -> TradingReportFilters {
        await MainActor.run { TradingReportSessionStore.shared.filters }
    }

    static func scopedTrades(
        from trades: [Trade],
        accounts: [TradingAccount],
        filters: TradingReportFilters,
        copyTradingGroups: [CopyTradingGroup] = []
    ) -> [Trade] {
        let scope = DashboardClientScopeFilter(
            accountFilter: filters.accountFilter,
            dateRange: .all,
            customInterval: nil,
            accountMode: filters.accountMode,
            showPublicOnly: false,
            linkedAccountModes: Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.mode) }),
            copyTradingGroups: copyTradingGroups
        )
        return PsychologyAnalyticsTradeScope.scopedTrades(
            ownerTrades: trades,
            accounts: accounts,
            scope: scope
        )
    }

    /// When a single account is selected, keep check-ins only on Eastern days that account traded –
    /// avoids attributing account-independent check-ins to that account.
    static func scopedCheckIns(
        _ checkIns: [TraderDailyCheckIn],
        scopedTrades: [Trade],
        filters: TradingReportFilters
    ) -> [TraderDailyCheckIn] {
        guard case .account = filters.accountFilter else { return checkIns }
        let tradeDays = Set(scopedTrades.map { TraderPsychologyAnalyticsFoundation.tradeDateKey(for: $0) })
        guard !tradeDays.isEmpty else { return [] }
        return checkIns.filter { tradeDays.contains($0.checkInDate) }
    }

    static func filtersFingerprint(_ filters: TradingReportFilters) -> String {
        let account: String = {
            switch filters.accountFilter {
            case .all: return "all"
            case .account(let id): return id.rawValue
            case .copyTradingAll: return "copyAll"
            case .copyTradingGroup(let id): return "copyGroup:\(id)"
            }
        }()
        return "acct:\(account):mode:\(filters.accountMode.rawValue)"
    }
}