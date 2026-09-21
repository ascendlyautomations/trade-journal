import Foundation
import Testing
@testable import TradeTraxs

struct CalendarAnalyticsGRDBCutoverTests {
    private func makeStore() throws -> (URL, AnalyticsLocalStore) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("calendar-grdb-cutover-\(UUID().uuidString).sqlite")
        let db = AnalyticsDatabase(configuration: .testing(databaseURL: url))
        return (url, AnalyticsLocalStore(database: db))
    }

    @Test("Presentation read prefers covered revision without server revision")
    func presentationReadAvailable() async throws {
        let (url, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("cutover-viewer")
        let payload = AnalyticsDailyRangeBootstrapV1(
            revision: PostgresFlexibleDouble(42),
            state_updated_at: "2026-09-21T12:00:00.000Z",
            start: "2026-09-01",
            end: "2026-09-30",
            account_id: nil,
            mode: nil,
            days: [],
            summary: AnalyticsDailyRangeSummaryV1(
                trade_count: 0,
                win_count: 0,
                loss_count: 0,
                breakeven_count: 0,
                net_pnl: PostgresFlexibleDouble(0),
                gross_profit: PostgresFlexibleDouble(0),
                gross_loss: PostgresFlexibleDouble(0)
            )
        )
        let scope = AnalyticsLocalStore.IngestScope(
            startDate: "2026-09-01",
            endDate: "2026-09-30",
            accountScope: AnalyticsScopeKeys.allAccountsQuery,
            modeScope: AnalyticsScopeKeys.allModesQuery
        )
        try await store.ingestCalendarDailyRange(viewerID: viewer, payload: payload, scope: scope)

        let read = try await store.readCalendarRangeForPresentation(
            viewerID: viewer,
            startDate: "2026-09-01",
            endDate: "2026-09-30",
            queryAccountID: nil,
            queryMode: nil
        )
        #expect(read.canRenderLocally)
        #expect(read.state == .available)
        #expect(read.effectiveRevision == 42)
    }

    @Test("Account-scoped coverage does not satisfy all-account presentation read")
    func restrictiveAccountCoverage() async throws {
        let (url, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("cutover-scope")
        let account = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        let payload = AnalyticsDailyRangeBootstrapV1(
            revision: PostgresFlexibleDouble(1),
            state_updated_at: "2026-09-21T12:00:00.000Z",
            start: "2026-09-01",
            end: "2026-09-30",
            account_id: account,
            mode: nil,
            days: [
                AnalyticsDailyStatRowV1(
                    calendar_day: "2026-09-01",
                    account_id: account,
                    mode_effective: "live",
                    trade_count: 1,
                    win_count: 1,
                    loss_count: 0,
                    breakeven_count: 0,
                    net_pnl: PostgresFlexibleDouble(10),
                    gross_profit: PostgresFlexibleDouble(10),
                    gross_loss: PostgresFlexibleDouble(0),
                    long_count: 0,
                    long_pnl: PostgresFlexibleDouble(0),
                    short_count: 0,
                    short_pnl: PostgresFlexibleDouble(0),
                    sum_rr: PostgresFlexibleDouble(0),
                    rr_count: 0,
                    sum_hold_seconds: PostgresFlexibleDouble(0),
                    hold_count: 0,
                    largest_win: PostgresFlexibleDouble(10),
                    largest_loss: nil
                ),
            ],
            summary: AnalyticsDailyRangeSummaryV1(
                trade_count: 1,
                win_count: 1,
                loss_count: 0,
                breakeven_count: 0,
                net_pnl: PostgresFlexibleDouble(10),
                gross_profit: PostgresFlexibleDouble(10),
                gross_loss: PostgresFlexibleDouble(0)
            )
        )
        let scope = AnalyticsLocalStore.IngestScope(
            startDate: "2026-09-01",
            endDate: "2026-09-30",
            accountScope: AnalyticsScopeKeys.accountScopeKey(forQueryAccountID: account),
            modeScope: AnalyticsScopeKeys.allModesQuery
        )
        try await store.ingestCalendarDailyRange(viewerID: viewer, payload: payload, scope: scope)

        let allAccountsRead = try await store.readCalendarRangeForPresentation(
            viewerID: viewer,
            startDate: "2026-09-01",
            endDate: "2026-09-30",
            queryAccountID: nil,
            queryMode: nil
        )
        #expect(!allAccountsRead.canRenderLocally)
        #expect(allAccountsRead.state == .missing)
    }

    @Test("GRDB loader builds month from local rows")
    func loaderMonthRender() async throws {
        let (url, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewer = ProfileID("loader-viewer")
        let day = AnalyticsDailyStatRowV1(
            calendar_day: "2026-09-15",
            account_id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            mode_effective: "live",
            trade_count: 2,
            win_count: 2,
            loss_count: 0,
            breakeven_count: 0,
            net_pnl: PostgresFlexibleDouble(20),
            gross_profit: PostgresFlexibleDouble(20),
            gross_loss: PostgresFlexibleDouble(0),
            long_count: 0,
            long_pnl: PostgresFlexibleDouble(0),
            short_count: 0,
            short_pnl: PostgresFlexibleDouble(0),
            sum_rr: PostgresFlexibleDouble(0),
            rr_count: 0,
            sum_hold_seconds: PostgresFlexibleDouble(0),
            hold_count: 0,
            largest_win: PostgresFlexibleDouble(20),
            largest_loss: nil
        )
        let payload = AnalyticsDailyRangeBootstrapV1(
            revision: PostgresFlexibleDouble(5),
            state_updated_at: "2026-09-21T12:00:00.000Z",
            start: "2026-09-01",
            end: "2026-09-30",
            account_id: nil,
            mode: nil,
            days: [day],
            summary: AnalyticsDailyRangeSummaryV1(
                trade_count: 2,
                win_count: 2,
                loss_count: 0,
                breakeven_count: 0,
                net_pnl: PostgresFlexibleDouble(20),
                gross_profit: PostgresFlexibleDouble(20),
                gross_loss: PostgresFlexibleDouble(0)
            )
        )
        try await store.ingestCalendarDailyRange(
            viewerID: viewer,
            payload: payload,
            scope: AnalyticsLocalStore.IngestScope(
                startDate: "2026-09-01",
                endDate: "2026-09-30",
                accountScope: AnalyticsScopeKeys.allAccountsQuery,
                modeScope: AnalyticsScopeKeys.allModesQuery
            )
        )

        let month = await CalendarAnalyticsGRDBLoader.loadMonth(
            viewerID: viewer,
            year: 2026,
            month: 9,
            queryAccountID: nil,
            queryMode: nil,
            store: store
        )
        #expect(month.canRenderMonth)
        let filtered = CalendarAnalyticsAggregator.filteredRows(
            month.wireRows,
            accountFilter: .account(TradingAccountID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")),
            modeFilter: nil
        )
        #expect(filtered.count == 1)
        #expect(filtered.first?.trade_count == 2)
    }

    @Test("calendarAnalyticsGRDB flag OFF keeps JSON path viable")
    func grdbFlagRollback() {
        BackendV2FeatureFlags.resetFlagsForTests()
        BackendV2FeatureFlags.setFlagForTests(.calendarAnalyticsV2, enabled: true)
        BackendV2FeatureFlags.setFlagForTests(.calendarAnalyticsGRDB, enabled: false)
        #expect(BackendV2FeatureFlags.isEnabled(.calendarAnalyticsV2))
        #expect(!BackendV2FeatureFlags.isEnabled(.calendarAnalyticsGRDB))
        BackendV2FeatureFlags.resetFlagsForTests()
    }
}
