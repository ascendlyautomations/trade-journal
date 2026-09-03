import Foundation

/// Period bounds and historical catalog for psychology reports.
nonisolated enum PsychologyReportPeriods {
    struct Bounds: Hashable, Sendable {
        var ref: PsychologyReportPeriodRef
        var start: Date
        var end: Date
        var dateRangeLabel: String
    }

    static func bounds(for ref: PsychologyReportPeriodRef, now: Date = Date()) -> Bounds {
        if ref.template.isPeriodic {
            return periodicBounds(for: ref, now: now)
        }
        return rollingBounds(for: ref.template, now: now)
    }

    static func availableCatalog(
        trades: [Trade],
        now: Date = Date(),
        maxWeekly: Int = 12,
        maxMonthly: Int = 6
    ) -> [PsychologyReportPeriodRef] {
        var refs: [PsychologyReportPeriodRef] = []

        for template in PsychologyReportTemplate.allCases where !template.isPeriodic {
            refs.append(PsychologyReportPeriodRef(template: template, periodID: "rolling:90d"))
        }

        guard let earliest = earliestTradeDate(trades) else {
            refs.insert(contentsOf: defaultPeriodicRefs(now: now), at: 0)
            return refs
        }

        refs.insert(contentsOf: weeklyRefs(from: earliest, now: now, limit: maxWeekly), at: 0)
        refs.insert(contentsOf: monthlyRefs(from: earliest, now: now, limit: maxMonthly), at: 0)
        return refs
    }

    static func weeklyRefs(from earliest: Date, now: Date, limit: Int) -> [PsychologyReportPeriodRef] {
        let calendar = Calendar.current
        var monday = mondayOfWeek(containing: now, calendar: calendar)
        var refs: [PsychologyReportPeriodRef] = []
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        for _ in 0..<limit {
            if monday < calendar.startOfDay(for: earliest) { break }
            let id = "week:\(formatter.string(from: monday))"
            refs.append(PsychologyReportPeriodRef(template: .weekly, periodID: id))
            guard let prev = calendar.date(byAdding: .day, value: -7, to: monday) else { break }
            monday = prev
        }
        return refs
    }

    static func monthlyRefs(from earliest: Date, now: Date, limit: Int) -> [PsychologyReportPeriodRef] {
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month], from: now)
        var refs: [PsychologyReportPeriodRef] = []

        for _ in 0..<limit {
            guard let year = comps.year, let month = comps.month else { break }
            let id = String(format: "month:%04d-%02d", year, month)
            refs.append(PsychologyReportPeriodRef(template: .monthly, periodID: id))
            guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  start >= calendar.startOfDay(for: earliest)
            else { break }
            guard let prev = calendar.date(byAdding: .month, value: -1, to: start) else { break }
            comps = calendar.dateComponents([.year, .month], from: prev)
        }
        return refs
    }

    private static func defaultPeriodicRefs(now: Date) -> [PsychologyReportPeriodRef] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let monday = mondayOfWeek(containing: now, calendar: .current)
        let comps = Calendar.current.dateComponents([.year, .month], from: now)
        let monthID = String(format: "month:%04d-%02d", comps.year ?? 2026, comps.month ?? 1)
        return [
            PsychologyReportPeriodRef(template: .weekly, periodID: "week:\(formatter.string(from: monday))"),
            PsychologyReportPeriodRef(template: .monthly, periodID: monthID),
        ]
    }

    private static func periodicBounds(for ref: PsychologyReportPeriodRef, now: Date) -> Bounds {
        let calendar = Calendar.current
        if ref.periodID.hasPrefix("week:") {
            let dateStr = String(ref.periodID.dropFirst("week:".count))
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            let monday = formatter.date(from: dateStr) ?? now
            let sunday = calendar.date(byAdding: .day, value: 6, to: monday) ?? monday
            let end = min(endOfDay(sunday, calendar: calendar), endOfDay(now, calendar: calendar))
            let label = TradingReportPeriods.dateRangeLabel(start: monday, end: end, kind: .weekly)
            return Bounds(ref: ref, start: monday, end: end, dateRangeLabel: label)
        }

        if ref.periodID.hasPrefix("month:") {
            let parts = ref.periodID.dropFirst("month:".count).split(separator: "-")
            let year = Int(parts.first ?? "2026") ?? 2026
            let month = Int(parts.dropFirst().first ?? "1") ?? 1
            let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? now
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            let endDay = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? start
            let isCurrentMonth = calendar.isDate(start, equalTo: now, toGranularity: .month)
            let end = isCurrentMonth ? endOfDay(now, calendar: calendar) : endOfDay(endDay, calendar: calendar)
            let label = TradingReportPeriods.dateRangeLabel(start: start, end: end, kind: .monthly)
            return Bounds(ref: ref, start: start, end: end, dateRangeLabel: label)
        }

        return rollingBounds(for: ref.template, now: now)
    }

    private static func rollingBounds(for template: PsychologyReportTemplate, now: Date) -> Bounds {
        let calendar = Calendar.current
        let end = endOfDay(now, calendar: calendar)
        let start = calendar.date(byAdding: .day, value: -89, to: calendar.startOfDay(for: now)) ?? now
        let ref = PsychologyReportPeriodRef(template: template, periodID: "rolling:90d")
        let label = "Last 90 days"
        return Bounds(ref: ref, start: start, end: end, dateRangeLabel: label)
    }

    private static func earliestTradeDate(_ trades: [Trade]) -> Date? {
        trades.map(\.entryAt).min()
    }

    private static func mondayOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start)
        let diff = weekday == 1 ? -6 : 1 - weekday
        return calendar.date(byAdding: .day, value: diff, to: start) ?? start
    }

    private static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        guard let next = calendar.date(byAdding: .day, value: 1, to: start) else { return date }
        return next.addingTimeInterval(-0.001)
    }
}
