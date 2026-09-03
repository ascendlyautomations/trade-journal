import Foundation

/// Structured facts derived from Phase 4 analytics — sole source for coach copy and AI context.
nonisolated struct PsychologyCoachFacts: Hashable, Codable, Sendable {
    var generatedAt: Date
    var factsHash: String
    var baseline: PsychologyCoachFactMetric
    var topInsights: [PsychologyCoachFactInsight]
    var combinedPatterns: [PsychologyCoachFactInsight]
    var trends: [PsychologyCoachTrendFact]
    var guardrailFacts: PsychologyCoachGuardrailFacts
    var dataGaps: [String]
    var hasMinimumData: Bool
}

nonisolated struct PsychologyCoachFactMetric: Hashable, Codable, Sendable {
    var tradeCount: Int
    var winRate: Double?
    var expectancy: Double?
    var averagePnL: Double?
    var reliability: String
}

nonisolated struct PsychologyCoachFactInsight: Hashable, Codable, Sendable {
    var id: String
    var category: String
    var headline: String
    var detail: String
    var sampleSize: Int
    var reliability: String
    var expectancy: Double?
    var winRate: Double?
    var averagePnL: Double?
}

nonisolated struct PsychologyCoachTrendFact: Hashable, Codable, Sendable {
    var id: String
    var headline: String
    var detail: String
    var recentSampleSize: Int
    var priorSampleSize: Int
    var reliability: String
}

nonisolated struct PsychologyCoachGuardrailFacts: Hashable, Codable, Sendable {
    var consecutiveLossCheckpoint: Int?
    var consecutiveLossWinRateAfter: Double?
    var consecutiveLossBaselineWinRate: Double?
    var lowSleepHoursThreshold: Double?
    var lowSleepExpectancy: Double?
    var maxTradesDaySoftLimit: Int?
    var lateTradeAveragePnL: Double?
    var earlyTradeAveragePnL: Double?
}

nonisolated struct PsychologyCoachSummary: Hashable, Sendable {
    var title: String
    var overview: String
    var doingWell: [String]
    var watchItems: [String]
    var recommendations: [String]
    var isDeterministic: Bool
}

nonisolated struct PsychologyGuardrailNotice: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var message: String
    var kind: PsychologyGuardrailKind
}

nonisolated enum PsychologyGuardrailKind: String, Hashable, Codable, Sendable {
    case consecutiveLosses
    case lowSleep
    case highStress
    case lowFocus
    case tradeCount
    case lowFocusDay
}

nonisolated struct PsychologyCoachAIRequest: Sendable {
    var facts: PsychologyCoachFacts
    var messages: [PsychologyCoachAIMessage]
    var mode: PsychologyCoachAIMode
}

nonisolated enum PsychologyCoachAIMode: String, Sendable {
    case summary
    case explain
    case followUp
    case reportSummary
}

nonisolated struct PsychologyCoachAIMessage: Hashable, Codable, Sendable {
    var role: String
    var content: String
}

nonisolated struct PsychologyCoachAIResponse: Sendable {
    var reply: String
}
