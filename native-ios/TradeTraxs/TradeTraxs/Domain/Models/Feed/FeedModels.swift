import Foundation

nonisolated enum FeedItemKind: String, Hashable, Codable, Sendable {
    case trade
    case post
    case achievement
    case reel
    case story
}

nonisolated enum FeedScope: String, Hashable, Codable, Sendable {
    case global
    case following
}

nonisolated enum ReactionKind: String, Hashable, Codable, Sendable {
    case like
    case fire
    case insight
}

/// Timeline entry — Feed aggregate projection over posts/trades/reels/etc.
nonisolated struct FeedItem: Hashable, Codable, Sendable, Identifiable {
    var id: String
    var kind: FeedItemKind
    var authorProfileID: ProfileID
    var createdAt: Date
    var tradeID: TradeID?
    var postID: PostID?
    var reelID: ReelID?
    var storyID: StoryID?
    var achievementID: AchievementID?
    var caption: String?
    var likeCount: Int
    var commentCount: Int
    var viewerHasLiked: Bool
    /// Web feed embed `profiles.username` — seeded into DetailPresentationCache (no N+1).
    var authorUsername: String? = nil
    /// Web feed embed `profiles` display label (`name` when present, else username).
    var authorDisplayName: String? = nil
    /// Web feed embed `profiles.avatar_url`.
    var authorAvatarURL: String? = nil
    /// Card media for profile posts / reel thumbs / achievement images when present on the row.
    var mediaURL: String? = nil
}

nonisolated struct Post: Hashable, Codable, Sendable, Identifiable {
    var id: PostID
    var authorProfileID: ProfileID
    var body: String
    var media: [MediaReference]
    var visibility: ContentVisibility
    var linkedTradeID: TradeID?
    /// Web Profile client sort key (`profile_posts.is_pinned` when present).
    var isPinned: Bool
    var createdAt: Date
    var updatedAt: Date
}

nonisolated struct Comment: Hashable, Codable, Sendable, Identifiable {
    var id: CommentID
    var postID: PostID?
    var tradeID: TradeID?
    var reelID: ReelID?
    var authorProfileID: ProfileID
    var body: String
    var parentCommentID: CommentID?
    var createdAt: Date
}

nonisolated struct Reaction: Hashable, Codable, Sendable, Identifiable {
    var id: ReactionID
    var kind: ReactionKind
    var actorProfileID: ProfileID
    var postID: PostID?
    var tradeID: TradeID?
    var reelID: ReelID?
    var createdAt: Date
}

nonisolated struct Story: Hashable, Codable, Sendable, Identifiable {
    var id: StoryID
    var authorProfileID: ProfileID
    var media: MediaReference
    var expiresAt: Date
    var createdAt: Date
    var viewerHasSeen: Bool
}

nonisolated struct Reel: Hashable, Codable, Sendable, Identifiable {
    var id: ReelID
    var authorProfileID: ProfileID
    var video: MediaReference
    var thumbnail: MediaReference?
    var caption: String?
    var visibility: ContentVisibility
    var linkedTradeID: TradeID?
    /// Seconds when provided by `reels.duration_seconds`.
    var durationSeconds: Int?
    var createdAt: Date
}
