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
}
