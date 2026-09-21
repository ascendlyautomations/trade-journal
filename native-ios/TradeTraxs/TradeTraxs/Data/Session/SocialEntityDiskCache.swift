import Foundation

/// Viewer-scoped shared social entity records — one canonical disk copy per entity.
///
/// Patched from Feed / Profile / Detail mutations so surfaces stay coherent offline.
nonisolated enum SocialEntityDiskCache {
    static let folderName = "SocialEntityDiskCache"
    static let schemaVersion = 2
    static let maxEntitiesPerViewer = 150
    static let hardExpirySeconds: TimeInterval = 7 * 24 * 60 * 60

    enum EntityKind: String, Codable, Sendable {
        case trade
        case post
        case reel
        case achievement
        case profile
    }

    struct Record: Codable, Sendable {
        var schemaVersion: Int = SocialEntityDiskCache.schemaVersion
        var viewerID: String
        var kind: EntityKind
        var entityID: String
        var savedAt: Date
        var lastAccessedAt: Date
        /// Phase 8F — social preview only (never authoritative detail).
        var tradeSummary: TradeSummary?
        /// Legacy v1 full trade blob — rejected on read unless migrated to summary.
        var trade: Trade?
        var post: Post?
        var reel: Reel?
        var achievement: Achievement?
        var profile: Profile?
    }

    // MARK: - Trades

    static func saveTradeSummary(_ summary: TradeSummary, viewerID: ProfileID) {
        save(
            Record(
                schemaVersion: schemaVersion,
                viewerID: viewerID.rawValue,
                kind: .trade,
                entityID: summary.id.rawValue,
                savedAt: Date(),
                lastAccessedAt: Date(),
                tradeSummary: summary,
                trade: nil,
                post: nil,
                reel: nil,
                achievement: nil,
                profile: nil
            )
        )
    }

    /// Back-compat — persists canonical ``TradeSummary`` (list/mutation rows are not authoritative detail).
    static func saveTrade(_ trade: Trade, viewerID: ProfileID) {
        saveTradeSummary(TradeSummaryMapper.summary(fromPartialListTrade: trade), viewerID: viewerID)
    }

    static func loadTradeSummary(id: TradeID, viewerID: ProfileID) -> TradeSummary? {
        guard let record = loadRecord(kind: .trade, entityID: id.rawValue, viewerID: viewerID) else {
            return nil
        }
        if let summary = record.tradeSummary {
            return summary
        }
        if let legacy = record.trade {
            let summary = TradeSummaryMapper.summary(fromPartialListTrade: legacy)
            saveTradeSummary(summary, viewerID: viewerID)
            return summary
        }
        return nil
    }

    /// Non-authoritative card preview — never use for edit/detail completeness.
    static func loadTrade(id: TradeID, viewerID: ProfileID) -> Trade? {
        guard let summary = loadTradeSummary(id: id, viewerID: viewerID) else { return nil }
        return TradeSummaryMapper.previewTrade(from: summary)
    }

    static func removeTrade(id: TradeID, viewerID: ProfileID) {
        remove(kind: .trade, entityID: id.rawValue, viewerID: viewerID)
    }

    // MARK: - Posts

    static func savePost(_ post: Post, viewerID: ProfileID) {
        save(
            Record(
                viewerID: viewerID.rawValue,
                kind: .post,
                entityID: post.id.rawValue,
                savedAt: Date(),
                lastAccessedAt: Date(),
                trade: nil,
                post: post,
                reel: nil,
                achievement: nil,
                profile: nil
            )
        )
    }

    static func loadPost(id: PostID, viewerID: ProfileID) -> Post? {
        load(kind: .post, entityID: id.rawValue, viewerID: viewerID)?.post
    }

    static func removePost(id: PostID, viewerID: ProfileID) {
        remove(kind: .post, entityID: id.rawValue, viewerID: viewerID)
    }

    // MARK: - Reels

    static func saveReel(_ reel: Reel, viewerID: ProfileID) {
        save(
            Record(
                viewerID: viewerID.rawValue,
                kind: .reel,
                entityID: reel.id.rawValue,
                savedAt: Date(),
                lastAccessedAt: Date(),
                trade: nil,
                post: nil,
                reel: reel,
                achievement: nil,
                profile: nil
            )
        )
    }

    static func loadReel(id: ReelID, viewerID: ProfileID) -> Reel? {
        load(kind: .reel, entityID: id.rawValue, viewerID: viewerID)?.reel
    }

    static func removeReel(id: ReelID, viewerID: ProfileID) {
        remove(kind: .reel, entityID: id.rawValue, viewerID: viewerID)
    }

    // MARK: - Achievements

    static func saveAchievement(_ achievement: Achievement, viewerID: ProfileID) {
        save(
            Record(
                viewerID: viewerID.rawValue,
                kind: .achievement,
                entityID: achievement.id.rawValue,
                savedAt: Date(),
                lastAccessedAt: Date(),
                trade: nil,
                post: nil,
                reel: nil,
                achievement: achievement,
                profile: nil
            )
        )
    }

    static func loadAchievement(id: AchievementID, viewerID: ProfileID) -> Achievement? {
        load(kind: .achievement, entityID: id.rawValue, viewerID: viewerID)?.achievement
    }

    static func removeAchievement(id: AchievementID, viewerID: ProfileID) {
        remove(kind: .achievement, entityID: id.rawValue, viewerID: viewerID)
    }

    // MARK: - Profiles

    static func saveProfile(_ profile: Profile, viewerID: ProfileID) {
        save(
            Record(
                viewerID: viewerID.rawValue,
                kind: .profile,
                entityID: profile.id.rawValue,
                savedAt: Date(),
                lastAccessedAt: Date(),
                trade: nil,
                post: nil,
                reel: nil,
                achievement: nil,
                profile: profile
            )
        )
    }

    static func loadProfile(id: ProfileID, viewerID: ProfileID) -> Profile? {
        load(kind: .profile, entityID: id.rawValue, viewerID: viewerID)?.profile
    }

    // MARK: - Session isolation

    static func clear(viewerID: ProfileID) {
        removeMatching(prefix: "entity-\(viewerID.rawValue)-")
    }

    static func clearAll() {
        guard let dir = directoryURL() else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - IO

    private static func save(_ record: Record) {
        write(record, file: entityFile(viewerID: record.viewerID, kind: record.kind, entityID: record.entityID))
        enforceEntityLimit(viewerID: record.viewerID)
    }

    private static func loadRecord(kind: EntityKind, entityID: String, viewerID: ProfileID) -> Record? {
        guard let record: Record = read(
            file: entityFile(viewerID: viewerID.rawValue, kind: kind, entityID: entityID)
        ) else { return nil }
        guard record.viewerID == viewerID.rawValue,
              record.kind == kind,
              record.entityID == entityID
        else { return nil }
        if record.kind == .trade,
           record.schemaVersion < schemaVersion,
           record.tradeSummary == nil,
           record.trade == nil
        {
            remove(kind: kind, entityID: entityID, viewerID: viewerID)
            return nil
        }
        let age = Date().timeIntervalSince(record.savedAt)
        guard age <= hardExpirySeconds else {
            remove(kind: kind, entityID: entityID, viewerID: viewerID)
            return nil
        }
        return record
    }

    private static func load(kind: EntityKind, entityID: String, viewerID: ProfileID) -> Record? {
        loadRecord(kind: kind, entityID: entityID, viewerID: viewerID)
    }

    private static func remove(kind: EntityKind, entityID: String, viewerID: ProfileID) {
        remove(file: entityFile(viewerID: viewerID.rawValue, kind: kind, entityID: entityID))
    }

    private static func enforceEntityLimit(viewerID: String) {
        guard let dir = directoryURL() else { return }
        let prefix = "entity-\(viewerID)-"
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let files = urls.filter { $0.lastPathComponent.hasPrefix(prefix) }
        guard files.count > maxEntitiesPerViewer else { return }

        let ranked: [(URL, Date)] = files.compactMap { url in
            guard let record: Record = readURL(url) else { return nil }
            return (url, record.lastAccessedAt)
        }
        .sorted { $0.1 < $1.1 }

        for entry in ranked.prefix(ranked.count - maxEntitiesPerViewer) {
            try? FileManager.default.removeItem(at: entry.0)
        }
    }

    private static func entityFile(viewerID: String, kind: EntityKind, entityID: String) -> String {
        "entity-\(viewerID)-\(kind.rawValue)-\(entityID).json"
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
        } catch {}
    }

    private static func read<T: Decodable>(file: String) -> T? {
        guard let dir = directoryURL() else { return nil }
        let url = dir.appendingPathComponent(sanitize(file))
        return readURL(url)
    }

    private static func readURL<T: Decodable>(_ url: URL) -> T? {
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

#if DEBUG
@MainActor
enum SocialEntityCacheProbe {
    private(set) static var hits: [SocialEntityDiskCache.EntityKind: Int] = [:]
    private(set) static var misses: [SocialEntityDiskCache.EntityKind: Int] = [:]
    private(set) static var writes: [SocialEntityDiskCache.EntityKind: Int] = [:]

    static func resetForTesting() {
        hits = [:]
        misses = [:]
        writes = [:]
    }

    static func recordHit(kind: SocialEntityDiskCache.EntityKind) {
        hits[kind, default: 0] += 1
    }

    static func recordMiss(kind: SocialEntityDiskCache.EntityKind) {
        misses[kind, default: 0] += 1
    }

    static func recordWrite(kind: SocialEntityDiskCache.EntityKind) {
        writes[kind, default: 0] += 1
    }
}
#endif
