import Foundation

/// Psychology report templates in the Reports catalog.
nonisolated enum PsychologyReportTemplate: String, Hashable, Codable, Sendable, CaseIterable, Identifiable {
    case weekly
    case monthly
    case sleepPerformance
    case discipline
    case emotions
    case afterLosses
    case mentalState
    case tradeFrequency

    var id: String { rawValue }

    var catalogTitle: String {
        switch self {
        case .weekly: return "Weekly Psychology Report"
        case .monthly: return "Monthly Psychology Report"
        case .sleepPerformance: return "Sleep & Performance"
        case .discipline: return "Discipline Report"
        case .emotions: return "Emotional Trading"
        case .afterLosses: return "After-Loss Behavior"
        case .mentalState: return "Focus / Stress / Energy"
        case .tradeFrequency: return "Overtrading / Trade Frequency"
        }
    }

    var catalogSubtitle: String {
        switch self {
        case .weekly: return "Check-ins, discipline, emotions, and behavior for a calendar week."
        case .monthly: return "Monthly trends with comparisons to the prior month."
        case .sleepPerformance: return "How sleep correlates with your results."
        case .discipline: return "Plan adherence and execution over recent trades."
        case .emotions: return "Emotion tags and their performance impact."
        case .afterLosses: return "How you trade after consecutive losses."
        case .mentalState: return "Stress, focus, and energy patterns."
        case .tradeFrequency: return "Trade sequencing and overtrading signals."
        }
    }

    var systemImage: String {
        switch self {
        case .weekly, .monthly: return "brain.head.profile"
        case .sleepPerformance: return "bed.double.fill"
        case .discipline: return "checkmark.seal.fill"
        case .emotions: return "face.smiling"
        case .afterLosses: return "arrow.triangle.2.circlepath"
        case .mentalState: return "bolt.heart.fill"
        case .tradeFrequency: return "chart.bar.fill"
        }
    }

    var isPeriodic: Bool {
        self == .weekly || self == .monthly
    }

    var reportIDPrefix: String { "psych_\(rawValue)" }
}

/// Identifies a specific report instance (historical week/month or thematic window).
nonisolated struct PsychologyReportPeriodRef: Hashable, Codable, Sendable {
    var template: PsychologyReportTemplate
    /// e.g. `week:2026-08-31` or `month:2026-09` or `rolling:90d`
    var periodID: String

    var reportID: ReportID {
        ReportID("\(template.reportIDPrefix):\(periodID)")
    }

    static func parse(reportID: ReportID) -> PsychologyReportPeriodRef? {
        let raw = reportID.rawValue
        guard raw.hasPrefix("psych_") else { return nil }
        let remainder = String(raw.dropFirst("psych_".count))
        guard let separator = remainder.firstIndex(of: ":") else { return nil }
        let templateRaw = String(remainder[..<separator])
        let periodID = String(remainder[remainder.index(after: separator)...])
        guard let template = PsychologyReportTemplate(rawValue: templateRaw) else { return nil }
        return PsychologyReportPeriodRef(template: template, periodID: periodID)
    }
}

nonisolated struct PsychologyReportCheckInSummary: Hashable, Sendable {
    var checkInCount: Int
    var averageSleepHours: Double?
    var averageSleepQuality: Double?
    var averageMorningRating: Double?
    var averageStress: Double?
    var averageEnergy: Double?
    var averageFocus: Double?
}

nonisolated struct PsychologyReportTradingPsychology: Hashable, Sendable {
    var followedPlanRate: Double?
    var averageConviction: Double?
    var mostCommonEmotion: String?
    var fomoTradeCount: Int
    var frustratedTradeCount: Int
    var averageExecutionRating: Double?
}

nonisolated struct PsychologyReportBehaviorSummary: Hashable, Sendable {
    var averageTradesPerDay: Double?
    var afterTwoLossesWinRate: Double?
    var afterTwoLossesBaselineWinRate: Double?
    var earlyTradeAvgPnL: Double?
    var lateTradeAvgPnL: Double?
}

nonisolated struct PsychologyReportComparison: Hashable, Sendable {
    var headline: String
    var detail: String
    var reliability: String
}

nonisolated struct PsychologyReportSection: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var subtitle: String?
    var bullets: [String]
    var metrics: [PsychologyReportMetricRow]
}

nonisolated struct PsychologyReportMetricRow: Hashable, Sendable {
    var label: String
    var value: String
}

/// Deterministic psychology report — reproducible from trades + check-ins.
nonisolated struct PsychologyReport: Hashable, Sendable, Identifiable {
    var periodRef: PsychologyReportPeriodRef
    var title: String
    var dateRangeLabel: String
    var periodStartIso: String
    var periodEndIso: String
    var generatedAt: TimeInterval
    var factsHash: String
    var checkInSummary: PsychologyReportCheckInSummary
    var tradingPsychology: PsychologyReportTradingPsychology
    var behavior: PsychologyReportBehaviorSummary
    var performance: PsychologyGroupMetrics
    var comparisons: [PsychologyReportComparison]
    var doingWell: [String]
    var watchItems: [String]
    var sections: [PsychologyReportSection]

    var id: ReportID { periodRef.reportID }
}

nonisolated struct PsychologyReportsSnapshot: Hashable, Sendable {
    var reports: [ReportID: PsychologyReport]
    var computedAt: TimeInterval
    var catalogPeriods: [PsychologyReportPeriodRef]

    func report(for id: ReportID) -> PsychologyReport? {
        reports[id]
    }
}
