import Foundation

nonisolated enum TraderType: String, Hashable, Codable, Sendable {
    case futures
    case options
    case investor
}

nonisolated enum FollowState: String, Hashable, Codable, Sendable {
    case none
    case following
    case requested
}

/// Authenticated identity (auth subject). Not a social profile.
nonisolated struct User: Hashable, Codable, Sendable, Identifiable {
    var id: UserID
    var email: String?
    var createdAt: Date
}

/// Public / social persona owned by a user.
nonisolated struct Profile: Hashable, Codable, Sendable, Identifiable {
    var id: ProfileID
    var userID: UserID
    var username: String
    var displayName: String
    var bio: String?
    var avatar: MediaReference?
    var traderType: TraderType?
    var tradingStyle: String?
    var primaryMarket: String?
    var startedTradingAt: Date?
    var isPrivate: Bool
    var isCreator: Bool
    var createdAt: Date
}

nonisolated struct Creator: Hashable, Codable, Sendable, Identifiable {
    var id: ProfileID
    var profileID: ProfileID
    var isVerified: Bool
    var headline: String?
}

nonisolated struct FollowRelationship: Hashable, Codable, Sendable {
    var followerID: ProfileID
    var followingID: ProfileID
    var state: FollowState
    var createdAt: Date
}

nonisolated struct ProfileStats: Hashable, Codable, Sendable {
    var profileID: ProfileID
    var followerCount: Int
    var followingCount: Int
    var tradeCount: Int
    var publicTradeCount: Int
}
