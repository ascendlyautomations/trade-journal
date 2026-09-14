import Foundation

/// Deterministic first-page merge after a cached Feed render.
nonisolated enum FeedPersistentReconcile {
    struct Result: Sendable {
        var entries: [FeedTimelineEntry]
        var inserted: Int
        var updated: Int
        var removed: Int
    }

    /// Server first page is authoritative for the overlapping window; older paginated tail is preserved.
    static func reconcileFirstPage(
        existing: [FeedTimelineEntry],
        incoming: [FeedTimelineEntry],
        preserveEntryIDs: Set<String> = []
    ) -> Result {
        let sortedIncoming = FeedSupport.sortDescending(incoming)
        let incomingIDs = Set(sortedIncoming.map(\.id))
        let incomingOldest = sortedIncoming.last?.createdAt

        var inserted = 0
        var updated = 0
        var removed = 0
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        if let oldest = incomingOldest {
            for (id, entry) in byID where entry.createdAt >= oldest && !incomingIDs.contains(id) {
                if preserveEntryIDs.contains(id) { continue }
                byID.removeValue(forKey: id)
                removed += 1
            }
        }

        for entry in sortedIncoming {
            if let prior = byID[entry.id] {
                if prior != entry {
                    updated += 1
                }
                byID[entry.id] = entry
            } else {
                inserted += 1
                byID[entry.id] = entry
            }
        }

        let merged = FeedSupport.sortDescending(Array(byID.values))
        return Result(entries: merged, inserted: inserted, updated: updated, removed: removed)
    }

    /// Dedupes by id, keeping the first occurrence in input order.
    static func dedupe(_ entries: [FeedTimelineEntry]) -> [FeedTimelineEntry] {
        var seen = Set<String>()
        var result: [FeedTimelineEntry] = []
        for entry in entries where seen.insert(entry.id).inserted {
            result.append(entry)
        }
        return FeedSupport.sortDescending(result)
    }
}
