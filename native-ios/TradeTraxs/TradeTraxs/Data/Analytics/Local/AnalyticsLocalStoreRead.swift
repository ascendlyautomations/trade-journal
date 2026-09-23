import Foundation
import GRDB

extension AnalyticsLocalStore {
    /// Calendar coverage rows older than `revision` — bounded remote repair (Phase 6D).
    func calendarCoveragesBelowRevision(
        viewerID: ProfileID,
        revision: Int64,
        limit: Int
    ) async throws -> [AnalyticsRangeCoverageRecord] {
        let viewer = normalizedViewer(viewerID)
        let cap = max(0, limit)
        let queue = try await database.databaseQueue()
        return try await queue.read { db in
            try AnalyticsRangeCoverageRecord
                .filter(Column("viewer_id") == viewer)
                .filter(Column("domain") == AnalyticsLocalSchema.domainCalendar)
                .filter(Column("server_revision") < revision)
                .order(Column("server_revision"))
                .limit(cap)
                .fetchAll(db)
        }
    }

    func calendarCoverageSegments(
        viewerID: ProfileID,
        accountScope: String,
        modeScope: String
    ) async throws -> [AnalyticsRangeCoverageRecord] {
        let viewer = normalizedViewer(viewerID)
        let queue = try await database.databaseQueue()
        return try await queue.read { db in
            try AnalyticsRangeCoverageRecord
                .filter(Column("viewer_id") == viewer)
                .filter(Column("domain") == AnalyticsLocalSchema.domainCalendar)
                .filter(Column("account_scope") == accountScope)
                .filter(Column("mode_scope") == modeScope)
                .fetchAll(db)
        }
    }

    /// Best local Calendar material for immediate display (max revision with full coverage).
    func readCalendarRangeForPresentation(
        viewerID: ProfileID,
        startDate: String,
        endDate: String,
        queryAccountID: String?,
        queryMode: String?
    ) async throws -> AnalyticsCalendarPresentationReadResult {
        #if DEBUG
        AnalyticsLocalStoreDebug.assertViewerScoped(viewerID)
        #endif
        let started = Date()
        let accountScope = AnalyticsScopeKeys.accountScopeKey(forQueryAccountID: queryAccountID)
        let modeScope = AnalyticsScopeKeys.modeScopeKey(forQueryMode: queryMode)

        let coverageRows = try await calendarCoverageSegments(
            viewerID: viewerID,
            accountScope: accountScope,
            modeScope: modeScope
        )
        let segments = AnalyticsCalendarCoverageValidator.segments(from: coverageRows)
        let overlapping = segments.filter {
            AnalyticsCalendarCoverageValidator.overlaps(
                $0.start,
                $0.end,
                startDate,
                endDate
            )
        }

        if overlapping.isEmpty {
            return presentationResult(
                state: .missing,
                revision: nil,
                startDate: startDate,
                endDate: endDate,
                accountScope: accountScope,
                modeScope: modeScope,
                wireRows: [],
                canRender: false,
                started: started
            )
        }

        let revisions = Set(overlapping.map(\.serverRevision)).sorted(by: >)
        for revision in revisions {
            let atRevision = overlapping.filter { $0.serverRevision == revision }
            guard AnalyticsCalendarCoverageValidator.fullyCovers(
                requestStart: startDate,
                requestEnd: endDate,
                segments: atRevision
            ) else { continue }

            let dailyRows = try await dailyStats(
                viewerID: viewerID,
                startDate: startDate,
                endDate: endDate,
                accountScope: accountScope,
                modeScope: modeScope
            )
            let rowsAtRevision = dailyRows.filter { $0.ingested_revision == revision }
            if rowsAtRevision.count != dailyRows.count, !dailyRows.isEmpty {
                let found = dailyRows.map(\.ingested_revision).max()
                let wire = rowsAtRevision.map { $0.toWireRow() }
                return presentationResult(
                    state: .stale(foundRevision: found),
                    revision: revision,
                    startDate: startDate,
                    endDate: endDate,
                    accountScope: accountScope,
                    modeScope: modeScope,
                    wireRows: wire.isEmpty ? dailyRows.map { $0.toWireRow() } : wire,
                    canRender: true,
                    started: started
                )
            }
            let wireRows = rowsAtRevision.map { $0.toWireRow() }
            return presentationResult(
                state: .available,
                revision: revision,
                startDate: startDate,
                endDate: endDate,
                accountScope: accountScope,
                modeScope: modeScope,
                wireRows: wireRows,
                canRender: true,
                started: started
            )
        }

        if !overlapping.isEmpty {
            return presentationResult(
                state: .partial,
                revision: revisions.first,
                startDate: startDate,
                endDate: endDate,
                accountScope: accountScope,
                modeScope: modeScope,
                wireRows: [],
                canRender: false,
                started: started
            )
        }

        return presentationResult(
            state: .missing,
            revision: nil,
            startDate: startDate,
            endDate: endDate,
            accountScope: accountScope,
            modeScope: modeScope,
            wireRows: [],
            canRender: false,
            started: started
        )
    }

    private func presentationResult(
        state: AnalyticsLocalReadState,
        revision: Int64?,
        startDate: String,
        endDate: String,
        accountScope: String,
        modeScope: String,
        wireRows: [AnalyticsDailyStatRowV1],
        canRender: Bool,
        started: Date
    ) -> AnalyticsCalendarPresentationReadResult {
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        AnalyticsGRDBProbe.logReadPerf(
            domain: "calendar",
            rows: wireRows.count,
            metricsRows: nil,
            chartBundles: nil,
            bundles: nil,
            elapsedMs: elapsed
        )
        return AnalyticsCalendarPresentationReadResult(
            state: state,
            effectiveRevision: revision,
            startDate: startDate,
            endDate: endDate,
            accountScope: accountScope,
            modeScope: modeScope,
            wireRows: wireRows,
            canRenderLocally: canRender
        )
    }

    /// Viewer-scoped Calendar shadow read — coverage validated before rows are authoritative.
    func readCalendarRange(
        viewerID: ProfileID,
        startDate: String,
        endDate: String,
        queryAccountID: String?,
        queryMode: String?,
        requiredRevision: Int64
    ) async throws -> AnalyticsCalendarRangeReadResult {
        #if DEBUG
        AnalyticsLocalStoreDebug.assertViewerScoped(viewerID)
        #endif
        let started = Date()
        let accountScope = AnalyticsScopeKeys.accountScopeKey(forQueryAccountID: queryAccountID)
        let modeScope = AnalyticsScopeKeys.modeScopeKey(forQueryMode: queryMode)

        let coverageRows = try await calendarCoverageSegments(
            viewerID: viewerID,
            accountScope: accountScope,
            modeScope: modeScope
        )
        let segments = AnalyticsCalendarCoverageValidator.segments(from: coverageRows)
        let coverageState = AnalyticsCalendarCoverageValidator.evaluate(
            requestStart: startDate,
            requestEnd: endDate,
            requiredRevision: requiredRevision,
            segments: segments
        )

        var dailyRows: [AnalyticsDailyStatRecord] = []
        var wireRows: [AnalyticsDailyStatRowV1] = []
        var coverageRevision: Int64?

        if coverageState == .available {
            dailyRows = try await dailyStats(
                viewerID: viewerID,
                startDate: startDate,
                endDate: endDate,
                accountScope: accountScope,
                modeScope: modeScope
            )
            if dailyRows.contains(where: { $0.ingested_revision != requiredRevision }) {
                return AnalyticsCalendarRangeReadResult(
                    state: .stale(foundRevision: dailyRows.map(\.ingested_revision).max()),
                    requiredRevision: requiredRevision,
                    startDate: startDate,
                    endDate: endDate,
                    accountScope: accountScope,
                    modeScope: modeScope,
                    dailyRows: [],
                    wireRows: [],
                    coverageRevision: requiredRevision
                )
            }
            wireRows = dailyRows.map { $0.toWireRow() }
            coverageRevision = requiredRevision
        }

        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        AnalyticsGRDBProbe.logReadPerf(
            domain: "calendar",
            rows: dailyRows.count,
            metricsRows: nil,
            chartBundles: nil,
            bundles: nil,
            elapsedMs: elapsed
        )

        return AnalyticsCalendarRangeReadResult(
            state: coverageState,
            requiredRevision: requiredRevision,
            startDate: startDate,
            endDate: endDate,
            accountScope: accountScope,
            modeScope: modeScope,
            dailyRows: coverageState == .available ? dailyRows : [],
            wireRows: coverageState == .available ? wireRows : [],
            coverageRevision: coverageRevision
        )
    }

    /// Best complete local Dashboard snapshot for immediate presentation (max revision).
    func readDashboardSnapshotForPresentation(
        viewerID: ProfileID
    ) async throws -> AnalyticsDashboardPresentationReadResult {
        #if DEBUG
        AnalyticsLocalStoreDebug.assertViewerScoped(viewerID)
        #endif
        let started = Date()
        let viewer = normalizedViewer(viewerID)
        let queue = try await database.databaseQueue()

        let (metrics, charts, bootstrapCoverage) = try await queue.read { db -> (
            [DashboardPresetMetricsRecord],
            [DashboardChartBundleRecord],
            [AnalyticsRangeCoverageRecord]
        ) in
            let metrics = try DashboardPresetMetricsRecord
                .filter(Column("viewer_id") == viewer)
                .fetchAll(db)
            let charts = try DashboardChartBundleRecord
                .filter(Column("viewer_id") == viewer)
                .filter(Column("account_scope_key") == AnalyticsScopeKeys.allAccountsQuery)
                .fetchAll(db)
            let coverage = try AnalyticsRangeCoverageRecord
                .filter(Column("viewer_id") == viewer)
                .filter(Column("domain") == AnalyticsLocalSchema.domainDashboardBootstrap)
                .fetchAll(db)
            return (metrics, charts, coverage)
        }

        let revisions = Set(
            metrics.map(\.ingested_revision)
                + charts.map(\.ingested_revision)
                + bootstrapCoverage.map(\.server_revision)
        ).filter { $0 > 0 }.sorted(by: >)

        for revision in revisions {
            let state = Self.dashboardSnapshotState(
                requiredRevision: revision,
                metrics: metrics,
                aggregateCharts: charts,
                bootstrapCoverage: bootstrapCoverage
            )
            if state == .available,
               let snapshot = try? Self.buildDashboardSnapshot(
                   requiredRevision: revision,
                   metrics: metrics,
                   aggregateCharts: charts
               )
            {
                let elapsed = Int(Date().timeIntervalSince(started) * 1000)
                AnalyticsGRDBProbe.logReadPerf(
                    domain: "dashboard",
                    rows: nil,
                    metricsRows: metrics.filter { $0.ingested_revision == revision }.count,
                    chartBundles: charts.filter { $0.ingested_revision == revision }.count,
                    bundles: nil,
                    elapsedMs: elapsed
                )
                return AnalyticsDashboardPresentationReadResult(
                    state: .available,
                    effectiveRevision: revision,
                    snapshot: snapshot,
                    canRenderLocally: true,
                    elapsedMs: elapsed
                )
            }
        }

        if !revisions.isEmpty {
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            return AnalyticsDashboardPresentationReadResult(
                state: .partial,
                effectiveRevision: revisions.first,
                snapshot: nil,
                canRenderLocally: false,
                elapsedMs: elapsed
            )
        }

        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        return AnalyticsDashboardPresentationReadResult(
            state: .missing,
            effectiveRevision: nil,
            snapshot: nil,
            canRenderLocally: false,
            elapsedMs: elapsed
        )
    }

    func readDashboardSnapshot(
        viewerID: ProfileID,
        requiredRevision: Int64
    ) async throws -> AnalyticsDashboardSnapshotReadResult {
        #if DEBUG
        AnalyticsLocalStoreDebug.assertViewerScoped(viewerID)
        #endif
        let started = Date()
        let viewer = normalizedViewer(viewerID)
        let queue = try await database.databaseQueue()

        let (metrics, charts, bootstrapCoverage) = try await queue.read { db -> (
            [DashboardPresetMetricsRecord],
            [DashboardChartBundleRecord],
            [AnalyticsRangeCoverageRecord]
        ) in
            let metrics = try DashboardPresetMetricsRecord
                .filter(Column("viewer_id") == viewer)
                .fetchAll(db)
            let charts = try DashboardChartBundleRecord
                .filter(Column("viewer_id") == viewer)
                .filter(Column("account_scope_key") == AnalyticsScopeKeys.allAccountsQuery)
                .fetchAll(db)
            let coverage = try AnalyticsRangeCoverageRecord
                .filter(Column("viewer_id") == viewer)
                .filter(Column("domain") == AnalyticsLocalSchema.domainDashboardBootstrap)
                .fetchAll(db)
            return (metrics, charts, coverage)
        }

        let state = Self.dashboardSnapshotState(
            requiredRevision: requiredRevision,
            metrics: metrics,
            aggregateCharts: charts,
            bootstrapCoverage: bootstrapCoverage
        )

        var snapshot: AnalyticsLocalDashboardV3Snapshot?
        if state == .available {
            snapshot = try Self.buildDashboardSnapshot(
                requiredRevision: requiredRevision,
                metrics: metrics,
                aggregateCharts: charts
            )
        }

        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        AnalyticsGRDBProbe.logReadPerf(
            domain: "dashboard",
            rows: nil,
            metricsRows: metrics.filter { $0.ingested_revision == requiredRevision }.count,
            chartBundles: charts.filter { $0.ingested_revision == requiredRevision }.count,
            bundles: nil,
            elapsedMs: elapsed
        )

        return AnalyticsDashboardSnapshotReadResult(
            state: state,
            requiredRevision: requiredRevision,
            snapshot: snapshot
        )
    }

    func readDashboardAccountCharts(
        viewerID: ProfileID,
        accountID: TradingAccountID,
        requiredRevision: Int64
    ) async throws -> AnalyticsDashboardAccountChartsReadResult {
        #if DEBUG
        AnalyticsLocalStoreDebug.assertViewerScoped(viewerID)
        #endif
        let started = Date()
        let viewer = normalizedViewer(viewerID)
        let accountKey = AnalyticsScopeKeys.accountScopeKey(forQueryAccountID: accountID.rawValue)
        let queue = try await database.databaseQueue()

        let (bundles, coverageRows) = try await queue.read { db -> (
            [DashboardChartBundleRecord],
            [AnalyticsRangeCoverageRecord]
        ) in
            let bundles = try DashboardChartBundleRecord
                .filter(Column("viewer_id") == viewer)
                .filter(Column("account_scope_key") == accountKey)
                .fetchAll(db)
            let coverage = try AnalyticsRangeCoverageRecord
                .filter(Column("viewer_id") == viewer)
                .filter(Column("domain") == AnalyticsLocalSchema.domainDashboardAccountCharts)
                .filter(Column("account_scope") == accountKey)
                .fetchAll(db)
            return (bundles, coverage)
        }

        let state = Self.accountChartsState(
            requiredRevision: requiredRevision,
            bundles: bundles,
            coverageRows: coverageRows
        )

        var presets: [String: AnalyticsDashboardChartsPresetV1] = [:]
        if state == .available {
            for bundle in bundles where bundle.ingested_revision == requiredRevision {
                if let decoded = try? bundle.decodedCharts() {
                    presets[bundle.preset_key] = decoded
                }
            }
        }

        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        AnalyticsGRDBProbe.logReadPerf(
            domain: "accountCharts",
            rows: nil,
            metricsRows: nil,
            chartBundles: nil,
            bundles: bundles.filter { $0.ingested_revision == requiredRevision }.count,
            elapsedMs: elapsed
        )

        return AnalyticsDashboardAccountChartsReadResult(
            state: state,
            requiredRevision: requiredRevision,
            accountScopeKey: accountKey,
            presets: state == .available ? presets : [:]
        )
    }

    // MARK: - Dashboard snapshot assembly

    static func dashboardSnapshotState(
        requiredRevision: Int64,
        metrics: [DashboardPresetMetricsRecord],
        aggregateCharts: [DashboardChartBundleRecord],
        bootstrapCoverage: [AnalyticsRangeCoverageRecord]
    ) -> AnalyticsLocalReadState {
        let keys = AnalyticsLocalDashboardPolicy.aggregatePresetKeys
        let metricsAtR = metrics.filter { $0.ingested_revision == requiredRevision }
        let chartsAtR = aggregateCharts.filter { $0.ingested_revision == requiredRevision }
        let aggregateAtR = metricsAtR.filter { $0.scope == AnalyticsLocalSchema.scopeAggregate }
        let aggregateKeysOK = keys.allSatisfy { key in
            aggregateAtR.contains(where: { $0.preset_key == key })
        }
        let chartKeysOK = keys.allSatisfy { key in
            chartsAtR.contains(where: { $0.preset_key == key })
        }

        if aggregateKeysOK, chartKeysOK {
            let revisionMismatch = metrics.contains { $0.ingested_revision != requiredRevision }
                || aggregateCharts.contains { $0.ingested_revision != requiredRevision }
            if revisionMismatch {
                return .partial
            }
            let coverageOK = bootstrapCoverage.contains { $0.server_revision == requiredRevision }
            if coverageOK {
                return .available
            }
            return .partial
        }

        if !metricsAtR.isEmpty || !chartsAtR.isEmpty {
            return .partial
        }

        let hasOlder = metrics.contains { $0.ingested_revision > 0 && $0.ingested_revision < requiredRevision }
            || aggregateCharts.contains { $0.ingested_revision > 0 && $0.ingested_revision < requiredRevision }
            || bootstrapCoverage.contains { $0.server_revision > 0 && $0.server_revision < requiredRevision }
        if hasOlder {
            let found = [
                metrics.map(\.ingested_revision).max(),
                aggregateCharts.map(\.ingested_revision).max(),
                bootstrapCoverage.map(\.server_revision).max()
            ].compactMap { $0 }.max()
            return .stale(foundRevision: found)
        }

        return .missing
    }

    static func buildDashboardSnapshot(
        requiredRevision: Int64,
        metrics: [DashboardPresetMetricsRecord],
        aggregateCharts: [DashboardChartBundleRecord]
    ) throws -> AnalyticsLocalDashboardV3Snapshot {
        let metricsAtR = metrics.filter { $0.ingested_revision == requiredRevision }
        let chartsAtR = aggregateCharts.filter { $0.ingested_revision == requiredRevision }
        let asOf = metricsAtR.first?.as_of_et ?? chartsAtR.first?.preset_end ?? ""

        var aggregatePresets: [String: AnalyticsDashboardPresetBundleV1] = [:]
        for key in AnalyticsLocalDashboardPolicy.aggregatePresetKeys {
            guard
                let metric = metricsAtR.first(where: {
                    $0.scope == AnalyticsLocalSchema.scopeAggregate && $0.preset_key == key
                }),
                let chart = chartsAtR.first(where: { $0.preset_key == key }),
                let charts = try? chart.decodedCharts()
            else { continue }
            let metricsPreset = metric.toMetricsPreset()
            aggregatePresets[key] = AnalyticsDashboardPresetBundleV1(
                preset: metricsPreset.preset,
                start: metricsPreset.start,
                end: metricsPreset.end,
                metrics: metricsPreset.metrics,
                equity: charts.equity,
                distributions: charts.distributions,
                insights: charts.insights
            )
        }

        var accountGroups: [String: [String: AnalyticsDashboardMetricsPresetV1]] = [:]
        for row in metricsAtR where row.scope == AnalyticsLocalSchema.scopeAccount {
            var presets = accountGroups[row.account_scope_key] ?? [:]
            presets[row.preset_key] = row.toMetricsPreset()
            accountGroups[row.account_scope_key] = presets
        }
        let accountPresetMetrics = accountGroups.map { accountKey, presets in
            AnalyticsDashboardBootstrapV3.AccountPresetMetrics(
                account_id: accountKey,
                presets: presets
            )
        }.sorted { $0.account_id < $1.account_id }

        return AnalyticsLocalDashboardV3Snapshot(
            revision: requiredRevision,
            asOfET: asOf,
            aggregatePresets: aggregatePresets,
            accountPresetMetrics: accountPresetMetrics
        )
    }

    static func accountChartsState(
        requiredRevision: Int64,
        bundles: [DashboardChartBundleRecord],
        coverageRows: [AnalyticsRangeCoverageRecord]
    ) -> AnalyticsLocalReadState {
        let atR = bundles.filter { $0.ingested_revision == requiredRevision }
        let coverageAtR = coverageRows.contains { $0.server_revision == requiredRevision }

        if coverageAtR, !atR.isEmpty {
            return .available
        }

        if coverageAtR, atR.isEmpty, bundles.isEmpty {
            return .missing
        }

        if !atR.isEmpty, !coverageAtR {
            return .partial
        }

        let hasOlder = bundles.contains { $0.ingested_revision > 0 && $0.ingested_revision < requiredRevision }
            || coverageRows.contains { $0.server_revision > 0 && $0.server_revision < requiredRevision }
        if hasOlder, atR.isEmpty {
            return .stale(foundRevision: bundles.map(\.ingested_revision).max())
        }

        if !bundles.isEmpty, atR.isEmpty {
            return .stale(foundRevision: bundles.map(\.ingested_revision).max())
        }

        return .missing
    }
}
