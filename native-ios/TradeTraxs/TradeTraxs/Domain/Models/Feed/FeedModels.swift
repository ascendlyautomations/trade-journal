import Foundation

nonisolated enum FeedItemKind: String, Hashable, Codable, Sendable {
    case trade
    case post
    case achievement
    case reel
    case story
}

nonisolated enum FeedScope: String, CaseIterable, Hashable, Codable, Sendable {
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
    /// Authoritative Feed/Profile crop metadata when present on the row.
    var imageCrop: ContentImagePresentation? = nil
    /// Trade Room share snapshot from `profile_posts.room_*` (web `FeedRoomShareCard`).
    var roomShare: RoomShareAttachment? = nil
    /// True when like/comment counts were authoritative at persist/bootstrap time.
    var engagementStateCached: Bool? = nil
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
    /// Snapshot of a Trade Room attached at publish time. Nil for ordinary posts.
    var roomShare: RoomShareAttachment? = nil
}

/// Frozen room identity stored on a profile post so the feed can offer Join Room
/// without another lookup. Matches web `room_id` / `room_name` / `room_logo` / `room_description`.
nonisolated struct RoomShareAttachment: Hashable, Codable, Sendable {
    var roomID: RoomID
    var name: String
    var logoURL: String?
    var description: String?

    init(room: TradeRoom) {
        let trimmedName = room.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let logo = room.image?.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = room.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            roomID: room.id,
            name: trimmedName.isEmpty ? "Trade Room" : trimmedName,
            logoURL: (logo?.isEmpty == false) ? logo : nil,
            description: (description?.isEmpty == false) ? description : nil
        )
    }

    init(roomID: RoomID, name: String, logoURL: String?, description: String?) {
        self.roomID = roomID
        self.name = name
        self.logoURL = logoURL
        self.description = description
    }

    static func parsed(
        roomID: String?,
        name: String?,
        logoURL: String?,
        description: String?
    ) -> RoomShareAttachment? {
        let id = roomID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !id.isEmpty else { return nil }
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let logo = logoURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let about = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return RoomShareAttachment(
            roomID: RoomID(id),
            name: trimmedName.isEmpty ? "Trade Room" : trimmedName,
            logoURL: (logo?.isEmpty == false) ? logo : nil,
            description: (about?.isEmpty == false) ? about : nil
        )
    }
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
