import Foundation

nonisolated enum CalendarAnalyticsDailyRangeReason: String, Sendable {
    case monthLoad = "monthLoad"
    case monthReconcile = "monthReconcile"
    case yearOverview = "yearOverview"
    case grdbBackgroundFreshness = "grdbBackgroundFreshness"
}

#if DEBUG
nonisolated enum CalendarAnalyticsV2Probe {
    static func logDailyRange(
        reason: CalendarAnalyticsDailyRangeReason,
        startDate: String,
        endDate: String,
        monthKey: String?,
        account: String,
        mode: String?,
        source: String,
        revision: Int64,
        dailyRows: Int,
        payloadBytes: Int?,
        elapsedMs: Int?
    ) {
        let bytes = payloadBytes.map { "\($0)" } ?? "-"
        let ms = elapsedMs.map { "\($0)" } ?? "-"
        let modeLabel = mode ?? "all"
        let month = monthKey ?? "-"
        let range = monthKey ?? "\(startDate)...\(endDate)"
        print(
            """
            [CalendarV2] reason=\(reason.rawValue) startDate=\(startDate) endDate=\(endDate) \
            range=\(range) month=\(month) account=\(account) mode=\(modeLabel) source=\(source) \
            revision=\(revision) dailyRows=\(dailyRows) payloadBytes=\(bytes) elapsedMs=\(ms)
            """
        )
    }

    static func logMonth(
        source: String,
        month: String,
        account: String,
        mode: String?,
        revision: Int64,
        dailyRows: Int,
        payloadBytes: Int?,
        elapsedMs: Int,
        stale: Bool,
        reconciled: Bool,
        reason: CalendarAnalyticsDailyRangeReason = .monthLoad,
        startDate: String? = nil,
        endDate: String? = nil
    ) {
        logDailyRange(
            reason: reason,
            startDate: startDate ?? month,
            endDate: endDate ?? month,
            monthKey: month,
            account: account,
            mode: mode,
            source: source,
            revision: revision,
            dailyRows: dailyRows,
            payloadBytes: payloadBytes,
            elapsedMs: elapsedMs
        )
        if stale || reconciled {
            print(
                "[CalendarV2] monthMeta stale=\(stale) reconciled=\(reconciled)"
            )
        }
    }

    static func logDay(
        date: String,
        aggregateCount: Int,
        summaryCount: Int,
        aggregatePnL: Decimal,
        summaryPnL: Decimal,
        parity: Bool,
        source: String,
        payloadBytes: Int?,
        elapsedMs: Int?,
        rpc: String = "rpc_v1_analytics_calendar_day_trades"
    ) {
        let bytes = payloadBytes.map { "\($0)" } ?? "-"
        let ms = elapsedMs.map { "\($0)" } ?? "-"
        print(
            """
            [CalendarDay] rpc=\(rpc) date=\(date) aggregateCount=\(aggregateCount) \
            summaryCount=\(summaryCount) aggregatePnL=\(aggregatePnL) summaryPnL=\(summaryPnL) \
            parity=\(parity) source=\(source) bytes=\(bytes) elapsedMs=\(ms)
            """
        )
        if !parity {
            print("[CalendarDay] PARITY MISMATCH day=\(date)")
        }
    }

    static func logDayFetchStarted(date: String, account: String) {
        print(
            "[CalendarDay] fetching rpc_v1_analytics_calendar_day_trades date=\(date) account=\(account)"
        )
    }
}
#endif
