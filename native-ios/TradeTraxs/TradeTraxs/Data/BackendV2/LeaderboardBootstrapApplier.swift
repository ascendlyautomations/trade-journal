import Foundation

nonisolated enum LeaderboardBootstrapApplier {
    private struct RowWire: Codable, Sendable {
        var profile_id: String
        var username: String?
        var display_name: String?
        var avatar_url: String?
        var follower_count: Int?
        var total_pnl: PostgresFlexibleDouble?
        var trade_count: Int?
        var avg_rr: PostgresFlexibleDouble?
        var win_rate: PostgresFlexibleDouble?
        var profit_factor: PostgresFlexibleDouble?
        var expectancy: PostgresFlexibleDouble?
        var win_streak: Int?
        var profit_percent: PostgresFlexibleDouble?
        var consistency: PostgresFlexibleDouble?
    }

    struct Applied: Sendable {
        var entries: [LeaderboardEntry]
        var profiles: [ProfileID: Profile]
        var followers: [ProfileID: Int]
        var nextCursor: String?
    }

    nonisolated static func apply(
        _ bootstrap: LeaderboardBootstrapV1,
        rankOffset: Int
    ) -> Applied {
        var entries: [LeaderboardEntry] = []
        var profiles: [ProfileID: Profile] = [:]
        var followers: [ProfileID: Int] = [:]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for (index, raw) in bootstrap.data.rows.enumerated() {
            guard let data = try? encoder.encode(raw),
                  let wire = try? decoder.decode(RowWire.self, from: data)
            else { continue }

            let profileID = ProfileID(wire.profile_id)
            let username = wire.username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let display = wire.display_name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let avatarURL = wire.avatar_url?.trimmingCharacters(in: .whitespacesAndNewlines)

            let profile = Profile(
                id: profileID,
                userID: UserID(profileID.rawValue),
                username: username.isEmpty ? profileID.rawValue : username,
                displayName: (display?.isEmpty == false) ? display! : (username.isEmpty ? profileID.rawValue : username),
                bio: nil,
                avatar: avatarURL.flatMap { url in
                    url.isEmpty ? nil : MediaReference(id: url, kind: .image, altText: nil)
                },
                traderType: nil,
                tradingStyle: nil,
                primaryMarket: nil,
                startedTradingAt: nil,
                isPrivate: false,
                isCreator: false,
                createdAt: .now
            )
            profiles[profileID] = LeaderboardTradeIdentity.mergeLeaderboardProfile(
                existing: profiles[profileID],
                fetched: profile
            )

            if let count = wire.follower_count {
                followers[profileID] = count
            }

            let entry = LeaderboardEntry(
                rank: rankOffset + index + 1,
                profileID: profileID,
                username: username,
                totalPnL: Money(amount: wire.total_pnl?.decimal ?? 0),
                tradeCount: wire.trade_count ?? 0,
                averageRiskReward: wire.avg_rr?.decimal,
                winRate: wire.win_rate?.decimal,
                profitFactor: wire.profit_factor?.decimal,
                expectancy: wire.expectancy?.decimal,
                winStreak: wire.win_streak ?? 0,
                profitPercent: wire.profit_percent?.decimal,
                consistency: wire.consistency?.decimal
            )
            entries.append(entry)
        }

        return Applied(
            entries: entries,
            profiles: profiles,
            followers: followers,
            nextCursor: bootstrap.data.next_cursor
        )
    }
}
