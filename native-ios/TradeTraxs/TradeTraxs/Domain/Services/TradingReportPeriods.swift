import Foundation

/// Web `lib/tradingReports/tradingReportPeriods.ts` — calendar week (Mon–Sun) and month windows.
nonisolated enum TradingReportPeriods {
    struct Bounds: Hashable, Sendable {
        var key: TradingReportPeriodKey
        var kind: TradingReportKind
        var start: Date
        var end: Date
    }

    static let eastern: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return calendar
    }()

    static func bounds(
        for key: TradingReportPeriodKey,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bounds {
        _ = calendar
        let eastern = Self.eastern
        let today = eastern.startOfDay(for: now)

        switch key {
        case .weeklyThis, .weeklyLast:
            var monday = mondayOfWeek(containing: today, calendar: eastern)
            if key == .weeklyLast {
                monday = eastern.date(byAdding: .day, value: -7, to: monday) ?? monday
            }
            let sunday = eastern.date(byAdding: .day, value: 6, to: monday) ?? monday
            let naturalEnd = endOfDay(sunday, calendar: eastern)
            let end = key == .weeklyThis ? min(endOfDay(now, calendar: eastern), naturalEnd) : naturalEnd
            return Bounds(key: key, kind: .weekly, start: monday, end: end)

        case .monthlyThis:
            let comps = eastern.dateComponents([.year, .month], from: today)
            let start = eastern.date(from: DateComponents(
                calendar: eastern,
                timeZone: eastern.timeZone,
                year: comps.year,
                month: comps.month,
                day: 1
            )) ?? today
            let nextMonth = eastern.date(byAdding: .month, value: 1, to: start) ?? start
            let lastDay = eastern.date(byAdding: .day, value: -1, to: nextMonth) ?? start
            let naturalEnd = endOfDay(lastDay, calendar: eastern)
            return Bounds(
                key: key,
                kind: .monthly,
                start: eastern.startOfDay(for: start),
                end: min(endOfDay(now, calendar: eastern), naturalEnd)
            )

        case .monthlyLast:
            let comps = eastern.dateComponents([.year, .month], from: today)
            let thisMonthStart = eastern.date(from: DateComponents(
                calendar: eastern,
                timeZone: eastern.timeZone,
                year: comps.year,
                month: comps.month,
                day: 1
            )) ?? today
            let start = eastern.date(byAdding: .month, value: -1, to: thisMonthStart) ?? thisMonthStart
            let endDay = eastern.date(byAdding: .day, value: -1, to: thisMonthStart) ?? start
            return Bounds(
                key: key,
                kind: .monthly,
                start: eastern.startOfDay(for: start),
                end: endOfDay(endDay, calendar: eastern)
            )
        }
    }

    /// Monday–Sunday for `week:YYYY-MM-DD`. In-progress weeks end today.
    static func bounds(forWeekStarting mondayKey: String, now: Date = Date()) -> Bounds? {
        guard let ref = TradingReportWeekRef.parse(reportID: ReportID("week:\(mondayKey)")) else {
            return nil
        }
        let calendar = eastern
        let parts = ref.mondayKey.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              let monday = calendar.date(from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day
              ))
        else { return nil }
        let mondayStart = calendar.startOfDay(for: monday)
        let sunday = calendar.date(byAdding: .day, value: 6, to: mondayStart) ?? mondayStart
        let naturalEnd = endOfDay(sunday, calendar: calendar)
        let todayKey = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: now)
        let sundayKey = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: sunday)
        let inProgress = todayKey >= ref.mondayKey && todayKey < sundayKey
        return Bounds(
            key: inProgress ? .weeklyThis : .weeklyLast,
            kind: .weekly,
            start: mondayStart,
            end: inProgress ? min(endOfDay(now, calendar: calendar), naturalEnd) : naturalEnd
        )
    }

    static func dateRangeLabel(start: Date, end: Date, kind: TradingReportKind) -> String {
        let calendar = eastern
        if calendar.isDate(start, inSameDayAs: end) {
            return Self.medium.string(from: start)
        }

        if kind == .monthly, calendar.component(.day, from: start) == 1 {
            let monthEnd = calendar.date(
                byAdding: DateComponents(month: 1, day: -1),
                to: calendar.startOfDay(for: start)
            )
            if let monthEnd, calendar.isDate(end, inSameDayAs: monthEnd) {
                return Self.monthYear.string(from: start)
            }
        }

        let startYear = calendar.component(.year, from: start)
        let endYear = calendar.component(.year, from: end)
        let startLabel: String
        if startYear != endYear {
            startLabel = Self.medium.string(from: start)
        } else {
            startLabel = Self.monthDay.string(from: start)
        }
        let endLabel = Self.medium.string(from: end)
        return "\(startLabel) – \(endLabel)"
    }

    /// Calendar year window — Jan 1 through Dec 31, or through today for the current year.
    static func yearBounds(
        year: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bounds {
        _ = calendar
        let calendar = eastern
        let start = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: 1,
            day: 1
        )) ?? now
        let startDay = calendar.startOfDay(for: start)
        let currentYear = calendar.component(.year, from: now)
        let end: Date
        if year == currentYear {
            end = endOfDay(now, calendar: calendar)
        } else if year < currentYear {
            let nextYearStart = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? start
            let lastDay = calendar.date(byAdding: .day, value: -1, to: nextYearStart) ?? start
            end = endOfDay(lastDay, calendar: calendar)
        } else {
            end = endOfDay(start, calendar: calendar)
        }
        return Bounds(key: .monthlyThis, kind: .monthly, start: startDay, end: end)
    }

    /// Single calendar month — full month for past years; current month ends today.
    static func customBounds(interval: DateInterval) -> Bounds {
        let calendar = eastern
        let normalized = DashboardScopeFilterSupport.normalizedCustomInterval(
            start: interval.start,
            end: interval.end,
            calendar: calendar
        )
        return Bounds(
            key: .monthlyThis,
            kind: .custom,
            start: normalized.start,
            end: normalized.end
        )
    }

    /// Bounds for the Quick Select month — ends today when the month is in progress.
    static func selectedMonthBounds(
        year: Int,
        month: Int,
        now: Date = Date()
    ) -> Bounds {
        monthBounds(year: year, month: month, now: now)
    }

    static func monthBounds(
        year: Int,
        month: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bounds {
        _ = calendar
        let calendar = eastern
        let start = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: 1
        )) ?? now
        let startDay = calendar.startOfDay(for: start)
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        let end: Date
        if year == currentYear, month == currentMonth {
            end = endOfDay(now, calendar: calendar)
        } else {
            let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: startDay) ?? startDay
            let lastDay = calendar.date(byAdding: .day, value: -1, to: nextMonthStart) ?? startDay
            end = endOfDay(lastDay, calendar: calendar)
        }
        return Bounds(key: .monthlyThis, kind: .monthly, start: startDay, end: end)
    }

    /// Years that contain at least one non-backtest trade (newest first).
    static func availableYears(
        from trades: [Trade],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Int] {
        _ = calendar
        _ = now
        var years = Set<Int>()
        for trade in trades where trade.mode != .backtest {
            let key = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: trade)
            if let year = Int(key.prefix(4)) { years.insert(year) }
        }
        return years.sorted(by: >)
    }

    static func yearDateRangeLabel(
        year: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        _ = calendar
        let bounds = yearBounds(year: year, now: now)
        let currentYear = eastern.component(.year, from: now)
        if year == currentYear {
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.timeZone = eastern.timeZone
            formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
            let startLabel = formatter.string(from: bounds.start)
            let endLabel = Self.medium.string(from: bounds.end)
            let today = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: now)
            let partial = today.hasSuffix("-12-31") ? "" : " (partial)"
            return "\(startLabel) – \(endLabel)\(partial)"
        }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("yyyy")
        return formatter.string(from: bounds.start)
    }

    /// Web `tradingReportPeriodId` for notify dedupe.
    static func periodID(for key: TradingReportPeriodKey, now: Date = Date()) -> String {
        let bounds = bounds(for: key, now: now)
        switch bounds.kind {
        case .weekly:
            return "week:\(TraderPsychologyAnalyticsFoundation.tradeDateKey(for: bounds.start))"
        case .monthly:
            let key = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: bounds.start)
            return "month:\(key.prefix(7))"
        case .custom:
            let start = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: bounds.start)
            let end = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: bounds.end)
            return "custom:\(start):\(end)"
        }
    }

    // MARK: - Helpers

    private static func mondayOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start) // 1 = Sunday
        let diff = weekday == 1 ? -6 : 1 - weekday
        return calendar.date(byAdding: .day, value: diff, to: start) ?? start
    }

    private static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        guard let next = calendar.date(byAdding: .day, value: 1, to: start) else { return date }
        return next.addingTimeInterval(-0.001)
    }

    private static let medium: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        return formatter
    }()

    private static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    private static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return formatter
    }()
}
