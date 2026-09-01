import Foundation

/// Web `TRADER_TYPE_OPTIONS` — stored/displayed as title case (`Futures`, `Options`, `Investor`).
nonisolated enum TraderType: String, Hashable, Codable, Sendable {
    case futures = "Futures"
    case options = "Options"
    case investor = "Investor"

    /// Accepts web title-case and legacy lowercase raw values.
    static func parse(_ raw: String?) -> TraderType? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = TraderType(rawValue: trimmed) { return exact }
        switch trimmed.lowercased() {
        case "futures": return .futures
        case "options": return .options
        case "investor": return .investor
        default: return nil
        }
    }
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

extension Profile {
    /// Merge a newer cache seed without dropping richer fields such as avatars.
    nonisolated func mergingCachedPresentation(with incoming: Profile) -> Profile {
        guard id == incoming.id else { return incoming }
        var merged = self
        merged.avatar = incoming.avatar ?? merged.avatar
        if !incoming.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.username = incoming.username
        }
        if !incoming.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.displayName = incoming.displayName
        }
        merged.bio = incoming.bio ?? merged.bio
        merged.traderType = incoming.traderType ?? merged.traderType
        merged.tradingStyle = incoming.tradingStyle ?? merged.tradingStyle
        merged.primaryMarket = incoming.primaryMarket ?? merged.primaryMarket
        merged.startedTradingAt = incoming.startedTradingAt ?? merged.startedTradingAt
        merged.isPrivate = incoming.isPrivate
        merged.isCreator = incoming.isCreator || merged.isCreator
        return merged
    }
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
    /// Count of `profile_posts` rows (web Profile wall).
    var postCount: Int
    /// Legacy total (unused by Profile overview). Prefer ``publicTradeCount``.
    var tradeCount: Int
    /// Public non-backtest trade count — mirrors web overview `Trades`.
    var publicTradeCount: Int
    /// Public non-backtest win rate as `0...1` (web displays ×100).
    var winRate: Decimal? = nil
    /// Public non-backtest profit factor; `nil` when there are no losses (web).
    var profitFactor: Decimal? = nil
    /// Public non-backtest net PnL (web overview).
    var netPnL: Decimal? = nil
    /// Mean stored RR over public non-backtest trades with finite RR (web Avg RR).
    var averageRR: Decimal? = nil
    /// Sum of payout achievement values — web overview `overviewPayoutTotal`.
    var payoutTotal: Decimal? = nil
    /// Not on web Profile — kept for forward compatibility; always `nil` today.
    var expectancy: Decimal? = nil
}

extension ProfileStats {
    /// True when overview metrics were computed from summary trades (REST aggregation).
    /// Session bootstrap stubs leave ``winRate`` nil.
    var hasLoadedHeaderMetrics: Bool {
        winRate != nil
    }

    /// Prefer richer cached header metrics over partial session projections.
    func mergingRicher(with incoming: ProfileStats) -> ProfileStats {
        guard profileID == incoming.profileID else { return self }
        if hasLoadedHeaderMetrics, !incoming.hasLoadedHeaderMetrics {
            var merged = self
            if incoming.followerCount > 0 { merged.followerCount = incoming.followerCount }
            if incoming.followingCount > 0 { merged.followingCount = incoming.followingCount }
            merged.postCount = max(merged.postCount, incoming.postCount)
            merged.publicTradeCount = max(merged.publicTradeCount, incoming.publicTradeCount)
            merged.tradeCount = max(merged.tradeCount, incoming.tradeCount)
            return merged
        }
        return incoming
    }
}
