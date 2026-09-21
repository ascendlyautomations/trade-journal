import Foundation

/// Normal TradeTraxs calendar day — mirrors SQL `analytics_calendar_day` (ET civil, no 18:00 rollover).
///
/// Used for Calendar V2 month boundaries and display keys. Legacy ``TradingCalendarDay`` remains for rollback.
nonisolated enum AnalyticsCalendarDay {
    static let timeZone = TimeZone(identifier: "America/New_York") ?? .gmt

    static func key(for trade: Trade) -> String? {
        guard let date = TradingCalendarDay.resolveInstant(entryAt: trade.entryAt, exitAt: trade.exitAt)
            ?? Optional(trade.createdAt)
        else { return nil }
        return key(for: date)
    }

    static func key(for date: Date) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        guard let y = comps.year, let m = comps.month, let d = comps.day else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func components(from key: String) -> (year: Int, month: Int, day: Int)? {
        TradingCalendarDay.components(from: key)
    }

    /// Inclusive normal calendar month bounds as `YYYY-MM-DD` (ET semantics via server for authoritative data).
    static func civilMonthDateBounds(year: Int, month: Int) -> (start: String, end: String)? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard
            let monthStart = calendar.date(from: DateComponents(
                calendar: calendar,
                timeZone: timeZone,
                year: year,
                month: month,
                day: 1
            )),
            let range = calendar.range(of: .day, in: .month, for: monthStart)
        else { return nil }
        let lastDay = range.count
        let start = String(format: "%04d-%02d-%02d", year, month, 1)
        let end = String(format: "%04d-%02d-%02d", year, month, lastDay)
        return (start, end)
    }

    static func civilYearDateBounds(year: Int) -> (start: String, end: String)? {
        guard let jan = civilMonthDateBounds(year: year, month: 1),
              let dec = civilMonthDateBounds(year: year, month: 12)
        else { return nil }
        return (jan.start, dec.end)
    }

    static func todayKey(now: Date = Date()) -> String? {
        key(for: now)
    }

    static func monthTitle(year: Int, month: Int) -> String {
        TradingCalendarDay.monthTitle(year: year, month: month)
    }

    static func monthAbbreviation(year: Int, month: Int) -> String {
        TradingCalendarDay.monthAbbreviation(year: year, month: month)
    }

    static func displayDate(from key: String) -> String {
        TradingCalendarDay.displayDate(from: key)
    }
}
