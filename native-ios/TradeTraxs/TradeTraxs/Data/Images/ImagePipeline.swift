import Foundation

/// Controls whether feed-sized Supabase render URLs are used at fetch time.
nonisolated enum ImageDeliveryQuality: String, Sendable {
    /// Supabase `/render/image/` transforms matching web feed presets.
    case feedDisplay
    /// Compact profile grid thumbnails (~256px) — not full feed thumb width.
    case profileGrid
    /// Higher-width render for detail surfaces (1280px) — not original object bytes.
    case feedDetail
    /// Original object bytes — deep zoom / explicit full fidelity only.
    case fullResolution
}

nonisolated enum ImagePurpose: String, Sendable {
    case profileAvatar
    case tradeScreenshot
    case postImage
    case storyMedia
    case reelThumbnail
}

nonisolated enum ImageCacheResolutionTier: Sendable {
    case memory
    case disk
}

nonisolated struct ImageCachedLookupResult: Sendable {
    var data: Data
    var quality: ImageDeliveryQuality
    var tier: ImageCacheResolutionTier
}

nonisolated struct ImageRequest: Sendable {
    var reference: MediaReference
    var purpose: ImagePurpose
    var maxPixelSize: Int?
    var allowsProgressiveLoading: Bool
    var deliveryQuality: ImageDeliveryQuality
    /// DEBUG audit label — `feed` vs `detail` for pipeline comparison logs.
    var auditSurface: String
    /// DEBUG row/item id (may differ from ``reference.id``).
    var auditMediaID: String
    /// Lookahead / prefetch — deprioritized vs auth and on-screen loads.
    var isSpeculativePrefetch: Bool
    /// DEBUG correlated timeline — ``FeedImageTimingTrace``.
    var imageTraceCorrelationID: UUID?

    init(
        reference: MediaReference,
        purpose: ImagePurpose,
        maxPixelSize: Int? = nil,
        allowsProgressiveLoading: Bool = true,
        deliveryQuality: ImageDeliveryQuality = .feedDisplay,
        auditSurface: String = "",
        auditMediaID: String = "",
        isSpeculativePrefetch: Bool = false,
        imageTraceCorrelationID: UUID? = nil
    ) {
        self.reference = reference
        self.purpose = purpose
        self.maxPixelSize = maxPixelSize
        self.allowsProgressiveLoading = allowsProgressiveLoading
        self.deliveryQuality = deliveryQuality
        self.auditSurface = auditSurface
        self.auditMediaID = auditMediaID.isEmpty ? reference.id : auditMediaID
        self.isSpeculativePrefetch = isSpeculativePrefetch
        self.imageTraceCorrelationID = imageTraceCorrelationID
    }
}

/// Image loading / downsampling / cache orchestration — no UIKit decoding yet.
nonisolated protocol ImagePipeline: Sendable {
    func data(for request: ImageRequest) async throws -> Data
    func prefetch(_ requests: [ImageRequest]) async
    func invalidate(reference: MediaReference) async
    func cachedImageData(for request: ImageRequest) async -> Data?
    func bestCachedImageData(for request: ImageRequest) async -> (data: Data, quality: ImageDeliveryQuality)?
    /// Memory-first, then disk — reports which tier satisfied the lookup.
    func bestCachedImageDataWithTier(for request: ImageRequest) async -> ImageCachedLookupResult?
    /// Promotes disk hits to memory — never uses the network.
    func warmCachedImages(for requests: [ImageRequest]) async
}

extension ImagePipeline {
    func cachedImageData(for request: ImageRequest) async -> Data? {
        nil
    }

    func bestCachedImageData(for request: ImageRequest) async -> (data: Data, quality: ImageDeliveryQuality)? {
        nil
    }

    func bestCachedImageDataWithTier(for request: ImageRequest) async -> ImageCachedLookupResult? {
        nil
    }

    func warmCachedImages(for requests: [ImageRequest]) async {}
}

nonisolated struct PlaceholderImagePipeline: ImagePipeline {
    private let cache: any ImageCaching

    init(cache: any ImageCaching = PlaceholderImageCache()) {
        self.cache = cache
    }

    func data(for request: ImageRequest) async throws -> Data {
        if let cached = await cache.imageData(forKey: request.reference.id) {
            return cached
        }
        throw DataPlaceholder.unimplemented("ImagePipeline.data")
    }

    func cachedImageData(for request: ImageRequest) async -> Data? {
        await cache.imageData(forKey: request.reference.id)
    }

    func bestCachedImageData(for request: ImageRequest) async -> (data: Data, quality: ImageDeliveryQuality)? {
        nil
    }

    func prefetch(_ requests: [ImageRequest]) async {
        _ = requests
    }

    func invalidate(reference: MediaReference) async {
        await cache.removeImage(forKey: reference.id)
    }
}
