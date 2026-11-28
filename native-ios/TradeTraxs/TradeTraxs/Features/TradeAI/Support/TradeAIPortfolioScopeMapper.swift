import Foundation

/// Maps dashboard scope filters to the BFF `AiPortfolioScope` contract.
nonisolated enum TradeAIPortfolioScopeMapper {
    static func map(
        _ filter: DashboardClientScopeFilter,
        accounts: [TradingAccount]
    ) -> TradeAIPortfolioScope {
        if let custom = filter.customInterval {
            return TradeAIPortfolioScope(
                preset: "custom",
                accountIds: accountIds(from: filter, accounts: accounts),
                startDate: dayString(custom.start),
                endDate: dayString(custom.end)
            )
        }

        switch filter.dateRange {
        case .all:
            return TradeAIPortfolioScope(preset: "all_time", accountIds: accountIds(from: filter, accounts: accounts))
        case .sevenDays:
            return TradeAIPortfolioScope(preset: "last_7", accountIds: accountIds(from: filter, accounts: accounts))
        case .thirtyDays:
            return TradeAIPortfolioScope(preset: "last_30", accountIds: accountIds(from: filter, accounts: accounts))
        case .ninetyDays:
            return TradeAIPortfolioScope(preset: "last_90", accountIds: accountIds(from: filter, accounts: accounts))
        case .oneYear:
            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -365, to: end) ?? end
            return TradeAIPortfolioScope(
                preset: "custom",
                accountIds: accountIds(from: filter, accounts: accounts),
                startDate: dayString(start),
                endDate: dayString(end)
            )
        case .ytd:
            let end = Date()
            let year = Calendar.current.component(.year, from: end)
            var comps = DateComponents()
            comps.year = year
            comps.month = 1
            comps.day = 1
            let start = Calendar.current.date(from: comps) ?? end
            return TradeAIPortfolioScope(
                preset: "custom",
                accountIds: accountIds(from: filter, accounts: accounts),
                startDate: dayString(start),
                endDate: dayString(end)
            )
        }
    }

    private static func accountIds(
        from filter: DashboardClientScopeFilter,
        accounts: [TradingAccount]
    ) -> [String]? {
        switch filter.accountFilter {
        case .all:
            return nil
        case .account(let id):
            return [id.rawValue]
        case .copyTradingAll:
            let groups = filter.copyTradingGroups
            let linked = DashboardAccountFilterCopyTradingSupport.linkedAccountIDs(from: groups)
            let ids = accounts.map(\.id.rawValue).filter { linked.contains($0) }
            return ids.isEmpty ? nil : ids
        case .copyTradingGroup(let groupKey):
            let scoped = DashboardAccountFilterCopyTradingSupport.accountIDs(
                forGroupID: groupKey,
                groups: filter.copyTradingGroups
            )
            let ids = accounts.map(\.id.rawValue).filter { scoped.contains($0) }
            return ids.isEmpty ? nil : ids
        }
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}