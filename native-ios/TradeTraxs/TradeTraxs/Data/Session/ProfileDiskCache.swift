import Foundation

/// Viewer-scoped on-disk snapshots for Profile first paint + recent section payloads.
///
/// Structured metadata only — no media blobs. Server + RLS remain authoritative.
nonisolated enum ProfileDiskCache {
    static let folderName = "ProfileDiskCache"
    static let schemaVersion = 1

    // MARK: - Bounds

    static let maxProfilesPerViewer = 20
    static let maxTradesPerProfile = 30
    static let maxPostsPerProfile = 50
    static let maxClipsPerProfile = 30
    static let maxAchievementsPerProfile = 30
    static let hardExpirySeconds: TimeInterval = 7 * 24 * 60 * 60

    // MARK: - Blob

    struct SnapshotBlob: Codable, Sendable {
        var schemaVersion: Int = ProfileDiskCache.schemaVersion
        var viewerID: String
        var targetProfileID: String
        var savedAt: Date
        var lastAccessedAt: Date

        var profile: Profile
        var stats: ProfileStats?
        var isOwner: Bool
        var isFollowing: Bool
        var isRequested: Bool
        var followsYou: Bool
        var canViewTrades: Bool
        var ownedTradeRoom: TradeRoom?
        var didResolveTradeRoom: Bool
        var activeStories: [Story]
        var pinnedContent: [ProfilePinnedItem]

        var trades: [Trade]
        var tradesNextCursor: String?
        var accountNames: [String: String]
        var accountModes: [String: String]
        var accountSizes: [String: String]

        var posts: [Post]
        var clips: [Reel]
        var achievements: [Achievement]

        var didLoadTrades: Bool
        var didLoadPosts: Bool
        var didLoadClips: Bool
        var didLoadAchievements: Bool
    }

    // MARK: - IO

    static func saveSnapshot(_ blob: SnapshotBlob) {
        var capped = blob
        capped.trades = Array(blob.trades.prefix(maxTradesPerProfile))
        capped.posts = Array(blob.posts.prefix(maxPostsPerProfile))
        capped.clips = Array(blob.clips.prefix(maxClipsPerProfile))
        capped.achievements = Array(blob.achievements.prefix(maxAchievementsPerProfile))
        write(capped, file: snapshotFile(viewerID: blob.viewerID, targetProfileID: blob.targetProfileID))
        enforceProfileLimit(viewerID: blob.viewerID)
    }

    static func loadSnapshot(
        viewerID: ProfileID,
        targetProfileID: ProfileID
    ) -> SnapshotBlob? {
        guard let blob: SnapshotBlob = read(
            file: snapshotFile(
                viewerID: viewerID.rawValue,
                targetProfileID: targetProfileID.rawValue
            )
        ) else { return nil }
        guard blob.viewerID == viewerID.rawValue,
              blob.targetProfileID == targetProfileID.rawValue,
              blob.schemaVersion == schemaVersion
        else { return nil }
        let age = Date().timeIntervalSince(blob.savedAt)
        guard age <= hardExpirySeconds else {
            removeSnapshot(viewerID: viewerID, targetProfileID: targetProfileID)
            return nil
        }
        return blob
    }

    static func removeSnapshot(viewerID: ProfileID, targetProfileID: ProfileID) {
        remove(
            file: snapshotFile(
                viewerID: viewerID.rawValue,
                targetProfileID: targetProfileID.rawValue
            )
        )
    }

    static func removeSnapshotsForBlockedPeer(_ peerID: ProfileID) {
        guard let dir = directoryURL() else { return }
        let suffix = "-\(peerID.rawValue).json"
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for url in urls where url.lastPathComponent.hasSuffix(suffix) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func allSnapshots(for viewerID: ProfileID) -> [SnapshotBlob] {
        guard let dir = directoryURL() else { return [] }
        let prefix = "profile-page-\(viewerID.rawValue)-"
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap { url -> SnapshotBlob? in
            guard url.lastPathComponent.hasPrefix(prefix) else { return nil }
            return readURL(url)
        }
    }

    static func clear(viewerID: ProfileID) {
        removeMatching(prefix: "profile-page-\(viewerID.rawValue)-")
    }

    static func clearAll() {
        guard let dir = directoryURL() else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - LRU

    private static func enforceProfileLimit(viewerID: String) {
        guard let dir = directoryURL() else { return }
        let prefix = "profile-page-\(viewerID)-"
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let files = urls.filter { $0.lastPathComponent.hasPrefix(prefix) }
        guard files.count > maxProfilesPerViewer else { return }

        let ranked: [(URL, Date)] = files.compactMap { url in
            guard let blob: SnapshotBlob = readURL(url) else { return nil }
            return (url, blob.lastAccessedAt)
        }
        .sorted { $0.1 < $1.1 }

        for entry in ranked.prefix(ranked.count - maxProfilesPerViewer) {
            try? FileManager.default.removeItem(at: entry.0)
        }
    }

    // MARK: - Files

    private static func snapshotFile(viewerID: String, targetProfileID: String) -> String {
        "profile-page-\(viewerID)-\(targetProfileID).json"
    }

    private static func directoryURL() -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
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
