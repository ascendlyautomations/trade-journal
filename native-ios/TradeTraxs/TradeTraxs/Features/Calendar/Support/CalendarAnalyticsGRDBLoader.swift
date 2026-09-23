import Foundation

/// Calendar V2 GRDB-first local read (Phase 5E — no network).
nonisolated enum CalendarAnalyticsGRDBLoader {
    struct MonthPresentation: Sendable {
        var readState: AnalyticsLocalReadState
        var revision: Int64?
        var wireRows: [AnalyticsDailyStatRowV1]
        /// Full month coverage at `revision` — safe to render (including known-zero).
        var canRenderMonth: Bool
        var elapsedMs: Int
    }

    static func loadMonth(
        viewerID: ProfileID,
        year: Int,
        month: Int,
        queryAccountID: String?,
        queryMode: String?,
        store: AnalyticsLocalStore? = nil
    ) async -> MonthPresentation {
        let store = store ?? AnalyticsLocalStore.sharedStore()
        let started = Date()
        guard let bounds = AnalyticsCalendarDay.civilMonthDateBounds(year: year, month: month) else {
            return emptyPresentation(elapsedMs: elapsed(started), state: .missing)
        }
        do {
            let read = try await store.readCalendarRangeForPresentation(
                viewerID: viewerID,
                startDate: bounds.start,
                endDate: bounds.end,
                queryAccountID: queryAccountID,
                queryMode: queryMode
            )
            let elapsed = elapsed(started)
            return MonthPresentation(
                readState: read.state,
                revision: read.effectiveRevision,
                wireRows: read.wireRows,
                canRenderMonth: read.canRenderLocally,
                elapsedMs: elapsed
            )
        } catch {
            return emptyPresentation(elapsedMs: elapsed(started), state: .missing)
        }
    }

    static func loadYear(
        viewerID: ProfileID,
        year: Int,
        queryAccountID: String?,
        queryMode: String?,
        store: AnalyticsLocalStore? = nil
    ) async -> MonthPresentation {
        let store = store ?? AnalyticsLocalStore.sharedStore()
        let started = Date()
        guard let bounds = AnalyticsCalendarDay.civilYearDateBounds(year: year) else {
            return emptyPresentation(elapsedMs: elapsed(started), state: .missing)
        }
        do {
            let read = try await store.readCalendarRangeForPresentation(
                viewerID: viewerID,
                startDate: bounds.start,
                endDate: bounds.end,
                queryAccountID: queryAccountID,
                queryMode: queryMode
            )
            return MonthPresentation(
                readState: read.state,
                revision: read.effectiveRevision,
                wireRows: read.wireRows,
                canRenderMonth: read.canRenderLocally,
                elapsedMs: elapsed(started)
            )
        } catch {
            return emptyPresentation(elapsedMs: elapsed(started), state: .missing)
        }
    }

    static func syntheticPayload(
        rows: [AnalyticsDailyStatRowV1],
        revision: Int64,
        start: String,
        end: String
    ) -> AnalyticsDailyRangeBootstrapV1 {
        let tradeCount = rows.reduce(0) { $0 + $1.trade_count }
        let winCount = rows.reduce(0) { $0 + $1.win_count }
        let lossCount = rows.reduce(0) { $0 + $1.loss_count }
        let beCount = rows.reduce(0) { $0 + $1.breakeven_count }
        let net = rows.reduce(0.0) { $0 + ($1.net_pnl.value ?? 0) }
        let gp = rows.reduce(0.0) { $0 + ($1.gross_profit.value ?? 0) }
        let gl = rows.reduce(0.0) { $0 + ($1.gross_loss.value ?? 0) }
        return AnalyticsDailyRangeBootstrapV1(
            revision: PostgresFlexibleDouble(Double(revision)),
            state_updated_at: ISO8601DateFormatter().string(from: Date()),
            start: start,
            end: end,
            account_id: nil,
            mode: nil,
            days: rows,
            summary: AnalyticsDailyRangeSummaryV1(
                trade_count: tradeCount,
                win_count: winCount,
                loss_count: lossCount,
                breakeven_count: beCount,
                net_pnl: PostgresFlexibleDouble(net),
                gross_profit: PostgresFlexibleDouble(gp),
                gross_loss: PostgresFlexibleDouble(gl)
            )
        )
    }

    private static func emptyPresentation(
        elapsedMs: Int,
        state: AnalyticsLocalReadState
    ) -> MonthPresentation {
        MonthPresentation(
            readState: state,
            revision: nil,
            wireRows: [],
            canRenderMonth: false,
            elapsedMs: elapsedMs
        )
    }

    private static func elapsed(_ start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }
}
