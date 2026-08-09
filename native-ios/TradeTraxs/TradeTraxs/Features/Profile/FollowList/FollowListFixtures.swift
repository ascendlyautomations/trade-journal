import Foundation

/// Deterministic follow-list rows for DEBUG development sessions / screenshots.
enum FollowListFixtures {
    /// Lookup a fixture row by ID (Followers / Following → unified Profile).
    static func profile(id: ProfileID) -> Profile? {
        let owner = ProfileID("dev.fixture-owner")
        return (followers(owner: owner) + following(owner: owner))
            .first { $0.id == id }
    }

    static func followers(owner: ProfileID) -> [Profile] {
        [
            make(id: "dev.follower.ada", username: "ada", name: "Ada Lovelace", creator: true),
            make(id: "dev.follower.grace", username: "grace", name: "Grace Hopper", creator: false),
            make(id: "dev.follower.alan", username: "turing", name: "Alan Turing", creator: true),
            make(id: "dev.follower.kate", username: "kate", name: "Kate Crawford", creator: false),
            make(id: "dev.follower.linus", username: "linus", name: "Linus Torvalds", creator: false),
        ]
    }

    static func following(owner: ProfileID) -> [Profile] {
        [
            make(id: "dev.following.nq", username: "nqdesk", name: "NQ Desk", creator: true),
            make(id: "dev.following.ict", username: "ict", name: "Inner Circle", creator: true),
            make(id: "dev.following.risk", username: "riskfirst", name: "Risk First", creator: false),
            make(id: "dev.follower.ada", username: "ada", name: "Ada Lovelace", creator: true),
        ]
    }

    private static func make(
        id: String,
        username: String,
        name: String,
        creator: Bool
    ) -> Profile {
        let started = Calendar.current.date(byAdding: .month, value: -30, to: Date())
        return Profile(
            id: ProfileID(id),
            userID: UserID(id),
            username: username,
            displayName: name,
            bio: "Public trader on TradeTraxs.",
            avatar: nil,
            traderType: .futures,
            tradingStyle: "ICT",
            primaryMarket: "NQ",
            startedTradingAt: started,
            isPrivate: false,
            isCreator: creator,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
