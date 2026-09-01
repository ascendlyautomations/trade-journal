import Foundation

/// Web `lib/commentLikes.ts` — unified `comment_likes` table sources.
nonisolated enum CommentLikeSource: String, Sendable, CaseIterable {
    case comments
    case tradeComments = "trade_comments"
    case profilePostComments = "profile_post_comments"
    case achievementPostComments = "achievement_post_comments"
    case reelComments = "reel_comments"

    static func from(_ kind: InteractionContentKind) -> CommentLikeSource {
        switch kind {
        case .trade: return .tradeComments
        case .profilePost: return .profilePostComments
        case .reel: return .reelComments
        case .feedPost: return .comments
        case .achievement: return .achievementPostComments
        }
    }
}

/// Web `CommentLikeMeta` — count + viewer liked state for one comment.
nonisolated struct CommentLikeSnapshot: Hashable, Sendable {
    var count: Int
    var liked: Bool

    static let empty = CommentLikeSnapshot(count: 0, liked: false)

    func togglingLike() -> CommentLikeSnapshot {
        if liked {
            return CommentLikeSnapshot(count: max(0, count - 1), liked: false)
        }
        return CommentLikeSnapshot(count: count + 1, liked: true)
    }
}

nonisolated enum CommentLikeSemantics {
    /// Max ids for a single Realtime `in.(…)` filter (web `REALTIME_IN_FILTER_MAX_IDS`).
    static let realtimeInFilterMaxIDs = 100

    static func realtimeFilter(source: CommentLikeSource, commentIDs: [String]) -> String {
        let unique = Array(Set(commentIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
            .sorted()
        if !unique.isEmpty, unique.count <= realtimeInFilterMaxIDs {
            return "comment_id=in.(\(unique.joined(separator: ",")))"
        }
        return "comment_source=eq.\(source.rawValue)"
    }

    static func stableRouteSuffix(source: CommentLikeSource, commentIDs: [String]) -> String {
        let unique = Array(Set(commentIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
            .sorted()
        let idsKey = unique.joined(separator: ",")
        if idsKey.isEmpty {
            return "\(source.rawValue)-empty"
        }
        return "\(source.rawValue)-\(idsKey.prefix(48))"
    }

    static func aggregateMeta(
        rows: [(commentID: String, userID: String)],
        commentIDs: [CommentID],
        viewerUserID: String?
    ) -> [CommentID: CommentLikeSnapshot] {
        var meta: [CommentID: CommentLikeSnapshot] = [:]
        for id in commentIDs {
            meta[id] = .empty
        }
        for row in rows {
            let id = CommentID(row.commentID)
            guard meta[id] != nil else { continue }
            var snap = meta[id] ?? .empty
            snap.count += 1
            if let viewerUserID, row.userID == viewerUserID {
                snap.liked = true
            }
            meta[id] = snap
        }
        return meta
    }

    /// Web `applyCommentLikeRealtimeEvent` — skip double-count while optimistic toggle is in-flight.
    static func applyRealtimeEvent(
        _ previous: CommentLikeSnapshot,
        event: RealtimeMutationKind,
        actorUserID: String,
        currentUserID: String?
    ) -> CommentLikeSnapshot {
        switch event {
        case .insert:
            if actorUserID == currentUserID, previous.liked {
                return previous
            }
            return CommentLikeSnapshot(
                count: previous.count + 1,
                liked: actorUserID == currentUserID ? true : previous.liked
            )
        case .delete:
            if actorUserID == currentUserID, !previous.liked {
                return previous
            }
            return CommentLikeSnapshot(
                count: max(0, previous.count - 1),
                liked: actorUserID == currentUserID ? false : previous.liked
            )
        }
    }

    enum RealtimeMutationKind: Sendable {
        case insert
        case delete
    }
}

nonisolated struct CommentLikeRealtimeSignal: Sendable {
    var kind: CommentLikeSemantics.RealtimeMutationKind
    var commentID: String
    var userID: String
    var commentSource: String
}
