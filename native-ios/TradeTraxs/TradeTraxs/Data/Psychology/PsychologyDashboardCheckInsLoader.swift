import Foundation

/// Web `fetchPsychologyDashboardCheckIns` — 90-day PostgREST range + psychology RPC (no account scope on dashboard).
nonisolated enum PsychologyDashboardCheckInsLoader {
    static func load(
        profileID: ProfileID,
        dailyCheckIns: any TraderDailyCheckInRepository,
        rpc: (any RPCClient)?
    ) async throws -> [TraderDailyCheckIn] {
        let range = dashboardWindow()
        let rangeRows = try await dailyCheckIns.checkIns(
            for: profileID,
            from: range.start,
            to: range.end
        )

        guard BackendV2FeatureFlags.isEnabled(.dashboard), let rpc else {
            return rangeRows
        }

        // Web: RPC failure must not discard the 90-day range fetch.
        let rpcRows = (try? await PsychologyCheckInBootstrapLoader.load(
            rpc: rpc,
            accountID: nil
        )) ?? []
        return TraderDailyCheckInMerge.preferNewer(primary: rangeRows, secondary: rpcRows)
    }

    /// Same 90-day PostgREST window as Check-In History (authoritative for psych gate).
    static func loadHistoryWindow(
        profileID: ProfileID,
        dailyCheckIns: any TraderDailyCheckInRepository
    ) async throws -> [TraderDailyCheckIn] {
        let range = dashboardWindow()
        return try await dailyCheckIns.checkIns(
            for: profileID,
            from: range.start,
            to: range.end
        )
    }

    static func dashboardWindow() -> (start: String, end: String) {
        let end = TraderPsychologyAnalyticsFoundation.todayCheckInDateKey()
        let start = CheckInHistoryAggregator.startDateKey(
            dayLimit: CheckInHistoryAggregator.defaultDayWindow
        )
        return (start, end)
    }
}
