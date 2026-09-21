import Foundation
import GRDB

/// Viewer-scoped analytical store (shadow write + typed read APIs — not UI-authoritative through Phase 5D).
struct AnalyticsLocalStore {
    struct IngestScope: Sendable, Equatable {
        var startDate: String
        var endDate: String
        /// Query account scope (`*` = all accounts).
        var accountScope: String
        /// Query mode scope (`*` = all modes returned by RPC).
        var modeScope: String
    }

    let database: AnalyticsDatabase

    init(database: AnalyticsDatabase = .shared) {
        self.database = database
    }

    /// Replace daily rows for the ingested scope, then coverage + sync revision (single transaction).
    func ingestCalendarDailyRange(
        viewerID: ProfileID,
        payload: AnalyticsDailyRangeBootstrapV1,
        scope: IngestScope,
        simulateFailureAfterDelete: Bool = false
    ) async throws {
        let viewer = normalizedViewer(viewerID)
        let revision = payload.revisionInt
        let records = payload.days.map {
            AnalyticsDailyStatRecord.from(row: $0, viewerID: viewer, ingestedRevision: revision)
        }
        let started = Date()
        let queue = try await database.databaseQueue()
        try await queue.write { db in
            try deleteDailyStatsInIngestScope(db: db, viewerID: viewer, scope: scope)
            if simulateFailureAfterDelete {
                throw AnalyticsLocalStoreTestSupport.simulatedFailure
            }
            for record in records {
                try record.insert(db, onConflict: .replace)
            }
            let coverage = AnalyticsRangeCoverageRecord(
                viewer_id: viewer,
                domain: AnalyticsLocalSchema.domainCalendar,
                account_scope: scope.accountScope,
                mode_scope: scope.modeScope,
                start_date: scope.startDate,
                end_date: scope.endDate,
                server_revision: revision,
                fetched_at: isoNow()
            )
            try coverage.insert(db, onConflict: .replace)
            try upsertMonotonicSyncState(db: db, viewerID: viewer, revision: revision)
        }
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        AnalyticsGRDBProbe.logIngest(rows: records.count, elapsedMs: elapsed)
    }

    func dailyStats(
        viewerID: ProfileID,
        startDate: String,
        endDate: String,
        accountScope: String,
        modeScope: String
    ) async throws -> [AnalyticsDailyStatRecord] {
        let viewer = normalizedViewer(viewerID)
        let started = Date()
        let queue = try await database.databaseQueue()
        let rows = try await queue.read { db in
            var sql = """
                SELECT * FROM analytics_daily_stat
                WHERE viewer_id = ?
                  AND calendar_day >= ?
                  AND calendar_day <= ?
                """
            var args: [DatabaseValueConvertible?] = [viewer, startDate, endDate]
            if modeScope != AnalyticsScopeKeys.allModesQuery {
                sql += " AND mode_effective = ?"
                args.append(modeScope)
            }
            if accountScope != AnalyticsScopeKeys.allAccountsQuery {
                sql += " AND account_scope_key = ?"
                args.append(accountScope)
            }
            sql += " ORDER BY calendar_day, mode_effective, account_scope_key"
            return try AnalyticsDailyStatRecord.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        AnalyticsGRDBProbe.logQuery(rows: rows.count, elapsedMs: elapsed)
        return rows
    }

    func coverage(
        viewerID: ProfileID,
        domain: String,
        accountScope: String,
        modeScope: String,
        startDate: String,
        endDate: String
    ) async throws -> AnalyticsRangeCoverageRecord? {
        let viewer = normalizedViewer(viewerID)
        let queue = try await database.databaseQueue()
        return try await queue.read { db in
            try AnalyticsRangeCoverageRecord
                .filter(sql: "viewer_id = ?", arguments: [viewer])
                .filter(Column("domain") == domain)
                .filter(Column("account_scope") == accountScope)
                .filter(Column("mode_scope") == modeScope)
                .filter(Column("start_date") == startDate)
                .filter(Column("end_date") == endDate)
                .fetchOne(db)
        }
    }

    func syncState(viewerID: ProfileID) async throws -> AnalyticsSyncStateRecord? {
        let viewer = normalizedViewer(viewerID)
        let queue = try await database.databaseQueue()
        return try await queue.read { db in
            try AnalyticsSyncStateRecord.fetchOne(db, key: viewer)
        }
    }

    func ingestDashboardBootstrap(
        viewerID: ProfileID,
        bootstrap: AnalyticsDashboardBootstrapV3
    ) async throws -> (metricsWritten: Int, chartBundlesWritten: Int, elapsedMs: Int) {
        let viewer = normalizedViewer(viewerID)
        let revision = bootstrap.data.revisionInt
        let asOf = bootstrap.data.as_of_et
        let started = Date()

        var metricRecords: [DashboardPresetMetricsRecord] = []
        for (key, bundle) in bootstrap.data.aggregatePresets {
            metricRecords.append(
                DashboardPresetMetricsRecord.fromAggregate(
                    presetKey: key,
                    bundle: bundle,
                    viewerID: viewer,
                    asOfET: asOf,
                    revision: revision
                )
            )
        }
        for accountRow in bootstrap.data.account_preset_metrics ?? [] {
            for (key, preset) in accountRow.presets {
                metricRecords.append(
                    DashboardPresetMetricsRecord.fromAccount(
                        accountID: accountRow.account_id,
                        presetKey: key,
                        metricsPreset: preset,
                        viewerID: viewer,
                        asOfET: asOf,
                        revision: revision
                    )
                )
            }
        }

        var aggregateCharts: [DashboardChartBundleRecord] = []
        for (key, bundle) in bootstrap.data.aggregatePresets {
            let charts = AnalyticsDashboardChartsPresetV1(
                preset: bundle.preset,
                start: bundle.start,
                end: bundle.end,
                equity: bundle.equity,
                distributions: bundle.distributions,
                insights: bundle.insights
            )
            aggregateCharts.append(
                try DashboardChartBundleRecord.from(
                    charts: charts,
                    viewerID: viewer,
                    accountScopeKey: AnalyticsScopeKeys.allAccountsQuery,
                    revision: revision
                )
            )
            _ = key
        }

        let queue = try await database.databaseQueue()
        try await queue.write { db in
            try DashboardPresetMetricsRecord
                .filter(Column("viewer_id") == viewer)
                .deleteAll(db)
            try DashboardChartBundleRecord
                .filter(Column("viewer_id") == viewer)
                .filter(Column("account_scope_key") == AnalyticsScopeKeys.allAccountsQuery)
                .deleteAll(db)
            for record in metricRecords {
                try record.insert(db, onConflict: .replace)
            }
            for record in aggregateCharts {
                try record.insert(db, onConflict: .replace)
            }
            let coverage = AnalyticsRangeCoverageRecord(
                viewer_id: viewer,
                domain: AnalyticsLocalSchema.domainDashboardBootstrap,
                account_scope: AnalyticsScopeKeys.allAccountsQuery,
                mode_scope: AnalyticsScopeKeys.allModesQuery,
                start_date: asOf,
                end_date: asOf,
                server_revision: revision,
                fetched_at: isoNow()
            )
            try coverage.insert(db, onConflict: .replace)
            try upsertMonotonicSyncState(db: db, viewerID: viewer, revision: revision)
        }
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        AnalyticsGRDBProbe.logDashboardBootstrapIngest(
            metricsRows: metricRecords.count,
            chartBundles: aggregateCharts.count,
            elapsedMs: elapsed
        )
        return (metricRecords.count, aggregateCharts.count, elapsed)
    }

    func ingestDashboardAccountCharts(
        viewerID: ProfileID,
        response: AnalyticsDashboardAccountChartsV3,
        accountID: TradingAccountID,
        knownRevision: Int64
    ) async throws -> (bundlesWritten: Int, elapsedMs: Int) {
        let viewer = normalizedViewer(viewerID)
        let accountKey = AnalyticsScopeKeys.accountScopeKey(forQueryAccountID: accountID.rawValue)
        let ingestRevision = knownRevision
        let asOf = response.data.as_of_et
        let started = Date()

        var bundles: [DashboardChartBundleRecord] = []
        for (_, charts) in response.data.presets {
            bundles.append(
                try DashboardChartBundleRecord.from(
                    charts: charts,
                    viewerID: viewer,
                    accountScopeKey: accountKey,
                    revision: ingestRevision
                )
            )
        }

        let queue = try await database.databaseQueue()
        try await queue.write { db in
            try DashboardChartBundleRecord
                .filter(Column("viewer_id") == viewer)
                .filter(Column("account_scope_key") == accountKey)
                .deleteAll(db)
            for record in bundles {
                try record.insert(db, onConflict: .replace)
            }
            let coverage = AnalyticsRangeCoverageRecord(
                viewer_id: viewer,
                domain: AnalyticsLocalSchema.domainDashboardAccountCharts,
                account_scope: accountKey,
                mode_scope: AnalyticsScopeKeys.allModesQuery,
                start_date: asOf,
                end_date: asOf,
                server_revision: ingestRevision,
                fetched_at: isoNow()
            )
            try coverage.insert(db, onConflict: .replace)
            try upsertMonotonicSyncState(db: db, viewerID: viewer, revision: ingestRevision)
        }
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        AnalyticsGRDBProbe.logAccountChartsIngest(bundles: bundles.count, elapsedMs: elapsed)
        return (bundles.count, elapsed)
    }

    func dashboardPresetMetrics(viewerID: ProfileID) async throws -> [DashboardPresetMetricsRecord] {
        let viewer = normalizedViewer(viewerID)
        let queue = try await database.databaseQueue()
        return try await queue.read { db in
            try DashboardPresetMetricsRecord
                .filter(Column("viewer_id") == viewer)
                .fetchAll(db)
        }
    }

    func dashboardChartBundles(
        viewerID: ProfileID,
        accountScopeKey: String
    ) async throws -> [DashboardChartBundleRecord] {
        let viewer = normalizedViewer(viewerID)
        let queue = try await database.databaseQueue()
        return try await queue.read { db in
            try DashboardChartBundleRecord
                .filter(Column("viewer_id") == viewer)
                .filter(Column("account_scope_key") == accountScopeKey)
                .fetchAll(db)
        }
    }

    func clearViewer(_ viewerID: ProfileID) async {
        let viewer = normalizedViewer(viewerID)
        do {
            let queue = try await database.databaseQueue()
            try await queue.write { db in
                try AnalyticsDailyStatRecord
                    .filter(Column("viewer_id") == viewer)
                    .deleteAll(db)
                try AnalyticsRangeCoverageRecord
                    .filter(Column("viewer_id") == viewer)
                    .deleteAll(db)
                try DashboardPresetMetricsRecord
                    .filter(Column("viewer_id") == viewer)
                    .deleteAll(db)
                try DashboardChartBundleRecord
                    .filter(Column("viewer_id") == viewer)
                    .deleteAll(db)
                try AnalyticsSyncStateRecord
                    .filter(Column("viewer_id") == viewer)
                    .deleteAll(db)
                try ProfileAnalyticsSnapshotRecord
                    .filter(Column("viewer_id") == viewer)
                    .deleteAll(db)
            }
        } catch {
            AnalyticsGRDBProbe.logLogoutCleanupFailure("\(error)")
        }
    }

    // MARK: - Internal

    func normalizedViewer(_ viewerID: ProfileID) -> String {
        let raw = viewerID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        #if DEBUG
        precondition(!raw.isEmpty, "AnalyticsLocalStore requires non-empty viewerID")
        #endif
        return raw
    }

    private func deleteDailyStatsInIngestScope(
        db: Database,
        viewerID: String,
        scope: IngestScope
    ) throws {
        var sql = """
            DELETE FROM analytics_daily_stat
            WHERE viewer_id = ?
              AND calendar_day >= ?
              AND calendar_day <= ?
            """
        var args: [DatabaseValueConvertible?] = [viewerID, scope.startDate, scope.endDate]
        if scope.modeScope != AnalyticsScopeKeys.allModesQuery {
            sql += " AND mode_effective = ?"
            args.append(scope.modeScope)
        }
        if scope.accountScope != AnalyticsScopeKeys.allAccountsQuery {
            sql += " AND account_scope_key = ?"
            args.append(scope.accountScope)
        }
        try db.execute(sql: sql, arguments: StatementArguments(args))
    }

    private func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func upsertMonotonicSyncState(db: Database, viewerID: String, revision: Int64) throws {
        if var existing = try AnalyticsSyncStateRecord.fetchOne(db, key: viewerID) {
            existing.server_revision = max(existing.server_revision, revision)
            existing.updated_at = isoNow()
            existing.local_schema_version = AnalyticsLocalSchema.localSchemaVersion
            try existing.update(db)
        } else {
            try AnalyticsSyncStateRecord(
                viewer_id: viewerID,
                server_revision: revision,
                updated_at: isoNow(),
                local_schema_version: AnalyticsLocalSchema.localSchemaVersion
            ).insert(db)
        }
    }

}

#if DEBUG
nonisolated enum AnalyticsLocalStoreDebug {
    static func assertViewerScoped(_ viewerID: ProfileID?) {
        assert(viewerID != nil, "Analytics read requires explicit viewerID")
    }
}

enum AnalyticsLocalStoreTestSupport {
    static let simulatedFailure = NSError(domain: "AnalyticsLocalStoreTest", code: 1)
}
#endif
