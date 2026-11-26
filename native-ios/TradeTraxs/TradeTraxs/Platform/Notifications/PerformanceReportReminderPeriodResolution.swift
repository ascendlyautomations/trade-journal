import Foundation

/// Resolves Performance Report deep-link targets when a local reminder is opened.
nonisolated enum PerformanceReportReminderPeriodResolution {
  enum Kind: String, Sendable {
    case weekly
    case monthly
  }

  static let userInfoKey = "performance_report_reminder"

  /// Resolve from the notification's original delivery instant (tap may be days later).
  static func resolvedReportID(kind: Kind, referenceDate: Date = Date()) -> ReportID {
    switch kind {
    case .weekly:
      return weeklyReportAfterFridayEnded(referenceDate: referenceDate)
    case .monthly:
      return monthlyPriorCompletedMonth(referenceDate: referenceDate)
    }
  }

  private static func weeklyReportAfterFridayEnded(referenceDate: Date) -> ReportID {
    let calendar = TradingReportPeriods.eastern
    let today = calendar.startOfDay(for: referenceDate)
    let monday = mondayContaining(today, calendar: calendar)
    let mondayKey = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: monday)
    return TradingReportWeekRef(mondayKey: mondayKey).reportID
  }

  private static func monthlyPriorCompletedMonth(referenceDate: Date) -> ReportID {
    let bounds = TradingReportPeriods.bounds(for: .monthlyLast, now: referenceDate)
    let startKey = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: bounds.start)
    let yearMonth = String(startKey.prefix(7))
    return ReportID("month:\(yearMonth)")
  }

  private static func mondayContaining(_ date: Date, calendar: Calendar) -> Date {
    let start = calendar.startOfDay(for: date)
    let weekday = calendar.component(.weekday, from: start)
    let diff = weekday == 1 ? -6 : 1 - weekday
    return calendar.date(byAdding: .day, value: diff, to: start) ?? start
  }
}