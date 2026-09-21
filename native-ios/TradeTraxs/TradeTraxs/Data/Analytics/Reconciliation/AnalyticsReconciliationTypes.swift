import Foundation

// MARK: - Sources & reasons

nonisolated enum AnalyticsReconcileSource: Sendable, Equatable {
    case localMutation(AnalyticalMutationScope)
    case remoteRevision(serverRevision: Int64)
    case repair(AnalyticsRepairReason)
}

nonisolated enum AnalyticsRepairReason: String, Sendable, Equatable {
    case foreground
    case networkReconnect
    case realtimeReconnect
    case authRefresh
    case explicit
}

nonisolated enum AnalyticsDomain: Sendable, Equatable, Hashable {
    case calendar
    case dashboardBootstrap
    case accountCharts(accountID: String)
}

// MARK: - Mutation scope (6C will populate richer pre-image data)

nonisolated struct AnalyticalMutationScope: Sendable, Equatable {
    var viewerID: ProfileID
    var oldCalendarDay: String?
    var newCalendarDay: String?
    var oldAccountID: String?
    var newAccountID: String?
    var oldMode: String?
    var newMode: String?
    var affectedAccountIDs: [String]
    var calendarRanges: [AnalyticsCalendarRangeIntent]
    var requestsDashboardBootstrap: Bool
    var accountChartAccountIDs: [String]

    init(
        viewerID: ProfileID,
        oldCalendarDay: String? = nil,
        newCalendarDay: String? = nil,
        oldAccountID: String? = nil,
        newAccountID: String? = nil,
        oldMode: String? = nil,
        newMode: String? = nil,
        affectedAccountIDs: [String] = [],
        calendarRanges: [AnalyticsCalendarRangeIntent] = [],
        requestsDashboardBootstrap: Bool = false,
        accountChartAccountIDs: [String] = []
    ) {
        self.viewerID = viewerID
        self.oldCalendarDay = oldCalendarDay
        self.newCalendarDay = newCalendarDay
        self.oldAccountID = oldAccountID
        self.newAccountID = newAccountID
        self.oldMode = oldMode
        self.newMode = newMode
        self.affectedAccountIDs = affectedAccountIDs
        self.calendarRanges = calendarRanges
        self.requestsDashboardBootstrap = requestsDashboardBootstrap
        self.accountChartAccountIDs = accountChartAccountIDs
    }
}

// MARK: - Domain intents

nonisolated struct DashboardReconcileIntent: Sendable, Equatable {
    var viewerID: ProfileID
    /// `nil` = local mutation — adopt revision from authoritative RPC response.
    var targetRevision: Int64?
}

nonisolated struct AnalyticsCalendarRangeIntent: Sendable, Equatable, Hashable {
    var viewerID: ProfileID
    var startDate: String
    var endDate: String
    /// Query account scope (`AnalyticsScopeKeys.allAccountsQuery` = all accounts).
    var accountScope: String
    /// Query mode scope (`AnalyticsScopeKeys.allModesQuery` = all modes).
    var modeScope: String
    /// `nil` or `<= lastApplied` eligible on next local pass; remote passes use concrete targets.
    var targetRevision: Int64?

    var coalescingKey: AnalyticsCalendarRangeCoalescingKey {
        AnalyticsCalendarRangeCoalescingKey(
            viewerID: viewerID.rawValue,
            accountScope: accountScope,
            modeScope: modeScope
        )
    }
}

nonisolated struct AccountChartsReconcileIntent: Sendable, Equatable, Hashable {
    var viewerID: ProfileID
    var accountID: String
    var targetRevision: Int64?

    var normalizedAccountID: String {
        DashboardAnalyticsAccountMetricsLookup.normalizedAccountID(accountID)
    }
}

nonisolated enum AnalyticsLocalMutationKind: String, Sendable {
    case create
    case update
    case delete
    case bulk
    case account
}

nonisolated enum AnalyticsBulkImportSource: String, Sendable {
    case csv
    case screenshot
    case tradovate
    case rithmic
    case brokerResync
    case unknown
}

nonisolated struct AnalyticsDashboardReconcileResult: Sendable {
    var serverRevision: Int64
    var elapsedMs: Int
}

nonisolated struct AnalyticsCalendarReconcileResult: Sendable {
    var serverRevision: Int64
    var rowsWritten: Int
    var elapsedMs: Int
}

nonisolated struct AnalyticsCalendarRangeCoalescingKey: Hashable, Sendable {
    var viewerID: String
    var accountScope: String
    var modeScope: String
}

nonisolated struct AnalyticsRevisionSeed: Sendable, Equatable {
    /// Global high-water for duplicate suppression — not proof of per-domain coverage.
    var highWaterRevision: Int64
    var source: String
}
