import Foundation

/// Session memory for Feed timeline — survives tab switches within the authenticated session.
@MainActor
final class FeedSessionStore {
    static let shared = FeedSessionStore()

    struct Snapshot: Sendable {
        var cacheKey: String
        var entries: [FeedTimelineEntry]
        var stories: [Story]
        var nextCursor: String?
        var loadedAt: Date
    }

    private var snapshots: [String: Snapshot] = [:]

    private init() {}

    static func cacheKey(
        viewerID: ProfileID,
        scope: FeedScope,
        contentFilter: FeedContentFilter,
        cursor: String?
    ) -> String {
        "\(viewerID.rawValue)|\(scope.rawValue)|\(contentFilter.rpcValue)|\(cursor ?? "-")"
    }

    func restore(key: String) -> Snapshot? {
        snapshots[key]
    }

    /// All first-page snapshots for a viewer + scope (any content filter).
    func firstPageSnapshots(viewerID: ProfileID, scope: FeedScope) -> [Snapshot] {
        let prefix = "\(viewerID.rawValue)|\(scope.rawValue)|"
        return snapshots.values.filter { snapshot in
            snapshot.cacheKey.hasPrefix(prefix) && snapshot.cacheKey.hasSuffix("|-")
        }
    }

    /// Exact filter cache or merged rows from sibling filter caches in this session.
    func resolvedEntries(
        viewerID: ProfileID,
        scope: FeedScope,
        contentFilter: FeedContentFilter
    ) -> (entries: [FeedTimelineEntry], source: FeedFilterCacheSource) {
        let exactKey = Self.cacheKey(
            viewerID: viewerID,
            scope: scope,
            contentFilter: contentFilter,
            cursor: nil
        )
        if let cached = restore(key: exactKey) {
            return (cached.entries, .exactFilterCache)
        }

        var seen = Set<String>()
        var merged: [FeedTimelineEntry] = []
        for snapshot in firstPageSnapshots(viewerID: viewerID, scope: scope) {
            for entry in snapshot.entries where entry.matches(filter: contentFilter) {
                if seen.insert(entry.id).inserted {
                    merged.append(entry)
                }
            }
        }
        if merged.isEmpty {
            return ([], .none)
        }
        return (FeedSupport.sortDescending(merged), .siblingFilterCache)
    }

    func save(_ snapshot: Snapshot) {
        snapshots[snapshot.cacheKey] = snapshot
    }

    func invalidate(viewerID: ProfileID? = nil) {
        if let viewerID {
            let prefix = viewerID.rawValue + "|"
            snapshots = snapshots.filter { !$0.key.hasPrefix(prefix) }
        } else {
            snapshots = [:]
        }
    }

    /// Newest active viewer story from any cached Following-scope bootstrap snapshot.
    func activeViewerStory(viewerID: ProfileID, now: Date = Date()) -> Story? {
        let prefix = "\(viewerID.rawValue)|\(FeedScope.following.rawValue)|"
        var best: Story?
        for snapshot in snapshots.values where snapshot.cacheKey.hasPrefix(prefix) {
            guard let candidate = snapshot.stories.first(where: { $0.authorProfileID == viewerID }) else {
                continue
            }
            guard ActiveStorySemantics.isActive(createdAt: candidate.createdAt, now: now) else { continue }
            if let best, candidate.createdAt <= best.createdAt { continue }
            best = candidate
        }
        return best
    }
}
