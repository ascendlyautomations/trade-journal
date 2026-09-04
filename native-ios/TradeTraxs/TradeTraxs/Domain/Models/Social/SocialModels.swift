import Foundation

nonisolated enum AchievementTier: String, Hashable, Codable, Sendable {
    case bronze
    case silver
    case gold
    case platinum
}

nonisolated enum AchievementKind: String, Hashable, Codable, Sendable {
    case propFirmPayout = "prop_firm_payout"
    case liveTradingPayout = "live_trading_payout"
    case passedEvaluation = "passed_eval"
    case milestone = "milestone"
}

nonisolated struct Achievement: Hashable, Codable, Sendable, Identifiable {
    var id: AchievementID
    var ownerProfileID: ProfileID
    var kind: AchievementKind
    var title: String
    var description: String?
    var tier: AchievementTier
    var value: Money?
    var valueText: String?
    var firm: String?
    var accountID: TradingAccountID?
    var image: MediaReference?
    var isPublic: Bool
    var isFeatured: Bool
    var sortOrder: Int
    var achievedAt: Date
}

nonisolated enum LeaderboardWindow: String, Hashable, Codable, Sendable {
    case sevenDays
    case thirtyDays
    case ninetyDays
    case yearToDate
    case allTime
    case custom
}

nonisolated struct LeaderboardEntry: Hashable, Codable, Sendable, Identifiable {
    var id: ProfileID { profileID }
    var rank: Int
    var profileID: ProfileID
    var username: String
    var totalPnL: Money
    var tradeCount: Int
    var averageRiskReward: Decimal?
    /// Win rate as `0...1` over trades in the selected window.
    var winRate: Decimal?
    var profitFactor: Decimal?
    var expectancy: Decimal?
    /// Longest consecutive winning trades (`pnl > 0`) in the window.
    var winStreak: Int
    /// Share of trading days with positive net PnL (`0...100`).
    var profitPercent: Decimal?
    /// Inverse win concentration — higher means profits are less dominated by one trade (`0...100`).
    var consistency: Decimal?

    init(
        rank: Int,
        profileID: ProfileID,
        username: String,
        totalPnL: Money,
        tradeCount: Int,
        averageRiskReward: Decimal?,
        winRate: Decimal? = nil,
        profitFactor: Decimal? = nil,
        expectancy: Decimal? = nil,
        winStreak: Int = 0,
        profitPercent: Decimal? = nil,
        consistency: Decimal? = nil
    ) {
        self.rank = rank
        self.profileID = profileID
        self.username = username
        self.totalPnL = totalPnL
        self.tradeCount = tradeCount
        self.averageRiskReward = averageRiskReward
        self.winRate = winRate
        self.profitFactor = profitFactor
        self.expectancy = expectancy
        self.winStreak = winStreak
        self.profitPercent = profitPercent
        self.consistency = consistency
    }
}

nonisolated enum SearchResultKind: String, Hashable, Codable, Sendable {
    case profile
    case trade
    case room
    case post
}

nonisolated struct SearchResult: Hashable, Codable, Sendable, Identifiable {
    var id: String
    var kind: SearchResultKind
    var title: String
    var subtitle: String?
    var profileID: ProfileID?
    var tradeID: TradeID?
    var roomID: RoomID?
    var postID: PostID?
}

nonisolated struct Referral: Hashable, Codable, Sendable, Identifiable {
    var id: ReferralID
    var referrerProfileID: ProfileID
    var code: String
    var inviteeProfileID: ProfileID?
    var rewardDescription: String?
    var createdAt: Date
    var completedAt: Date?
}
