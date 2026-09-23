import Foundation

/// Viewer-scoped Vault presentation snapshot — references only (no authoritative detail).
nonisolated enum VaultDiskCache {
    static let folderName = "VaultDiskCache"
    static let schemaVersion = 1
    static let hardExpirySeconds: TimeInterval = 7 * 24 * 60 * 60

    static let maxFolders = 64
    static let maxStateEntries = 400
    static let maxHomePages = 8
    static let maxItemsPerHomePage = 30

    struct HomePageRecord: Codable, Sendable, Equatable {
        var filter: VaultContentFilter
        var folderID: String?
        var items: [VaultItem]
        var nextCursor: String?
        var savedAt: Date
    }

    struct SnapshotBlob: Codable, Sendable {
        var schemaVersion: Int = VaultDiskCache.schemaVersion
        var viewerID: String
        var savedAt: Date
        var lastAccessedAt: Date
        var folders: [VaultFolder]
        var states: [String: VaultItemState]
        var homePages: [HomePageRecord]
        var writeGeneration: UInt64 = 0
    }

    static func saveSnapshot(_ blob: SnapshotBlob) {
        var capped = blob
        capped.folders = Array(blob.folders.prefix(maxFolders))
        capped.states = Dictionary(
            uniqueKeysWithValues: Array(blob.states.prefix(maxStateEntries))
        )
        capped.homePages = Array(blob.homePages.prefix(maxHomePages)).map { page in
            var copy = page
            copy.items = Array(page.items.prefix(maxItemsPerHomePage))
            return copy
        }
        write(capped, file: snapshotFile(viewerID: blob.viewerID))
    }

    static func loadSnapshot(viewerID: ProfileID) -> SnapshotBlob? {
        guard let blob: SnapshotBlob = read(file: snapshotFile(viewerID: viewerID.rawValue)) else {
            return nil
        }
        guard blob.viewerID == viewerID.rawValue,
              blob.schemaVersion == schemaVersion
        else {
            removeSnapshot(viewerID: viewerID)
            return nil
        }
        let age = Date().timeIntervalSince(blob.savedAt)
        guard age <= hardExpirySeconds else {
            removeSnapshot(viewerID: viewerID)
            return nil
        }
        return blob
    }

    static func removeSnapshot(viewerID: ProfileID) {
        remove(file: snapshotFile(viewerID: viewerID.rawValue))
    }

    static func clear(viewerID: ProfileID) {
        removeSnapshot(viewerID: viewerID)
    }

    static func clearAll() {
        guard let dir = directoryURL() else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    static func homePageKey(filter: VaultContentFilter, folderID: VaultFolderID?) -> String {
        "\(filter.rawValue)|\(folderID?.rawValue ?? "-")"
    }

    // MARK: - Files

    private static func snapshotFile(viewerID: String) -> String {
        "vault-snapshot-\(viewerID).json"
    }

    private static func directoryURL() -> URL? {
        PersistentAppDataDiskCache.directoryURL(component: folderName)
    }

    private static func write(_ blob: SnapshotBlob, file: String) {
        guard let dir = directoryURL() else { return }
        let url = dir.appendingPathComponent(file)
        do {
            let data = try JSONEncoder().encode(blob)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Soft-fail — network remains authoritative.
        }
    }

    private static func read<T: Decodable>(file: String) -> T? {
        guard let dir = directoryURL() else { return nil }
        let url = dir.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func remove(file: String) {
        guard let dir = directoryURL() else { return }
        let url = dir.appendingPathComponent(file)
        try? FileManager.default.removeItem(at: url)
    }
}
