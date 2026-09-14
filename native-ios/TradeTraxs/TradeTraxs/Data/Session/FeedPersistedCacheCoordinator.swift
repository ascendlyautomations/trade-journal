import Foundation

/// Central write-through for viewer-scoped Feed disk snapshots.
@MainActor
enum FeedPersistedCacheCoordinator {
    // MARK: - Hydrate

    /// Loads all persisted first-page snapshots for a viewer into ``FeedSessionStore``.
    @discardableResult
    static func hydrateSessionStore(
        viewerID: ProfileID,
        scope: FeedScope? = nil,
        contentFilter: FeedContentFilter? = nil,
        detailCache: DetailPresentationCache? = nil,
        blockedFilter: FeedBlockedAuthorsFilter? = nil
    ) -> Bool {
        if let blockedFilter, let blob = FeedDiskCache.loadBlockedPeers(for: viewerID) {
            let peers = Set(blob.peerIDs.map { ProfileID($0) })
            blockedFilter.replaceAll(peers)
        }

        var hydratedAny = false
        let scopes: [FeedScope] = scope.map { [$0] } ?? FeedScope.allCases
        let filters: [FeedContentFilter] = contentFilter.map { [$0] } ?? FeedContentFilter.allCases

        for feedScope in scopes {
            for filter in filters {
                guard let blob = FeedDiskCache.loadPage(
                    viewerID: viewerID,
                    scope: feedScope,
                    contentFilter: filter
                ) else { continue }

                let key = FeedSessionStore.cacheKey(
                    viewerID: viewerID,
                    scope: feedScope,
                    contentFilter: filter,
                    cursor: nil
                )
                let snapshot = FeedSessionStore.Snapshot(
                    cacheKey: key,
                    entries: blob.entries,
                    stories: blob.stories,
                    nextCursor: blob.nextCursor,
                    loadedAt: blob.savedAt
                )
                FeedSessionStore.shared.save(snapshot)
                if let detailCache {
                    seedDetailCache(from: snapshot.entries, stories: snapshot.stories, detailCache: detailCache)
                }
                hydratedAny = true
            }
        }
        return hydratedAny
    }

    /// Loads a single scope/filter page from disk into ``FeedSessionStore``.
    static func hydratePage(
        viewerID: ProfileID,
        scope: FeedScope,
        contentFilter: FeedContentFilter,
        detailCache: DetailPresentationCache? = nil,
        blockedFilter: FeedBlockedAuthorsFilter? = nil
    ) -> (entries: Int, ageMs: Int)? {
        applyBlockedPeersIfNeeded(viewerID: viewerID, blockedFilter: blockedFilter)
        guard let loaded = loadPageBlobFromDisk(
            viewerID: viewerID,
            scope: scope,
            contentFilter: contentFilter
        ) else { return nil }
        applyLoadedPage(
            blob: loaded.blob,
            viewerID: viewerID,
            scope: scope,
            contentFilter: contentFilter,
            detailCache: detailCache
        )
        return (loaded.blob.entries.count, loaded.ageMs)
    }

    /// Disk decode off the hot path — session snapshot on MainActor; detail seeds deferred.
    static func hydratePageAsync(
        viewerID: ProfileID,
        scope: FeedScope,
        contentFilter: FeedContentFilter,
        detailCache: DetailPresentationCache? = nil,
        blockedFilter: FeedBlockedAuthorsFilter? = nil
    ) async -> (entries: Int, ageMs: Int)? {
        struct Payload: Sendable {
            var blob: FeedDiskCache.PageBlob
            var ageMs: Int
            var blockedPeerIDs: [String]?
        }

        let payload = await Task.detached(priority: .userInitiated) { () -> Payload? in
            guard let blob = FeedDiskCache.loadPage(
                viewerID: viewerID,
                scope: scope,
                contentFilter: contentFilter
            ) else { return nil }
            let blockedPeerIDs = FeedDiskCache.loadBlockedPeers(for: viewerID)?.peerIDs
            let ageMs = Int(Date().timeIntervalSince(blob.savedAt) * 1000)
            return Payload(blob: blob, ageMs: ageMs, blockedPeerIDs: blockedPeerIDs)
        }.value

        guard let payload else { return nil }

        if let blockedFilter, let peerIDs = payload.blockedPeerIDs {
            blockedFilter.replaceAll(Set(peerIDs.map { ProfileID($0) }))
        }

        let entries = payload.blob.entries
        let stories = payload.blob.stories

        MainThreadWorkProbe.measure("feed.cache.apply", surface: "feed") {
            applySessionSnapshot(
                blob: payload.blob,
                viewerID: viewerID,
                scope: scope,
                contentFilter: contentFilter
            )
        }

        if let detailCache {
            Task(priority: .utility) { @MainActor in
                MainThreadWorkProbe.measure("feed.cache.detailSeed", surface: "feed") {
                    seedDetailCache(from: entries, stories: stories, detailCache: detailCache)
                }
            }
        }

        return (entries.count, payload.ageMs)
    }

    // MARK: - Persist

    static func persist(snapshot: FeedSessionStore.Snapshot, engagementStore: EngagementStore? = nil) {
        guard let parsed = parseFirstPageKey(snapshot.cacheKey) else { return }
        var entries = snapshot.entries
        if let engagementStore {
            entries = syncEngagement(into: entries, engagementStore: engagementStore)
        }
        let blob = FeedDiskCache.PageBlob(
            viewerID: parsed.viewerID.rawValue,
            scope: parsed.scope.rawValue,
            contentFilter: parsed.contentFilter.rpcValue,
            savedAt: Date(),
            lastAccessedAt: Date(),
            entries: entries,
            stories: snapshot.stories,
            nextCursor: snapshot.nextCursor
        )
        let pageBlob = blob
        Task.detached(priority: .utility) {
            FeedDiskCache.savePage(pageBlob)
        }
    }

    static func persistFirstPage(
        viewerID: ProfileID,
        scope: FeedScope,
        contentFilter: FeedContentFilter,
        entries: [FeedTimelineEntry],
        stories: [Story],
        nextCursor: String?,
        engagementStore: EngagementStore? = nil
    ) {
        let key = FeedSessionStore.cacheKey(
            viewerID: viewerID,
            scope: scope,
            contentFilter: contentFilter,
            cursor: nil
        )
        let snapshot = FeedSessionStore.Snapshot(
            cacheKey: key,
            entries: entries,
            stories: stories,
            nextCursor: nextCursor,
            loadedAt: Date()
        )
        FeedSessionStore.shared.save(snapshot)
        persist(snapshot: snapshot, engagementStore: engagementStore)
    }

    static func persistBlockedPeers(viewerID: ProfileID, peers: Set<ProfileID>) {
        let blob = FeedDiskCache.BlockedPeersBlob(
            viewerID: viewerID.rawValue,
            savedAt: Date(),
            peerIDs: peers.map(\.rawValue).sorted()
        )
        Task.detached(priority: .utility) {
            FeedDiskCache.saveBlockedPeers(blob)
        }
    }

    // MARK: - Prune

    /// Rewrites pruned feed pages on a background queue — never blocks tab transition.
    static func pruneBlockedAuthors(viewerID: ProfileID, blocked: Set<ProfileID>) {
        guard !blocked.isEmpty else { return }
        let viewerCopy = viewerID
        let blockedCopy = blocked
        Task.detached(priority: .utility) {
            let patches = FeedDiskCache.pruneBlockedAuthorsOnDisk(
                viewerID: viewerCopy,
                blocked: blockedCopy
            )
            guard !patches.isEmpty else { return }
            await MainActor.run {
                MainThreadWorkProbe.measure("feed.blockPrune.apply", surface: "feed") {
                    for patch in patches {
                        if var snapshot = FeedSessionStore.shared.restore(key: patch.cacheKey) {
                            snapshot.entries = patch.entries
                            snapshot.stories = patch.stories
                            FeedSessionStore.shared.save(snapshot)
                        } else {
                            FeedSessionStore.shared.save(
                                FeedSessionStore.Snapshot(
                                    cacheKey: patch.cacheKey,
                                    entries: patch.entries,
                                    stories: patch.stories,
                                    nextCursor: patch.nextCursor,
                                    loadedAt: patch.loadedAt
                                )
                            )
                        }
                    }
                }
            }
        }
    }

    static func patchTrade(_ trade: Trade, viewerID: ProfileID) {
        SocialEntityDiskCache.saveTrade(trade, viewerID: viewerID)
        for blob in FeedDiskCache.allPages(for: viewerID) {
            var changed = false
            let updatedEntries = blob.entries.map { entry -> FeedTimelineEntry in
                switch entry {
                case .trade(let item, let existing) where existing.id == trade.id:
                    changed = true
                    return .trade(item, trade)
                default:
                    return entry
                }
            }
            guard changed,
                  let scope = FeedScope(rawValue: blob.scope),
                  let filter = contentFilter(fromRPC: blob.contentFilter)
            else { continue }
            persistFirstPage(
                viewerID: viewerID,
                scope: scope,
                contentFilter: filter,
                entries: updatedEntries,
                stories: blob.stories,
                nextCursor: blob.nextCursor
            )
        }
    }

    static func removeEntry(viewerID: ProfileID, entryID: String) {
        for blob in FeedDiskCache.allPages(for: viewerID) {
            guard blob.entries.contains(where: { $0.id == entryID }) else { continue }
            guard let scope = FeedScope(rawValue: blob.scope),
                  let filter = contentFilter(fromRPC: blob.contentFilter)
            else { continue }
            let filtered = blob.entries.filter { $0.id != entryID }
            persistFirstPage(
                viewerID: viewerID,
                scope: scope,
                contentFilter: filter,
                entries: filtered,
                stories: blob.stories,
                nextCursor: blob.nextCursor
            )
        }
        for scope in FeedScope.allCases {
            for snapshot in FeedSessionStore.shared.firstPageSnapshots(viewerID: viewerID, scope: scope) {
                var copy = snapshot
                guard copy.entries.contains(where: { $0.id == entryID }) else { continue }
                copy.entries.removeAll { $0.id == entryID }
                FeedSessionStore.shared.save(copy)
            }
        }
    }

    // MARK: - Session isolation

    static func clear(viewerID: ProfileID) {
        FeedDiskCache.clear(viewerID: viewerID)
    }

    static func clearAll() {
        FeedDiskCache.clearAll()
    }

    // MARK: - Helpers

    private static func parseFirstPageKey(_ key: String) -> (
        viewerID: ProfileID,
        scope: FeedScope,
        contentFilter: FeedContentFilter
    )? {
        let parts = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts[3] == "-" else { return nil }
        guard let scope = FeedScope(rawValue: parts[1]),
              let filter = contentFilter(fromRPC: parts[2])
        else { return nil }
        return (ProfileID(parts[0]), scope, filter)
    }

    private static func contentFilter(fromRPC value: String) -> FeedContentFilter? {
        switch value {
        case "all": return .all
        case "trades": return .trades
        case "posts": return .posts
        case "reels": return .clips
        case "achievements": return .achievements
        default: return nil
        }
    }

    private static func applyBlockedPeersIfNeeded(
        viewerID: ProfileID,
        blockedFilter: FeedBlockedAuthorsFilter?
    ) {
        guard let blockedFilter, let peers = FeedDiskCache.loadBlockedPeers(for: viewerID) else { return }
        blockedFilter.replaceAll(Set(peers.peerIDs.map { ProfileID($0) }))
    }

    private static func loadPageBlobFromDisk(
        viewerID: ProfileID,
        scope: FeedScope,
        contentFilter: FeedContentFilter
    ) -> (blob: FeedDiskCache.PageBlob, ageMs: Int)? {
        guard let blob = FeedDiskCache.loadPage(
            viewerID: viewerID,
            scope: scope,
            contentFilter: contentFilter
        ) else {
            return nil
        }
        let ageMs = Int(Date().timeIntervalSince(blob.savedAt) * 1000)
        return (blob, ageMs)
    }

    private static func applyLoadedPage(
        blob: FeedDiskCache.PageBlob,
        viewerID: ProfileID,
        scope: FeedScope,
        contentFilter: FeedContentFilter,
        detailCache: DetailPresentationCache?
    ) {
        applySessionSnapshot(
            blob: blob,
            viewerID: viewerID,
            scope: scope,
            contentFilter: contentFilter
        )
        if let detailCache {
            seedDetailCache(from: blob.entries, stories: blob.stories, detailCache: detailCache)
        }
    }

    private static func applySessionSnapshot(
        blob: FeedDiskCache.PageBlob,
        viewerID: ProfileID,
        scope: FeedScope,
        contentFilter: FeedContentFilter
    ) {
        let key = FeedSessionStore.cacheKey(
            viewerID: viewerID,
            scope: scope,
            contentFilter: contentFilter,
            cursor: nil
        )
        FeedSessionStore.shared.save(
            FeedSessionStore.Snapshot(
                cacheKey: key,
                entries: blob.entries,
                stories: blob.stories,
                nextCursor: blob.nextCursor,
                loadedAt: blob.savedAt
            )
        )
    }

    private static func seedDetailCache(
        from entries: [FeedTimelineEntry],
        stories: [Story],
        detailCache: DetailPresentationCache
    ) {
        for entry in entries {
            FeedBootstrap.seedAuthor(from: entry.item, detailCache: detailCache)
            switch entry {
            case .trade(_, let trade):
                detailCache.seed(trade)
            case .post(_, let post):
                detailCache.seed(post)
            case .clip(_, let reel):
                detailCache.seed(reel)
            case .achievement(_, let achievement):
                detailCache.seed(achievement)
            }
        }
        detailCache.seed(stories: stories)
    }

    private static func syncEngagement(
        into entries: [FeedTimelineEntry],
        engagementStore: EngagementStore
    ) -> [FeedTimelineEntry] {
        entries.map { entry in
            let snap = engagementStore.snapshot(for: entry.interactionTarget)
            guard snap != .empty else { return entry }
            var item = entry.item
            item.likeCount = snap.likeCount
            item.commentCount = snap.commentCount
            item.viewerHasLiked = snap.viewerHasLiked
            switch entry {
            case .trade(_, let trade):
                return .trade(item, trade)
            case .post(_, let post):
                return .post(item, post)
            case .clip(_, let reel):
                return .clip(item, reel)
            case .achievement(_, let achievement):
                return .achievement(item, achievement)
            }
        }
    }
}
