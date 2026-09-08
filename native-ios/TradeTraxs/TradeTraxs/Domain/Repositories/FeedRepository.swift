import Foundation

/// Profile clips load — reels plus trades embedded in the PostgREST join.
nonisolated struct ProfileReelsResult: Sendable {
    var reels: [Reel]
    var embeddedTrades: [Trade]
}

/// Single reel fetch — reel body plus optional embedded linked trade.
nonisolated struct ReelLoadResult: Sendable {
    var reel: Reel
    var embeddedTrade: Trade?
}

/// Bounded feed page plus trades already embedded in the PostgREST join.
nonisolated struct FeedPageResult: Sendable {
    var items: [FeedItem]
    var nextCursor: String?
    /// Trade bodies from `posts → trades(...)` — seed `SessionTradeEntityStore` / detail cache.
    var embeddedTrades: [Trade]

    var page: CursorPage<FeedItem> {
        CursorPage(items: items, nextCursor: nextCursor)
    }
}

nonisolated protocol FeedRepository: Sendable {
    func feed(
        scope: FeedScope,
        contentFilter: FeedContentFilter,
        page: PageRequest
    ) async throws -> FeedPageResult
    func post(id: PostID) async throws -> Post
    func posts(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post>
    func createPost(_ post: Post) async throws -> Post
    func deletePost(id: PostID) async throws
    func comments(for postID: PostID, page: PageRequest) async throws -> CursorPage<Comment>
    func addComment(_ comment: Comment) async throws -> Comment
    func setReaction(on item: FeedItem, kind: ReactionKind, isActive: Bool) async throws
    func stories(for viewer: ProfileID) async throws -> [Story]
    /// All active stories for the viewer's following ring (not deduped per author).
    func allActiveStories(for viewer: ProfileID) async throws -> [Story]
    /// Resolves a single active story when the viewer is allowed to see it (RLS + 24h window).
    func story(id: StoryID) async throws -> Story?
    func createStory(userID: ProfileID, imageURL: String) async throws -> Story
    /// Deletes a story the viewer owns.
    func deleteStory(id: StoryID) async throws
    func reel(id: ReelID) async throws -> ReelLoadResult
    func reels(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Reel>
    /// Web `fetchUserProfileReels` — Profile Clips tab (trade-linked visibility filter).
    func profileReels(for profileID: ProfileID) async throws -> ProfileReelsResult
    func createReel(_ reel: Reel) async throws -> Reel
    /// Deletes a reel the viewer owns.
    func deleteReel(id: ReelID) async throws
    /// Own clips with `trade_id IS NULL` — candidates for linking to a new trade.
    func unattachedReels(for profileID: ProfileID, limit: Int) async throws -> [Reel]
    /// Sets `reels.trade_id` (and clears caption per DB check). App enforces one reel per trade.
    func attachReel(id: ReelID, to tradeID: TradeID) async throws
    /// True when any reel already references this trade.
    func tradeHasAttachedReel(_ tradeID: TradeID) async throws -> Bool
}

extension FeedRepository {
    func allActiveStories(for viewer: ProfileID) async throws -> [Story] {
        try await stories(for: viewer)
    }

    func story(id: StoryID) async throws -> Story? {
        nil
    }

    func deleteStory(id: StoryID) async throws {
        throw AppError.notImplemented(feature: "deleteStory")
    }

    func deleteReel(id: ReelID) async throws {
        throw AppError.notImplemented(feature: "deleteReel")
    }

    func unattachedReels(for profileID: ProfileID, limit: Int) async throws -> [Reel] {
        let page = try await reels(
            authoredBy: profileID,
            page: PageRequest(limit: max(limit, 1))
        )
        return Array(page.items.filter { $0.linkedTradeID == nil }.prefix(limit))
    }

    func attachReel(id: ReelID, to tradeID: TradeID) async throws {
        throw AppError.notImplemented(feature: "attachReel")
    }

    func tradeHasAttachedReel(_ tradeID: TradeID) async throws -> Bool {
        false
    }
}
