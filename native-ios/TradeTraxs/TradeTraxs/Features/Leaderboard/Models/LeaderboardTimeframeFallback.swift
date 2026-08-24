import Foundation

/// Cross-platform timeframe fallback — smallest → largest preset order.
enum LeaderboardTimeframeFallback {
    /// Native UI order: Today → Week → Month → Year → All Time.
    static let presetOrder: [LeaderboardTimeframe] = [
        .today, .week, .month, .year, .allTime,
    ]

    struct Resolution: Equatable, Sendable {
        var requested: LeaderboardTimeframe
        var effective: LeaderboardTimeframe
        var usedFallback: Bool
    }

    struct ResolvedPage: Sendable {
        var resolution: Resolution
        var entries: [LeaderboardEntry]
        var nextCursor: String?
    }

    static func nextLarger(_ timeframe: LeaderboardTimeframe) -> LeaderboardTimeframe? {
        guard let index = presetOrder.firstIndex(of: timeframe) else {
            return presetOrder.first
        }
        let next = index + 1
        guard next < presetOrder.count else { return nil }
        return presetOrder[next]
    }

    /// Window-level resolution (rankings exist) — used before profile hydration on bootstrap.
    static func resolveWindow(
        trades: [LeaderboardTradeRow],
        requested: LeaderboardTimeframe,
        limit: Int = 100,
        now: Date = Date()
    ) -> ResolvedPage {
        var timeframe = requested
        while true {
            let filtered = LeaderboardTradeWindowFilter.filter(
                trades,
                window: timeframe.repositoryWindow,
                interval: timeframe.customInterval,
                now: now
            )
            let rankings = LeaderboardTradeWindowFilter.buildRankings(from: filtered)
            if !rankings.entries.isEmpty {
                let page = LeaderboardTradeWindowFilter.entries(
                    from: trades,
                    window: timeframe.repositoryWindow,
                    interval: timeframe.customInterval,
                    page: PageRequest(limit: limit),
                    now: now
                )
                return ResolvedPage(
                    resolution: Resolution(
                        requested: requested,
                        effective: timeframe,
                        usedFallback: timeframe != requested
                    ),
                    entries: page.items,
                    nextCursor: page.nextCursor
                )
            }
            guard let next = nextLarger(timeframe) else {
                let page = LeaderboardTradeWindowFilter.entries(
                    from: trades,
                    window: timeframe.repositoryWindow,
                    interval: timeframe.customInterval,
                    page: PageRequest(limit: limit),
                    now: now
                )
                return ResolvedPage(
                    resolution: Resolution(
                        requested: requested,
                        effective: requested,
                        usedFallback: false
                    ),
                    entries: page.items,
                    nextCursor: page.nextCursor
                )
            }
            timeframe = next
        }
    }

    /// Full presentation resolution — audience/category aware (cached refilter).
    static func resolvePage(
        trades: [LeaderboardTradeRow],
        requested: LeaderboardTimeframe,
        audience: LeaderboardAudience,
        category: LeaderboardCategory,
        profiles: [ProfileID: Profile],
        verified: Set<ProfileID>,
        followers: [ProfileID: Int],
        following: Set<ProfileID>,
        friends: Set<ProfileID>,
        viewerID: ProfileID?,
        limit: Int = 100,
        now: Date = Date()
    ) -> ResolvedPage {
        var timeframe = requested
        while true {
            let page = LeaderboardTradeWindowFilter.entries(
                from: trades,
                window: timeframe.repositoryWindow,
                interval: timeframe.customInterval,
                page: PageRequest(limit: limit),
                now: now
            )
            let ranked = LeaderboardPresentation.rankedRows(
                entries: page.items,
                profiles: profiles,
                verified: verified,
                followers: followers,
                following: following,
                viewerID: viewerID,
                audience: audience,
                friends: friends,
                category: category
            )
            if !ranked.isEmpty {
                return ResolvedPage(
                    resolution: Resolution(
                        requested: requested,
                        effective: timeframe,
                        usedFallback: timeframe != requested
                    ),
                    entries: page.items,
                    nextCursor: page.nextCursor
                )
            }
            guard let next = nextLarger(timeframe) else {
                return ResolvedPage(
                    resolution: Resolution(
                        requested: requested,
                        effective: requested,
                        usedFallback: false
                    ),
                    entries: page.items,
                    nextCursor: page.nextCursor
                )
            }
            timeframe = next
        }
    }

    static func fallbackMessage(
        requested: LeaderboardTimeframe,
        effective: LeaderboardTimeframe
    ) -> String? {
        guard requested != effective else { return nil }
        return "No results for \(requested.title) — showing \(effective.title)"
    }

    /// Maps native presets to web view ids for cross-platform parity tests.
    static func webViewID(for timeframe: LeaderboardTimeframe) -> String {
        switch timeframe {
        case .today: return "Custom"
        case .week: return "7D"
        case .month: return "30D"
        case .year: return "YTD"
        case .allTime: return "ALL"
        }
    }
}
