import Foundation

/// Structured facts derived from Phase 4 analytics, sole source for coach copy and AI context.
nonisolated struct PsychologyCoachFacts: Hashable, Codable, Sendable {
    var generatedAt: Date
    var factsHash: String
    var scope: PsychologyCoachScopeFacts
    var reportMeta: PsychologyCoachReportMetaFacts
    var baseline: PsychologyCoachFactMetric
    var comparisons: [PsychologyCoachComparisonFact]
    var topInsights: [PsychologyCoachFactInsight]
    var combinedPatterns: [PsychologyCoachFactInsight]
    var trends: [PsychologyCoachTrendFact]
    var checkInAggregates: PsychologyCoachCheckInAggregates
    var tradingRulesCompliance: PsychologyCoachTradingRulesFacts?
    var deterministicCoach: PsychologyCoachDeterministicFacts
    var guardrailFacts: PsychologyCoachGuardrailFacts
    var dataGaps: [String]
    var hasMinimumData: Bool
}

nonisolated struct PsychologyCoachScopeFacts: Hashable, Codable, Sendable {
    var label: String
    var fingerprint: String
}

nonisolated struct PsychologyCoachReportMetaFacts: Hashable, Codable, Sendable {
    var enrichedTradeCount: Int
    var checkInMatchedTradeCount: Int
    var matchedDayCount: Int
}

nonisolated struct PsychologyCoachFactMetric: Hashable, Codable, Sendable {
    var tradeCount: Int
    var winRate: Double?
    var expectancy: Double?
    var averagePnL: Double?
    var reliability: String
}

nonisolated struct PsychologyCoachComparisonSide: Hashable, Codable, Sendable {
    var label: String
    var sampleLabel: String
    var tradeCount: Int
    var winRate: Double?
    var averagePnL: Double?
    var expectancy: Double?
    var reliability: String
    var highlight: Bool
}

nonisolated struct PsychologyCoachComparisonFact: Hashable, Codable, Sendable {
    var id: String
    var category: String
    var title: String
    var headline: String
    var suggestion: String
    var sampleLine: String
    var reliability: String
    var favorableSide: String
    var left: PsychologyCoachComparisonSide
    var right: PsychologyCoachComparisonSide
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

nonisolated struct PsychologyCoachCheckInAggregates: Hashable, Codable, Sendable {
    var matchedDayCount: Int
    var averageSleepHours: Double?
    var averageStress: Double?
    var averageMood: Double?
    var averageConfidence: Double?
    var averageEnergy: Double?
    var averageFocus: Double?
}

nonisolated struct PsychologyCoachTradingRulesFacts: Hashable, Codable, Sendable {
    var adherencePercent: Double?
    var evaluated: Int
    var followed: Int
    var violated: Int
    var topViolationRules: [PsychologyCoachRuleViolationFact]
}

nonisolated struct PsychologyCoachRuleViolationFact: Hashable, Codable, Sendable {
    var ruleId: String
    var ruleLabel: String
    var violationCount: Int
    var followedWinRate: Double?
    var violatedWinRate: Double?
}

nonisolated struct PsychologyCoachDeterministicFacts: Hashable, Codable, Sendable {
    var overview: String
    var doingWell: [String]
    var watchItems: [String]
    var recommendations: [String]
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
    /// True only when lower-stress trades beat higher-stress trades.
    var highStressWeaker: Bool = false
    /// True only when higher-focus trades beat lower-focus trades.
    var lowFocusWeaker: Bool = false
    var personalLossPause: Bool = false
    var personalTradeCap: Bool = false
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

nonisolated struct PsychologyCoachAITurnUserMessage: Sendable {
    var id: String
    var displayContent: String
    var createdAt: String?
}

nonisolated struct PsychologyCoachAIRequest: Sendable {
    var facts: PsychologyCoachFacts
    var messages: [PsychologyCoachAIMessage]
    var mode: PsychologyCoachAIMode
    var conversationID: AIConversationID?
    var createConversation: Bool = true
    var assistantMessageID: String?
    var userMessage: PsychologyCoachAITurnUserMessage?
    var persistCachedOnly: Bool = false
    var cachedReply: String?
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
    var conversationID: AIConversationID?
    var assistantMessageID: String?
}