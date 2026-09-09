import Foundation

/// Lightweight lookahead prefetch for Feed card images — reuses the shared ``ImagePipeline`` cache.
nonisolated enum FeedImagePrefetch {
    static let lookaheadCount = 4

    static func prefetchNearby(
        entries: [FeedTimelineEntry],
        currentEntryID: String,
        pipeline: any ImagePipeline
    ) {
        guard let index = entries.firstIndex(where: { $0.id == currentEntryID }) else { return }
        let requests = entries
            .dropFirst(index + 1)
            .prefix(lookaheadCount)
            .compactMap(imageRequest(for:))
        guard !requests.isEmpty else { return }
        Task(priority: .utility) {
            await pipeline.prefetch(requests)
        }
    }

    static func imageRequest(for entry: FeedTimelineEntry) -> ImageRequest? {
        switch entry {
        case .trade(_, let trade):
            guard let reference = trade.thumbnail else { return nil }
            return ImageRequest(
                reference: reference,
                purpose: .tradeScreenshot,
                allowsProgressiveLoading: true
            )

        case .post(_, let post):
            guard let reference = post.media.first(where: {
                !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) else { return nil }
            return ImageRequest(
                reference: reference,
                purpose: .postImage,
                allowsProgressiveLoading: true
            )

        case .achievement(_, let achievement):
            guard let reference = achievement.image else { return nil }
            return ImageRequest(
                reference: reference,
                purpose: .postImage,
                allowsProgressiveLoading: true
            )

        case .clip(_, let reel):
            guard let reference = reel.thumbnail else { return nil }
            return ImageRequest(
                reference: reference,
                purpose: .reelThumbnail,
                allowsProgressiveLoading: true
            )
        }
    }
}
