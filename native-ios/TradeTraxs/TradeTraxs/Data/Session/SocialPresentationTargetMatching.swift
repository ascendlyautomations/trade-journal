import Foundation

/// Maps engagement mutation targets onto cached Feed / Profile rows (no network).
enum SocialPresentationTargetMatching {
    static func matches(entry: FeedTimelineEntry, target: InteractionTarget) -> Bool {
        if entry.interactionTarget == target { return true }
        switch (target.kind, entry.interactionTarget.kind) {
        case (.feedPost, .profilePost), (.profilePost, .feedPost):
            return target.id == entry.interactionTarget.id
        default:
            break
        }
        switch target.kind {
        case .trade:
            if case .trade(_, let summary) = entry, summary.id.rawValue == target.id { return true }
            if case .trade(let item, _) = entry, item.tradeID?.rawValue == target.id { return true }
        case .achievement:
            if case .achievement(let item, _) = entry, item.achievementID?.rawValue == target.id {
                return true
            }
            if case .achievement(_, let achievement) = entry, achievement.id.rawValue == target.id {
                return true
            }
        case .feedPost, .profilePost, .reel:
            break
        }
        return false
    }

    static func profileContains(target: InteractionTarget, state: ProfileState) -> Bool {
        switch target.kind {
        case .trade:
            return state.trades.contains { $0.id.rawValue == target.id }
        case .profilePost, .feedPost:
            return state.posts.contains { $0.id.rawValue == target.id }
        case .reel:
            return state.clips.contains { $0.id.rawValue == target.id }
        case .achievement:
            return state.achievements.contains { $0.id.rawValue == target.id }
        }
    }
}

extension InteractionTarget {
    var presentationStorageKey: String { "\(kind.rawValue)|\(id)" }

    init?(presentationStorageKey: String) {
        let parts = presentationStorageKey.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = InteractionContentKind(rawValue: parts[0]) else { return nil }
        self.init(kind: kind, id: parts[1])
    }
}

extension FeedTimelineEntry {
    func patchingEngagement(_ snapshot: EngagementSnapshot) -> FeedTimelineEntry {
        var item = self.item
        item.likeCount = snapshot.likeCount
        item.commentCount = snapshot.commentCount
        item.viewerHasLiked = snapshot.viewerHasLiked
        FeedEngagementCacheRestore.markEngagementCached(on: &item)
        switch self {
        case .trade(_, let summary):
            return .trade(item, summary)
        case .post(_, let post):
            return .post(item, post)
        case .clip(_, let reel):
            return .clip(item, reel)
        case .achievement(_, let achievement):
            return .achievement(item, achievement)
        }
    }
}
