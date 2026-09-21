import Foundation
import ImageIO

/// Production image pipeline: memory → disk → network (with in-flight coalescing).
///
/// Feed surfaces use `/storage/v1/render/image/public/` transforms (web parity).
/// Detail uses `.feedDetail` (1280px) by default; `.fullResolution` for deep zoom.
nonisolated struct DefaultImagePipeline: ImagePipeline {
    private let cache: any ImageCaching
    private let tieredCache: TieredImageCache?
    private let storage: any ObjectStorageProviding
    private let downloadService: any DownloadService
    private let urlSession: URLSession
    private let coalescer: ImageLoadCoalescer

    private static let sharedCoalescer = ImageLoadCoalescer()

    init(
        cache: any ImageCaching,
        storage: any ObjectStorageProviding,
        downloadService: any DownloadService,
        urlSession: URLSession = MediaURLSession.shared,
        coalescer: ImageLoadCoalescer? = nil
    ) {
        self.cache = cache
        self.tieredCache = cache as? TieredImageCache
        self.storage = storage
        self.downloadService = downloadService
        self.urlSession = urlSession
        self.coalescer = coalescer ?? Self.sharedCoalescer
    }

    func data(for request: ImageRequest) async throws -> Data {
        let key = ImageCacheKey.make(for: request)
        if let cached = await cache.imageData(forKey: key) {
            #if DEBUG
            logCacheHit(request: request, cacheKey: key, data: cached, source: .memoryOrDisk)
            #endif
            return cached
        }

        #if DEBUG
        MediaEgressTracker.recordImageCacheMiss()
        #endif

        return try await coalescer.load(key: key) { [self] in
            if let raced = await cache.imageData(forKey: key) {
                return raced
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
            traceEvent(request, "disk.write.start")
            await cache.setImageData(data, forKey: key)
            traceEvent(request, "disk.write.end")
            return data
        }
    }

    func cachedImageData(for request: ImageRequest) async -> Data? {
        await cache.imageData(forKey: ImageCacheKey.make(for: request))
    }

    /// Best available cached bytes at or below the requested delivery tier (feed thumb before detail).
    func bestCachedImageData(for request: ImageRequest) async -> (data: Data, quality: ImageDeliveryQuality)? {
        if let resolved = await bestCachedImageDataWithTier(for: request) {
            return (resolved.data, resolved.quality)
        }
        return nil
    }

    func bestCachedImageDataWithTier(for request: ImageRequest) async -> ImageCachedLookupResult? {
        let order = Self.cacheQualityOrder(for: request.deliveryQuality)
        traceEvent(request, "memory.lookup.start")
        for quality in order {
            var candidate = request
            candidate.deliveryQuality = quality
            let key = ImageCacheKey.make(for: candidate)
            if let data = await tieredCache?.memoryImageData(forKey: key) {
                traceEvent(request, "memory.lookup.end", detail: "hit \(quality.rawValue)")
                traceEvent(request, "cache.hit.memory", detail: quality.rawValue)
                return ImageCachedLookupResult(data: data, quality: quality, tier: .memory)
            }
            if tieredCache == nil, let data = await cache.imageData(forKey: key) {
                traceEvent(request, "memory.lookup.end", detail: "hit \(quality.rawValue)")
                traceEvent(request, "cache.hit.memory", detail: quality.rawValue)
                return ImageCachedLookupResult(data: data, quality: quality, tier: .memory)
            }
        }
        traceEvent(request, "memory.lookup.end", detail: "miss")

        if tieredCache != nil {
            traceEvent(request, "disk.lookup.start")
            for quality in order {
                var candidate = request
                candidate.deliveryQuality = quality
                let key = ImageCacheKey.make(for: candidate)
                if let data = await tieredCache?.diskImageDataPromotingToMemory(forKey: key) {
                    traceEvent(request, "disk.lookup.end", detail: "hit \(quality.rawValue)")
                    traceEvent(request, "cache.hit.disk", detail: quality.rawValue)
                    return ImageCachedLookupResult(data: data, quality: quality, tier: .disk)
                }
            }
            traceEvent(request, "disk.lookup.end", detail: "miss")
        }

        traceEvent(request, "cache.miss")
        return nil
    }

    func warmCachedImages(for requests: [ImageRequest]) async {
        for request in requests {
            if Task.isCancelled { break }
            _ = await bestCachedImageDataWithTier(for: request)
        }
    }

    func prefetch(_ requests: [ImageRequest]) async {
        for request in requests {
            if Task.isCancelled { break }
            if await cachedImageData(for: request) != nil { continue }
            _ = try? await data(for: request)
        }
    }

    func invalidate(reference: MediaReference) async {
        for purpose in ImagePurpose.allCases {
            for quality in [ImageDeliveryQuality.feedDisplay, .profileGrid, .feedDetail, .fullResolution] {
                let key = "\(reference.id)|\(purpose.rawValue)|\(quality.rawValue)|0"
                await cache.removeImage(forKey: key)
                let feedKey = key + "|feedRev=\(StorageImageTransform.feedDisplayCacheRevision)"
                await cache.removeImage(forKey: feedKey)
            }
        }
    }

    // MARK: - Private

    private static func cacheQualityOrder(for deliveryQuality: ImageDeliveryQuality) -> [ImageDeliveryQuality] {
        switch deliveryQuality {
        case .fullResolution:
            return [.fullResolution, .feedDetail, .feedDisplay]
        case .feedDetail:
            return [.feedDetail, .feedDisplay, .profileGrid]
        case .feedDisplay:
            return [.feedDisplay, .profileGrid]
        case .profileGrid:
            return [.profileGrid]
        }
    }

    private func traceEvent(_ request: ImageRequest, _ name: String, detail: String? = nil) {
        guard let id = request.imageTraceCorrelationID else { return }
        FeedImageTimingTrace.event(id, name, detail: detail)
    }

    private func traceComplete(_ request: ImageRequest) {
        guard let id = request.imageTraceCorrelationID else { return }
        FeedImageTimingTrace.complete(id)
    }

    private func traceFailed(_ request: ImageRequest, message: String) {
        guard let id = request.imageTraceCorrelationID else { return }
        FeedImageTimingTrace.failed(id, message: message)
    }

    private func traceCancelled(_ request: ImageRequest) {
        guard let id = request.imageTraceCorrelationID else { return }
        FeedImageTimingTrace.cancelled(id)
    }

    private enum CacheHitSource {
        case memoryOrDisk
    }

    #if DEBUG
    private func logCacheHit(
        request: ImageRequest,
        cacheKey: String,
        data: Data,
        source: CacheHitSource
    ) {
        _ = source
        let mediaID = request.reference.id.split(separator: "/").last.map(String.init)
            ?? request.reference.id
        MediaLoadDiagnostics.log(
            contentType: "image/\(request.purpose.rawValue)",
            mediaID: String(mediaID.prefix(48)),
            source: .feedImage,
            role: .image,
            cacheHit: true
        )
        logFetchAudit(request: request, cacheKey: cacheKey, cacheHit: true, data: data)
    }
    #endif

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
                tieredCache?.markDiskEligible(key: cacheKey)
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

    private func fetchURLWithTransientRetry(_ url: URL, request: ImageRequest) async throws -> Data {
        let maximumAttempts = 3
        var lastError: Error?
        let usesFeedVisibleCap = FeedVisibleImageFetchPolicy.requiresVisibleFetchSlot(for: request)
        for attempt in 1...maximumAttempts {
            var holdsFeedVisibleSlot = false
            do {
                if usesFeedVisibleCap {
                    traceEvent(request, "coordinator.queued", detail: "feedVisibleFetchSlot")
                    try await FeedVisibleImageFetchLimiter.shared.acquireFeedVisibleFetchSlot()
                    holdsFeedVisibleSlot = true
                    traceEvent(request, "coordinator.acquired", detail: "feedVisibleFetchSlot")
                }

                let host = url.host ?? "storage"
                let schedulingPriority: NetworkSchedulingPriority =
                    request.isSpeculativePrefetch ? .background : .visible
                traceEvent(request, "http.started", detail: url.path)
                let httpStarted = CFAbsoluteTimeGetCurrent()
                let (data, response, metrics) = try await NetworkConcurrencyCoordinator.shared.runWithSlot(
                    priority: schedulingPriority,
                    path: url.path,
                    host: host
                ) { [self] in
                    let urlRequest = URLRequest(url: url)
                    return try await urlSession.dataWithTaskMetrics(for: urlRequest)
                }
                if holdsFeedVisibleSlot {
                    await FeedVisibleImageFetchLimiter.shared.releaseFeedVisibleFetchSlot()
                    holdsFeedVisibleSlot = false
                }

                let status = (response as? HTTPURLResponse)?.statusCode
                if let transaction = metrics?.transactionMetrics.first,
                   let fetchStart = transaction.fetchStartDate,
                   let responseStart = transaction.responseStartDate
                {
                    let ms = responseStart.timeIntervalSince(fetchStart) * 1000
                    traceEvent(request, "http.firstByte", detail: String(format: "%.1fms", ms))
                }
                if let http = response as? HTTPURLResponse {
                    traceEvent(
                        request,
                        "http.headers",
                        detail: "status=\(http.statusCode)"
                    )
                }
                let elapsedMs = (CFAbsoluteTimeGetCurrent() - httpStarted) * 1000
                traceEvent(request, "http.completed", detail: String(format: "%.1fms bytes=\(data.count)", elapsedMs))

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
            } catch is CancellationError {
                if holdsFeedVisibleSlot {
                    await FeedVisibleImageFetchLimiter.shared.releaseFeedVisibleFetchSlot()
                }
                traceCancelled(request)
                throw CancellationError()
            } catch let error as URLError where Self.isTransientURLError(error) {
                if holdsFeedVisibleSlot {
                    await FeedVisibleImageFetchLimiter.shared.releaseFeedVisibleFetchSlot()
                    holdsFeedVisibleSlot = false
                }
                lastError = error
                guard attempt < maximumAttempts else { break }
                let delay = pow(2.0, Double(attempt - 1)) * 0.25
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                if holdsFeedVisibleSlot {
                    await FeedVisibleImageFetchLimiter.shared.releaseFeedVisibleFetchSlot()
                }
                traceFailed(request, message: String(describing: error))
                throw error
            }
        }
        if let lastError {
            traceFailed(request, message: String(describing: lastError))
            throw lastError
        }
        traceFailed(request, message: "connectivity")
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

    private static func downsampleIfNeeded(_ data: Data, maxPixelSize: Int?) -> Data {
        guard let maxPixelSize, maxPixelSize > 0 else { return data }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return data }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixelWidth = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let pixelHeight = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard pixelWidth > 0, pixelHeight > 0 else { return data }

        let aspect = Double(pixelWidth) / Double(pixelHeight)
        let longestNeeded: Int = {
            if aspect >= 1 {
                return maxPixelSize
            } else {
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
