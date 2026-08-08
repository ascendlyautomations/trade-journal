import Foundation

nonisolated enum ImagePurpose: String, Sendable {
    case profileAvatar
    case tradeScreenshot
    case postImage
    case storyMedia
    case reelThumbnail
}

nonisolated struct ImageRequest: Sendable {
    var reference: MediaReference
    var purpose: ImagePurpose
    var maxPixelSize: Int?
    var allowsProgressiveLoading: Bool

    init(
        reference: MediaReference,
        purpose: ImagePurpose,
        maxPixelSize: Int? = nil,
        allowsProgressiveLoading: Bool = true
    ) {
        self.reference = reference
        self.purpose = purpose
        self.maxPixelSize = maxPixelSize
        self.allowsProgressiveLoading = allowsProgressiveLoading
    }
}

/// Image loading / downsampling / cache orchestration — no UIKit decoding yet.
nonisolated protocol ImagePipeline: Sendable {
    func data(for request: ImageRequest) async throws -> Data
    func prefetch(_ requests: [ImageRequest]) async
    func invalidate(reference: MediaReference) async
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

    func prefetch(_ requests: [ImageRequest]) async {
        _ = requests
    }

    func invalidate(reference: MediaReference) async {
        await cache.removeImage(forKey: reference.id)
    }
}
