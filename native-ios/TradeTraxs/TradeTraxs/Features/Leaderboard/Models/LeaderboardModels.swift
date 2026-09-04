import Foundation

/// Audience scope for the Leaderboards screen (presentation filter over ranked rows).
enum LeaderboardAudience: String, CaseIterable, Hashable, Sendable {
    case all
    case friends
    case following

    var title: String {
        switch self {
        case .all: return "All"
        case .friends: return "Friends"
        case .following: return "Following"
        }
    }
}

/// Time window selector — maps onto existing ``LeaderboardWindow`` for repository calls.
enum LeaderboardTimeframe: String, CaseIterable, Hashable, Sendable {
    case today
    case week
    case month
    case year
    case allTime

    var title: String {
        switch self {
        case .today: return "Today"
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        case .allTime: return "All Time"
        }
    }

    var repositoryWindow: LeaderboardWindow {
        switch self {
        case .today: return .custom
        case .week: return .sevenDays
        case .month: return .thirtyDays
        case .year: return .yearToDate
        case .allTime: return .allTime
        }
    }

    /// Calendar day in the current time zone (used when window is `.custom` / Today).
    var customInterval: DateIntervalValue? {
        guard self == .today else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return DateIntervalValue(start: start, end: end)
    }
}

/// Ranking / display metric. Sorting uses fields already available from the leaderboard
/// backend + hydrated social counts — no new ranking algorithms.
enum LeaderboardCategory: String, CaseIterable, Hashable, Sendable {
    case pnl
    case winRate
    case profitFactor
    case expectancy
    case rr
    case winStreak
    case profitPercent
    case followers
    case consistency

    var title: String {
        switch self {
        case .pnl: return "PnL"
        case .winRate: return "Win Rate"
        case .profitFactor: return "Profit Factor"
        case .expectancy: return "Expectancy"
        case .rr: return "RR"
        case .winStreak: return "Win Streak"
        case .profitPercent: return "Profit %"
        case .followers: return "Followers"
        case .consistency: return "Consistency"
        }
    }
}

enum LeaderboardTrend: Hashable, Sendable {
    case up
    case down
    case flat
}

/// Hydrated row for rendering — built by ``LeaderboardBootstrap``, never fetched by child views.
struct LeaderboardRow: Hashable, Identifiable, Sendable {
    var id: ProfileID { profileID }
    var rank: Int
    var profileID: ProfileID
    var profile: Profile
    var isVerified: Bool
    var primaryMetricText: String
    var secondaryMetricText: String
    var trend: LeaderboardTrend
    var totalPnL: Money
    var tradeCount: Int
    var averageRiskReward: Decimal?
    var winRate: Decimal?
    var profitFactor: Decimal?
    var expectancy: Decimal?
    var winStreak: Int
    var profitPercent: Decimal?
    var consistency: Decimal?
    var followerCount: Int
    var isFollowing: Bool
    var isCurrentUser: Bool

    /// Sort key for the selected category (higher is better).
    func sortValue(for category: LeaderboardCategory) -> Decimal {
        switch category {
        case .pnl:
            return totalPnL.amount
        case .winRate:
            return winRate ?? Decimal(-999_999)
        case .profitFactor:
            // Unavailable PF ("—") always sorts below calculable values.
            return profitFactor ?? Decimal(-999_999)
        case .expectancy:
            return expectancy ?? Decimal(-999_999)
        case .rr:
            return averageRiskReward ?? Decimal(-999_999)
        case .winStreak:
            return Decimal(winStreak)
        case .profitPercent:
            return profitPercent ?? Decimal(-999_999)
        case .consistency:
            return consistency ?? Decimal(-999_999)
        case .followers:
            return Decimal(followerCount)
        }
    }
}
