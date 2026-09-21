import Foundation

/// Viewport-aware Feed image prefetch — small lookahead, cancellable, feed-display quality only.
@MainActor
enum FeedImagePrefetch {
    static let lookaheadCount = 2

    private static var generation: UInt64 = 0
    private static var prefetchTask: Task<Void, Never>?

    static func prefetchNearby(
        entries: [FeedTimelineEntry],
        currentEntryID: String,
        pipeline: any ImagePipeline
    ) {
        guard FeedImageViewportReadiness.allowsPrefetch else { return }
        guard let index = entries.firstIndex(where: { $0.id == currentEntryID }) else { return }
        let requests = entries
            .dropFirst(index + 1)
            .prefix(lookaheadCount)
            .compactMap(imageRequest(for:))
        guard !requests.isEmpty else { return }

        generation &+= 1
        let token = generation
        prefetchTask?.cancel()
        prefetchTask = Task(priority: .utility) {
            for request in requests {
                if Task.isCancelled || token != generation {
                    #if DEBUG
                    MediaEgressTracker.recordImagePrefetchCancelled()
                    #endif
                    return
                }
                await FeedPrefetchScheduler.waitForBackgroundCapacity()
                if Task.isCancelled || token != generation { return }
                if await pipeline.cachedImageData(for: request) != nil {
                    continue
                }
                _ = try? await pipeline.data(for: request)
            }
        }
    }

    static func cancelAll() {
        generation &+= 1
        prefetchTask?.cancel()
        prefetchTask = nil
    }

    static func imageRequest(for entry: FeedTimelineEntry) -> ImageRequest? {
        switch entry {
        case .trade(_, let summary):
            guard let reference = summary.thumbnail else { return nil }
            return ImageRequest(
                reference: reference,
                purpose: .tradeScreenshot,
                allowsProgressiveLoading: true,
                deliveryQuality: .feedDisplay,
                auditSurface: "feed",
                isSpeculativePrefetch: true
            )

        case .post(_, let post):
            guard let reference = post.media.first(where: {
                !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) else { return nil }
            return ImageRequest(
                reference: reference,
                purpose: .postImage,
                allowsProgressiveLoading: true,
                deliveryQuality: .feedDisplay,
                auditSurface: "feed",
                isSpeculativePrefetch: true
            )

        case .achievement(_, let achievement):
            guard let reference = achievement.image else { return nil }
            return ImageRequest(
                reference: reference,
                purpose: .postImage,
                allowsProgressiveLoading: true,
                deliveryQuality: .feedDisplay,
                auditSurface: "feed",
                isSpeculativePrefetch: true
            )

        case .clip(_, let reel):
            guard let reference = reel.thumbnail else { return nil }
            return ImageRequest(
                reference: reference,
                purpose: .reelThumbnail,
                allowsProgressiveLoading: true,
                deliveryQuality: .feedDisplay,
                auditSurface: "feed",
                isSpeculativePrefetch: true
            )
        }
    }
}
