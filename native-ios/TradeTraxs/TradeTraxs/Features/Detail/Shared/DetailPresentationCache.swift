import Foundation
import Observation

/// In-memory seeds for detail destinations — avoids re-fetching list entities already held.
///
/// List containers write on load / open; detail ViewModels read first, then lazy-load
/// supplementary fields (notes, images, video URL) only when needed.
@Observable
@MainActor
final class DetailPresentationCache {
    private var trades: [TradeID: Trade] = [:]
    private var posts: [PostID: Post] = [:]
    private var reels: [ReelID: Reel] = [:]
    private var achievements: [AchievementID: Achievement] = [:]
    private var storiesByID: [StoryID: Story] = [:]
    private var profilesByID: [ProfileID: Profile] = [:]
    private var statsByProfile: [ProfileID: ProfileStats] = [:]
    private var ownedTradeRooms: [ProfileID: TradeRoom] = [:]
    private var ownedTradeRoomResolved: Set<ProfileID> = []
    private var accountNames: [TradingAccountID: String] = [:]
    private var accountNumbers: [TradingAccountID: String] = [:]
    private var accountModes: [TradingAccountID: TradingAccountMode] = [:]
    private var accountSizes: [TradingAccountID: Decimal] = [:]
    /// Full `accounts` rows keyed by profile — session reuse for Stats / Detail.
    private var accountsByProfile: [ProfileID: [TradingAccount]] = [:]
    /// Public trades list last seeded for a profile (Profile Trades / Stats share).
    private var publicTradesByProfile: [ProfileID: [Trade]] = [:]
    /// Session Followers / Following lists (web `followListCache` parity).
    private var followersByProfile: [ProfileID: [Profile]] = [:]
    private var followingByProfile: [ProfileID: [Profile]] = [:]
    /// Profiles the authenticated viewer currently follows — drives Follow / Following buttons.
    /// Only set when a **complete** following list is known (Follow list screen).
    private var viewerFollowingIDSet: Set<ProfileID>?
    /// Per-profile follow edges from pairwise `followState` / toggle — never treated as a full list.
    private var viewerFollowEdgeByProfile: [ProfileID: Bool] = [:]

    func seed(_ profile: Profile) {
        if let existing = profilesByID[profile.id] {
            profilesByID[profile.id] = existing.mergingCachedPresentation(with: profile)
        } else {
            profilesByID[profile.id] = profile
        }
    }

    func profile(id: ProfileID) -> Profile? {
        profilesByID[id]
    }

    func seed(stats: ProfileStats) {
        if let existing = statsByProfile[stats.profileID] {
            statsByProfile[stats.profileID] = existing.mergingRicher(with: stats)
        } else {
            statsByProfile[stats.profileID] = stats
        }
    }

    func stats(for profileID: ProfileID) -> ProfileStats? {
        statsByProfile[profileID]
    }

    /// Seeds owned-room resolution. Pass `nil` when the profile owns no room.
    func seedOwnedTradeRoom(_ room: TradeRoom?, for profileID: ProfileID) {
        ownedTradeRoomResolved.insert(profileID)
        if let room {
            ownedTradeRooms[profileID] = room
        } else {
            ownedTradeRooms.removeValue(forKey: profileID)
        }
    }

    func hasResolvedOwnedTradeRoom(for profileID: ProfileID) -> Bool {
        ownedTradeRoomResolved.contains(profileID)
    }

    func ownedTradeRoom(for profileID: ProfileID) -> TradeRoom? {
        ownedTradeRooms[profileID]
    }

    func seed(_ trade: Trade) {
        trades[trade.id] = trade
    }

    func seed(trades items: [Trade]) {
        for trade in items {
            trades[trade.id] = trade
        }
    }

    func seed(_ post: Post) {
        posts[post.id] = post
    }

    func seed(posts items: [Post]) {
        for post in items {
            posts[post.id] = post
        }
    }

    func seed(_ reel: Reel) {
        reels[reel.id] = reel
    }

    func seed(reels items: [Reel]) {
        for reel in items {
            reels[reel.id] = reel
        }
    }

    func seed(_ achievement: Achievement) {
        achievements[achievement.id] = achievement
    }

    func seed(achievements items: [Achievement]) {
        for achievement in items {
            achievements[achievement.id] = achievement
        }
    }

    func seed(_ story: Story) {
        storiesByID[story.id] = story
    }

    func seed(stories items: [Story]) {
        for story in items {
            storiesByID[story.id] = story
        }
    }

    func story(id: StoryID) -> Story? {
        storiesByID[id]
    }

    func seedAccountName(_ name: String, for accountID: TradingAccountID) {
        accountNames[accountID] = name
    }

    func seed(accountNames names: [TradingAccountID: String]) {
        for (id, name) in names {
            accountNames[id] = name
        }
    }

    func seed(accountModes modes: [TradingAccountID: TradingAccountMode]) {
        for (id, mode) in modes {
            accountModes[id] = mode
        }
    }

    func seed(accountSizes sizes: [TradingAccountID: Decimal]) {
        for (id, size) in sizes {
            accountSizes[id] = size
        }
    }

    /// Seeds public-safe account labels for profile/shared surfaces — never account numbers.
    func seedPublicAccountMetadata(
        names: [TradingAccountID: String],
        modes: [TradingAccountID: TradingAccountMode],
        sizes: [TradingAccountID: Decimal] = [:],
        for profileID: ProfileID
    ) {
        let sanitizedNames = Dictionary(
            uniqueKeysWithValues: names.map { id, name in
                (
                    id,
                    PublicAccountPrivacy.publicSafeAccountName(
                        rawName: name,
                        accountNumber: nil,
                        category: nil,
                        mode: modes[id]
                    )
                )
            }
        )
        seed(accountNames: sanitizedNames)
        seed(accountModes: modes)
        seed(accountSizes: sizes)
        purgeAccountNumbers(for: Array(names.keys))
    }

    /// Owner-only full account rows — never use for visitor profiles or public caches.
    func seedOwnerAccounts(_ accounts: [TradingAccount], for profileID: ProfileID) {
        accountsByProfile[profileID] = accounts
        seed(accounts: accounts)
    }

    func purgeAccountNumbers(for accountIDs: [TradingAccountID]) {
        for id in accountIDs {
            accountNumbers[id] = nil
        }
    }

    func purgeAllAccountNumbers() {
        accountNumbers = [:]
    }

    /// Seeds name / mode / size / number from linked `accounts` rows (owner contexts only).
    func seed(accounts: [TradingAccount]) {
        seed(accountNames: Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) }))
        seed(accountModes: Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.mode) }))
        let sizes = accounts.compactMap { account -> (TradingAccountID, Decimal)? in
            guard let amount = account.size?.amount else { return nil }
            return (account.id, amount)
        }
        seed(accountSizes: Dictionary(uniqueKeysWithValues: sizes))
        let numbers = accounts.compactMap { account -> (TradingAccountID, String)? in
            guard let number = TradingAccountDisplay.normalizedAccountNumber(account.accountNumber) else {
                return nil
            }
            return (account.id, number)
        }
        seed(accountNumbers: Dictionary(uniqueKeysWithValues: numbers))
    }

    func seed(accountNumbers numbers: [TradingAccountID: String]) {
        for (id, number) in numbers {
            accountNumbers[id] = number
        }
    }

    /// Seeds accounts for a profile and marks the profile as resolved for the session.
    func seed(accounts: [TradingAccount], for profileID: ProfileID) {
        accountsByProfile[profileID] = accounts
        seed(accounts: accounts)
    }

    /// Public profile path — sanitized labels only; strips any prior owner numbers.
    func seedPublicProfileAccounts(_ accounts: [TradingAccount], for profileID: ProfileID) {
        accountsByProfile[profileID] = accounts.map { account in
            var copy = account
            copy.accountNumber = nil
            copy.name = PublicAccountPrivacy.publicSafeAccountName(for: account)
            return copy
        }
        seedPublicAccountMetadata(
            names: Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) }),
            modes: Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.mode) }),
            sizes: Dictionary(
                uniqueKeysWithValues: accounts.compactMap { account -> (TradingAccountID, Decimal)? in
                    guard let amount = account.size?.amount else { return nil }
                    return (account.id, amount)
                }
            ),
            for: profileID
        )
    }

    func accounts(for profileID: ProfileID) -> [TradingAccount]? {
        accountsByProfile[profileID]
    }

    func hasAccounts(for profileID: ProfileID) -> Bool {
        accountsByProfile[profileID] != nil
    }

    func seed(publicTrades items: [Trade], for profileID: ProfileID) {
        publicTradesByProfile[profileID] = items
        seed(trades: items)
    }

    func publicTrades(for profileID: ProfileID) -> [Trade]? {
        publicTradesByProfile[profileID]
    }

    func seed(followers items: [Profile], for profileID: ProfileID) {
        followersByProfile[profileID] = items
    }

    func followers(for profileID: ProfileID) -> [Profile]? {
        followersByProfile[profileID]
    }

    func seed(following items: [Profile], for profileID: ProfileID) {
        followingByProfile[profileID] = items
    }

    func following(for profileID: ProfileID) -> [Profile]? {
        followingByProfile[profileID]
    }

    func seedViewerFollowingIDs(_ ids: Set<ProfileID>) {
        viewerFollowingIDSet = ids
        for id in ids {
            viewerFollowEdgeByProfile[id] = true
        }
    }

    func viewerFollowingIDs() -> Set<ProfileID>? {
        viewerFollowingIDSet
    }

    /// Pairwise follow edge for one profile (safe for Profile header Follow).
    func viewerFollowEdge(for profileID: ProfileID) -> Bool? {
        viewerFollowEdgeByProfile[profileID]
    }

    func setViewerFollows(_ profileID: ProfileID, isFollowing: Bool) {
        viewerFollowEdgeByProfile[profileID] = isFollowing
        // Only mutate the complete following set when it already exists.
        guard var ids = viewerFollowingIDSet else { return }
        if isFollowing {
            ids.insert(profileID)
        } else {
            ids.remove(profileID)
        }
        viewerFollowingIDSet = ids
    }

    func trade(id: TradeID) -> Trade? {
        trades[id]
    }

    func post(id: PostID) -> Post? {
        posts[id]
    }

    func reel(id: ReelID) -> Reel? {
        reels[id]
    }

    func achievement(id: AchievementID) -> Achievement? {
        achievements[id]
    }

    // MARK: - Feed engagement overrides (detail opened from Home feed)

    private var feedEngagementTargetByTradeID: [TradeID: InteractionTarget] = [:]
    private var feedEngagementTargetByAchievementID: [AchievementID: InteractionTarget] = [:]

    /// Web feed trade cards like/comment on `posts.id`, not `trades.id`.
    func seedFeedEngagementTarget(_ target: InteractionTarget, forTrade tradeID: TradeID) {
        feedEngagementTargetByTradeID[tradeID] = target
    }

    func feedEngagementTarget(forTrade tradeID: TradeID) -> InteractionTarget? {
        feedEngagementTargetByTradeID[tradeID]
    }

    /// Feed achievement rows use `achievement_posts.id`; profile lists use `achievements.id`.
    func seedFeedEngagementTarget(_ target: InteractionTarget, forAchievement achievementID: AchievementID) {
        feedEngagementTargetByAchievementID[achievementID] = target
    }

    func feedEngagementTarget(forAchievement achievementID: AchievementID) -> InteractionTarget? {
        feedEngagementTargetByAchievementID[achievementID]
    }

    func accountName(for accountID: TradingAccountID) -> String? {
        accountNames[accountID]
    }

    func accountNumber(for accountID: TradingAccountID) -> String? {
        accountNumbers[accountID]
    }

    func accountMode(for accountID: TradingAccountID) -> TradingAccountMode? {
        accountModes[accountID]
    }

    func accountSize(for accountID: TradingAccountID) -> Decimal? {
        accountSizes[accountID]
    }

    /// Clear trade list seeds after CSV import so Dashboard / Profile refetch.
    func invalidateJournalLists() {
        trades = [:]
        publicTradesByProfile = [:]
        statsByProfile = [:]
    }

    /// Remove one trade from detail + public profile list seeds (delete path).
    func removeTrade(id: TradeID) {
        trades[id] = nil
        for key in publicTradesByProfile.keys {
            publicTradesByProfile[key]?.removeAll { $0.id == id }
        }
        statsByProfile = [:]
    }

    func removePost(id: PostID) {
        posts[id] = nil
    }

    func removeReel(id: ReelID) {
        reels[id] = nil
    }

    /// Drop all session seeds when the authenticated user changes.
    func removeAll() {
        trades = [:]
        posts = [:]
        reels = [:]
        achievements = [:]
        storiesByID = [:]
        profilesByID = [:]
        statsByProfile = [:]
        ownedTradeRooms = [:]
        ownedTradeRoomResolved = []
        accountNames = [:]
        accountNumbers = [:]
        accountModes = [:]
        accountSizes = [:]
        accountsByProfile = [:]
        publicTradesByProfile = [:]
        followersByProfile = [:]
        followingByProfile = [:]
        viewerFollowingIDSet = nil
        viewerFollowEdgeByProfile = [:]
        feedEngagementTargetByTradeID = [:]
        feedEngagementTargetByAchievementID = [:]
    }
}
