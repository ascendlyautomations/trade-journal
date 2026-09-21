import Foundation

/// Memory/disk-only warm for Feed first page — no network.
enum FeedImageCacheWarmer {
    /// Same keys as ``InteractiveImageView`` / ``FeedImagePrefetch`` for feedDisplay.
    static func imageRequests(for entries: [FeedTimelineEntry]) -> [ImageRequest] {
        entries
            .prefix(8)
            .compactMap { entry -> ImageRequest? in
                guard var request = FeedImagePrefetch.imageRequest(for: entry) else { return nil }
                request.isSpeculativePrefetch = false
                request.auditSurface = "feed"
                return request
            }
    }

    static func warmInitialViewport(
        entries: [FeedTimelineEntry],
        pipeline: any ImagePipeline
    ) async {
        let requests = imageRequests(for: entries)
        guard !requests.isEmpty else { return }
        await pipeline.warmCachedImages(for: requests)
    }
}
