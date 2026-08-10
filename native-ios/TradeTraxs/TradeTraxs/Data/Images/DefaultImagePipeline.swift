import Foundation
import ImageIO

/// Production image pipeline: memory cache → public storage URL or HTTPS → optional downsample.
///
/// Mirrors web `postImageSrc` / `tradeScreenshotPublicUrl`:
/// `/storage/v1/object/public/{bucket}/{path}` (not authenticated object GET).
///
/// Web feed display uses storage transforms when available and **falls back to this
/// original object URL**. Feed/detail should request `maxPixelSize: nil` so native
/// renders the same bytes — longest-edge client downsampling under-fills portrait
/// width on 3× screens and SwiftUI upscales → blur.
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
        if ImageFidelityTrace.isEnabled {
            let before = ImageFidelityTrace.pixelSize(of: raw)
            let after = ImageFidelityTrace.pixelSize(of: data)
            ImageFidelityTrace.log(
                ImageFidelityTrace.StageReport(
                    stage: "pipeline/after-downsample",
                    url: request.reference.id,
                    byteCount: data.count,
                    pixelSize: after,
                    resizingNote: request.maxPixelSize.map { "maxPixelSize=\($0)" } ?? "maxPixelSize=nil (passthrough)",
                    fidelityNote: {
                        guard let before, let after else { return nil }
                        if before == after { return "bytes unchanged vs download" }
                        return "CHANGED \(before.label) → \(after.label)"
                    }()
                )
            )
        }
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
            let status = (response as? HTTPURLResponse)?.statusCode
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw AppError.network(.server(statusCode: http.statusCode, message: nil))
            }
            if ImageFidelityTrace.isEnabled {
                ImageFidelityTrace.log(
                    ImageFidelityTrace.StageReport(
                        stage: "pipeline/http-response",
                        url: url.absoluteString,
                        httpStatus: status,
                        byteCount: data.count,
                        pixelSize: ImageFidelityTrace.pixelSize(of: data),
                        resizingNote: "raw bytes before downsampleIfNeeded"
                    )
                )
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

    /// ImageIO downsample for **list thumbnails only** (avatars, 96pt cards).
    ///
    /// Feed/detail pass `maxPixelSize: nil` and receive original object bytes.
    /// When a budget is set, it is treated as a **minimum width-or-height floor for the
    /// displayed axis**: we size so neither edge of the decoded bitmap is smaller than
    /// `maxPixelSize` after aspect-fit (avoids portrait under-width → SwiftUI upscale blur).
    private static func downsampleIfNeeded(_ data: Data, maxPixelSize: Int?) -> Data {
        guard let maxPixelSize, maxPixelSize > 0 else { return data }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return data }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixelWidth = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let pixelHeight = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard pixelWidth > 0, pixelHeight > 0 else { return data }

        // Longest-edge target that keeps *both* edges ≥ maxPixelSize when possible.
        // Portrait 3:4 needing width ≥ W requires longest(height) ≥ W × 4/3.
        let aspect = Double(pixelWidth) / Double(pixelHeight)
        let longestNeeded: Int = {
            if aspect >= 1 {
                // Landscape — width is longest.
                return maxPixelSize
            } else {
                // Portrait — height is longest; size height so width == maxPixelSize.
                return Int((Double(maxPixelSize) / aspect).rounded(.up))
            }
        }()

        let longestEdge = max(pixelWidth, pixelHeight)
        if longestEdge <= longestNeeded {
            return data
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longestNeeded,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return data
        }

        let sourceType = CGImageSourceGetType(source) as String?
        let preferJPEG = sourceType == "public.jpeg" || sourceType == "public.heic" || sourceType == "public.heif"
        let uti: CFString = preferJPEG ? "public.jpeg" as CFString : "public.png" as CFString

        let mutable = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutable,
            uti,
            1,
            nil
        ) else {
            return data
        }
        var destinationOptions: [CFString: Any] = [:]
        if preferJPEG {
            destinationOptions[kCGImageDestinationLossyCompressionQuality] = 0.95
        }
        CGImageDestinationAddImage(destination, cgImage, destinationOptions as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return data }
        return mutable as Data
    }
}

extension ImagePurpose: CaseIterable {
    nonisolated static var allCases: [ImagePurpose] {
        [.profileAvatar, .tradeScreenshot, .postImage, .storyMedia, .reelThumbnail]
    }
}
