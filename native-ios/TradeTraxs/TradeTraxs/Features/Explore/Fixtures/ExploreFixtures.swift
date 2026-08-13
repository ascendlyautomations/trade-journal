import Foundation

enum ExploreFixtures {
    static let viewerID = ProfileID("dev.explore.viewer")

    static func traders(excluding viewer: ProfileID = viewerID) -> [ExploreTraderSuggestion] {
        let profiles = [
            makeProfile(id: "dev.explore.alex", username: "alexfutures", name: "Alex Rivera", type: .futures, style: "Scalper"),
            makeProfile(id: "dev.explore.mia", username: "miaoptions", name: "Mia Chen", type: .options, style: "Swing"),
            makeProfile(id: "dev.explore.sam", username: "saminvest", name: "Sam Okonkwo", type: .investor, style: "Position"),
            makeProfile(id: "dev.explore.jordan", username: "jordanfx", name: "Jordan Lee", type: .futures, style: "Day Trader"),
            makeProfile(id: "dev.explore.riley", username: "rileytrades", name: "Riley Nguyen", type: .options, style: "Momentum"),
        ]
        return ExploreTraderRanking.rank(
            profiles: profiles,
            followerCounts: [
                ProfileID("dev.explore.alex"): 1280,
                ProfileID("dev.explore.mia"): 842,
                ProfileID("dev.explore.sam"): 512,
                ProfileID("dev.explore.jordan"): 390,
                ProfileID("dev.explore.riley"): 210,
            ],
            excluding: [viewer],
            limit: 12,
            minScore: 1
        )
    }

    static func rooms() -> [ExploreRoomSuggestion] {
        [
            ExploreRoomSuggestion(
                id: RoomID("dev.explore.room.futures"),
                name: "Futures Desk",
                slug: "futures-desk",
                description: "Open discussion for index and commodity futures.",
                memberCount: 1284,
                imageURL: nil
            ),
            ExploreRoomSuggestion(
                id: RoomID("dev.explore.room.options"),
                name: "Options Lab",
                slug: "options-lab",
                description: "Spreads, greeks, and weekly setups.",
                memberCount: 876,
                imageURL: nil
            ),
            ExploreRoomSuggestion(
                id: RoomID("dev.explore.room.risk"),
                name: "Risk & Psychology",
                slug: "risk-psych",
                description: "Process, journaling, and drawdown recovery.",
                memberCount: 540,
                imageURL: nil
            ),
        ]
    }

    static func seedDetailCache(_ cache: DetailPresentationCache, viewer: ProfileID = viewerID) {
        for trader in traders(excluding: viewer) {
            cache.seed(trader.profile)
        }
    }

    private static func makeProfile(
        id: String,
        username: String,
        name: String,
        type: TraderType,
        style: String
    ) -> Profile {
        Profile(
            id: ProfileID(id),
            userID: UserID(id),
            username: username,
            displayName: name,
            bio: "Sharing process and public trades.",
            avatar: nil,
            traderType: type,
            tradingStyle: style,
            primaryMarket: type == .investor ? "Equities" : "ES",
            startedTradingAt: Calendar.current.date(byAdding: .year, value: -3, to: .now),
            isPrivate: false,
            isCreator: false,
            createdAt: .now.addingTimeInterval(-86_400 * 40)
        )
    }
}
