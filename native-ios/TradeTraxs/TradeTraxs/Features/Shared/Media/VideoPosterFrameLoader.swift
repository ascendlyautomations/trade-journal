import AVFoundation
import Foundation
import UIKit

/// Async poster frames for remote clips — memory cache, coalesced generation, no main-thread extraction.
enum VideoPosterFrameLoader {
    private actor Cache {
        static let shared = Cache()

        private var memory: [String: UIImage] = [:]
        private var inflight: [String: Task<UIImage?, Never>] = [:]

        func image(for cacheKey: String) -> UIImage? {
            memory[cacheKey]
        }

        func store(_ image: UIImage, for cacheKey: String) {
            memory[cacheKey] = image
        }

        func coalesce(cacheKey: String, operation: @escaping @Sendable () async -> UIImage?) async -> UIImage? {
            if let cached = memory[cacheKey] {
                return cached
            }
            if let existing = inflight[cacheKey] {
                return await existing.value
            }
            let task = Task { await operation() }
            inflight[cacheKey] = task
            let result = await task.value
            inflight[cacheKey] = nil
            if let result {
                memory[cacheKey] = result
            }
            return result
        }
    }

    static func loadPoster(
        thumbnail: MediaReference?,
        video: MediaReference,
        imagePipeline: any ImagePipeline,
        storage: any ObjectStorageProviding,
        bucket: StorageBucket,
        displayScale: CGFloat,
        allowsVideoFrameExtraction: Bool = false
    ) async -> UIImage? {
        let cacheKey = video.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cacheKey.isEmpty else { return nil }

        if let cached = await Cache.shared.image(for: cacheKey) {
            return cached
        }

        if let thumbnail,
           thumbnail.kind == .image,
           thumbnail.id != video.id,
           let image = await decodeThumbnail(thumbnail, pipeline: imagePipeline, displayScale: displayScale)
        {
            await Cache.shared.store(image, for: cacheKey)
            return image
        }

        guard allowsVideoFrameExtraction else { return nil }

        return await Cache.shared.coalesce(cacheKey: cacheKey) {
            await generatePosterFromVideo(
                video: video,
                storage: storage,
                bucket: bucket
            )
        }
    }

    private static func decodeThumbnail(
        _ reference: MediaReference,
        pipeline: any ImagePipeline,
        displayScale: CGFloat
    ) async -> UIImage? {
        let request = ImageRequest(
            reference: reference,
            purpose: .reelThumbnail,
            maxPixelSize: nil,
            allowsProgressiveLoading: true
        )
        let data: Data
        do {
            if let cached = await pipeline.cachedImageData(for: request) {
                data = cached
            } else {
                data = try await pipeline.data(for: request)
            }
        } catch {
            return nil
        }
        return await Task.detached(priority: .userInitiated) {
            UIImage(data: data, scale: displayScale)
        }.value
    }

    private static func generatePosterFromVideo(
        video: MediaReference,
        storage: any ObjectStorageProviding,
        bucket: StorageBucket
    ) async -> UIImage? {
        guard let url = MediaURLResolver.url(for: video, bucket: bucket, storage: storage) else {
            return nil
        }
        let asset = AVURLAsset(url: url)
        let candidateSeconds: [Double] = [0.1, 0.5, 1.0]
        for seconds in candidateSeconds {
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            if let image = await InlineClipFrameCapture.captureFrame(asset: asset, time: time) {
                return image
            }
        }
        return nil
    }
}
