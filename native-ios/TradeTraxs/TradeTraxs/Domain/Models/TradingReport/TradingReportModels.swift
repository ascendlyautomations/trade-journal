import Foundation

/// Web `TradingReportPeriodKey`, exact period catalog used by Dashboard Trading Reports.
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

/// Eastern Monday identified by `week:YYYY-MM-DD`.
nonisolated struct TradingReportWeekRef: Hashable, Sendable {
    var mondayKey: String

    var reportID: ReportID { ReportID("week:\(mondayKey)") }

    static func parse(reportID: ReportID) -> TradingReportWeekRef? {
        let raw = reportID.rawValue
        guard raw.hasPrefix("week:") else { return nil }
        let day = String(raw.dropFirst("week:".count))
        let parts = day.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let dayOfMonth = Int(parts[2]),
              (1...12).contains(month),
              (1...31).contains(dayOfMonth)
        else { return nil }
        let calendar = TradingReportPeriods.eastern
        guard let date = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: dayOfMonth
        )) else { return nil }
        guard calendar.component(.weekday, from: date) == 2 else { return nil }
        let normalized = String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
        return TradingReportWeekRef(mondayKey: normalized)
    }
}

nonisolated enum TradingReportKind: String, Hashable, Codable, Sendable {
    case weekly
    case monthly
    case custom

    var title: String {
        switch self {
        case .weekly: return "Weekly Trading Report"
        case .monthly: return "Monthly Trading Report"
        case .custom: return "Custom Trading Report"
        }
    }
}

/// Arbitrary eastern calendar range, `custom:YYYY-MM-DD:YYYY-MM-DD`.
nonisolated struct TradingReportCustomRangeRef: Hashable, Sendable {
    var startKey: String
    var endKey: String

    var reportID: ReportID { ReportID("custom:\(startKey):\(endKey)") }

  var interval: DateInterval? {
        guard let start = Self.dayKeyDate(startKey),
              let end = Self.dayKeyDate(endKey)
        else { return nil }
        return DashboardScopeFilterSupport.normalizedCustomInterval(
            start: start,
            end: end,
            calendar: TradingReportPeriods.eastern
        )
    }

    static func from(interval: DateInterval) -> TradingReportCustomRangeRef {
        let calendar = TradingReportPeriods.eastern
        let normalized = DashboardScopeFilterSupport.normalizedCustomInterval(
            start: interval.start,
            end: interval.end,
            calendar: calendar
        )
        return TradingReportCustomRangeRef(
            startKey: TraderPsychologyAnalyticsFoundation.tradeDateKey(for: normalized.start),
            endKey: TraderPsychologyAnalyticsFoundation.tradeDateKey(for: normalized.end)
        )
    }

    static func parse(reportID: ReportID) -> TradingReportCustomRangeRef? {
        let raw = reportID.rawValue
        guard raw.hasPrefix("custom:") else { return nil }
        let rest = String(raw.dropFirst("custom:".count))
        let parts = rest.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              Self.isValidDayKey(parts[0]),
              Self.isValidDayKey(parts[1])
        else { return nil }
        return TradingReportCustomRangeRef(startKey: parts[0], endKey: parts[1])
    }

    private static func isValidDayKey(_ key: String) -> Bool {
        dayKeyDate(key) != nil
    }

    private static func dayKeyDate(_ key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }
        let calendar = TradingReportPeriods.eastern
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        ))
    }
}

nonisolated struct TradingReportMetrics: Hashable, Codable, Sendable {
    var netPnl: Double
    var winRate: Double
    /// Trades with a recorded P&L. Missing results are excluded from money and win rate.
    var knownResultCount: Int
    /// Mean targeted R:R (`TradePointsAndRealizedRr.averageTargetedRr`).
    var averageRr: Double?
    /// Mean `maxRrReached` across trades that recorded it.
    var averageReachedRr: Double?
    var profitFactor: Double?
    var tradesTaken: Int
    var averageWinner: Double?
    var averageLoser: Double?
    var expectancy: Double?
    var bestTrade: Double?
    var worstTrade: Double?
    var maxDrawdown: Double?
    var bestDayLabel: String?
    var bestDayPnl: Double?
    var worstDayLabel: String?
    var worstDayPnl: Double?
    var winningDays: Int?
    var losingDays: Int?
    var bestSessionLabel: String?
    var bestSessionPnl: Double?
    var worstSessionLabel: String?
    var worstSessionPnl: Double?
    var mostTradedSymbol: String?
    var averageHoldTimeSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case netPnl, winRate, knownResultCount, averageRr, averageReachedRr, profitFactor, tradesTaken
        case averageWinner, averageLoser, expectancy, bestTrade, worstTrade, maxDrawdown
        case bestDayLabel, bestDayPnl, worstDayLabel, worstDayPnl, winningDays, losingDays
        case bestSessionLabel, bestSessionPnl, worstSessionLabel, worstSessionPnl
        case mostTradedSymbol, averageHoldTimeSeconds
    }

    init(
        netPnl: Double,
        winRate: Double,
        knownResultCount: Int,
        averageRr: Double? = nil,
        averageReachedRr: Double? = nil,
        profitFactor: Double? = nil,
        tradesTaken: Int,
        averageWinner: Double? = nil,
        averageLoser: Double? = nil,
        expectancy: Double? = nil,
        bestTrade: Double? = nil,
        worstTrade: Double? = nil,
        maxDrawdown: Double? = nil,
        bestDayLabel: String? = nil,
        bestDayPnl: Double? = nil,
        worstDayLabel: String? = nil,
        worstDayPnl: Double? = nil,
        winningDays: Int? = nil,
        losingDays: Int? = nil,
        bestSessionLabel: String? = nil,
        bestSessionPnl: Double? = nil,
        worstSessionLabel: String? = nil,
        worstSessionPnl: Double? = nil,
        mostTradedSymbol: String? = nil,
        averageHoldTimeSeconds: Int? = nil
    ) {
        self.netPnl = netPnl
        self.winRate = winRate
        self.knownResultCount = knownResultCount
        self.averageRr = averageRr
        self.averageReachedRr = averageReachedRr
        self.profitFactor = profitFactor
        self.tradesTaken = tradesTaken
        self.averageWinner = averageWinner
        self.averageLoser = averageLoser
        self.expectancy = expectancy
        self.bestTrade = bestTrade
        self.worstTrade = worstTrade
        self.maxDrawdown = maxDrawdown
        self.bestDayLabel = bestDayLabel
        self.bestDayPnl = bestDayPnl
        self.worstDayLabel = worstDayLabel
        self.worstDayPnl = worstDayPnl
        self.winningDays = winningDays
        self.losingDays = losingDays
        self.bestSessionLabel = bestSessionLabel
        self.bestSessionPnl = bestSessionPnl
        self.worstSessionLabel = worstSessionLabel
        self.worstSessionPnl = worstSessionPnl
        self.mostTradedSymbol = mostTradedSymbol
        self.averageHoldTimeSeconds = averageHoldTimeSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        netPnl = try container.decode(Double.self, forKey: .netPnl)
        winRate = try container.decode(Double.self, forKey: .winRate)
        knownResultCount = try container.decode(Int.self, forKey: .knownResultCount)
        averageRr = try container.decodeIfPresent(Double.self, forKey: .averageRr)
        averageReachedRr = try container.decodeIfPresent(Double.self, forKey: .averageReachedRr)
        profitFactor = try container.decodeIfPresent(Double.self, forKey: .profitFactor)
        tradesTaken = try container.decode(Int.self, forKey: .tradesTaken)
        averageWinner = try container.decodeIfPresent(Double.self, forKey: .averageWinner)
        averageLoser = try container.decodeIfPresent(Double.self, forKey: .averageLoser)
        expectancy = try container.decodeIfPresent(Double.self, forKey: .expectancy)
        bestTrade = try container.decodeIfPresent(Double.self, forKey: .bestTrade)
        worstTrade = try container.decodeIfPresent(Double.self, forKey: .worstTrade)
        maxDrawdown = try container.decodeIfPresent(Double.self, forKey: .maxDrawdown)
        bestDayLabel = try container.decodeIfPresent(String.self, forKey: .bestDayLabel)
        bestDayPnl = try container.decodeIfPresent(Double.self, forKey: .bestDayPnl)
        worstDayLabel = try container.decodeIfPresent(String.self, forKey: .worstDayLabel)
        worstDayPnl = try container.decodeIfPresent(Double.self, forKey: .worstDayPnl)
        winningDays = try container.decodeIfPresent(Int.self, forKey: .winningDays)
        losingDays = try container.decodeIfPresent(Int.self, forKey: .losingDays)
        bestSessionLabel = try container.decodeIfPresent(String.self, forKey: .bestSessionLabel)
        bestSessionPnl = try container.decodeIfPresent(Double.self, forKey: .bestSessionPnl)
        worstSessionLabel = try container.decodeIfPresent(String.self, forKey: .worstSessionLabel)
        worstSessionPnl = try container.decodeIfPresent(Double.self, forKey: .worstSessionPnl)
        mostTradedSymbol = try container.decodeIfPresent(String.self, forKey: .mostTradedSymbol)
        averageHoldTimeSeconds = try container.decodeIfPresent(Int.self, forKey: .averageHoldTimeSeconds)
    }
}

/// Web `TradingReport`, deterministic report payload (`summarySource: "deterministic"`).
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
    case strengthsAndWeaknesses(strengths: [String], weaknesses: [String])
    case recommendations([String])
    case bestTrade(TradeID)
    case keyTakeaway(String)

    var id: String {
        switch self {
        case .summary: return "summary"
        case .metrics: return "metrics"
        case .strengths: return "strengths"
        case .opportunities: return "opportunities"
        case .strengthsAndWeaknesses: return "strengthsAndWeaknesses"
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
        case .strengthsAndWeaknesses: return "Strengths & Weaknesses"
        case .recommendations: return "Recommendations"
        case .bestTrade: return "Best Trade"
        case .keyTakeaway: return "Key Takeaway"
        }
    }

    static func blocks(from report: TradingReport) -> [TradingReportDetailBlock] {
        var result: [TradingReportDetailBlock] = [
            .summary(report.executiveSummary),
        ]

        if !report.strengths.isEmpty || !report.opportunities.isEmpty {
            result.append(
                .strengthsAndWeaknesses(
                    strengths: report.strengths,
                    weaknesses: report.opportunities
                )
            )
        }

        if !report.recommendations.isEmpty { result.append(.recommendations(report.recommendations)) }
        if !report.keyTakeaway.isEmpty { result.append(.keyTakeaway(report.keyTakeaway)) }

        result.append(.metrics(report.metrics))

        if let raw = report.bestTradeId, !raw.isEmpty {
            result.append(.bestTrade(TradeID(raw)))
        }
        return result
    }
}
