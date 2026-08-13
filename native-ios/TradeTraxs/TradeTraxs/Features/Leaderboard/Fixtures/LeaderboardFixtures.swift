import Foundation

enum LeaderboardFixtures {
    /// Dated public trades so Today / Week / Month / Year / All Time diverge (web filter parity).
    static func trades(viewerID: ProfileID) -> [LeaderboardTradeRow] {
        let now = Date()
        func iso(_ date: Date) -> String {
            ISO8601DateFormatter().string(from: date)
        }

        var rows: [LeaderboardTradeRow] = []

        // Alex — strong all-time, also active this week
        rows.append(contentsOf: [
            row("dev.lb.alex", 12_000, 2.4, iso(now.addingTimeInterval(-86_400 * 2))),
            row("dev.lb.alex", 8_000, 2.1, iso(now.addingTimeInterval(-86_400 * 40))),
            row("dev.lb.alex", 28_220, 2.6, iso(now.addingTimeInterval(-86_400 * 200))),
        ])

        // Mia — dominates today only
        rows.append(contentsOf: [
            row("dev.lb.mia", 20_000, 1.9, iso(now.addingTimeInterval(-3_600))),
            row("dev.lb.mia", 16_110, 1.8, iso(now.addingTimeInterval(-86_400 * 120))),
        ])

        // Sam — month window strength
        rows.append(contentsOf: [
            row("dev.lb.sam", 15_000, 2.0, iso(now.addingTimeInterval(-86_400 * 10))),
            row("dev.lb.sam", 14_840, 2.2, iso(now.addingTimeInterval(-86_400 * 80))),
        ])

        // Jordan — older YTD / all-time
        rows.append(row("dev.lb.jordan", 22_450, 1.6, iso(now.addingTimeInterval(-86_400 * 60))))
        rows.append(row("dev.lb.riley", 18_920, 2.8, iso(now.addingTimeInterval(-86_400 * 5))))
        rows.append(row("dev.lb.casey", 14_300, 1.4, iso(now.addingTimeInterval(-86_400 * 15))))
        rows.append(row("dev.lb.drew", 11_780, 1.8, iso(now.addingTimeInterval(-86_400 * 25))))
        rows.append(row("dev.lb.quinn", 9_640, 2.0, iso(now.addingTimeInterval(-86_400 * 3))))
        rows.append(row(viewerID.rawValue, 7_210, 1.5, iso(now.addingTimeInterval(-86_400 * 8))))
        rows.append(row("dev.lb.skyler", 5_880, 1.2, iso(now.addingTimeInterval(-86_400 * 400))))

        return rows
    }

    static func entries(viewerID: ProfileID) -> [LeaderboardEntry] {
        LeaderboardTradeWindowFilter.entries(
            from: trades(viewerID: viewerID),
            window: .thirtyDays,
            interval: nil,
            page: PageRequest(limit: 50)
        ).items
    }

    static func profiles(from entries: [LeaderboardEntry]) -> [ProfileID: Profile] {
        var map: [ProfileID: Profile] = [:]
        for entry in entries {
            let id = entry.profileID.rawValue
            let name: String
            if id.contains("alex") { name = "Alex Rivera" }
            else if id.contains("mia") { name = "Mia Chen" }
            else if id.contains("sam") { name = "Sam Okonkwo" }
            else if id.contains("jordan") { name = "Jordan Lee" }
            else if id.contains("riley") { name = "Riley Nguyen" }
            else if id.contains("casey") { name = "Casey Brooks" }
            else if id.contains("drew") { name = "Drew Patel" }
            else if id.contains("quinn") { name = "Quinn Morales" }
            else if id.contains("skyler") { name = "Skyler Hart" }
            else { name = "You" }
            let username = id.hasPrefix("dev.lb.")
                ? String(id.dropFirst("dev.lb.".count))
                : entry.username
            map[entry.profileID] = Profile(
                id: entry.profileID,
                userID: UserID(entry.profileID.rawValue),
                username: username,
                displayName: name,
                bio: nil,
                avatar: nil,
                traderType: .futures,
                tradingStyle: "Day Trader",
                primaryMarket: "ES",
                startedTradingAt: nil,
                isPrivate: false,
                isCreator: entry.rank <= 3,
                createdAt: .now.addingTimeInterval(-86_400 * 90)
            )
        }
        return map
    }

    static func followerCounts(from entries: [LeaderboardEntry]) -> [ProfileID: Int] {
        Dictionary(uniqueKeysWithValues: entries.map { entry in
            (entry.profileID, max(120, 2_400 - entry.rank * 180))
        })
    }

    private static func row(
        _ userID: String,
        _ pnl: Decimal,
        _ rr: Decimal,
        _ createdAt: String
    ) -> LeaderboardTradeRow {
        LeaderboardTradeRow(
            userID: userID,
            pnl: pnl,
            rr: rr,
            createdAt: createdAt,
            accountType: "live",
            mode: "live"
        )
    }
}
