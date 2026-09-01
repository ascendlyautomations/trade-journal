import Foundation

/// Platform interaction API — content-agnostic likes & comments (web table parity).
nonisolated protocol InteractionRepository: Sendable {
    /// Batch engagement for list cards — one round-trip group per kind.
    func engagement(for targets: [InteractionTarget]) async throws -> [InteractionTarget: EngagementSnapshot]

    /// Toggle like — insert/delete matching web `toggleContentLike` / `toggleReelLike`.
    /// Treats unique-violation as success.
    func setLiked(_ liked: Bool, on target: InteractionTarget) async throws

    /// Full comment list (web has no pagination) — ordered by `created_at`.
    func comments(
        for target: InteractionTarget,
        order: CommentSortOrder
    ) async throws -> [InteractionComment]

    func addComment(
        body: String,
        parentID: CommentID?,
        on target: InteractionTarget
    ) async throws -> InteractionComment

    func deleteComment(id: CommentID, on target: InteractionTarget) async throws

    /// Batch like meta for visible comments — one `comment_likes` SELECT.
    func commentLikeMeta(
        for commentIDs: [CommentID],
        source: CommentLikeSource
    ) async throws -> [CommentID: CommentLikeSnapshot]

    /// Insert/delete on `comment_likes` — treats unique violation as success on insert.
    func setCommentLiked(
        _ liked: Bool,
        commentID: CommentID,
        source: CommentLikeSource
    ) async throws

    /// Update `pinned` on a top-level comment — content-owner RLS on the comments table.
    func setCommentPinned(
        _ pinned: Bool,
        commentID: CommentID,
        on target: InteractionTarget
    ) async throws
}
