import Foundation

/// Bounded discovery queries for native Explore — reuses web RPCs / public profile pools.
nonisolated protocol ExploreRepository: Sendable {
    /// Public discoverable profiles for ranking (offset via `page.cursor` as Int string).
    func discoverableProfiles(page: PageRequest) async throws -> CursorPage<Profile>

    /// Batch follower/following counts via `explore_social_counts`.
    func socialCounts(for profileIDs: [ProfileID]) async throws -> ExploreSocialCounts

    /// Optional trade activity summaries via `explore_trade_meta_aggregates` (bounded).
    func tradeActivitySummaries(limit: Int) async throws -> [ProfileID: ExploreTraderRanking.TradeSummary]

    /// Public rooms ordered by member count via `popular_trade_rooms`.
    func popularRooms(limit: Int) async throws -> [ExploreRoomSuggestion]

    /// Public room name/slug search via `search_public_trade_rooms`.
    func searchRooms(query: String, limit: Int) async throws -> [ExploreRoomSuggestion]
}
