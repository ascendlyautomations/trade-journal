import Foundation

/// Debug-only decorator: development sessions (`dev.*` user IDs) receive a local
/// profile fixture so Profile header / tab avatar can be exercised without Supabase.
nonisolated struct DevelopmentProfileRepository: ProfileRepository {
    private let base: any ProfileRepository

    init(wrapping base: any ProfileRepository) {
        self.base = base
    }

    func currentUser() async throws -> User {
        try await base.currentUser()
    }

    func profile(id: ProfileID) async throws -> Profile {
        if Self.isDevelopmentID(id) {
            return Self.fixtureProfile(id: id)
        }
        return try await base.profile(id: id)
    }

    func profiles(ids: [ProfileID]) async throws -> [Profile] {
        var result: [Profile] = []
        var remote: [ProfileID] = []
        for id in Set(ids) {
            if Self.isDevelopmentID(id) {
                result.append(Self.fixtureProfile(id: id))
            } else {
                remote.append(id)
            }
        }
        if !remote.isEmpty {
            result.append(contentsOf: try await base.profiles(ids: remote))
        }
        return result
    }

    func profile(username: String) async throws -> Profile {
        try await base.profile(username: username)
    }

    func updateProfile(_ profile: Profile) async throws -> Profile {
        if Self.isDevelopmentID(profile.id) {
            return profile
        }
        return try await base.updateProfile(profile)
    }

    func stats(for profileID: ProfileID) async throws -> ProfileStats {
        if Self.isDevelopmentID(profileID) {
            // Mirrors web overview formulas against a fixed public non-backtest set.
            let payoutTotal = ProfilePayoutTotals.sum(
                from: ProfileAchievementFixtures.samples(owner: profileID)
            )
            return ProfileStats(
                profileID: profileID,
                followerCount: 128,
                followingCount: 42,
                postCount: 18,
                tradeCount: 31,
                publicTradeCount: 31,
                winRate: Decimal(string: "0.58"),
                profitFactor: Decimal(string: "1.85"),
                netPnL: Decimal(string: "12450"),
                averageRR: Decimal(string: "2.1"),
                payoutTotal: payoutTotal,
                expectancy: nil
            )
        }
        return try await base.stats(for: profileID)
    }

    func wallPosts(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        if Self.isDevelopmentID(profileID) {
            return CursorPage(items: ProfilePostFixtures.samples(owner: profileID), nextCursor: nil)
        }
        return try await base.wallPosts(for: profileID, page: page)
    }

    func wallPost(id: PostID) async throws -> Post {
        if let fixture = ProfilePostFixtures.post(id: id) {
            return fixture
        }
        return try await base.wallPost(id: id)
    }

    func createWallPost(authorID: ProfileID, content: String, imageURL: String?) async throws -> Post {
        try await base.createWallPost(authorID: authorID, content: content, imageURL: imageURL)
    }

    func deleteWallPost(id: PostID) async throws {
        try await base.deleteWallPost(id: id)
    }

    func followState(from viewer: ProfileID, to target: ProfileID) async throws -> FollowState {
        try await base.followState(from: viewer, to: target)
    }

    func follow(from viewer: ProfileID, to target: ProfileID) async throws {
        try await base.follow(from: viewer, to: target)
    }

    func unfollow(from viewer: ProfileID, to target: ProfileID) async throws {
        try await base.unfollow(from: viewer, to: target)
    }

    func followers(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        try await base.followers(of: profileID, page: page)
    }

    func following(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        try await base.following(of: profileID, page: page)
    }

    func creator(for profileID: ProfileID) async throws -> Creator? {
        if Self.isDevelopmentID(profileID) {
            return Creator(
                id: profileID,
                profileID: profileID,
                isVerified: true,
                headline: "Native iOS development session"
            )
        }
        return try await base.creator(for: profileID)
    }

    private static func isDevelopmentID(_ id: ProfileID) -> Bool {
        id.rawValue.hasPrefix("dev.")
    }

    private static func fixtureProfile(id: ProfileID) -> Profile {
        // Mirror web profile metadata: style · trader type · market · experience.
        let started = Calendar.current.date(
            byAdding: .month,
            value: -41,
            to: Date()
        )
        return Profile(
            id: id,
            userID: UserID(id.rawValue),
            username: "tradetraxs",
            displayName: "TradeTraxs",
            bio: "Journal every trade. Improve every session.",
            avatar: nil,
            traderType: .futures,
            tradingStyle: "ICT",
            primaryMarket: "NQ",
            startedTradingAt: started,
            isPrivate: false,
            isCreator: true,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
