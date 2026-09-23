import Foundation

/// Shadow-write Calendar V2 analytical RPC payloads to GRDB (failures must not affect UI).
enum AnalyticsShadowWriter {
    static func ingestCalendarDailyRangeIfNeeded(
        viewerID: ProfileID,
        payload: AnalyticsDailyRangeBootstrapV1,
        startDate: String,
        endDate: String,
        queryAccountID: String?,
        queryMode: String?
    ) {
        Task(priority: .utility) {
            await ingestCalendarDailyRange(
                viewerID: viewerID,
                payload: payload,
                startDate: startDate,
                endDate: endDate,
                queryAccountID: queryAccountID,
                queryMode: queryMode
            )
        }
    }

    static func ingestCalendarDailyRange(
        viewerID: ProfileID,
        payload: AnalyticsDailyRangeBootstrapV1,
        startDate: String,
        endDate: String,
        queryAccountID: String?,
        queryMode: String?
    ) async {
        let scope = AnalyticsLocalStore.IngestScope(
            startDate: startDate,
            endDate: endDate,
            accountScope: AnalyticsScopeKeys.accountScopeKey(forQueryAccountID: queryAccountID),
            modeScope: AnalyticsScopeKeys.modeScopeKey(forQueryMode: queryMode)
        )
        let store = AnalyticsLocalStore.sharedStore()
        do {
            try await store.ingestCalendarDailyRange(
                viewerID: viewerID,
                payload: payload,
                scope: scope
            )
            #if DEBUG
            let localRows = try await store.dailyStats(
                viewerID: viewerID,
                startDate: startDate,
                endDate: endDate,
                accountScope: scope.accountScope,
                modeScope: scope.modeScope
            )
            let coverage = try await store.coverage(
                viewerID: viewerID,
                domain: AnalyticsLocalSchema.domainCalendar,
                accountScope: scope.accountScope,
                modeScope: scope.modeScope,
                startDate: startDate,
                endDate: endDate
            )
            _ = AnalyticsShadowParity.validate(
                viewerID: viewerID,
                payload: payload,
                scope: scope,
                localRows: localRows,
                coverage: coverage
            )
            await AnalyticsShadowReadParity.validateCalendarAfterIngest(
                viewerID: viewerID,
                payload: payload,
                startDate: startDate,
                endDate: endDate,
                queryAccountID: queryAccountID,
                queryMode: queryMode,
                accountFilter: .all,
                modeFilter: queryMode
            )
            _ = await AnalyticsDatabase.shared.databaseFileBytes()
            #endif
        } catch {
            AnalyticsGRDBProbe.logShadowIngestFailure("\(error)")
        }
    }
}
