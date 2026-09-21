import Foundation

nonisolated enum AnalyticsLocalMutationScopeBuilder {
    static func create(trade: Trade) -> AnalyticalMutationScope {
        let viewer = trade.ownerProfileID
        let day = AnalyticsTradeAnalyticalScope.calendarDay(for: trade)
        return AnalyticalMutationScope(
            viewerID: viewer,
            newCalendarDay: day,
            newAccountID: AnalyticsTradeAnalyticalScope.accountID(for: trade),
            newMode: AnalyticsTradeAnalyticalScope.modeEffective(for: trade),
            affectedAccountIDs: accountList(from: nil, newTrade: trade),
            calendarRanges: calendarRanges(oldDay: nil, newDay: day, viewer: viewer),
            requestsDashboardBootstrap: true,
            accountChartAccountIDs: accountList(from: nil, newTrade: trade)
        )
    }

    static func update(old: Trade, new: Trade) -> AnalyticalMutationScope {
        let viewer = new.ownerProfileID
        let oldDay = AnalyticsTradeAnalyticalScope.calendarDay(for: old)
        let newDay = AnalyticsTradeAnalyticalScope.calendarDay(for: new)
        return AnalyticalMutationScope(
            viewerID: viewer,
            oldCalendarDay: oldDay,
            newCalendarDay: newDay,
            oldAccountID: AnalyticsTradeAnalyticalScope.accountID(for: old),
            newAccountID: AnalyticsTradeAnalyticalScope.accountID(for: new),
            oldMode: AnalyticsTradeAnalyticalScope.modeEffective(for: old),
            newMode: AnalyticsTradeAnalyticalScope.modeEffective(for: new),
            affectedAccountIDs: accountList(from: old, newTrade: new),
            calendarRanges: calendarRanges(oldDay: oldDay, newDay: newDay, viewer: viewer),
            requestsDashboardBootstrap: true,
            accountChartAccountIDs: accountList(from: old, newTrade: new)
        )
    }

    static func delete(old: Trade) -> AnalyticalMutationScope {
        let viewer = old.ownerProfileID
        let day = AnalyticsTradeAnalyticalScope.calendarDay(for: old)
        return AnalyticalMutationScope(
            viewerID: viewer,
            oldCalendarDay: day,
            oldAccountID: AnalyticsTradeAnalyticalScope.accountID(for: old),
            oldMode: AnalyticsTradeAnalyticalScope.modeEffective(for: old),
            affectedAccountIDs: accountList(from: old, newTrade: nil),
            calendarRanges: calendarRanges(oldDay: day, newDay: nil, viewer: viewer),
            requestsDashboardBootstrap: true,
            accountChartAccountIDs: accountList(from: old, newTrade: nil)
        )
    }

    static func bulkImport(viewerID: ProfileID, visibleMonth: (start: String, end: String)?) -> AnalyticalMutationScope {
        var ranges: [AnalyticsCalendarRangeIntent] = []
        if let visibleMonth {
            ranges.append(
                AnalyticsCalendarRangeIntent(
                    viewerID: viewerID,
                    startDate: visibleMonth.start,
                    endDate: visibleMonth.end,
                    accountScope: AnalyticsScopeKeys.allAccountsQuery,
                    modeScope: AnalyticsScopeKeys.allModesQuery,
                    targetRevision: nil
                )
            )
        }
        return AnalyticalMutationScope(
            viewerID: viewerID,
            calendarRanges: ranges,
            requestsDashboardBootstrap: true,
            accountChartAccountIDs: []
        )
    }

    static func accountModeChanged(
        viewerID: ProfileID,
        accountID: TradingAccountID,
        visibleMonth: (start: String, end: String)?
    ) -> AnalyticalMutationScope {
        var ranges: [AnalyticsCalendarRangeIntent] = []
        if let visibleMonth {
            ranges.append(
                AnalyticsCalendarRangeIntent(
                    viewerID: viewerID,
                    startDate: visibleMonth.start,
                    endDate: visibleMonth.end,
                    accountScope: AnalyticsScopeKeys.allAccountsQuery,
                    modeScope: AnalyticsScopeKeys.allModesQuery,
                    targetRevision: nil
                )
            )
        }
        return AnalyticalMutationScope(
            viewerID: viewerID,
            affectedAccountIDs: [accountID.rawValue],
            calendarRanges: ranges,
            requestsDashboardBootstrap: true,
            accountChartAccountIDs: [accountID.rawValue]
        )
    }

    private static func accountList(from old: Trade?, newTrade: Trade?) -> [String] {
        var ids = Set<String>()
        if let old, let id = AnalyticsTradeAnalyticalScope.accountID(for: old) {
            ids.insert(DashboardAnalyticsAccountMetricsLookup.normalizedAccountID(id))
        }
        if let newTrade, let id = AnalyticsTradeAnalyticalScope.accountID(for: newTrade) {
            ids.insert(DashboardAnalyticsAccountMetricsLookup.normalizedAccountID(id))
        }
        return Array(ids)
    }

    private static func calendarRanges(
        oldDay: String?,
        newDay: String?,
        viewer: ProfileID
    ) -> [AnalyticsCalendarRangeIntent] {
        guard let intent = AnalyticsTradeAnalyticalScope.allAccountsAllModesRange(
            viewerID: viewer,
            oldDay: oldDay,
            newDay: newDay
        ) else { return [] }
        return [intent]
    }
}
