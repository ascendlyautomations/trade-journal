import Foundation

/// Supabase Storage delivery — object/public URLs only (no Image Transformations).
///
/// Parity with web `lib/optimizedStorageImage.ts` / `supabaseStorageTransformGuard.ts`.
nonisolated enum StorageImageTransform {
    /// Bump when feed delivery URL shape changes so image caches miss stale bytes.
    static let feedDisplayCacheRevision = 4
    /// Bump when profile grid render params change.
    static let profileGridCacheRevision = 1

    enum Preset: Sendable {
        case avatar
        case feedThumb
        case profileCompact
        case feedDetail
        case story
        case reelThumb
    }

    private static let objectPublic = "/storage/v1/object/public/"
    private static let renderPublic = "/storage/v1/render/image/public/"

    static func isSupabaseStoragePublicURL(_ url: URL) -> Bool {
        let path = url.path
        return path.contains(objectPublic) || path.contains(renderPublic)
    }

    /// Stable identity for logging — host + path without query tokens.
    static func urlIdentity(for url: URL) -> String {
        var components = URLComponents()
        components.host = url.host
        components.path = url.path
        return (components.string ?? url.absoluteString).lowercased()
    }

    /// Object/public URL for full-resolution delivery (optimized `/opt/` assets, not legacy giants).
    static func deliveryObjectURL(for url: URL) -> URL {
        guard isSupabaseStoragePublicURL(url) else { return url }
        return objectPublicBaseURL(for: url)
    }

    static func optimizedURL(for url: URL, preset: Preset) -> URL {
        guard isSupabaseStoragePublicURL(url) else { return url }
        let objectBase = deliveryObjectURL(for: url)
        let assetPolicy = StorageOptimizedMedia.isOptimizedStorageURL(objectBase)
            ? "optimizedObject"
            : "legacy"
        #if DEBUG
        assert(!objectBase.path.contains(renderPublic), "Supabase transform URL forbidden")
        StorageOptimizedMedia.logDelivery(
            url: objectBase,
            assetPolicy: assetPolicy,
            delivery: "object",
            preset: String(describing: preset)
        )
        #endif
        return objectBase
    }

    private static func objectPublicBaseURL(for url: URL) -> URL {
        if url.path.contains(renderPublic) {
            return StorageOptimizedMedia.objectPublicURL(from: url)
        }
        return url
    }

    static func preset(for purpose: ImagePurpose, delivery: ImageDeliveryQuality) -> Preset? {
        switch delivery {
        case .fullResolution:
            return nil
        case .feedDetail:
            switch purpose {
            case .profileAvatar: return .avatar
            case .tradeScreenshot, .postImage: return .feedDetail
            case .storyMedia: return .story
            case .reelThumbnail: return .reelThumb
            }
        case .profileGrid:
            switch purpose {
            case .profileAvatar: return .avatar
            case .tradeScreenshot, .postImage: return .profileCompact
            case .storyMedia: return .story
            case .reelThumbnail: return .profileCompact
            }
        case .feedDisplay:
            switch purpose {
            case .profileAvatar: return .avatar
            case .tradeScreenshot, .postImage: return .feedThumb
            case .storyMedia: return .story
            case .reelThumbnail: return .reelThumb
            }
        }
    }
}
