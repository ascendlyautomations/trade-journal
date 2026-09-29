import Foundation

/// UTC calendar-day count point from `admin_analytics_bundle` series arrays.
nonisolated struct AdminUsageDailyCount: Sendable, Hashable, Codable {
    var day: String
    var count: Int
}

nonisolated struct AdminUsageAnalyticsSeries: Sendable, Hashable, Codable {
    /// New profile signups per UTC day (`profiles.created_at`).
    var usersPerDay: [AdminUsageDailyCount]
    /// Distinct active users per UTC day (see ``AdminUsageAnalyticsDefinition/dailyActiveUsersPerDay``).
    var activeUsersPerDay: [AdminUsageDailyCount]
    var tradesPerDay: [AdminUsageDailyCount]
    var postsPerDay: [AdminUsageDailyCount]
    var reelsPerDay: [AdminUsageDailyCount]
    var commentsPerDay: [AdminUsageDailyCount]
    var likesPerDay: [AdminUsageDailyCount]
    var followsPerDay: [AdminUsageDailyCount]
}

nonisolated struct AdminUsageAnalyticsBundle: Sendable, Hashable, Codable {
    var totalUsers: Int
    var newUsersToday: Int
    var newUsersWeek: Int
    /// Rolling last-24h distinct active users (see ``AdminUsageAnalyticsDefinition/rollingDailyActiveUsers``).
    var dailyActiveUsers: Int
    var weeklyActiveUsers: Int
    var tradesToday: Int
    var tradesWeek: Int
    var postsToday: Int
    var postsWeek: Int
    var totalTrades: Int
    var totalPosts: Int
    var seriesDays: Int
    var series: AdminUsageAnalyticsSeries
}

enum AdminChartsRange: Int, CaseIterable, Identifiable, Sendable {
    case days7 = 7
    case days30 = 30
    case days90 = 90
    case days365 = 365

    var id: Int { rawValue }

    var menuLabel: String {
        switch self {
        case .days7: return "7D"
        case .days30: return "30D"
        case .days90: return "90D"
        case .days365: return "1Y"
        }
    }
}

enum AdminUsageAnalyticsDefinition {
    /// Per UTC calendar day: distinct users with ≥1 of trade, feed post, profile post, story, feedback, or support ticket created that day.
    static let dailyActiveUsersPerDay =
        "Distinct users per UTC day who created a trade, feed post, profile wall post, story, product feedback, or support ticket."

    /// Snapshot metric from RPC (`dailyActiveUsers`): rolling 24h window, same action union as web DAU.
    static let rollingDailyActiveUsers =
        "Distinct users in the last 24 hours (UTC) who created a trade, feed post, profile wall post, story, feedback submission, or support ticket."
}

nonisolated protocol AdminUsageAnalyticsRepository: Sendable {
    func fetchBundle(seriesDays: Int) async throws -> AdminUsageAnalyticsBundle
}

enum AdminUsageAnalyticsMath {
    static func totalCount(_ points: [AdminUsageDailyCount]) -> Int {
        points.reduce(0) { $0 + max(0, $1.count) }
    }

    static func averagePerDay(_ points: [AdminUsageDailyCount]) -> Double {
        guard !points.isEmpty else { return 0 }
        return Double(totalCount(points)) / Double(points.count)
    }

    static func latestDayCount(_ points: [AdminUsageDailyCount]) -> Int {
        points.last?.count ?? 0
    }
}
