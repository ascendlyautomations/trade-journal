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
            FeedPersistedCacheCoordinator.clear(viewerID: viewerID)
        } else {
            snapshots = [:]
            FeedPersistedCacheCoordinator.clearAll()
        }
    }

    struct SharedContentSeed: Sendable {
        var item: FeedItem
        var trade: Trade?
        var post: Post?
        var reel: Reel?
        var achievement: Achievement?

        var syntheticFeedPost: Post {
            let caption = item.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let body = caption.isEmpty ? (trade?.publicCaption ?? "") : caption
            let media: [MediaReference]
            if let url = item.mediaURL?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
                media = [MediaReference(id: url, kind: .image, altText: nil)]
            } else if let thumb = trade?.thumbnail {
                media = [thumb]
            } else {
                media = []
            }
            return Post(
                id: PostID(item.id),
                authorProfileID: item.authorProfileID,
                body: body,
                media: media,
                visibility: trade?.visibility ?? .public,
                linkedTradeID: trade?.id,
                isPinned: false,
                createdAt: item.createdAt,
                updatedAt: item.createdAt
            )
        }
    }

    /// Lookup hydrated feed entities for shared message cards — reuses session feed snapshots.
    func lookup(reference: SharedContentReference, viewerID: ProfileID) -> SharedContentSeed? {
        let prefix = "\(viewerID.rawValue)|"
        for snapshot in snapshots.values where snapshot.cacheKey.hasPrefix(prefix) {
            for entry in snapshot.entries {
                if let seed = match(entry: entry, reference: reference) {
                    return seed
                }
            }
        }
        return nil
    }

    func lookupTrade(id: TradeID, viewerID: ProfileID) -> Trade? {
        let prefix = "\(viewerID.rawValue)|"
        for snapshot in snapshots.values where snapshot.cacheKey.hasPrefix(prefix) {
            for entry in snapshot.entries {
                if case .trade(_, let trade) = entry, trade.id == id {
                    return trade
                }
            }
        }
        return nil
    }

    private func match(entry: FeedTimelineEntry, reference: SharedContentReference) -> SharedContentSeed? {
        switch (reference, entry) {
        case (.feedPost(let id), .trade(let item, let trade)) where PostID(item.id) == id:
            return SharedContentSeed(item: item, trade: trade, post: nil, reel: nil, achievement: nil)
        case (.feedPost(let id), .post(let item, let post)) where post.id == id:
            return SharedContentSeed(item: item, trade: nil, post: post, reel: nil, achievement: nil)
        case (.profilePost(let id), .post(let item, let post)) where post.id == id:
            return SharedContentSeed(item: item, trade: nil, post: post, reel: nil, achievement: nil)
        case (.reel(let id), .clip(let item, let reel)) where reel.id == id:
            return SharedContentSeed(item: item, trade: nil, post: nil, reel: reel, achievement: nil)
        case (.achievementPost(let id), .achievement(let item, let achievement)) where PostID(item.id) == id:
            return SharedContentSeed(item: item, trade: nil, post: nil, reel: nil, achievement: achievement)
        case (.trade(let id), .trade(_, let trade)) where trade.id == id:
            return SharedContentSeed(item: entry.item, trade: trade, post: nil, reel: nil, achievement: nil)
        default:
            return nil
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
