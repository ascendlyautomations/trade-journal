import Foundation

/// Web `TradingReportPeriodKey` — exact period catalog used by Dashboard Trading Reports.
nonisolated enum TradingReportPeriodKey: String, Hashable, Codable, Sendable, CaseIterable, Identifiable {
    case weeklyThis = "weekly_this"
    case weeklyLast = "weekly_last"
    case monthlyThis = "monthly_this"
    case monthlyLast = "monthly_last"

    var id: String { rawValue }

    var kind: TradingReportKind {
        switch self {
        case .weeklyThis, .weeklyLast: return .weekly
        case .monthlyThis, .monthlyLast: return .monthly
        }
    }

    var catalogTitle: String {
        switch self {
        case .weeklyThis: return "This Week"
        case .weeklyLast: return "Last Week"
        case .monthlyThis: return "This Month"
        case .monthlyLast: return "Last Month"
        }
    }

    var catalogSubtitle: String {
        switch self {
        case .weeklyThis:
            return "Review your trading performance for the current week."
        case .weeklyLast:
            return "Review your trading performance from last week."
        case .monthlyThis:
            return "Analyze trends for the current month."
        case .monthlyLast:
            return "Analyze trends from last month."
        }
    }

    var systemImage: String {
        switch self {
        case .weeklyThis, .weeklyLast: return "calendar"
        case .monthlyThis, .monthlyLast: return "calendar.badge.clock"
        }
    }

    var reportID: ReportID { ReportID(rawValue) }
}

nonisolated enum TradingReportKind: String, Hashable, Codable, Sendable {
    case weekly
    case monthly

    var title: String {
        switch self {
        case .weekly: return "Weekly Trading Report"
        case .monthly: return "Monthly Trading Report"
        }
    }
}

struct TradingReportMetrics: Hashable, Codable, Sendable {
    var netPnl: Double
    var winRate: Double
    var averageRr: Double?
    var profitFactor: Double?
    var tradesTaken: Int
    var bestDayLabel: String?
    var bestDayPnl: Double?
    var worstDayLabel: String?
    var worstDayPnl: Double?
    var bestSessionLabel: String?
    var bestSessionPnl: Double?
    var worstSessionLabel: String?
    var worstSessionPnl: Double?
    var mostTradedSymbol: String?
    var averageHoldTimeSeconds: Int?
}

/// Web `TradingReport` — deterministic report payload (`summarySource: "deterministic"`).
struct TradingReport: Hashable, Codable, Sendable, Identifiable {
    var periodKey: TradingReportPeriodKey
    var kind: TradingReportKind
    var title: String
    var dateRangeLabel: String
    var periodStartIso: String
    var periodEndIso: String
    var generatedAt: TimeInterval
    var executiveSummary: String
    var metrics: TradingReportMetrics
    var strengths: [String]
    var opportunities: [String]
    var recommendations: [String]
    var bestTradeId: String?
    var keyTakeaway: String
    var summarySource: String

    var id: ReportID { periodKey.reportID }
}

nonisolated struct TradingReportsSnapshot: Hashable, Codable, Sendable {
    var reports: [TradingReportPeriodKey: TradingReport]
    var computedAt: TimeInterval

    func report(for key: TradingReportPeriodKey) -> TradingReport? {
        reports[key]
    }
}

/// Ordered detail sections derived from a report (no hardcoded empty placeholders).
enum TradingReportDetailBlock: Hashable, Identifiable, Sendable {
    case summary(String)
    case metrics(TradingReportMetrics)
    case strengths([String])
    case opportunities([String])
    case recommendations([String])
    case bestTrade(TradeID)
    case keyTakeaway(String)

    var id: String {
        switch self {
        case .summary: return "summary"
        case .metrics: return "metrics"
        case .strengths: return "strengths"
        case .opportunities: return "opportunities"
        case .recommendations: return "recommendations"
        case .bestTrade: return "bestTrade"
        case .keyTakeaway: return "keyTakeaway"
        }
    }

    var title: String {
        switch self {
        case .summary: return "Summary"
        case .metrics: return "Key Metrics"
        case .strengths: return "Strengths"
        case .opportunities: return "Opportunities"
        case .recommendations: return "Recommendations"
        case .bestTrade: return "Best Trade"
        case .keyTakeaway: return "Key Takeaway"
        }
    }

    static func blocks(from report: TradingReport) -> [TradingReportDetailBlock] {
        var result: [TradingReportDetailBlock] = [
            .summary(report.executiveSummary),
            .metrics(report.metrics),
        ]
        if !report.strengths.isEmpty { result.append(.strengths(report.strengths)) }
        if !report.opportunities.isEmpty { result.append(.opportunities(report.opportunities)) }
        if !report.recommendations.isEmpty { result.append(.recommendations(report.recommendations)) }
        if let raw = report.bestTradeId, !raw.isEmpty {
            result.append(.bestTrade(TradeID(raw)))
        }
        if !report.keyTakeaway.isEmpty { result.append(.keyTakeaway(report.keyTakeaway)) }
        return result
    }
}
