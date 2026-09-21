import Foundation

/// Viewer-scoped disk caches that must survive iOS storage pressure (not `Caches/`).
///
/// Legacy caches lived under `Library/Caches/` and could disappear after ~hours/days without
/// exceeding app TTLs. New writes use Application Support; one-time migration copies known files.
nonisolated enum PersistentAppDataDiskCache {
    private static let rootFolderName = "TradeTraxsPersistentCache"

    static func directoryURL(component: String) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let root = base.appendingPathComponent(rootFolderName, isDirectory: true)
        let dir = root.appendingPathComponent(component, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        migrateLegacyCachesDirectoryIfNeeded(component: component, destination: dir)
        return dir
    }

    private static func migrateLegacyCachesDirectoryIfNeeded(component: String, destination: URL) {
        guard let cachesBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return }
        let legacyDir = cachesBase.appendingPathComponent(component, isDirectory: true)
        guard FileManager.default.fileExists(atPath: legacyDir.path) else { return }

        let legacyFiles =
            (try? FileManager.default.contentsOfDirectory(at: legacyDir, includingPropertiesForKeys: nil)) ?? []
        guard !legacyFiles.isEmpty else { return }

        for legacyURL in legacyFiles {
            let name = legacyURL.lastPathComponent
            let destURL = destination.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: destURL.path) else { continue }
            do {
                try FileManager.default.copyItem(at: legacyURL, to: destURL)
            } catch {
                // Soft-fail — network remains authoritative.
            }
        }
    }
}
