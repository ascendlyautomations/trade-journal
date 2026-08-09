import Foundation
import ImageIO

/// Production image pipeline: memory cache → public storage URL or HTTPS → optional downsample.
///
/// Mirrors web `tradeScreenshotSrc` / `postImageSrc`: storage paths resolve to
/// `/storage/v1/object/public/{bucket}/{path}` rather than authenticated object GET
/// (screenshots bucket has no SELECT RLS).
nonisolated struct DefaultImagePipeline: ImagePipeline {
    private let cache: any ImageCaching
    private let storage: any ObjectStorageProviding
    private let downloadService: any DownloadService
    private let urlSession: URLSession

    init(
        cache: any ImageCaching,
        storage: any ObjectStorageProviding,
        downloadService: any DownloadService,
        urlSession: URLSession = .shared
    ) {
        self.cache = cache
        self.storage = storage
        self.downloadService = downloadService
        self.urlSession = urlSession
    }

    func data(for request: ImageRequest) async throws -> Data {
        let key = cacheKey(for: request)
        if let cached = await cache.imageData(forKey: key) {
            return cached
        }

        let raw = try await fetch(reference: request.reference, purpose: request.purpose)
        let data = Self.downsampleIfNeeded(raw, maxPixelSize: request.maxPixelSize)
        await cache.setImageData(data, forKey: key)
        return data
    }

    func prefetch(_ requests: [ImageRequest]) async {
        for request in requests {
            _ = try? await data(for: request)
        }
    }

    func invalidate(reference: MediaReference) async {
        await cache.removeImage(forKey: reference.id)
        // Also clear sized variants.
        for purpose in ImagePurpose.allCases {
            await cache.removeImage(forKey: "\(reference.id)|\(purpose.rawValue)|0")
        }
    }

    // MARK: - Private

    private func cacheKey(for request: ImageRequest) -> String {
        "\(request.reference.id)|\(request.purpose.rawValue)|\(request.maxPixelSize ?? 0)"
    }

    private func fetch(reference: MediaReference, purpose: ImagePurpose) async throws -> Data {
        let identifier = reference.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else {
            throw AppError.network(.validation(message: "Empty media reference"))
        }

        // Prefer public URL resolution (web parity) for storage paths.
        if let url = MediaURLResolver.url(
            for: reference,
            bucket: Self.storageBucket(for: purpose),
            storage: storage
        ) {
            let (data, response) = try await urlSession.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw AppError.network(.server(statusCode: http.statusCode, message: nil))
            }
            return data
        }

        // Last resort — authenticated download (private buckets / unconfigured public URL).
        return try await downloadService.download(
            DownloadRequest(bucket: Self.storageBucket(for: purpose).rawValue, path: identifier)
        )
    }

    private static func storageBucket(for purpose: ImagePurpose) -> StorageBucket {
        switch purpose {
        case .profileAvatar: return .avatars
        case .tradeScreenshot: return .screenshots
        case .postImage: return .posts
        case .storyMedia: return .stories
        case .reelThumbnail: return .reels
        }
    }

    /// ImageIO downsample off the caller's cooperative thread (pipeline is nonisolated).
    private static func downsampleIfNeeded(_ data: Data, maxPixelSize: Int?) -> Data {
        guard let maxPixelSize, maxPixelSize > 0 else { return data }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return data }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return data
        }

        let mutable = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutable,
            "public.jpeg" as CFString,
            1,
            nil
        ) else {
            return data
        }
        CGImageDestinationAddImage(destination, cgImage, [
            kCGImageDestinationLossyCompressionQuality: 0.9,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return data }
        return mutable as Data
    }
}

extension ImagePurpose: CaseIterable {
    nonisolated static var allCases: [ImagePurpose] {
        [.profileAvatar, .tradeScreenshot, .postImage, .storyMedia, .reelThumbnail]
    }
}
