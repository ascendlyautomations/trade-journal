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
    private var tradeAuthority: [TradeID: TradeDetailAuthority] = [:]
    private var presentationSeeds: [TradeID: DetailPresentationSeed] = [:]
    private var posts: [PostID: Post] = [:]
    private var reels: [ReelID: Reel] = [:]
    private var reelIDByLinkedTradeID: [TradeID: ReelID] = [:]
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
    private var publicTradeSummariesByProfile: [ProfileID: [TradeSummary]] = [:]
    /// Session Followers / Following lists (web `followListCache` parity).
    private var followersByProfile: [ProfileID: [Profile]] = [:]
    private var followingByProfile: [ProfileID: [Profile]] = [:]
    /// Profiles the authenticated viewer currently follows — drives Follow / Following buttons.
    /// Only set when a **complete** following list is known (Follow list screen).
    private var viewerFollowingIDSet: Set<ProfileID>?
    /// Per-profile follow edges from pairwise `followState` / toggle — never treated as a full list.
    private var viewerFollowEdgeByProfile: [ProfileID: Bool] = [:]
    /// Pending follow request (private profiles) — never implies following.
    private var viewerFollowRequestByProfile: [ProfileID: Bool] = [:]

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

    /// List/card/bootstrap snapshot — not authoritative for detail or edit.
    func seed(_ trade: Trade) {
        seedListPreview(trade)
    }

    func seedListPreview(_ trade: Trade) {
        seedPresentationSeed(TradeSummaryMapper.presentationSeed(fromListTrade: trade))
    }

    func seedListPreviews(_ items: [Trade]) {
        for trade in items {
            seedListPreview(trade)
        }
    }

    func seed(trades items: [Trade]) {
        seedListPreviews(items)
    }

    func seedPresentationSeed(_ summary: TradeSummary) {
        seedPresentationSeed(DetailPresentationSeed(summary: summary))
    }

    /// Journal list summaries — presentation seeds only (not authoritative detail).
    func seed(journalSummaries items: [TradeOwnerJournalSummary]) {
        for item in items {
            seedPresentationSeed(TradeSummaryMapper.presentationSeed(from: item))
        }
    }

    func seedPresentationSeed(_ seed: DetailPresentationSeed) {
        presentationSeeds[seed.summary.id] = seed
        trades[seed.summary.id] = seed.previewTrade
        tradeAuthority[seed.summary.id] = .listSeed
    }

    /// Complete detail from network or successful mutation — safe for edit/detail completeness.
    func seedAuthoritativeDetail(_ detail: TradeDetail, authority: TradeDetailAuthority) {
        trades[detail.id] = detail
        tradeAuthority[detail.id] = authority
        presentationSeeds[detail.id] = nil
    }

    func presentationSeed(id: TradeID) -> DetailPresentationSeed? {
        presentationSeeds[id]
    }

    /// Feed / Calendar / Profile list card transport — never authoritative detail.
    func tradeSummary(id: TradeID) -> TradeSummary? {
        if let seed = presentationSeeds[id] {
            return seed.summary
        }
        guard let trade = trades[id] else { return nil }
        return TradeSummaryMapper.summary(fromPartialListTrade: trade)
    }

    func authoritativeDetail(id: TradeID) -> TradeDetail? {
        guard let trade = trades[id],
              TradeDetailCompleteness.isAuthoritative(tradeAuthority[id] ?? .listSeed)
        else { return nil }
        return trade
    }

    func tradeAuthority(for id: TradeID) -> TradeDetailAuthority? {
        tradeAuthority[id]
    }

    func evictAuthoritativeDetail(tradeID: TradeID) {
        if TradeDetailCompleteness.isAuthoritative(tradeAuthority[tradeID] ?? .listSeed) {
            trades[tradeID] = nil
            tradeAuthority[tradeID] = nil
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
        if let existing = reels[reel.id],
           let existingTradeID = existing.linkedTradeID,
           existingTradeID != reel.linkedTradeID
        {
            reelIDByLinkedTradeID.removeValue(forKey: existingTradeID)
        }
        reels[reel.id] = reel
        if let tradeID = reel.linkedTradeID {
            reelIDByLinkedTradeID[tradeID] = reel.id
        }
    }

    func seed(reels items: [Reel]) {
        for reel in items {
            seed(reel)
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

    func seed(publicTradeSummaries items: [TradeSummary], for profileID: ProfileID) {
        publicTradeSummariesByProfile[profileID] = items
        for item in items {
            seedPresentationSeed(DetailPresentationSeed(summary: item))
        }
    }

    func publicTrades(for profileID: ProfileID) -> [Trade]? {
        publicTradesByProfile[profileID]
    }

    func publicTradeSummaries(for profileID: ProfileID) -> [TradeSummary]? {
        publicTradeSummariesByProfile[profileID]
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
        if isFollowing {
            viewerFollowRequestByProfile[profileID] = false
        }
        // Only mutate the complete following set when it already exists.
        guard var ids = viewerFollowingIDSet else { return }
        if isFollowing {
            ids.insert(profileID)
        } else {
            ids.remove(profileID)
        }
        viewerFollowingIDSet = ids
    }

    func viewerFollowRequested(for profileID: ProfileID) -> Bool? {
        viewerFollowRequestByProfile[profileID]
    }

    func setViewerFollowRequested(_ profileID: ProfileID, isRequested: Bool) {
        viewerFollowRequestByProfile[profileID] = isRequested
        if isRequested {
            viewerFollowEdgeByProfile[profileID] = false
        }
    }

    /// Card/list preview transport — not authoritative detail (prefer ``tradeSummary(id:)``).
    func previewTrade(id: TradeID) -> Trade? {
        if let seed = presentationSeeds[id] {
            return seed.previewTrade
        }
        guard let trade = trades[id] else { return nil }
        #if DEBUG
        if !TradeDetailCompleteness.isAuthoritative(tradeAuthority[id] ?? .listSeed) {
            TradeSummaryLegacyTelemetry.legacyFullTradePath(context: "previewTrade(id:)", tradeID: id)
        }
        #endif
        return trade
    }

    func trade(id: TradeID) -> Trade? {
        guard let trade = trades[id] else { return nil }
        #if DEBUG
        if !TradeDetailCompleteness.isAuthoritative(tradeAuthority[id] ?? .listSeed) {
            TradeSummaryLegacyTelemetry.legacyFullTradePath(context: "trade(id:)", tradeID: id)
        }
        #endif
        return trade
    }

    func tradesOwnedBy(_ profileID: ProfileID) -> [Trade] {
        trades.values.filter { $0.ownerProfileID == profileID }
    }

    func post(id: PostID) -> Post? {
        posts[id]
    }

    func reel(id: ReelID) -> Reel? {
        reels[id]
    }

    func reel(linkedTo tradeID: TradeID) -> Reel? {
        guard let reelID = reelIDByLinkedTradeID[tradeID] else { return nil }
        return reels[reelID]
    }

    func achievement(id: AchievementID) -> Achievement? {
        achievements[id]
    }

    // MARK: - Feed engagement overrides (detail opened from Home feed)
    //
    // Phase 9B: Detail UI reads ``EngagementStore`` for like/comment presentation — DPC stores
    // feed-vs-trade target routing only, not duplicate engagement counts.

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
        publicTradeSummariesByProfile = [:]
        statsByProfile = [:]
    }

    /// Remove one trade from detail + public profile list seeds (delete path).
    func removeTrade(id: TradeID) {
        trades[id] = nil
        tradeAuthority[id] = nil
        presentationSeeds[id] = nil
        for key in publicTradesByProfile.keys {
            publicTradesByProfile[key]?.removeAll { $0.id == id }
        }
        for key in publicTradeSummariesByProfile.keys {
            publicTradeSummariesByProfile[key]?.removeAll { $0.id == id }
        }
        statsByProfile = [:]
    }

    func removePost(id: PostID) {
        posts[id] = nil
    }

    func removeReel(id: ReelID) {
        if let reel = reels[id], let tradeID = reel.linkedTradeID {
            reelIDByLinkedTradeID.removeValue(forKey: tradeID)
        }
        reels[id] = nil
    }

    func removeStory(id: StoryID) {
        storiesByID[id] = nil
    }

    /// Drop all session seeds when the authenticated user changes.
    func removeAll() {
        trades = [:]
        tradeAuthority = [:]
        presentationSeeds = [:]
        posts = [:]
        reels = [:]
        reelIDByLinkedTradeID = [:]
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
        publicTradeSummariesByProfile = [:]
        followersByProfile = [:]
        followingByProfile = [:]
        viewerFollowingIDSet = nil
        viewerFollowEdgeByProfile = [:]
        viewerFollowRequestByProfile = [:]
        feedEngagementTargetByTradeID = [:]
        feedEngagementTargetByAchievementID = [:]
    }
}
