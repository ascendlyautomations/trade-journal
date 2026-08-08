import Foundation

nonisolated enum AchievementTier: String, Hashable, Codable, Sendable {
    case bronze
    case silver
    case gold
    case platinum
}

nonisolated enum AchievementKind: String, Hashable, Codable, Sendable {
    case propFirmPayout
    case liveTradingPayout
    case passedEvaluation
    case milestone
}

nonisolated struct Achievement: Hashable, Codable, Sendable, Identifiable {
    var id: AchievementID
    var ownerProfileID: ProfileID
    var kind: AchievementKind
    var title: String
    var tier: AchievementTier
    var value: Money?
    var accountID: TradingAccountID?
    var image: MediaReference?
    var isPublic: Bool
    var isFeatured: Bool
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
