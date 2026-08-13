import Foundation

/// Futures trading-day key matching web Calendar (`lib/formatDate.ts`).
///
/// - Zone: `America/New_York`
/// - Session rolls to the **next** civil day at 18:00 Eastern
/// - Trade time source: **entryAt**, else **exitAt** (web `resolveTradingTimeSourceForKey`)
/// - Trades with neither entry nor exit time are omitted (same as `/calendar`)
///
/// Note: ``PropFirmTradingDay`` prefers exit → entry for prop-firm metrics.
/// Journal Calendar intentionally matches the web Calendar entry-first rule.
nonisolated enum TradingCalendarDay {
    static let timeZone = TimeZone(identifier: "America/New_York") ?? .gmt

    /// `YYYY-MM-DD` trading day for a trade, or `nil` when the trade cannot be bucketed.
    static func key(for trade: Trade) -> String? {
        // Web calendar: entry_time || exit_time — never created_at alone.
        // Domain `entryAt` is non-optional (mapper requires it); still prefer entry then exit.
        guard let date = resolveInstant(entryAt: trade.entryAt, exitAt: trade.exitAt) else {
            return nil
        }
        return key(for: date)
    }

    /// Prefer entry, then exit — mirrors web `trade.entry_time || trade.exit_time`.
    static func resolveInstant(entryAt: Date?, exitAt: Date?) -> Date? {
        entryAt ?? exitAt
    }

    static func key(for date: Date) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var comps = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        guard let hour = comps.hour else { return nil }
        if hour >= 18 {
            guard
                let dayStart = calendar.date(from: DateComponents(
                    calendar: calendar,
                    timeZone: timeZone,
                    year: comps.year,
                    month: comps.month,
                    day: comps.day
                )),
                let next = calendar.date(byAdding: .day, value: 1, to: dayStart)
            else { return nil }
            comps = calendar.dateComponents([.year, .month, .day], from: next)
        }
        guard let y = comps.year, let m = comps.month, let d = comps.day else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// Parses `YYYY-MM-DD` into year/month/day components.
    static func components(from key: String) -> (year: Int, month: Int, day: Int)? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return (parts[0], parts[1], parts[2])
    }

    /// Inclusive UTC-ish fetch window covering a trading month (padded for 18:00 rollover).
    ///
    /// July 31 18:00 ET → Aug 1 trading day; Aug 31 17:59 ET still August.
    static func fetchWindow(year: Int, month: Int) -> DateIntervalValue? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard
            let monthStart = calendar.date(from: DateComponents(
                calendar: calendar,
                timeZone: timeZone,
                year: year,
                month: month,
                day: 1,
                hour: 0
            )),
            let previousDay = calendar.date(byAdding: .day, value: -1, to: monthStart),
            let windowStart = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: previousDay),
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart),
            let lastTradingDayEnd = calendar.date(
                byAdding: .second,
                value: -1,
                to: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: nextMonth) ?? nextMonth
            )
        else { return nil }
        return DateIntervalValue(start: windowStart, end: lastTradingDayEnd)
    }

    static func monthTitle(year: Int, month: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return String(format: "%04d-%02d", year, month)
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: date)
    }

    static func displayDate(from key: String) -> String {
        guard let comps = components(from: key) else { return key }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = calendar.date(from: DateComponents(
            year: comps.year,
            month: comps.month,
            day: comps.day,
            hour: 12
        )) else { return key }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d, yyyy")
        return formatter.string(from: date)
    }

    static func todayKey(now: Date = Date()) -> String? {
        key(for: now)
    }
}
