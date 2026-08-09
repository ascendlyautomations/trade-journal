import Foundation

/// Deterministic sample clips for DEBUG development sessions / screenshots.
enum ProfileClipFixtures {
    /// Public sample MP4 so AVPlayer works offline-of-Supabase in development.
    private static let sampleVideoURL =
        "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4"

    static func samples(owner profileID: ProfileID) -> [Reel] {
        let now = Date()
        return [
            Reel(
                id: ReelID("dev-reel-1"),
                authorProfileID: profileID,
                video: MediaReference(id: sampleVideoURL, kind: .video, altText: nil),
                thumbnail: nil,
                caption: "Open drive clip — NQ continuation",
                visibility: .public,
                linkedTradeID: TradeID("dev-trade-1"),
                durationSeconds: 15,
                createdAt: now.addingTimeInterval(-50_000)
            ),
            Reel(
                id: ReelID("dev-reel-2"),
                authorProfileID: profileID,
                video: MediaReference(id: sampleVideoURL, kind: .video, altText: nil),
                thumbnail: nil,
                caption: "Process over outcome",
                visibility: .public,
                linkedTradeID: nil,
                durationSeconds: 12,
                createdAt: now.addingTimeInterval(-200_000)
            ),
        ]
    }

    static func reel(id: ReelID) -> Reel? {
        samples(owner: ProfileID("dev.fixture")).first { $0.id == id }
    }
}
