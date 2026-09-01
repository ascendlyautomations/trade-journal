import Foundation

/// Web `lib/pinComment.ts` + pinned ordering from `lib/commentThreads.ts`.
enum CommentPinSemantics {
    static func canPinComment(
        viewerUserID: String?,
        contentOwnerUserID: String?
    ) -> Bool {
        let viewer = viewerUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let owner = contentOwnerUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !viewer.isEmpty && !owner.isEmpty && viewer == owner
    }

    static func isCommentPinned(_ comment: InteractionComment) -> Bool {
        comment.isPinned && !comment.isReply
    }

    /// One pinned top-level comment max — unpins siblings when pinning.
    static func applyPinnedState(
        _ comments: [InteractionComment],
        commentID: CommentID,
        pinned: Bool
    ) -> [InteractionComment] {
        comments.map { comment in
            if comment.id == commentID {
                var updated = comment
                updated.isPinned = pinned
                return updated
            }
            if pinned, comment.isPinned, !comment.isReply {
                var updated = comment
                updated.isPinned = false
                return updated
            }
            return comment
        }
    }

    /// Top-level rows: pinned first, then chronological per sort order.
    static func sortedTopLevel(
        _ comments: [InteractionComment],
        order: CommentSortOrder
    ) -> [InteractionComment] {
        comments.sorted { lhs, rhs in
            let lhsPinned = isCommentPinned(lhs) ? 1 : 0
            let rhsPinned = isCommentPinned(rhs) ? 1 : 0
            if lhsPinned != rhsPinned { return lhsPinned > rhsPinned }
            switch order {
            case .oldest: return lhs.createdAt < rhs.createdAt
            case .newest: return lhs.createdAt > rhs.createdAt
            }
        }
    }
}

nonisolated struct CommentPinRealtimeSignal: Sendable {
    var commentID: String
    var pinned: Bool
}
