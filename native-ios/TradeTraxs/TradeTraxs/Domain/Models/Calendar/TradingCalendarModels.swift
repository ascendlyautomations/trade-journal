import Foundation

/// Outcome of a trading day's net P&L for cell styling / accessibility.
nonisolated enum TradingDayOutcome: String, Hashable, Codable, Sendable {
    case profit
    case loss
    case breakeven
    case none
}

/// Aggregated performance for a single futures trading day (`YYYY-MM-DD`).
nonisolated struct TradingDaySummary: Hashable, Codable, Sendable, Identifiable {
    /// Futures trading day key (`YYYY-MM-DD`).
    var dayKey: String
    var netPnL: Decimal
    var tradeCount: Int
    var winCount: Int
    var lossCount: Int
    var breakevenCount: Int
    var grossProfit: Decimal
    var grossLoss: Decimal
    var tradeIDs: [TradeID]
    var accountIDs: [TradingAccountID]

    var id: String { dayKey }

    var outcome: TradingDayOutcome {
        guard tradeCount > 0 else { return .none }
        if netPnL > 0 { return .profit }
        if netPnL < 0 { return .loss }
        return .breakeven
    }

    var winRate: Decimal? {
        guard tradeCount > 0 else { return nil }
        return Decimal(winCount) / Decimal(tradeCount)
    }
}

/// Sunday-start week total matching web Calendar week rows.
nonisolated struct TradingWeekSummary: Hashable, Codable, Sendable, Identifiable {
    var id: String
    var netPnL: Decimal
    var tradeCount: Int
    var tradingDayCount: Int
}

/// Month-level summary for the visible calendar.
nonisolated struct TradingMonthSummary: Hashable, Codable, Sendable {
    var year: Int
    var month: Int
    var netPnL: Decimal
    var tradeCount: Int
    var tradingDayCount: Int
    var winningDayCount: Int
    var losingDayCount: Int
    var breakevenDayCount: Int
    var bestDayKey: String?
    var bestDayPnL: Decimal?
    var worstDayKey: String?
    var worstDayPnL: Decimal?
    var averageDailyPnL: Decimal?
    /// Wins / all trades in the month (breakeven counts in denominator — Dashboard parity).
    var tradeWinRate: Decimal?
}

/// One cell in the month grid (may be leading/trailing empty).
nonisolated struct CalendarGridCell: Hashable, Sendable, Identifiable {
    var id: String
    var dayKey: String?
    var dayNumber: Int?
    var isCurrentMonth: Bool
    var isToday: Bool
    var summary: TradingDaySummary?
}

/// Full month presentation snapshot.
nonisolated struct TradingCalendarMonth: Hashable, Sendable {
    var year: Int
    var month: Int
    var title: String
    var cells: [CalendarGridCell]
    /// Seven cells → one week summary (aligned with grid rows).
    var weekSummaries: [TradingWeekSummary]
    var monthSummary: TradingMonthSummary
    var days: [String: TradingDaySummary]
}

/// Year-month identity for cache keys / navigation.
nonisolated struct CalendarMonthID: Hashable, Codable, Sendable, Comparable {
    var year: Int
    var month: Int

    var cacheKey: String { String(format: "%04d-%02d", year, month) }

    static func < (lhs: CalendarMonthID, rhs: CalendarMonthID) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        return lhs.month < rhs.month
    }

    static func current(now: Date = Date()) -> CalendarMonthID {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TradingCalendarDay.timeZone
        let comps = calendar.dateComponents([.year, .month], from: now)
        return CalendarMonthID(year: comps.year ?? 2026, month: comps.month ?? 1)
    }

    func advancing(by delta: Int) -> CalendarMonthID {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TradingCalendarDay.timeZone
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let next = calendar.date(byAdding: .month, value: delta, to: date)
        else { return self }
        let comps = calendar.dateComponents([.year, .month], from: next)
        return CalendarMonthID(year: comps.year ?? year, month: comps.month ?? month)
    }
}
