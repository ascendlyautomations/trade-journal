import Foundation

/// Pure presentation transforms — no networking.
enum LeaderboardPresentation {
    static func buildState(
        entries: [LeaderboardEntry],
        profiles: [ProfileID: Profile],
        verified: Set<ProfileID>,
        followers: [ProfileID: Int],
        following: Set<ProfileID>,
        friends: Set<ProfileID>,
        viewerID: ProfileID?,
        audience: LeaderboardAudience,
        category: LeaderboardCategory,
        nextCursor: String?,
        preserving phase: LeaderboardState.Phase = .loaded,
        didBootstrap: Bool = true,
        lastUpdated: Date? = Date(),
        didPlayPodiumEntrance: Bool = false
    ) -> LeaderboardState {
        let ranked = rankedRows(
            entries: entries,
            profiles: profiles,
            verified: verified,
            followers: followers,
            following: following,
            viewerID: viewerID,
            audience: audience,
            friends: friends,
            category: category
        )

        let podium = Array(ranked.prefix(3))
        let listRows = Array(ranked.dropFirst(min(3, ranked.count)))
        let pinned: LeaderboardRow? = {
            guard let viewerID else { return nil }
            if let viewerRow = ranked.first(where: { $0.profileID == viewerID }) {
                // Approximate Strava sticky “You”: pin when below the first-screen ranks.
                return viewerRow.rank > 6 ? viewerRow : nil
            }
            return makeViewerRowIfMissing(
                viewerID: viewerID,
                entries: entries,
                profiles: profiles,
                verified: verified,
                followers: followers,
                following: following,
                category: category
            )
        }()

        var state = LeaderboardState()
        state.phase = phase
        state.audience = audience
        state.category = category
        state.rows = ranked
        state.podium = podium
        state.listRows = listRows
        state.pinnedViewer = pinned
        state.viewerID = viewerID
        state.followingIDs = following
        state.friendIDs = friends
        state.nextCursor = nextCursor
        state.hasMore = nextCursor != nil
        state.didBootstrap = didBootstrap
        state.lastUpdated = lastUpdated
        state.didPlayPodiumEntrance = didPlayPodiumEntrance
        return state
    }

    static func rankedRows(
        entries: [LeaderboardEntry],
        profiles: [ProfileID: Profile],
        verified: Set<ProfileID>,
        followers: [ProfileID: Int],
        following: Set<ProfileID>,
        viewerID: ProfileID?,
        audience: LeaderboardAudience,
        friends: Set<ProfileID>,
        category: LeaderboardCategory
    ) -> [LeaderboardRow] {
        let filtered = entries.filter { entry in
            switch audience {
            case .all:
                return true
            case .following:
                return following.contains(entry.profileID) || entry.profileID == viewerID
            case .friends:
                return friends.contains(entry.profileID) || entry.profileID == viewerID
            }
        }

        let rows: [LeaderboardRow] = filtered.compactMap { entry in
            makeRow(
                entry: entry,
                rank: entry.rank,
                profiles: profiles,
                verified: verified,
                followers: followers,
                following: following,
                viewerID: viewerID,
                category: category
            )
        }

        let sorted = rows.sorted { lhs, rhs in
            let l = lhs.sortValue(for: category)
            let r = rhs.sortValue(for: category)
            if l != r { return l > r }
            return lhs.profileID.rawValue < rhs.profileID.rawValue
        }

        return sorted.enumerated().map { index, row in
            var copy = row
            copy.rank = index + 1
            copy.trend = trend(for: copy, category: category)
            copy.primaryMetricText = primaryMetric(for: copy, category: category)
            copy.secondaryMetricText = secondaryMetric(for: copy, category: category)
            return copy
        }
    }

    private static func makeViewerRowIfMissing(
        viewerID: ProfileID,
        entries: [LeaderboardEntry],
        profiles: [ProfileID: Profile],
        verified: Set<ProfileID>,
        followers: [ProfileID: Int],
        following: Set<ProfileID>,
        category: LeaderboardCategory
    ) -> LeaderboardRow? {
        guard let entry = entries.first(where: { $0.profileID == viewerID }) else { return nil }
        return makeRow(
            entry: entry,
            rank: entry.rank,
            profiles: profiles,
            verified: verified,
            followers: followers,
            following: following,
            viewerID: viewerID,
            category: category
        )
    }

    private static func makeRow(
        entry: LeaderboardEntry,
        rank: Int,
        profiles: [ProfileID: Profile],
        verified: Set<ProfileID>,
        followers: [ProfileID: Int],
        following: Set<ProfileID>,
        viewerID: ProfileID?,
        category: LeaderboardCategory
    ) -> LeaderboardRow? {
        let profile = resolveProfile(entry.profileID, from: profiles)
        var row = LeaderboardRow(
            rank: rank,
            profileID: entry.profileID,
            profile: profile,
            isVerified: verified.contains(entry.profileID) || profile.isCreator,
            primaryMetricText: "",
            secondaryMetricText: "",
            trend: .flat,
            totalPnL: entry.totalPnL,
            tradeCount: entry.tradeCount,
            averageRiskReward: entry.averageRiskReward,
            followerCount: followers[entry.profileID] ?? 0,
            isFollowing: following.contains(entry.profileID),
            isCurrentUser: entry.profileID == viewerID
        )
        row.primaryMetricText = primaryMetric(for: row, category: category)
        row.secondaryMetricText = secondaryMetric(for: row, category: category)
        row.trend = trend(for: row, category: category)
        return row
    }

    private static func primaryMetric(for row: LeaderboardRow, category: LeaderboardCategory) -> String {
        switch category {
        case .pnl, .profitPercent, .winRate, .profitFactor, .expectancy, .winStreak, .consistency:
            return TradeDisplay.pnlText(row.totalPnL)
        case .rr:
            if let rr = row.averageRiskReward {
                return String(format: "%.2f RR", NSDecimalNumber(decimal: rr).doubleValue)
            }
            return "—"
        case .followers:
            return ProfileDisplay.compactCount(row.followerCount)
        }
    }

    private static func secondaryMetric(for row: LeaderboardRow, category: LeaderboardCategory) -> String {
        switch category {
        case .followers:
            return TradeDisplay.pnlText(row.totalPnL)
        case .rr:
            return "\(row.tradeCount) trades"
        default:
            if let rr = row.averageRiskReward {
                return String(format: "%d trades · %.1f RR", row.tradeCount, NSDecimalNumber(decimal: rr).doubleValue)
            }
            return "\(row.tradeCount) trades"
        }
    }

    /// Resolve display profile from the shared userID-keyed dictionary.
    static func resolveProfile(_ profileID: ProfileID, from profiles: [ProfileID: Profile]) -> Profile {
        leaderboardProfile(profiles[profileID], profileID: profileID)
    }

    private static func leaderboardProfile(_ profile: Profile?, profileID: ProfileID) -> Profile {
        let displayName = ProfileIdentitySanitizer.leaderboardDisplayName(
            name: profile?.displayName,
            username: profile?.username
        )
        let username = ProfileIdentitySanitizer.leaderboardUsername(profile?.username) ?? ""

        if var profile {
            profile.displayName = displayName
            profile.username = username
            return profile
        }

        return Profile(
            id: profileID,
            userID: UserID(profileID.rawValue),
            username: username,
            displayName: displayName,
            bio: nil,
            avatar: nil,
            traderType: nil,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: .now
        )
    }

    private static func trend(for row: LeaderboardRow, category: LeaderboardCategory) -> LeaderboardTrend {
        switch category {
        case .followers:
            if row.followerCount >= 1_000 { return .up }
            if row.followerCount < 200 { return .down }
            return .flat
        default:
            let amount = row.totalPnL.amount
            if amount > 0 { return .up }
            if amount < 0 { return .down }
            return .flat
        }
    }
}
