import Foundation
import GRDB
import Testing
@testable import TradeTraxs

struct AnalyticsLocalGRDBTests {
    private func makeTempDatabase() throws -> (URL, AnalyticsLocalStore) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("analytics-grdb-test-\(UUID().uuidString).sqlite")
        let db = AnalyticsDatabase(configuration: .testing(databaseURL: url))
        let store = AnalyticsLocalStore(database: db)
        return (url, store)
    }

    private func samplePayload(
        days: [AnalyticsDailyStatRowV1],
        revision: Int64 = 5
    ) -> AnalyticsDailyRangeBootstrapV1 {
        AnalyticsDailyRangeBootstrapV1(
            revision: PostgresFlexibleDouble(Double(revision)),
            state_updated_at: "2026-09-21T12:00:00.000Z",
            start: "2026-09-01",
            end: "2026-09-30",
            account_id: nil,
            mode: nil,
            days: days,
            summary: AnalyticsDailyRangeSummaryV1(
                trade_count: days.reduce(0) { $0 + $1.trade_count },
                win_count: 0,
                loss_count: 0,
                breakeven_count: 0,
                net_pnl: PostgresFlexibleDouble(0),
                gross_profit: PostgresFlexibleDouble(0),
                gross_loss: PostgresFlexibleDouble(0)
            )
        )
    }

    private func row(
        day: String,
        account: String? = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
        trades: Int = 1,
        net: Double = 100
    ) -> AnalyticsDailyStatRowV1 {
        AnalyticsDailyStatRowV1(
            calendar_day: day,
            account_id: account,
            mode_effective: "live",
            trade_count: trades,
            win_count: 1,
            loss_count: 0,
            breakeven_count: 0,
            net_pnl: PostgresFlexibleDouble(net),
            gross_profit: PostgresFlexibleDouble(net),
            gross_loss: PostgresFlexibleDouble(0),
            long_count: 0,
            long_pnl: PostgresFlexibleDouble(0),
            short_count: 0,
            short_pnl: PostgresFlexibleDouble(0),
            sum_rr: PostgresFlexibleDouble(0),
            rr_count: 0,
            sum_hold_seconds: PostgresFlexibleDouble(0),
            hold_count: 0,
            largest_win: PostgresFlexibleDouble(net),
            largest_loss: nil
        )
    }

    @Test("Migration creates expected tables")
    func schemaCreated() async throws {
        let (url, _) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let db = AnalyticsDatabase(configuration: .testing(databaseURL: url))
        let queue = try await db.databaseQueue()
        try await queue.read { db in
            let tables = try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
            )
            #expect(tables.contains("analytics_sync_state"))
            #expect(tables.contains("analytics_daily_stat"))
            #expect(tables.contains("analytics_range_coverage"))
            #expect(tables.contains("dashboard_preset_metrics"))
            #expect(tables.contains("dashboard_chart_bundle"))
        }
    }

    @Test("Migration is idempotent")
    func migrationIdempotent() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("analytics-grdb-migrate-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await AnalyticsDatabase(configuration: .testing(databaseURL: url)).databaseQueue()
        _ = try await AnalyticsDatabase(configuration: .testing(databaseURL: url)).databaseQueue()
    }

    @Test("Sparse month + full coverage")
    func sparseMonthCoverage() async throws {
        let (url, store) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("viewer-a")
        let scope = AnalyticsLocalStore.IngestScope(
            startDate: "2026-09-01",
            endDate: "2026-09-30",
            accountScope: AnalyticsScopeKeys.allAccountsQuery,
            modeScope: AnalyticsScopeKeys.allModesQuery
        )
        let payload = samplePayload(days: [
            row(day: "2026-09-04"),
            row(day: "2026-09-10"),
        ])
        try await store.ingestCalendarDailyRange(viewerID: viewer, payload: payload, scope: scope)
        let coverage = try await store.coverage(
            viewerID: viewer,
            domain: AnalyticsLocalSchema.domainCalendar,
            accountScope: scope.accountScope,
            modeScope: scope.modeScope,
            startDate: scope.startDate,
            endDate: scope.endDate
        )
        #expect(coverage != nil)
        let local = try await store.dailyStats(
            viewerID: viewer,
            startDate: scope.startDate,
            endDate: scope.endDate,
            accountScope: scope.accountScope,
            modeScope: scope.modeScope
        )
        #expect(local.count == 2)
    }

    @Test("Empty month still writes coverage")
    func emptyMonthCoverage() async throws {
        let (url, store) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("viewer-empty")
        let scope = AnalyticsLocalStore.IngestScope(
            startDate: "2026-10-01",
            endDate: "2026-10-31",
            accountScope: AnalyticsScopeKeys.allAccountsQuery,
            modeScope: AnalyticsScopeKeys.allModesQuery
        )
        try await store.ingestCalendarDailyRange(
            viewerID: viewer,
            payload: samplePayload(days: [], revision: 2),
            scope: scope
        )
        let coverage = try await store.coverage(
            viewerID: viewer,
            domain: AnalyticsLocalSchema.domainCalendar,
            accountScope: scope.accountScope,
            modeScope: scope.modeScope,
            startDate: scope.startDate,
            endDate: scope.endDate
        )
        #expect(coverage?.server_revision == 2)
        let local = try await store.dailyStats(
            viewerID: viewer,
            startDate: scope.startDate,
            endDate: scope.endDate,
            accountScope: scope.accountScope,
            modeScope: scope.modeScope
        )
        #expect(local.isEmpty)
    }

    @Test("Missing coverage means unknown")
    func missingCoverage() async throws {
        let (url, store) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("viewer-no-cov")
        let cov = try await store.coverage(
            viewerID: viewer,
            domain: AnalyticsLocalSchema.domainCalendar,
            accountScope: "*",
            modeScope: "*",
            startDate: "2026-11-01",
            endDate: "2026-11-30"
        )
        #expect(cov == nil)
    }

    @Test("Replacement removes stale daily row")
    func replacementRemovesStaleRow() async throws {
        let (url, store) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("viewer-replace")
        let scope = AnalyticsLocalStore.IngestScope(
            startDate: "2026-09-01",
            endDate: "2026-09-30",
            accountScope: AnalyticsScopeKeys.allAccountsQuery,
            modeScope: AnalyticsScopeKeys.allModesQuery
        )
        try await store.ingestCalendarDailyRange(
            viewerID: viewer,
            payload: samplePayload(days: [row(day: "2026-09-10")]),
            scope: scope
        )
        try await store.ingestCalendarDailyRange(
            viewerID: viewer,
            payload: samplePayload(days: [row(day: "2026-09-04")], revision: 6),
            scope: scope
        )
        let local = try await store.dailyStats(
            viewerID: viewer,
            startDate: scope.startDate,
            endDate: scope.endDate,
            accountScope: scope.accountScope,
            modeScope: scope.modeScope
        )
        #expect(local.count == 1)
        #expect(local.first?.calendar_day == "2026-09-04")
    }

    @Test("Replacement respects mode scope")
    func replacementRespectsModeScope() async throws {
        let (url, store) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("viewer-mode")
        let allModes = AnalyticsLocalStore.IngestScope(
            startDate: "2026-09-01",
            endDate: "2026-09-30",
            accountScope: AnalyticsScopeKeys.allAccountsQuery,
            modeScope: AnalyticsScopeKeys.allModesQuery
        )
        var evalRow = row(day: "2026-09-05")
        evalRow.mode_effective = "evaluation"
        try await store.ingestCalendarDailyRange(
            viewerID: viewer,
            payload: samplePayload(days: [row(day: "2026-09-05"), evalRow]),
            scope: allModes
        )
        let liveOnly = AnalyticsLocalStore.IngestScope(
            startDate: "2026-09-01",
            endDate: "2026-09-30",
            accountScope: AnalyticsScopeKeys.allAccountsQuery,
            modeScope: "live"
        )
        try await store.ingestCalendarDailyRange(
            viewerID: viewer,
            payload: samplePayload(days: [row(day: "2026-09-12")], revision: 3),
            scope: liveOnly
        )
        let all = try await store.dailyStats(
            viewerID: viewer,
            startDate: allModes.startDate,
            endDate: allModes.endDate,
            accountScope: allModes.accountScope,
            modeScope: allModes.modeScope
        )
        #expect(all.count == 2)
        #expect(all.contains { $0.mode_effective == "evaluation" && $0.calendar_day == "2026-09-05" })
        #expect(all.contains { $0.mode_effective == "live" && $0.calendar_day == "2026-09-12" })
        #expect(all.contains { $0.mode_effective == "live" && $0.calendar_day == "2026-09-05" } == false)
    }

    @Test("Replacement does not delete outside requested range")
    func replacementRespectsRange() async throws {
        let (url, store) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("viewer-range")
        let september = AnalyticsLocalStore.IngestScope(
            startDate: "2026-09-01",
            endDate: "2026-09-30",
            accountScope: AnalyticsScopeKeys.allAccountsQuery,
            modeScope: AnalyticsScopeKeys.allModesQuery
        )
        let october = AnalyticsLocalStore.IngestScope(
            startDate: "2026-10-01",
            endDate: "2026-10-31",
            accountScope: AnalyticsScopeKeys.allAccountsQuery,
            modeScope: AnalyticsScopeKeys.allModesQuery
        )
        try await store.ingestCalendarDailyRange(
            viewerID: viewer,
            payload: samplePayload(days: [row(day: "2026-09-10")]),
            scope: september
        )
        try await store.ingestCalendarDailyRange(
            viewerID: viewer,
            payload: samplePayload(days: [row(day: "2026-10-05")], revision: 3),
            scope: october
        )
        let sep = try await store.dailyStats(
            viewerID: viewer,
            startDate: september.startDate,
            endDate: september.endDate,
            accountScope: september.accountScope,
            modeScope: september.modeScope
        )
        let oct = try await store.dailyStats(
            viewerID: viewer,
            startDate: october.startDate,
            endDate: october.endDate,
            accountScope: october.accountScope,
            modeScope: october.modeScope
        )
        #expect(sep.count == 1)
        #expect(oct.count == 1)
    }

    @Test("Null account row identity does not collide with account row")
    func nullAccountIdentity() async throws {
        let keyNull = AnalyticsScopeKeys.accountScopeKey(forRowAccountID: nil)
        let keyA = AnalyticsScopeKeys.accountScopeKey(
            forRowAccountID: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        )
        #expect(keyNull != keyA)
        #expect(keyNull == AnalyticsScopeKeys.nullAccountRow)
    }

    @Test("Same identity upserts rather than duplicates")
    func upsertIdentity() async throws {
        let (url, store) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("viewer-upsert")
        let scope = AnalyticsLocalStore.IngestScope(
            startDate: "2026-09-01",
            endDate: "2026-09-30",
            accountScope: AnalyticsScopeKeys.allAccountsQuery,
            modeScope: AnalyticsScopeKeys.allModesQuery
        )
        try await store.ingestCalendarDailyRange(
            viewerID: viewer,
            payload: samplePayload(days: [row(day: "2026-09-04", net: 10)]),
            scope: scope
        )
        try await store.ingestCalendarDailyRange(
            viewerID: viewer,
            payload: samplePayload(days: [row(day: "2026-09-04", net: 99)], revision: 4),
            scope: scope
        )
        let local = try await store.dailyStats(
            viewerID: viewer,
            startDate: scope.startDate,
            endDate: scope.endDate,
            accountScope: scope.accountScope,
            modeScope: scope.modeScope
        )
        #expect(local.count == 1)
        #expect(abs(local.first!.net_pnl - 99) < 0.001)
    }

    @Test("Viewer A cannot read viewer B")
    func viewerIsolation() async throws {
        let (url, store) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let a = ProfileID("viewer-aaaa")
        let b = ProfileID("viewer-bbbb")
        let scope = AnalyticsLocalStore.IngestScope(
            startDate: "2026-09-01",
            endDate: "2026-09-30",
            accountScope: AnalyticsScopeKeys.allAccountsQuery,
            modeScope: AnalyticsScopeKeys.allModesQuery
        )
        try await store.ingestCalendarDailyRange(
            viewerID: a,
            payload: samplePayload(days: [row(day: "2026-09-01")]),
            scope: scope
        )
        let bRows = try await store.dailyStats(
            viewerID: b,
            startDate: scope.startDate,
            endDate: scope.endDate,
            accountScope: scope.accountScope,
            modeScope: scope.modeScope
        )
        #expect(bRows.isEmpty)
    }

    @Test("Clearing viewer A preserves viewer B")
    func clearViewerIsolation() async throws {
        let (url, store) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let a = ProfileID("clear-a")
        let b = ProfileID("clear-b")
        let scope = AnalyticsLocalStore.IngestScope(
            startDate: "2026-09-01",
            endDate: "2026-09-30",
            accountScope: AnalyticsScopeKeys.allAccountsQuery,
            modeScope: AnalyticsScopeKeys.allModesQuery
        )
        try await store.ingestCalendarDailyRange(
            viewerID: a,
            payload: samplePayload(days: [row(day: "2026-09-02")]),
            scope: scope
        )
        try await store.ingestCalendarDailyRange(
            viewerID: b,
            payload: samplePayload(days: [row(day: "2026-09-03")], revision: 2),
            scope: scope
        )
        await store.clearViewer(a)
        let aRows = try await store.dailyStats(
            viewerID: a,
            startDate: scope.startDate,
            endDate: scope.endDate,
            accountScope: scope.accountScope,
            modeScope: scope.modeScope
        )
        let bRows = try await store.dailyStats(
            viewerID: b,
            startDate: scope.startDate,
            endDate: scope.endDate,
            accountScope: scope.accountScope,
            modeScope: scope.modeScope
        )
        #expect(aRows.isEmpty)
        #expect(bRows.count == 1)
    }

    @Test("Revision stored in sync state and coverage")
    func revisionStored() async throws {
        let (url, store) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("viewer-rev")
        let scope = AnalyticsLocalStore.IngestScope(
            startDate: "2026-09-01",
            endDate: "2026-09-30",
            accountScope: AnalyticsScopeKeys.allAccountsQuery,
            modeScope: AnalyticsScopeKeys.allModesQuery
        )
        try await store.ingestCalendarDailyRange(
            viewerID: viewer,
            payload: samplePayload(days: [], revision: 42),
            scope: scope
        )
        let sync = try await store.syncState(viewerID: viewer)
        #expect(sync?.server_revision == 42)
    }

    @Test("Reopening database preserves rows")
    func reopenPreserves() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("analytics-grdb-reopen-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("viewer-reopen")
        let scope = AnalyticsLocalStore.IngestScope(
            startDate: "2026-09-01",
            endDate: "2026-09-30",
            accountScope: AnalyticsScopeKeys.allAccountsQuery,
            modeScope: AnalyticsScopeKeys.allModesQuery
        )
        let store1 = AnalyticsLocalStore(database: AnalyticsDatabase(configuration: .testing(databaseURL: url)))
        try await store1.ingestCalendarDailyRange(
            viewerID: viewer,
            payload: samplePayload(days: [row(day: "2026-09-07")]),
            scope: scope
        )
        let store2 = AnalyticsLocalStore(database: AnalyticsDatabase(configuration: .testing(databaseURL: url)))
        let rows = try await store2.dailyStats(
            viewerID: viewer,
            startDate: scope.startDate,
            endDate: scope.endDate,
            accountScope: scope.accountScope,
            modeScope: scope.modeScope
        )
        #expect(rows.count == 1)
    }

    @Test("Transaction failure does not commit coverage or revision")
    func transactionFailureRollsBack() async throws {
        let (url, store) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("viewer-tx")
        let scope = AnalyticsLocalStore.IngestScope(
            startDate: "2026-09-01",
            endDate: "2026-09-30",
            accountScope: AnalyticsScopeKeys.allAccountsQuery,
            modeScope: AnalyticsScopeKeys.allModesQuery
        )
        try await store.ingestCalendarDailyRange(
            viewerID: viewer,
            payload: samplePayload(days: [row(day: "2026-09-01")], revision: 1),
            scope: scope
        )
        do {
            try await store.ingestCalendarDailyRange(
                viewerID: viewer,
                payload: samplePayload(days: [row(day: "2026-09-09")], revision: 99),
                scope: scope,
                simulateFailureAfterDelete: true
            )
            Issue.record("Expected simulated ingest failure")
        } catch {
            #expect(error.localizedDescription.isEmpty == false)
        }
        let sync = try await store.syncState(viewerID: viewer)
        #expect(sync?.server_revision == 1)
        let local = try await store.dailyStats(
            viewerID: viewer,
            startDate: scope.startDate,
            endDate: scope.endDate,
            accountScope: scope.accountScope,
            modeScope: scope.modeScope
        )
        #expect(local.count == 1)
        #expect(local.first?.calendar_day == "2026-09-01")
    }

    @Test("Numeric ingredients preserve precision")
    func numericPrecision() async throws {
        let (url, store) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("viewer-num")
        let scope = AnalyticsLocalStore.IngestScope(
            startDate: "2026-09-01",
            endDate: "2026-09-30",
            accountScope: AnalyticsScopeKeys.allAccountsQuery,
            modeScope: AnalyticsScopeKeys.allModesQuery
        )
        let day = row(day: "2026-09-08", net: 3063.505)
        try await store.ingestCalendarDailyRange(
            viewerID: viewer,
            payload: samplePayload(days: [day]),
            scope: scope
        )
        let local = try await store.dailyStats(
            viewerID: viewer,
            startDate: scope.startDate,
            endDate: scope.endDate,
            accountScope: scope.accountScope,
            modeScope: scope.modeScope
        )
        #expect(abs((local.first?.net_pnl ?? 0) - 3063.505) < 0.001)
    }
}
