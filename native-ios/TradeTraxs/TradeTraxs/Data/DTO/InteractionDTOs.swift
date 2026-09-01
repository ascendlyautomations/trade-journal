import Foundation

nonisolated enum InteractionDTO {
    struct LikeRow: Codable, Sendable {
        var trade_id: String?
        var profile_post_id: String?
        var reel_id: String?
        var post_id: String?
        var achievement_post_id: String?
        var user_id: String?
    }

    struct CommentCountRow: Codable, Sendable {
        var trade_id: String?
        var profile_post_id: String?
        var reel_id: String?
        var post_id: String?
        var achievement_post_id: String?
    }

    struct CommentLikeRow: Codable, Sendable {
        var comment_id: String?
        var user_id: String?
        var comment_source: String?
    }

    struct CommentRow: Codable, Sendable {
        var id: String?
        var trade_id: String?
        var profile_post_id: String?
        var reel_id: String?
        var post_id: String?
        var achievement_post_id: String?
        var user_id: String?
        var content: String?
        var body: String?
        var parent_comment_id: String?
        var pinned: Bool?
        var created_at: String?
        var profiles: ProfileEmbed?

        struct ProfileEmbed: Codable, Sendable {
            var username: String?
            var name: String?
            var avatar_url: String?
        }
    }
}
