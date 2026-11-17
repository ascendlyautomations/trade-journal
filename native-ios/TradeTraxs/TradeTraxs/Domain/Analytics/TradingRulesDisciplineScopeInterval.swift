import Foundation

/// Eastern-aligned scope windows for discipline prior-period comparisons (no device-local calendar drift).
nonisolated enum TradingRulesDisciplineScopeInterval {
    static let eastern = TradingReportPeriods.eastern

    /// Active dashboard window for discipline comparisons. `nil` for All Time (no prior slice).
    static func currentInterval(
        scope: DashboardClientScopeFilter,
        now: Date = Date()
    ) -> DateInterval? {
        if let custom = scope.customInterval {
            return normalizedHalfOpen(custom)
        }
        let end = now
        let start: Date?
        switch scope.dateRange {
        case .all:
            return nil
        case .ytd:
            let today = eastern.startOfDay(for: now)
            let year = eastern.component(.year, from: today)
            start = eastern.date(from: DateComponents(calendar: eastern, timeZone: eastern.timeZone, year: year, month: 1, day: 1))
        case .sevenDays:
            start = eastern.date(byAdding: .day, value: -7, to: eastern.startOfDay(for: now))
        case .thirtyDays:
            start = eastern.date(byAdding: .day, value: -30, to: eastern.startOfDay(for: now))
        case .ninetyDays:
            start = eastern.date(byAdding: .day, value: -90, to: eastern.startOfDay(for: now))
        case .oneYear:
            start = eastern.date(byAdding: .day, value: -365, to: eastern.startOfDay(for: now))
        }
        guard let start else { return nil }
        guard start < end else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Prior window of equal duration immediately before `current` (non-overlapping, end == current.start).
    static func priorInterval(matching current: DateInterval) -> DateInterval? {
        let duration = current.duration
        guard duration > 0 else { return nil }
        let priorEnd = current.start
        let priorStart = priorEnd.addingTimeInterval(-duration)
        guard priorStart < priorEnd else { return nil }
        return DateInterval(start: priorStart, end: priorEnd)
    }

    private static func normalizedHalfOpen(_ interval: DateInterval) -> DateInterval? {
        guard interval.start < interval.end else { return nil }
        return interval
    }
}
