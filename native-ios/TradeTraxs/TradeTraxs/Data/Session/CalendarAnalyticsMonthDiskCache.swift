import Foundation

/// Persistent Calendar V2 month analytical cache (Application Support — not `Caches/`).
nonisolated enum CalendarAnalyticsMonthDiskCache {
    static let folderName = "CalendarAnalyticsMonthDiskCache"
    static let schemaVersion = 1

    struct Blob: Codable, Sendable {
        var viewerID: String
        var monthKey: String
        var modeFilter: String?
        var contractVersion: String
        var schemaVersion: Int
        var revision: Int64
        var savedAt: Date
        var payload: AnalyticsDailyRangeBootstrapV1
    }

    static func cacheFileKey(monthKey: String, modeFilter: String?) -> String {
        let mode = modeFilter ?? "all_modes"
        return "\(monthKey)|\(mode)|v\(schemaVersion)"
    }

    static func save(_ blob: Blob) {
        guard let dir = PersistentAppDataDiskCache.directoryURL(component: folderName) else { return }
        let file = dir.appendingPathComponent("\(blob.viewerID).\(cacheFileKey(monthKey: blob.monthKey, modeFilter: blob.modeFilter)).json")
        var encoded = blob
        encoded.savedAt = Date()
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        try? data.write(to: file, options: [.atomic])
    }

    static func load(
        viewerID: ProfileID,
        monthKey: String,
        modeFilter: String?
    ) -> Blob? {
        guard let dir = PersistentAppDataDiskCache.directoryURL(component: folderName) else { return nil }
        let file = dir.appendingPathComponent("\(viewerID.rawValue).\(cacheFileKey(monthKey: monthKey, modeFilter: modeFilter)).json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Blob.self, from: data)
    }

    static func clear(viewerID: ProfileID) {
        guard let dir = PersistentAppDataDiskCache.directoryURL(component: folderName) else { return }
        let prefix = "\(viewerID.rawValue)."
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func clearAll() {
        guard let dir = PersistentAppDataDiskCache.directoryURL(component: folderName) else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for url in files {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
