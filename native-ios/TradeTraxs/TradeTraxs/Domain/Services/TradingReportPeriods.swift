import Foundation

/// Web `lib/tradingReports/tradingReportPeriods.ts` — calendar week (Mon–Sun) and month windows.
nonisolated enum TradingReportPeriods {
    struct Bounds: Hashable, Sendable {
        var key: TradingReportPeriodKey
        var kind: TradingReportKind
        var start: Date
        var end: Date
    }

    static func bounds(
        for key: TradingReportPeriodKey,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bounds {
        let today = calendar.startOfDay(for: now)

        switch key {
        case .weeklyThis, .weeklyLast:
            var monday = mondayOfWeek(containing: today, calendar: calendar)
            if key == .weeklyLast {
                monday = calendar.date(byAdding: .day, value: -7, to: monday) ?? monday
            }
            let sunday = endOfDay(
                calendar.date(byAdding: .day, value: 6, to: monday) ?? monday,
                calendar: calendar
            )
            let end = key == .weeklyThis ? endOfDay(now, calendar: calendar) : sunday
            return Bounds(key: key, kind: .weekly, start: monday, end: end)

        case .monthlyThis:
            let comps = calendar.dateComponents([.year, .month], from: today)
            let start = calendar.date(from: DateComponents(
                year: comps.year,
                month: comps.month,
                day: 1
            )) ?? today
            return Bounds(
                key: key,
                kind: .monthly,
                start: calendar.startOfDay(for: start),
                end: endOfDay(now, calendar: calendar)
            )

        case .monthlyLast:
            let comps = calendar.dateComponents([.year, .month], from: today)
            let thisMonthStart = calendar.date(from: DateComponents(
                year: comps.year,
                month: comps.month,
                day: 1
            )) ?? today
            let start = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) ?? thisMonthStart
            let endDay = calendar.date(byAdding: .day, value: -1, to: thisMonthStart) ?? start
            return Bounds(
                key: key,
                kind: .monthly,
                start: calendar.startOfDay(for: start),
                end: endOfDay(endDay, calendar: calendar)
            )
        }
    }

    static func dateRangeLabel(start: Date, end: Date, kind: TradingReportKind) -> String {
        let calendar = Calendar.current
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
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? now
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
    static func monthBounds(
        year: Int,
        month: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bounds {
        let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? now
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
        var years = Set<Int>()
        for trade in trades where trade.mode != .backtest {
            years.insert(calendar.component(.year, from: trade.entryAt))
        }
        return years.sorted(by: >)
    }

    static func yearDateRangeLabel(
        year: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let bounds = yearBounds(year: year, now: now, calendar: calendar)
        let currentYear = calendar.component(.year, from: now)
        if year == currentYear {
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
            let startLabel = formatter.string(from: bounds.start)
            let endLabel = Self.medium.string(from: bounds.end)
            return "\(startLabel) – \(endLabel)"
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
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            return "week:\(formatter.string(from: bounds.start))"
        case .monthly:
            let comps = Calendar.current.dateComponents([.year, .month], from: bounds.start)
            let month = String(format: "%02d", comps.month ?? 1)
            return "month:\(comps.year ?? 0)-\(month)"
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
        formatter.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        return formatter
    }()

    private static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    private static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return formatter
    }()
}
