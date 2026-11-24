import Foundation

enum TradingReportCustomRangeSupport {
  /// Default sheet state, current calendar month through today (eastern).
    static func defaultMonthSelection(now: Date = Date()) -> (year: Int, month: Int, start: Date, end: Date) {
        let calendar = TradingReportPeriods.eastern
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let bounds = TradingReportPeriods.selectedMonthBounds(year: year, month: month, now: now)
        return (year, month, bounds.start, bounds.end)
    }

    static func monthRange(year: Int, month: Int, now: Date = Date()) -> (start: Date, end: Date) {
        let bounds = TradingReportPeriods.selectedMonthBounds(year: year, month: month, now: now)
        return (bounds.start, bounds.end)
    }

    static func selectableYears(now: Date = Date(), tradeYears: [Int] = []) -> [Int] {
        let calendar = TradingReportPeriods.eastern
        let current = calendar.component(.year, from: now)
        var years = Set(tradeYears)
        years.insert(current)
        if years.isEmpty {
            return (current - 4 ... current).reversed()
        }
        return years.sorted(by: >)
    }

    static func canGenerate(
        start: Date?,
        end: Date?,
        now: Date = Date(),
        calendar: Calendar = TradingReportPeriods.eastern
    ) -> Bool {
        validationMessage(start: start, end: end, now: now, calendar: calendar) == nil
    }

    static func validationMessage(
        start: Date?,
        end: Date?,
        now: Date = Date(),
        calendar: Calendar = TradingReportPeriods.eastern
    ) -> String? {
        guard let start, let end else {
            return "Choose a start and end date."
        }
        let todayStart = calendar.startOfDay(for: now)
        if calendar.startOfDay(for: start) > todayStart {
            return "Start date can't be in the future."
        }
        if calendar.startOfDay(for: end) > todayStart {
            return "End date can't be in the future."
        }
        if start > end {
            return "End date must be on or after the start date."
        }
        return nil
    }
}