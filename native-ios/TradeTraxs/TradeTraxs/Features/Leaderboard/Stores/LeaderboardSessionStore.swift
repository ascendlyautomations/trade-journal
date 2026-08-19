import Foundation
import Observation

/// Session-scoped Leaderboard cache so Explore → Leaderboards → Profile → Back
/// does not cold-reload. Holds the raw trade set (web session cache parity) plus
/// hydrated presentation data.
@Observable
@MainActor
final class LeaderboardSessionStore {
    static let shared = LeaderboardSessionStore()

    /// Full public trade set — web `leaderboardSessionCache.trades`.
    private(set) var rawTrades: [LeaderboardTradeRow] = []
    /// Ranked entries for the current timeframe (derived from ``rawTrades``).
    private(set) var rawEntries: [LeaderboardEntry] = []
    private(set) var profilesByID: [ProfileID: Profile] = [:]
    private(set) var verifiedIDs: Set<ProfileID> = []
    private(set) var followerCounts: [ProfileID: Int] = [:]
    private(set) var followingIDs: Set<ProfileID> = []
    private(set) var friendIDs: Set<ProfileID> = []
    private(set) var viewerID: ProfileID?
    private(set) var nextCursor: String?
    private(set) var audience: LeaderboardAudience = .all
    private(set) var timeframe: LeaderboardTimeframe = .month
    private(set) var category: LeaderboardCategory = .pnl
    private(set) var hasBootstrapped = false
    private(set) var lastUpdated: Date?

    private init() {}

    func applyBootstrap(
        trades: [LeaderboardTradeRow],
        entries: [LeaderboardEntry],
        profiles: [ProfileID: Profile],
        verified: Set<ProfileID>,
        followers: [ProfileID: Int],
        following: Set<ProfileID>,
        friends: Set<ProfileID>,
        viewerID: ProfileID?,
        nextCursor: String?,
        audience: LeaderboardAudience,
        timeframe: LeaderboardTimeframe,
        category: LeaderboardCategory
    ) {
        rawTrades = trades
        rawEntries = entries
        profilesByID = profiles
        verifiedIDs = verified
        followerCounts = followers
        followingIDs = following
        friendIDs = friends
        self.viewerID = viewerID
        self.nextCursor = nextCursor
        self.audience = audience
        self.timeframe = timeframe
        self.category = category
        hasBootstrapped = true
        lastUpdated = Date()
    }

    /// Re-rank from cached trades after a timeframe change (no network).
    func replaceEntries(_ entries: [LeaderboardEntry], nextCursor: String?, timeframe: LeaderboardTimeframe) {
        rawEntries = entries
        self.nextCursor = nextCursor
        self.timeframe = timeframe
        lastUpdated = Date()
    }

    func mergeProfiles(
        _ profiles: [ProfileID: Profile],
        verified: Set<ProfileID>,
        followers: [ProfileID: Int]
    ) {
        for (id, profile) in profiles { profilesByID[id] = profile }
        verifiedIDs.formUnion(verified)
        for (id, count) in followers { followerCounts[id] = count }
    }

    func appendEntries(
        _ entries: [LeaderboardEntry],
        profiles: [ProfileID: Profile],
        verified: Set<ProfileID>,
        followers: [ProfileID: Int],
        nextCursor: String?
    ) {
        var merged = Dictionary(uniqueKeysWithValues: rawEntries.map { ($0.profileID, $0) })
        for entry in entries {
            merged[entry.profileID] = entry
        }
        rawEntries = merged.values.sorted { $0.rank < $1.rank }
        mergeProfiles(profiles, verified: verified, followers: followers)
        self.nextCursor = nextCursor
        lastUpdated = Date()
    }

    func setFollowing(_ id: ProfileID, isFollowing: Bool) {
        applyFollowEdge(id, isFollowing: isFollowing, adjustFollowerCount: false)
    }

    /// Shared Follow mutation patch — edge + optional follower-count column.
    func applyFollowEdge(
        _ id: ProfileID,
        isFollowing: Bool,
        adjustFollowerCount: Bool
    ) {
        if isFollowing {
            followingIDs.insert(id)
        } else {
            followingIDs.remove(id)
            friendIDs.remove(id)
        }
        guard adjustFollowerCount else { return }
        let current = followerCounts[id] ?? 0
        followerCounts[id] = max(0, current + (isFollowing ? 1 : -1))
    }

    func updateFilters(
        audience: LeaderboardAudience,
        timeframe: LeaderboardTimeframe,
        category: LeaderboardCategory
    ) {
        self.audience = audience
        self.timeframe = timeframe
        self.category = category
    }

    func invalidate() {
        rawTrades = []
        rawEntries = []
        profilesByID = [:]
        verifiedIDs = []
        followerCounts = [:]
        followingIDs = []
        friendIDs = []
        viewerID = nil
        nextCursor = nil
        audience = .all
        timeframe = .month
        category = .pnl
        hasBootstrapped = false
        lastUpdated = nil
    }
}
