import SwiftUI
import UIKit

enum ConversationStoryBubblePreviewPolicy {
    static let maxMediaAttempts = 3
    static let retryDelayNs: UInt64 = 250_000_000
    static let replyPreviewWidth: CGFloat = 135
    static let replyPreviewAspect: CGFloat = 9 / 16
    static var replyPreviewHeight: CGFloat { replyPreviewWidth / replyPreviewAspect }
    static let unavailableLabel = "Story Unavailable"
}

/// Stable story-reply preview state across `LazyVStack` cell reuse (same pattern as shared-card VM cache).
@MainActor
enum ConversationStoryDmReplyPreviewCache {
    struct Snapshot {
        var accessChecked: Bool
        var mediaAllowed: Bool
        var mediaLoadFailed: Bool
        var thumbnail: UIImage?
    }

    private static var storage: [String: Snapshot] = [:]

    static func snapshot(storyID: String) -> Snapshot? {
        storage[storyID]
    }

    static func store(storyID: String, _ snapshot: Snapshot) {
        storage[storyID] = snapshot
    }
}

enum ConversationStoryDmPreviewLoader {
    static func resolveAccess(
        storyID: String,
        feed: any FeedRepository
    ) async -> StoryDmMediaAccess? {
        do {
            return try await feed.storyDmMediaAccess(id: StoryID(storyID))
        } catch {
            return nil
        }
    }

    static func loadThumbnailUIImage(
        imagePipeline: any ImagePipeline,
        storage: any ObjectStorageProviding,
        access: StoryDmMediaAccess,
        fallbackImageURL: String,
        isVideo: Bool,
        maxPixelSize: Int
    ) async -> (image: UIImage?, aspect: CGFloat) {
        for attempt in 1...ConversationStoryBubblePreviewPolicy.maxMediaAttempts {
            if let result = await loadThumbnailAttempt(
                imagePipeline: imagePipeline,
                storage: storage,
                access: access,
                fallbackImageURL: fallbackImageURL,
                isVideo: isVideo,
                maxPixelSize: maxPixelSize
            ) {
                return result
            }
            guard attempt < ConversationStoryBubblePreviewPolicy.maxMediaAttempts else { break }
            try? await Task.sleep(nanoseconds: ConversationStoryBubblePreviewPolicy.retryDelayNs)
        }
        return (nil, ConversationStoryBubblePreviewPolicy.replyPreviewAspect)
    }

    private static func loadThumbnailAttempt(
        imagePipeline: any ImagePipeline,
        storage: any ObjectStorageProviding,
        access: StoryDmMediaAccess,
        fallbackImageURL: String,
        isVideo: Bool,
        maxPixelSize: Int
    ) async -> (UIImage, CGFloat)? {
        guard let media = await StorySignedMediaResolver.shared.signedMediaReference(
            storagePath: access.storagePath,
            imageURL: access.imageURL ?? fallbackImageURL,
            isVideo: isVideo
        ) else {
            return nil
        }

        if isVideo,
           let uiImage = await VideoPosterFrameLoader.loadPoster(
            thumbnail: nil,
            video: media,
            imagePipeline: imagePipeline,
            storage: storage,
            bucket: .stories,
            displayScale: UIScreen.main.scale,
            allowsVideoFrameExtraction: true
           ) {
            return (uiImage, ConversationStoryBubblePreviewPolicy.replyPreviewAspect)
        }

        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: media,
                    purpose: .storyMedia,
                    maxPixelSize: maxPixelSize
                )
            )
            guard let uiImage = UIImage(data: data) else { return nil }
            let aspect = uiImage.size.height > 0
                ? uiImage.size.width / uiImage.size.height
                : ConversationStoryBubblePreviewPolicy.replyPreviewAspect
            let clamped = min(max(aspect, 0.55), 1.35)
            return (uiImage, clamped)
        } catch {
            return nil
        }
    }
}