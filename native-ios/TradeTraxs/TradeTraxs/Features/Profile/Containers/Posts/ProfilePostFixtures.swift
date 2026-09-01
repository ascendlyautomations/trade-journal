import Foundation

/// Deterministic sample posts for DEBUG development sessions / screenshots.
nonisolated enum ProfilePostFixtures {
    /// Landscape sample — verifies aspect-fit (not square crop / zoom).
    private static let sampleLandscapeURL =
        "https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=1200&q=80"
    /// Portrait sample — verifies tall images are contained, not forced-fill.
    private static let samplePortraitURL =
        "https://images.unsplash.com/photo-1590283603385-17ffb3a7f29f?w=800&q=80"

    static func samples(owner profileID: ProfileID) -> [Post] {
        let now = Date()
        return [
            Post(
                id: PostID("dev-post-1"),
                authorProfileID: profileID,
                body: "Session recap — waited for the level, took the continuation. Held through the open drive with clean level respect and size management. Process notes for later review.",
                media: [
                    MediaReference(id: sampleLandscapeURL, kind: .image, altText: "Session chart"),
                ],
                visibility: .public,
                linkedTradeID: TradeID("dev-trade-1"),
                isPinned: true,
                createdAt: now.addingTimeInterval(-40_000),
                updatedAt: now.addingTimeInterval(-40_000)
            ),
            Post(
                id: PostID("dev-post-2"),
                authorProfileID: profileID,
                body: "Journaling the process > chasing the result.",
                media: [
                    MediaReference(id: samplePortraitURL, kind: .image, altText: "Journal photo"),
                ],
                visibility: .public,
                linkedTradeID: nil,
                isPinned: false,
                createdAt: now.addingTimeInterval(-120_000),
                updatedAt: now.addingTimeInterval(-120_000)
            ),
            /// Text-only — feed Layout B (no media container / likes below caption).
            Post(
                id: PostID("dev-post-text-only"),
                authorProfileID: profileID,
                body: "No screenshot today — just process. Waited for the open, skipped the first impulse, and only took the second touch at the level. Size stayed small. That is the edge.",
                media: [],
                visibility: .public,
                linkedTradeID: nil,
                isPinned: false,
                createdAt: now.addingTimeInterval(-5_000),
                updatedAt: now.addingTimeInterval(-5_000)
            ),
        ]
    }

    static func post(id: PostID) -> Post? {
        samples(owner: ProfileID("dev.fixture")).first { $0.id == id }
            .map { post in
                Post(
                    id: post.id,
                    authorProfileID: post.authorProfileID,
                    body: post.body,
                    media: post.media,
                    visibility: post.visibility,
                    linkedTradeID: post.linkedTradeID,
                    isPinned: post.isPinned,
                    createdAt: post.createdAt,
                    updatedAt: post.updatedAt
                )
            }
    }
}
