import Foundation

/// Deterministic Profile section merge after a cached first render.
nonisolated enum ProfilePersistentReconcile {
    struct Counts: Sendable {
        var inserted: Int
        var updated: Int
        var removed: Int
    }

    static func reconcileTrades(
        existing: [Trade],
        incoming: [Trade],
        preserveIDs: Set<TradeID> = []
    ) -> (items: [Trade], counts: Counts) {
        reconcileByCreatedAt(
            existing: existing,
            incoming: incoming,
            createdAt: \.createdAt,
            preserveIDs: preserveIDs
        )
    }

    static func reconcileTradeSummaries(
        existing: [TradeSummary],
        incoming: [TradeSummary],
        preserveIDs: Set<TradeID> = []
    ) -> (items: [TradeSummary], counts: Counts) {
        reconcileByCreatedAt(
            existing: existing,
            incoming: incoming,
            createdAt: \.createdAt,
            preserveIDs: preserveIDs
        )
    }

    static func reconcilePosts(existing: [Post], incoming: [Post]) -> (items: [Post], counts: Counts) {
        reconcileByCreatedAt(existing: existing, incoming: incoming, createdAt: \.createdAt)
    }

    static func reconcileClips(existing: [Reel], incoming: [Reel]) -> (items: [Reel], counts: Counts) {
        reconcileByCreatedAt(existing: existing, incoming: incoming, createdAt: \.createdAt)
    }

    static func reconcileAchievements(
        existing: [Achievement],
        incoming: [Achievement]
    ) -> (items: [Achievement], counts: Counts) {
        reconcileByCreatedAt(existing: existing, incoming: incoming, createdAt: \.achievedAt)
    }

    static func reconcileProfileState(
        existing: ProfileState,
        incoming: ProfileState,
        preservePublicTradeIDs: Set<TradeID> = []
    ) -> ProfileState {
        var merged = incoming
        if incoming.didLoadTrades && !existing.trades.isEmpty {
            let result = reconcileTradeSummaries(
                existing: existing.trades,
                incoming: incoming.trades,
                preserveIDs: preservePublicTradeIDs
            )
            merged.trades = result.items
            logSection("trades", result.counts)
        }
        if incoming.didLoadPosts && !existing.posts.isEmpty {
            merged.posts = reconcilePosts(existing: existing.posts, incoming: incoming.posts).items
        }
        if incoming.didLoadClips && !existing.clips.isEmpty {
            merged.clips = reconcileClips(existing: existing.clips, incoming: incoming.clips).items
        }
        if incoming.didLoadAchievements && !existing.achievements.isEmpty {
            merged.achievements = reconcileAchievements(
                existing: existing.achievements,
                incoming: incoming.achievements
            ).items
        }
        return preservingAbsentSectionLoads(incoming: merged, existing: existing)
    }

    /// Incoming bootstrap omitted a section that was already resolved (including authoritative empty).
    static func preservingAbsentSectionLoads(
        incoming: ProfileState,
        existing: ProfileState
    ) -> ProfileState {
        var next = incoming
        if existing.didLoadPosts, !incoming.didLoadPosts, incoming.posts.isEmpty {
            next.didLoadPosts = true
            next.posts = existing.posts
        }
        if existing.didLoadClips, !incoming.didLoadClips, incoming.clips.isEmpty {
            next.didLoadClips = true
            next.clips = existing.clips
        }
        if existing.didLoadTrades, !incoming.didLoadTrades, incoming.trades.isEmpty {
            next.didLoadTrades = true
            next.trades = existing.trades
            if incoming.tradesNextCursor == nil {
                next.tradesNextCursor = existing.tradesNextCursor
            }
        }
        if existing.didLoadAchievements, !incoming.didLoadAchievements, incoming.achievements.isEmpty {
            next.didLoadAchievements = true
            next.achievements = existing.achievements
        }
        return next
    }

    private static func reconcileByCreatedAt<T: Identifiable & Equatable>(
        existing: [T],
        incoming: [T],
        createdAt: KeyPath<T, Date>,
        preserveIDs: Set<T.ID> = []
    ) -> (items: [T], counts: Counts) where T.ID: Hashable {
        let sortedIncoming = incoming.sorted { $0[keyPath: createdAt] > $1[keyPath: createdAt] }
        let incomingIDs = Set(sortedIncoming.map(\.id))
        let incomingOldest = sortedIncoming.last.map { $0[keyPath: createdAt] }

        var inserted = 0
        var updated = 0
        var removed = 0
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        if let oldest = incomingOldest {
            for (id, item) in byID where item[keyPath: createdAt] >= oldest && !incomingIDs.contains(id) {
                if preserveIDs.contains(id) { continue }
                byID.removeValue(forKey: id)
                removed += 1
            }
        }

        for item in sortedIncoming {
            if let prior = byID[item.id] {
                if prior != item {
                    updated += 1
                }
                byID[item.id] = item
            } else {
                inserted += 1
                byID[item.id] = item
            }
        }

        let merged = Array(byID.values).sorted { $0[keyPath: createdAt] > $1[keyPath: createdAt] }
        return (merged, Counts(inserted: inserted, updated: updated, removed: removed))
    }

    private static func logSection(_ section: String, _ counts: Counts) {
        #if DEBUG
        print(
            "[ProfilePersistentCache] section=\(section) inserted=\(counts.inserted) updated=\(counts.updated) removed=\(counts.removed)"
        )
        #endif
    }
}
