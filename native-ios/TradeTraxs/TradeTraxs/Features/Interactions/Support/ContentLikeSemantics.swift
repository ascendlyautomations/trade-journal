import Foundation

/// Production content-like tables — mirrors ``DefaultInteractionRepository`` routing.
nonisolated enum ContentLikeTable: String, Sendable, CaseIterable {
    case reelLikes = "reel_likes"
    case tradeLikes = "trade_likes"
    case profilePostLikes = "profile_post_likes"
    case achievementPostLikes = "achievement_post_likes"
    case feedPostLikes = "likes"

    static func from(_ kind: InteractionContentKind) -> ContentLikeTable {
        switch kind {
        case .trade: return .tradeLikes
        case .profilePost: return .profilePostLikes
        case .reel: return .reelLikes
        case .feedPost: return .feedPostLikes
        case .achievement: return .achievementPostLikes
        }
    }

    var foreignKeyColumn: String {
        switch self {
        case .reelLikes: return "reel_id"
        case .tradeLikes: return "trade_id"
        case .profilePostLikes: return "profile_post_id"
        case .achievementPostLikes: return "achievement_post_id"
        case .feedPostLikes: return "post_id"
        }
    }

    var interactionKind: InteractionContentKind {
        switch self {
        case .reelLikes: return .reel
        case .tradeLikes: return .trade
        case .profilePostLikes: return .profilePost
        case .achievementPostLikes: return .achievement
        case .feedPostLikes: return .feedPost
        }
    }
}

nonisolated enum ContentLikeSemantics {
    static let realtimeInFilterMaxIDs = 100

    static func realtimeFilter(table: ContentLikeTable, contentIDs: [String]) -> String {
        let column = table.foreignKeyColumn
        let unique = Array(Set(contentIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
            .sorted()
        guard !unique.isEmpty, unique.count <= realtimeInFilterMaxIDs else {
            return "\(column)=eq.__invalid_empty__"
        }
        return "\(column)=in.(\(unique.joined(separator: ",")))"
    }

    static func stableRouteSuffix(table: ContentLikeTable, contentIDs: [String]) -> String {
        let unique = Array(Set(contentIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
            .sorted()
        let idsKey = unique.joined(separator: ",")
        if idsKey.isEmpty {
            return "\(table.rawValue)-empty"
        }
        return "\(table.rawValue)-\(idsKey.prefix(48))"
    }

    /// Web parity — same echo / idempotent rules as ``CommentLikeSemantics.applyRealtimeEvent``.
    static func applyRealtimeEvent(
        _ previous: EngagementSnapshot,
        event: RealtimeMutationKind,
        actorUserID: String,
        currentUserID: String?
    ) -> EngagementSnapshot {
        switch event {
        case .insert:
            if actorUserID == currentUserID, previous.viewerHasLiked {
                return previous
            }
            return EngagementSnapshot(
                likeCount: previous.likeCount + 1,
                commentCount: previous.commentCount,
                viewerHasLiked: actorUserID == currentUserID ? true : previous.viewerHasLiked
            )
        case .delete:
            if actorUserID == currentUserID, !previous.viewerHasLiked {
                return previous
            }
            return EngagementSnapshot(
                likeCount: max(0, previous.likeCount - 1),
                commentCount: previous.commentCount,
                viewerHasLiked: actorUserID == currentUserID ? false : previous.viewerHasLiked
            )
        }
    }

    enum RealtimeMutationKind: Sendable {
        case insert
        case delete
    }
}

nonisolated struct ContentLikeRealtimeSignal: Sendable {
    var table: ContentLikeTable
    var contentID: String
    var userID: String
    var kind: ContentLikeSemantics.RealtimeMutationKind
    /// Like row `id` — duplicate Realtime delivery dedupe.
    var rowID: String?
}
