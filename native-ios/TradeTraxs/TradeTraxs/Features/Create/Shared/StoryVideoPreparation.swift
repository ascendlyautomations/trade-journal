import Foundation

/// Story video delivery prep — same encoder as reels with story duration/size limits.
enum StoryVideoPreparation {
    static func prepareForUpload(
        from sourceURL: URL,
        contentType: String?,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> MediaVideoPreparation.PreparedLocalVideo {
        try await MediaVideoPreparation.prepareLocalVideo(
            from: sourceURL,
            contentType: contentType,
            limits: .story,
            onProgress: onProgress
        )
    }
}
