import Foundation

/// Shared Performance Report scope — mirrors Dashboard account + mode filters.
nonisolated struct TradingReportFilters: Hashable, Sendable {
    var accountFilter: DashboardAccountFilter = .all
    var accountMode: ProfileStatisticsMetrics.Mode = .all
}

/// Identifies a yearly performance report instance (`yearly:2026`).
nonisolated struct TradingReportYearRef: Hashable, Codable, Sendable {
    var year: Int

    var reportID: ReportID { ReportID("yearly:\(year)") }

    static func parse(reportID: ReportID) -> TradingReportYearRef? {
        let raw = reportID.rawValue
        guard raw.hasPrefix("yearly:") else { return nil }
        let remainder = String(raw.dropFirst("yearly:".count))
        guard let year = Int(remainder), year > 0 else { return nil }
        return TradingReportYearRef(year: year)
    }
}

/// Identifies a calendar month drill-down (`month:2026-09`).
nonisolated struct TradingReportMonthRef: Hashable, Codable, Sendable {
    var year: Int
    var month: Int

    var reportID: ReportID {
        ReportID("month:\(year)-\(String(format: "%02d", month))")
    }

    static func parse(reportID: ReportID) -> TradingReportMonthRef? {
        let raw = reportID.rawValue
        guard raw.hasPrefix("month:") else { return nil }
        let remainder = String(raw.dropFirst("month:".count))
        let parts = remainder.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              (1...12).contains(month)
        else { return nil }
        return TradingReportMonthRef(year: year, month: month)
    }
}

nonisolated enum TradingYearlyMonthAvailability: Hashable, Sendable {
    case upcoming
    case available(TradingYearlyMonthMetrics)
}

nonisolated struct TradingYearlyMonthMetrics: Hashable, Sendable, Identifiable {
    var year: Int
    var month: Int
    var monthLabel: String
    var netPnl: Decimal
    var tradeCount: Int
    var winRate: Decimal?
    var monthRef: TradingReportMonthRef

    var id: String { monthRef.reportID.rawValue }
}

nonisolated struct TradingYearlyReportMetrics: Hashable, Sendable {
    var netPnl: Decimal
    var tradeCount: Int
    var winRate: Decimal?
    var profitFactor: Decimal?
    var averageWinner: Decimal?
    var averageLoser: Decimal?
    var averageRR: Decimal?
    var expectancy: Decimal?
    var bestTrade: Decimal?
    var worstTrade: Decimal?
    var bestDayLabel: String?
    var bestDayPnl: Decimal?
    var worstDayLabel: String?
    var worstDayPnl: Decimal?
    var maxDrawdown: Decimal
    var winningDays: Int
    var losingDays: Int
}

nonisolated struct TradingYearlyMonthRow: Hashable, Sendable, Identifiable {
    var month: Int
    var monthLabel: String
    var availability: TradingYearlyMonthAvailability

    var id: Int { month }
}

/// Full-year performance report payload — generated locally from owner trades.
nonisolated struct TradingYearlyReport: Sendable, Identifiable {
    var year: Int
    var filters: TradingReportFilters
    var title: String
    var dateRangeLabel: String
    var periodStartIso: String
    var periodEndIso: String
    var generatedAt: TimeInterval
    var executiveSummary: String
    var metrics: TradingYearlyReportMetrics
    var monthRows: [TradingYearlyMonthRow]
    var chartSummary: DashboardChartMetrics.Summary
    var monthlyPnLBars: [DashboardBarPoint]
    var strongestMonth: TradingYearlyMonthMetrics?
    var weakestMonth: TradingYearlyMonthMetrics?

    var id: ReportID { yearRef.reportID }
    var yearRef: TradingReportYearRef { TradingReportYearRef(year: year) }
}
