import Foundation

/// Bounded discovery queries for native Explore — reuses web RPCs / public profile pools.
nonisolated protocol ExploreRepository: Sendable {
    /// Public discoverable profiles for ranking (offset via `page.cursor` as Int string).
    func discoverableProfiles(page: PageRequest) async throws -> CursorPage<Profile>

    /// Filtered discoverable profiles — category (`trader_type`) and strategy (`trading_style` / `trading_model`).
    func discoverableProfiles(
        page: PageRequest,
        filter: ExploreDiscoverableProfileFilter
    ) async throws -> CursorPage<Profile>

    /// Discoverable profiles with a non-empty avatar (Explore home rail fallback).
    func discoverableProfilesWithAvatars(limit: Int) async throws -> [Profile]

    /// Batch follower/following counts via `explore_social_counts`.
    func socialCounts(for profileIDs: [ProfileID]) async throws -> ExploreSocialCounts

    /// Optional trade activity summaries via `explore_trade_meta_aggregates` (bounded).
    func tradeActivitySummaries(limit: Int) async throws -> [ProfileID: ExploreTraderRanking.TradeSummary]

    /// Public rooms ordered by member count via `popular_trade_rooms`.
    func popularRooms(limit: Int) async throws -> [ExploreRoomSuggestion]

    /// Suggested / Popular / Your Rooms via `rpc_v1_trade_room_discovery` (falls back to popular).
    func discoverRooms(
        mode: TradeRoomDiscoveryMode,
        scope: TradeRoomDiscoveryScope,
        limit: Int
    ) async throws -> [ExploreRoomSuggestion]

    /// Single-call home bootstrap — Your Rooms + Suggested + Popular with is_owner/is_member.
    func tradeRoomsHomeBootstrap(
        scope: TradeRoomDiscoveryScope,
        limit: Int,
        suggestedCursor: String?,
        popularCursor: String?,
        category: TradeRoomCategory?
    ) async throws -> TradeRoomsHomeBootstrap

    /// Public room name/slug search via `search_public_trade_rooms`.
    func searchRooms(query: String, limit: Int) async throws -> [ExploreRoomSuggestion]

    /// Active public live broadcasts for Explore (`GET /api/explore/live-traders`).
    func liveTradersNow(limit: Int) async throws -> [ExploreLiveTraderNow]
}

extension ExploreRepository {
    func discoverableProfiles(
        page: PageRequest,
        filter: ExploreDiscoverableProfileFilter
    ) async throws -> CursorPage<Profile> {
        let result = try await discoverableProfiles(page: page)
        guard filter.traderType != nil || filter.normalizedStrategyQuery != nil else {
            return result
        }
        let items = result.items.filter { ExploreDiscoverableProfileFilter.matches($0, filter: filter) }
        return CursorPage(items: items, nextCursor: result.nextCursor)
    }

    func discoverableProfilesWithAvatars(limit: Int) async throws -> [Profile] {
        let capped = max(1, min(limit, 24))
        let page = try await discoverableProfiles(page: PageRequest(limit: capped))
        return page.items.filter { ExploreTraderRanking.hasValidProfilePicture($0) }
    }

    func discoverRooms(mode: TradeRoomDiscoveryMode, limit: Int) async throws -> [ExploreRoomSuggestion] {
        try await discoverRooms(mode: mode, scope: .all, limit: limit)
    }

    func discoverRooms(
        mode: TradeRoomDiscoveryMode,
        scope: TradeRoomDiscoveryScope,
        limit: Int
    ) async throws -> [ExploreRoomSuggestion] {
        try await popularRooms(limit: limit)
    }

    func tradeRoomsHomeBootstrap(
        scope: TradeRoomDiscoveryScope,
        limit: Int,
        suggestedCursor: String? = nil,
        popularCursor: String? = nil,
        category: TradeRoomCategory? = nil
    ) async throws -> TradeRoomsHomeBootstrap {
        _ = category
        return TradeRoomsHomeBootstrap(
            viewerID: nil,
            scope: scope,
            yourRooms: [],
            suggested: try await popularRooms(limit: limit),
            popular: try await popularRooms(limit: limit),
            suggestedNextCursor: nil,
            popularNextCursor: nil
        )
    }

    func liveTradersNow(limit: Int) async throws -> [ExploreLiveTraderNow] { [] }
}
