import Foundation

/// Bounded Calendar repair intents for remote revision signals (unknown affected scope).
nonisolated enum AnalyticsRemoteCalendarRepair {
    static let defaultMaxStaleRanges = 3

    static func intents(
        viewerID: ProfileID,
        pendingRevision: Int64,
        visibleMonth: (start: String, end: String)?,
        staleCoverages: [AnalyticsRangeCoverageRecord],
        maxStaleRanges: Int = defaultMaxStaleRanges
    ) -> [AnalyticsCalendarRangeIntent] {
        var intents: [AnalyticsCalendarRangeIntent] = []
        let accountScope = AnalyticsScopeKeys.allAccountsQuery
        let modeScope = AnalyticsScopeKeys.allModesQuery

        if let visibleMonth {
            intents.append(
                AnalyticsCalendarRangeIntent(
                    viewerID: viewerID,
                    startDate: visibleMonth.start,
                    endDate: visibleMonth.end,
                    accountScope: accountScope,
                    modeScope: modeScope,
                    targetRevision: pendingRevision
                )
            )
        }

        let visibleKey = visibleMonth.map { "\($0.start)|\($0.end)" }
        let stale = staleCoverages
            .filter { $0.server_revision < pendingRevision }
            .filter { row in
                let key = "\(row.start_date)|\(row.end_date)"
                return key != visibleKey
            }
            .sorted { lhs, rhs in
                if lhs.server_revision != rhs.server_revision {
                    return lhs.server_revision < rhs.server_revision
                }
                return lhs.start_date < rhs.start_date
            }
            .prefix(max(0, maxStaleRanges))

        for row in stale {
            intents.append(
                AnalyticsCalendarRangeIntent(
                    viewerID: viewerID,
                    startDate: row.start_date,
                    endDate: row.end_date,
                    accountScope: row.account_scope,
                    modeScope: row.mode_scope,
                    targetRevision: pendingRevision
                )
            )
        }

        return AnalyticsCalendarRangeCoalescing.merge(intents)
    }
}
