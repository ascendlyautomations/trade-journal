import Foundation

typealias ScorecardReliability = PsychologySampleReliability

nonisolated enum ScorecardCategoryId: String, Sendable, CaseIterable {
    case consistency
    case risk
    case discipline
    case psychology
}

nonisolated struct ScorecardSubMetric: Hashable, Sendable {
    var id: String
    var label: String
    var value: String
    var explanation: String
    var sampleSize: Int
    var sampleLabel: String
}

nonisolated struct ScorecardCategoryResult: Hashable, Sendable {
    var id: ScorecardCategoryId
    var title: String
    var weight: Double
    var score: Int?
    var coveragePercent: Int
    var reliability: ScorecardReliability
    var eligible: Bool
    var subMetrics: [ScorecardSubMetric]
    var strengths: [String]
    var weaknesses: [String]
    var dataGaps: [String]
}

nonisolated struct ScorecardOverallContribution: Hashable, Sendable {
    var id: ScorecardCategoryId
    var title: String
    var score: Int
    var nominalWeight: Double
    var effectiveWeight: Double
}

nonisolated enum ScorecardOverallStatus: String, Sendable {
    case ready
    case building
    case unavailable
}

nonisolated struct ScorecardOverallResult: Hashable, Sendable {
    var score: Int?
    var status: ScorecardOverallStatus
    var statusMessage: String
    var coveragePercent: Int
    var reliability: ScorecardReliability
    var tradeCount: Int
    var tradingDayCount: Int
    var contributions: [ScorecardOverallContribution]
    var nominalWeightIncluded: Double
}

nonisolated struct ScorecardResult: Hashable, Sendable {
    var scopeLabel: String
    var generatedAtMs: Int64
    var overall: ScorecardOverallResult
    var categories: [ScorecardCategoryResult]
}

nonisolated struct ScorecardTrade: Hashable, Sendable {
    var id: String
    var pnl: Double
    var rr: Double?
    var maxRrReached: Double?
    var realizedRr: Double?
    var followedPlan: Bool?
    var mistakeType: String?
    var confidence: Double?
    var executionRating: Double?
    var entryTimeMs: Int64
    var tradingDayKey: String?
    var psychologyDayKey: String?
}

nonisolated struct ScorecardAnalyticsContext: Sendable {
    var periodTradingDayCount: Int
    var maxDrawdown: Double
    var avgWin: Double
    var avgLoss: Double
    var totalTrades: Int
    var postTripleLossWinRate: Double?
    var rrTargetAnalysis: DashboardRrTargetAnalysis
}

nonisolated struct ScorecardBuildInput: Sendable {
    var scopeLabel: String
    var trades: [ScorecardTrade]
    var checkIns: [TraderDailyCheckIn]
    var analytics: ScorecardAnalyticsContext
}

nonisolated enum ScorecardConstants {
    static let categoryWeights: [ScorecardCategoryId: Double] = [
        .consistency: 0.25,
        .risk: 0.25,
        .discipline: 0.2,
        .psychology: 0.3,
    ]
    static let minTradesOverall = 20
    static let minTradingDaysOverall = 5
    static let minNominalWeightOverall = 0.45
    static let minScoredCategoriesOverall = 2
}
