import Foundation

/// Phase 1: upload-time optimized assets include `/opt/` in the storage path.
/// Delivery uses object/public URLs (no Supabase Image Transformations).
nonisolated enum StorageOptimizedMedia {
    static let pathSegment = "/opt/"

    static func objectPath(prefix: String, fileExtension: String = "jpg") -> String {
        let trimmed = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let ext = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let safeExt = ext.isEmpty ? "jpg" : ext
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        return "\(trimmed)/opt/\(stamp).\(safeExt)"
    }

    static func storagePath(from url: URL) -> String? {
        let path = url.path
        let objectMarker = "/storage/v1/object/public/"
        let renderMarker = "/storage/v1/render/image/public/"
        if let range = path.range(of: objectMarker) {
            return String(path[range.upperBound...])
        }
        if let range = path.range(of: renderMarker) {
            return String(path[range.upperBound...])
        }
        return nil
    }

    static func isOptimizedStoragePath(_ pathOrURL: String) -> Bool {
        if pathOrURL.contains(pathSegment) { return true }
        if let url = URL(string: pathOrURL), let path = storagePath(from: url) {
            return path.contains(pathSegment)
        }
        return false
    }

    static func isOptimizedStorageURL(_ url: URL) -> Bool {
        if url.path.contains(pathSegment) { return true }
        if let path = storagePath(from: url) {
            return path.contains(pathSegment)
        }
        return false
    }

    static func objectPublicURL(from url: URL) -> URL {
        guard url.path.contains("/storage/v1/render/image/public/") else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = components?.path ?? url.path
        components?.path = path.replacingOccurrences(
            of: "/storage/v1/render/image/public/",
            with: "/storage/v1/object/public/"
        )
        components?.query = nil
        return components?.url ?? url
    }

    static func deliveryIdentity(for url: URL) -> String {
        let path = storagePath(from: url) ?? url.path
        let parts = path.split(separator: "/")
        return parts.suffix(3).joined(separator: "/")
    }

    #if DEBUG
    static func logDelivery(
        url: URL,
        assetPolicy: String,
        delivery: String,
        preset: String? = nil
    ) {
        let presetSuffix = preset.map { " preset=\($0)" } ?? ""
        print(
            "[StorageImageDelivery] assetPolicy=\(assetPolicy) delivery=\(delivery)\(presetSuffix) "
                + "id=\(deliveryIdentity(for: url))"
        )
    }
    #endif
}
