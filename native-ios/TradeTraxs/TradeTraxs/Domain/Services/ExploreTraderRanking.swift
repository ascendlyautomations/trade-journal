import Foundation

/// Port of web `scoreActiveTrader` — completeness + optional activity signals, no ML.
enum ExploreTraderRanking {
    struct TradeSummary: Hashable, Sendable {
        var tradeCount: Int
        var lastTradeAt: Date?
    }

    struct PostSummary: Hashable, Sendable {
        var postCount: Int
        var lastPostAt: Date?
    }

    static func score(
        profile: Profile,
        trades: TradeSummary? = nil,
        posts: PostSummary? = nil,
        now: Date = .now
    ) -> Int {
        var score = 0
        if !profile.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 1 }
        if profile.avatar != nil { score += 2 }
        if let bio = profile.bio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
            score += 2
        }
        if !profile.isPrivate { score += 1 }
        if profile.traderType != nil { score += 1 }
        if let style = profile.tradingStyle?.trimmingCharacters(in: .whitespacesAndNewlines), !style.isEmpty {
            score += 1
        }
        if let market = profile.primaryMarket?.trimmingCharacters(in: .whitespacesAndNewlines), !market.isEmpty {
            score += 1
        }
        if profile.startedTradingAt != nil { score += 1 }

        if let trades, trades.tradeCount > 0 { score += 3 }
        if let last = trades?.lastTradeAt, isRecent(last, days: 30, now: now) { score += 4 }

        if let posts, posts.postCount > 0 { score += 1 }
        if let last = posts?.lastPostAt, isRecent(last, days: 30, now: now) { score += 1 }

        return score
    }

    static func identityLine(for profile: Profile) -> String? {
        var parts: [String] = []
        if let type = profile.traderType {
            parts.append(type.rawValue)
        }
        if let style = profile.tradingStyle?.trimmingCharacters(in: .whitespacesAndNewlines), !style.isEmpty {
            parts.append(style)
        }
        if let market = profile.primaryMarket?.trimmingCharacters(in: .whitespacesAndNewlines), !market.isEmpty {
            parts.append(market)
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    static func rank(
        profiles: [Profile],
        tradeSummaries: [ProfileID: TradeSummary] = [:],
        postSummaries: [ProfileID: PostSummary] = [:],
        followerCounts: [ProfileID: Int] = [:],
        excluding: Set<ProfileID> = [],
        limit: Int = 16,
        minScore: Int = 3,
        now: Date = .now
    ) -> [ExploreTraderSuggestion] {
        profiles
            .filter { profile in
                !excluding.contains(profile.id)
                    && !profile.isPrivate
                    && !profile.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .map { profile in
                let score = score(
                    profile: profile,
                    trades: tradeSummaries[profile.id],
                    posts: postSummaries[profile.id],
                    now: now
                )
                let activity = max(
                    tradeSummaries[profile.id]?.lastTradeAt?.timeIntervalSince1970 ?? 0,
                    postSummaries[profile.id]?.lastPostAt?.timeIntervalSince1970 ?? 0,
                    profile.createdAt.timeIntervalSince1970
                )
                return (profile, score, activity)
            }
            .filter { $0.1 >= minScore }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.2 > rhs.2
            }
            .prefix(limit)
            .map { profile, score, _ in
                ExploreTraderSuggestion(
                    profile: profile,
                    followerCount: followerCounts[profile.id] ?? 0,
                    score: score,
                    identityLine: identityLine(for: profile)
                )
            }
    }

    private static func isRecent(_ date: Date, days: Int, now: Date) -> Bool {
        now.timeIntervalSince(date) <= Double(days) * 24 * 60 * 60
    }
}
