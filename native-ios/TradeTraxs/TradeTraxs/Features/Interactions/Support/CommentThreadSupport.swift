import Foundation

/// Web `lib/commentThreads.ts` + `lib/commentReplyUx.ts` — single-level reply threads.
enum CommentThreadSupport {
    static let manyTopLevelCommentsThreshold = 5
    static let replyPreviewMaxLength = 80

    /// Stored as `parent_comment_id` — always the thread root (top-level comment).
    struct ReplyTarget: Equatable, Sendable {
        var parentCommentID: CommentID
        var authorName: String
        var preview: String
        var mentionUsername: String
    }

    struct ReplyThreadDisplay<T> {
        var visibleReplies: [T]
        var showToggle: Bool
        var collapsedLabel: String?
    }

    static func indexCommentsByID(_ comments: [InteractionComment]) -> [CommentID: InteractionComment] {
        Dictionary(uniqueKeysWithValues: comments.map { ($0.id, $0) })
    }

    /// Walk `parent_comment_id` chain to the thread root — matches web `getCommentThreadRootId`.
    static func threadRootID(
        for commentID: CommentID,
        commentsByID: [CommentID: InteractionComment]
    ) -> CommentID {
        var visited = Set<CommentID>()
        var currentID = commentID

        while !visited.contains(currentID) {
            visited.insert(currentID)
            guard let parentID = commentsByID[currentID]?.parentCommentID else {
                return currentID
            }
            currentID = parentID
        }

        return commentID
    }

    static func replies(
        for rootID: CommentID,
        in comments: [InteractionComment]
    ) -> [InteractionComment] {
        let byID = indexCommentsByID(comments)
        return comments
            .filter { comment in
                guard comment.isReply else { return false }
                return threadRootID(for: comment.id, commentsByID: byID) == rootID
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func buildReplyTarget(
        for comment: InteractionComment,
        allComments: [InteractionComment]
    ) -> ReplyTarget {
        let byID = indexCommentsByID(allComments)
        let parentCommentID = comment.isReply
            ? threadRootID(for: comment.id, commentsByID: byID)
            : comment.id

        let mentionUsername = commentAuthorUsername(comment)

        return ReplyTarget(
            parentCommentID: parentCommentID,
            authorName: replyAuthorLabel(comment),
            preview: truncateReplyPreview(comment.body),
            mentionUsername: mentionUsername
        )
    }

    static func replyMentionPrefix(username: String?) -> String {
        let normalized = username?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^@", with: "", options: .regularExpression)
        guard let normalized, !normalized.isEmpty else { return "" }
        return "@\(normalized) "
    }

    static func replyThreadDisplay(
        replies: [InteractionComment],
        topLevelCommentCount: Int,
        expanded: Bool
    ) -> ReplyThreadDisplay<InteractionComment> {
        let count = replies.count

        if count <= 1 {
            return ReplyThreadDisplay(
                visibleReplies: replies,
                showToggle: false,
                collapsedLabel: nil
            )
        }

        if expanded {
            return ReplyThreadDisplay(
                visibleReplies: replies,
                showToggle: true,
                collapsedLabel: nil
            )
        }

        let manyTopLevel = topLevelCommentCount >= manyTopLevelCommentsThreshold

        if manyTopLevel {
            let label = count == 1 ? "View 1 reply" : "View \(count) replies"
            return ReplyThreadDisplay(
                visibleReplies: [],
                showToggle: true,
                collapsedLabel: label
            )
        }

        let hiddenCount = count - 1
        let label = hiddenCount == 1
            ? "View 1 more reply"
            : "View \(hiddenCount) more replies"
        return ReplyThreadDisplay(
            visibleReplies: Array(replies.prefix(1)),
            showToggle: true,
            collapsedLabel: label
        )
    }

    static func descendantIDs(
        of commentID: CommentID,
        in comments: [InteractionComment]
    ) -> Set<CommentID> {
        var removed = Set<CommentID>([commentID])
        var changed = true
        while changed {
            changed = false
            for comment in comments where !removed.contains(comment.id) {
                if let parentID = comment.parentCommentID, removed.contains(parentID) {
                    removed.insert(comment.id)
                    changed = true
                }
            }
        }
        return removed
    }

    static func matchesOptimistic(
        _ server: InteractionComment,
        _ optimistic: InteractionComment
    ) -> Bool {
        server.body == optimistic.body
            && server.parentCommentID == optimistic.parentCommentID
            && server.authorProfileID == optimistic.authorProfileID
    }

    private static func commentAuthorUsername(_ comment: InteractionComment) -> String {
        if let username = comment.authorUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
           !username.isEmpty {
            return username
        }
        if let name = comment.authorDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
                .replacingOccurrences(of: "\\s+", with: "_", options: .regularExpression)
                .lowercased()
        }
        return "user"
    }

    private static func replyAuthorLabel(_ comment: InteractionComment) -> String {
        if let name = comment.authorDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        if let username = comment.authorUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
           !username.isEmpty {
            return username
        }
        return "Someone"
    }

    private static func truncateReplyPreview(_ text: String, max: Int = replyPreviewMaxLength) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.count > max else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: max)
        return String(trimmed[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
