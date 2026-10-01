import Foundation

/// Best-effort removal of Storage objects the database no longer references.
///
/// Runs only after the owning row is deleted or successfully updated to a different
/// object. Failures are ignored so a storage error cannot undo that write.
/// Paths are parsed from `/storage/v1/object/public/{bucket}/{path}` only.
/// Storage RLS still requires the caller to own the first folder.
nonisolated enum OwnedMediaStorageCleanup {
    static func removePublicObjects(
        urls: [String?],
        storage: any SupabaseStorageProviding
    ) async {
        var seen = Set<String>()
        for raw in urls {
            guard let location = location(fromPublicURL: raw) else { continue }
            let key = "\(location.bucket)/\(location.path)"
            guard seen.insert(key).inserted else { continue }
            try? await storage.delete(bucket: location.bucket, path: location.path)
        }
    }

    static func removePublicObjects(
        urls: [String?],
        storage: any ObjectStorageProviding
    ) async {
        var seen = Set<String>()
        for raw in urls {
            guard let location = location(fromPublicURL: raw) else { continue }
            let key = "\(location.bucket)/\(location.path)"
            guard seen.insert(key).inserted else { continue }
            try? await storage.delete(bucket: location.bucket, path: location.path)
        }
    }

    /// Deletes `previous` after a successful replace or clear. Same URL is left alone.
    /// A bare storage path (no public URL) is removed from `fallbackBucket` when set.
    static func removeReplacedObject(
        previous: String?,
        current: String?,
        fallbackBucket: String? = nil,
        storage: any ObjectStorageProviding
    ) async {
        let previousTrimmed = previous?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let currentTrimmed = current?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !previousTrimmed.isEmpty, previousTrimmed != currentTrimmed else { return }
        if let previousLocation = location(fromPublicURL: previousTrimmed) {
            if let currentLocation = location(fromPublicURL: currentTrimmed),
               currentLocation.bucket == previousLocation.bucket,
               currentLocation.path == previousLocation.path
            {
                return
            }
            try? await storage.delete(bucket: previousLocation.bucket, path: previousLocation.path)
            return
        }
        guard let fallbackBucket, !fallbackBucket.isEmpty, !previousTrimmed.contains(".."),
              !previousTrimmed.contains("://")
        else { return }
        try? await storage.delete(bucket: fallbackBucket, path: previousTrimmed)
    }

    static func location(fromPublicURL raw: String?) -> (bucket: String, path: String)? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let combined = StorageOptimizedMedia.storagePath(from: url)
        else { return nil }
        let decoded = combined.removingPercentEncoding ?? combined
        let parts = decoded.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        let bucket = String(parts[0])
        let path = String(parts[1])
        guard !bucket.isEmpty, !path.isEmpty, !path.contains("..") else { return nil }
        return (bucket, path)
    }
}
