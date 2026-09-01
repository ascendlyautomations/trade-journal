import Foundation

/// Content surface for likes/comments — mirrors web table routing.
///
/// | Kind | Likes table | Comments table |
/// |------|-------------|----------------|
/// | trade | trade_likes | trade_comments |
/// | profilePost | profile_post_likes | profile_post_comments |
/// | reel | reel_likes | reel_comments |
/// | feedPost | likes | comments |
/// | achievement | achievement_post_likes | achievement_post_comments |
nonisolated enum InteractionContentKind: String, Hashable, Codable, Sendable {
    case trade
    case profilePost
    case reel
    case feedPost
    /// Web achievement feed posts (`achievement_post_id`).
    case achievement
}

/// Typed target injected into reusable Like/Comment UI — never hard-codes a screen.
nonisolated struct InteractionTarget: Hashable, Codable, Sendable {
    var kind: InteractionContentKind
    var id: String

    static func trade(_ id: TradeID) -> InteractionTarget {
        InteractionTarget(kind: .trade, id: id.rawValue)
    }

    static func profilePost(_ id: PostID) -> InteractionTarget {
        InteractionTarget(kind: .profilePost, id: id.rawValue)
    }

    static func reel(_ id: ReelID) -> InteractionTarget {
        InteractionTarget(kind: .reel, id: id.rawValue)
    }

    static func feedPost(_ id: PostID) -> InteractionTarget {
        InteractionTarget(kind: .feedPost, id: id.rawValue)
    }

    /// Target id is usually `achievement_posts.id`. Profile surfaces may pass `achievements.id`;
    /// ``DefaultInteractionRepository`` resolves that before likes/comments.
    static func achievement(_ id: AchievementID) -> InteractionTarget {
        InteractionTarget(kind: .achievement, id: id.rawValue)
    }
}

/// Aggregated engagement — web `LikeMeta` + comment count.
nonisolated struct EngagementSnapshot: Hashable, Codable, Sendable {
    var likeCount: Int
    var commentCount: Int
    var viewerHasLiked: Bool

    static let empty = EngagementSnapshot(likeCount: 0, commentCount: 0, viewerHasLiked: false)

    func togglingLike() -> EngagementSnapshot {
        if viewerHasLiked {
            return EngagementSnapshot(
                likeCount: max(0, likeCount - 1),
                commentCount: commentCount,
                viewerHasLiked: false
            )
        }
        return EngagementSnapshot(
            likeCount: likeCount + 1,
            commentCount: commentCount,
            viewerHasLiked: true
        )
    }
}

nonisolated enum CommentSortOrder: String, Hashable, Codable, Sendable, CaseIterable {
    case oldest
    case newest
}

/// Presentation comment — domain ``Comment`` plus optional author display.
nonisolated struct InteractionComment: Hashable, Codable, Sendable, Identifiable {
    var id: CommentID
    var target: InteractionTarget
    var authorProfileID: ProfileID
    var authorUsername: String?
    /// Display name from profiles join — used for initials / a11y; list UI keeps @username.
    var authorDisplayName: String? = nil
    /// Avatar storage URL / public path from the same comments list join (no N+1 profile fetch).
    var authorAvatarURL: String? = nil
    var body: String
    var parentCommentID: CommentID?
    var createdAt: Date
    /// Architecture-ready — pin UI ships later.
    var isPinned: Bool

    var isReply: Bool { parentCommentID != nil }

    var authorAvatarReference: MediaReference? {
        guard let raw = authorAvatarURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }
        return MediaReference(id: raw, kind: .image, altText: nil)
    }
}
