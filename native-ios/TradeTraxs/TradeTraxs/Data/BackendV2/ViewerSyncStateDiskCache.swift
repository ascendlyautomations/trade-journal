import Foundation

/// Persists last authoritative viewer sync fingerprints (viewer-scoped JSON on disk).
nonisolated enum ViewerSyncStateDiskCache {
    private static let folderName = "BackendV2BootstrapCache"

    struct Blob: Codable, Sendable {
        var viewerID: String
        var savedAt: Date
        var fingerprints: ViewerSyncStateFingerprints
    }

    static func save(_ fingerprints: ViewerSyncStateFingerprints) {
        let blob = Blob(
            viewerID: fingerprints.viewerID,
            savedAt: Date(),
            fingerprints: fingerprints
        )
        write(blob, file: fileName(viewerID: fingerprints.viewerID))
    }

    static func load(viewerID: String) -> ViewerSyncStateFingerprints? {
        guard let blob: Blob = read(file: fileName(viewerID: viewerID)) else { return nil }
        guard blob.viewerID == viewerID else { return nil }
        return blob.fingerprints
    }

    static func clear(viewerID: String? = nil) {
        guard let dir = directoryURL() else { return }
        guard let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        for url in contents {
            let name = url.lastPathComponent
            if name.hasPrefix("viewer-sync-state-") {
                if let viewerID {
                    if name == fileName(viewerID: viewerID) {
                        try? FileManager.default.removeItem(at: url)
                    }
                } else {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    private static func fileName(viewerID: String) -> String {
        "viewer-sync-state-\(viewerID).json"
    }

    private static func directoryURL() -> URL? {
        PersistentAppDataDiskCache.directoryURL(component: folderName)
    }

    private static func write<T: Encodable>(_ value: T, file: String) {
        guard let dir = directoryURL() else { return }
        let url = dir.appendingPathComponent(file)
        let temp = dir.appendingPathComponent("\(file).tmp")
        guard let data = try? JSONEncoder().encode(value) else { return }
        do {
            try data.write(to: temp, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: temp, to: url)
        } catch {
            try? FileManager.default.removeItem(at: temp)
        }
    }

    private static func read<T: Decodable>(file: String) -> T? {
        guard let dir = directoryURL() else { return nil }
        let url = dir.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
