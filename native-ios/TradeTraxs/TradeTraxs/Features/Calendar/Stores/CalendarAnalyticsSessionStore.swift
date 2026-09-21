import Foundation

/// In-memory Calendar V2 context for day-detail parity and filter-aware summaries.
@MainActor
final class CalendarAnalyticsSessionStore {
    static let shared = CalendarAnalyticsSessionStore()

    private(set) var accountFilter: DashboardAccountFilter = .all
    private(set) var modeFilter: String?
    private(set) var monthDays: [String: TradingDaySummary] = [:]
    private(set) var revision: Int64 = 0

    private init() {}

    func publishMonth(
        days: [String: TradingDaySummary],
        accountFilter: DashboardAccountFilter,
        modeFilter: String?,
        revision: Int64
    ) {
        self.monthDays = days
        self.accountFilter = accountFilter
        self.modeFilter = modeFilter
        self.revision = revision
    }

    func expectedSummary(for dayKey: String, accountFilter: DashboardAccountFilter) -> TradingDaySummary? {
        guard accountFilter == self.accountFilter else { return monthDays[dayKey] }
        return monthDays[dayKey]
    }

    func invalidate() {
        monthDays = [:]
        revision = 0
    }
}
