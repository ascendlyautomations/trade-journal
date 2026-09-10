import Foundation
import ImageIO

/// Production image pipeline: memory cache → Supabase render URL (feed) or original → optional downsample.
///
/// Feed surfaces use `/storage/v1/render/image/public/` transforms (web parity).
/// Detail/zoom passes `deliveryQuality: .fullResolution` for original object bytes.
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
            #if DEBUG
            let mediaID = request.reference.id.split(separator: "/").last.map(String.init)
                ?? request.reference.id
            MediaLoadDiagnostics.log(
                contentType: "image/\(request.purpose.rawValue)",
                mediaID: String(mediaID.prefix(48)),
                source: .feedImage,
                role: .image,
                cacheHit: true
            )
            logFetchAudit(request: request, cacheKey: key, cacheHit: true, data: cached)
            #endif
            return cached
        }

        let raw = try await fetch(
            request: request,
            cacheKey: key,
            cacheHit: false
        )
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

    func cachedImageData(for request: ImageRequest) async -> Data? {
        await cache.imageData(forKey: cacheKey(for: request))
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
        "\(request.reference.id)|\(request.purpose.rawValue)|\(request.deliveryQuality.rawValue)|\(request.maxPixelSize ?? 0)"
    }

    private func fetch(
        request: ImageRequest,
        cacheKey: String,
        cacheHit: Bool
    ) async throws -> Data {
        let reference = request.reference
        let purpose = request.purpose
        let deliveryQuality = request.deliveryQuality
        let identifier = reference.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else {
            throw AppError.network(.validation(statusCode: nil, message: "Empty media reference"))
        }

        // Prefer public URL resolution (web parity) for storage paths.
        if let url = MediaURLResolver.url(
            for: reference,
            bucket: Self.storageBucket(for: purpose),
            storage: storage
        ) {
            let preset = StorageImageTransform.preset(for: purpose, delivery: deliveryQuality)
            let fetchURL: URL
            if let preset {
                fetchURL = StorageImageTransform.optimizedURL(for: url, preset: preset)
            } else {
                fetchURL = url
            }

            do {
                let data = try await fetchURLWithTransientRetry(fetchURL, request: request)
                #if DEBUG
                let mediaID = reference.id.split(separator: "/").last.map(String.init) ?? reference.id
                MediaLoadDiagnostics.log(
                    contentType: "image/\(purpose.rawValue)",
                    mediaID: String(mediaID.prefix(48)),
                    source: .feedImage,
                    role: .image,
                    urlIdentity: StorageImageTransform.urlIdentity(for: fetchURL),
                    byteCount: data.count,
                    cacheHit: false
                )
                logFetchAudit(
                    request: request,
                    cacheKey: cacheKey,
                    cacheHit: cacheHit,
                    data: data,
                    objectURL: url,
                    fetchURL: fetchURL.absoluteString,
                    preset: preset
                )
                #endif
                return data
            } catch {
                // Transform unavailable — fall back to original only on genuine transform failure.
                // Never fall back on cancellation (SwiftUI task teardown would double-fetch).
                if fetchURL != url, !Self.shouldSkipTransformFallback(for: error) {
                    let data = try await fetchURLWithTransientRetry(url, request: request)
                    #if DEBUG
                    logFetchAudit(
                        request: request,
                        cacheKey: cacheKey,
                        cacheHit: cacheHit,
                        data: data,
                        objectURL: url,
                        fetchURL: url.absoluteString,
                        preset: nil,
                        transformFallback: true
                    )
                    #endif
                    return data
                }
                throw error
            }
        }

        // Last resort — authenticated download (private buckets / unconfigured public URL).
        let data = try await downloadService.download(
            DownloadRequest(bucket: Self.storageBucket(for: purpose).rawValue, path: identifier)
        )
        #if DEBUG
        MediaEgressTracker.recordNetworkTransfer(
            type: MediaEgressTracker.mediaType(for: purpose),
            surface: MediaEgressTracker.surface(for: request),
            mediaID: request.auditMediaID,
            bytes: data.count
        )
        logFetchAudit(
            request: request,
            cacheKey: cacheKey,
            cacheHit: cacheHit,
            data: data,
            objectURL: nil,
            fetchURL: "download://\(Self.storageBucket(for: purpose).rawValue)/\(identifier)",
            preset: nil
        )
        #endif
        return data
    }

    #if DEBUG
    private func logFetchAudit(
        request: ImageRequest,
        cacheKey: String,
        cacheHit: Bool,
        data: Data,
        objectURL: URL? = nil,
        fetchURL: String? = nil,
        preset: StorageImageTransform.Preset? = nil,
        transformFallback: Bool = false
    ) {
        let encoded = MediaPipelineAudit.encodedPixelSize(of: data)
        let presetInfo = preset.map { MediaPipelineAudit.describePreset($0) }
        var params = presetInfo?.params
        if transformFallback {
            params = (params ?? "none") + " FALLBACK=originalObject"
        }
        MediaPipelineAudit.logFetch(
            MediaPipelineAudit.FetchReport(
                surface: request.auditSurface.isEmpty ? "unknown" : request.auditSurface,
                mediaID: request.auditMediaID,
                storageReference: request.reference.id,
                purpose: request.purpose.rawValue,
                deliveryQuality: request.deliveryQuality.rawValue,
                cacheKey: cacheKey,
                cacheHit: cacheHit,
                objectURL: objectURL?.absoluteString,
                fetchURL: fetchURL ?? objectURL?.absoluteString ?? request.reference.id,
                transformPreset: presetInfo?.name,
                transformParams: params,
                byteCount: data.count,
                encodedPixelWidth: encoded?.width,
                encodedPixelHeight: encoded?.height
            )
        )
    }
    #endif

    /// Short bounded retry for flaky cellular / brief outages (idempotent GET).
    private func fetchURLWithTransientRetry(_ url: URL, request: ImageRequest) async throws -> Data {
        let maximumAttempts = 3
        var lastError: Error?
        for attempt in 1...maximumAttempts {
            do {
                let (data, response) = try await urlSession.data(from: url)
                let status = (response as? HTTPURLResponse)?.statusCode
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    let serverError = AppError.network(.server(statusCode: http.statusCode, message: nil))
                    if (500..<600).contains(http.statusCode), attempt < maximumAttempts {
                        lastError = serverError
                        let delay = pow(2.0, Double(attempt - 1)) * 0.25
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    }
                    throw serverError
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
                #if DEBUG
                MediaEgressTracker.recordNetworkTransfer(
                    type: MediaEgressTracker.mediaType(for: request.purpose),
                    surface: MediaEgressTracker.surface(for: request),
                    mediaID: request.auditMediaID,
                    bytes: data.count
                )
                #endif
                return data
            } catch let error as URLError where Self.isTransientURLError(error) {
                lastError = error
                guard attempt < maximumAttempts else { break }
                let delay = pow(2.0, Double(attempt - 1)) * 0.25
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        if let lastError {
            throw lastError
        }
        throw AppError.network(.connectivity)
    }

    private static func shouldSkipTransformFallback(for error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    private static func isTransientURLError(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut,
             .networkConnectionLost,
             .notConnectedToInternet,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .dataNotAllowed:
            return true
        default:
            return false
        }
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
