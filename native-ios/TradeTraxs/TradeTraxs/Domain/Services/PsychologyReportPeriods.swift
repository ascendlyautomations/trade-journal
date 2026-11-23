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
        return rollingBounds(for: ref, now: now)
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
        let calendar = TradingReportPeriods.eastern
        var monday = mondayOfWeek(containing: now, calendar: calendar)
        var refs: [PsychologyReportPeriodRef] = []

        for _ in 0..<limit {
            if monday < calendar.startOfDay(for: earliest) { break }
            let id = "week:\(TraderPsychologyAnalyticsFoundation.tradeDateKey(for: monday))"
            refs.append(PsychologyReportPeriodRef(template: .weekly, periodID: id))
            guard let prev = calendar.date(byAdding: .day, value: -7, to: monday) else { break }
            monday = prev
        }
        return refs
    }

    static func monthlyRefs(from earliest: Date, now: Date, limit: Int) -> [PsychologyReportPeriodRef] {
        let calendar = TradingReportPeriods.eastern
        var comps = calendar.dateComponents([.year, .month], from: now)
        var refs: [PsychologyReportPeriodRef] = []

        for _ in 0..<limit {
            guard let year = comps.year, let month = comps.month else { break }
            let id = String(format: "month:%04d-%02d", year, month)
            refs.append(PsychologyReportPeriodRef(template: .monthly, periodID: id))
            guard let start = calendar.date(from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: 1
            )),
                  start >= calendar.startOfDay(for: earliest)
            else { break }
            guard let prev = calendar.date(byAdding: .month, value: -1, to: start) else { break }
            comps = calendar.dateComponents([.year, .month], from: prev)
        }
        return refs
    }

    private static func defaultPeriodicRefs(now: Date) -> [PsychologyReportPeriodRef] {
        let calendar = TradingReportPeriods.eastern
        let monday = mondayOfWeek(containing: now, calendar: calendar)
        let comps = calendar.dateComponents([.year, .month], from: now)
        let monthID = String(format: "month:%04d-%02d", comps.year ?? 2026, comps.month ?? 1)
        return [
            PsychologyReportPeriodRef(
                template: .weekly,
                periodID: "week:\(TraderPsychologyAnalyticsFoundation.tradeDateKey(for: monday))"
            ),
            PsychologyReportPeriodRef(template: .monthly, periodID: monthID),
        ]
    }

    private static func periodicBounds(for ref: PsychologyReportPeriodRef, now: Date) -> Bounds {
        let calendar = TradingReportPeriods.eastern
        if ref.periodID.hasPrefix("week:") {
            let dateStr = String(ref.periodID.dropFirst("week:".count))
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            formatter.timeZone = calendar.timeZone
            let monday = formatter.date(from: dateStr) ?? now
            let sunday = calendar.date(byAdding: .day, value: 6, to: monday) ?? monday
            let naturalEnd = endOfDay(sunday, calendar: calendar)
            let end = min(naturalEnd, endOfDay(now, calendar: calendar))
            var label = TradingReportPeriods.dateRangeLabel(start: monday, end: end, kind: .weekly)
            if end < naturalEnd { label += " (partial)" }
            return Bounds(ref: ref, start: monday, end: end, dateRangeLabel: label)
        }

        if ref.periodID.hasPrefix("month:") {
            let parts = ref.periodID.dropFirst("month:".count).split(separator: "-")
            let year = Int(parts.first ?? "2026") ?? 2026
            let month = Int(parts.dropFirst().first ?? "1") ?? 1
            let start = calendar.date(from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: 1
            )) ?? now
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            let endDay = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? start
            let naturalEnd = endOfDay(endDay, calendar: calendar)
            let isCurrentMonth = calendar.isDate(start, equalTo: now, toGranularity: .month)
            let end = isCurrentMonth ? min(endOfDay(now, calendar: calendar), naturalEnd) : naturalEnd
            var label = TradingReportPeriods.dateRangeLabel(start: start, end: end, kind: .monthly)
            if end < naturalEnd { label += " (partial)" }
            return Bounds(ref: ref, start: start, end: end, dateRangeLabel: label)
        }

        return rollingBounds(for: ref, now: now)
    }

    private static func rollingBounds(for ref: PsychologyReportPeriodRef, now: Date) -> Bounds {
        let calendar = TradingReportPeriods.eastern
        let end = endOfDay(now, calendar: calendar)

        if ref.periodID.hasPrefix("custom:") {
            let rest = String(ref.periodID.dropFirst("custom:".count))
            let parts = rest.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2,
               let start = dayKeyDate(parts[0], calendar: calendar),
               let endDay = dayKeyDate(parts[1], calendar: calendar) {
                let startDay = calendar.startOfDay(for: start)
                let rangeEnd = min(endOfDay(endDay, calendar: calendar), end)
                let label = TradingReportPeriods.dateRangeLabel(
                    start: startDay,
                    end: rangeEnd,
                    kind: .weekly
                )
                return Bounds(ref: ref, start: startDay, end: rangeEnd, dateRangeLabel: label)
            }
        }

        let preset = PsychologyReportTimePreset.from(periodID: ref.periodID) ?? .ninetyDays
        let start: Date
        let label: String
        switch preset {
        case .sevenDays:
            start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
            label = "Last 7 days"
        case .thirtyDays:
            start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now
            label = "Last 30 days"
        case .ninetyDays:
            start = calendar.date(byAdding: .day, value: -89, to: calendar.startOfDay(for: now)) ?? now
            label = "Last 90 days"
        case .sixMonths:
            start = calendar.date(byAdding: .day, value: -179, to: calendar.startOfDay(for: now)) ?? now
            label = "Last 6 months"
        case .all:
            start = calendar.date(byAdding: .year, value: -30, to: calendar.startOfDay(for: now)) ?? now
            label = "All time"
        }
        return Bounds(ref: ref, start: start, end: end, dateRangeLabel: label)
    }

    private static func dayKeyDate(_ key: String, calendar: Calendar) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = calendar.timeZone
        return formatter.date(from: key)
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
