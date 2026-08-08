import Foundation

nonisolated struct PerformanceSummary: Hashable, Codable, Sendable {
    var interval: DateIntervalValue
    var statistics: TradeStatistics
    var bestTradeID: TradeID?
    var worstTradeID: TradeID?
    var currentStreakDays: Int
}

nonisolated struct Insight: Hashable, Codable, Sendable, Identifiable {
    var id: String
    var title: String
    var body: String
    var relatedTradeIDs: [TradeID]
    var generatedAt: Date
}

nonisolated enum HomeWidgetKind: String, Hashable, Codable, Sendable {
    case dailyPnL
    case winRate
    case streak
    case shortcuts
    case insights
    case calendar
}

nonisolated struct HomeWidget: Hashable, Codable, Sendable, Identifiable {
    var id: String { kind.rawValue }
    var kind: HomeWidgetKind
    var isEnabled: Bool
}

nonisolated struct HomeDashboard: Hashable, Codable, Sendable {
    var summary: PerformanceSummary
    var widgets: [HomeWidget]
    var insights: [Insight]
    var shortcutDestinations: [String]
    var refreshedAt: Date
}
