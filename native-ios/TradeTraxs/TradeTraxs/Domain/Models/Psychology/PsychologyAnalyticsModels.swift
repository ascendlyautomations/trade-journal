import Foundation

/// Sample-size policy for psychology analytics — avoids misleading small-n stats.
nonisolated enum PsychologySampleReliability: String, Hashable, Codable, Sendable {
    case insufficient
    case earlySignal
    case developing
    case strong

    static func resolve(tradeCount: Int) -> PsychologySampleReliability {
        switch tradeCount {
        case ..<5: return .insufficient
        case 5...9: return .earlySignal
        case 10...29: return .developing
        case 30...: return .strong
        default: return .insufficient
        }
    }

    var label: String {
        switch self {
        case .insufficient: return "Insufficient data"
        case .earlySignal: return "Early signal"
        case .developing: return "Developing"
        case .strong: return "Strong signal"
        }
    }

    /// Dashboard cards require at least early signal.
    var qualifiesForDashboardCard: Bool {
        switch self {
        case .insufficient: return false
        case .earlySignal, .developing, .strong: return true
        }
    }

    /// Headline comparisons require developing or better.
    var qualifiesForComparison: Bool {
        switch self {
        case .developing, .strong: return true
        case .insufficient, .earlySignal: return false
        }
    }
}

nonisolated struct PsychologyGroupMetrics: Hashable, Sendable {
    var tradeCount: Int
    var winCount: Int
    var lossCount: Int
    var winRate: Decimal?
    var totalPnL: Decimal
    var averagePnL: Decimal?
    var expectancy: Decimal?
    var averageRR: Decimal?
    var profitFactor: Decimal?
    var reliability: PsychologySampleReliability

    static let empty = PsychologyGroupMetrics(
        tradeCount: 0,
        winCount: 0,
        lossCount: 0,
        winRate: nil,
        totalPnL: 0,
        averagePnL: nil,
        expectancy: nil,
        averageRR: nil,
        profitFactor: nil,
        reliability: .insufficient
    )
}

nonisolated enum PsychologyInsightCategory: String, Hashable, Codable, Sendable, CaseIterable {
    case sleep
    case mentalState
    case conviction
    case discipline
    case emotion
    case afterLosses
    case tradeFrequency
    case combined
}

nonisolated struct PsychologyInsightCard: Identifiable, Hashable, Sendable {
    var id: String
    var category: PsychologyInsightCategory
    var sectionTitle: String
    var headline: String
    var detail: String
    var sampleSize: Int
    var reliability: PsychologySampleReliability
    var rankingScore: Double
}

nonisolated struct PsychologyAnalyticsSection: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var subtitle: String?
    var groups: [PsychologyAnalyticsGroupRow]
    var footnote: String?
}

nonisolated struct PsychologyAnalyticsGroupRow: Identifiable, Hashable, Sendable {
    var id: String
    var label: String
    var metrics: PsychologyGroupMetrics
    var highlight: Bool
}

nonisolated struct PsychologyAnalyticsReport: Hashable, Sendable {
    var generatedAt: Date
    var baseline: PsychologyGroupMetrics
    var dashboardCards: [PsychologyInsightCard]
    var sections: [PsychologyAnalyticsSection]
    var enrichedTradeCount: Int
    var checkInMatchedTradeCount: Int
}

nonisolated struct PsychologyEnrichedTrade: Hashable, Sendable {
    var trade: Trade
    var dailyCheckIn: TraderDailyCheckIn?
    var consecutiveLossesBefore: Int
    var consecutiveWinsBefore: Int
    var tradeNumberInDay: Int
    var previousTradeWasLoss: Bool
}
