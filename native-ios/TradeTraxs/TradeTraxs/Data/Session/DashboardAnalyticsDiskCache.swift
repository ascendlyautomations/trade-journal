import Foundation

/// Persistent Dashboard V3 analytical cache (Application Support).
nonisolated enum DashboardAnalyticsDiskCache {
    static let folderName = "DashboardAnalyticsDiskCache"
    static let schemaVersion = 2

    struct Blob: Codable, Sendable {
        var viewerID: String
        var contractVersion: String
        var schemaVersion: Int
        var revision: Int64
        var savedAt: Date
        var payload: AnalyticsDashboardBootstrapV3
    }

    static func save(_ blob: Blob) {
        guard let dir = PersistentAppDataDiskCache.directoryURL(component: folderName) else { return }
        let file = dir.appendingPathComponent("\(blob.viewerID).v\(schemaVersion).json")
        var encoded = blob
        encoded.savedAt = Date()
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        try? data.write(to: file, options: [.atomic])
    }

    static func load(viewerID: ProfileID) -> Blob? {
        guard let dir = PersistentAppDataDiskCache.directoryURL(component: folderName) else { return nil }
        let file = dir.appendingPathComponent("\(viewerID.rawValue).v\(schemaVersion).json")
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
