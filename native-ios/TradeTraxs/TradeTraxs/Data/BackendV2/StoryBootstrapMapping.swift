import Foundation

/// Maps bootstrap story wire rows into domain ``Story`` (Feed + Profile RPC).
nonisolated enum StoryBootstrapMapping {
    static func map(_ previews: [FeedStoryPreviewV1]) -> [Story] {
        previews.compactMap(map(_:))
    }

    static func map(_ preview: FeedStoryPreviewV1) -> Story? {
        guard let created = ISO8601.date(from: preview.created_at),
              ActiveStorySemantics.isActive(createdAt: created)
        else { return nil }

        let imageURL = preview.image_url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !imageURL.isEmpty else { return nil }

        return Story(
            id: StoryID(preview.id),
            authorProfileID: ProfileID(preview.user_id),
            media: MediaReference(id: imageURL, kind: .image, altText: nil),
            expiresAt: created.addingTimeInterval(ActiveStorySemantics.window),
            createdAt: created,
            viewerHasSeen: false
        )
    }

    /// Newest active story for a profile avatar ring (one bubble per author).
    static func newestActive(_ stories: [Story], now: Date = Date()) -> Story? {
        ActiveStorySemantics.filterActive(stories, now: now)
            .max(by: { $0.createdAt < $1.createdAt })
    }
}
