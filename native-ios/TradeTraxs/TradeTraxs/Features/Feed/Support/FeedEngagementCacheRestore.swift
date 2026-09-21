import Foundation

/// Restores Feed engagement into ``EngagementStore`` from persisted timeline rows.
enum FeedEngagementCacheRestore {
    struct RestoreSummary: Sendable {
        var restoredFromExplicitFlag: Int
        var restoredLegacyImplicit: Int
        var skippedIncomplete: Int
    }

    static func snapshot(for entry: FeedTimelineEntry) -> EngagementSnapshot {
        let item = entry.item
        return EngagementSnapshot(
            likeCount: item.likeCount,
            commentCount: item.commentCount,
            viewerHasLiked: item.viewerHasLiked
        )
    }

    static func engagementMap(from entries: [FeedTimelineEntry]) -> [InteractionTarget: EngagementSnapshot] {
        var map: [InteractionTarget: EngagementSnapshot] = [:]
        map.reserveCapacity(entries.count)
        for entry in entries {
            map[entry.interactionTarget] = snapshot(for: entry)
        }
        return map
    }

    /// Seeds the session engagement store from cached Feed rows before first paint.
    @MainActor
    static func seedEngagementStore(
        from entries: [FeedTimelineEntry],
        into store: EngagementStore
    ) -> RestoreSummary {
        var summary = RestoreSummary(restoredFromExplicitFlag: 0, restoredLegacyImplicit: 0, skippedIncomplete: 0)
        for entry in entries {
            let target = entry.interactionTarget
            if store.hasLoaded(target) { continue }
            if entry.item.engagementStateCached == true {
                store.seed(snapshot(for: entry), for: target)
                summary.restoredFromExplicitFlag += 1
            } else if entry.item.engagementStateCached == false {
                summary.skippedIncomplete += 1
            } else {
                // Legacy persisted timelines — trust embedded FeedItem counts.
                store.seed(snapshot(for: entry), for: target)
                summary.restoredLegacyImplicit += 1
            }
        }
        return summary
    }

    static func markEngagementCached(on item: inout FeedItem) {
        item.engagementStateCached = true
    }
}
