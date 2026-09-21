import Foundation
import Testing
@testable import TradeTraxs

@Suite("Calendar Analytics V2")
struct CalendarAnalyticsV2Tests {
    @Test("Normal calendar: Monday 19:30 ET stays Monday")
    func mondayEveningStaysSameCivilDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = AnalyticsCalendarDay.timeZone
        var comps = DateComponents(calendar: calendar, timeZone: AnalyticsCalendarDay.timeZone)
        comps.year = 2026
        comps.month = 9
        comps.day = 21
        comps.hour = 19
        comps.minute = 30
        let date = try #require(calendar.date(from: comps))

        let normal = AnalyticsCalendarDay.key(for: date)
        let legacy = TradingCalendarDay.key(for: date)
        #expect(normal == "2026-09-21")
        #expect(legacy == "2026-09-22")
    }

    @Test("Month aggregate composes from daily rows")
    func monthComposition() {
        let rows = [
            AnalyticsDailyStatRowV1(
                calendar_day: "2026-09-01",
                account_id: "a1",
                mode_effective: "live",
                trade_count: 2,
                win_count: 1,
                loss_count: 1,
                breakeven_count: 0,
                net_pnl: PostgresFlexibleDouble(100),
                gross_profit: PostgresFlexibleDouble(150),
                gross_loss: PostgresFlexibleDouble(-50)
            ),
            AnalyticsDailyStatRowV1(
                calendar_day: "2026-09-01",
                account_id: "a2",
                mode_effective: "live",
                trade_count: 1,
                win_count: 1,
                loss_count: 0,
                breakeven_count: 0,
                net_pnl: PostgresFlexibleDouble(40),
                gross_profit: PostgresFlexibleDouble(40),
                gross_loss: PostgresFlexibleDouble(0)
            ),
        ]

        let month = CalendarAnalyticsAggregator.buildMonth(
            year: 2026,
            month: 9,
            rows: rows,
            accountFilter: .all
        )
        let day = month.days["2026-09-01"]
        #expect(day?.tradeCount == 3)
        #expect(day?.netPnL == Decimal(140))
        #expect(month.monthSummary.tradeCount == 3)
    }

    @Test("Account filter sums one account bucket")
    func accountFilter() {
        let rows = [
            AnalyticsDailyStatRowV1(
                calendar_day: "2026-09-02",
                account_id: "acct-a",
                mode_effective: "live",
                trade_count: 2,
                win_count: 2,
                loss_count: 0,
                breakeven_count: 0,
                net_pnl: PostgresFlexibleDouble(20),
                gross_profit: PostgresFlexibleDouble(20),
                gross_loss: PostgresFlexibleDouble(0)
            ),
            AnalyticsDailyStatRowV1(
                calendar_day: "2026-09-02",
                account_id: "acct-b",
                mode_effective: "live",
                trade_count: 5,
                win_count: 0,
                loss_count: 5,
                breakeven_count: 0,
                net_pnl: PostgresFlexibleDouble(-50),
                gross_profit: PostgresFlexibleDouble(0),
                gross_loss: PostgresFlexibleDouble(-50)
            ),
        ]
        let month = CalendarAnalyticsAggregator.buildMonth(
            year: 2026,
            month: 9,
            rows: rows,
            accountFilter: .account(TradingAccountID("acct-a"))
        )
        #expect(month.days["2026-09-02"]?.tradeCount == 2)
        #expect(month.days["2026-09-02"]?.netPnL == Decimal(20))
    }

    @Test("Disk cache key isolates mode variant")
    func cacheKeyIsolation() {
        let a = CalendarAnalyticsMonthDiskCache.cacheFileKey(monthKey: "2026-09", modeFilter: nil)
        let b = CalendarAnalyticsMonthDiskCache.cacheFileKey(monthKey: "2026-09", modeFilter: "live")
        #expect(a != b)
    }

    @Test("Civil month bounds are calendar dates not session windows")
    func civilMonthBounds() {
        let bounds = AnalyticsCalendarDay.civilMonthDateBounds(year: 2026, month: 2)
        #expect(bounds?.start == "2026-02-01")
        #expect(bounds?.end == "2026-02-28")
    }
}
