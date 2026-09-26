import Foundation

/// Viewer-scoped on-disk snapshots for Feed first-page timelines.
///
/// Structured metadata only — no image/video blobs. Server + RLS remain authoritative.
nonisolated enum FeedDiskCache {
    static let folderName = "FeedDiskCache"
    static let schemaVersion = 2

    // MARK: - Bounds

    static let maxEntriesPerPage = 30
    static let maxFilterVariants = 10
    static let hardExpirySeconds: TimeInterval = 7 * 24 * 60 * 60

    // MARK: - Blobs

    struct PageBlob: Codable, Sendable {
        var schemaVersion: Int = FeedDiskCache.schemaVersion
        var viewerID: String
        var scope: String
        var contentFilter: String
        var savedAt: Date
        var lastAccessedAt: Date
        var entries: [FeedTimelineEntry]
        var stories: [Story]
        var nextCursor: String?
    }

    struct BlockedPeersBlob: Codable, Sendable {
        var viewerID: String
        var savedAt: Date
        var peerIDs: [String]
    }

    // MARK: - First page

    static func savePage(_ blob: PageBlob) {
        var capped = blob
        capped.entries = Array(
            FeedSupport.sortDescending(blob.entries).prefix(maxEntriesPerPage)
        )
        if capped.scope == FeedScope.following.rawValue {
            capped.stories = Array(blob.stories.prefix(40))
        } else {
            capped.stories = []
        }
        write(capped, file: pageFile(viewerID: blob.viewerID, scope: blob.scope, filter: blob.contentFilter))
        enforceFilterVariantLimit(viewerID: blob.viewerID)
    }

    static func loadPage(
        viewerID: ProfileID,
        scope: FeedScope,
        contentFilter: FeedContentFilter
    ) -> PageBlob? {
        guard let blob: PageBlob = read(
            file: pageFile(
                viewerID: viewerID.rawValue,
                scope: scope.rawValue,
                filter: contentFilter.rpcValue
            )
        ) else { return nil }
        guard blob.schemaVersion == schemaVersion else {
            remove(
                file: pageFile(
                    viewerID: viewerID.rawValue,
                    scope: scope.rawValue,
                    filter: contentFilter.rpcValue
                )
            )
            return nil
        }
        guard blob.viewerID == viewerID.rawValue else { return nil }
        guard blob.scope == scope.rawValue else { return nil }
        guard blob.contentFilter == contentFilter.rpcValue else { return nil }
        let age = Date().timeIntervalSince(blob.savedAt)
        guard age <= hardExpirySeconds else {
            remove(
                file: pageFile(
                    viewerID: viewerID.rawValue,
                    scope: scope.rawValue,
                    filter: contentFilter.rpcValue
                )
            )
            return nil
        }
        return blob
    }

    static func removePage(
        viewerID: ProfileID,
        scope: FeedScope,
        contentFilter: FeedContentFilter
    ) {
        remove(
            file: pageFile(
                viewerID: viewerID.rawValue,
                scope: scope.rawValue,
                filter: contentFilter.rpcValue
            )
        )
    }

    static func allPages(for viewerID: ProfileID) -> [PageBlob] {
        guard let dir = directoryURL() else { return [] }
        let prefix = "feed-page-\(viewerID.rawValue)-"
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap { url -> PageBlob? in
            guard url.lastPathComponent.hasPrefix(prefix) else { return nil }
            return readURL(url)
        }
    }

    /// Disk + decode work for blocked-author pruning — safe off the main actor.
    struct PrunedPageSnapshot: Sendable {
        var cacheKey: String
        var entries: [FeedTimelineEntry]
        var stories: [Story]
        var nextCursor: String?
        var loadedAt: Date
    }

    static func pruneBlockedAuthorsOnDisk(
        viewerID: ProfileID,
        blocked: Set<ProfileID>
    ) -> [PrunedPageSnapshot] {
        guard !blocked.isEmpty else { return [] }
        var patches: [PrunedPageSnapshot] = []
        for blob in allPages(for: viewerID) {
            guard let scope = FeedScope(rawValue: blob.scope),
                  let filter = contentFilter(fromRPC: blob.contentFilter)
            else { continue }
            let filteredEntries = blob.entries.filter { !blocked.contains($0.authorProfileID) }
            let filteredStories = blob.stories.filter { !blocked.contains($0.authorProfileID) }
            guard filteredEntries.count != blob.entries.count
                || filteredStories.count != blob.stories.count
            else { continue }

            var updated = blob
            updated.entries = filteredEntries
            updated.stories = filteredStories
            savePage(updated)

            let cacheKey = "\(viewerID.rawValue)|\(scope.rawValue)|\(filter.rpcValue)|-"
            patches.append(
                PrunedPageSnapshot(
                    cacheKey: cacheKey,
                    entries: filteredEntries,
                    stories: filteredStories,
                    nextCursor: blob.nextCursor,
                    loadedAt: blob.savedAt
                )
            )
        }
        return patches
    }

    static func pruneViewerOwnContentOnDisk(viewerID: ProfileID) -> [PrunedPageSnapshot] {
        var patches: [PrunedPageSnapshot] = []
        for blob in allPages(for: viewerID) {
            guard let scope = FeedScope(rawValue: blob.scope),
                  let filter = contentFilter(fromRPC: blob.contentFilter)
            else { continue }
            let filteredEntries = blob.entries.filter { $0.authorProfileID != viewerID }
            guard filteredEntries.count != blob.entries.count else { continue }

            var updated = blob
            updated.entries = filteredEntries
            savePage(updated)

            let cacheKey = "\(viewerID.rawValue)|\(scope.rawValue)|\(filter.rpcValue)|-"
            patches.append(
                PrunedPageSnapshot(
                    cacheKey: cacheKey,
                    entries: filteredEntries,
                    stories: blob.stories,
                    nextCursor: blob.nextCursor,
                    loadedAt: blob.savedAt
                )
            )
        }
        return patches
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

    // MARK: - Block peers

    static func saveBlockedPeers(_ blob: BlockedPeersBlob) {
        write(blob, file: blockedPeersFile(viewerID: blob.viewerID))
    }

    static func loadBlockedPeers(for viewerID: ProfileID) -> BlockedPeersBlob? {
        read(file: blockedPeersFile(viewerID: viewerID.rawValue))
    }

    // MARK: - Session isolation

    static func clear(viewerID: ProfileID) {
        removeMatching(prefix: "feed-page-\(viewerID.rawValue)-")
        remove(file: blockedPeersFile(viewerID: viewerID.rawValue))
    }

    static func clearAll() {
        guard let dir = directoryURL() else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - LRU enforcement

    private static func enforceFilterVariantLimit(viewerID: String) {
        guard let dir = directoryURL() else { return }
        let prefix = "feed-page-\(viewerID)-"
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let pageFiles = urls.filter { $0.lastPathComponent.hasPrefix(prefix) }
        guard pageFiles.count > maxFilterVariants else { return }

        let ranked: [(URL, Date)] = pageFiles.compactMap { url in
            guard let blob: PageBlob = readURL(url) else { return nil }
            return (url, blob.lastAccessedAt)
        }
        .sorted { $0.1 < $1.1 }

        for entry in ranked.prefix(ranked.count - maxFilterVariants) {
            try? FileManager.default.removeItem(at: entry.0)
        }
    }

    // MARK: - IO

    private static func pageFile(viewerID: String, scope: String, filter: String) -> String {
        "feed-page-\(viewerID)-\(scope)-\(filter).json"
    }

    private static func blockedPeersFile(viewerID: String) -> String {
        "feed-blocks-\(viewerID).json"
    }

    private static func directoryURL() -> URL? {
        PersistentAppDataDiskCache.directoryURL(component: folderName)
    }

    private static func write<T: Encodable>(_ value: T, file: String) {
        guard let dir = directoryURL() else { return }
        let url = dir.appendingPathComponent(sanitize(file))
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Soft-fail — disk cache must never break networking.
        }
    }

    private static func read<T: Decodable>(file: String) -> T? {
        guard let dir = directoryURL() else { return nil }
        let url = dir.appendingPathComponent(sanitize(file))
        return readURL(url)
    }

    static func readURL<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func remove(file: String) {
        guard let dir = directoryURL() else { return }
        let url = dir.appendingPathComponent(sanitize(file))
        try? FileManager.default.removeItem(at: url)
    }

    private static func removeMatching(prefix: String) {
        guard let dir = directoryURL() else { return }
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for url in urls where url.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func sanitize(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "_")
    }
}
